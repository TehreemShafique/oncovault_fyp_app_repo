// test/unit/reconciliationWorker.test.ts
import { expect } from 'chai';
import sinon from 'sinon';
import { ReconciliationWorker } from '../../src/services/reconciliationWorker';
import { RecordService } from '../../src/services/recordService';

describe('ReconciliationWorker Unit Tests', () => {
  let worker: ReconciliationWorker;
  let mockFabricGateway: any;
  let mockFirebaseAdmin: any;
  let mockRecordService: any;
  let mockFirestore: any;

  const MOCK_NOTE_ID = 'note_sync_001';
  const MOCK_PATIENT_ID = 'pat_sync_123';
  const MOCK_AUTHOR_UID = 'nurse_sync_789';
  const MOCK_HASH = 'a'.repeat(64);

  let mockNoteData: Record<string, any>;
  let mockDocRef: any;

  beforeEach(() => {
    mockNoteData = {
      noteId: MOCK_NOTE_ID,
      patientId: MOCK_PATIENT_ID,
      authorUid: MOCK_AUTHOR_UID,
      noteType: 'progress_note',
      clinicalSummary: 'Patient stable, blood pressure normal.',
      nurseReviewedTranscript: 'Patient vitals stable.',
      narrativeObservations: 'Alert and oriented.',
      careInterventions: 'IV fluids given.',
      treatmentResponseNarrative: 'Responding well.',
      supportedExtractedSymptoms: {},
      amendmentOf: '',
      amendmentReason: '',
      createdAtIso: '2026-10-17T10:00:00.000Z',
      status: 'SUBMITTED',
      fabricStatus: 'PENDING',
      fileHash: MOCK_HASH
    };

    mockDocRef = {
      id: MOCK_NOTE_ID,
      update: sinon.stub().resolves(),
      get: sinon.stub().resolves({
        exists: true,
        id: MOCK_NOTE_ID,
        data: () => ({ ...mockNoteData })
      })
    };

    const mockSnapshot = {
      docs: [
        {
          id: MOCK_NOTE_ID,
          ref: mockDocRef,
          data: () => ({ ...mockNoteData })
        }
      ]
    };

    const mockCollectionGroupQuery = {
      where: sinon.stub().returnsThis(),
      get: sinon.stub().callsFake(async () => ({
        docs: [
          {
            id: MOCK_NOTE_ID,
            ref: mockDocRef,
            data: () => ({ ...mockNoteData })
          }
        ]
      }))
    };

    mockFirestore = {
      collectionGroup: sinon.stub().withArgs('clinical_notes').returns(mockCollectionGroupQuery),
      collection: sinon.stub(),
      doc: sinon.stub(),
      runTransaction: sinon.stub().callsFake(async (callback) => {
        const transaction = {
          get: sinon.stub().callsFake(async (ref) => {
            return {
              exists: true,
              id: MOCK_NOTE_ID,
              data: () => ({ ...mockNoteData })
            };
          }),
          update: sinon.stub().callsFake((ref, payload) => {
            Object.assign(mockNoteData, payload);
            mockDocRef.update(payload);
          })
        };
        return await callback(transaction);
      })
    };

    mockFabricGateway = {
      evaluateTransaction: sinon.stub(),
      submitTransaction: sinon.stub()
    };

    mockFirebaseAdmin = {
      getFirestoreInstance: sinon.stub().returns(mockFirestore),
      updateRecordProof: sinon.stub().resolves()
    };

    mockRecordService = {
      computeCanonicalClinicalNoteHash: sinon.stub().returns(MOCK_HASH),
      computeCanonicalTaskHash: sinon.stub().returns(MOCK_HASH),
      computeCanonicalProgressHash: sinon.stub().returns(MOCK_HASH)
    };

    worker = new ReconciliationWorker(
      mockFabricGateway,
      mockFirebaseAdmin,
      mockRecordService
    );
  });

  afterEach(() => {
    worker.stopPeriodicSweeper();
    sinon.restore();
  });

  it('should successfully discover and anchor a PENDING clinical note on Fabric', async () => {
    // 1. Existing ledger check returns nothing (fresh anchor)
    mockFabricGateway.evaluateTransaction
      .withArgs('GetRecordProof')
      .rejects(new Error('Record not found'));

    // 2. Submit transaction succeeds
    mockFabricGateway.submitTransaction
      .withArgs('AnchorRecordHash')
      .resolves({
        result: JSON.stringify({
          recordId: 'rec_opaque_key',
          sha256Hash: MOCK_HASH,
          version: 1,
          txId: 'tx_fabric_reconciled_123',
          timestamp: '2026-10-17T10:05:00.000Z'
        }),
        txId: 'tx_fabric_reconciled_123'
      });

    // 3. Ledger verification returns verified
    mockFabricGateway.evaluateTransaction
      .withArgs('VerifyRecordHash')
      .resolves(JSON.stringify({
        verified: true,
        status: 'VERIFIED',
        sha256Hash: MOCK_HASH
      }));

    const result = await worker.reconcilePendingClinicalNotes();

    expect(result.processed).to.equal(1);
    expect(result.committed).to.equal(1);
    expect(result.failed).to.equal(0);

    // Verify Fabric submit was invoked with correct arguments
    expect(mockFabricGateway.submitTransaction.calledOnce).to.be.true;
    const submitArgs = mockFabricGateway.submitTransaction.firstCall.args;
    expect(submitArgs[0]).to.equal('AnchorRecordHash');
    expect(submitArgs[2]).to.equal(MOCK_HASH);

    // Verify Firestore proof update was triggered
    expect(mockFirebaseAdmin.updateRecordProof.calledOnce).to.be.true;
    expect(mockDocRef.update.called).to.be.true;
    const updatePayload = mockDocRef.update.lastCall.args[0];
    expect(updatePayload.fabricStatus).to.equal('COMMITTED');
    expect(updatePayload.fabricTxId).to.equal('tx_fabric_reconciled_123');
  });

  it('should detect tamper and fail permanently when recalculated hash does not match stored fileHash', async () => {
    // Recalculated hash does not match stored hash
    mockRecordService.computeCanonicalClinicalNoteHash.returns('b'.repeat(64));

    const result = await worker.reconcilePendingClinicalNotes();

    expect(result.processed).to.equal(1);
    expect(result.committed).to.equal(0);
    expect(result.failed).to.equal(1);

    // Fabric submission must NEVER occur for tampered content
    expect(mockFabricGateway.submitTransaction.called).to.be.false;

    // Document marked as FAILED_PERMANENT
    expect(mockDocRef.update.called).to.be.true;
    const updatePayload = mockDocRef.update.lastCall.args[0];
    expect(updatePayload.fabricStatus).to.equal('FAILED_PERMANENT');
    expect(updatePayload.fabricError).to.include('tampering');
  });

  it('should idempotently recover when note is already anchored on chain without duplicate block creation', async () => {
    // Existing ledger check returns matching proof
    mockFabricGateway.evaluateTransaction
      .withArgs('GetRecordProof')
      .resolves(JSON.stringify({
        recordId: 'rec_opaque_key',
        sha256Hash: MOCK_HASH,
        version: 1,
        txId: 'tx_existing_onchain_proof',
        timestamp: '2026-10-17T09:30:00.000Z'
      }));

    const result = await worker.reconcilePendingClinicalNotes();

    expect(result.processed).to.equal(1);
    expect(result.committed).to.equal(1);
    expect(result.failed).to.equal(0);

    // submitTransaction must NOT be called since proof is already valid on-chain
    expect(mockFabricGateway.submitTransaction.called).to.be.false;

    // Firestore marked COMMITTED with existing proof
    expect(mockDocRef.update.called).to.be.true;
    const updatePayload = mockDocRef.update.lastCall.args[0];
    expect(updatePayload.fabricStatus).to.equal('COMMITTED');
    expect(updatePayload.fabricTxId).to.equal('tx_existing_onchain_proof');
  });

  it('should mark FAILED_RETRYABLE on transient Fabric error and FAILED_PERMANENT after 5 retries', async () => {
    mockFabricGateway.evaluateTransaction
      .withArgs('GetRecordProof')
      .rejects(new Error('Record not found'));

    mockFabricGateway.submitTransaction
      .withArgs('AnchorRecordHash')
      .rejects(new Error('DEADLINE_EXCEEDED: Peer endorsement timeout'));

    // Attempt 1: retryCount becomes 1 -> FAILED_RETRYABLE
    const result1 = await worker.reconcilePendingClinicalNotes();
    expect(result1.failed).to.equal(1);
    expect(result1.committed).to.equal(0);

    let updatePayload = mockDocRef.update.lastCall.args[0];
    expect(updatePayload.fabricStatus).to.equal('FAILED_RETRYABLE');
    expect(updatePayload.retryCount).to.equal(1);

    // Simulate 4 prior retries (retryCount = 4) and eligible retry timestamp
    mockNoteData.retryCount = 4;
    mockNoteData.fabricStatus = 'FAILED_RETRYABLE';
    mockNoteData.nextRetryAt = Date.now() - 1000;

    const result2 = await worker.reconcilePendingClinicalNotes();
    expect(result2.failed).to.equal(1);

    updatePayload = mockDocRef.update.lastCall.args[0];
    expect(updatePayload.fabricStatus).to.equal('FAILED_PERMANENT');
    expect(updatePayload.retryCount).to.equal(5);
  });

  it('should reject stale worker whose lease token was superseded before committing', async () => {
    mockFabricGateway.evaluateTransaction
      .withArgs('GetRecordProof')
      .rejects(new Error('Record not found'));

    mockFabricGateway.submitTransaction
      .withArgs('AnchorRecordHash')
      .resolves({
        result: JSON.stringify({
          recordId: 'rec_opaque_key',
          sha256Hash: MOCK_HASH,
          version: 1,
          txId: 'tx_fabric_stale_123',
          timestamp: '2026-10-17T10:05:00.000Z'
        }),
        txId: 'tx_fabric_stale_123'
      });

    mockFabricGateway.evaluateTransaction
      .withArgs('VerifyRecordHash')
      .resolves(JSON.stringify({
        verified: true,
        status: 'VERIFIED',
        sha256Hash: MOCK_HASH
      }));

    // Intercept runTransaction: on the second call (the commit transaction), simulate another worker has changed leaseToken
    let txCount = 0;
    mockFirestore.runTransaction = sinon.stub().callsFake(async (callback) => {
      txCount++;
      if (txCount === 1) {
        // First transaction: lease acquisition
        const transaction = {
          get: sinon.stub().resolves({
            exists: true,
            id: MOCK_NOTE_ID,
            data: () => ({ ...mockNoteData })
          }),
          update: sinon.stub().callsFake((ref, payload) => {
            Object.assign(mockNoteData, payload);
            mockDocRef.update(payload);
          })
        };
        return await callback(transaction);
      } else {
        // Subsequent transaction: simulate superseded lease
        const transaction = {
          get: sinon.stub().resolves({
            exists: true,
            id: MOCK_NOTE_ID,
            data: () => ({ ...mockNoteData, leaseToken: 'superseded-by-worker-B' })
          }),
          update: sinon.stub().callsFake((ref, payload) => {
            Object.assign(mockNoteData, payload);
            mockDocRef.update(payload);
          })
        };
        return await callback(transaction);
      }
    });

    const result = await worker.reconcilePendingClinicalNotes();

    // Commit must be rejected because lease token was superseded
    expect(result.committed).to.equal(0);
    expect(result.failed).to.equal(1);
    expect(mockFirebaseAdmin.updateRecordProof.called).to.be.false;
  });

  it('should reconcile clinical notes in REVIEWED status without changing clinical status', async () => {
    mockNoteData.status = 'REVIEWED';
    mockNoteData.doctorReviewNotes = 'Verified and approved by Dr. Smith';
    mockNoteData.reviewedByUid = 'doc_456';

    mockFabricGateway.evaluateTransaction
      .withArgs('GetRecordProof')
      .rejects(new Error('Record not found'));

    mockFabricGateway.submitTransaction
      .withArgs('AnchorRecordHash')
      .resolves({
        result: JSON.stringify({
          recordId: 'rec_opaque_key',
          sha256Hash: MOCK_HASH,
          version: 1,
          txId: 'tx_fabric_reviewed_123',
          timestamp: '2026-10-17T10:05:00.000Z'
        }),
        txId: 'tx_fabric_reviewed_123'
      });

    mockFabricGateway.evaluateTransaction
      .withArgs('VerifyRecordHash')
      .resolves(JSON.stringify({
        verified: true,
        status: 'VERIFIED',
        sha256Hash: MOCK_HASH
      }));

    const result = await worker.reconcilePendingClinicalNotes();

    expect(result.committed).to.equal(1);
    expect(mockNoteData.fabricStatus).to.equal('COMMITTED');
    expect(mockNoteData.status).to.equal('REVIEWED'); // Clinical status remains unchanged!
  });

  it('should skip candidate notes whose nextRetryAt is in the future', async () => {
    mockNoteData.fabricStatus = 'FAILED_RETRYABLE';
    mockNoteData.nextRetryAt = Date.now() + 60000; // 1 minute in future

    const result = await worker.reconcilePendingClinicalNotes();

    expect(result.processed).to.equal(0);
    expect(result.committed).to.equal(0);
    expect(result.failed).to.equal(0);
    expect(mockFabricGateway.submitTransaction.called).to.be.false;
  });

  it('should never retry notes marked FAILED_PERMANENT', async () => {
    mockNoteData.fabricStatus = 'FAILED_PERMANENT';

    const result = await worker.reconcilePendingClinicalNotes();

    expect(result.processed).to.equal(0);
    expect(result.committed).to.equal(0);
    expect(result.failed).to.equal(0);
    expect(mockFabricGateway.submitTransaction.called).to.be.false;
  });

  it('should start and stop periodic sweeper loop without leaks', () => {
    worker.startPeriodicSweeper(1000);
    // Starting again is a no-op
    worker.startPeriodicSweeper(1000);
    worker.stopPeriodicSweeper();
    // Stopping again is a no-op
    worker.stopPeriodicSweeper();
  });

  describe('reconcilePendingTreatmentOperations', () => {
    const MOCK_OP_TASK_ID = 'op_task_001';
    const MOCK_TASK_ID = 'task_001';
    const MOCK_PLAN_ID = 'plan_001';
    const MOCK_PAT_ID = 'pat_101';
    const MOCK_TASK_SOURCE_PATH = `patients/${MOCK_PAT_ID}/treatment_plans/${MOCK_PLAN_ID}/tasks/${MOCK_TASK_ID}`;

    let mockOpData: Record<string, any>;
    let mockTaskData: Record<string, any>;
    let mockOpDocRef: any;
    let mockTaskDocRef: any;

    beforeEach(() => {
      mockOpData = {
        id: MOCK_OP_TASK_ID,
        documentType: 'TREATMENT_PLAN',
        recordType: 'TREATMENT_TASK_COMPLETION',
        patientId: MOCK_PAT_ID,
        planId: MOCK_PLAN_ID,
        recordId: MOCK_TASK_ID,
        sourceDocPath: MOCK_TASK_SOURCE_PATH,
        status: 'PENDING'
      };

      mockTaskData = {
        taskId: MOCK_TASK_ID,
        planId: MOCK_PLAN_ID,
        patientId: MOCK_PAT_ID,
        status: 'completed',
        completedByNurseId: 'nurse_123',
        completedByNurseName: 'Nurse Joy',
        completedAt: '2026-10-17T10:00:00.000Z',
        title: 'Pre-hydration Saline',
        instructions: '1L normal saline over 2 hours'
      };

      mockOpDocRef = {
        id: MOCK_OP_TASK_ID,
        update: sinon.stub().resolves(),
        get: sinon.stub().callsFake(async () => ({
          exists: true,
          id: MOCK_OP_TASK_ID,
          data: () => ({ ...mockOpData })
        }))
      };

      mockTaskDocRef = {
        id: MOCK_TASK_ID,
        update: sinon.stub().resolves(),
        get: sinon.stub().callsFake(async () => ({
          exists: true,
          id: MOCK_TASK_ID,
          data: () => ({ ...mockTaskData })
        }))
      };

      const mockOperationsQuery = {
        where: sinon.stub().returnsThis(),
        get: sinon.stub().callsFake(async () => ({
          docs: [
            {
              id: MOCK_OP_TASK_ID,
              ref: mockOpDocRef,
              data: () => ({ ...mockOpData })
            }
          ]
        }))
      };

      mockFirestore.collection.withArgs('gateway_operations').returns(mockOperationsQuery);
      mockFirestore.doc.withArgs(MOCK_TASK_SOURCE_PATH).returns(mockTaskDocRef);

      mockFirestore.runTransaction = sinon.stub().callsFake(async (callback) => {
        const transaction = {
          get: sinon.stub().callsFake(async (ref) => {
            if (ref === mockOpDocRef || ref.id === MOCK_OP_TASK_ID) {
              return {
                exists: true,
                id: MOCK_OP_TASK_ID,
                data: () => ({ ...mockOpData })
              };
            }
            if (ref === mockTaskDocRef || ref.id === MOCK_TASK_ID) {
              return {
                exists: true,
                id: MOCK_TASK_ID,
                data: () => ({ ...mockTaskData })
              };
            }
            return { exists: false, data: () => null };
          }),
          update: sinon.stub().callsFake((ref, payload) => {
            if (ref === mockOpDocRef || ref.id === MOCK_OP_TASK_ID) {
              Object.assign(mockOpData, payload);
              mockOpDocRef.update(payload);
            }
            if (ref === mockTaskDocRef || ref.id === MOCK_TASK_ID) {
              Object.assign(mockTaskData, payload);
              mockTaskDocRef.update(payload);
            }
          })
        };
        return await callback(transaction);
      });
    });

    it('should successfully discover and anchor a PENDING treatment task completion', async () => {
      mockFabricGateway.evaluateTransaction
        .withArgs('GetRecordProof')
        .rejects(new Error('Record not found'));

      mockFabricGateway.submitTransaction
        .withArgs('AnchorRecordHash')
        .resolves({
          result: JSON.stringify({
            recordId: 'rec_task_opaque',
            sha256Hash: MOCK_HASH,
            version: 1,
            txId: 'tx_treatment_task_123',
            timestamp: '2026-10-17T10:05:00.000Z'
          }),
          txId: 'tx_treatment_task_123'
        });

      mockFabricGateway.evaluateTransaction
        .withArgs('VerifyRecordHash')
        .resolves(JSON.stringify({
          verified: true,
          status: 'VERIFIED',
          sha256Hash: MOCK_HASH
        }));

      const result = await worker.reconcilePendingTreatmentOperations();

      expect(result.processed).to.equal(1);
      expect(result.committed).to.equal(1);
      expect(result.failed).to.equal(0);

      // Verify Fabric submission
      expect(mockFabricGateway.submitTransaction.calledOnce).to.be.true;
      const submitArgs = mockFabricGateway.submitTransaction.firstCall.args;
      expect(submitArgs[0]).to.equal('AnchorRecordHash');
      expect(submitArgs[2]).to.equal(MOCK_HASH);
      const parsedMetadata = JSON.parse(submitArgs[3]);
      expect(parsedMetadata.documentType).to.equal('TREATMENT_PLAN');
      expect(parsedMetadata.recordType).to.equal('TREATMENT_TASK_COMPLETION');

      // Verify Firestore status updates
      expect(mockOpData.status).to.equal('COMMITTED');
      expect(mockOpData.fabricTxId).to.equal('tx_treatment_task_123');
      expect(mockTaskData.fabricStatus).to.equal('COMMITTED');
      expect(mockTaskData.fabricTxId).to.equal('tx_treatment_task_123');
    });

    it('should successfully discover and anchor a PENDING treatment progress update', async () => {
      const MOCK_OP_PROG_ID = 'op_prog_001';
      const MOCK_PROG_ID = 'tp_001';
      const MOCK_PROG_SOURCE_PATH = `patients/${MOCK_PAT_ID}/treatment_plans/${MOCK_PLAN_ID}/progress_updates/${MOCK_PROG_ID}`;

      mockOpData = {
        id: MOCK_OP_PROG_ID,
        documentType: 'TREATMENT_PLAN',
        recordType: 'TREATMENT_PROGRESS',
        patientId: MOCK_PAT_ID,
        planId: MOCK_PLAN_ID,
        recordId: MOCK_PROG_ID,
        sourceDocPath: MOCK_PROG_SOURCE_PATH,
        status: 'PENDING'
      };

      const mockProgData: Record<string, any> = {
        updateId: MOCK_PROG_ID,
        planId: MOCK_PLAN_ID,
        patientId: MOCK_PAT_ID,
        authorUid: 'doc_456',
        authorRole: 'doctor',
        timestamp: '2026-10-17T11:00:00.000Z',
        clinicalSummary: 'Tolerating chemotherapy regimen with minor fatigue.'
      };

      const mockProgDocRef = {
        id: MOCK_PROG_ID,
        update: sinon.stub().resolves(),
        get: sinon.stub().callsFake(async () => ({
          exists: true,
          id: MOCK_PROG_ID,
          data: () => ({ ...mockProgData })
        }))
      };

      const mockProgOperationsQuery = {
        where: sinon.stub().returnsThis(),
        get: sinon.stub().callsFake(async () => ({
          docs: [
            {
              id: MOCK_OP_PROG_ID,
              ref: mockOpDocRef,
              data: () => ({ ...mockOpData })
            }
          ]
        }))
      };

      mockFirestore.collection.withArgs('gateway_operations').returns(mockProgOperationsQuery);
      mockFirestore.doc.withArgs(MOCK_PROG_SOURCE_PATH).returns(mockProgDocRef);

      mockFirestore.runTransaction = sinon.stub().callsFake(async (callback) => {
        const transaction = {
          get: sinon.stub().callsFake(async (ref) => {
            if (ref === mockOpDocRef || ref.id === MOCK_OP_PROG_ID) {
              return {
                exists: true,
                id: MOCK_OP_PROG_ID,
                data: () => ({ ...mockOpData })
              };
            }
            if (ref === mockProgDocRef || ref.id === MOCK_PROG_ID) {
              return {
                exists: true,
                id: MOCK_PROG_ID,
                data: () => ({ ...mockProgData })
              };
            }
            return { exists: false, data: () => null };
          }),
          update: sinon.stub().callsFake((ref, payload) => {
            if (ref === mockOpDocRef || ref.id === MOCK_OP_PROG_ID) {
              Object.assign(mockOpData, payload);
              mockOpDocRef.update(payload);
            }
            if (ref === mockProgDocRef || ref.id === MOCK_PROG_ID) {
              Object.assign(mockProgData, payload);
              mockProgDocRef.update(payload);
            }
          })
        };
        return await callback(transaction);
      });

      mockFabricGateway.evaluateTransaction
        .withArgs('GetRecordProof')
        .rejects(new Error('Record not found'));

      mockFabricGateway.submitTransaction
        .withArgs('AnchorRecordHash')
        .resolves({
          result: JSON.stringify({
            recordId: 'rec_prog_opaque',
            sha256Hash: MOCK_HASH,
            version: 1,
            txId: 'tx_prog_anchor_456',
            timestamp: '2026-10-17T11:05:00.000Z'
          }),
          txId: 'tx_prog_anchor_456'
        });

      mockFabricGateway.evaluateTransaction
        .withArgs('VerifyRecordHash')
        .resolves(JSON.stringify({
          verified: true,
          status: 'VERIFIED',
          sha256Hash: MOCK_HASH
        }));

      const result = await worker.reconcilePendingTreatmentOperations();

      expect(result.processed).to.equal(1);
      expect(result.committed).to.equal(1);
      expect(result.failed).to.equal(0);

      const submitArgs = mockFabricGateway.submitTransaction.firstCall.args;
      const parsedMetadata = JSON.parse(submitArgs[3]);
      expect(parsedMetadata.documentType).to.equal('TREATMENT_PLAN');
      expect(parsedMetadata.recordType).to.equal('TREATMENT_PROGRESS');
      expect(mockOpData.status).to.equal('COMMITTED');
      expect(mockProgData.fabricStatus).to.equal('COMMITTED');
    });

    it('should idempotently recover when treatment task is already anchored on chain', async () => {
      mockFabricGateway.evaluateTransaction
        .withArgs('GetRecordProof')
        .resolves(JSON.stringify({
          recordId: 'rec_task_opaque',
          sha256Hash: MOCK_HASH,
          version: 1,
          txId: 'tx_existing_task_proof',
          timestamp: '2026-10-17T09:00:00.000Z'
        }));

      const result = await worker.reconcilePendingTreatmentOperations();

      expect(result.processed).to.equal(1);
      expect(result.committed).to.equal(1);
      expect(result.failed).to.equal(0);

      // submitTransaction must NOT be called
      expect(mockFabricGateway.submitTransaction.called).to.be.false;

      // Status marked COMMITTED with existing proof
      expect(mockOpData.status).to.equal('COMMITTED');
      expect(mockOpData.fabricTxId).to.equal('tx_existing_task_proof');
      expect(mockTaskData.fabricStatus).to.equal('COMMITTED');
      expect(mockTaskData.fabricTxId).to.equal('tx_existing_task_proof');
    });

    it('should reject stale worker whose lease token was superseded before committing treatment operation', async () => {
      mockFabricGateway.evaluateTransaction
        .withArgs('GetRecordProof')
        .rejects(new Error('Record not found'));

      mockFabricGateway.submitTransaction
        .withArgs('AnchorRecordHash')
        .resolves({
          result: JSON.stringify({
            recordId: 'rec_task_opaque',
            sha256Hash: MOCK_HASH,
            version: 1,
            txId: 'tx_stale_123',
            timestamp: '2026-10-17T10:05:00.000Z'
          }),
          txId: 'tx_stale_123'
        });

      mockFabricGateway.evaluateTransaction
        .withArgs('VerifyRecordHash')
        .resolves(JSON.stringify({
          verified: true,
          status: 'VERIFIED',
          sha256Hash: MOCK_HASH
        }));

      let txCount = 0;
      mockFirestore.runTransaction = sinon.stub().callsFake(async (callback) => {
        txCount++;
        if (txCount === 1) {
          // Lease acquisition transaction
          const transaction = {
            get: sinon.stub().resolves({
              exists: true,
              id: MOCK_OP_TASK_ID,
              data: () => ({ ...mockOpData })
            }),
            update: sinon.stub().callsFake((ref, payload) => {
              Object.assign(mockOpData, payload);
            })
          };
          return await callback(transaction);
        } else {
          // Second transaction (commit): simulate superseded lease token
          const transaction = {
            get: sinon.stub().resolves({
              exists: true,
              id: MOCK_OP_TASK_ID,
              data: () => ({ ...mockOpData, leaseToken: 'superseded-lease-token' })
            }),
            update: sinon.stub()
          };
          return await callback(transaction);
        }
      });

      const result = await worker.reconcilePendingTreatmentOperations();

      expect(result.committed).to.equal(0);
      expect(result.failed).to.equal(1);
    });

    it('should mark FAILED_RETRYABLE on transient Fabric error and FAILED_PERMANENT after 5 retries', async () => {
      mockFabricGateway.evaluateTransaction
        .withArgs('GetRecordProof')
        .rejects(new Error('Record not found'));

      mockFabricGateway.submitTransaction
        .withArgs('AnchorRecordHash')
        .rejects(new Error('DEADLINE_EXCEEDED: Peer timeout'));

      const result1 = await worker.reconcilePendingTreatmentOperations();
      expect(result1.failed).to.equal(1);
      expect(result1.committed).to.equal(0);
      expect(mockOpData.status).to.equal('FAILED_RETRYABLE');
      expect(mockOpData.retryCount).to.equal(1);

      // Simulate 4 prior retries (retryCount = 4) and eligible retry timestamp
      mockOpData.retryCount = 4;
      mockOpData.status = 'FAILED_RETRYABLE';
      mockOpData.nextRetryAt = Date.now() - 1000;

      const result2 = await worker.reconcilePendingTreatmentOperations();
      expect(result2.failed).to.equal(1);
      expect(mockOpData.status).to.equal('FAILED_PERMANENT');
      expect(mockOpData.retryCount).to.equal(5);
    });
  });
});
