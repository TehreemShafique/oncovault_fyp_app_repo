import { expect } from 'chai';
import sinon from 'sinon';
import express from 'express';
import request from 'supertest';
import consentRoutes from '../../src/routes/consent';
import { errorHandler } from '../../src/middleware/errorHandler';
import { FirebaseAdminService } from '../../src/services/firebaseAdmin';
import { config } from '../../src/config/env';
import { ConsentService } from '../../src/services/consentService';
import { ReconciliationService } from '../../src/services/reconciliationService';
import { ConsentSubmissionError, FabricGatewayService } from '../../src/services/fabricGateway';
import { MemoryFirestore } from '../helpers/memoryFirestore';

const patient = { uid: 'fictional-patient', role: 'patient' as const };
const provider = 'fictional-doctor';
const key = 'fictional-stable-request-001';
const scope = 'DIRECT_CARE';
async function rejects(work: Promise<unknown>, message: string) {
  let caught: any;
  try { await work; } catch (error) { caught = error; }
  expect(caught?.message).to.include(message);
}

describe('Consent transaction safety (fake persistence and Fabric only)', () => {
  let db: MemoryFirestore;
  let fabric: any;
  let service: ConsentService;
  let admin: any;
  let receipt: any;
  let history: any[];
  let originalFlag: boolean;
  const makeService = () => new ConsentService(fabric, new ReconciliationService(admin), admin);
  const grant = (requestKey = key, expiry = 'NEVER') => service.grantConsent(patient, provider, scope, expiry, requestKey);
  const revoke = (requestKey = key) => service.revokeConsent(patient, provider, scope, requestKey);
  beforeEach(() => {
    originalFlag = config.enableLiveConsentMutations;
    config.enableLiveConsentMutations = true; // Test process only; all dispatch is fake.
    db = new MemoryFirestore();
    db.documents.set('users/fictional-patient', { role: 'patient' });
    db.documents.set('users/fictional-doctor', { role: 'doctor', uid: provider });
    db.documents.set('doctors/fictional-doctor', { uid: provider });
    admin = { getFirestoreInstance: () => db };
    history = [];
    fabric = {
      evaluateTransaction: sinon.stub().callsFake(async (name: string) => JSON.stringify(
        name === 'GetConsentHistory' ? history : { status: 'NOT_FOUND', active: false })),
      submitConsentTransaction: sinon.stub().callsFake(async (name: string, args: string[], prepared: any) => {
        const txId = `fictional-tx-${fabric.submitConsentTransaction.callCount}`;
        await prepared(txId);
        receipt = {
          patientPseudoId: args[0], providerPseudoId: args[1], scope: args[2],
          status: name === 'GrantConsent' ? 'GRANTED' : 'REVOKED',
          expirationTimestamp: args[3] === 'NEVER' || !args[3] ? null : args[3],
          timestamp: new Date().toISOString(), txId
        };
        history.push({ txId, value: receipt, isDelete: false });
        return { txId, result: JSON.stringify(receipt) };
      })
    };
    service = makeService();
  });
  afterEach(() => { config.enableLiveConsentMutations = originalFlag; sinon.restore(); });

  it('duplicate grant returns the original confirmed receipt without another dispatch', async () => {
    const first = await grant();
    expect((await grant()).consent).to.deep.equal(first.consent);
    expect(fabric.submitConsentTransaction.callCount).to.equal(1);
  });
  it('duplicate revoke returns the original confirmed receipt', async () => {
    fabric.evaluateTransaction.resolves(JSON.stringify({ status: 'GRANTED', active: true }));
    const first = await revoke();
    expect((await revoke()).consent).to.deep.equal(first.consent);
    expect(fabric.submitConsentTransaction.callCount).to.equal(1);
  });
  it('concurrent identical requests dispatch at most once', async () => {
    const results = await Promise.allSettled([grant(), grant()]);
    expect(results.some(result => result.status === 'fulfilled')).to.equal(true);
    expect(fabric.submitConsentTransaction.callCount).to.equal(1);
  });
  it('concurrent different keys cannot bypass the scope guard', async () => {
    let finish!: () => void;
    const wait = new Promise<void>(resolve => { finish = resolve; });
    const original = fabric.submitConsentTransaction;
    fabric.submitConsentTransaction = sinon.stub().callsFake(async (...args: any[]) => {
      await wait;
      return original(...args);
    });
    const first = grant();
    // Wait until durable claim is visible without wall-clock sleeps.
    while (!Array.from(db.documents.keys()).some(path => path.includes('gateway_operations/consent_scope_'))) await new Promise(resolve => setImmediate(resolve));
    await rejects(grant('fictional-other-request-002'), 'CONSENT_PENDING');
    finish();
    await first;
    expect(fabric.submitConsentTransaction.callCount).to.equal(1);
  });
  it('rejects key reuse for another operation type', async () => {
    await grant();
    await rejects(revoke(), 'different consent parameters');
    expect(fabric.submitConsentTransaction.callCount).to.equal(1);
  });
  it('rejects key reuse with different expiry', async () => {
    await grant();
    await rejects(grant(key, '2099-01-01T00:00:00Z'), 'different consent parameters');
  });
  it('rejects key reuse with a different provider', async () => {
    await grant();
    db.documents.set('users/fictional-other-doctor', { role: 'doctor' });
    db.documents.set('doctors/fictional-other-doctor', {});
    await rejects(service.grantConsent(patient, 'fictional-other-doctor', scope, 'NEVER', key), 'different consent parameters');
  });
  it('browser timeout retry recovers the exact transaction from history without resubmission', async () => {
    const original = fabric.submitConsentTransaction;
    fabric.submitConsentTransaction = sinon.stub().callsFake(async (...args: any[]) => {
      await original(...args);
      throw new ConsentSubmissionError('UNCERTAIN');
    });
    await rejects(grant(), 'CONSENT_PENDING');
    const result = await grant();
    expect(result.consent.txId).to.equal(receipt.txId);
    expect(result.operationStatus).to.equal('COMMITTED');
    expect(fabric.submitConsentTransaction.callCount).to.equal(1);
  });
  it('process restart recovers from durable storage, not a memory cache', async () => {
    const original = fabric.submitConsentTransaction;
    fabric.submitConsentTransaction = sinon.stub().callsFake(async (...args: any[]) => {
      await original(...args); throw new ConsentSubmissionError('UNCERTAIN');
    });
    await rejects(grant(), 'CONSENT_PENDING');
    service = makeService();
    expect((await grant()).consent.txId).to.equal(receipt.txId);
    expect(fabric.submitConsentTransaction.callCount).to.equal(1);
  });
  it('empty history never releases an uncertain claim, even with a new key', async () => {
    fabric.submitConsentTransaction.callsFake(async (_name: string, _args: string[], prepared: any) => {
      await prepared('fictional-uncertain-tx'); throw new ConsentSubmissionError('UNCERTAIN');
    });
    await rejects(grant(), 'CONSENT_PENDING');
    service = makeService();
    await rejects(grant(), 'CONSENT_PENDING');
    await rejects(grant('fictional-new-key-002'), 'CONSENT_PENDING');
    expect(fabric.submitConsentTransaction.callCount).to.equal(1);
  });
  it('crash before saving a txId remains blocked rather than assuming nothing was submitted', async () => {
    fabric.submitConsentTransaction.rejects(new Error('simulated crash'));
    await rejects(grant(), 'CONSENT_PENDING');
    service = makeService();
    await rejects(grant(), 'CONSENT_PENDING');
    expect(fabric.submitConsentTransaction.callCount).to.equal(1);
  });
  it('explicit rejection is terminal and releases only the scope guard', async () => {
    fabric.submitConsentTransaction.rejects(new ConsentSubmissionError('REJECTED'));
    await rejects(grant(), 'CONSENT_REJECTED');
    await rejects(grant(), 'CONSENT_REJECTED');
    expect(fabric.submitConsentTransaction.callCount).to.equal(1);
    const guard = [...db.documents.values()].find(value => 'activeOperationId' in value);
    expect(guard.activeOperationId).to.equal(null);
  });
  it('rejects a missing doctor without dispatch', async () => {
    db.documents.delete('doctors/fictional-doctor');
    await rejects(grant(), 'verified registered doctor');
    expect(fabric.submitConsentTransaction.called).to.equal(false);
  });
  it('rejects a mismatched doctor identity', async () => {
    db.documents.set('doctors/fictional-doctor', { uid: 'fictional-wrong-doctor' });
    await rejects(grant(), 'verified registered doctor');
  });
  for (const role of [undefined, 'doctor']) {
    it(`fails closed for missing or incorrect authoritative patient role (${role})`, async () => {
      db.documents.set('users/fictional-patient', role ? { role } : {});
      await rejects(grant(), 'authoritative patient role');
      expect(fabric.submitConsentTransaction.called).to.equal(false);
    });
  }
  it('fails closed for absent authoritative patient record despite request role', async () => {
    db.documents.delete('users/fictional-patient');
    await rejects(grant(), 'authoritative patient role');
  });
  for (const expiry of ['not-a-date', '2020-01-01T00:00:00Z', '2099-02-30T00:00:00Z']) {
    it(`rejects invalid/past expiry ${expiry} before dispatch`, async () => {
      await rejects(grant(key, expiry), 'Invalid consent expiration');
      expect(fabric.submitConsentTransaction.called).to.equal(false);
    });
  }
  it('accepts a valid future expiry without changing the contract format', async () => {
    expect((await grant(key, '2099-01-01T00:00:00Z')).consent.expirationTimestamp).to.equal('2099-01-01T00:00:00.000Z');
  });
  it('projection failure preserves verified commit and retries projection only', async () => {
    db.failWrites = path => path.startsWith('doctor_patient_consents/');
    const first = await grant();
    expect(first.operationStatus).to.equal('COMMITTED');
    expect(first.projectionStatus).to.equal('PENDING');
    await rejects(revoke('fictional-revoke-request-002'), 'CONSENT_PENDING');
    db.failWrites = () => false;
    service = makeService();
    expect((await grant()).projectionStatus).to.equal('SYNCED');
    expect(fabric.submitConsentTransaction.callCount).to.equal(1);
  });
  it('receipt mismatch cannot become proof or a Firestore projection', async () => {
    fabric.submitConsentTransaction.callsFake(async (_name: string, _args: string[], prepared: any) => {
      await prepared('fictional-real-tx');
      return { txId: 'fictional-real-tx', result: JSON.stringify({ txId: 'fictional-wrong-tx' }) };
    });
    await rejects(grant(), 'CONSENT_PENDING');
    expect([...db.documents.keys()].some(path => path.startsWith('doctor_patient_consents/'))).to.equal(false);
  });
  it('persistence outage prevents dispatch', async () => {
    db.failWrites = () => true;
    await rejects(grant(), 'Fake persistence failure');
    expect(fabric.submitConsentTransaction.called).to.equal(false);
  });
  it('failed durable receipt write is recovered by txId without dispatching again', async () => {
    db.failWrites = (_path, value) => value.status === 'COMMITTED';
    await rejects(grant(), 'CONSENT_PENDING');
    db.failWrites = () => false;
    service = makeService();
    expect((await grant()).consent.txId).to.equal(receipt.txId);
    expect(fabric.submitConsentTransaction.callCount).to.equal(1);
  });
  it('scope-aware projection and legacy Direct Care projection agree', async () => {
    const result = await grant();
    const projection = db.documents.get('doctor_patient_consents/fictional-patient_fictional-doctor');
    expect(projection.scope).to.equal('DIRECT_CARE');
    expect(projection.id).to.equal('fictional-patient_fictional-doctor');
    expect(projection.fabricTxId).to.equal(result.consent.txId);
    expect([...db.documents.keys()].filter(path => path.startsWith('doctor_patient_consents/'))).to.have.length(2);
  });
  it('replaying an old grant after revoke cannot overwrite the new projection', async () => {
    const first = await grant();
    fabric.evaluateTransaction.callsFake(async (name: string) => JSON.stringify(name === 'GetConsentHistory' ? history : { status: 'GRANTED', active: true }));
    await revoke('fictional-revoke-request-002');
    expect((await grant()).consent.txId).to.equal(first.consent.txId);
    expect(db.documents.get('doctor_patient_consents/fictional-patient_fictional-doctor').status).to.equal('revoked');
    expect(fabric.submitConsentTransaction.callCount).to.equal(2);
  });
  it('a fresh key cannot duplicate an already active grant', async () => {
    fabric.evaluateTransaction.resolves(JSON.stringify({ status: 'GRANTED', active: true }));
    await rejects(grant(), 'CONSENT_REJECTED');
    expect(fabric.submitConsentTransaction.called).to.equal(false);
  });
  it('concurrent duplicate revocations dispatch at most once', async () => {
    fabric.evaluateTransaction.resolves(JSON.stringify({ status: 'GRANTED', active: true }));
    await Promise.allSettled([revoke(), revoke()]);
    expect(fabric.submitConsentTransaction.callCount).to.equal(1);
  });
  it('a missing provider user record fails closed even when a doctor profile exists', async () => {
    db.documents.delete('users/fictional-doctor');
    await rejects(grant(), 'verified registered doctor');
    expect(fabric.submitConsentTransaction.called).to.equal(false);
  });
  it('mismatched authoritative patient UID fails closed', async () => {
    db.documents.set('users/fictional-patient', { role: 'patient', uid: 'fictional-other-patient' });
    await rejects(grant(), 'authoritative patient role');
  });
  it('scope mismatch rejects reuse of the same key', async () => {
    await grant();
    await rejects(service.grantConsent(patient, provider, 'BLOOD_CANCER_RESEARCH', 'NEVER', key), 'different consent parameters');
  });
  it('missing durable persistence cannot fall back to memory-only submission', async () => {
    service = new ConsentService(fabric, new ReconciliationService({ getFirestoreInstance: () => null } as any), admin);
    await rejects(grant(), 'storage unavailable');
    expect(fabric.submitConsentTransaction.called).to.equal(false);
  });
  it('an arbitrarily old pending operation never becomes eligible for takeover', async () => {
    fabric.submitConsentTransaction.rejects(new ConsentSubmissionError('UNCERTAIN'));
    await rejects(grant(), 'CONSENT_PENDING');
    for (const [path, value] of db.documents) {
      if (value.fingerprint) db.documents.set(path, { ...value, createdAt: '2000-01-01T00:00:00Z', updatedAt: '2000-01-01T00:00:00Z' });
    }
    service = makeService();
    await rejects(grant(), 'CONSENT_PENDING');
    expect(fabric.submitConsentTransaction.callCount).to.equal(1);
  });
  it('history outage during recovery keeps the claim pending', async () => {
    fabric.submitConsentTransaction.callsFake(async (_name: string, _args: string[], prepared: any) => {
      await prepared('fictional-uncertain-tx'); throw new ConsentSubmissionError('UNCERTAIN');
    });
    await rejects(grant(), 'CONSENT_PENDING');
    fabric.evaluateTransaction.rejects(new Error('history unavailable'));
    await rejects(grant(), 'CONSENT_PENDING');
    expect(fabric.submitConsentTransaction.callCount).to.equal(1);
  });
  it('accepts a valid fractional-second future expiry', async () => {
    expect((await grant(key, '2099-01-01T00:00:00.1Z')).consent.expirationTimestamp).to.equal('2099-01-01T00:00:00.100Z');
  });
  it('accepts a valid offset future expiry and normalizes it to UTC', async () => {
    expect((await grant(key, '2099-01-01T05:00:00+05:00')).consent.expirationTimestamp).to.equal('2099-01-01T00:00:00.000Z');
  });
  it('saved proposal ID must match the confirmed SDK receipt ID', async () => {
    const original = fabric.submitConsentTransaction;
    fabric.submitConsentTransaction = sinon.stub().callsFake(async (...args: any[]) => {
      const result = await original(...args);
      const value = JSON.parse(result.result);
      return { txId: 'fictional-other-sdk-tx', result: JSON.stringify({ ...value, txId: 'fictional-other-sdk-tx' }) };
    });
    await rejects(grant(), 'CONSENT_PENDING');
    expect([...db.documents.keys()].some(path => path.startsWith('doctor_patient_consents/'))).to.equal(false);
  });
  it('explicit recovery after restart resolves existing history even with mutations disabled', async () => {
    const original = fabric.submitConsentTransaction;
    fabric.submitConsentTransaction = sinon.stub().callsFake(async (...args: any[]) => {
      await original(...args); throw new ConsentSubmissionError('UNCERTAIN');
    });
    await rejects(grant(), 'CONSENT_PENDING');
    config.enableLiveConsentMutations = false;
    service = makeService();
    const recovered: any = await service.reconcileConsent(patient, provider, scope);
    expect(recovered.consent.txId).to.equal(receipt.txId);
    expect(recovered.projectionStatus).to.equal('SYNCED');
    expect(fabric.submitConsentTransaction.callCount).to.equal(1);
  });
  it('explicit recovery with no existing operation never creates or submits one', async () => {
    config.enableLiveConsentMutations = false;
    expect(await service.reconcileConsent(patient, provider, scope)).to.deep.equal({ operationStatus: 'NONE' });
    expect(db.documents.size).to.equal(3);
    expect(fabric.submitConsentTransaction.called).to.equal(false);
  });
  it('explicit recovery cannot infer a commit from empty history', async () => {
    fabric.submitConsentTransaction.callsFake(async (_name: string, _args: string[], prepared: any) => {
      await prepared('fictional-unknown-tx'); throw new ConsentSubmissionError('UNCERTAIN');
    });
    await rejects(grant(), 'CONSENT_PENDING');
    config.enableLiveConsentMutations = false;
    await rejects(service.reconcileConsent(patient, provider, scope), 'CONSENT_PENDING');
    expect(fabric.submitConsentTransaction.callCount).to.equal(1);
  });
  it('explicit recovery retries a confirmed projection without enabling ledger writes', async () => {
    db.failWrites = path => path.startsWith('doctor_patient_consents/');
    await grant();
    config.enableLiveConsentMutations = false;
    db.failWrites = () => false;
    const result: any = await service.reconcileConsent(patient, provider, scope);
    expect(result.projectionStatus).to.equal('SYNCED');
    expect(fabric.submitConsentTransaction.callCount).to.equal(1);
  });
  it('disabled gate prevents all identity/persistence and submission work', async () => {
    config.enableLiveConsentMutations = false;
    await rejects(grant(), 'FEATURE_DISABLED');
    expect(db.documents.size).to.equal(3);
    expect(fabric.submitConsentTransaction.called).to.equal(false);
  });
});

