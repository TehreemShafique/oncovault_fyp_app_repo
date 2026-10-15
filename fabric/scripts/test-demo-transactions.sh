#!/usr/bin/env bash
set -e

cd /home/oncovault/oncovault-fabric/fabric-samples/test-network
export PATH="/home/oncovault/oncovault-fabric/fabric-samples/bin:$PATH"
export FABRIC_CFG_PATH=/home/oncovault/oncovault-fabric/fabric-samples/config

. scripts/envVar.sh

echo "================================================================="
echo "ONCOVAULT BATCH 2A: HARDENED FABRIC VERIFICATION & SECURITY GATE"
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

# --- 1. Confirm Committed Chaincode Definition (v1.1, seq 2) on Org1 & Org2 ---
echo ""
echo "--- 1. Querying Committed Chaincode Definition on Org1 and Org2 ---"
setGlobals 1
COMMITTED_ORG1=$(peer lifecycle chaincode querycommitted --channelID oncovault-channel --name oncovault)
echo "$COMMITTED_ORG1"
assert_contains "$COMMITTED_ORG1" "Version: 1.1, Sequence: 2" "Org1 has committed Version 1.1, Sequence 2"
assert_contains "$COMMITTED_ORG1" "Approvals: [Org1MSP: true, Org2MSP: true]" "Org1 confirms dual-org approval"

setGlobals 2
COMMITTED_ORG2=$(peer lifecycle chaincode querycommitted --channelID oncovault-channel --name oncovault)
echo "$COMMITTED_ORG2"
assert_contains "$COMMITTED_ORG2" "Version: 1.1, Sequence: 2" "Org2 has committed Version 1.1, Sequence 2"
assert_contains "$COMMITTED_ORG2" "Approvals: [Org1MSP: true, Org2MSP: true]" "Org2 confirms dual-org approval"

# --- 2. Negative Test: Strict Metadata Allowlist Rejection ---
echo ""
echo "--- 2. Negative Test: Strict Metadata Allowlist (Reject unapproved metadata) ---"
setGlobals 1
RECORD_ID="rec-syn-hardened-$(date +%s)"
HASH_V1="4a5e1e4baab89f3a32518a88c31bc87f618f76673e2cc77ab2127b7afdeda33b"
set +e
REJECT_META_RES=$(peer chaincode invoke -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com --tls --cafile "$ORDERER_CA" -C oncovault-channel -n oncovault --peerAddresses localhost:7051 --tlsRootCertFiles "$PEER0_ORG1_CA" --peerAddresses localhost:9051 --tlsRootCertFiles "$PEER0_ORG2_CA" -c "{\"function\":\"AnchorRecordHash\",\"Args\":[\"$RECORD_ID\",\"$HASH_V1\",\"{\\\"unapprovedCustomKey\\\":\\\"secret_data\\\"}\"]}" 2>&1)
set -e
echo "$REJECT_META_RES"
assert_contains "$REJECT_META_RES" "Rejected unapproved metadata key" "Strict metadata allowlist rejects non-allowlisted key"

# --- 3. Positive Test: Submit Valid SHA-256 Integrity Proof with Allowlisted Metadata ---
echo ""
echo "--- 3. Submit Valid SHA-256 Integrity Proof (AnchorRecordHash) ---"
INVOKE_RES=$(peer chaincode invoke -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com --tls --cafile "$ORDERER_CA" -C oncovault-channel -n oncovault --peerAddresses localhost:7051 --tlsRootCertFiles "$PEER0_ORG1_CA" --peerAddresses localhost:9051 --tlsRootCertFiles "$PEER0_ORG2_CA" --waitForEvent -c "{\"function\":\"AnchorRecordHash\",\"Args\":[\"$RECORD_ID\",\"$HASH_V1\",\"{\\\"documentType\\\":\\\"PATHOLOGY_PANEL\\\",\\\"schemaVersion\\\":\\\"1.0\\\",\\\"synthetic\\\":true}\"]}" 2>&1)
echo "$INVOKE_RES"
assert_contains "$INVOKE_RES" "status:200" "Chaincode invoke returned status 200"
assert_contains "$INVOKE_RES" "committed with status (VALID) at localhost:7051" "Committed with VALID status on Org1 peer"
assert_contains "$INVOKE_RES" "committed with status (VALID) at localhost:9051" "Committed with VALID status on Org2 peer"

TXID=$(echo "$INVOKE_RES" | grep -o "txid \[[a-f0-9]*\]" | cut -d'[' -f2 | cut -d']' -f1 | head -n 1)
echo ">>> Captured Committed Transaction ID: $TXID"

