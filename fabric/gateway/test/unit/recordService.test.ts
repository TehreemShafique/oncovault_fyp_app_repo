// test/unit/recordService.test.ts
import { expect } from 'chai';
import crypto from 'crypto';
import sinon from 'sinon';
import { RecordService, canonicalJsonStringify } from '../../src/services/recordService';
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

  const NURSE_USER: AuthenticatedUser = {
    uid: 'nurse-789',
    role: 'nurse',
    email: 'nurse@example.com'
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
      checkDoctorPatientConsent: sinon.stub(),
      checkActiveNurseAssignment: sinon.stub()
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

    it('should deterministically hash treatment task completions matching Cloud Functions schema', () => {
      const task1 = {
        taskId: 'task_001',
        planId: 'plan_100',
        patientId: 'pat_200',
        completedByNurseId: 'nurse_300',
        completedAtIso: '2026-10-17T14:30:00.000Z',
        executionRemarks: 'Infused over 2 hours'
      };
      const task2 = {
        executionRemarks: 'Infused over 2 hours',
        completedAtIso: '2026-10-17T14:30:00.000Z',
        performerUid: 'nurse_300',
        patientId: 'pat_200',
        planId: 'plan_100',
        taskId: 'task_001'
      };

      const hash1 = recordService.computeCanonicalTaskHash(task1);
      const hash2 = recordService.computeCanonicalTaskHash(task2);

      expect(hash1).to.equal(hash2);
      expect(hash1).to.match(/^[a-f0-9]{64}$/);
    });

    it('should deterministically hash treatment progress updates with Firestore Timestamp conversion', () => {
      const mockTimestamp = {
        toDate: () => new Date('2026-10-17T15:00:00.000Z')
      };
      const update1 = {
        updateId: 'upd_001',
        planId: 'plan_100',
        patientId: 'pat_200',
        authorUid: 'nurse_300',
        timestamp: mockTimestamp,
        clinicalSummary: 'Patient stable, blood count improving.',
        patientTolerance: 'well_tolerated',
        factualObservations: 'Vitals stable'
      };
      const update2 = {
        factualObservations: 'Vitals stable',
        patientTolerance: 'well_tolerated',
        clinicalSummary: 'Patient stable, blood count improving.',
        timestampIso: '2026-10-17T15:00:00.000Z',
        authorId: 'nurse_300',
        patientId: 'pat_200',
        planId: 'plan_100',
        updateId: 'upd_001'
      };

      const hash1 = recordService.computeCanonicalProgressHash(update1);
      const hash2 = recordService.computeCanonicalProgressHash(update2);

      expect(hash1).to.equal(hash2);
      expect(hash1).to.match(/^[a-f0-9]{64}$/);
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
      mockFabricGateway.evaluateTransaction.withArgs('GetRecordProof').callsFake(async (_name: string, key: string) => {
        throw { code: 2, details: [{ message: `chaincode response 500, Record '${key}' does not exist on ledger.` }] };
      });

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
    it('should return VERIFIED when binary report bytes match ledger proof (Test A)', async () => {
      mockFirebaseAdmin.getMedicalRecord.resolves({
        id: MOCK_RECORD_ID,
        patientId: PATIENT_USER.uid,
        fileUrl: 'gs://mock-bucket/records/sample.pdf',
        fileHash: EXPECTED_HASH
      });
      mockFirebaseAdmin.getFileBytes.withArgs('gs://mock-bucket/records/sample.pdf').resolves(MOCK_FILE_CONTENT);

      mockFabricGateway.evaluateTransaction.withArgs('GetRecordProof').resolves(JSON.stringify({
        recordId: 'rec_opaque_sample',
        sha256Hash: EXPECTED_HASH,
        version: 1,
        txId: 'tx-verified-999',
        timestamp: '2026-10-17T00:00:00Z',
        status: 'ACTIVE'
      }));
      mockFabricGateway.evaluateTransaction.withArgs('VerifyRecordHash').resolves(JSON.stringify({
        verified: true,
        status: 'VERIFIED',
        sha256Hash: EXPECTED_HASH
      }));

      const res = await recordService.verifyRecord(PATIENT_USER, MOCK_RECORD_ID, EXPECTED_HASH);

      expect(res.verified).to.be.true;
      expect(res.status).to.equal('VERIFIED');
      expect(res.targetHash).to.equal(EXPECTED_HASH);
    });

    it('should return TAMPERED_OR_MISMATCH when clinical field changes while stored fileHash remains unchanged (Test B)', async () => {
      // Attacker modified summary in Firestore, but left the old fileHash in place
      const initialRecord = {
        id: 'meta-rec-001',
        patientId: PATIENT_USER.uid,
        type: 'report',
        subtype: 'CBC',
        facility: 'Oncology Ward 3A',
        summary: 'Original uncorrupted clinical diagnosis: Remission Stage 1'
      };
      const originalCanonicalHash = recordService.computeCanonicalMetadataHash(initialRecord);

      // Now simulate unauthorized mutation of summary field in Firestore
      const tamperedRecord = {
        ...initialRecord,
        summary: 'TAMPERED: Altered diagnosis text Stage 4 Relapse',
        fileHash: originalCanonicalHash // Stored hash was NOT updated by attacker
      };

      mockFirebaseAdmin.getMedicalRecord.resolves(tamperedRecord);

      // Fabric ledger holds the original genuine proof
      mockFabricGateway.evaluateTransaction.withArgs('GetRecordProof').resolves(JSON.stringify({
        recordId: 'rec_opaque_meta',
        sha256Hash: originalCanonicalHash,
        version: 1,
        txId: 'tx-orig-anchor-111',
        timestamp: '2026-10-17T00:00:00Z',
        status: 'ACTIVE'
      }));

      // Fabric on-chain verification of the newly computed hash returns mismatch
      mockFabricGateway.evaluateTransaction.withArgs('VerifyRecordHash').resolves(JSON.stringify({
        verified: false,
        status: 'TAMPERED_OR_MISMATCH'
      }));

      // Client passes old fileHash, but gateway must recompute from current Firestore content and catch mismatch
      const res = await recordService.verifyRecord(PATIENT_USER, 'meta-rec-001', originalCanonicalHash);

      expect(res.verified).to.be.false;
      expect(res.status).to.equal('TAMPERED_OR_MISMATCH');
      expect(res.targetHash).to.not.equal(originalCanonicalHash);
      expect(res.message).to.include('differs from on-chain proof');
    });

    it('should return TAMPERED_OR_MISMATCH when both clinical content and stored fileHash are altered (Test C)', async () => {
      const originalRecord = {
        id: 'meta-rec-002',
        patientId: PATIENT_USER.uid,
        type: 'report',
        subtype: 'CBC',
        facility: 'Oncology Ward 3A',
        summary: 'Initial benign result'
      };
      const originalCanonicalHash = recordService.computeCanonicalMetadataHash(originalRecord);

      const tamperedRecord: Record<string, any> = {
        ...originalRecord,
        summary: 'FORGED: Critical relapse detected without physician authorization'
      };
      const forgedHash = recordService.computeCanonicalMetadataHash(tamperedRecord);
      tamperedRecord['fileHash'] = forgedHash; // Attacker updated fileHash to match their forged text

      mockFirebaseAdmin.getMedicalRecord.resolves(tamperedRecord);

      // Ledger has original proof
      mockFabricGateway.evaluateTransaction.withArgs('GetRecordProof').resolves(JSON.stringify({
        recordId: 'rec_opaque_meta_2',
        sha256Hash: originalCanonicalHash,
        version: 1,
        txId: 'tx-ledger-proof-222',
        timestamp: '2026-10-17T00:00:00Z',
        status: 'ACTIVE'
      }));

      mockFabricGateway.evaluateTransaction.withArgs('VerifyRecordHash').resolves(JSON.stringify({
        verified: false,
        status: 'TAMPERED_OR_MISMATCH'
      }));

      const res = await recordService.verifyRecord(PATIENT_USER, 'meta-rec-002', forgedHash);

      expect(res.verified).to.be.false;
      expect(res.status).to.equal('TAMPERED_OR_MISMATCH');
      expect(res.targetHash).to.equal(forgedHash);
    });

    it('should return TAMPERED_OR_MISMATCH when storage file bytes are altered (Test D)', async () => {
      const tamperedBytes = Buffer.from('CORRUPTED_OR_TAMPERED_FILE_BYTES_IN_STORAGE');
      const tamperedBytesHash = crypto.createHash('sha256').update(tamperedBytes).digest('hex').toLowerCase();

      mockFirebaseAdmin.getMedicalRecord.resolves({
        id: MOCK_RECORD_ID,
        patientId: PATIENT_USER.uid,
        fileUrl: 'gs://mock-bucket/records/sample.pdf',
        fileHash: EXPECTED_HASH // Old hash in Firestore
      });
      // Storage returns tampered bytes
      mockFirebaseAdmin.getFileBytes.withArgs('gs://mock-bucket/records/sample.pdf').resolves(tamperedBytes);

      mockFabricGateway.evaluateTransaction.withArgs('GetRecordProof').resolves(JSON.stringify({
        recordId: 'rec_opaque_sample',
        sha256Hash: EXPECTED_HASH,
        version: 1,
        txId: 'tx-sample-333',
        status: 'ACTIVE'
      }));

      mockFabricGateway.evaluateTransaction.withArgs('VerifyRecordHash').resolves(JSON.stringify({
        verified: false,
        status: 'TAMPERED_OR_MISMATCH'
      }));

      const res = await recordService.verifyRecord(PATIENT_USER, MOCK_RECORD_ID);

      expect(res.verified).to.be.false;
      expect(res.status).to.equal('TAMPERED_OR_MISMATCH');
      expect(res.targetHash).to.equal(tamperedBytesHash);
    });

    it('should return TAMPERED_OR_MISMATCH when storage file is missing or unreadable', async () => {
      mockFirebaseAdmin.getMedicalRecord.resolves({
        id: MOCK_RECORD_ID,
        patientId: PATIENT_USER.uid,
        fileUrl: 'gs://mock-bucket/deleted.pdf',
        fileHash: EXPECTED_HASH
      });
      mockFirebaseAdmin.getFileBytes.rejects(new Error('File not found in storage bucket'));

      const res = await recordService.verifyRecord(PATIENT_USER, MOCK_RECORD_ID);

      expect(res.verified).to.be.false;
      expect(res.status).to.equal('TAMPERED_OR_MISMATCH');
      expect(res.message).to.include('Authoritative storage file is missing or unreadable');
    });

    it('should verify metadata record under its canonical hashing format (Test E)', async () => {
      const validMetaRecord = {
        id: 'legacy-meta-001',
        patientId: PATIENT_USER.uid,
        type: 'report',
        subtype: 'PATHOLOGY',
        facility: 'Memorial Oncology',
        summary: 'Bone marrow aspirate indicates complete molecular response'
      };
      const canonicalHash = recordService.computeCanonicalMetadataHash(validMetaRecord);

      mockFirebaseAdmin.getMedicalRecord.resolves({
        ...validMetaRecord,
        fileHash: canonicalHash
      });

      mockFabricGateway.evaluateTransaction.withArgs('GetRecordProof').resolves(JSON.stringify({
        recordId: 'rec_opaque_legacy',
        sha256Hash: canonicalHash,
        version: 1,
        txId: 'tx-legacy-444',
        status: 'ACTIVE'
      }));
      mockFabricGateway.evaluateTransaction.withArgs('VerifyRecordHash').resolves(JSON.stringify({
        verified: true,
        status: 'VERIFIED'
      }));

      const res = await recordService.verifyRecord(PATIENT_USER, 'legacy-meta-001');

      expect(res.verified).to.be.true;
      expect(res.status).to.equal('VERIFIED');
      expect(res.targetHash).to.equal(canonicalHash);
    });

    it('should return NOT_ANCHORED when record does not exist on ledger (Test F)', async () => {
      mockFirebaseAdmin.getMedicalRecord.resolves({
        id: MOCK_RECORD_ID,
        patientId: PATIENT_USER.uid,
        fileUrl: 'gs://mock-bucket/sample.pdf',
        fileHash: EXPECTED_HASH
      });
      mockFirebaseAdmin.getFileBytes.resolves(MOCK_FILE_CONTENT);

      mockFabricGateway.evaluateTransaction.withArgs('GetRecordProof').rejects(new Error('Record rec_opaque_sample does not exist on ledger.'));

      const res = await recordService.verifyRecord(PATIENT_USER, MOCK_RECORD_ID, EXPECTED_HASH);

      expect(res.verified).to.be.false;
      expect(res.status).to.equal('NOT_ANCHORED');
      expect(res.message).to.include('Record has not been anchored on the blockchain ledger');
    });

    it('should return VERIFICATION_UNAVAILABLE on transient Fabric error without reporting fake mismatch (Test G)', async () => {
      mockFirebaseAdmin.getMedicalRecord.resolves({
        id: MOCK_RECORD_ID,
        patientId: PATIENT_USER.uid,
        fileUrl: 'gs://mock-bucket/sample.pdf',
        fileHash: EXPECTED_HASH
      });
      mockFirebaseAdmin.getFileBytes.resolves(MOCK_FILE_CONTENT);

      mockFabricGateway.evaluateTransaction.withArgs('GetRecordProof').rejects(new Error('503 Service Unavailable: peer connection refused'));

      const res = await recordService.verifyRecord(PATIENT_USER, MOCK_RECORD_ID);

      expect(res.verified).to.be.false;
      expect(res.status).to.equal('VERIFICATION_UNAVAILABLE');
      expect(res.message).to.include('Ledger verification unavailable');
    });

    it('should reject unauthorized caller attempting to verify another patient record (Test H)', async () => {
      const OTHER_PATIENT: AuthenticatedUser = { uid: 'unauthorized-intruder', role: 'patient', email: 'intruder@evil.com' };
      mockFirebaseAdmin.getMedicalRecord.resolves({
        id: MOCK_RECORD_ID,
        patientId: 'victim-patient-123',
        fileUrl: 'gs://mock-bucket/records/sample.pdf'
      });

      try {
        await recordService.verifyRecord(OTHER_PATIENT, MOCK_RECORD_ID);
        expect.fail('Should have thrown authorization exception');
      } catch (err: any) {
        expect(err.message).to.include('Patients may only access their own medical records');
      }
    });

    it('should prevent client-supplied fake hash from bypassing verification when content is tampered', async () => {
      // Clinical content was altered on server, but attacker sends clientSpecifiedHash = originalLedgerHash
      const tamperedRecord = {
        id: 'meta-rec-003',
        patientId: PATIENT_USER.uid,
        type: 'report',
        summary: 'Tampered summary'
      };
      const actualHash = recordService.computeCanonicalMetadataHash(tamperedRecord);
      const originalLedgerHash = '1111111111111111111111111111111111111111111111111111111111111111';

      mockFirebaseAdmin.getMedicalRecord.resolves(tamperedRecord);
      mockFabricGateway.evaluateTransaction.withArgs('GetRecordProof').resolves(JSON.stringify({
        recordId: 'rec_opaque_3',
        sha256Hash: originalLedgerHash,
        version: 1,
        status: 'ACTIVE'
      }));

      // Attacker passes the ledger's hash in clientSpecifiedHash hoping to fool verification
      const res = await recordService.verifyRecord(PATIENT_USER, 'meta-rec-003', originalLedgerHash);

      expect(res.verified).to.be.false;
      expect(res.status).to.equal('TAMPERED_OR_MISMATCH');
      expect(res.targetHash).to.equal(actualHash);
      expect(res.message).to.include('Authoritative clinical content SHA-256 digest differs from on-chain proof');
    });
  });

  describe('Clinical Notes Anchoring & Nurse Authorization', () => {
    it('should reject anchoring clinical record if it is in DRAFT status', async () => {
      mockFirebaseAdmin.getMedicalRecord.resolves({
        id: 'note-draft-001',
        patientId: 'patient-123',
        status: 'DRAFT',
        isClinicalNote: true
      });

      try {
        await recordService.anchorRecord(PATIENT_USER, 'note-draft-001');
        expect.fail('Should have thrown an error');
      } catch (err: any) {
        expect(err.message).to.include('because it is in DRAFT status');
      }
    });

    it('should successfully anchor clinical note with canonical hashing for assigned nurse', async () => {
      const mockNote = {
        id: 'note-sub-001',
        patientId: 'patient-123',
        authorUid: NURSE_USER.uid,
        status: 'SUBMITTED',
        noteType: 'NURSING_NOTE',
        clinicalText: 'Patient vitals stable.',
        rawTranscript: 'patient vitals stable',
        structuredSummary: { condition: 'stable' },
        createdAtIso: '2026-10-17T00:00:00.000Z',
        isClinicalNote: true
      };

      mockFirebaseAdmin.getMedicalRecord.resolves(mockNote);
      mockFirebaseAdmin.checkActiveNurseAssignment.resolves(true);
      mockFabricGateway.evaluateTransaction.withArgs('GetRecordProof').callsFake(async (_name: string, key: string) => {
        throw { code: 2, details: [{ message: `chaincode response 500, Record '${key}' does not exist on ledger.` }] };
      });

      const noteHash = recordService.computeCanonicalClinicalNoteHash(mockNote);
      expect(noteHash).to.have.lengthOf(64);

      mockFabricGateway.submitTransaction.resolves({
        result: JSON.stringify({
          recordId: 'rec_opaque_note',
          sha256Hash: noteHash,
          version: 1,
          txId: 'tx-note-anchor-001',
          timestamp: '2026-10-17T00:00:05.000Z'
        }),
        txId: 'tx-note-anchor-001'
      });

      const res = await recordService.anchorRecord(NURSE_USER, 'note-sub-001', undefined, undefined, 'patient-123');
      expect(res.proof.txId).to.equal('tx-note-anchor-001');
      expect(res.fileHash).to.equal(noteHash);
      expect(mockFabricGateway.submitTransaction.calledOnce).to.be.true;

      const submitArgs = mockFabricGateway.submitTransaction.firstCall.args;
      expect(submitArgs[0]).to.equal('AnchorRecordHash');
      expect(submitArgs[2]).to.equal(noteHash);
      const metadata = JSON.parse(submitArgs[3]);
      expect(metadata.documentType).to.equal('CLINICAL_NOTE');
    });

    it('should reject nurse from anchoring when not assigned to patient', async () => {
      mockFirebaseAdmin.getMedicalRecord.resolves({
        id: 'note-sub-002',
        patientId: 'patient-unassigned',
        status: 'SUBMITTED',
        isClinicalNote: true
      });
      mockFirebaseAdmin.checkActiveNurseAssignment.resolves(false);

      try {
        await recordService.anchorRecord(NURSE_USER, 'note-sub-002', undefined, undefined, 'patient-unassigned');
        expect.fail('Should have thrown an error');
      } catch (err: any) {
        expect(err.message).to.include('Access Denied: Nurse does not hold active assignment');
      }
    });

    it('should verify clinical note integrity without fileUrl using canonical note hash', async () => {
      const mockNote = {
        id: 'note-sub-001',
        patientId: PATIENT_USER.uid,
        authorUid: 'nurse-789',
        status: 'SUBMITTED',
        noteType: 'NURSING_NOTE',
        clinicalText: 'Patient vitals stable.',
        rawTranscript: 'patient vitals stable',
        structuredSummary: { condition: 'stable' },
        createdAtIso: '2026-10-17T00:00:00.000Z',
        isClinicalNote: true
      };

      const noteHash = recordService.computeCanonicalClinicalNoteHash(mockNote);
      mockFirebaseAdmin.getMedicalRecord.resolves(mockNote);

      mockFabricGateway.evaluateTransaction.withArgs('VerifyRecordHash').resolves(JSON.stringify({
        verified: true,
        status: 'VERIFIED',
        sha256Hash: noteHash
      }));
      mockFabricGateway.evaluateTransaction.withArgs('GetRecordProof').resolves(JSON.stringify({
        version: 1,
        txId: 'tx-note-verified-001',
        sha256Hash: noteHash
      }));

      const res = await recordService.verifyRecord(PATIENT_USER, 'note-sub-001');
      expect(res.verified).to.be.true;
      expect(res.status).to.equal('VERIFIED');
      expect(res.targetHash).to.equal(noteHash);
    });
  });

  describe('Prescription Integrity Hashing (Schema 2.0 & Legacy Schema 1.0)', () => {
    const BASE_PRESCRIPTION = {
      id: 'rx_synthetic_001',
      patientId: 'patient-123',
      type: 'prescription',
      subtype: 'Digital Prescription',
      facility: 'OncoVault Oncology Center',
      summary: 'Cisplatin 500mg Oral Twice Daily',
      doctorId: 'doc_oncologist_99',
      doctorName: 'Dr. Sarah Connor',
      dateIso: '2026-10-20T10:00:00.000Z',
      additionalNotes: 'Hydrate well with 2L water daily',
      followUpInstructions: 'Return in 14 days for renal panel',
      prescriptionData: {
        drugs: [
          {
            name: 'Cisplatin',
            dosage: '500mg',
            frequency: 'Twice Daily',
            duration: '14 days',
            route: 'Oral',
            instructions: 'Take after meals'
          }
        ]
      }
    };

    it('1. should deterministically compute identical hash regardless of object property ordering', () => {
      const rxReordered = {
        summary: BASE_PRESCRIPTION.summary,
        type: BASE_PRESCRIPTION.type,
        facility: BASE_PRESCRIPTION.facility,
        patientId: BASE_PRESCRIPTION.patientId,
        id: BASE_PRESCRIPTION.id,
        prescriptionData: {
          drugs: [
            {
              instructions: 'Take after meals',
              route: 'Oral',
              duration: '14 days',
              frequency: 'Twice Daily',
              dosage: '500mg',
              name: 'Cisplatin'
            }
          ]
        },
        doctorName: BASE_PRESCRIPTION.doctorName,
        doctorId: BASE_PRESCRIPTION.doctorId,
        dateIso: BASE_PRESCRIPTION.dateIso,
        subtype: BASE_PRESCRIPTION.subtype,
        followUpInstructions: BASE_PRESCRIPTION.followUpInstructions,
        additionalNotes: BASE_PRESCRIPTION.additionalNotes
      };

      const hash1 = recordService.computeCanonicalPrescriptionHash(BASE_PRESCRIPTION);
      const hash2 = recordService.computeCanonicalPrescriptionHash(rxReordered);
      expect(hash1).to.equal(hash2);
      expect(hash1).to.have.lengthOf(64);
    });

    it('2. should alter hash when medication name changes (Cisplatin -> Carboplatin)', () => {
      const tampered = JSON.parse(JSON.stringify(BASE_PRESCRIPTION));
      tampered.prescriptionData.drugs[0].name = 'Carboplatin';

      const hOriginal = recordService.computeCanonicalPrescriptionHash(BASE_PRESCRIPTION);
      const hTampered = recordService.computeCanonicalPrescriptionHash(tampered);
      expect(hOriginal).to.not.equal(hTampered);
    });

    it('3. should alter hash when medication dosage changes (500mg -> 100mg)', () => {
      const tampered = JSON.parse(JSON.stringify(BASE_PRESCRIPTION));
      tampered.prescriptionData.drugs[0].dosage = '100mg';

      const hOriginal = recordService.computeCanonicalPrescriptionHash(BASE_PRESCRIPTION);
      const hTampered = recordService.computeCanonicalPrescriptionHash(tampered);
      expect(hOriginal).to.not.equal(hTampered);
    });

    it('4. should alter hash when medication frequency changes (Twice Daily -> Once Daily)', () => {
      const tampered = JSON.parse(JSON.stringify(BASE_PRESCRIPTION));
      tampered.prescriptionData.drugs[0].frequency = 'Once Daily';

      const hOriginal = recordService.computeCanonicalPrescriptionHash(BASE_PRESCRIPTION);
      const hTampered = recordService.computeCanonicalPrescriptionHash(tampered);
      expect(hOriginal).to.not.equal(hTampered);
    });

    it('5. should alter hash when medication duration changes (14 days -> 28 days)', () => {
      const tampered = JSON.parse(JSON.stringify(BASE_PRESCRIPTION));
      tampered.prescriptionData.drugs[0].duration = '28 days';

      const hOriginal = recordService.computeCanonicalPrescriptionHash(BASE_PRESCRIPTION);
      const hTampered = recordService.computeCanonicalPrescriptionHash(tampered);
      expect(hOriginal).to.not.equal(hTampered);
    });

    it('6. should alter hash when administration route changes (Oral -> IV)', () => {
      const tampered = JSON.parse(JSON.stringify(BASE_PRESCRIPTION));
      tampered.prescriptionData.drugs[0].route = 'IV';

      const hOriginal = recordService.computeCanonicalPrescriptionHash(BASE_PRESCRIPTION);
      const hTampered = recordService.computeCanonicalPrescriptionHash(tampered);
      expect(hOriginal).to.not.equal(hTampered);
    });

    it('7. should alter hash when medication instructions change', () => {
      const tampered = JSON.parse(JSON.stringify(BASE_PRESCRIPTION));
      tampered.prescriptionData.drugs[0].instructions = 'Take on empty stomach';

      const hOriginal = recordService.computeCanonicalPrescriptionHash(BASE_PRESCRIPTION);
      const hTampered = recordService.computeCanonicalPrescriptionHash(tampered);
      expect(hOriginal).to.not.equal(hTampered);
    });

    it('8. should alter hash when a second drug is added to multi-drug array', () => {
      const multiDrug = JSON.parse(JSON.stringify(BASE_PRESCRIPTION));
      multiDrug.prescriptionData.drugs.push({
        name: 'Ondansetron',
        dosage: '8mg',
        frequency: 'Every 8 hours PRN',
        duration: '3 days',
        route: 'Oral',
        instructions: 'For nausea'
      });

      const hOriginal = recordService.computeCanonicalPrescriptionHash(BASE_PRESCRIPTION);
      const hMulti = recordService.computeCanonicalPrescriptionHash(multiDrug);
      expect(hOriginal).to.not.equal(hMulti);
    });

    it('9. should alter hash when prescribing doctor name changes', () => {
      const tampered = JSON.parse(JSON.stringify(BASE_PRESCRIPTION));
      tampered.doctorName = 'Dr. Gregory House';

      const hOriginal = recordService.computeCanonicalPrescriptionHash(BASE_PRESCRIPTION);
      const hTampered = recordService.computeCanonicalPrescriptionHash(tampered);
      expect(hOriginal).to.not.equal(hTampered);
    });

    it('10. should alter hash when prescribing doctor ID changes', () => {
      const tampered = JSON.parse(JSON.stringify(BASE_PRESCRIPTION));
      tampered.doctorId = 'doc_impostor_66';

      const hOriginal = recordService.computeCanonicalPrescriptionHash(BASE_PRESCRIPTION);
      const hTampered = recordService.computeCanonicalPrescriptionHash(tampered);
      expect(hOriginal).to.not.equal(hTampered);
    });

    it('11. should alter hash when prescription date changes', () => {
      const tampered = JSON.parse(JSON.stringify(BASE_PRESCRIPTION));
      tampered.dateIso = '2026-10-21T10:00:00.000Z';

      const hOriginal = recordService.computeCanonicalPrescriptionHash(BASE_PRESCRIPTION);
      const hTampered = recordService.computeCanonicalPrescriptionHash(tampered);
      expect(hOriginal).to.not.equal(hTampered);
    });

    it('12. should verify legacy Schema 1.0 prescription with status LEGACY_METADATA_VERIFIED', async () => {
      const legacyRecord = JSON.parse(JSON.stringify(BASE_PRESCRIPTION));
      // In Schema 1.0, only metadata was anchored
      const legacyHash = recordService.computeCanonicalMetadataHash(legacyRecord);

      mockFirebaseAdmin.getMedicalRecord.resolves(legacyRecord);
      mockFabricGateway.evaluateTransaction.withArgs('GetRecordProof').resolves(JSON.stringify({
        recordId: 'rx_opaque_legacy_001',
        sha256Hash: legacyHash,
        version: 1,
        txId: 'tx-legacy-rx-001',
        timestamp: '2026-10-17T00:00:00.000Z',
        metadata: {
          documentType: 'PRESCRIPTION',
          schemaVersion: '1.0'
        }
      }));
      mockFabricGateway.evaluateTransaction.withArgs('VerifyRecordHash').resolves(JSON.stringify({
        verified: true,
        status: 'VERIFIED',
        sha256Hash: legacyHash
      }));

      const res = await recordService.verifyRecord(PATIENT_USER, BASE_PRESCRIPTION.id);
      expect(res.verified).to.be.true;
      expect(res.status).to.equal('LEGACY_METADATA_VERIFIED');
      expect(res.schemaVersion).to.equal('1.0');
      expect(res.comprehensiveDrugIntegrity).to.be.false;
      expect(res.message).to.include('Legacy metadata verified against ledger proof');
    });

    it('13. should detect tampering on legacy Schema 1.0 prescription when metadata is altered', async () => {
      const tamperedLegacy = JSON.parse(JSON.stringify(BASE_PRESCRIPTION));
      tamperedLegacy.summary = 'Altered summary not on ledger';
      const originalLegacyHash = recordService.computeCanonicalMetadataHash(BASE_PRESCRIPTION);

      mockFirebaseAdmin.getMedicalRecord.resolves(tamperedLegacy);
      mockFabricGateway.evaluateTransaction.withArgs('GetRecordProof').resolves(JSON.stringify({
        recordId: 'rx_opaque_legacy_001',
        sha256Hash: originalLegacyHash,
        version: 1,
        txId: 'tx-legacy-rx-001',
        metadata: {
          documentType: 'PRESCRIPTION',
          schemaVersion: '1.0'
        }
      }));

      const res = await recordService.verifyRecord(PATIENT_USER, BASE_PRESCRIPTION.id);
      expect(res.verified).to.be.false;
      expect(res.status).to.equal('TAMPERED_OR_MISMATCH');
      expect(res.schemaVersion).to.equal('1.0');
      expect(res.comprehensiveDrugIntegrity).to.be.false;
    });

    it('14. should verify Schema 2.0 prescription as VERIFIED with comprehensiveDrugIntegrity = true', async () => {
      const schema2Record = JSON.parse(JSON.stringify(BASE_PRESCRIPTION));
      const schema2Hash = recordService.computeCanonicalPrescriptionHash(schema2Record);

      mockFirebaseAdmin.getMedicalRecord.resolves(schema2Record);
      mockFabricGateway.evaluateTransaction.withArgs('GetRecordProof').resolves(JSON.stringify({
        recordId: 'rx_opaque_s2_001',
        sha256Hash: schema2Hash,
        version: 1,
        txId: 'tx-s2-rx-001',
        timestamp: '2026-10-20T12:00:00.000Z',
        metadata: {
          documentType: 'PRESCRIPTION',
          schemaVersion: '2.0'
        }
      }));
      mockFabricGateway.evaluateTransaction.withArgs('VerifyRecordHash').resolves(JSON.stringify({
        verified: true,
        status: 'VERIFIED',
        sha256Hash: schema2Hash
      }));

      const res = await recordService.verifyRecord(PATIENT_USER, BASE_PRESCRIPTION.id);
      expect(res.verified).to.be.true;
      expect(res.status).to.equal('VERIFIED');
      expect(res.schemaVersion).to.equal('2.0');
      expect(res.comprehensiveDrugIntegrity).to.be.true;
      expect(res.message).to.include('immutable Hyperledger Fabric ledger');
    });

    it('15. should detect tampering on Schema 2.0 prescription when drug dosage is altered', async () => {
      const tamperedRecord = JSON.parse(JSON.stringify(BASE_PRESCRIPTION));
      // Clinical tamper: change drug dosage while leaving metadata/summary untouched
      tamperedRecord.prescriptionData.drugs[0].dosage = '1000mg';
      const honestSchema2Hash = recordService.computeCanonicalPrescriptionHash(BASE_PRESCRIPTION);

      mockFirebaseAdmin.getMedicalRecord.resolves(tamperedRecord);
      mockFabricGateway.evaluateTransaction.withArgs('GetRecordProof').resolves(JSON.stringify({
        recordId: 'rx_opaque_s2_001',
        sha256Hash: honestSchema2Hash,
        version: 1,
        txId: 'tx-s2-rx-001',
        metadata: {
          documentType: 'PRESCRIPTION',
          schemaVersion: '2.0'
        }
      }));

      const res = await recordService.verifyRecord(PATIENT_USER, BASE_PRESCRIPTION.id);
      expect(res.verified).to.be.false;
      expect(res.status).to.equal('TAMPERED_OR_MISMATCH');
      expect(res.schemaVersion).to.equal('2.0');
      expect(res.comprehensiveDrugIntegrity).to.be.false;
      expect(res.message).to.include('Authoritative clinical content SHA-256 digest differs from on-chain proof');
    });

    it('16. (Anti-IDOR Gate) should reject unauthorized caller attempting to verify another patient prescription', async () => {
      const INTRUDER: AuthenticatedUser = { uid: 'intruder-999', role: 'patient', email: 'intruder@evil.com' };
      mockFirebaseAdmin.getMedicalRecord.resolves(BASE_PRESCRIPTION);

      try {
        await recordService.verifyRecord(INTRUDER, BASE_PRESCRIPTION.id);
        expect.fail('Should have rejected unauthorized patient');
      } catch (err: any) {
        expect(err.message).to.include('Patients may only access their own medical records');
      }
    });
  });

});