describe('Fabric consent dispatch phases (SDK fakes only)', () => {
  let gateway: FabricGatewayService;
  let transaction: any;
  let prepared: any;
  beforeEach(() => {
    gateway = FabricGatewayService.getInstance();
    transaction = { submit: sinon.stub().resolves({ getStatus: sinon.stub().resolves({ successful: true }) }),
      getResult: () => Buffer.from('{"txId":"fictional-sdk-tx"}') };
    sinon.stub(gateway, 'getContract').returns({ newProposal: () => ({
      getTransactionId: () => 'fictional-sdk-tx', endorse: async () => transaction
    }) } as any);
    prepared = sinon.stub().resolves();
  });
  afterEach(() => sinon.restore());
  it('persists genuine txId before submitting and verifies commit', async () => {
    const result = await gateway.submitConsentTransaction('GrantConsent', [], prepared);
    expect(result.txId).to.equal('fictional-sdk-tx');
    sinon.assert.callOrder(prepared, transaction.submit);
  });
  it('does not submit if saving the proposal txId fails', async () => {
    prepared.rejects(new Error('storage failed'));
    await rejects(gateway.submitConsentTransaction('GrantConsent', [], prepared), 'NOT_SUBMITTED');
    expect(transaction.submit.called).to.equal(false);
  });
  it('classifies network failure during submission as uncertain', async () => {
    transaction.submit.rejects(new Error('connection lost'));
    await rejects(gateway.submitConsentTransaction('GrantConsent', [], prepared), 'UNCERTAIN');
  });
  it('classifies commit-status timeout as uncertain', async () => {
    transaction.submit.resolves({ getStatus: sinon.stub().rejects(new Error('deadline')) });
    await rejects(gateway.submitConsentTransaction('GrantConsent', [], prepared), 'UNCERTAIN');
  });
  it('classifies explicit invalid commit as rejected', async () => {
    transaction.submit.resolves({ getStatus: sinon.stub().resolves({ successful: false }) });
    await rejects(gateway.submitConsentTransaction('RevokeConsent', [], prepared), 'REJECTED');
  });
});