sleep 1

# --- 4. Query Proof from Both Org1 and Org2 Peers ---
echo ""
echo "--- 4. Query Proof from Org1 and Org2 Peers (GetRecordProof) ---"
setGlobals 1
PROOF_ORG1=$(peer chaincode query -C oncovault-channel -n oncovault -c "{\"function\":\"GetRecordProof\",\"Args\":[\"$RECORD_ID\"]}")
echo "Org1 Peer Proof: $PROOF_ORG1"
assert_contains "$PROOF_ORG1" "\"recordId\":\"$RECORD_ID\"" "Proof found on Org1"
assert_contains "$PROOF_ORG1" "\"version\":1" "Proof on Org1 is version 1"
assert_contains "$PROOF_ORG1" "\"sha256Hash\":\"$HASH_V1\"" "Org1 hash matches"

setGlobals 2
PROOF_ORG2=$(peer chaincode query -C oncovault-channel -n oncovault -c "{\"function\":\"GetRecordProof\",\"Args\":[\"$RECORD_ID\"]}")
echo "Org2 Peer Proof: $PROOF_ORG2"
assert_contains "$PROOF_ORG2" "\"recordId\":\"$RECORD_ID\"" "Proof found on Org2"
assert_contains "$PROOF_ORG2" "\"version\":1" "Proof on Org2 is version 1"
assert_contains "$PROOF_ORG2" "\"sha256Hash\":\"$HASH_V1\"" "Org2 hash matches"

# --- 5. Verify Correct SHA-256 Hash Succeeds ---
echo ""
echo "--- 5. Verify Correct SHA-256 Hash (VerifyRecordHash) ---"
VERIFY_VALID=$(peer chaincode query -C oncovault-channel -n oncovault -c "{\"function\":\"VerifyRecordHash\",\"Args\":[\"$RECORD_ID\",\"$HASH_V1\"]}")
echo "$VERIFY_VALID"
assert_contains "$VERIFY_VALID" "\"verified\":true" "Hash verification succeeded"
assert_contains "$VERIFY_VALID" "\"status\":\"VERIFIED\"" "Status is VERIFIED"

# --- 6. Verify Tampered Hash Fails ---
echo ""
echo "--- 6. Verify Tampered Hash (VerifyRecordHash) ---"
TAMPERED_HASH="0000000000000000000000000000000000000000000000000000000000000000"
VERIFY_TAMPERED=$(peer chaincode query -C oncovault-channel -n oncovault -c "{\"function\":\"VerifyRecordHash\",\"Args\":[\"$RECORD_ID\",\"$TAMPERED_HASH\"]}")
echo "$VERIFY_TAMPERED"
assert_contains "$VERIFY_TAMPERED" "\"verified\":false" "Tampered hash verification rejected"
assert_contains "$VERIFY_TAMPERED" "\"status\":\"TAMPERED_OR_MISMATCH\"" "Status is TAMPERED_OR_MISMATCH"

# --- 7. Duplicate Anchoring Prevention ---
echo ""
echo "--- 7. Duplicate Anchoring Prevention ---"
setGlobals 1
set +e
DUP_RES=$(peer chaincode invoke -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com --tls --cafile "$ORDERER_CA" -C oncovault-channel -n oncovault --peerAddresses localhost:7051 --tlsRootCertFiles "$PEER0_ORG1_CA" --peerAddresses localhost:9051 --tlsRootCertFiles "$PEER0_ORG2_CA" -c "{\"function\":\"AnchorRecordHash\",\"Args\":[\"$RECORD_ID\",\"$HASH_V1\",\"{}\"]}" 2>&1)
set -e
echo "$DUP_RES"
assert_contains "$DUP_RES" "Duplicate anchoring rejected" "Duplicate identical hash anchoring rejected"

# --- 8. Legitimate Record Revision (Version 2) ---
echo ""
echo "--- 8. Legitimate Record Revision (Version 2) ---"
HASH_V2="b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9"
REV_RES=$(peer chaincode invoke -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com --tls --cafile "$ORDERER_CA" -C oncovault-channel -n oncovault --peerAddresses localhost:7051 --tlsRootCertFiles "$PEER0_ORG1_CA" --peerAddresses localhost:9051 --tlsRootCertFiles "$PEER0_ORG2_CA" --waitForEvent -c "{\"function\":\"AnchorRecordHash\",\"Args\":[\"$RECORD_ID\",\"$HASH_V2\",\"{\\\"revisionReason\\\":\\\"AMENDED_ASSAY\\\"}\"]}" 2>&1)
echo "$REV_RES"
assert_contains "$REV_RES" "status:200" "Revision invoke returned 200"
assert_contains "$REV_RES" "committed with status (VALID) at localhost:7051" "Revision committed VALID on Org1"
assert_contains "$REV_RES" "committed with status (VALID) at localhost:9051" "Revision committed VALID on Org2"

