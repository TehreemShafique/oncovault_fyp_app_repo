#!/usr/bin/env bash
set -e

cd /home/oncovault/oncovault-fabric/fabric-samples/test-network
export PATH="/home/oncovault/oncovault-fabric/fabric-samples/bin:$PATH"
export FABRIC_CFG_PATH=/home/oncovault/oncovault-fabric/fabric-samples/config

. scripts/envVar.sh

echo "================================================================="
echo "ONCOVAULT BATCH 2B.2: DEDICATED GATEWAY IDENTITY & SECURITY GATE"
echo "================================================================="

assert_contains() {
    local text="$1"
    local expected="$2"
    local message="$3"
    if [[ "$text" != *"$expected"* ]]; then
        echo "[-] ASSERTION FAILED: $message"
        echo "    Expected to find: '$expected'"
        echo "    Actual output: $text"
        exit 1
    fi
    echo "[+] ASSERTION PASSED: $message"
}

GATEWAY_MSP="/home/oncovault/oncovault-fabric/fabric-samples/test-network/organizations/peerOrganizations/org1.example.com/users/oncovault-gateway@org1.example.com/msp"
ADMIN_MSP="/home/oncovault/oncovault-fabric/fabric-samples/test-network/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp"
USER1_MSP="/home/oncovault/oncovault-fabric/fabric-samples/test-network/organizations/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp"

# Check that gateway MSP directory exists
if [ ! -d "$GATEWAY_MSP" ]; then
    echo "[-] ERROR: Gateway MSP directory does not exist: $GATEWAY_MSP"
    exit 1
fi

# --- 1. Confirm Committed Chaincode Definition (v1.2, seq 3) on Org1 & Org2 ---
echo ""
echo "--- 1. Querying Committed Chaincode Definition on Org1 and Org2 ---"
setGlobals 1
COMMITTED_ORG1=$(peer lifecycle chaincode querycommitted --channelID oncovault-channel --name oncovault)
echo "$COMMITTED_ORG1"
assert_contains "$COMMITTED_ORG1" "Version: 1.2" "Org1 has committed Version 1.2"
assert_contains "$COMMITTED_ORG1" "Approvals: [Org1MSP: true, Org2MSP: true]" "Org1 confirms dual-org approval"

setGlobals 2
COMMITTED_ORG2=$(peer lifecycle chaincode querycommitted --channelID oncovault-channel --name oncovault)
echo "$COMMITTED_ORG2"
assert_contains "$COMMITTED_ORG2" "Version: 1.2" "Org2 has committed Version 1.2"
assert_contains "$COMMITTED_ORG2" "Approvals: [Org1MSP: true, Org2MSP: true]" "Org2 confirms dual-org approval"

# --- 2. Record Anchoring Integrity Verification ---
echo ""
echo "--- 2. Record Anchoring Integrity Verification (Org1 Admin) ---"
setGlobals 1
RECORD_ID="rec-gate-$(date +%s)"
HASH_V1="5e884898da28047151d0e56f8dc6292773603d0d6aabbdd62a11ef721d1542d8"

INVOKE_RES=$(peer chaincode invoke -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com --tls --cafile "$ORDERER_CA" -C oncovault-channel -n oncovault --peerAddresses localhost:7051 --tlsRootCertFiles "$PEER0_ORG1_CA" --peerAddresses localhost:9051 --tlsRootCertFiles "$PEER0_ORG2_CA" --waitForEvent -c "{\"function\":\"AnchorRecordHash\",\"Args\":[\"$RECORD_ID\",\"$HASH_V1\",\"{\\\"documentType\\\":\\\"PATHOLOGY_PANEL\\\",\\\"schemaVersion\\\":\\\"1.0\\\",\\\"synthetic\\\":true}\"]}" 2>&1)
echo "$INVOKE_RES"
assert_contains "$INVOKE_RES" "status:200" "Anchor invoke returned status 200"
assert_contains "$INVOKE_RES" "committed with status (VALID) at localhost:7051" "Committed with VALID status on Org1 peer"
assert_contains "$INVOKE_RES" "committed with status (VALID) at localhost:9051" "Committed with VALID status on Org2 peer"

# Verify on Org2 peer
setGlobals 2
PROOF_ORG2=$(peer chaincode query -C oncovault-channel -n oncovault -c "{\"function\":\"GetRecordProof\",\"Args\":[\"$RECORD_ID\"]}")
echo "Org2 Peer Proof: $PROOF_ORG2"
assert_contains "$PROOF_ORG2" "\"recordId\":\"$RECORD_ID\"" "Proof found on Org2 peer"
assert_contains "$PROOF_ORG2" "\"sha256Hash\":\"$HASH_V1\"" "Org2 hash matches"

# Verify valid hash
VERIFY_RES=$(peer chaincode query -C oncovault-channel -n oncovault -c "{\"function\":\"VerifyRecordHash\",\"Args\":[\"$RECORD_ID\",\"$HASH_V1\"]}")
assert_contains "$VERIFY_RES" "\"verified\":true" "Hash verification succeeded"