describe('Consent recovery route authorization (no live services)', () => {
  let app: express.Application;
  let db: MemoryFirestore;
  let fakeAdmin: any;
  let fakeFabric: any;
  let originalFlag: boolean;
  beforeEach(() => {
    originalFlag = config.enableLiveConsentMutations;
    config.enableLiveConsentMutations = false;
    db = new MemoryFirestore();
    db.documents.set('users/fictional-patient', { role: 'patient' });
    db.documents.set('users/fictional-doctor', { role: 'doctor' });
    db.documents.set('doctors/fictional-doctor', {});
    fakeAdmin = { verifyIdToken: sinon.stub().resolves({ uid: patient.uid, role: 'patient' }),
      getAuthoritativeUser: sinon.stub().resolves(patient), getFirestoreInstance: () => db };
    fakeFabric = { submitConsentTransaction: sinon.stub().throws(new Error('Unexpected dispatch')),
      evaluateTransaction: sinon.stub().throws(new Error('Unexpected query')) };
    sinon.stub(FirebaseAdminService, 'getInstance').returns(fakeAdmin);
    sinon.stub(FabricGatewayService, 'getInstance').returns(fakeFabric);
    app = express();
    app.use(express.json());
    app.use('/consent', consentRoutes);
    app.use(errorHandler);
  });
  afterEach(() => { config.enableLiveConsentMutations = originalFlag; sinon.restore(); });
  it('rejects unauthenticated recovery', async () => {
    expect((await request(app).post('/consent/reconcile').send({ providerId: provider, scope })).status).to.equal(401);
    expect(fakeFabric.submitConsentTransaction.called).to.equal(false);
  });
  it('authenticates recovery and returns NONE without submitting while mutations are disabled', async () => {
    const response = await request(app).post('/consent/reconcile').set('Authorization', 'Bearer fictional-token').send({ providerId: provider, scope });
    expect(response.status).to.equal(200);
    expect(response.body.data.operationStatus).to.equal('NONE');
    expect(fakeFabric.submitConsentTransaction.called).to.equal(false);
    expect(fakeFabric.evaluateTransaction.called).to.equal(false);
  });
  it('rejects malformed recovery requests', async () => {
    const response = await request(app).post('/consent/reconcile').set('Authorization', 'Bearer fictional-token').send({});
    expect(response.status).to.equal(400);
  });
  it('default patient token role cannot bypass missing authoritative identity', async () => {
    fakeAdmin.getAuthoritativeUser.resolves(null);
    db.documents.delete('users/fictional-patient');
    const response = await request(app).post('/consent/reconcile').set('Authorization', 'Bearer fictional-token').send({ providerId: provider, scope });
    expect(response.status).to.equal(403);
    expect(fakeFabric.submitConsentTransaction.called).to.equal(false);
  });
  it('authenticated grant remains blocked by the live mutation gate', async () => {
    const response = await request(app).post('/consent/grant').set('Authorization', 'Bearer fictional-token').set('X-Idempotency-Key', key).send({ providerId: provider, scope });
    expect(response.status).to.equal(403);
    expect(response.body.error.code).to.equal('FEATURE_DISABLED');
    expect(fakeFabric.submitConsentTransaction.called).to.equal(false);
  });
});
