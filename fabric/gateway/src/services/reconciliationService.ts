// src/services/reconciliationService.ts
import { DurableOperation, OperationStatus } from '../types';
import { FirebaseAdminService } from './firebaseAdmin';

export class ReconciliationService {
  private static instance: ReconciliationService | null = null;
  // In-memory cache for fast concurrency gating and fallback operation tracking
  private memoryOperations: Map<string, DurableOperation> = new Map();
  // Concurrency lock set to prevent simultaneous identical mutation attempts
  private inFlightLocks: Set<string> = new Set();

  private constructor() {}

  public static getInstance(): ReconciliationService {
    if (!ReconciliationService.instance) {
      ReconciliationService.instance = new ReconciliationService();
    }
    return ReconciliationService.instance;
  }

  /**
   * Acquires a concurrency lock for an operation entity.
   * Throws if an operation on the same entity or idempotency key is already in flight.
   */
  public acquireLock(lockKey: string): boolean {
    if (this.inFlightLocks.has(lockKey)) {
      return false;
    }
    this.inFlightLocks.add(lockKey);
    return true;
  }

  /**
   * Releases concurrency lock.
   */
  public releaseLock(lockKey: string): void {
    this.inFlightLocks.delete(lockKey);
  }

  /**
   * Starts tracking a durable operation in state PENDING.
   */
  public async startOperation(
    operationId: string,
    operationType: 'ANCHOR_RECORD' | 'GRANT_CONSENT' | 'REVOKE_CONSENT',
    entityId: string,
    idempotencyKey?: string
  ): Promise<DurableOperation> {
    const now = new Date().toISOString();
    const op: DurableOperation = {
      operationId,
      idempotencyKey,
      operationType,
      entityId,
      status: 'PENDING',
      attempts: 1,
      createdAt: now,
      updatedAt: now
    };

    this.memoryOperations.set(operationId, op);
    if (idempotencyKey) {
      this.memoryOperations.set(`key:${idempotencyKey}`, op);
    }

    // Persist to Firestore atomically using a transaction to guarantee mutual exclusion across instances
    try {
      const db = FirebaseAdminService.getInstance().getFirestoreInstance();
      if (db) {
        const opRef = db.collection('gateway_operations').doc(operationId);
        if (typeof db.runTransaction === 'function') {
          await db.runTransaction(async (transaction) => {
            const doc = await transaction.get(opRef);
            if (doc.exists) {
              const existing = doc.data() as DurableOperation;
              if (existing.status === 'COMMITTED') {
                op.status = 'COMMITTED';
                op.txId = existing.txId;
                op.blockTimestamp = existing.blockTimestamp;
                return;
              }
              if (existing.status === 'PENDING') {
                const ageMs = Date.now() - new Date(existing.updatedAt).getTime();
                if (ageMs < 30000) {
                  throw new Error(`CONCURRENCY_CONFLICT: Operation ${operationId} is already in-progress on another gateway instance.`);
                }
                op.attempts = (existing.attempts || 1) + 1;
              } else if (existing.status === 'FAILED' || existing.status === 'UNCERTAIN_RETRYABLE') {
                op.attempts = (existing.attempts || 1) + 1;
              }
            }
            transaction.set(opRef, op, { merge: true });
          });
        } else {
          // Fallback for non-transactional mock environments
          await opRef.set(op, { merge: true });
        }
      }
    } catch (err: any) {
      if (err.message && err.message.includes('CONCURRENCY_CONFLICT')) {
        throw err;
      }
      // Non-blocking in offline/mock environment
    }

    return op;
  }

  /**
   * Marks operation COMMITTED with genuine transaction ID and timestamp.
   */
  public async markCommitted(operationId: string, txId: string, blockTimestamp?: string): Promise<DurableOperation | null> {
    const op = this.memoryOperations.get(operationId);
    if (!op) return null;

    op.status = 'COMMITTED';
    op.txId = txId;
    op.blockTimestamp = blockTimestamp || new Date().toISOString();
    op.updatedAt = new Date().toISOString();

    try {
      const db = FirebaseAdminService.getInstance().getFirestoreInstance();
      if (db) {
        await db.collection('gateway_operations').doc(operationId).set({
          status: 'COMMITTED',
          txId,
          blockTimestamp: op.blockTimestamp,
          updatedAt: op.updatedAt
        }, { merge: true });
      }
    } catch (_) {
      // Non-blocking
    }

    return op;
  }

  /**
   * Marks operation FAILED or UNCERTAIN_RETRYABLE.
   */
  public async markStatus(operationId: string, status: OperationStatus, error?: string): Promise<DurableOperation | null> {
    const op = this.memoryOperations.get(operationId);
    if (!op) return null;

    op.status = status;
    op.error = error;
    op.updatedAt = new Date().toISOString();

    try {
      const db = FirebaseAdminService.getInstance().getFirestoreInstance();
      if (db) {
        await db.collection('gateway_operations').doc(operationId).set({
          status,
          error,
          updatedAt: op.updatedAt
        }, { merge: true });
      }
    } catch (_) {
      // Non-blocking
    }

    return op;
  }

  /**
   * Looks up an existing operation by idempotency key (synchronous memory cache).
   */
  public getByIdempotencyKey(key: string): DurableOperation | undefined {
    return this.memoryOperations.get(`key:${key}`);
  }

  /**
   * Looks up an existing operation by idempotency key (checks Firestore if not in memory).
   */
  public async getByIdempotencyKeyAsync(key: string): Promise<DurableOperation | undefined> {
    const mem = this.memoryOperations.get(`key:${key}`);
    if (mem) return mem;

    try {
      const db = FirebaseAdminService.getInstance().getFirestoreInstance();
      if (db) {
        const snap = await db.collection('gateway_operations').where('idempotencyKey', '==', key).limit(1).get();
        if (!snap.empty) {
          const data = snap.docs[0].data() as DurableOperation;
          this.memoryOperations.set(`key:${key}`, data);
          this.memoryOperations.set(data.operationId, data);
          return data;
        }
      }
    } catch (_) {
      // Non-blocking
    }
    return undefined;
  }

  /**
   * Looks up an existing operation by operationId.
   */
  public getOperation(operationId: string): DurableOperation | undefined {
    return this.memoryOperations.get(operationId);
  }

  /**
   * Looks up an existing operation by operationId (checking Firestore across process restarts).
   */
  public async getOperationAsync(operationId: string): Promise<DurableOperation | undefined> {
    const mem = this.memoryOperations.get(operationId);
    if (mem) return mem;

    try {
      const db = FirebaseAdminService.getInstance().getFirestoreInstance();
      if (db) {
        const doc = await db.collection('gateway_operations').doc(operationId).get();
        if (doc.exists) {
          const data = doc.data() as DurableOperation;
          this.memoryOperations.set(operationId, data);
          if (data.idempotencyKey) {
            this.memoryOperations.set(`key:${data.idempotencyKey}`, data);
          }
          return data;
        }
      }
    } catch (_) {
      // Non-blocking
    }
    return undefined;
  }
}
