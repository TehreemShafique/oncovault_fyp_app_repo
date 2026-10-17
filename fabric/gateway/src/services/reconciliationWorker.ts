// src/services/reconciliationWorker.ts
import crypto from 'crypto';
import * as admin from 'firebase-admin';
import { FabricGatewayService } from './fabricGateway';
import { FirebaseAdminService } from './firebaseAdmin';
import { RecordService } from './recordService';
import { PseudonymService } from './pseudonymService';

export class ReconciliationWorker {
  private static instance: ReconciliationWorker | null = null;
  private _fabricGateway?: FabricGatewayService;
  private _firebaseAdmin?: FirebaseAdminService;
  private _recordService?: RecordService;
  private intervalTimer: NodeJS.Timeout | null = null;
  private isReconciling: boolean = false;

  constructor(
    fabricGateway?: FabricGatewayService,
    firebaseAdmin?: FirebaseAdminService,
    recordService?: RecordService
  ) {
    this._fabricGateway = fabricGateway;
    this._firebaseAdmin = firebaseAdmin;
    this._recordService = recordService;
  }

  public static getInstance(): ReconciliationWorker {
    if (!ReconciliationWorker.instance) {
      ReconciliationWorker.instance = new ReconciliationWorker();
    }
    return ReconciliationWorker.instance;
  }

  private get fabricGateway(): FabricGatewayService {
    return this._fabricGateway || FabricGatewayService.getInstance();
  }

  private get firebaseAdmin(): FirebaseAdminService {
    return this._firebaseAdmin || FirebaseAdminService.getInstance();
  }

  private get recordService(): RecordService {
    return (
      this._recordService ||
      new RecordService(this.fabricGateway, this.firebaseAdmin)
    );
  }

  private isReconcilingNotes: boolean = false;
  private isReconcilingTreatment: boolean = false;

  /**
   * Starts a background periodic sweeper loop to discover and anchor PENDING clinical notes and treatment operations.
   */
  public startPeriodicSweeper(intervalMs: number = 10000): void {
    if (this.intervalTimer) {
      return;
    }
    this.intervalTimer = setInterval(async () => {
      try {
        await this.reconcilePendingClinicalNotes();
      } catch (err: any) {
        console.warn(`[ReconciliationWorker] Clinical notes sweeper cycle error: ${err.message}`);
      }
      try {
        await this.reconcilePendingTreatmentOperations();
      } catch (err: any) {
        console.warn(`[ReconciliationWorker] Treatment operations sweeper cycle error: ${err.message}`);
      }
    }, intervalMs);
    console.info(`[+] OncoVault Fabric Reconciliation Worker started (interval: ${intervalMs}ms).`);
  }

  /**
   * Stops the background periodic sweeper loop cleanly.
   */
  public stopPeriodicSweeper(): void {
    if (this.intervalTimer) {
      clearInterval(this.intervalTimer);
      this.intervalTimer = null;
      console.info('[-] OncoVault Fabric Reconciliation Worker stopped.');
    }
  }

