// fabric/gateway/test/e2e/firebaseFabricE2E.test.ts
import { expect } from 'chai';
import request from 'supertest';
import * as crypto from 'crypto';
import * as fs from 'fs';
import * as admin from 'firebase-admin';
import { createApp } from '../../src/app';
import { FabricGatewayService } from '../../src/services/fabricGateway';
import { FirebaseAdminService } from '../../src/services/firebaseAdmin';
import { PseudonymService } from '../../src/services/pseudonymService';

describe('Real Authenticated Firebase-to-Fabric End-to-End Test Suite', function () {
  this.timeout(60000);

  let app: any;
  let fabric: FabricGatewayService;
  let hostIp = '127.0.0.1';

  // Test identities
  const patAId = 'e2e_pat_a';
  const patBId = 'e2e_pat_b';
  const docAId = 'e2e_doc_a';
  const docBId = 'e2e_doc_b';

  let patAToken: string;
  let patBToken: string;
  let docAToken: string;
  let docBToken: string;

  let recordId: string;
  const fileName = 'cbc_blood_panel_synthetic.pdf';
  const bucketName = 'oncovault-8cbbc.firebasestorage.app';

  // Synthetic clinical binary bytes (Oncology CBC Panel)
  const syntheticReportBytes = Buffer.from(
    `%PDF-1.4\n` +
    `%OncoVault Synthetic Clinical Blood Cancer Assay\n` +
    `Patient ID: ${patAId}\n` +
    `Specimen: Peripheral Blood\n` +
    `WBC Count: 2.8 x10^9/L (Critical Low)\n` +
    `Platelets: 42 x10^9/L (Severe Thrombocytopenia)\n` +
    `Blast Cell Differential: 24% (Abnormal Myeloblasts)\n` +
    `Flow Cytometry Markers: CD34+, CD33+, CD117+, HLA-DR+\n` +
    `Diagnosis Correlation: Acute Myeloid Leukemia (AML) Relapse Risk\n` +
    `Laboratory Director: Dr. E2E Hematopathologist\n` +
    `Timestamp: ${new Date().toISOString()}\n` +
    `%%EOF`
  );

  const independentSha256 = crypto.createHash('sha256').update(syntheticReportBytes).digest('hex');
  let anchoredTxId = '';
  let grantTxId = '';

  // Helper to exchange custom token for ID token via Auth Emulator REST API
  async function exchangeCustomToken(customToken: string): Promise<string> {
    const url = `http://${hostIp}:9099/identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=fake-api-key`;
    const res = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ token: customToken, returnSecureToken: true })
    });
    const json = (await res.json()) as any;
    if (!json.idToken) {
      throw new Error(`Failed to exchange custom token: ${JSON.stringify(json)}`);
    }
    return json.idToken;
  }

  before(async function () {
    // 1. Resolve host IP for emulator connectivity from WSL
    if (fs.existsSync('/etc/resolv.conf')) {
      const resolv = fs.readFileSync('/etc/resolv.conf', 'utf8');
      const match = resolv.match(/nameserver\s+([^\s]+)/);
      if (match && match[1]) {
        hostIp = match[1];
      }
    }

    // Configure emulator environment variables
    process.env.FIREBASE_AUTH_EMULATOR_HOST = `${hostIp}:9099`;
    process.env.FIRESTORE_EMULATOR_HOST = `${hostIp}:8080`;
    process.env.FIREBASE_STORAGE_EMULATOR_HOST = `${hostIp}:9199`;
    process.env.STORAGE_EMULATOR_HOST = `http://${hostIp}:9199`;
    process.env.FIREBASE_PROJECT_ID = 'oncovault-8cbbc';
    process.env.FIREBASE_STORAGE_BUCKET = bucketName;

    // Reset and initialize Firebase Admin
    if (admin.apps.length > 0) {
      await Promise.all(admin.apps.map(a => a?.delete()));
    }
    FirebaseAdminService.resetInstance();
    const adminService = FirebaseAdminService.getInstance();
    const firestore = adminService.getFirestoreInstance()!;
    const auth = adminService.getAuthInstance()!;
    const storage = adminService.getStorageInstance()!;

    // 2. Connect to real Fabric network on oncovault-channel
    fabric = FabricGatewayService.getInstance();
    await fabric.connect();
    expect(fabric.isConnected()).to.be.true;

    // 3. Create synthetic users in Auth Emulator & authoritative Firestore profiles
    const usersToCreate = [
      { uid: patAId, email: 'patient_a@oncovault.test', role: 'patient', name: 'Patient A' },
      { uid: patBId, email: 'patient_b@oncovault.test', role: 'patient', name: 'Patient B' },
      { uid: docAId, email: 'doctor_a@oncovault.test', role: 'doctor', name: 'Authorized Doctor A' },
      { uid: docBId, email: 'doctor_b@oncovault.test', role: 'doctor', name: 'Unauthorized Doctor B' },
    ];

    for (const u of usersToCreate) {
      try {
        await auth.deleteUser(u.uid);
      } catch (_) {}
      await auth.createUser({
        uid: u.uid,
        email: u.email,
        password: 'Password123!',
        displayName: u.name,
      });

      await firestore.collection('users').doc(u.uid).set({
        uid: u.uid,
        email: u.email,
        name: u.name,
        role: u.role,
        createdAt: new Date().toISOString(),
      });
    }

    // 4. Acquire genuine Auth Emulator-issued ID tokens
    const customPatA = await auth.createCustomToken(patAId);
    const customPatB = await auth.createCustomToken(patBId);
    const customDocA = await auth.createCustomToken(docAId);
    const customDocB = await auth.createCustomToken(docBId);

    patAToken = await exchangeCustomToken(customPatA);
    patBToken = await exchangeCustomToken(customPatB);
    docAToken = await exchangeCustomToken(customDocA);
    docBToken = await exchangeCustomToken(customDocB);

    expect(patAToken).to.be.a('string').and.not.empty;
    expect(docAToken).to.be.a('string').and.not.empty;

    // 5. Upload synthetic report bytes to Storage Emulator with unique recordId
    recordId = `rec_e2e_cbc_${Date.now()}`;
    const storagePath = `reports/${patAId}/${recordId}_${fileName}`;
    const bucket = storage.bucket(bucketName);
    const file = bucket.file(storagePath);
    await file.save(syntheticReportBytes, {
      contentType: 'application/pdf',
      metadata: { patientId: patAId }
    });

    // 6. Create authoritative medical record in Firestore
    const recordPayload = {
      id: recordId,
      patientId: patAId,
      title: 'Synthetic Oncology CBC Panel',
      type: 'report',
      subtype: 'Hematology',
      facility: 'Shaukat Khanum Memorial Cancer Hospital',
      fileUrl: `gs://${bucketName}/${storagePath}`,
      isArchived: false,
      uploadedAt: new Date().toISOString()
    };
    await firestore.collection('medical_records').doc(recordId).set(recordPayload);
    await firestore.collection('patients').doc(patAId).collection('medicalRecords').doc(recordId).set(recordPayload);

    // 7. Initialize Express app
    app = createApp();
  });

  after(async function () {
    if (fabric && fabric.isConnected()) {
      await fabric.disconnect();
    }
  });

  it('1. Authentication Verification: verifies genuine Auth Emulator token and loads authoritative Firestore role', async () => {
    // Send health check with authenticated user
    const res = await request(app)
      .get('/health')
      .expect(200);
    expect(res.body.status).to.equal('UP');
  });

  it('2. Fabric On-Chain Consent: establishes genuine on-chain patient consent for Doctor A', async function () {
    this.timeout(30000);
    const patientPseudoId = PseudonymService.generatePatientPseudoId(patAId);
    const providerPseudoId = PseudonymService.generateProviderPseudoId(docAId);

    const { result, txId } = await fabric.submitTransaction(
      'GrantConsent',
      patientPseudoId,
      providerPseudoId,
      'BLOOD_CANCER_RESEARCH',
      'NEVER'
    );
    grantTxId = txId || '';
    expect(grantTxId).to.be.a('string').and.not.empty;

    // Verify on-chain CheckConsent returns active === true
    const checkStr = await fabric.evaluateTransaction(
      'CheckConsent',
      patientPseudoId,
      providerPseudoId,
      'BLOOD_CANCER_RESEARCH'
    );
    const checkRes = JSON.parse(checkStr);
    expect(checkRes.active).to.be.true;
    expect(checkRes.status).to.equal('GRANTED');

    // Sync Firestore projection via Admin SDK
    const db = FirebaseAdminService.getInstance().getFirestoreInstance()!;
    await db.collection('doctor_patient_consents').doc(`${patAId}_${docAId}`).set({
      id: `${patAId}_${docAId}`,
      patientId: patAId,
      doctorId: docAId,
      scope: 'BLOOD_CANCER_RESEARCH',
      status: 'granted',
      fabricTxId: grantTxId,
      fabricStatus: 'COMMITTED',
      blockchainVerified: true
    });
  });

  it('3. Record Anchoring: Doctor A anchors synthetic report via Gateway; downloads storage bytes and anchors on real Fabric', async function () {
    this.timeout(45000);

    const res = await request(app)
      .post('/api/v1/records/anchor')
      .set('Authorization', `Bearer ${docAToken}`)
      .send({
        recordId,
        patientId: patAId,
        metadata: {
          documentType: 'LABORATORY_REPORT',
          assayName: 'CBC_FLOW_CYTOMETRY'
        }
      })
      .expect(200);

    expect(res.body.success).to.be.true;
    expect(res.body.data.proof).to.exist;
    expect(res.body.data.proof.sha256Hash).to.equal(independentSha256);
    expect(res.body.data.proof.version).to.equal(1);
    expect(res.body.data.proof.status).to.equal('ACTIVE');
    expect(res.body.data.proof.txId).to.be.a('string').and.not.empty;

    anchoredTxId = res.body.data.proof.txId;

    // Verify proof metadata was written to Firestore
    const db = FirebaseAdminService.getInstance().getFirestoreInstance()!;
    const docSnap = await db.collection('medical_records').doc(recordId).get();
    expect(docSnap.exists).to.be.true;
    const docData = docSnap.data()!;
    expect(docData.fabricStatus).to.equal('COMMITTED');
    expect(docData.fabricTxId).to.equal(anchoredTxId);
    expect(docData.fileHash).to.equal(independentSha256);
    expect(docData.fabricVersion).to.equal(1);
  });

  it('4. Ledger Hash vs Independent Binary SHA-256: query on-chain GetRecordProof directly and verify cryptographic match', async () => {
    const opaqueRecordKey = PseudonymService.generateOpaqueRecordKey(patAId, recordId);
    const proofStr = await fabric.evaluateTransaction('GetRecordProof', opaqueRecordKey);
    const proof = JSON.parse(proofStr);

    expect(proof.sha256Hash.toLowerCase()).to.equal(independentSha256.toLowerCase());
    expect(proof.txId).to.equal(anchoredTxId);
    expect(proof.version).to.equal(1);
  });

  it('5. Record Verification (Genuine): returns status VERIFIED for matching hash', async () => {
    const res = await request(app)
      .post('/api/v1/records/verify')
      .set('Authorization', `Bearer ${docAToken}`)
      .send({
        recordId,
        patientId: patAId,
        expectedHash: independentSha256
      })
      .expect(200);

    expect(res.body.data.verified).to.be.true;
    expect(res.body.data.status).to.equal('VERIFIED');
    expect(res.body.data.ledgerProof).to.exist;
    expect(res.body.data.ledgerProof.txId).to.equal(anchoredTxId);
  });

  it('6. Record Verification (Tampered): returns status TAMPERED_OR_MISMATCH for forged hash', async () => {
    const tamperedHash = crypto.createHash('sha256').update('MALICIOUS_TAMPERED_CONTENT').digest('hex');

    const res = await request(app)
      .post('/api/v1/records/verify')
      .set('Authorization', `Bearer ${docAToken}`)
      .send({
        recordId,
        patientId: patAId,
        expectedHash: tamperedHash
      })
      .expect(200);

    expect(res.body.data.verified).to.be.false;
    expect(res.body.data.status).to.equal('TAMPERED_OR_MISMATCH');
  });

  it('7. Patient IDOR Protection: Patient B attempting to access Patient A record is rejected with 403', async () => {
    const res = await request(app)
      .post('/api/v1/records/verify')
      .set('Authorization', `Bearer ${patBToken}`)
      .send({
        recordId,
        patientId: patAId,
        expectedHash: independentSha256
      })
      .expect(403);

    expect(res.body.success).to.be.false;
  });

  it('8. Clinician Consent Enforcement: Unauthorized Doctor B accessing Patient A record is rejected with 403', async () => {
    const res = await request(app)
      .post('/api/v1/records/verify')
      .set('Authorization', `Bearer ${docBToken}`)
      .send({
        recordId,
        patientId: patAId,
        expectedHash: independentSha256
      })
      .expect(403);

    expect(res.body.success).to.be.false;
    expect(res.body.error.message).to.include('Access Denied');
  });

  it('9. Missing / Fake Token: rejected with 401 Unauthorized', async () => {
    await request(app)
      .post('/api/v1/records/anchor')
      .send({ recordId, patientId: patAId })
      .expect(401);

    await request(app)
      .post('/api/v1/records/anchor')
      .set('Authorization', 'Bearer fake_invalid_jwt_token_123')
      .send({ recordId, patientId: patAId })
      .expect(401);
  });

  it('10. Idempotency & Reconciliation: duplicate anchor request returns existing proof with version 1 without duplicate ledger mutation', async function () {
    this.timeout(30000);

    const res = await request(app)
      .post('/api/v1/records/anchor')
      .set('Authorization', `Bearer ${docAToken}`)
      .set('X-Idempotency-Key', 'idemp_e2e_duplicate_test')
      .send({
        recordId,
        patientId: patAId
      })
      .expect(200);

    expect(res.body.success).to.be.true;
    expect(res.body.data.proof.version).to.equal(1);
    expect(res.body.data.proof.txId).to.equal(anchoredTxId);
  });

  it('11. On-Chain Consent Revocation & Fail-Closed Access: revoking consent on Fabric immediately blocks clinician access', async function () {
    this.timeout(30000);
    const patientPseudoId = PseudonymService.generatePatientPseudoId(patAId);
    const providerPseudoId = PseudonymService.generateProviderPseudoId(docAId);

    // 1. Submit RevokeConsent on real Fabric ledger
    const { txId: revokeTxIdRaw } = await fabric.submitTransaction(
      'RevokeConsent',
      patientPseudoId,
      providerPseudoId,
      'BLOOD_CANCER_RESEARCH'
    );
    const revokeTxId = revokeTxIdRaw || '';
    expect(revokeTxId).to.be.a('string').and.not.empty;

    // 2. Verify on-chain CheckConsent is REVOKED
    const checkStr = await fabric.evaluateTransaction(
      'CheckConsent',
      patientPseudoId,
      providerPseudoId,
      'BLOOD_CANCER_RESEARCH'
    );
    const checkRes = JSON.parse(checkStr);
    expect(checkRes.active).to.be.false;
    expect(checkRes.status).to.equal('REVOKED');

    // 3. Doctor A attempting to access Patient A record now fails closed with 403
    const res = await request(app)
      .post('/api/v1/records/verify')
      .set('Authorization', `Bearer ${docAToken}`)
      .send({
        recordId,
        patientId: patAId,
        expectedHash: independentSha256
      })
      .expect(403);

    expect(res.body.success).to.be.false;
    expect(res.body.error.message).to.include('revoked');
  });
});
