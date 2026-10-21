// src/services/reconciliationService.ts
import { ConsentOperation, DurableOperation, OperationStatus } from '../types';
import { FirebaseAdminService } from './firebaseAdmin';

export class ReconciliationService {
  private static instance: ReconciliationService | null = null;
  // In-memory cache for fast concurrency gating and fallback operation tracking
  private memoryOperations: Map<string, DurableOperation> = new Map();
  // Concurrency lock set to prevent simultaneous identical mutation attempts
  private inFlightLocks: Set<string> = new Set();

  constructor(private readonly firebaseAdmin?: Pick<FirebaseAdminService, 'getFirestoreInstance'>) {}

  private consentDatabase(): any {
    const db = (this.firebaseAdmin || FirebaseAdminService.getInstance()).getFirestoreInstance();
    if (!db || typeof db.runTransaction !== 'function') {
      throw new Error('Consent operation storage unavailable; no transaction submitted.');
    }
    return db;
  }

  /** Atomic durable claim and scope guard shared by all request keys and instances. */
  public async claimConsentOperation(operation: ConsentOperation): Promise<{ operation: ConsentOperation; claimed: boolean }> {
    const db = this.consentDatabase();
    const collection = db.collection('gateway_operations');
    return db.runTransaction(async (transaction: any) => {
      const ref = collection.doc(operation.operationId);
      const guardRef = collection.doc(operation.guardId);
      const prior = await transaction.get(ref);
      const guard = await transaction.get(guardRef);
      if (prior.exists) {
        const existing = prior.data() as ConsentOperation;
        if (existing.fingerprint !== operation.fingerprint) {
          throw new Error('Conflict: Idempotency key was already used with different consent parameters.');
        }
        return { operation: existing, claimed: false };
      }
      if (guard.exists && guard.data().activeOperationId) {
        throw new Error('CONSENT_PENDING: An earlier consent operation requires confirmation. Do not submit a new request.');
      }
      transaction.set(ref, operation);
      transaction.set(guardRef, { activeOperationId: operation.operationId });
      return { operation, claimed: true };
    });
  }

  public async getPendingConsentOperation(guardId: string): Promise<ConsentOperation | null> {
    const db = this.consentDatabase();
    return db.runTransaction(async (transaction: any) => {
      const guard = await transaction.get(db.collection('gateway_operations').doc(guardId));
      const id = guard.data()?.activeOperationId;
      if (!id) return null;
      const snapshot = await transaction.get(db.collection('gateway_operations').doc(id));
      const operation = snapshot.data() as ConsentOperation;
      if (!snapshot.exists || operation.guardId !== guardId || operation.operationId !== id) {
        throw new Error('Consent operation storage unavailable.');
      }
      return operation;
    });
  }

  /** No lease expiry or stale-lock takeover for potentially submitted transactions. */
  public async updateConsentOperation(operation: ConsentOperation, changes: Partial<ConsentOperation>, release = false): Promise<ConsentOperation> {
    const db = this.consentDatabase();
    return db.runTransaction(async (transaction: any) => {
      const ref = db.collection('gateway_operations').doc(operation.operationId);
      const guardRef = db.collection('gateway_operations').doc(operation.guardId);
      const snapshot = await transaction.get(ref);
      const guard = await transaction.get(guardRef);
      if (!snapshot.exists || snapshot.data().fingerprint !== operation.fingerprint) {
        throw new Error('Consent operation storage unavailable.');
      }
      const current = snapshot.data() as ConsentOperation;
      // Racing read-only recovery cannot downgrade a verified commit.
      if (current.status === 'COMMITTED') {
        if (changes.status === 'COMMITTED' && changes.txId !== current.txId) {
          throw new Error('Conflict: A different transaction receipt cannot replace a verified commit.');
        }
        return current;
      }
      if (guard.data()?.activeOperationId !== operation.operationId) {
        throw new Error('Conflict: Consent operation no longer owns its scope guard.');
      }
      const updated = { ...current, ...changes, updatedAt: new Date().toISOString() };
      transaction.set(ref, updated);
      if (release) transaction.set(guardRef, { activeOperationId: null });
      return updated;
    });
  }