# --- 3. Negative Test: org1admin CANNOT Grant Consent (Bypass Removed) ---
echo ""
echo "--- 3. Negative Test: org1admin CANNOT Grant Consent (Bypass Removed) ---"
setGlobals 1
export CORE_PEER_MSPCONFIGPATH="$ADMIN_MSP"

PAT_ID="pat-auth-$(date +%s)"
PROV_ID="prov-onc-center"
SCOPE="BLOOD_CANCER_RESEARCH"
EXPIRATION="2028-12-31T23:59:59Z"

set +e
ADMIN_GRANT_RES=$(peer chaincode invoke -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com --tls --cafile "$ORDERER_CA" -C oncovault-channel -n oncovault --peerAddresses localhost:7051 --tlsRootCertFiles "$PEER0_ORG1_CA" --peerAddresses localhost:9051 --tlsRootCertFiles "$PEER0_ORG2_CA" -c "{\"function\":\"GrantConsent\",\"Args\":[\"$PAT_ID\",\"$PROV_ID\",\"$SCOPE\",\"$EXPIRATION\"]}" 2>&1)
set -e
echo "$ADMIN_GRANT_RES"
assert_contains "$ADMIN_GRANT_RES" "Access Denied: Caller 'org1admin'" "org1admin is rejected fail-closed"
assert_contains "$ADMIN_GRANT_RES" "not an authorized OncoVault Gateway identity" "Rejection message confirms unauthorized identity"

# --- 4. Negative Test: user1 CANNOT Grant Consent ---
echo ""
echo "--- 4. Negative Test: Ordinary user1 CANNOT Grant Consent ---"
export CORE_PEER_MSPCONFIGPATH="$USER1_MSP"

set +e
USER1_GRANT_RES=$(peer chaincode invoke -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com --tls --cafile "$ORDERER_CA" -C oncovault-channel -n oncovault --peerAddresses localhost:7051 --tlsRootCertFiles "$PEER0_ORG1_CA" --peerAddresses localhost:9051 --tlsRootCertFiles "$PEER0_ORG2_CA" -c "{\"function\":\"GrantConsent\",\"Args\":[\"$PAT_ID\",\"$PROV_ID\",\"$SCOPE\",\"$EXPIRATION\"]}" 2>&1)
set -e
echo "$USER1_GRANT_RES"
assert_contains "$USER1_GRANT_RES" "Access Denied: Caller 'user1'" "user1 is rejected fail-closed"

# --- 5. Positive Test: Dedicated oncovault-gateway Grants Consent ---
echo ""
echo "--- 5. Positive Test: Dedicated oncovault-gateway Grants Consent ---"
export CORE_PEER_MSPCONFIGPATH="$GATEWAY_MSP"

GATEWAY_GRANT_RES=$(peer chaincode invoke -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com --tls --cafile "$ORDERER_CA" -C oncovault-channel -n oncovault --peerAddresses localhost:7051 --tlsRootCertFiles "$PEER0_ORG1_CA" --peerAddresses localhost:9051 --tlsRootCertFiles "$PEER0_ORG2_CA" --waitForEvent -c "{\"function\":\"GrantConsent\",\"Args\":[\"$PAT_ID\",\"$PROV_ID\",\"$SCOPE\",\"$EXPIRATION\"]}" 2>&1)
echo "$GATEWAY_GRANT_RES"
assert_contains "$GATEWAY_GRANT_RES" "status:200" "oncovault-gateway grant returned 200"
assert_contains "$GATEWAY_GRANT_RES" "committed with status (VALID) at localhost:7051" "Grant committed VALID on Org1"
assert_contains "$GATEWAY_GRANT_RES" "committed with status (VALID) at localhost:9051" "Grant committed VALID on Org2"
assert_contains "$GATEWAY_GRANT_RES" "gatewayEnrollmentId" "Recorded gateway identity in response"
assert_contains "$GATEWAY_GRANT_RES" "oncovault-gateway" "Gateway enrollment ID is oncovault-gateway"

sleep 1

# --- 6. Query Consent from Both Org1 and Org2 Peers ---
echo ""
echo "--- 6. Query Active Consent from Org1 and Org2 Peers ---"
setGlobals 1
CHECK_ACTIVE_ORG1=$(peer chaincode query -C oncovault-channel -n oncovault -c "{\"function\":\"CheckConsent\",\"Args\":[\"$PAT_ID\",\"$PROV_ID\",\"$SCOPE\"]}")
echo "Org1 CheckConsent: $CHECK_ACTIVE_ORG1"
assert_contains "$CHECK_ACTIVE_ORG1" "\"active\":true" "Consent is active on Org1"
assert_contains "$CHECK_ACTIVE_ORG1" "\"status\":\"GRANTED\"" "Status is GRANTED on Org1"
assert_contains "$CHECK_ACTIVE_ORG1" "\"patientPseudoId\":\"$PAT_ID\"" "Patient pseudo ID matches on Org1"

