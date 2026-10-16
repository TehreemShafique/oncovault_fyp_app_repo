# OncoVault — Trusted Hyperledger Fabric Gateway

The OncoVault Fabric Gateway is a dedicated Node.js/TypeScript backend service bridging Firebase Authentication, Firestore, Firebase Storage, and the real Hyperledger Fabric ledger (`oncovault-channel`, chaincode `oncovault` v1.2 sequence 3).

---

## 1. Architecture

```text
Flutter Mobile Client
       │ (HTTPS / Bearer Firebase ID Token)
       ▼
OncoVault Trusted Gateway (Node.js/TypeScript Express on 127.0.0.1:5001)
  ├── 1. Auth Middleware: Verify Firebase ID Token via Firebase Admin SDK
  ├── 2. Authorize Middleware: Firestore Role & Anti-IDOR Patient Ownership
  ├── 3. Record Service: Server-Side Binary SHA-256 & Deterministic Pseudonymization
  ├── 4. Consent Service: Phase 2 Safety Gate & Patient-Delegated Authorization
  ├── 5. Reconciliation Service: Idempotency & Status Tracking (PENDING, COMMITTED, UNCERTAIN_RETRYABLE)
       │ (gRPC TLS using oncovault-gateway X.509 Client Credentials)
       ▼
Hyperledger Fabric Network (WSL2 / Linux Engine)
  ├── peer0.org1.example.com (Port 7051)
  ├── peer0.org2.example.com (Port 9051)
  └── orderer.example.com (Port 7050)
```

---

## 2. Security Boundaries

1. **Loopback-Only Binding**: Defaults strictly to `127.0.0.1:5001` to protect Bearer tokens and gRPC RPCs.
2. **Dedicated Gateway Identity**: Connects via CA-issued client identity `oncovault-gateway` under `Org1MSP`. Chaincode administrative bypasses have been removed.
3. **Off-Chain Patient Authorization**: Fabric gateway certificates establish submitter trust with peers, but *do not* prove human patient consent. The gateway verifies Firebase ID tokens, patient ownership, and clinician delegation before submitting transactions.
4. **Anti-PHI Protection**: Raw patient records, UIDs, and medical diagnoses never reach the blockchain. Records are anchored as SHA-256 digests and domain-separated HMAC-SHA256 pseudonyms (`pat_...`, `prov_...`, `rec_...`).
5. **Live Consent Mutation Safety Gate**: Live consent mutations are disabled by default (`ENABLE_LIVE_CONSENT_MUTATIONS=false`) until Firestore direct mutation bypass paths in Flutter are migrated in Phase 3. Ledger queries remain active.

---

## 3. Configuration (`.env`)

Copy `.env.example` to `.env`:

```bash
cp .env.example .env
```

| Variable | Description | Default |
| :--- | :--- | :--- |
| `HOST` | Loopback listener address | `127.0.0.1` |
| `PORT` | Local service port | `5001` |
| `FABRIC_CHANNEL_NAME` | Channel name | `oncovault-channel` |
| `FABRIC_CHAINCODE_NAME` | Smart contract name | `oncovault` |
| `FABRIC_MSP_ID` | Organization MSP | `Org1MSP` |
| `FABRIC_PEER_ENDPOINT` | Org1 peer gRPC endpoint | `localhost:7051` |
| `FABRIC_PEER_HOST_OVERRIDE` | TLS hostname override | `peer0.org1.example.com` |
| `FABRIC_TLS_CERT_PATH` | Peer TLS root cert | `.../tlsca.org1.example.com-cert.pem` |
| `FABRIC_GATEWAY_CERT_PATH` | Client public cert | `.../oncovault-gateway@org1.example.com/msp/signcerts/cert.pem` |
| `FABRIC_GATEWAY_KEY_DIR` | Client keystore directory | `.../oncovault-gateway@org1.example.com/msp/keystore` |
| `PSEUDONYM_HMAC_SECRET` | HMAC secret for pseudonyms | `32+ character protected secret` |
| `ENABLE_LIVE_CONSENT_MUTATIONS`| Live consent mutation gate | `false` (Phase 2 default) |
| `FIREBASE_PROJECT_ID` | Verified Firebase Project ID | `oncovault-8cbbc` |
| `FIREBASE_STORAGE_BUCKET` | Firebase Cloud Storage bucket | `oncovault-8cbbc.firebasestorage.app` |
| `FIREBASE_SERVICE_ACCOUNT_PATH`| Path to service account JSON | *Optional for local/emulator* |

---

## 4. Local Execution & Testing (WSL2 / Linux)

### Installation
```bash
cd fabric/gateway
npm install
```

### Run Unit Tests (Mocked External Dependencies)
```bash
npm test
```

### Run Live Fabric Network Tests (Real Fabric Gateway SDK)
```bash
npm run test:live
```

### Build & Start Gateway Server
```bash
# Development mode with hot-reloading:
npm run dev

# Production build and run:
npm run build
npm start
```

### Health & Readiness Endpoints
- `GET http://127.0.0.1:5001/health` — Basic liveness probe.
- `GET http://127.0.0.1:5001/ready` — Inspects Fabric gRPC and Firebase dependency readiness without leaking secrets.
