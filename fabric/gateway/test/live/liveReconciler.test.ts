// test/live/liveReconciler.test.ts
import { expect } from 'chai';
import sinon from 'sinon';
import crypto from 'crypto';
import { FabricGatewayService } from '../../src/services/fabricGateway';
import { RecordService } from '../../src/services/recordService';
import { ReconciliationWorker } from '../../src/services/reconciliationWorker';
import { PseudonymService } from '../../src/services/pseudonymService';

describe('Live Fabric Reconciliation Worker End-to-End Tests', () => {
  let fabric: FabricGatewayService;
  let recordService: RecordService;

  const timestamp = Date.now();
  const SYNTH_PATIENT_ID = `pat_synth_rec_${timestamp}`;
  const SYNTH_NOTE_ID = `note_synth_rec_${timestamp}`;
  const SYNTH_NURSE_UID = `nurse_synth_rec_${timestamp}`;
  const SYNTH_PLAN_ID = `plan_synth_rec_${timestamp}`;
  const SYNTH_TASK_ID = `task_synth_rec_${timestamp}`;
  const SYNTH_PROG_ID = `prog_synth_rec_${timestamp}`;

  before(async function () {
    this.timeout(30000);
    fabric = FabricGatewayService.getInstance();
    await fabric.connect();
    recordService = new RecordService(fabric);
  });

  after(async function () {
    await fabric.disconnect();
  });

  it('should reconcile a synthetic PENDING clinical note on live Fabric, obtain block commit, and update status to COMMITTED', async function () {
    this.timeout(45000);

    const syntheticNote: Record<string, any> = {
      noteId: SYNTH_NOTE_ID,
      patientId: SYNTH_PATIENT_ID,
      authorUid: SYNTH_NURSE_UID,
      authorName: 'Synthetic Nurse',
      authorRole: 'nurse',
      noteType: 'progress_note',
      clinicalSummary: 'Synthetic test clinical note for live Fabric reconciliation verification.',
      nurseReviewedTranscript: 'Patient vitals within normal parameters. Routine IV hydration continuing.',
      narrativeObservations: 'Synthetic observations.',
      careInterventions: 'Synthetic care interventions.',
      treatmentResponseNarrative: 'Synthetic response narrative.',
      supportedExtractedSymptoms: {},
      amendmentOf: '',
      amendmentReason: '',
      createdAtIso: new Date().toISOString(),
      status: 'SUBMITTED',
      fabricStatus: 'PENDING'
    };

    const canonicalHash = recordService.computeCanonicalClinicalNoteHash(syntheticNote);
    syntheticNote.fileHash = canonicalHash;

    let updatedStatus = '';
    let updatedTxId = '';

    const mockDocRef: any = {
      id: SYNTH_NOTE_ID,
      update: sinon.stub().callsFake(async (updatePayload: any) => {
        Object.assign(syntheticNote, updatePayload);
        if (updatePayload.fabricStatus) {
          updatedStatus = updatePayload.fabricStatus;
        }
        if (updatePayload.fabricTxId) {
          updatedTxId = updatePayload.fabricTxId;
        }
      })
    };

    const mockSnapshot = {
      docs: [
        {
          id: SYNTH_NOTE_ID,
          ref: mockDocRef,
          data: () => ({ ...syntheticNote })
        }
      ]
    };

    const mockCollectionGroupQuery = {
      where: sinon.stub().returnsThis(),
      get: sinon.stub().resolves(mockSnapshot)
    };

    const mockFirestore: any = {
      collectionGroup: sinon.stub().withArgs('clinical_notes').returns(mockCollectionGroupQuery),
      runTransaction: sinon.stub().callsFake(async (callback) => {
        const transaction = {
          get: sinon.stub().callsFake(async () => ({
            exists: true,
            id: SYNTH_NOTE_ID,
            data: () => ({ ...syntheticNote })
          })),
          update: sinon.stub().callsFake((ref, payload) => {
            Object.assign(syntheticNote, payload);
            mockDocRef.update(payload);
          })
        };
        return await callback(transaction);
      })
    };

    const mockFirebaseAdmin: any = {
      getFirestoreInstance: sinon.stub().returns(mockFirestore),
      updateRecordProof: sinon.stub().resolves()
    };

    const worker = new ReconciliationWorker(fabric, mockFirebaseAdmin, recordService);

    const result = await worker.reconcilePendingClinicalNotes();

    expect(result.processed).to.equal(1);
    expect(result.committed).to.equal(1);
    expect(result.failed).to.equal(0);

    expect(updatedStatus).to.equal('COMMITTED');
    expect(updatedTxId).to.match(/^[a-fA-F0-9]{64}$/);

    const opaqueRecordKey = PseudonymService.generateOpaqueRecordKey(SYNTH_PATIENT_ID, SYNTH_NOTE_ID);
    const proofStr = await fabric.evaluateTransaction('GetRecordProof', opaqueRecordKey);
    const proof = JSON.parse(proofStr);
    expect(proof.recordId).to.equal(opaqueRecordKey);
    expect(proof.sha256Hash).to.equal(canonicalHash);
    expect(proof.txId).to.equal(updatedTxId);

    const verifyValidStr = await fabric.evaluateTransaction('VerifyRecordHash', opaqueRecordKey, canonicalHash);
    const verifyValid = JSON.parse(verifyValidStr);
    expect(verifyValid.verified).to.be.true;
    expect(verifyValid.status).to.equal('VERIFIED');

    // Idempotent recovery
    syntheticNote.fabricStatus = 'PENDING';
    const retryResult = await worker.reconcilePendingClinicalNotes();
    expect(retryResult.committed).to.equal(1);
    expect(retryResult.failed).to.equal(0);
  });

  it('should reconcile a synthetic PENDING treatment task completion on live Fabric, obtain real transaction ID, dual endorsement and verify on-chain proof (Step 3)', async function () {
    this.timeout(45000);

    const taskSourceData: Record<string, any> = {
      taskId: SYNTH_TASK_ID,
      planId: SYNTH_PLAN_ID,
      patientId: SYNTH_PATIENT_ID,
      title: 'Administer Ondansetron 8mg IV piggyback',
      category: 'medication',
      instructions: 'Infuse over 15 minutes pre-chemo',
      scheduledTimeIso: '2026-10-17T09:00:00.000Z',
      status: 'completed',
      completedByNurseId: SYNTH_NURSE_UID,
      completedByNurseName: 'Nurse Sarah Jenkins',
      completedAt: { toDate: () => new Date('2026-10-17T09:15:00.000Z') },
      executionRemarks: 'Infused uneventfully. No acute reaction.',
      fabricStatus: 'PENDING'
    };

    const taskCanonicalHash = recordService.computeCanonicalTaskHash(taskSourceData);
    expect(taskCanonicalHash).to.match(/^[a-f0-9]{64}$/);

    const opDocPath = `gateway_operations/op_task_${SYNTH_TASK_ID}`;
    const taskSourcePath = `patients/${SYNTH_PATIENT_ID}/treatment_plans/${SYNTH_PLAN_ID}/tasks/${SYNTH_TASK_ID}`;

    const opData: Record<string, any> = {
      operationType: 'TREATMENT_TASK_COMPLETION',
      recordType: 'TREATMENT_TASK_COMPLETION',
      documentType: 'TREATMENT_PLAN',
      patientId: SYNTH_PATIENT_ID,
      planId: SYNTH_PLAN_ID,
      recordId: SYNTH_TASK_ID,
      sourceDocPath: taskSourcePath,
      status: 'PENDING',
      retryCount: 0,
      createdAt: { toDate: () => new Date() }
    };

    let taskUpdatedStatus = '';
    let taskUpdatedTxId = '';
    let opUpdatedStatus = '';

    const mockTaskDocRef: any = {
      id: SYNTH_TASK_ID,
      path: taskSourcePath,
      get: sinon.stub().callsFake(async () => ({
        exists: true,
        id: SYNTH_TASK_ID,
        data: () => ({ ...taskSourceData })
      })),
      update: sinon.stub().callsFake(async (payload: any) => {
        Object.assign(taskSourceData, payload);
        if (payload.fabricStatus) taskUpdatedStatus = payload.fabricStatus;
        if (payload.fabricTxId) taskUpdatedTxId = payload.fabricTxId;
      })
    };

    const mockOpDocRef: any = {
      id: `op_task_${SYNTH_TASK_ID}`,
      path: opDocPath,
      get: sinon.stub().callsFake(async () => ({
        exists: true,
        id: `op_task_${SYNTH_TASK_ID}`,
        data: () => ({ ...opData })
      })),
      update: sinon.stub().callsFake(async (payload: any) => {
        Object.assign(opData, payload);
        if (payload.status) opUpdatedStatus = payload.status;
      })
    };

    const mockOpSnapshot = {
      docs: [
        {
          id: `op_task_${SYNTH_TASK_ID}`,
          ref: mockOpDocRef,
          data: () => ({ ...opData })
        }
      ]
    };

    const mockFirestore: any = {
      collection: sinon.stub().withArgs('gateway_operations').returns({
        where: sinon.stub().withArgs('documentType', '==', 'TREATMENT_PLAN').returns({
          get: sinon.stub().resolves(mockOpSnapshot)
        })
      }),
      doc: sinon.stub().callsFake((path: string) => {
        if (path === taskSourcePath) return mockTaskDocRef;
        if (path === opDocPath) return mockOpDocRef;
        return mockTaskDocRef;
      }),
      runTransaction: sinon.stub().callsFake(async (callback) => {
        const transaction = {
          get: sinon.stub().callsFake(async (ref: any) => {
            if (ref === mockOpDocRef || ref.id === mockOpDocRef.id) {
              return { exists: true, id: mockOpDocRef.id, data: () => ({ ...opData }) };
            }
            if (ref === mockTaskDocRef || ref.id === mockTaskDocRef.id) {
              return { exists: true, id: mockTaskDocRef.id, data: () => ({ ...taskSourceData }) };
            }
            return { exists: true, id: ref.id, data: () => ({ ...opData }) };
          }),
          update: sinon.stub().callsFake((ref: any, payload: any) => {
            if (ref === mockOpDocRef || ref.id === mockOpDocRef.id) {
              Object.assign(opData, payload);
              mockOpDocRef.update(payload);
            } else {
              Object.assign(taskSourceData, payload);
              mockTaskDocRef.update(payload);
            }
          })
        };
        return await callback(transaction);
      })
    };

    const mockFirebaseAdmin: any = {
      getFirestoreInstance: sinon.stub().returns(mockFirestore),
      updateRecordProof: sinon.stub().resolves()
    };

    const worker = new ReconciliationWorker(fabric, mockFirebaseAdmin, recordService);

    // Reconcile treatment task on real Fabric network
    const result = await worker.reconcilePendingTreatmentOperations();

    expect(result.processed).to.equal(1);
    expect(result.committed).to.equal(1);
    expect(result.failed).to.equal(0);

    expect(taskUpdatedStatus).to.equal('COMMITTED');
    expect(opUpdatedStatus).to.equal('COMMITTED');
    expect(taskUpdatedTxId).to.match(/^[a-fA-F0-9]{64}$/);

    // Verify on-chain ledger proof using domain-separated key
    const domainTaskId = `task_${SYNTH_PLAN_ID}_${SYNTH_TASK_ID}`;
    const opaqueTaskKey = PseudonymService.generateOpaqueRecordKey(SYNTH_PATIENT_ID, domainTaskId);

    const onChainProofStr = await fabric.evaluateTransaction('GetRecordProof', opaqueTaskKey);
    const onChainProof = JSON.parse(onChainProofStr);

    expect(onChainProof.recordId).to.equal(opaqueTaskKey);
    expect(onChainProof.sha256Hash).to.equal(taskCanonicalHash);
    expect(onChainProof.txId).to.equal(taskUpdatedTxId);
    expect(onChainProof.status).to.equal('ACTIVE');

    // VerifyRecordHash returns verified: true with exact hash
    const verifyProofStr = await fabric.evaluateTransaction('VerifyRecordHash', opaqueTaskKey, taskCanonicalHash);
    const verifyProof = JSON.parse(verifyProofStr);
    expect(verifyProof.verified).to.be.true;
    expect(verifyProof.status).to.equal('VERIFIED');
  });

  it('should reconcile a synthetic PENDING treatment progress update on live Fabric, obtain proof, and verify on-chain (Step 4)', async function () {
    this.timeout(45000);

    const progressSourceData: Record<string, any> = {
      updateId: SYNTH_PROG_ID,
      planId: SYNTH_PLAN_ID,
      patientId: SYNTH_PATIENT_ID,
      authorUid: SYNTH_NURSE_UID,
      authorName: 'Nurse Sarah Jenkins',
      authorRole: 'nurse',
      clinicalSummary: 'Patient resting comfortably post-chemotherapy. Vitals stable.',
      patientTolerance: 'well_tolerated',
      factualObservations: 'No nausea, emesis, or diaphoresis observed.',
      timestamp: { toDate: () => new Date('2026-10-17T10:00:00.000Z') },
      fabricStatus: 'PENDING'
    };

    const progressCanonicalHash = recordService.computeCanonicalProgressHash(progressSourceData);
    expect(progressCanonicalHash).to.match(/^[a-f0-9]{64}$/);

    const opDocPath = `gateway_operations/op_prog_${SYNTH_PROG_ID}`;
    const progressSourcePath = `patients/${SYNTH_PATIENT_ID}/treatment_plans/${SYNTH_PLAN_ID}/progress_updates/${SYNTH_PROG_ID}`;

    const opData: Record<string, any> = {
      operationType: 'TREATMENT_PROGRESS_UPDATE',
      recordType: 'TREATMENT_PROGRESS_UPDATE',
      documentType: 'TREATMENT_PLAN',
      patientId: SYNTH_PATIENT_ID,
      planId: SYNTH_PLAN_ID,
      recordId: SYNTH_PROG_ID,
      sourceDocPath: progressSourcePath,
      status: 'PENDING',
      retryCount: 0,
      createdAt: { toDate: () => new Date() }
    };

    let progUpdatedStatus = '';
    let progUpdatedTxId = '';
    let opUpdatedStatus = '';

    const mockProgDocRef: any = {
      id: SYNTH_PROG_ID,
      path: progressSourcePath,
      get: sinon.stub().callsFake(async () => ({
        exists: true,
        id: SYNTH_PROG_ID,
        data: () => ({ ...progressSourceData })
      })),
      update: sinon.stub().callsFake(async (payload: any) => {
        Object.assign(progressSourceData, payload);
        if (payload.fabricStatus) progUpdatedStatus = payload.fabricStatus;
        if (payload.fabricTxId) progUpdatedTxId = payload.fabricTxId;
      })
    };

    const mockOpDocRef: any = {
      id: `op_prog_${SYNTH_PROG_ID}`,
      path: opDocPath,
      get: sinon.stub().callsFake(async () => ({
        exists: true,
        id: `op_prog_${SYNTH_PROG_ID}`,
        data: () => ({ ...opData })
      })),
      update: sinon.stub().callsFake(async (payload: any) => {
        Object.assign(opData, payload);
        if (payload.status) opUpdatedStatus = payload.status;
      })
    };

    const mockOpSnapshot = {
      docs: [
        {
          id: `op_prog_${SYNTH_PROG_ID}`,
          ref: mockOpDocRef,
          data: () => ({ ...opData })
        }
      ]
    };

    const mockFirestore: any = {
      collection: sinon.stub().withArgs('gateway_operations').returns({
        where: sinon.stub().withArgs('documentType', '==', 'TREATMENT_PLAN').returns({
          get: sinon.stub().resolves(mockOpSnapshot)
        })
      }),
      doc: sinon.stub().callsFake((path: string) => {
        if (path === progressSourcePath) return mockProgDocRef;
        if (path === opDocPath) return mockOpDocRef;
        return mockProgDocRef;
      }),
      runTransaction: sinon.stub().callsFake(async (callback) => {
        const transaction = {
          get: sinon.stub().callsFake(async (ref: any) => {
            if (ref === mockOpDocRef || ref.id === mockOpDocRef.id) {
              return { exists: true, id: mockOpDocRef.id, data: () => ({ ...opData }) };
            }
            if (ref === mockProgDocRef || ref.id === mockProgDocRef.id) {
              return { exists: true, id: mockProgDocRef.id, data: () => ({ ...progressSourceData }) };
            }
            return { exists: true, id: ref.id, data: () => ({ ...opData }) };
          }),
          update: sinon.stub().callsFake((ref: any, payload: any) => {
            if (ref === mockOpDocRef || ref.id === mockOpDocRef.id) {
              Object.assign(opData, payload);
              mockOpDocRef.update(payload);
            } else {
              Object.assign(progressSourceData, payload);
              mockProgDocRef.update(payload);
            }
          })
        };
        return await callback(transaction);
      })
    };

    const mockFirebaseAdmin: any = {
      getFirestoreInstance: sinon.stub().returns(mockFirestore),
      updateRecordProof: sinon.stub().resolves()
    };

    const worker = new ReconciliationWorker(fabric, mockFirebaseAdmin, recordService);

    // Reconcile treatment progress update on real Fabric network
    const result = await worker.reconcilePendingTreatmentOperations();

    expect(result.processed).to.equal(1);
    expect(result.committed).to.equal(1);
    expect(result.failed).to.equal(0);

    expect(progUpdatedStatus).to.equal('COMMITTED');
    expect(opUpdatedStatus).to.equal('COMMITTED');
    expect(progUpdatedTxId).to.match(/^[a-fA-F0-9]{64}$/);

    const domainProgId = `tp_${SYNTH_PLAN_ID}_${SYNTH_PROG_ID}`;
    const opaqueProgKey = PseudonymService.generateOpaqueRecordKey(SYNTH_PATIENT_ID, domainProgId);

    const onChainProofStr = await fabric.evaluateTransaction('GetRecordProof', opaqueProgKey);
    const onChainProof = JSON.parse(onChainProofStr);

    expect(onChainProof.recordId).to.equal(opaqueProgKey);
    expect(onChainProof.sha256Hash).to.equal(progressCanonicalHash);
    expect(onChainProof.txId).to.equal(progUpdatedTxId);

    const verifyProofStr = await fabric.evaluateTransaction('VerifyRecordHash', opaqueProgKey, progressCanonicalHash);
    const verifyProof = JSON.parse(verifyProofStr);
    expect(verifyProof.verified).to.be.true;
    expect(verifyProof.status).to.equal('VERIFIED');
  });

  it('should detect tampering when verifying modified content hash against live Fabric (Step 5)', async function () {
    this.timeout(30000);

    const domainTaskId = `task_${SYNTH_PLAN_ID}_${SYNTH_TASK_ID}`;
    const opaqueTaskKey = PseudonymService.generateOpaqueRecordKey(SYNTH_PATIENT_ID, domainTaskId);

    // 1. Correct hash succeeds
    const legitProofStr = await fabric.evaluateTransaction('GetRecordProof', opaqueTaskKey);
    const legitProof = JSON.parse(legitProofStr);
    expect(legitProof.sha256Hash).to.exist;

    const correctVerifyStr = await fabric.evaluateTransaction('VerifyRecordHash', opaqueTaskKey, legitProof.sha256Hash);
    const correctVerify = JSON.parse(correctVerifyStr);
    expect(correctVerify.verified).to.be.true;
    expect(correctVerify.status).to.equal('VERIFIED');

    // 2. Tampered content hash fails verification
    const forgedHash = crypto.createHash('sha256').update('FORGED_TREATMENT_OBSERVATION').digest('hex');
    const tamperedVerifyStr = await fabric.evaluateTransaction('VerifyRecordHash', opaqueTaskKey, forgedHash);
    const tamperedVerify = JSON.parse(tamperedVerifyStr);
    expect(tamperedVerify.verified).to.be.false;
    expect(tamperedVerify.status).to.equal('TAMPERED_OR_MISMATCH');

    // 3. Wrong/non-existent record identifier fails verification
    const nonExistentKey = `TASK_NON_EXISTENT_${Date.now()}`;
    try {
      await fabric.evaluateTransaction('VerifyRecordHash', nonExistentKey, legitProof.sha256Hash);
      expect.fail('Should have failed for non-existent key');
    } catch (err: any) {
      expect(err.message).to.include('does not exist on ledger');
    }

    // 4. Cross-patient key substitution rejected
    const crossPatientKey = PseudonymService.generateOpaqueRecordKey('DIFFERENT_PATIENT_999', domainTaskId);
    try {
      await fabric.evaluateTransaction('VerifyRecordHash', crossPatientKey, legitProof.sha256Hash);
      expect.fail('Should have failed for cross-patient key');
    } catch (err: any) {
      expect(err.message).to.include('does not exist on ledger');
    }
  });
});
