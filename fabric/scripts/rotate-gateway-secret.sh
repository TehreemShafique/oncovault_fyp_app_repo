#!/usr/bin/env bash
set -e

# ==============================================================================
# OncoVault — Fabric CA Gateway Secret Rotation Script
# Securely rotates/invalidates the enrollment secret of oncovault-gateway in ca-org1
# without invalidating issued X.509 certificates or exposing secrets in console.
# ==============================================================================

cd /home/oncovault/oncovault-fabric/fabric-samples/test-network
export PATH="/home/oncovault/oncovault-fabric/fabric-samples/bin:$PATH"
export FABRIC_CA_CLIENT_HOME="${PWD}/organizations/peerOrganizations/org1.example.com/"

CA_CERT="${PWD}/organizations/fabric-ca/org1/ca-cert.pem"

if [ ! -f "$CA_CERT" ]; then
    echo "[-] Error: CA certificate not found at $CA_CERT" >&2
    exit 1
fi

# Obtain new secret securely: environment variable, file, or generated cryptographically
NEW_SECRET=""
if [ -n "$GATEWAY_NEW_SECRET" ]; then
    NEW_SECRET="$GATEWAY_NEW_SECRET"
elif [ -n "$1" ] && [ -f "$1" ]; then
    NEW_SECRET=$(cat "$1" | tr -d '\r\n')
else
    # Cryptographically secure random 256-bit secret
    NEW_SECRET=$(openssl rand -hex 32)
fi

if [ -z "$NEW_SECRET" ]; then
    echo "[-] Error: Failed to generate or read new secret." >&2
    exit 1
fi

echo "=== Rotating Fabric CA Enrollment Secret for 'oncovault-gateway' ==="

# Execute identity modify to rotate secret in CA registry
fabric-ca-client identity modify oncovault-gateway \
    --secret "$NEW_SECRET" \
    --caname ca-org1 \
    --tls.certfiles "$CA_CERT" > /dev/null 2>&1

MODIFY_STATUS=$?

# Zero out secret immediately from memory
unset NEW_SECRET
unset GATEWAY_NEW_SECRET

if [ $MODIFY_STATUS -ne 0 ]; then
    echo "[-] Error: Failed to modify identity 'oncovault-gateway' in ca-org1." >&2
    exit 1
fi

echo "[+] Success: Enrollment secret for 'oncovault-gateway' has been rotated in ca-org1."
echo "[+] The previous enrollment secret is now INVALID and cannot be used for enrollment."
echo "[+] Active X.509 certificate and private key remain valid and functional."
