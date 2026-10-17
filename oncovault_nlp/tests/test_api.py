import os
import pytest
import io
from fastapi.testclient import TestClient
from main import app

@pytest.fixture(autouse=True)
def enable_test_tokens(monkeypatch):
    """Enables test tokens explicitly via environment variable for tests."""
    monkeypatch.setenv("ALLOW_TEST_TOKENS", "true")
    monkeypatch.setenv("ENVIRONMENT", "test")

client = TestClient(app)

def test_health_endpoint_public():
    """Health check remains unauthenticated for monitoring/load balancers."""
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "online"

def test_extract_endpoint_unauthenticated_fails():
    """Extract endpoint rejects requests missing Authorization header with 401."""
    payload = {"text": "Patient has fever and fatigue."}
    response = client.post("/extract", json=payload)
    assert response.status_code == 401
    assert "Missing Authorization header" in response.json()["detail"]

def test_extract_endpoint_malformed_token_fails():
    """Extract endpoint rejects malformed tokens with 401."""
    payload = {"text": "Patient has fever and fatigue."}
    headers = {"Authorization": "Bearer invalid_malformed_token"}
    response = client.post("/extract", json=payload, headers=headers)
    assert response.status_code == 401

def test_extract_endpoint_patient_role_blocked():
    """Extract endpoint rejects non-clinicians (patients) with 403."""
    payload = {"text": "Patient has fever and fatigue."}
    headers = {"Authorization": "Bearer test_patient_token"}
    response = client.post("/extract", json=payload, headers=headers)
    assert response.status_code == 403
    assert "Patients cannot access clinical dictation" in response.json()["detail"]

def test_extract_endpoint_nurse_authorized():
    """Extract endpoint processes clinical text for authenticated nurses."""
    payload = {"text": "Patient has persistent fatigue and fever but denies bone pain. WBC is 14.5 k/uL."}
    headers = {"Authorization": "Bearer test_nurse_token"}
    response = client.post("/extract", json=payload, headers=headers)
    assert response.status_code == 200
    data = response.json()
    assert "symptoms" in data
    assert data["symptoms"]["persistentWeaknessAndFatigue"]["value"] is True
    assert data["symptoms"]["bonePain"]["value"] is False
    assert data["cbc"]["wbc"]["value"] == 14.5

def test_extract_endpoint_doctor_authorized():
    """Extract endpoint processes clinical text for authenticated doctors."""
    payload = {"text": "Platelets are 45 k/uL. Petechiae present on lower limbs."}
    headers = {"Authorization": "Bearer test_doctor_token"}
    response = client.post("/extract", json=payload, headers=headers)
    assert response.status_code == 200
    data = response.json()
    assert "symptoms" in data
    assert data["symptoms"]["significantBruisingOrBleeding"]["value"] is True
    assert data["cbc"]["platelets"]["value"] == 45.0

def test_transcribe_unauthenticated_fails():
    """Transcribe rejects unauthenticated requests."""
    fake_audio = io.BytesIO(b"RIFF....WAVEfmt ....data....")
    response = client.post(
        "/transcribe",
        files={"audio": ("test.wav", fake_audio, "audio/wav")}
    )
    assert response.status_code == 401

def test_transcribe_patient_role_blocked():
    """Transcribe rejects patient role with 403."""
    fake_audio = io.BytesIO(b"RIFF....WAVEfmt ....data....")
    headers = {"Authorization": "Bearer test_patient_token"}
    response = client.post(
        "/transcribe",
        files={"audio": ("test.wav", fake_audio, "audio/wav")},
        headers=headers,
    )
    assert response.status_code == 403

def make_jwt(payload: dict) -> str:
    import base64
    import json
    header = base64.urlsafe_b64encode(json.dumps({"alg": "none", "typ": "JWT"}).encode()).decode().rstrip("=")
    body = base64.urlsafe_b64encode(json.dumps(payload).encode()).decode().rstrip("=")
    return f"{header}.{body}.mock_signature"

def test_jwt_expired_fails():
    """Rejects expired JWT tokens with 401."""
    import time
    token = make_jwt({"sub": "user_123", "role": "nurse", "exp": time.time() - 3600})
    response = client.post("/extract", json={"text": "fever"}, headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 401
    assert "expired" in response.json()["detail"].lower()

def test_jwt_revoked_fails():
    """Rejects revoked JWT tokens with 401."""
    import time
    token = make_jwt({"sub": "user_123", "role": "nurse", "exp": time.time() + 3600, "revoked": True})
    response = client.post("/extract", json={"text": "fever"}, headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 401
    assert "revoked" in response.json()["detail"].lower()

def test_jwt_patient_role_forbidden():
    """Rejects JWT tokens containing patient role with 403."""
    import time
    token = make_jwt({"sub": "patient_123", "role": "patient", "exp": time.time() + 3600})
    response = client.post("/extract", json={"text": "fever"}, headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 403

def test_jwt_tenant_isolation_mismatch_fails():
    """Rejects cross-hospital access when caller hospital doesn't match header context."""
    import time
    token = make_jwt({"sub": "nurse_123", "role": "nurse", "hospital_id": "hospital-A", "exp": time.time() + 3600})
    headers = {"Authorization": f"Bearer {token}", "X-Hospital-Id": "hospital-B"}
    response = client.post("/extract", json={"text": "fever"}, headers=headers)
    assert response.status_code == 403
    assert "tenant isolation" in response.json()["detail"].lower()

def test_jwt_tenant_isolation_match_succeeds():
    """Allows access when caller hospital matches requested hospital context."""
    import time
    token = make_jwt({"sub": "nurse_123", "role": "nurse", "hospital_id": "hospital-A", "exp": time.time() + 3600})
    headers = {"Authorization": f"Bearer {token}", "X-Hospital-Id": "hospital-A"}
    response = client.post("/extract", json={"text": "Patient has fever."}, headers=headers)
    assert response.status_code == 200

def test_audio_oversize_fails():
    """Rejects audio payloads exceeding 25 MB limit with 413."""
    huge_audio = io.BytesIO(b"RIFF" + b"0" * (25 * 1024 * 1024 + 100))
    headers = {"Authorization": "Bearer test_nurse_token"}
    response = client.post(
        "/transcribe",
        files={"audio": ("test.wav", huge_audio, "audio/wav")},
        headers=headers,
    )
    assert response.status_code == 413
    assert "25 MB" in response.json()["detail"]

def test_unsupported_audio_format_fails():
    """Rejects unsupported audio extensions with 400."""
    bad_audio = io.BytesIO(b"dummy text file content")
    headers = {"Authorization": "Bearer test_nurse_token"}
    response = client.post(
        "/transcribe",
        files={"audio": ("test.txt", bad_audio, "text/plain")},
        headers=headers,
    )
    assert response.status_code == 400
    assert "Unsupported audio format" in response.json()["detail"]

def test_test_tokens_rejected_in_production_environment(monkeypatch):
    """Verifies that test tokens are rejected with 401 when environment variables do not allow them,
    proving sys.modules / pytest presence alone does not grant access."""
    monkeypatch.setenv("ALLOW_TEST_TOKENS", "false")
    monkeypatch.setenv("ENVIRONMENT", "production")
    payload = {"text": "Patient has persistent fatigue."}
    headers = {"Authorization": "Bearer test_nurse_token"}
    response = client.post("/extract", json=payload, headers=headers)
    assert response.status_code == 401
    assert "Test tokens are disabled" in response.json()["detail"]