  /**
   * Reconciles all pending or retryable clinical notes across patients:
   * 1. Finds submitted or reviewed notes awaiting blockchain anchoring.
   * 2. Acquires atomic lock lease with unique fencing token (PROCESSING).
   * 3. Validates canonical hash integrity before submission.
   * 4. Checks if already anchored on the ledger (idempotent recovery).
   * 5. Submits AnchorRecordHash transaction to Hyperledger Fabric.
   * 6. Verifies on-chain receipt and validates lease fence before marking COMMITTED in Firestore.
   */
  public async reconcilePendingClinicalNotes(): Promise<{
    processed: number;
    committed: number;
    failed: number;
  }> {
    if (this.isReconcilingNotes) {
      return { processed: 0, committed: 0, failed: 0 };
    }

    const db = this.firebaseAdmin.getFirestoreInstance();
    if (!db) {
      return { processed: 0, committed: 0, failed: 0 };
    }

    this.isReconcilingNotes = true;
    let processed = 0;
    let committed = 0;
    let failed = 0;

    try {
      // 1. Query clinical notes in SUBMITTED or REVIEWED status (excluding DRAFT)
      const snapshot = await db
        .collectionGroup('clinical_notes')
        .where('status', 'in', ['SUBMITTED', 'REVIEWED'])
        .get();

      const candidateDocs = snapshot.docs.filter((doc) => {
        const data = doc.data() as Record<string, any>;
        const fStatus = data.fabricStatus || 'PENDING';
        const nowMs = Date.now();
        const leaseExpired = data.lockExpiresAt && data.lockExpiresAt < nowMs;
        const retryEligible = !data.nextRetryAt || data.nextRetryAt <= nowMs;

        return (
          (fStatus === 'PENDING' && retryEligible) ||
          (fStatus === 'FAILED_RETRYABLE' && retryEligible) ||
          (fStatus === 'PROCESSING' && leaseExpired)
        );
      });

      for (const doc of candidateDocs) {
        processed++;
        const noteRef = doc.ref;

        // 2. Atomic Lease Gating with Fencing Token
        let noteData: Record<string, any> | null = null;
        try {
          noteData = await db.runTransaction(async (transaction) => {
            const freshDoc = await transaction.get(noteRef);
            if (!freshDoc.exists) return null;
            const data = freshDoc.data() as Record<string, any>;
            const isFinalized = data.status === 'SUBMITTED' || data.status === 'REVIEWED';
            if (!isFinalized) return null;

            const fStatus = data.fabricStatus || 'PENDING';
            const nowMs = Date.now();
            const leaseExpired = data.lockExpiresAt && data.lockExpiresAt < nowMs;
            const retryEligible = !data.nextRetryAt || data.nextRetryAt <= nowMs;
            const eligible =
              (fStatus === 'PENDING' && retryEligible) ||
              (fStatus === 'FAILED_RETRYABLE' && retryEligible) ||
              (fStatus === 'PROCESSING' && leaseExpired);

            if (!eligible) return null;

            const leaseToken = crypto.randomUUID();
            transaction.update(noteRef, {
              fabricStatus: 'PROCESSING',
              lockExpiresAt: nowMs + 60000, // 60-second lease
              leaseToken,
              processingStartedAt: admin.firestore.FieldValue.serverTimestamp()
            });

            return { ...data, id: freshDoc.id, leaseToken };
          });
        } catch (lockErr: any) {
          console.warn(`[ReconciliationWorker] Lock contention for note ${doc.id}: ${lockErr.message}`);
          continue;
        }

        if (!noteData) {
          continue;
        }

        const noteId = noteData.noteId || noteData.id || doc.id;
        const patientId = noteData.patientId;
        const storedHash = (noteData.fileHash || '').toLowerCase();
        const activeLeaseToken = noteData.leaseToken;

        // 3. Server-side Content Validation & Canonical Hash Recalculation
        const recalculatedHash = this.recordService.computeCanonicalClinicalNoteHash(noteData);
        if (!storedHash || recalculatedHash.toLowerCase() !== storedHash) {
          console.error(
            `[SECURITY] Tamper detected for note '${noteId}' of patient '${patientId}'. Recalculated '${recalculatedHash}' != Stored '${storedHash}'`
          );
          await db.runTransaction(async (t) => {
            const snap = await t.get(noteRef);
            if (!snap.exists) return;
            const curr = snap.data() as Record<string, any>;
            if (curr.leaseToken !== activeLeaseToken) return;
            t.update(noteRef, {
              fabricStatus: 'FAILED_PERMANENT',
              fabricError: 'Canonical hash mismatch / content tampering detected',
              updatedAt: admin.firestore.FieldValue.serverTimestamp()
            });
          });
          failed++;
          continue;
        }

        // 4. Generate deterministic opaque ledger key
        const opaqueRecordKey = PseudonymService.generateOpaqueRecordKey(patientId, noteId);

        // 5. Existing Ledger Proof Check (Deduplication / Idempotent Recovery)
        let alreadyCommitted = false;
        try {
          const proofStr = await this.fabricGateway.evaluateTransaction('GetRecordProof', opaqueRecordKey);
          if (proofStr && proofStr.trim() !== '') {
            const existingProof = JSON.parse(proofStr);
            if (
              existingProof.sha256Hash &&
              existingProof.sha256Hash.toLowerCase() === storedHash
            ) {
              const committedProof = {
                txId: existingProof.txId,
                fileHash: storedHash,
                version: existingProof.version || 1,
                timestamp: existingProof.timestamp,
                opaqueRecordKey
              };

              let fenced = false;
              await db.runTransaction(async (t) => {
                const snap = await t.get(noteRef);
                if (!snap.exists) return;
                const curr = snap.data() as Record<string, any>;
                if (curr.leaseToken !== activeLeaseToken) return;
                t.update(noteRef, {
                  fabricStatus: 'COMMITTED',
                  fabricTxId: existingProof.txId,
                  fabricVersion: existingProof.version || 1,
                  fabricTimestamp: existingProof.timestamp,
                  opaqueRecordKey,
                  lastAnchoredAt: admin.firestore.FieldValue.serverTimestamp()
                });
                fenced = true;
              });

              if (fenced) {
                await this.firebaseAdmin.updateRecordProof(noteId, committedProof, patientId);
                alreadyCommitted = true;
                committed++;
              }
            }
          }
        } catch (_) {
          // Record not yet anchored on ledger — proceed to submit
        }

        if (alreadyCommitted) {
          continue;
        }

        // 6. Submit AnchorRecordHash transaction to Hyperledger Fabric
        try {
          const metadata = {
            documentType: 'CLINICAL_NOTE',
            recordType: (noteData.noteType || 'progress_note').toUpperCase(),
            schemaVersion: '1.0'
          };

          const { result, txId } = await this.fabricGateway.submitTransaction(
            'AnchorRecordHash',
            opaqueRecordKey,
            storedHash,
            JSON.stringify(metadata)
          );

          const proof = JSON.parse(result);

          // 7. Verify transaction commit on ledger
          const verifyStr = await this.fabricGateway.evaluateTransaction(
            'VerifyRecordHash',
            opaqueRecordKey,
            storedHash
          );
          const verifyResult = JSON.parse(verifyStr);
          if (!verifyResult.verified) {
            throw new Error(`Ledger verification failed with status: ${verifyResult.status}`);
          }

          // 8. Update Firestore record atomically to COMMITTED with Lease Fencing Validation
          const committedProof = {
            txId: proof.txId || txId,
            fileHash: storedHash,
            version: proof.version || 1,
            timestamp: proof.timestamp,
            opaqueRecordKey
          };

          let fencedCommit = false;
          await db.runTransaction(async (t) => {
            const snap = await t.get(noteRef);
            if (!snap.exists) {
              throw new Error(`Note '${noteId}' deleted before commit could be written.`);
            }
            const curr = snap.data() as Record<string, any>;
            if (curr.leaseToken !== activeLeaseToken) {
              throw new Error(
                `STALE_LEASE_FENCE: Worker lease token '${activeLeaseToken}' expired or superseded by '${curr.leaseToken}'. Aborting stale commit update.`
              );
            }
            t.update(noteRef, {
              fabricStatus: 'COMMITTED',
              fabricTxId: committedProof.txId,
              fabricVersion: committedProof.version,
              fabricTimestamp: committedProof.timestamp,
              opaqueRecordKey,
              lastAnchoredAt: admin.firestore.FieldValue.serverTimestamp()
            });
            fencedCommit = true;
          });

          if (fencedCommit) {
            await this.firebaseAdmin.updateRecordProof(noteId, committedProof, patientId);
            committed++;
          }
        } catch (err: any) {
          console.warn(
            `[ReconciliationWorker] Anchoring attempt failed for note '${noteId}': ${err.message}`
          );

          try {
            await db.runTransaction(async (t) => {
              const snap = await t.get(noteRef);
              if (!snap.exists) return;
              const curr = snap.data() as Record<string, any>;
              if (curr.leaseToken !== activeLeaseToken) {
                // Lease was already reclaimed by another worker; do not overwrite state with stale failure
                return;
              }
              const retryCount = (curr.retryCount || 0) + 1;
              const isPermanent = retryCount >= 5;
              const nextRetryDelayMs = Math.min(300000, Math.pow(2, retryCount) * 5000); // 10s, 20s, 40s, 80s, 160s, max 5m
              const nextRetryAt = Date.now() + nextRetryDelayMs;

              t.update(noteRef, {
                fabricStatus: isPermanent ? 'FAILED_PERMANENT' : 'FAILED_RETRYABLE',
                retryCount,
                nextRetryAt,
                fabricError: err.message || 'Unknown Fabric submission failure',
                lastFailedAt: admin.firestore.FieldValue.serverTimestamp()
              });
            });
          } catch (fErr: any) {
            console.warn(`[ReconciliationWorker] Failed to record failure state: ${fErr.message}`);
          }
          failed++;
        }
      }
    } finally {
      this.isReconcilingNotes = false;
    }

    return { processed, committed, failed };
  }

