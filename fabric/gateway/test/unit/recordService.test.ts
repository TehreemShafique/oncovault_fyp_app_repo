// test/unit/recordService.test.ts
import { expect } from 'chai';
import crypto from 'crypto';
import sinon from 'sinon';
import { RecordService } from '../../src/services/recordService';
import { AuthenticatedUser } from '../../src/types';

describe('RecordService Unit Tests', () => {
  let recordService: RecordService;
  let mockFabricGateway: any;
  let mockFirebaseAdmin: any;
  let mockReconciliation: any;

  const PATIENT_USER: AuthenticatedUser = {
    uid: 'patient-123',
    role: 'patient',
    email: 'patient@example.com'
  };

  const DOCTOR_USER: AuthenticatedUser = {
    uid: 'doctor-456',
    role: 'doctor',
    email: 'doctor@example.com'
  };

  const MOCK_RECORD_ID = 'rec-sample-001';
  const MOCK_FILE_CONTENT = Buffer.from('PDF_SAMPLE_CLINICAL_CONTENT_LEUKEMIA_BIOPSY_PANEL');
  const EXPECTED_HASH = crypto.createHash('sha256').update(MOCK_FILE_CONTENT).digest('hex').toLowerCase();

  beforeEach(() => {
    mockFabricGateway = {
      evaluateTransaction: sinon.stub(),
      submitTransaction: sinon.stub()
    };

    mockFirebaseAdmin = {
      getMedicalRecord: sinon.stub(),
      getFileBytes: sinon.stub(),
      updateRecordProof: sinon.stub().resolves(),
      checkDoctorPatientConsent: sinon.stub()
    };

    mockReconciliation = {
      acquireLock: sinon.stub().returns(true),
      releaseLock: sinon.stub(),
      startOperation: sinon.stub().resolves({}),
      markCommitted: sinon.stub().resolves({}),
      markStatus: sinon.stub().resolves({}),
      getOperationAsync: sinon.stub().resolves(undefined)
    };

    recordService = new RecordService(mockFabricGateway, mockFirebaseAdmin, mockReconciliation);
  });

  describe('Server-side Binary SHA-256 & Canonical Hashing', () => {
    it('should calculate accurate SHA-256 digest from binary bytes', () => {
      const hash = recordService.computeSha256(MOCK_FILE_CONTENT);
      expect(hash).to.equal(EXPECTED_HASH);
      expect(hash).to.have.lengthOf(64);
    });

    it('should deterministically hash metadata-only clinical records', () => {
      const record1 = { id: 'rec-1', patientId: 'p-1', type: 'report', summary: 'Normal blood count' };
      const record2 = { summary: 'Normal blood count', type: 'report', patientId: 'p-1', id: 'rec-1' };

      const hash1 = recordService.computeCanonicalMetadataHash(record1);
      const hash2 = recordService.computeCanonicalMetadataHash(record2);

      expect(hash1).to.equal(hash2);
      expect(hash1).to.have.lengthOf(64);
    });
  });

  describe('Record Anchoring', () => {
    it('should successfully anchor record with verified storage bytes and update Firestore proof', async () => {
      mockFirebaseAdmin.getMedicalRecord.resolves({
        id: MOCK_RECORD_ID,
        patientId: PATIENT_USER.uid,
        fileUrl: 'gs://oncovault-8cbbc.firebasestorage.app/records/patient-123/biopsy.pdf',
        type: 'report'
      });
      mockFirebaseAdmin.getFileBytes.resolves(MOCK_FILE_CONTENT);

      // Ledger has no existing proof for this key
      mockFabricGateway.evaluateTransaction.withArgs('GetRecordProof').rejects(new Error('Record not found'));

      // Ledger submits AnchorRecordHash
      const mockChaincodeProof = {
        recordId: 'rec_opaque_test',
        sha256Hash: EXPECTED_HASH,
        version: 1,
        txId: 'tx-fabric-live-11111',
        timestamp: '2026-10-16T12:00:00Z',
        status: 'ACTIVE'
      };
      mockFabricGateway.submitTransaction.resolves({
        result: JSON.stringify(mockChaincodeProof),
        txId: 'tx-fabric-live-11111'
      });

      const res = await recordService.anchorRecord(PATIENT_USER, MOCK_RECORD_ID);

      expect(res.fileHash).to.equal(EXPECTED_HASH);
      expect(res.proof.txId).to.equal('tx-fabric-live-11111');
      expect(mockFirebaseAdmin.updateRecordProof.calledOnce).to.be.true;
      expect(mockReconciliation.markCommitted.calledOnce).to.be.true;
    });

    it('should reject anchoring when clinician does not hold active patient consent', async () => {
      mockFirebaseAdmin.getMedicalRecord.resolves({
        id: MOCK_RECORD_ID,
        patientId: 'patient-other',
        fileUrl: 'gs://bucket/file.pdf',
        type: 'report'
      });
      mockFirebaseAdmin.checkDoctorPatientConsent.resolves(false); // No consent!

      try {
        await recordService.anchorRecord(DOCTOR_USER, MOCK_RECORD_ID);
        expect.fail('Should have rejected unauthorized clinician');
      } catch (err: any) {
        expect(err.message).to.include('Clinician does not hold active patient consent');
      }
    });

    it('should handle idempotent re-anchoring when hash is already anchored on ledger', async () => {
      mockFirebaseAdmin.getMedicalRecord.resolves({
        id: MOCK_RECORD_ID,
        patientId: PATIENT_USER.uid,
        fileUrl: 'gs://bucket/file.pdf',
        type: 'report'
      });
      mockFirebaseAdmin.getFileBytes.resolves(MOCK_FILE_CONTENT);

      // Ledger already has identical proof
      const existingProof = {
        recordId: 'rec_opaque_test',
        sha256Hash: EXPECTED_HASH,
        version: 1,
        txId: 'tx-existing-12345',
        timestamp: '2026-10-16T10:00:00Z',
        status: 'ACTIVE'
      };
      mockFabricGateway.evaluateTransaction.withArgs('GetRecordProof').resolves(JSON.stringify(existingProof));

      const res = await recordService.anchorRecord(PATIENT_USER, MOCK_RECORD_ID);

      expect(res.proof.txId).to.equal('tx-existing-12345');
      // Did not invoke a duplicate mutation on chaincode!
      expect(mockFabricGateway.submitTransaction.called).to.be.false;
    });

    it('should fail closed when on-chain consent is revoked on Fabric ledger', async () => {
      mockFirebaseAdmin.getMedicalRecord.resolves({
        id: MOCK_RECORD_ID,
        patientId: 'patient-other',
        fileUrl: 'gs://bucket/file.pdf',
        type: 'report'
      });
      // Ledger explicitly reports REVOKED
      mockFabricGateway.evaluateTransaction.withArgs('CheckConsent').resolves(JSON.stringify({ active: false, status: 'REVOKED' }));
      // Firestore projection says granted (outdated projection)
      mockFirebaseAdmin.checkDoctorPatientConsent.resolves(true);

      try {
        await recordService.anchorRecord(DOCTOR_USER, MOCK_RECORD_ID);
        expect.fail('Should have failed closed due to on-chain revocation');
      } catch (err: any) {
        expect(err.message).to.include('Patient consent has been revoked or is inactive');
      }
    });

    it('should recover from prior COMMITTED durable operation across process restart without duplicate ledger mutation', async () => {
      mockFirebaseAdmin.getMedicalRecord.resolves({
        id: MOCK_RECORD_ID,
        patientId: PATIENT_USER.uid,
        fileUrl: 'gs://bucket/file.pdf',
        type: 'report'
      });
      mockFirebaseAdmin.getFileBytes.resolves(MOCK_FILE_CONTENT);

      // Prior operation in Firestore from before process restart
      mockReconciliation.getOperationAsync.resolves({
        operationId: 'op_prior_restarted',
        status: 'COMMITTED',
        txId: 'tx-prior-recovered'
      });

      const existingProof = {
        recordId: 'rec_opaque_test',
        sha256Hash: EXPECTED_HASH,
        version: 1,
        txId: 'tx-prior-recovered',
        timestamp: '2026-10-16T10:00:00Z',
        status: 'ACTIVE'
      };
      mockFabricGateway.evaluateTransaction.withArgs('GetRecordProof').resolves(JSON.stringify(existingProof));

      const res = await recordService.anchorRecord(PATIENT_USER, MOCK_RECORD_ID);

      expect(res.proof.txId).to.equal('tx-prior-recovered');
      expect(mockFabricGateway.submitTransaction.called).to.be.false;
    });
  });

  describe('Record Verification', () => {
    it('should return VERIFIED when hash matches on ledger', async () => {
      mockFirebaseAdmin.getMedicalRecord.resolves({
        id: MOCK_RECORD_ID,
        patientId: PATIENT_USER.uid,
        fileHash: EXPECTED_HASH
      });

      mockFabricGateway.evaluateTransaction.withArgs('VerifyRecordHash').resolves(JSON.stringify({
        verified: true,
        status: 'VERIFIED',
        sha256Hash: EXPECTED_HASH
      }));
      mockFabricGateway.evaluateTransaction.withArgs('GetRecordProof').resolves(JSON.stringify({
        version: 1,
        txId: 'tx-verified-999'
      }));

      const res = await recordService.verifyRecord(PATIENT_USER, MOCK_RECORD_ID, EXPECTED_HASH);

      expect(res.verified).to.be.true;
      expect(res.status).to.equal('VERIFIED');
    });

    it('should return TAMPERED_OR_MISMATCH when hash does not match ledger', async () => {
      const tamperedHash = 'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';
      mockFirebaseAdmin.getMedicalRecord.resolves({
        id: MOCK_RECORD_ID,
        patientId: PATIENT_USER.uid,
        fileHash: tamperedHash
      });

      mockFabricGateway.evaluateTransaction.withArgs('VerifyRecordHash').resolves(JSON.stringify({
        verified: false,
        status: 'TAMPERED_OR_MISMATCH'
      }));

      const res = await recordService.verifyRecord(PATIENT_USER, MOCK_RECORD_ID, tamperedHash);

      expect(res.verified).to.be.false;
      expect(res.status).to.equal('TAMPERED_OR_MISMATCH');
    });

    it('should return NOT_ANCHORED when record does not exist on ledger', async () => {
      mockFirebaseAdmin.getMedicalRecord.resolves({
        id: MOCK_RECORD_ID,
        patientId: PATIENT_USER.uid,
        fileHash: EXPECTED_HASH
      });

      mockFabricGateway.evaluateTransaction.withArgs('VerifyRecordHash').rejects(new Error('Record not found on ledger'));

      const res = await recordService.verifyRecord(PATIENT_USER, MOCK_RECORD_ID, EXPECTED_HASH);

      expect(res.verified).to.be.false;
      expect(res.status).to.equal('NOT_ANCHORED');
    });
  });
});
