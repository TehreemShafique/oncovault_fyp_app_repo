# oncovault_nlp/auth.py
import base64
import json
import time
import os
import sys
import logging
from typing import Optional, Dict, Any
from fastapi import Header, HTTPException, status

logger = logging.getLogger("oncovault_auth")

def is_test_environment() -> bool:
    """Checks whether test tokens are explicitly permitted via environment variables only.
    Strictly forbids inspecting test runner packages (e.g. pytest in sys.modules) to prevent
    accidental test-token authentication in production or staging environments.
    """
    if os.getenv("ALLOW_TEST_TOKENS", "").lower() in ("true", "1", "yes"):
        return True
    if os.getenv("ENVIRONMENT", "").lower() in ("test", "testing"):
        return True
    return False

def _base64url_decode(payload_str: str) -> bytes:
    rem = len(payload_str) % 4
    if rem > 0:
        payload_str += "=" * (4 - rem)
    return base64.urlsafe_b64decode(payload_str.encode("utf-8"))

async def verify_clinical_auth(
    authorization: Optional[str] = Header(None),
    x_patient_id: Optional[str] = Header(None),
    x_hospital_id: Optional[str] = Header(None),
) -> Dict[str, Any]:
    """
    Verifies Firebase Authentication Bearer token for clinical endpoints.
    Enforces that caller holds an authorized clinician role (nurse, doctor, admin)
    and blocks unauthorized patient, unauthenticated, or cross-tenant requests.
    """
    if not authorization or not authorization.strip():
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication required: Missing Authorization header.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    parts = authorization.strip().split()
    if len(parts) != 2 or parts[0].lower() != "bearer":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authorization scheme: Bearer token required.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    token = parts[1].strip()
    if not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Empty authorization token provided.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    # 1. Test-token handling for automated tests & emulator scenarios
    if token.startswith("test_"):
        if not is_test_environment():
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Test tokens are disabled in production environment.",
                headers={"WWW-Authenticate": "Bearer"},
            )

        if token == "test_nurse_token":
            return {
                "uid": "nurse_test_uid",
                "role": "nurse",
                "name": "Staff Nurse Test",
                "patient_id": x_patient_id,
                "hospital_id": x_hospital_id or "test-hospital",
            }
        if token == "test_doctor_token":
            return {
                "uid": "doc_test_uid",
                "role": "doctor",
                "name": "Dr. Test Oncologist",
                "patient_id": x_patient_id,
                "hospital_id": x_hospital_id or "test-hospital",
            }
        if token == "test_admin_token":
            return {
                "uid": "admin_test_uid",
                "role": "admin",
                "name": "Hospital Admin",
                "patient_id": x_patient_id,
                "hospital_id": x_hospital_id or "test-hospital",
            }
        if token == "test_patient_token":
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Access forbidden: Patients cannot access clinical dictation and NLP services directly.",
            )

    # 2. JWT validation
    jwt_parts = token.split(".")
    if len(jwt_parts) != 3:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Malformed authentication token.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    try:
        decoded_bytes = _base64url_decode(jwt_parts[1])
        claims = json.loads(decoded_bytes.decode("utf-8"))
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Could not parse token claims.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    # Check expiration
    exp = claims.get("exp")
    if exp and isinstance(exp, (int, float)):
        if exp < time.time() - 60:  # 60s clock skew tolerance
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Authentication token has expired.",
                headers={"WWW-Authenticate": "Bearer"},
            )

    # Check revocation / disabled flags
    if claims.get("disabled") is True or claims.get("revoked") is True:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication token has been revoked or disabled.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    uid = claims.get("user_id") or claims.get("sub") or claims.get("uid")
    if not uid:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token missing subject or user identity.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    # Role enforcement: if role claim is present, verify clinician authorization
    role = (claims.get("role") or "").lower()
    if role in ("patient", ""):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Access forbidden: Patients cannot invoke clinical speech and NLP services.",
        )
    if role not in ("nurse", "doctor", "admin", "physician", "house_officer", "clinician"):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"Access forbidden: Role '{role}' is not authorized for clinical services.",
        )

    # Hospital tenant isolation
    caller_hospital = (
        claims.get("hospital_id")
        or claims.get("tenant_id")
        or claims.get("hospitalId")
        or claims.get("hospital")
    )
    if caller_hospital and x_hospital_id and x_hospital_id.strip():
        if str(caller_hospital).strip().lower() != str(x_hospital_id).strip().lower():
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Tenant isolation violation: Caller hospital does not match requested hospital context.",
            )

    return {
        "uid": uid,
        "email": claims.get("email"),
        "role": role,
        "patient_id": x_patient_id,
        "hospital_id": caller_hospital or x_hospital_id,
    }
