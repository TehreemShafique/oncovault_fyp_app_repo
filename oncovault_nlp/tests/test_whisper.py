import io
import wave
import struct
import math
import pytest
from fastapi.testclient import TestClient
from main import app
from transcription.whisper_service import WhisperService

client = TestClient(app)

def create_synthetic_wav(duration_s: float = 1.0, freq_hz: float = 440.0) -> bytes:
    sample_rate = 16000
    num_samples = int(duration_s * sample_rate)
    buf = io.BytesIO()
    with wave.open(buf, "wb") as wav_file:
        wav_file.setnchannels(1)  # Mono
        wav_file.setsampwidth(2)  # 16-bit
        wav_file.setframerate(sample_rate)
        for i in range(num_samples):
            value = int(32767.0 * 0.5 * math.sin(2.0 * math.pi * freq_hz * (i / sample_rate)))
            data = struct.pack("<h", value)
            wav_file.writeframesraw(data)
    return buf.getvalue()

def test_whisper_service_initialization():
    service = WhisperService.get_instance()
    assert service.model is not None
    assert service.model_size in ["base.en", "small.en", "tiny.en"]

def test_transcribe_empty_file():
    empty_bytes = b"tiny"
    response = client.post(
        "/transcribe",
        files={"audio": ("empty.wav", empty_bytes, "audio/wav")},
        headers={"Authorization": "Bearer test_doctor_token"},
    )
    assert response.status_code == 400

def test_transcribe_invalid_format():
    response = client.post(
        "/transcribe",
        files={"audio": ("document.pdf", b"fake pdf content header that is longer than 100 bytes" * 5, "application/pdf")},
        headers={"Authorization": "Bearer test_doctor_token"},
    )
    assert response.status_code == 400
    assert "Unsupported audio format" in response.json()["detail"]

def test_transcribe_synthetic_audio():
    wav_bytes = create_synthetic_wav(duration_s=1.5, freq_hz=300.0)
    response = client.post(
        "/transcribe",
        files={"audio": ("sample_clip.wav", wav_bytes, "audio/wav")},
        headers={"Authorization": "Bearer test_doctor_token"},
    )
    assert response.status_code == 200
    data = response.json()
    assert data["success"] is True
    assert "transcript" in data
    assert data["language"] == "en"
