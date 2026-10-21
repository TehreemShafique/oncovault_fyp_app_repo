import { expect } from 'chai';
import sinon from 'sinon';
import { ReconciliationWorker } from '../../src/services/reconciliationWorker';
import { RecordService } from '../../src/services/recordService';
import { PseudonymService } from '../../src/services/pseudonymService';
import { MemoryFirestore } from '../helpers/memoryFirestore';

/** Reuses the isolated transaction fake; no Firebase initialization or network. */
class WorkerStore extends MemoryFirestore {
  beforeTransaction?: () => void;
  updates = 0;
  doc(path: string): any {
    const ref: any = { path, id: path.split('/').pop() };
    ref.get = async () => ({
      exists: this.documents.has(path), ref, id: ref.id,
      data: () => structuredClone(this.documents.get(path))
    });
    return ref;
  }
  collection(name: string): any {
    return {
      doc: (id: string) => this.doc(name + '/' + id),
      where: (field: string, _op: string, value: any) => ({
        get: async () => ({
          docs:
            [...this.documents.entries()].filter(([p, d]) => p.startsWith(name + '/') && p.split('/').length === 2 && d[field] === value)
              .map(([p]) => ({ ref: this.doc(p), data: () => structuredClone(this.documents.get(p)) }))
        })
      })
    };
  }
  collectionGroup(name: string): any {
    return {
      where: (field: string, _op: string, values: string[]) => ({
        get: async () => ({
          docs:
            [...this.documents.entries()].filter(([p, d]) => p.split('/').at(-2) === name && values.includes(d[field]))
              .map(([p]) => ({ ref: this.doc(p), data: () => structuredClone(this.documents.get(p)) }))
        })
      })
    };
  }
  async runTransaction<T>(callback: (t: any) => Promise<T>): Promise<T> {
    this.beforeTransaction?.(); this.beforeTransaction = undefined;
    return super.runTransaction(t => callback({
      get: t.get, update: (ref: any, changes: any) => {
        this.updates++; t.set(ref, changes, { merge: true });
      }
    }));
  }
}

