#!/usr/bin/env bash
set -e

# ==============================================================================
# OncoVault — Dedicated Fabric Gateway Identity Enrollment Script
# Registers and enrolls 'oncovault-gateway' against ca-org1 with strict security.
# - Idempotent: Skips re-enrollment if valid certificate exists (preserves active certs)
# - No hardcoded secrets: Accepts secret via environment, file, or generates securely
# - Enforces restrictive permissions (0700 dir, 0600 key)
# - Never displays secrets or private keys
# ==============================================================================

cd /home/oncovault/oncovault-fabric/fabric-samples/test-network
export PATH="/home/oncovault/oncovault-fabric/fabric-samples/bin:$PATH"
export FABRIC_CA_CLIENT_HOME="${PWD}/organizations/peerOrganizations/org1.example.com/"

CA_CERT="${PWD}/organizations/fabric-ca/org1/ca-cert.pem"
TARGET_DIR="${PWD}/organizations/peerOrganizations/org1.example.com/users/oncovault-gateway@org1.example.com"
MSP_DIR="${TARGET_DIR}/msp"

FORCE_RE_ENROLL=false
SECRET_FILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --force)
            FORCE_RE_ENROLL=true
            shift
            ;;
        --secret-file)
            SECRET_FILE="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

# --- Helper: Verify and Enforce Permissions ---
enforce_permissions() {
    chmod 700 "$TARGET_DIR" 2>/dev/null || true
    chmod 700 "$MSP_DIR" 2>/dev/null || true
    chmod 700 "${MSP_DIR}/keystore" 2>/dev/null || true
    chmod 700 "${MSP_DIR}/signcerts" 2>/dev/null || true
    if compgen -G "${MSP_DIR}/keystore/*" > /dev/null; then
        chmod 600 "${MSP_DIR}/keystore/"*
    fi
    if compgen -G "${MSP_DIR}/signcerts/*" > /dev/null; then
        chmod 644 "${MSP_DIR}/signcerts/"*
    fi
    if [ -f "${MSP_DIR}/config.yaml" ]; then
        chmod 644 "${MSP_DIR}/config.yaml"
    fi
}

# --- 1. Idempotency Check: Existing Valid Certificate ---
if [ "$FORCE_RE_ENROLL" != "true" ] && [ -d "${MSP_DIR}/signcerts" ] && [ -d "${MSP_DIR}/keystore" ]; then
    EXISTING_CERT=$(ls "${MSP_DIR}/signcerts/"*.pem 2>/dev/null | head -n 1)
    if [ -n "$EXISTING_CERT" ] && [ -f "$EXISTING_CERT" ]; then
        if openssl x509 -checkend 0 -noout -in "$EXISTING_CERT" > /dev/null 2>&1; then
            echo "=== Active OncoVault Gateway Identity Found ==="
            enforce_permissions
            echo "[+] Valid, unexpired certificate exists. Skipping re-enrollment to preserve active identity."
            echo "[+] Directory: $TARGET_DIR"
            echo "Certificate Subject:"
            openssl x509 -in "$EXISTING_CERT" -noout -subject
            echo "Certificate Issuer:"
            openssl x509 -in "$EXISTING_CERT" -noout -issuer
            echo "Fabric CA Extension Attributes:"
            openssl x509 -in "$EXISTING_CERT" -noout -text | grep -A 2 "1.2.3.4.5.6.7.8.1"
            echo "[+] Pass --force to override and perform a fresh enrollment."
            exit 0
        fi
    fi
fi

echo "=== Registering and Enrolling oncovault-gateway identity ==="

# --- 2. Ingest or Generate Secret Securely ---
ENROLL_SECRET=""
if [ -n "$GATEWAY_ENROLLMENT_SECRET" ]; then
    ENROLL_SECRET="$GATEWAY_ENROLLMENT_SECRET"
elif [ -n "$SECRET_FILE" ] && [ -f "$SECRET_FILE" ]; then
    ENROLL_SECRET=$(cat "$SECRET_FILE" | tr -d '\r\n')
else
    # Cryptographically secure random 256-bit secret for fresh registration
    ENROLL_SECRET=$(openssl rand -hex 32)
fi

if [ -z "$ENROLL_SECRET" ]; then
    echo "[-] Error: Failed to obtain enrollment secret." >&2
    exit 1
fi

# --- 3. Register Identity with ca-org1 (if not already registered) ---
set +e
REGISTER_OUT=$(fabric-ca-client register \
    --caname ca-org1 \
    --id.name oncovault-gateway \
    --id.secret "$ENROLL_SECRET" \
    --id.type client \
    --tls.certfiles "$CA_CERT" 2>&1)
REG_EXIT=$?
set -e

if [ $REG_EXIT -ne 0 ]; then
    if [[ "$REGISTER_OUT" == *"is already registered"* ]]; then
        echo "[+] Identity 'oncovault-gateway' is already registered with ca-org1."
    else
        echo "[-] Registration error: $REGISTER_OUT" >&2
        unset ENROLL_SECRET
        unset GATEWAY_ENROLLMENT_SECRET
        exit 1
    fi
else
    echo "[+] Identity 'oncovault-gateway' registered successfully."
fi

# --- 4. Enroll into secure target directory outside Git ---
mkdir -p "$MSP_DIR"
fabric-ca-client enroll \
    -u "https://oncovault-gateway:${ENROLL_SECRET}@localhost:7054" \
    --caname ca-org1 \
    -M "$MSP_DIR" \
    --tls.certfiles "$CA_CERT" > /dev/null 2>&1
ENROLL_EXIT=$?

# Zero out secret immediately from memory
unset ENROLL_SECRET
unset GATEWAY_ENROLLMENT_SECRET

if [ $ENROLL_EXIT -ne 0 ]; then
    echo "[-] Enrollment failed. If identity was already registered with a rotated secret, provide it via GATEWAY_ENROLLMENT_SECRET or --secret-file." >&2
    exit 1
fi

# Copy NodeOU configuration
cp "${PWD}/organizations/peerOrganizations/org1.example.com/msp/config.yaml" "${MSP_DIR}/config.yaml"

# Enforce restrictive permissions
enforce_permissions

echo "=== Enrollment Complete with Restrictive Permissions ==="

# Inspect and verify attributes without exposing private keys
SIGN_CERT=$(ls "${MSP_DIR}/signcerts/"*.pem | head -n 1)
echo "Enrolled Certificate Subject:"
openssl x509 -in "$SIGN_CERT" -noout -subject
echo "Enrolled Certificate Issuer:"
openssl x509 -in "$SIGN_CERT" -noout -issuer
echo "Enrolled Fabric CA Extension:"
openssl x509 -in "$SIGN_CERT" -noout -text | grep -A 2 "1.2.3.4.5.6.7.8.1"