  /**
   * Reconciles all pending or retryable treatment operations from gateway_operations:
   * 1. Finds operations for TREATMENT_PLAN (tasks and progress updates).
   * 2. Acquires atomic lock lease with unique fencing token (PROCESSING).
   * 3. Fetches and validates authoritative Firestore source document.
   * 4. Confirms source record is finalized and eligible.
   * 5. Computes canonical SHA-256 digest from resolved persisted values.
   * 6. Generates deterministic domain-separated opaque record key.
   * 7. Checks if already anchored on the ledger (idempotent recovery).
   * 8. Submits AnchorRecordHash transaction to Hyperledger Fabric.
   * 9. Verifies on-chain receipt and validates lease fence before marking COMMITTED.
   * 10. Handles bounded retry and permanent failure transitions.
   */
  public async reconcilePendingTreatmentOperations(): Promise<{
    processed: number;
    committed: number;
    failed: number;
  }> {
    if (this.isReconcilingTreatment) {
      return { processed: 0, committed: 0, failed: 0 };
    }

    const db = this.firebaseAdmin.getFirestoreInstance();
    if (!db) {
      return { processed: 0, committed: 0, failed: 0 };
    }

    this.isReconcilingTreatment = true;
    let processed = 0;
    let committed = 0;
    let failed = 0;

    try {
      // 1. Query gateway_operations for TREATMENT_PLAN documents
      const snapshot = await db
        .collection('gateway_operations')
        .where('documentType', '==', 'TREATMENT_PLAN')
        .get();

      const candidateDocs = snapshot.docs.filter((doc) => {
        const data = doc.data() as Record<string, any>;
        const opStatus = data.status || 'PENDING';
        const nowMs = Date.now();
        const leaseExpired = data.lockExpiresAt && data.lockExpiresAt < nowMs;
        const retryEligible = !data.nextRetryAt || data.nextRetryAt <= nowMs;

        return (
          (opStatus === 'PENDING' && retryEligible) ||
          (opStatus === 'FAILED_RETRYABLE' && retryEligible) ||
          (opStatus === 'PROCESSING' && leaseExpired)
        );
      });

      for (const doc of candidateDocs) {
        processed++;
        const opRef = doc.ref;

        // 2. Atomic Lease Gating with Fencing Token
        let opData: Record<string, any> | null = null;
        try {
          opData = await db.runTransaction(async (transaction) => {
            const freshOp = await transaction.get(opRef);
            if (!freshOp.exists) return null;
            const data = freshOp.data() as Record<string, any>;

            const opStatus = data.status || 'PENDING';
            const nowMs = Date.now();
            const leaseExpired = data.lockExpiresAt && data.lockExpiresAt < nowMs;
            const retryEligible = !data.nextRetryAt || data.nextRetryAt <= nowMs;
            const eligible =
              (opStatus === 'PENDING' && retryEligible) ||
              (opStatus === 'FAILED_RETRYABLE' && retryEligible) ||
              (opStatus === 'PROCESSING' && leaseExpired);

            if (!eligible) return null;

            const leaseToken = crypto.randomUUID();
            transaction.update(opRef, {
              status: 'PROCESSING',
              lockExpiresAt: nowMs + 60000, // 60-second lease
              leaseToken,
              processingStartedAt: admin.firestore.FieldValue.serverTimestamp()
            });

            return { ...data, id: freshOp.id, leaseToken };
          });
        } catch (lockErr: any) {
          console.warn(`[ReconciliationWorker] Lock contention for operation ${doc.id}: ${lockErr.message}`);
          continue;
        }

        if (!opData) {
          continue;
        }

        const activeLeaseToken = opData.leaseToken;
        const recordId = opData.recordId || doc.id;
        const patientId = opData.patientId;
        const planId = opData.planId;
        const recordType = opData.recordType || 'TREATMENT_TASK_COMPLETION';

        // 3. Validate Required Operation Fields
        if (!patientId || !planId || !recordId || !opData.sourceDocPath) {
          console.error(`[ReconciliationWorker] Incomplete operation record '${doc.id}'`);
          await db.runTransaction(async (t) => {
            const curr = await t.get(opRef);
            if (!curr.exists) return;
            if (curr.data()?.leaseToken !== activeLeaseToken) return;
            t.update(opRef, {
              status: 'FAILED_PERMANENT',
              error: 'Missing required operation fields (patientId, planId, recordId, or sourceDocPath)',
              updatedAt: admin.firestore.FieldValue.serverTimestamp()
            });
          });
          failed++;
          continue;
        }

        // Resolve and Fetch Authoritative Source Document
        const sourceDocPath = opData.sourceDocPath;
        const sourceRef = db.doc(sourceDocPath);
        const sourceSnap = await sourceRef.get();

        if (!sourceSnap.exists) {
          console.error(`[ReconciliationWorker] Source document not found at: ${sourceDocPath}`);
          await db.runTransaction(async (t) => {
            const curr = await t.get(opRef);
            if (!curr.exists) return;
            if (curr.data()?.leaseToken !== activeLeaseToken) return;
            t.update(opRef, {
              status: 'FAILED_PERMANENT',
              error: 'Source clinical document not found',
              updatedAt: admin.firestore.FieldValue.serverTimestamp()
            });
          });
          failed++;
          continue;
        }

        const sourceData = sourceSnap.data() as Record<string, any>;

        // 4. Validate Cross-Patient / Cross-Plan Substitution Boundary
        if (sourceData.patientId !== patientId || sourceData.planId !== planId) {
          console.error(
            `[SECURITY] Cross-patient/plan mismatch for operation '${doc.id}': source (${sourceData.patientId}/${sourceData.planId}) != op (${patientId}/${planId})`
          );
          await db.runTransaction(async (t) => {
            const curr = await t.get(opRef);
            if (!curr.exists) return;
            if (curr.data()?.leaseToken !== activeLeaseToken) return;
            t.update(opRef, {
              status: 'FAILED_PERMANENT',
              error: 'Security violation: Cross-patient or cross-plan document substitution detected',
              updatedAt: admin.firestore.FieldValue.serverTimestamp()
            });
          });
          failed++;
          continue;
        }

        // 5. Validate Finalization and Eligibility
        if (recordType === 'TREATMENT_TASK_COMPLETION') {
          if (sourceData.status !== 'completed' || !sourceData.completedAt) {
            console.warn(`[ReconciliationWorker] Task '${recordId}' is not finalized (status: ${sourceData.status})`);
            await db.runTransaction(async (t) => {
              const curr = await t.get(opRef);
              if (!curr.exists) return;
              if (curr.data()?.leaseToken !== activeLeaseToken) return;
              t.update(opRef, {
                status: 'FAILED_RETRYABLE',
                nextRetryAt: Date.now() + 30000,
                error: 'Source task not yet completed or timestamp pending'
              });
            });
            failed++;
            continue;
          }
        }

        // 6. Calculate Canonical SHA-256 Digest from Resolved Persisted Record
        let calculatedHash = '';
        if (recordType === 'TREATMENT_TASK_COMPLETION') {
          calculatedHash = this.recordService.computeCanonicalTaskHash(sourceData);
        } else {
          calculatedHash = this.recordService.computeCanonicalProgressHash(sourceData);
        }

        // Tamper detection against queued hash (if provided) or previously recorded hash
        if (opData.canonicalHash && opData.canonicalHash.toLowerCase() !== calculatedHash.toLowerCase()) {
          console.error(
            `[SECURITY] Tamper detected for operation '${doc.id}': op hash '${opData.canonicalHash}' != recomputed '${calculatedHash}'`
          );
          await db.runTransaction(async (t) => {
            const curr = await t.get(opRef);
            if (!curr.exists) return;
            if (curr.data()?.leaseToken !== activeLeaseToken) return;
            t.update(opRef, {
              status: 'FAILED_PERMANENT',
              error: 'Canonical hash mismatch / content tampering detected',
              updatedAt: admin.firestore.FieldValue.serverTimestamp()
            });
          });
          failed++;
          continue;
        }

        // 6. Generate Deterministic Domain-Separated Opaque Ledger Key
        const domainRecordId =
          recordType === 'TREATMENT_TASK_COMPLETION'
            ? `task_${planId}_${recordId}`
            : `tp_${planId}_${recordId}`;
        const opaqueRecordKey = PseudonymService.generateOpaqueRecordKey(patientId, domainRecordId);

        // 7. Check Existing Ledger Proof (Idempotent Recovery)
        let alreadyCommitted = false;
        try {
          const proofStr = await this.fabricGateway.evaluateTransaction('GetRecordProof', opaqueRecordKey);
          if (proofStr && proofStr.trim() !== '') {
            const existingProof = JSON.parse(proofStr);
            if (
              existingProof.sha256Hash &&
              existingProof.sha256Hash.toLowerCase() === calculatedHash.toLowerCase()
            ) {
              let fenced = false;
              await db.runTransaction(async (t) => {
                const freshOp = await t.get(opRef);
                if (!freshOp.exists) return;
                const currOp = freshOp.data() as Record<string, any>;
                if (currOp.leaseToken !== activeLeaseToken) return;

                t.update(sourceRef, {
                  fabricStatus: 'COMMITTED',
                  fabricTxId: existingProof.txId,
                  fabricVersion: existingProof.version || 1,
                  fabricTimestamp: existingProof.timestamp,
                  fileHash: calculatedHash,
                  opaqueRecordKey,
                  lastAnchoredAt: admin.firestore.FieldValue.serverTimestamp()
                });

                t.update(opRef, {
                  status: 'COMMITTED',
                  fabricTxId: existingProof.txId,
                  fabricVersion: existingProof.version || 1,
                  fabricTimestamp: existingProof.timestamp,
                  payloadHash: calculatedHash,
                  opaqueRecordKey,
                  committedAt: admin.firestore.FieldValue.serverTimestamp()
                });
                fenced = true;
              });

              if (fenced) {
                alreadyCommitted = true;
                committed++;
              }
            }
          }
        } catch (_) {
          // Record not yet on ledger — proceed to anchor
        }

        if (alreadyCommitted) {
          continue;
        }

        // 8. Submit AnchorRecordHash to Hyperledger Fabric
        try {
          const metadata = {
            documentType: 'TREATMENT_PLAN',
            recordType: recordType.toUpperCase(),
            schemaVersion: '1.0'
          };

          const { result, txId } = await this.fabricGateway.submitTransaction(
            'AnchorRecordHash',
            opaqueRecordKey,
            calculatedHash,
            JSON.stringify(metadata)
          );

          const proof = JSON.parse(result);

          // 9. Verify Transaction Commit on Ledger
          const verifyStr = await this.fabricGateway.evaluateTransaction(
            'VerifyRecordHash',
            opaqueRecordKey,
            calculatedHash
          );
          const verifyResult = JSON.parse(verifyStr);
          if (!verifyResult.verified) {
            throw new Error(`Ledger verification failed with status: ${verifyResult.status}`);
          }

          // 10. Update Firestore Documents Atomically with Lease Fencing Validation
          const committedProof = {
            txId: proof.txId || txId,
            fileHash: calculatedHash,
            version: proof.version || 1,
            timestamp: proof.timestamp,
            opaqueRecordKey
          };

          let fencedCommit = false;
          await db.runTransaction(async (t) => {
            const freshOp = await t.get(opRef);
            if (!freshOp.exists) throw new Error('Operation record deleted');
            const currOp = freshOp.data() as Record<string, any>;
            if (currOp.leaseToken !== activeLeaseToken) {
              throw new Error(
                `STALE_LEASE_FENCE: Worker lease token '${activeLeaseToken}' expired or superseded by '${currOp.leaseToken}'. Aborting stale commit update.`
              );
            }

            t.update(sourceRef, {
              fabricStatus: 'COMMITTED',
              fabricTxId: committedProof.txId,
              fabricVersion: committedProof.version,
              fabricTimestamp: committedProof.timestamp,
              fileHash: calculatedHash,
              opaqueRecordKey,
              lastAnchoredAt: admin.firestore.FieldValue.serverTimestamp()
            });

            t.update(opRef, {
              status: 'COMMITTED',
              fabricTxId: committedProof.txId,
              fabricVersion: committedProof.version,
              fabricTimestamp: committedProof.timestamp,
              payloadHash: calculatedHash,
              opaqueRecordKey,
              committedAt: admin.firestore.FieldValue.serverTimestamp()
            });
            fencedCommit = true;
          });

          if (fencedCommit) {
            committed++;
          }
        } catch (err: any) {
          console.warn(
            `[ReconciliationWorker] Anchoring attempt failed for treatment operation '${recordId}': ${err.message}`
          );

          try {
            await db.runTransaction(async (t) => {
              const freshOp = await t.get(opRef);
              if (!freshOp.exists) return;
              const currOp = freshOp.data() as Record<string, any>;
              if (currOp.leaseToken !== activeLeaseToken) {
                return;
              }
              const retryCount = (currOp.retryCount || 0) + 1;
              const isPermanent = retryCount >= 5;
              const nextRetryDelayMs = Math.min(300000, Math.pow(2, retryCount) * 5000);
              const nextRetryAt = Date.now() + nextRetryDelayMs;

              t.update(opRef, {
                status: isPermanent ? 'FAILED_PERMANENT' : 'FAILED_RETRYABLE',
                retryCount,
                nextRetryAt,
                error: err.message || 'Unknown Fabric submission failure',
                lastFailedAt: admin.firestore.FieldValue.serverTimestamp()
              });

              t.update(sourceRef, {
                fabricStatus: isPermanent ? 'FAILED_PERMANENT' : 'FAILED_RETRYABLE',
                fabricError: err.message || 'Unknown Fabric submission failure'
              });
            });
          } catch (fErr: any) {
            console.warn(`[ReconciliationWorker] Failed to record failure state: ${fErr.message}`);
          }
          failed++;
        }
      }
    } finally {
      this.isReconcilingTreatment = false;
    }

    return { processed, committed, failed };
  }
}
