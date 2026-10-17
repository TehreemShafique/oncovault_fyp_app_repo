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
      computeCanonicalClinicalNoteHash: sinon.stub().returns(MOCK_HASH)
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
});