setGlobals 2
CHECK_ACTIVE_ORG2=$(peer chaincode query -C oncovault-channel -n oncovault -c "{\"function\":\"CheckConsent\",\"Args\":[\"$PAT_ID\",\"$PROV_ID\",\"$SCOPE\"]}")
echo "Org2 CheckConsent: $CHECK_ACTIVE_ORG2"
assert_contains "$CHECK_ACTIVE_ORG2" "\"active\":true" "Consent is active on Org2"
assert_contains "$CHECK_ACTIVE_ORG2" "\"status\":\"GRANTED\"" "Status is GRANTED on Org2"
assert_contains "$CHECK_ACTIVE_ORG2" "\"patientPseudoId\":\"$PAT_ID\"" "Patient pseudo ID matches on Org2"

# --- 7. Negative Test: org1admin CANNOT Revoke Consent ---
echo ""
echo "--- 7. Negative Test: org1admin CANNOT Revoke Consent ---"
setGlobals 1
export CORE_PEER_MSPCONFIGPATH="$ADMIN_MSP"

set +e
ADMIN_REV_RES=$(peer chaincode invoke -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com --tls --cafile "$ORDERER_CA" -C oncovault-channel -n oncovault --peerAddresses localhost:7051 --tlsRootCertFiles "$PEER0_ORG1_CA" --peerAddresses localhost:9051 --tlsRootCertFiles "$PEER0_ORG2_CA" -c "{\"function\":\"RevokeConsent\",\"Args\":[\"$PAT_ID\",\"$PROV_ID\",\"$SCOPE\"]}" 2>&1)
set -e
echo "$ADMIN_REV_RES"
assert_contains "$ADMIN_REV_RES" "Access Denied: Caller 'org1admin'" "org1admin revocation rejected fail-closed"

# --- 8. Positive Test: Dedicated oncovault-gateway Revokes Consent ---
echo ""
echo "--- 8. Positive Test: Dedicated oncovault-gateway Revokes Consent ---"
export CORE_PEER_MSPCONFIGPATH="$GATEWAY_MSP"

GATEWAY_REV_RES=$(peer chaincode invoke -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com --tls --cafile "$ORDERER_CA" -C oncovault-channel -n oncovault --peerAddresses localhost:7051 --tlsRootCertFiles "$PEER0_ORG1_CA" --peerAddresses localhost:9051 --tlsRootCertFiles "$PEER0_ORG2_CA" --waitForEvent -c "{\"function\":\"RevokeConsent\",\"Args\":[\"$PAT_ID\",\"$PROV_ID\",\"$SCOPE\"]}" 2>&1)
echo "$GATEWAY_REV_RES"
assert_contains "$GATEWAY_REV_RES" "status:200" "oncovault-gateway revoke returned 200"
assert_contains "$GATEWAY_REV_RES" "committed with status (VALID) at localhost:7051" "Revoke committed VALID on Org1"
assert_contains "$GATEWAY_REV_RES" "committed with status (VALID) at localhost:9051" "Revoke committed VALID on Org2"

sleep 1

# --- 9. Check Revoked Status on Org1 and Org2 Peers ---
echo ""
echo "--- 9. Check Revoked Status on Org1 and Org2 Peers ---"
setGlobals 1
CHECK_REV_ORG1=$(peer chaincode query -C oncovault-channel -n oncovault -c "{\"function\":\"CheckConsent\",\"Args\":[\"$PAT_ID\",\"$PROV_ID\",\"$SCOPE\"]}")
echo "Org1 Revoked Check: $CHECK_REV_ORG1"
assert_contains "$CHECK_REV_ORG1" "\"active\":false" "Active false on Org1"
assert_contains "$CHECK_REV_ORG1" "\"status\":\"REVOKED\"" "Status REVOKED on Org1"

setGlobals 2
CHECK_REV_ORG2=$(peer chaincode query -C oncovault-channel -n oncovault -c "{\"function\":\"CheckConsent\",\"Args\":[\"$PAT_ID\",\"$PROV_ID\",\"$SCOPE\"]}")
echo "Org2 Revoked Check: $CHECK_REV_ORG2"
assert_contains "$CHECK_REV_ORG2" "\"active\":false" "Active false on Org2"
assert_contains "$CHECK_REV_ORG2" "\"status\":\"REVOKED\"" "Status REVOKED on Org2"

# --- 10. Audit History Verification ---
echo ""
echo "--- 10. Retrieve Full Consent Lifecycle History (GetConsentHistory) ---"
CONSENT_HIST=$(peer chaincode query -C oncovault-channel -n oncovault -c "{\"function\":\"GetConsentHistory\",\"Args\":[\"$PAT_ID\",\"$PROV_ID\",\"$SCOPE\"]}")
echo "$CONSENT_HIST"
assert_contains "$CONSENT_HIST" "\"status\":\"GRANTED\"" "Consent history contains GRANTED"
assert_contains "$CONSENT_HIST" "\"status\":\"REVOKED\"" "Consent history contains REVOKED"
assert_contains "$CONSENT_HIST" "\"gatewayEnrollmentId\":\"oncovault-gateway\"" "Consent history attributes to oncovault-gateway"

echo ""
echo "================================================================="
echo "ALL BATCH 2B.2 SECURITY GATE ASSERTIONS PASSED RIGOROUSLY (EXIT 0)"
echo "================================================================="