sleep 1

PROOF_V2=$(peer chaincode query -C oncovault-channel -n oncovault -c "{\"function\":\"GetRecordProof\",\"Args\":[\"$RECORD_ID\"]}")
echo "Updated Proof V2: $PROOF_V2"
assert_contains "$PROOF_V2" "\"version\":2" "Record updated to Version 2"
assert_contains "$PROOF_V2" "\"previousHash\":\"$HASH_V1\"" "Version 2 links previous hash"

# --- 9. Retrieve Historical Proof Activity ---
echo ""
echo "--- 9. Retrieve Historical Proof Activity (GetRecordHistory) ---"
HISTORY=$(peer chaincode query -C oncovault-channel -n oncovault -c "{\"function\":\"GetRecordHistory\",\"Args\":[\"$RECORD_ID\"]}")
echo "$HISTORY"
assert_contains "$HISTORY" "\"version\":1" "History includes version 1"
assert_contains "$HISTORY" "\"version\":2" "History includes version 2"

# --- 10. Negative Test: Ordinary Org1 Identity (user1) CANNOT Grant Consent ---
echo ""
echo "--- 10. Negative Test: Ordinary User1 CANNOT Grant Consent (Fail-Closed Check) ---"
setGlobals 1
export CORE_PEER_MSPCONFIGPATH=/home/oncovault/oncovault-fabric/fabric-samples/test-network/organizations/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp

PAT_ID="pat-sec-$(date +%s)"
PROV_ID="prov-sec-clinic-z"
SCOPE="ONCOLOGY_RESEARCH"
EXPIRATION="2028-12-31T23:59:59Z"

set +e
USER1_GRANT_RES=$(peer chaincode invoke -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com --tls --cafile "$ORDERER_CA" -C oncovault-channel -n oncovault --peerAddresses localhost:7051 --tlsRootCertFiles "$PEER0_ORG1_CA" --peerAddresses localhost:9051 --tlsRootCertFiles "$PEER0_ORG2_CA" -c "{\"function\":\"GrantConsent\",\"Args\":[\"$PAT_ID\",\"$PROV_ID\",\"$SCOPE\",\"$EXPIRATION\"]}" 2>&1)
set -e
echo "$USER1_GRANT_RES"
assert_contains "$USER1_GRANT_RES" "not an authorized OncoVault Gateway identity" "Ordinary User1 identity is rejected fail-closed"

# --- 11. Positive Test: Authorized Gateway Identity (org1admin) Grants Consent ---
echo ""
echo "--- 11. Positive Test: Authorized Gateway Grants Consent ---"
export CORE_PEER_MSPCONFIGPATH=/home/oncovault/oncovault-fabric/fabric-samples/test-network/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp

GATEWAY_GRANT_RES=$(peer chaincode invoke -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com --tls --cafile "$ORDERER_CA" -C oncovault-channel -n oncovault --peerAddresses localhost:7051 --tlsRootCertFiles "$PEER0_ORG1_CA" --peerAddresses localhost:9051 --tlsRootCertFiles "$PEER0_ORG2_CA" --waitForEvent -c "{\"function\":\"GrantConsent\",\"Args\":[\"$PAT_ID\",\"$PROV_ID\",\"$SCOPE\",\"$EXPIRATION\"]}" 2>&1)
echo "$GATEWAY_GRANT_RES"
assert_contains "$GATEWAY_GRANT_RES" "status:200" "Authorized Gateway grant returned 200"
assert_contains "$GATEWAY_GRANT_RES" "committed with status (VALID) at localhost:7051" "Grant committed VALID on Org1"
assert_contains "$GATEWAY_GRANT_RES" "committed with status (VALID) at localhost:9051" "Grant committed VALID on Org2"

sleep 1