  /** Projection, bookkeeping and scope release are atomic; old receipts cannot overwrite newer state. */
  public async projectConsentOperation(operation: ConsentOperation): Promise<ConsentOperation> {
    const db = this.consentDatabase();
    return db.runTransaction(async (transaction: any) => {
      const ref = db.collection('gateway_operations').doc(operation.operationId);
      const guardRef = db.collection('gateway_operations').doc(operation.guardId);
      const snapshot = await transaction.get(ref);
      const guard = await transaction.get(guardRef);
      const current = snapshot.data() as ConsentOperation;
      if (!snapshot.exists || current?.status !== 'COMMITTED' || !current.consent?.txId) {
        throw new Error('Consent commit has not been verified.');
      }
      if (!current.projectionPending) return current;
      if (guard.data()?.activeOperationId !== operation.operationId) {
        throw new Error('Conflict: Consent projection no longer owns its scope guard.');
      }
      const projection = {
        patientId: current.patientId, doctorId: current.providerId, scope: current.scope,
        status: current.consent.status === 'REVOKED' ? 'revoked' : 'granted',
        fabricTxId: current.consent.txId, fabricStatus: 'COMMITTED', blockchainVerified: true,
        timestamp: current.consent.timestamp, expirationTimestamp: current.consent.expirationTimestamp ?? null
      };
      transaction.set(db.collection('doctor_patient_consents').doc(current.guardId), { ...projection, id: current.guardId });
      // Retain the existing DIRECT_CARE projection contract without changing EHR fallback logic.
      if (current.scope === 'DIRECT_CARE') {
        const legacyId = `${current.patientId}_${current.providerId}`;
        transaction.set(db.collection('doctor_patient_consents').doc(legacyId), { ...projection, id: legacyId }, { merge: true });
      }
      const updated = { ...current, projectionPending: false, updatedAt: new Date().toISOString() };
      transaction.set(ref, updated);
      transaction.set(guardRef, { activeOperationId: null });
      return updated;
    });
  }

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

    const db = (this.firebaseAdmin || FirebaseAdminService.getInstance()).getFirestoreInstance();
    if (!db || typeof db.runTransaction !== 'function') {
      throw new Error('Anchor operation storage unavailable; no transaction submitted.');
    }
    const claimed = await db.runTransaction(async (transaction: any) => {
      const ref = db.collection('gateway_operations').doc(operationId);
      const snapshot = await transaction.get(ref);
      if (snapshot.exists) {
        const existing = snapshot.data() as DurableOperation;
        if (existing.status === 'COMMITTED') return existing;
        // A restart or elapsed lease does not prove that an earlier submit failed.
        if (existing.status !== 'FAILED') {
          throw new Error('CONCURRENCY_CONFLICT: Anchor outcome unresolved; no new transaction submitted.');
        }
        op.attempts = (existing.attempts || 1) + 1;
        op.createdAt = existing.createdAt;
        op.idempotencyKey = existing.idempotencyKey || idempotencyKey;
      }
      // Replace a definitively failed attempt; do not carry its old proposal receipt.
      transaction.set(ref, op);
      return op;
    });
    this.memoryOperations.set(operationId, claimed);
    if (claimed.idempotencyKey) this.memoryOperations.set(`key:${claimed.idempotencyKey}`, claimed);
    return claimed;
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
      const db = (this.firebaseAdmin || FirebaseAdminService.getInstance()).getFirestoreInstance();
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
  public async markStatus(operationId: string, status: OperationStatus, error?: string, txId?: string): Promise<DurableOperation | null> {
    const op = this.memoryOperations.get(operationId);
    if (!op) return null;
    const changes = { status, error: error || '', updatedAt: new Date().toISOString(), ...(txId ? { txId } : {}) };
    const db = (this.firebaseAdmin || FirebaseAdminService.getInstance()).getFirestoreInstance();
    if (!db || typeof db.runTransaction !== 'function') {
      throw new Error('Anchor operation storage unavailable; outcome remains unresolved.');
    }
    const updated = await db.runTransaction(async (transaction: any) => {
      const ref = db.collection('gateway_operations').doc(operationId);
      const snapshot = await transaction.get(ref);
      if (!snapshot.exists) throw new Error('Anchor operation not found.');
      const current = snapshot.data() as DurableOperation;
      // A late timeout must never downgrade a separately verified commit.
      if (current.status === 'COMMITTED') return current;
      transaction.set(ref, changes, { merge: true });
      return { ...current, ...changes };
    });
    this.memoryOperations.set(operationId, updated);
    if (updated.idempotencyKey) this.memoryOperations.set(`key:${updated.idempotencyKey}`, updated);
    return updated;
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
      const db = (this.firebaseAdmin || FirebaseAdminService.getInstance()).getFirestoreInstance();
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
      const db = (this.firebaseAdmin || FirebaseAdminService.getInstance()).getFirestoreInstance();
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