for (const kind of ['note', 'task', 'progress'] as const) {
  describe('Projection-only worker safety: ' + kind, () => {
    let db: WorkerStore, fabric: any, worker: ReconciliationWorker, hash: string, proof: any, consent: any;
    let sourcePath: string, queuedPath: string;
    const txId = 'b'.repeat(64);
    const patient = 'demo-patient', doctor = 'demo-doctor', nurse = 'demo-nurse', hospital = 'demo-hospital';
    const recordId = 'demo-record', planId = 'demo-plan';
    const treatment = kind !== 'note';
    const records = new RecordService();
    const copy = (d: any) => structuredClone(d);
    const run = () => treatment ? worker.reconcilePendingTreatmentOperations() : worker.reconcilePendingClinicalNotes();
    const patch = (path: string, value: any) => Object.assign(db.documents.get(path), value);
    const makeWorker = () => new ReconciliationWorker(fabric, { getFirestoreInstance: () => db } as any, records);

    beforeEach(() => {
      db = new WorkerStore();
      for (const [path, data] of Object.entries({
        ['patients/' + patient]: { hospitalId: hospital },
        ['users/' + patient]: { role: 'patient' },
        ['users/' + doctor]: { role: 'doctor', hospitalId: hospital },
        ['doctors/' + doctor]: { uid: doctor },
        ['users/' + nurse]: { role: 'nurse', hospitalId: hospital },
        ['nurse_patient_assignments/' + nurse + '_' + patient]: { nurseId: nurse, patientId: patient, status: 'active', hospitalId: hospital },
        ['patients/' + patient + '/treatment_plans/' + planId]: { patientId: patient, hospitalId: hospital, doctorId: doctor, status: 'active' }
      })) db.documents.set(path, data);
      const source: any = kind === 'note'
        ? {
          noteId: recordId, patientId: patient, authorUid: doctor, hospitalId: hospital, noteType: 'progress_note',
          status: 'SUBMITTED', fabricStatus: 'PENDING', createdAtIso: '2026-01-01T00:00:00.000Z', clinicalSummary: 'Fictional demonstration note.'
        }
        : kind === 'task'
          ? { taskId: recordId, patientId: patient, planId, completedByNurseId: nurse, status: 'completed', completedAt: '2026-01-01T00:00:00.000Z', fabricStatus: 'PENDING' }
          : { updateId: recordId, patientId: patient, planId, authorUid: nurse, timestamp: '2026-01-01T00:00:00.000Z', fabricStatus: 'PENDING', clinicalSummary: 'Fictional progress.' };
      hash = kind === 'note' ? records.computeCanonicalClinicalNoteHash(source) : kind === 'task' ? records.computeCanonicalTaskHash(source) : records.computeCanonicalProgressHash(source);
      source.fileHash = hash;
      sourcePath = 'patients/' + patient + (kind === 'note' ? '/clinical_notes/' : '/treatment_plans/' + planId + (kind === 'task' ? '/tasks/' : '/progress_updates/')) + recordId;
      db.documents.set(sourcePath, source);
      queuedPath = treatment ? 'gateway_operations/demo-operation' : sourcePath;
      if (treatment) db.documents.set(queuedPath, {
        operationId: 'demo-operation', operationType: 'ANCHOR_RECORD', documentType: 'TREATMENT_PLAN',
        recordType: kind === 'task' ? 'TREATMENT_TASK_COMPLETION' : 'TREATMENT_PROGRESS', status: 'PENDING',
        patientId: patient, planId, recordId, hospitalId: hospital, sourceDocPath: sourcePath, canonicalHash: hash,
        idempotencyKey: 'demo-original-key', attempts: 1, createdAt: '2026-01-01T00:00:00.000Z'
      });
      const domainId = kind === 'note' ? recordId : (kind === 'task' ? 'task_' : 'tp_') + planId + '_' + recordId;
      const key = PseudonymService.generateOpaqueRecordKey(patient, domainId);
      proof = {
        recordId: key, sha256Hash: hash, txId, version: 1, status: 'ACTIVE', timestamp: '2026-01-01T00:01:00.000Z',
        metadata: { documentType: treatment ? 'TREATMENT_PLAN' : 'CLINICAL_NOTE' }
      };
      consent = {
        status: 'GRANTED', active: true, scope: 'DIRECT_CARE', patientPseudoId: PseudonymService.generatePatientPseudoId(patient),
        providerPseudoId: PseudonymService.generateProviderPseudoId(doctor), expirationTimestamp: null
      };
      fabric = {
        submitTransaction: sinon.stub().throws(new Error('Real submission prohibited')), submitConsentTransaction: sinon.stub().throws(new Error('Prohibited')),
        evaluateTransaction: sinon.stub().callsFake(async (name: string) => {
          if (name === 'CheckConsent') return JSON.stringify(consent);
          if (name === 'GetRecordProof') return JSON.stringify(proof);
          if (name === 'VerifyRecordHash') return JSON.stringify({
            verified: true, status: 'VERIFIED', txId,
            recordId: key, ledgerHash: hash
          });
          throw new Error('Unexpected query');
        })
      };
      worker = makeWorker();
      sinon.stub(console, 'warn');
    });
    afterEach(() => {
      worker.stopPeriodicSweeper();
      expect(fabric.submitTransaction.called).to.equal(false);
      expect(fabric.submitConsentTransaction.called).to.equal(false);
      sinon.restore();
    });
    async function blocked() {
      const before = copy(db.documents.get(queuedPath));
      const result = await run();
      expect(result.committed).to.equal(0); expect(db.updates).to.equal(0);
      expect(db.documents.get(queuedPath)).to.deep.equal(before);
    }
    it('recovers matching proof by projection only, retaining original metadata', async () => {
      const before = copy(db.documents.get(queuedPath));
      const result = await run();
      expect(result.committed).to.equal(1);
      expect(db.documents.get(sourcePath).fabricTxId).to.equal(txId);
      expect(db.documents.get(queuedPath).attempts).to.equal(before.attempts);
      expect(db.documents.get(queuedPath).idempotencyKey).to.equal(before.idempotencyKey);
      expect(db.documents.get(queuedPath).createdAt).to.equal(before.createdAt);
      const updates = db.updates;
      await run(); expect(db.updates).to.equal(updates);
    });
    for (const reason of ['Fabric unavailable', 'DEADLINE_EXCEEDED', 'Record does not exist on ledger', 'UNCERTAIN commit']) {
      it('blocks ' + reason + ' without treating it as permission to submit', async () => {
        fabric.evaluateTransaction.withArgs('GetRecordProof').rejects(new Error(reason)); await blocked();
      });
    }
    it('blocks a different hash rather than creating a ledger revision', async () => { proof.sha256Hash = 'c'.repeat(64); await blocked(); });
    for (const status of ['REVOKED', 'NOT_FOUND', 'EXPIRED']) {
      it('blocks consent ' + status, async () => { consent.status = status; consent.active = false; await blocked(); });
    }
    it('blocks a consent lookup outage without a Firestore fallback', async () => {
      fabric.evaluateTransaction.withArgs('CheckConsent').rejects(new Error('Unavailable')); await blocked();
    });
    it('blocks a malformed or mismatched consent response', async () => { consent.providerPseudoId = 'wrong-provider'; await blocked(); });
    it('blocks missing authoritative patient identity', async () => { db.documents.delete('users/' + patient); await blocked(); });
    it('blocks missing authoritative doctor identity', async () => { db.documents.delete('doctors/' + doctor); await blocked(); });
    it('blocks an unauthorized source author', async () => { db.documents.delete('users/' + (treatment ? nurse : doctor)); await blocked(); });
    it('revalidates source identity and contents before projection', async () => {
      db.beforeTransaction = () => patch(sourcePath, { patientId: 'different-patient' });
      expect((await run()).committed).to.equal(0);
      expect(db.updates).to.equal(0);
      expect(db.documents.get(sourcePath).patientId).to.equal('different-patient');
    });
    it('does not take over a still-live processing lease', async () => {
      patch(queuedPath, { [treatment ? 'status' : 'fabricStatus']: 'PROCESSING', lockExpiresAt: Date.now() + 60000 }); await blocked();
    });
    it('lease expiry permits only proof recovery, not resubmission', async () => {
      patch(queuedPath, { [treatment ? 'status' : 'fabricStatus']: 'PROCESSING', lockExpiresAt: Date.now() - 1 });
      fabric.evaluateTransaction.withArgs('GetRecordProof').rejects(new Error('Timeout')); await blocked();
    });
    it('restart preserves uncertainty until a matching committed proof is available', async () => {
      patch(queuedPath, { [treatment ? 'status' : 'fabricStatus']: 'UNCERTAIN_RETRYABLE', txId });
      fabric.evaluateTransaction.withArgs('GetRecordProof').onFirstCall().rejects(new Error('Unavailable'));
      await blocked(); worker = makeWorker();
      expect((await run()).committed).to.equal(1);
      expect(db.documents.get(queuedPath).txId).to.equal(txId);
    });
    it('a different saved transaction cannot be replaced by an older proof', async () => {
      patch(queuedPath, { txId: 'd'.repeat(64) }); await blocked();
    });
    it('concurrent workers project once and never submit', async () => {
      const second = makeWorker();
      const results = await Promise.all([run(), treatment ? second.reconcilePendingTreatmentOperations() : second.reconcilePendingClinicalNotes()]);
      expect(results.reduce((n, r) => n + r.committed, 0)).to.equal(1);
    });
    it('empty queue does not query Fabric or write bookkeeping', async () => {
      db.documents.delete(queuedPath); await run(); expect(fabric.evaluateTransaction.called).to.equal(false); expect(db.updates).to.equal(0);
    });
    it('never infers automatic submission approval from finalized or synthetic data', async () => {
      patch(sourcePath, { synthetic: true, reviewedBy: doctor, approved: true });
      fabric.evaluateTransaction.withArgs('GetRecordProof').rejects(new Error('Not found')); await blocked();
    });
    it('verification outage cannot turn an unverified receipt into a committed projection', async () => {
      fabric.evaluateTransaction.withArgs('VerifyRecordHash').rejects(new Error('DEADLINE_EXCEEDED')); await blocked();
    });
    it('projection persistence failure retries only recovery after restart', async () => {
      const before = copy(db.documents.get(queuedPath));
      db.failWrites = () => true;
      expect((await run()).committed).to.equal(0);
      expect(db.documents.get(queuedPath)).to.deep.equal(before);
      db.failWrites = () => false;
      worker = makeWorker();
      expect((await run()).committed).to.equal(1);
    });
    it('lease expiration during an in-flight lookup cannot start a Fabric submission', async () => {
      let release!: () => void;
      const gate = new Promise<void>(resolve => { release = resolve; });
      let started!: () => void;
      const entered = new Promise<void>(resolve => { started = resolve; });
      fabric.evaluateTransaction.withArgs('GetRecordProof').callsFake(async () => {
        started(); await gate; return JSON.stringify(proof);
      });
      const first = run(); await entered;
      patch(queuedPath, { [treatment ? 'status' : 'fabricStatus']: 'PROCESSING', lockExpiresAt: Date.now() - 1 });
      const other = makeWorker();
      const second = treatment ? other.reconcilePendingTreatmentOperations() : other.reconcilePendingClinicalNotes();
      release();
      const results = await Promise.all([first, second]);
      expect(results.reduce((n, r) => n + r.committed, 0)).to.equal(1);
    });
    it('a finalization timestamp must be valid', async () => {
      patch(sourcePath, { [kind === 'note' ? 'createdAtIso' : kind === 'task' ? 'completedAt' : 'timestamp']: 'invalid-date' });
      await blocked();
    });
    if (treatment) {
      it('blocks arbitrary source paths', async () => { patch(queuedPath, { sourceDocPath: 'medical_records/unrelated' }); await blocked(); });
      it('blocks unsupported record types', async () => { patch(queuedPath, { recordType: 'UNKNOWN' }); await blocked(); });
      it('blocks a missing queued content fingerprint', async () => { delete db.documents.get(queuedPath).canonicalHash; await blocked(); });
      it('blocks inactive treatment plans', async () => { patch('patients/' + patient + '/treatment_plans/' + planId, { status: 'discontinued' }); await blocked(); });
      it('blocks revoked nursing assignments', async () => { patch('nurse_patient_assignments/' + nurse + '_' + patient, { status: 'revoked' }); await blocked(); });
      it('blocks mismatched durable operation identity', async () => { patch(queuedPath, { operationId: 'different-operation' }); await blocked(); });
      if (kind === 'task') it('blocks an incomplete task', async () => { patch(sourcePath, { status: 'pending' }); await blocked(); });
    } else {
      it('never processes a DRAFT note', async () => { patch(sourcePath, { status: 'DRAFT' }); await blocked(); });
      it('requires a submitted note hash to match actual content', async () => { patch(sourcePath, { clinicalSummary: 'Changed after submission' }); await blocked(); });
      it('does not treat administrator role as automatic clinical approval', async () => { patch('users/' + doctor, { role: 'admin' }); await blocked(); });
    }
  });
}
