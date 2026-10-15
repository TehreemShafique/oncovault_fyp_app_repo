# OncoVault — Hyperledger Fabric Security Architecture & Boundaries

## Batch 2A Security Note

### 1. Consent Authorization & Gateway Identity Boundary
In the current development network deployment (Batch 2A), consent mutation operations (`GrantConsent`, `RevokeConsent`) are strictly gated using fail-closed authorization (`_validateGatewayAuthorization` in `lib/oncovault-contract.js`).

> [!WARNING]
> **Development Identities Only:**
> The identities `org1admin` and `org2admin` are enrolled as consent-capable development/administrative identities solely for bootstrapping, testing, and lifecycle management. **They must not be used for live patient consent.**

### 2. Trusted Gateway Dependency
Individual patients authenticate via the OncoVault mobile application using Firebase Authentication. Fabric MSP membership alone does not establish human patient authorization.

The future Trusted Gateway service must:
1. Verify the client's Firebase ID token and extract the authenticated Firebase UID.
2. Validate that the requesting patient owns the targeted `patientPseudoId` (or that an authorized provider holds active clinical delegated authority).
3. Ensure the patient has explicitly consented to the specific provider and scope before submitting transactions using dedicated Fabric Gateway credentials (`oncovault-gateway`).

### 3. Batch 2B Production Requirement
Batch 2B must replace or restrict the administrative bypasses (`org1admin`, `org2admin`) so that only a dedicated, cryptographically verified gateway identity enrolled under strict least-privilege policies may submit patient consent transactions.

### 4. Privacy & Anti-PHI Safeguards
- Public channel state never stores raw medical records, patient names, MRNs, diagnoses, or clinical notes.
- Only 64-character SHA-256 hexadecimal digests (`/^[a-fA-F0-9]{64}$/`) and pseudonymous opaque identifiers (`/^[A-Za-z0-9_\-\.]{3,128}$/`) are committed.
- Metadata is governed by a strict allowlist (`documentType`, `recordType`, `schemaVersion`, `mimeType`, `checksumAlg`, `revision`, `revisionReason`, `synthetic`). All unapproved keys and non-primitive values are rejected at endorsement.
