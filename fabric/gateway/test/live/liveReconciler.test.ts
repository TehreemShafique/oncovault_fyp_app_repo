// test/live/liveReconciler.test.ts
import { expect } from 'chai';
import sinon from 'sinon';
import { FabricGatewayService } from '../../src/services/fabricGateway';
import { RecordService } from '../../src/services/recordService';
import { ReconciliationWorker } from '../../src/services/reconciliationWorker';
import { PseudonymService } from '../../src/services/pseudonymService';

describe('Live Fabric Reconciliation Worker End-to-End Tests', () => {
  let fabric: FabricGatewayService;
  let recordService: RecordService;
  let worker: ReconciliationWorker;

  const timestamp = Date.now();
  const SYNTH_PATIENT_ID = `pat_synth_rec_${timestamp}`;
  const SYNTH_NOTE_ID = `note_synth_rec_${timestamp}`;
  const SYNTH_NURSE_UID = `nurse_synth_rec_${timestamp}`;

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

    // Calculate canonical SHA-256 hash using aligned RecordService
    const canonicalHash = recordService.computeCanonicalClinicalNoteHash(syntheticNote);
    syntheticNote.fileHash = canonicalHash;

    let updatedStatus = '';
    let updatedTxId = '';

    const mockDocRef: any = {
      id: SYNTH_NOTE_ID,
      update: sinon.stub().callsFake(async (updatePayload: any) => {
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
          get: sinon.stub().resolves({
            exists: true,
            id: SYNTH_NOTE_ID,
            data: () => ({ ...syntheticNote })
          }),
          update: sinon.stub().resolves()
        };
        return await callback(transaction);
      })
    };

    const mockFirebaseAdmin: any = {
      getFirestoreInstance: sinon.stub().returns(mockFirestore),
      updateRecordProof: sinon.stub().resolves()
    };

    worker = new ReconciliationWorker(fabric, mockFirebaseAdmin, recordService);

    // Run reconciliation on real Fabric network
    const result = await worker.reconcilePendingClinicalNotes();

    expect(result.processed).to.equal(1);
    expect(result.committed).to.equal(1);
    expect(result.failed).to.equal(0);

    expect(updatedStatus).to.equal('COMMITTED');
    expect(updatedTxId).to.match(/^[a-fA-F0-9]{64}$/);

    // Verify directly on the live Fabric ledger using opaque record key
    const opaqueRecordKey = PseudonymService.generateOpaqueRecordKey(SYNTH_PATIENT_ID, SYNTH_NOTE_ID);
    const proofStr = await fabric.evaluateTransaction('GetRecordProof', opaqueRecordKey);
    const proof = JSON.parse(proofStr);
    expect(proof.recordId).to.equal(opaqueRecordKey);
    expect(proof.sha256Hash).to.equal(canonicalHash);
    expect(proof.txId).to.equal(updatedTxId);

    // Verify on-chain tamper detection with VerifyRecordHash
    const verifyValidStr = await fabric.evaluateTransaction('VerifyRecordHash', opaqueRecordKey, canonicalHash);
    const verifyValid = JSON.parse(verifyValidStr);
    expect(verifyValid.verified).to.be.true;
    expect(verifyValid.status).to.equal('VERIFIED');

    // Idempotent retry check: running worker again detects existing ledger proof without duplicate commit
    syntheticNote.fabricStatus = 'PENDING';
    const retryResult = await worker.reconcilePendingClinicalNotes();
    expect(retryResult.committed).to.equal(1);
    expect(retryResult.failed).to.equal(0);
  });
});