# --- 12. Check Active Consent from Both Org1 and Org2 Peers ---
echo ""
echo "--- 12. Check Active Consent from Both Peers (CheckConsent) ---"
setGlobals 1
CHECK_ACTIVE_ORG1=$(peer chaincode query -C oncovault-channel -n oncovault -c "{\"function\":\"CheckConsent\",\"Args\":[\"$PAT_ID\",\"$PROV_ID\",\"$SCOPE\"]}")
echo "Org1 CheckConsent: $CHECK_ACTIVE_ORG1"
assert_contains "$CHECK_ACTIVE_ORG1" "\"active\":true" "Consent active on Org1"
assert_contains "$CHECK_ACTIVE_ORG1" "\"status\":\"GRANTED\"" "Status GRANTED on Org1"

setGlobals 2
CHECK_ACTIVE_ORG2=$(peer chaincode query -C oncovault-channel -n oncovault -c "{\"function\":\"CheckConsent\",\"Args\":[\"$PAT_ID\",\"$PROV_ID\",\"$SCOPE\"]}")
echo "Org2 CheckConsent: $CHECK_ACTIVE_ORG2"
assert_contains "$CHECK_ACTIVE_ORG2" "\"active\":true" "Consent active on Org2"
assert_contains "$CHECK_ACTIVE_ORG2" "\"status\":\"GRANTED\"" "Status GRANTED on Org2"

# --- 13. Negative Test: Ordinary User1 CANNOT Revoke Consent ---
echo ""
echo "--- 13. Negative Test: Ordinary User1 CANNOT Revoke Consent ---"
setGlobals 1
export CORE_PEER_MSPCONFIGPATH=/home/oncovault/oncovault-fabric/fabric-samples/test-network/organizations/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp

set +e
USER1_REVOKE_RES=$(peer chaincode invoke -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com --tls --cafile "$ORDERER_CA" -C oncovault-channel -n oncovault --peerAddresses localhost:7051 --tlsRootCertFiles "$PEER0_ORG1_CA" --peerAddresses localhost:9051 --tlsRootCertFiles "$PEER0_ORG2_CA" -c "{\"function\":\"RevokeConsent\",\"Args\":[\"$PAT_ID\",\"$PROV_ID\",\"$SCOPE\"]}" 2>&1)
set -e
echo "$USER1_REVOKE_RES"
assert_contains "$USER1_REVOKE_RES" "not an authorized OncoVault Gateway identity" "Ordinary User1 identity cannot revoke consent"

# --- 14. Positive Test: Authorized Gateway Revokes Consent ---
echo ""
echo "--- 14. Positive Test: Authorized Gateway Revokes Consent ---"
export CORE_PEER_MSPCONFIGPATH=/home/oncovault/oncovault-fabric/fabric-samples/test-network/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp

GATEWAY_REVOKE_RES=$(peer chaincode invoke -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com --tls --cafile "$ORDERER_CA" -C oncovault-channel -n oncovault --peerAddresses localhost:7051 --tlsRootCertFiles "$PEER0_ORG1_CA" --peerAddresses localhost:9051 --tlsRootCertFiles "$PEER0_ORG2_CA" --waitForEvent -c "{\"function\":\"RevokeConsent\",\"Args\":[\"$PAT_ID\",\"$PROV_ID\",\"$SCOPE\"]}" 2>&1)
echo "$GATEWAY_REVOKE_RES"
assert_contains "$GATEWAY_REVOKE_RES" "status:200" "Revoke invoke returned 200"
assert_contains "$GATEWAY_REVOKE_RES" "committed with status (VALID) at localhost:7051" "Revoke committed VALID on Org1"
assert_contains "$GATEWAY_REVOKE_RES" "committed with status (VALID) at localhost:9051" "Revoke committed VALID on Org2"

sleep 1

# --- 15. Verify Revoked Status from Both Peers ---
echo ""
echo "--- 15. Verify Revoked Status from Both Peers ---"
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

# --- 16. Retrieve Consent Audit History ---
echo ""
echo "--- 16. Retrieve Full Consent Lifecycle History (GetConsentHistory) ---"
CONSENT_HIST=$(peer chaincode query -C oncovault-channel -n oncovault -c "{\"function\":\"GetConsentHistory\",\"Args\":[\"$PAT_ID\",\"$PROV_ID\",\"$SCOPE\"]}")
echo "$CONSENT_HIST"
assert_contains "$CONSENT_HIST" "\"status\":\"GRANTED\"" "Consent history has GRANTED"
assert_contains "$CONSENT_HIST" "\"status\":\"REVOKED\"" "Consent history has REVOKED"

echo ""
echo "================================================================="
echo "ALL HARDENED SECURITY GATE TESTS PASSED RIGOROUSLY (EXIT 0)"
echo "================================================================="
