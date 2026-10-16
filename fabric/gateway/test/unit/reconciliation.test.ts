// test/unit/reconciliation.test.ts
import { expect } from 'chai';
import { ReconciliationService } from '../../src/services/reconciliationService';

describe('ReconciliationService Unit Tests (Concurrency & Idempotency)', () => {
  let reconciliation: ReconciliationService;

  beforeEach(() => {
    reconciliation = ReconciliationService.getInstance();
  });

  it('should acquire and release concurrency lock successfully', () => {
    const lockKey = 'test:lock:1';
    expect(reconciliation.acquireLock(lockKey)).to.be.true;
    // Second attempt should fail while held
    expect(reconciliation.acquireLock(lockKey)).to.be.false;

    reconciliation.releaseLock(lockKey);
    // After release, should succeed again
    expect(reconciliation.acquireLock(lockKey)).to.be.true;
    reconciliation.releaseLock(lockKey);
  });

  it('should track durable operation lifecycle and status transitions', async () => {
    const opId = 'op-rec-001';
    const op = await reconciliation.startOperation(opId, 'ANCHOR_RECORD', 'entity-1', 'idem-key-1');

    expect(op.status).to.equal('PENDING');
    expect(op.operationId).to.equal(opId);

    // Look up by idempotency key
    const retrieved = reconciliation.getByIdempotencyKey('idem-key-1');
    expect(retrieved).to.exist;
    expect(retrieved?.operationId).to.equal(opId);

    // Transition to COMMITTED
    const committed = await reconciliation.markCommitted(opId, 'tx-12345', '2026-10-16T12:00:00Z');
    expect(committed?.status).to.equal('COMMITTED');
    expect(committed?.txId).to.equal('tx-12345');
  });

  it('should support UNCERTAIN_RETRYABLE state when Firestore fails after Fabric commit', async () => {
    const opId = 'op-rec-uncertain';
    await reconciliation.startOperation(opId, 'ANCHOR_RECORD', 'entity-2');

    const updated = await reconciliation.markStatus(
      opId,
      'UNCERTAIN_RETRYABLE',
      'Fabric committed, but database write timed out'
    );

    expect(updated?.status).to.equal('UNCERTAIN_RETRYABLE');
    expect(updated?.error).to.include('Fabric committed');
  });

  it('should reject concurrent startOperation when operation is already PENDING in transaction', async () => {
    const opId = 'op-rec-concurrent-race';
    const operationsStore = new Map<string, any>();
    operationsStore.set(opId, {
      operationId: opId,
      status: 'PENDING',
      updatedAt: new Date().toISOString(),
      attempts: 1
    });

    const mockFirestore = {
      collection: () => ({
        doc: (id: string) => ({
          get: async () => ({
            exists: operationsStore.has(id),
            data: () => operationsStore.get(id)
          }),
          set: async (val: any) => operationsStore.set(id, val)
        })
      }),
      runTransaction: async (updateFunction: any) => {
        const transaction = {
          get: async (docRef: any) => docRef.get(),
          set: (docRef: any, val: any) => docRef.set(val)
        };
        return updateFunction(transaction);
      }
    };

    const { FirebaseAdminService } = await import('../../src/services/firebaseAdmin');
    FirebaseAdminService.getInstance().setMockInstances(null, mockFirestore, null);

    try {
      await reconciliation.startOperation(opId, 'ANCHOR_RECORD', 'rec-race-1');
      expect.fail('Should have thrown CONCURRENCY_CONFLICT');
    } catch (err: any) {
      expect(err.message).to.include('CONCURRENCY_CONFLICT');
    }
  });

  it('should safely permit retry when prior operation is UNCERTAIN_RETRYABLE or FAILED', async () => {
    const opId = 'op-rec-retryable';
    const operationsStore = new Map<string, any>();
    operationsStore.set(opId, {
      operationId: opId,
      status: 'UNCERTAIN_RETRYABLE',
      updatedAt: new Date().toISOString(),
      attempts: 1
    });

    const mockFirestore = {
      collection: () => ({
        doc: (id: string) => ({
          get: async () => ({
            exists: operationsStore.has(id),
            data: () => operationsStore.get(id)
          }),
          set: async (val: any) => operationsStore.set(id, val)
        })
      }),
      runTransaction: async (updateFunction: any) => {
        const transaction = {
          get: async (docRef: any) => docRef.get(),
          set: (docRef: any, val: any) => docRef.set(val)
        };
        return updateFunction(transaction);
      }
    };

    const { FirebaseAdminService } = await import('../../src/services/firebaseAdmin');
    FirebaseAdminService.getInstance().setMockInstances(null, mockFirestore, null);

    const retried = await reconciliation.startOperation(opId, 'ANCHOR_RECORD', 'rec-retry-1');
    expect(retried.status).to.equal('PENDING');
    expect(retried.attempts).to.equal(2);
  });
});
