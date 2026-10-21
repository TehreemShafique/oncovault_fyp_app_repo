import { expect } from 'chai';
import sinon from 'sinon';
import crypto from 'crypto';
import { RecordService } from '../../src/services/recordService';
import { FabricGatewayService, RecordSubmissionError } from '../../src/services/fabricGateway';
import { ReconciliationService } from '../../src/services/reconciliationService';
import { PseudonymService } from '../../src/services/pseudonymService';
import { MemoryFirestore } from '../helpers/memoryFirestore';

// All Fabric stages and persistence are fake: this suite never connects to Firebase or Fabric.
describe('EHR durable operation bookkeeping and submission stages', () => {
  const user = { uid: 'fictional-doctor', role: 'doctor' as const };
  const record = { recordId: 'fictional-ehr', patientId: 'fictional-patient',
    doctorId: user.uid, isBloodCancerEhr: true, documentType: 'BLOOD_CANCER_EHR',
    createdAt: '2026-10-20T00:00:00Z', cbc: {}, symptoms: {} };
  let db: MemoryFirestore;
  let admin: any;
  let fabric: FabricGatewayService;
  let contract: any;
  let proposal: any;
  let transaction: any;
  let commit: any;
  let service: RecordService;
  let reconciliation: ReconciliationService;
  let proof: any;
  let opId: string;
  let opPath: string;
  const run = () => service.anchorRecord(user, record.recordId,
    { documentType: 'BLOOD_CANCER_EHR' }, 'fictional-stable-key', record.patientId);
  const stored = () => db.documents.get(opPath);
  async function failure(work: Promise<unknown>, message: string) {
    let error: any;
    try { await work; } catch (caught) { error = caught; }
    expect(error?.message).to.include(message);
  }

  beforeEach(() => {
    db = new MemoryFirestore();
    admin = { getFirestoreInstance: () => db, getMedicalRecord: sinon.stub().resolves(record),
      updateRecordProof: sinon.stub().resolves() };
    reconciliation = new ReconciliationService(admin);
    fabric = FabricGatewayService.getInstance();
    service = new RecordService(fabric, admin, reconciliation);
    const hash = service.computeCanonicalEhrHash(record);
    const key = PseudonymService.generateOpaqueRecordKey(record.patientId, record.recordId);
    opId = 'op_anchor_' + crypto.createHash('sha256')
      .update(`${record.patientId}:${record.recordId}:${hash}`).digest('hex').substring(0, 24);
    opPath = `gateway_operations/${opId}`;
    proof = { recordId: key, sha256Hash: hash, txId: 'fictional-proposal', version: 1,
      timestamp: '2026-10-21T12:00:00Z', status: 'ACTIVE' };
    commit = { getStatus: sinon.stub().resolves({ successful: true, code: 0 }) };
    transaction = { submit: sinon.stub().resolves(commit), getResult: () => Buffer.from(JSON.stringify(proof)) };
    proposal = { getTransactionId: () => proof.txId, endorse: sinon.stub().resolves(transaction) };
    contract = { newProposal: sinon.stub().returns(proposal), evaluateTransaction: sinon.stub().callsFake(async (name: string) => {
      if (name === 'CheckConsent') return Buffer.from(JSON.stringify({ active: true, status: 'GRANTED' }));
      throw { code: 2, details: [{ message: `chaincode response 500, Record '${key}' does not exist on ledger.` }] };
    }) };
    sinon.stub(fabric, 'getContract').returns(contract);
  });
  afterEach(() => sinon.restore());

  it('marks the original content-derived operation FAILED only when endorsement never submitted', async () => {
    proposal.endorse.rejects(new Error('10 ABORTED: metadata rejected'));
    await failure(run(), 'metadata rejected');
    expect(stored().operationId).to.equal(opId);
    expect(stored().status).to.equal('FAILED');
    expect(stored().txId).to.equal(proof.txId);
    expect(stored().attempts).to.equal(1);
    expect(db.documents.has(`gateway_operations/op_anchor_${record.recordId}`)).to.equal(false);
    expect(transaction.submit.called).to.equal(false);
    expect(admin.updateRecordProof.called).to.equal(false);
    expect(reconciliation.acquireLock(`anchor:${record.recordId}`)).to.equal(true);
  });

  it('preserves the original idempotency key on a deliberate retry of a definitive rejection', async () => {
    proposal.endorse.onFirstCall().rejects(new Error('Rejected endorsement'));
    await failure(run(), 'Rejected endorsement');
    await run();
    expect(stored().status).to.equal('COMMITTED');
    expect(stored().idempotencyKey).to.equal('fictional-stable-key');
    expect(stored().attempts).to.equal(2);
    expect(transaction.submit.calledOnce).to.equal(true);
  });

  it('keeps a submit/network timeout UNCERTAIN and never automatically submits again', async () => {
    transaction.submit.rejects(new Error('HTTP 500 after possible submission'));
    await failure(run(), 'possible submission');
    expect(stored().status).to.equal('UNCERTAIN_RETRYABLE');
    await failure(run(), 'Previous anchor outcome requires verification');
    expect(transaction.submit.calledOnce).to.equal(true);
    expect(stored().attempts).to.equal(1);
    expect(admin.updateRecordProof.called).to.equal(false);
  });

  it('keeps commit-status timeout UNCERTAIN with the prepared transaction ID', async () => {
    commit.getStatus.rejects(new Error('DEADLINE_EXCEEDED'));
    await failure(run(), 'DEADLINE_EXCEEDED');
    expect(stored().status).to.equal('UNCERTAIN_RETRYABLE');
    expect(stored().txId).to.equal(proof.txId);
    expect(admin.updateRecordProof.called).to.equal(false);
  });

  it('records an explicitly invalid commit as FAILED, never Anchored', async () => {
    commit.getStatus.resolves({ successful: false, code: 11 });
    await failure(run(), 'commit rejected');
    expect(stored().status).to.equal('FAILED');
    expect(admin.updateRecordProof.called).to.equal(false);
  });

  it('browser disconnect does not abandon a continuing Gateway submission or unlock duplicates', async () => {
    let complete!: (value: any) => void;
    commit.getStatus.callsFake(() => new Promise(resolve => { complete = resolve; }));
    const first = run();
    while (!complete) await new Promise(resolve => setImmediate(resolve));
    // The client may have timed out; the original server promise is still running.
    await failure(run(), 'already in progress');
    expect(stored().status).to.equal('PENDING');
    complete({ successful: true, code: 0 });
    await first;
    expect(stored().status).to.equal('COMMITTED');
    expect(transaction.submit.calledOnce).to.equal(true);
  });

  it('a second Gateway instance cannot take over a pending operation even after thirty seconds', async () => {
    db.documents.set(opPath, { operationId: opId, status: 'PENDING', attempts: 1,
      updatedAt: '2020-01-01T00:00:00Z', createdAt: '2020-01-01T00:00:00Z' });
    service = new RecordService(fabric, admin, new ReconciliationService(admin));
    await failure(run(), 'Previous anchor outcome requires verification');
    expect(contract.newProposal.called).to.equal(false);
    expect(stored().status).to.equal('PENDING');
  });

  it('concurrent durable claims do not mutate the winner when the loser conflicts', async () => {
    const claim = () => new ReconciliationService(admin).startOperation(opId, 'ANCHOR_RECORD', record.recordId);
    const results = await Promise.allSettled([claim(), claim()]);
    expect(results.filter(r => r.status === 'fulfilled')).to.have.length(1);
    expect(stored().status).to.equal('PENDING');
    expect(stored().attempts).to.equal(1);
  });

  it('recovers a committed uncertain operation through proof only without another proposal', async () => {
    db.documents.set(opPath, { operationId: opId, status: 'UNCERTAIN_RETRYABLE', attempts: 1,
      txId: proof.txId, idempotencyKey: 'fictional-stable-key' });
    contract.evaluateTransaction.withArgs('GetRecordProof').resolves(Buffer.from(JSON.stringify(proof)));
    const result = await run();
    expect(result.proof.txId).to.equal(proof.txId);
    expect(stored().status).to.equal('COMMITTED');
    expect(contract.newProposal.called).to.equal(false);
  });

  it('confirmed commit and projection failure stay recoverable without duplicate submission', async () => {
    admin.updateRecordProof.rejects(new Error('Projection offline'));
    await failure(run(), 'local metadata synchronization failed');
    expect(stored().status).to.equal('UNCERTAIN_RETRYABLE');
    admin.updateRecordProof.resolves();
    contract.evaluateTransaction.withArgs('GetRecordProof').resolves(Buffer.from(JSON.stringify(proof)));
    await run();
    expect(stored().status).to.equal('COMMITTED');
    expect(transaction.submit.calledOnce).to.equal(true);
  });

  it('does not fall through into submit when syncing a pre-existing identical proof fails', async () => {
    contract.evaluateTransaction.withArgs('GetRecordProof').resolves(Buffer.from(JSON.stringify(proof)));
    admin.updateRecordProof.rejects(new Error('Projection offline'));
    await failure(run(), 'Projection offline');
    expect(stored().status).to.equal('UNCERTAIN_RETRYABLE');
    expect(contract.newProposal.called).to.equal(false);
  });

  it('verified ledger proof takes precedence over a misleading downstream failure classification', async () => {
    contract.evaluateTransaction.withArgs('GetRecordProof').resolves(Buffer.from(JSON.stringify(proof)));
    admin.updateRecordProof.rejects(new RecordSubmissionError('NOT_SUBMITTED', undefined,
      new Error('Projection adapter failure')));
    await failure(run(), 'Projection adapter failure');
    expect(stored().status).to.equal('UNCERTAIN_RETRYABLE');
    expect(contract.newProposal.called).to.equal(false);
  });

  it('a failed ledger lookup never authorizes a fresh submission', async () => {
    contract.evaluateTransaction.withArgs('GetRecordProof').rejects(new Error('Network timeout'));
    await failure(run(), 'Network timeout');
    expect(contract.newProposal.called).to.equal(false);
  });

  it('fails closed when durable claim persistence fails', async () => {
    db.failWrites = () => true;
    await failure(run(), 'Fake persistence failure');
    expect(contract.newProposal.called).to.equal(false);
    expect(db.documents.size).to.equal(0);
  });

  it('never downgrades a separately verified COMMITTED durable record', async () => {
    await reconciliation.startOperation(opId, 'ANCHOR_RECORD', record.recordId);
    db.documents.set(opPath, { ...stored(), status: 'COMMITTED', txId: proof.txId });
    await reconciliation.markStatus(opId, 'UNCERTAIN_RETRYABLE', 'Late timeout');
    expect(stored().status).to.equal('COMMITTED');
  });

  it('successful commit retains canonical hash, neutral metadata and a real confirmed receipt', async () => {
    const result = await run();
    const args = contract.newProposal.firstCall.args[1].arguments;
    expect(args[1]).to.equal(service.computeCanonicalEhrHash(record));
    expect(JSON.parse(args[2])).to.deep.equal({ documentType: 'EHR', schemaVersion: '2.0' });
    expect(result.proof.txId).to.equal(proof.txId);
    expect(stored().status).to.equal('COMMITTED');
    expect(admin.updateRecordProof.calledOnce).to.equal(true);
  });

  it('stage classification does not mistake an endorsement error for an uncertain submit', async () => {
    proposal.endorse.rejects(new Error('Peer validation rejected'));
    try { await fabric.submitTransaction('AnchorRecordHash', 'fictional-key', 'a'.repeat(64), '{}'); }
    catch (e) {
      expect(e).to.be.instanceOf(RecordSubmissionError);
      expect((e as RecordSubmissionError).outcome).to.equal('NOT_SUBMITTED');
      expect(transaction.submit.called).to.equal(false);
      return;
    }
    expect.fail('Expected staged endorsement error');
  });
});
