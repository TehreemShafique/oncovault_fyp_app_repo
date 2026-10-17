import os
import tempfile
import logging
from fastapi import FastAPI, HTTPException, status, UploadFile, File, Depends
from fastapi.middleware.cors import CORSMiddleware
import uvicorn
import sys
# Ensure both oncovault_nlp and repository root are in sys.path
_nlp_dir = os.path.dirname(os.path.abspath(__file__))
_root_dir = os.path.abspath(os.path.join(_nlp_dir, ".."))
for p in [_nlp_dir, _root_dir]:
    if p not in sys.path:
        sys.path.insert(0, p)

from models.request_response import ExtractRequest, ExtractResponse
from nlp.pipeline import ClinicalNlpPipeline
from transcription.whisper_service import WhisperService
from auth import verify_clinical_auth

try:
    from oncovault_ai.api.diagnostic_router import router as diagnostic_router
except ImportError:
    diagnostic_router = None

logger = logging.getLogger("oncovault_api")

app = FastAPI(
    title="OncoVault Clinical NLP, Whisper & AI Diagnostic Engine",
    description="Speech-to-Text Whisper transcription, biomedical NLP concept extraction, and AI Clinical Decision Support Risk Models for OncoVault EHR.",
    version="3.0.0"
)

# CORS configuration to allow Flutter Web and mobile clients
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

if diagnostic_router:
    app.include_router(diagnostic_router)

pipeline = ClinicalNlpPipeline()

ALLOWED_AUDIO_EXTENSIONS = {".wav", ".m4a", ".mp3", ".webm", ".ogg", ".aac", ".flac"}

def detect_audio_extension(content: bytes, fallback_ext: str = ".webm") -> str:
    if content.startswith(b"RIFF"):
        return ".wav"
    if content.startswith(b"\x1a\x45\xdf\xa3"):
        return ".webm"
    if content.startswith(b"OggS"):
        return ".ogg"
    if content.startswith(b"ID3") or (len(content) > 2 and content[0] == 0xFF and (content[1] & 0xE0) == 0xE0):
        return ".mp3"
    if len(content) > 8 and (b"ftyp" in content[:12] or b"M4A " in content[:12]):
        return ".m4a"
    return fallback_ext

MAX_AUDIO_BYTES = 25 * 1024 * 1024  # 25 MB maximum recording limit

@app.get("/health", status_code=status.HTTP_200_OK)
def health_check():
    return {
        "status": "online",
        "service": "OncoVault Clinical NLP & Whisper Engine",
        "version": "2.0.0",
        "whisper_model": os.getenv("WHISPER_MODEL", "small.en")
    }

@app.post("/transcribe", status_code=status.HTTP_200_OK)
async def transcribe_audio(
    audio: UploadFile = File(...),
    auth_user: dict = Depends(verify_clinical_auth)
):
    if not audio.filename:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No audio file uploaded."
        )

    client_ext = os.path.splitext(audio.filename)[1].lower()
    if client_ext and client_ext not in ALLOWED_AUDIO_EXTENSIONS:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Unsupported audio format '{client_ext}'. Allowed formats: {', '.join(sorted(ALLOWED_AUDIO_EXTENSIONS))}"
        )

    content = await audio.read()
    if len(content) < 100:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Uploaded audio file is empty or too short."
        )

    if len(content) > MAX_AUDIO_BYTES:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail="Audio file exceeds maximum permitted limit (25 MB)."
        )

    actual_ext = detect_audio_extension(content, fallback_ext=client_ext or ".webm")

    # Save audio stream to temporary file safely with correct extension
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=actual_ext)
    temp_path = temp_file.name
    try:
        temp_file.write(content)
        temp_file.flush()
        temp_file.close()

        whisper_service = WhisperService.get_instance()
        result = whisper_service.transcribe(temp_path, language="en")
        # Explicitly flag that all automated transcriptions mandate clinician human review
        result["requires_human_review"] = True
        return result
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Speech transcription failed: {type(e).__name__}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Speech transcription failed: {str(e)}"
        )
    finally:
        # Guarantee cleanup of temporary audio files
        if os.path.exists(temp_path):
            try:
                os.remove(temp_path)
            except Exception:
                pass

@app.post("/extract", response_model=ExtractResponse, status_code=status.HTTP_200_OK)
def extract_clinical_concepts(
    req: ExtractRequest,
    auth_user: dict = Depends(verify_clinical_auth)
):
    if not req.text or not req.text.strip():
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Clinical text transcription cannot be empty."
        )
    try:
        response = pipeline.process(req.text)
        return response
    except Exception as e:
        logger.error(f"Clinical NLP processing error: {type(e).__name__}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Clinical NLP processing error: {str(e)}"
        )

if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
