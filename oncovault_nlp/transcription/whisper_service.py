import os
import io
import gc
import logging
from typing import Dict, Any, Optional
import av
import numpy as np
from faster_whisper import WhisperModel

logger = logging.getLogger("oncovault_whisper")

def decode_audio_resilient(audio_source: str, sampling_rate: int = 16000) -> np.ndarray:
    """
    Robust audio decoder using PyAV that handles AAC/M4A containers produced by mobile
    devices (e.g. Android MediaRecorder where packet 0 holds codec extradata which causes
    avcodec_send_packet to raise an InvalidDataError and prematurely terminate standard generators).
    """
    resampler = av.audio.resampler.AudioResampler(
        format="s16",
        layout="mono",
        rate=sampling_rate,
    )
    raw_buffer = io.BytesIO()
    dtype = None

    try:
        with av.open(audio_source, mode="r", metadata_errors="ignore") as container:
            audio_streams = [s for s in container.streams if s.type == "audio"]
            if not audio_streams:
                return np.array([], dtype=np.float32)

            stream = audio_streams[0]
            for packet in container.demux(stream):
                try:
                    frames = packet.decode()
                    for frame in frames:
                        for rf in resampler.resample(frame):
                            arr = rf.to_ndarray()
                            dtype = arr.dtype
                            raw_buffer.write(arr)
                except Exception:
                    # Safely skip non-audio or header packets (such as the initial extradata sample in Android AAC)
                    continue

            try:
                for rf in resampler.resample(None):
                    arr = rf.to_ndarray()
                    dtype = arr.dtype
                    raw_buffer.write(arr)
            except Exception:
                pass
    except Exception as e:
        logger.warning(f"PyAV demux decode error on {audio_source}: {e}")

    del resampler
    gc.collect()

    buf = raw_buffer.getbuffer()
    if buf.nbytes == 0:
        return np.array([], dtype=np.float32)

    audio = np.frombuffer(buf, dtype=dtype)
    return audio.astype(np.float32) / 32768.0

class WhisperService:
    _instance: Optional["WhisperService"] = None

    def __init__(self, model_size: Optional[str] = None, device: str = "cpu", compute_type: str = "int8"):
        self.model_size = model_size or os.getenv("WHISPER_MODEL", "small.en")
        self.device = device
        self.compute_type = compute_type
        self.model: Optional[WhisperModel] = None
        self._load_model()

    @classmethod
    def get_instance(cls) -> "WhisperService":
        if cls._instance is None:
            cls._instance = cls()
        return cls._instance

    def _load_model(self) -> None:
        try:
            logger.info(f"Loading Whisper model '{self.model_size}' on {self.device} ({self.compute_type})...")
            self.model = WhisperModel(
                self.model_size,
                device=self.device,
                compute_type=self.compute_type,
                cpu_threads=2,
            )
            logger.info(f"Whisper model '{self.model_size}' loaded successfully.")
        except Exception as e:
            logger.error(f"Failed to load Whisper model: {e}")
            self.model = None
            raise RuntimeError(f"Could not initialize Whisper speech-to-text engine: {e}")

    def transcribe(self, audio_path: str, language: str = "en") -> Dict[str, Any]:
        if not os.path.exists(audio_path):
            raise FileNotFoundError(f"Audio file not found at path: {audio_path}")

        file_size = os.path.getsize(audio_path)
        if file_size < 100:
            raise ValueError("Audio file is empty or corrupted (file size too small).")

        if self.model is None:
            self._load_model()

        try:
            audio = decode_audio_resilient(audio_path, sampling_rate=16000)
            if len(audio) == 0:
                try:
                    from faster_whisper.audio import decode_audio
                    audio = decode_audio(audio_path, sampling_rate=16000)
                except Exception:
                    pass

            if len(audio) == 0:
                logger.warning(f"Decoded audio from {audio_path} is empty.")
                return {
                    "success": True,
                    "transcript": "",
                    "language": language,
                    "language_probability": 0.0,
                    "duration": 0.0,
                    "model": self.model_size,
                }

            segments, info = self.model.transcribe(
                audio,
                language=language,
                beam_size=5,
                temperature=0.0,
                condition_on_previous_text=False,
                repetition_penalty=1.15,
                no_speech_threshold=0.6,
                vad_filter=True,
                vad_parameters=dict(min_silence_duration_ms=400, speech_pad_ms=300),
            )

            text_segments = [seg.text.strip() for seg in segments if seg.text.strip()]
            full_transcript = " ".join(text_segments).strip()

            duration = getattr(info, "duration", float(len(audio)) / 16000.0)
            if not full_transcript and duration >= 1.0:
                logger.info("VAD filter returned empty transcript on non-trivial audio. Retrying without VAD...")
                fallback_segments, _ = self.model.transcribe(
                    audio,
                    language=language,
                    beam_size=5,
                    temperature=0.0,
                    condition_on_previous_text=False,
                    repetition_penalty=1.15,
                    vad_filter=False,
                )
                text_segments = [seg.text.strip() for seg in fallback_segments if seg.text.strip()]
                full_transcript = " ".join(text_segments).strip()

            return {
                "success": True,
                "transcript": full_transcript,
                "language": info.language if info else language,
                "language_probability": getattr(info, "language_probability", 1.0),
                "duration": duration,
                "model": self.model_size,
            }
        except Exception as e:
            logger.error(f"Transcription error on file {audio_path}: {e}")
            raise RuntimeError(f"Whisper transcription failed: {str(e)}")
