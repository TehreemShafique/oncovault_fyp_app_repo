# OncoVault — Hyperledger Fabric Security Architecture & Boundaries

## 1. Gateway Identity & Fail-Closed Consent Authorization (Batch 2B.2)

In Batch 2B.2 Phase 1, all development administrative bypasses (`org1admin`, `org2admin`) have been **completely eliminated** from chaincode consent mutation authorization.

Consent mutation operations (`GrantConsent`, `RevokeConsent`) are strictly gated by `_validateGatewayAuthorization` in `lib/oncovault-contract.js`:

```javascript
const AUTHORIZED_GATEWAY_IDENTITIES = [
    'oncovault-gateway'
];
const AUTHORIZED_GATEWAY_MSP = 'Org1MSP';
```

### Identity Verification Mechanics
1. **MSP Verification**: The transaction submitter must originate from `Org1MSP`. Any identity from `Org2MSP` or unauthorized MSPs attempting consent mutations is rejected fail-closed.
2. **Fabric CA Enrollment Verification**: The chaincode extracts the authenticated Fabric CA enrollment ID (`hf.EnrollmentID` attribute from Fabric CA extension OID `1.2.3.4.5.6.7.8.1`, falling back to X.509 Common Name `CN`).
3. **Fail-Closed Policy**:
   - `oncovault-gateway`: **PERMITTED** to submit delegated consent mutations.
   - `org1admin` / `org2admin`: **REJECTED** (`Access Denied: Caller 'org1admin' from 'Org1MSP' is not an authorized OncoVault Gateway identity`).
   - Ordinary members (e.g. `user1`): **REJECTED**.

---

## 2. Safe Gateway Enrollment & Credential Rotation Procedures

### Secure Enrollment Workflow
- **Idempotent Execution**: [`fabric/scripts/enroll-gateway.sh`](file:///g:/oncovault/oncovault_fyp_app_repo/fabric/scripts/enroll-gateway.sh) automatically inspects the gateway MSP directory (`.../users/oncovault-gateway@org1.example.com/msp`). If a valid, unexpired X.509 certificate exists, it verifies filesystem permissions and skips re-enrollment, preventing accidental certificate regeneration or downtime.
- **Zero Committed Secrets**: Enrollment scripts contain **no** hardcoded passwords or literals. Secrets are accepted dynamically via `GATEWAY_ENROLLMENT_SECRET`, from a protected local file (`--secret-file <path>`), or generated cryptographically using `openssl rand -hex 32` for fresh registrations.
- **Immediate In-Memory Zeroing**: Secrets are unset from environment and memory immediately following the enrollment call.
- **Filesystem Permissions**:
  - Target user directory: `0700` (`drwx------`)
  - MSP directory and subdirectories (`keystore`, `signcerts`): `0700` (`drwx------`)
  - Private key file (`..._sk`): `0600` (`-rw-------`)
  - Public certificate and config: `0644` (`-rw-r--r--`)
- **Git Protection**: Strict ignore rules in [`fabric/.gitignore`](file:///g:/oncovault/oncovault_fyp_app_repo/fabric/.gitignore) and root [`.gitignore`](file:///g:/oncovault/oncovault_fyp_app_repo/.gitignore) prevent tracking of `*.pem`, `*.key`, `*.secret`, `**/keystore/`, `**/msp/`, or `**/wallet/`.

### Secret Rotation Procedure
When an enrollment secret is rotated or invalidated:
1. Run [`fabric/scripts/rotate-gateway-secret.sh`](file:///g:/oncovault/oncovault_fyp_app_repo/fabric/scripts/rotate-gateway-secret.sh).
2. The script authenticates using CA registrar credentials and executes:
   ```bash
   fabric-ca-client identity modify oncovault-gateway \
       --secret "$NEW_SECRET" \
       --caname ca-org1 \
       --tls.certfiles "$CA_CERT"
   ```
3. **Rotation Mechanics & Scope**:
   - Modifying the secret updates the CA's internal authentication database immediately.
   - The previously exposed enrollment password is instantly **invalidated** and cannot be used for subsequent enrollments.
   - **Active Certificates**: The existing, issued X.509 client certificate and private key remain valid and functional until expiration or explicit revocation.
4. **Certificate Revocation (If Private Key Compromised)**:
   - If the private key itself is ever suspected of compromise (unlike a secret rotation), the certificate must be explicitly revoked:
     ```bash
     fabric-ca-client revoke --revoke.name oncovault-gateway --caname ca-org1 --tls.certfiles "$CA_CERT"
     ```
   - Then re-enrollment must be executed with `--force` using a freshly rotated secret.

---

## 3. Trusted Gateway Role & Off-Chain Patient Authorization

> [!IMPORTANT]
> **Gateway Certificate Does Not Equal Patient Authorization:**
> The Fabric gateway certificate establishes *delegated submitter trust* between the trusted backend service and the Fabric peers. It does **not** prove that an individual human patient consented to a particular transaction.

The upcoming Trusted Gateway service (Phase 2) must strictly enforce the following off-chain authorization pipeline before invoking chaincode:
1. **Firebase Authentication Verification**: Validate the client's Firebase ID token via the Firebase Admin SDK and extract the authenticated `uid`.
2. **Patient Authorization & Ownership**: Verify via Firestore security context that the authenticated caller owns the `patientPseudoId` (or is an explicitly delegated clinician).
3. **Consent Mutation Authoritative Path**: The gateway backend is the sole authoritative writer for patient consent. It writes to the ledger first, verifies dual-peer VALID commit, and subsequently records audit state in Firestore.
4. **Loopback-Only Network Binding**: The local gateway binds exclusively to `127.0.0.1` to prevent exposure of Firebase bearer tokens or Fabric Gateway RPC over insecure network interfaces.

---

## 4. Record Integrity & Anti-PHI Safeguards

- **Strict Metadata Allowlist**: Only approved keys (`documentType`, `recordType`, `schemaVersion`, `mimeType`, `checksumAlg`, `revision`, `revisionReason`, `synthetic`) with primitive string/number/boolean values are permitted.
- **Forbidden PHI Terms**: Both metadata and opaque identifiers are scanned for prohibited PHI keywords (`patient`, `name`, `mrn`, `diagnosis`, `cancer`, etc.). Any match is rejected at chaincode endorsement.
- **Append-Only Immutability**: Existing record integrity proofs cannot be overwritten with duplicate hashes, nor modified by non-originating MSPs. Legitimate revisions advance monotonically through version numbers and preserve SHA-256 historical linkage.
