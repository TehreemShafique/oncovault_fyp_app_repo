import * as admin from 'firebase-admin';
import { FabricGatewayService } from './fabricGateway';
import { FirebaseAdminService } from './firebaseAdmin';
import { RecordService } from './recordService';
import { PseudonymService } from './pseudonymService';

type Data = Record<string, any>;
type Read = (ref: any) => Promise<any>;
type Summary = { processed: number; committed: number; failed: number; blocked?: number };
type Candidate = {
  source: any; operation?: any; patient: string; actor: string; provider?: string;
  id: string; domainId: string; hash: string; type: string; hospital: string; fingerprint: string;
};
class Blocked extends Error { }

/**
 * Projection-only recovery. Finalization and queue membership are not approval
 * for a new Fabric write. The current schema has no authoritative automatic
 * submission approval, so this worker deliberately has NO Fabric submit path.
 * Existing durable identities, keys, attempts and uncertain outcomes are retained.
 */
export class ReconciliationWorker {
  private static instance: ReconciliationWorker | null = null;
  private intervalTimer: NodeJS.Timeout | null = null;
  private isReconcilingNotes = false;
  private isReconcilingTreatment = false;
  constructor(
    private readonly _fabricGateway?: FabricGatewayService,
    private readonly _firebaseAdmin?: FirebaseAdminService,
    private readonly _recordService?: RecordService
  ) { }
  public static getInstance(): ReconciliationWorker {
    return this.instance || (this.instance = new ReconciliationWorker());
  }
  private get fabricGateway(): FabricGatewayService { return this._fabricGateway || FabricGatewayService.getInstance(); }
  private get firebaseAdmin(): FirebaseAdminService { return this._firebaseAdmin || FirebaseAdminService.getInstance(); }
  private get recordService(): RecordService { return this._recordService || new RecordService(this.fabricGateway, this.firebaseAdmin); }

  public startPeriodicSweeper(intervalMs = 10000): void {
    if (this.intervalTimer) return;
    this.intervalTimer = setInterval(async () => {
      for (const run of [() => this.reconcilePendingClinicalNotes(), () => this.reconcilePendingTreatmentOperations()]) {
        try { await run(); }
        catch (_) { console.warn('[ReconciliationWorker] Recovery query unavailable; no Fabric submission.'); }
      }
    }, intervalMs);
    console.info('[+] OncoVault projection-only reconciliation started (interval: ' + intervalMs + 'ms).');
  }
  public stopPeriodicSweeper(): void {
    if (this.intervalTimer) clearInterval(this.intervalTimer);
    this.intervalTimer = null;
  }
  private require(condition: unknown, reason: string): asserts condition { if (!condition) throw new Blocked(reason); }
  private id(value: unknown): value is string { return typeof value === 'string' && value.length > 0 && !value.includes('/'); }
  private hash(value: unknown): value is string { return typeof value === 'string' && /^[a-f0-9]{64}$/i.test(value); }
  private date(value: any): boolean {
    const date = value?.toDate ? value.toDate() : new Date(value);
    return value != null && Number.isFinite(date.getTime()) && date.getTime() <= Date.now();
  }
  private eligible(data: Data, field: string): boolean {
    const status = data[field] || 'PENDING';
    if (status === 'COMMITTED') return data.projectionPending === true;
    // Lease expiry permits a proof READ, never a takeover or new submission.
    if (status === 'PROCESSING') return typeof data.lockExpiresAt === 'number' && data.lockExpiresAt < Date.now();
    return ['PENDING', 'FAILED_RETRYABLE', 'UNCERTAIN_RETRYABLE'].includes(status) &&
      (!data.nextRetryAt || data.nextRetryAt <= Date.now());
  }

  private async candidate(db: any, ref: any, treatment: boolean, read: Read): Promise<Candidate> {
    const snapshot = await read(ref);
    this.require(snapshot.exists, 'SOURCE_MISSING');
    const operation = snapshot.data() as Data;
    let source = ref, data = operation, plan: Data | undefined;
    const patient = operation.patientId;
    this.require(this.id(patient), 'PATIENT_IDENTITY_MISSING');
    let id: string, domainId: string, actor: string, provider: string | undefined, hash: string, type: string;
    if (treatment) {
      this.require(operation.operationId === ref.id && operation.operationType === 'ANCHOR_RECORD' &&
        operation.documentType === 'TREATMENT_PLAN', 'OPERATION_IDENTITY_MISMATCH');
      this.require(this.eligible(operation, 'status'), 'OPERATION_NOT_RECOVERABLE');
      this.require(this.id(operation.planId) && this.id(operation.recordId), 'SOURCE_IDENTITY_MISSING');
      id = operation.recordId;
      type = operation.recordType;
      this.require(['TREATMENT_TASK_COMPLETION', 'TREATMENT_PROGRESS'].includes(type), 'UNSUPPORTED_SOURCE_TYPE');
      const segment = type === 'TREATMENT_TASK_COMPLETION' ? 'tasks' : 'progress_updates';
      const path = 'patients/' + patient + '/treatment_plans/' + operation.planId + '/' + segment + '/' + id;
      this.require(operation.sourceDocPath === path, 'SOURCE_PATH_MISMATCH');
      source = db.doc(path);
      const sourceSnapshot = await read(source);
      this.require(sourceSnapshot.exists, 'SOURCE_MISSING');
      data = sourceSnapshot.data();
      this.require(data.patientId === patient && data.planId === operation.planId, 'SOURCE_OWNERSHIP_MISMATCH');
      const planSnapshot = await read(db.doc('patients/' + patient + '/treatment_plans/' + operation.planId));
      this.require(planSnapshot.exists, 'PLAN_MISSING');
      plan = planSnapshot.data();
      // Reuse the execution boundary; inactive-plan historical recovery requires
      // an explicit policy decision rather than an automatic exception.
      this.require(plan?.patientId === patient && (!plan.planId || plan.planId === operation.planId) &&
        plan.status === 'active', 'PLAN_NOT_ACTIVE');
      provider = plan.doctorId;
      this.require(this.id(provider), 'PLAN_DOCTOR_MISSING');
      if (type === 'TREATMENT_TASK_COMPLETION') {
        this.require(data.taskId === id && data.status === 'completed' && this.date(data.completedAt), 'TASK_NOT_FINALIZED');
        actor = data.completedByNurseId || data.performerUid;
        if (data.completedByNurseId && data.performerUid) this.require(data.completedByNurseId === data.performerUid, 'ACTOR_IDENTITY_MISMATCH');
        hash = this.recordService.computeCanonicalTaskHash(data);
        domainId = 'task_' + operation.planId + '_' + id;
      } else {
        this.require(data.updateId === id && this.date(data.timestamp), 'PROGRESS_NOT_FINALIZED');
        actor = data.authorUid || data.authorId;
        hash = this.recordService.computeCanonicalProgressHash(data);
        domainId = 'tp_' + operation.planId + '_' + id;
      }
      const queuedHash = operation.canonicalHash || operation.payloadHash;
      this.require(this.hash(queuedHash) && queuedHash.toLowerCase() === hash, 'QUEUED_CONTENT_IDENTITY_UNPROVEN');
      for (const fingerprint of [operation.canonicalHash, operation.payloadHash]) {
        this.require(!fingerprint || (this.hash(fingerprint) && fingerprint.toLowerCase() === hash), 'QUEUED_CONTENT_IDENTITY_UNPROVEN');
      }
    } else {
      id = ref.id;
      type = 'CLINICAL_NOTE';
      this.require(operation.noteId === id && ref.path === 'patients/' + patient + '/clinical_notes/' + id, 'NOTE_IDENTITY_MISMATCH');
      this.require(['SUBMITTED', 'REVIEWED'].includes(data.status) && this.eligible(data, 'fabricStatus'), 'NOTE_NOT_FINALIZED');
      this.require(typeof data.noteType === 'string' && data.noteType.trim() && this.date(data.createdAtIso || data.createdAt), 'NOTE_SCHEMA_INVALID');
      actor = data.authorUid || data.authorId;
      hash = this.recordService.computeCanonicalClinicalNoteHash(data);
      this.require(this.hash(data.fileHash) && data.fileHash.toLowerCase() === hash, 'CONTENT_HASH_MISMATCH');
      domainId = id;
    }
    this.require(this.id(actor) && this.hash(hash), 'ACTOR_OR_HASH_MISSING');
    if (data.authorUid && data.authorId) this.require(data.authorUid === data.authorId, 'ACTOR_IDENTITY_MISMATCH');
    if (data.fileHash) this.require(data.fileHash.toLowerCase() === hash, 'CONTENT_HASH_MISMATCH');
    const patientSnapshot = await read(db.doc('patients/' + patient));
    const patientUser = await read(db.doc('users/' + patient));
    const patientData = patientSnapshot.data();
    this.require(patientSnapshot.exists && patientUser.exists && patientUser.data()?.role === 'patient' &&
      (!patientData?.uid || patientData.uid === patient), 'PATIENT_NOT_AUTHORITATIVE');
    const hospital = patientData?.hospitalId;
    this.require(this.id(hospital) && (treatment ? !data.hospitalId || data.hospitalId === hospital : data.hospitalId === hospital) &&
      (!plan || (plan.hospitalId === hospital && operation.hospitalId === hospital)), 'HOSPITAL_BOUNDARY_UNPROVEN');
    const actorSnapshot = await read(db.doc('users/' + actor));
    const user = actorSnapshot.data();
    this.require(actorSnapshot.exists && user?.hospitalId === hospital && !['inactive', 'suspended'].includes(user.status), 'ACTOR_NOT_AUTHORIZED');
    if (user.role === 'doctor') {
      this.require(!treatment, 'TREATMENT_ACTOR_NOT_ASSIGNED_NURSE');
      provider = actor;
    } else {
      this.require(['nurse', 'house_officer'].includes(user.role), 'ACTOR_ROLE_UNSUPPORTED');
      const assignment = await read(db.doc('nurse_patient_assignments/' + actor + '_' + patient));
      const a = assignment.data();
      this.require(assignment.exists && a?.status === 'active' && a.nurseId === actor && a.patientId === patient && a.hospitalId === hospital, 'ASSIGNMENT_NOT_ACTIVE');
    }
    if (provider) {
      const doctorUser = await read(db.doc('users/' + provider));
      const doctorProfile = await read(db.doc('doctors/' + provider));
      this.require(doctorUser.exists && doctorUser.data()?.role === 'doctor' && doctorUser.data()?.hospitalId === hospital &&
        !['inactive', 'suspended'].includes(doctorUser.data()?.status) && doctorProfile.exists &&
        (!doctorProfile.data()?.uid || doctorProfile.data()?.uid === provider) &&
        (!doctorProfile.data()?.hospitalId || doctorProfile.data()?.hospitalId === hospital), 'DOCTOR_NOT_AUTHORITATIVE');
    }
    return {
      source, operation: treatment ? ref : undefined, patient, actor, provider, id, domainId, hash, type, hospital,
      fingerprint: JSON.stringify([patient, actor, provider, id, domainId, hash, type, hospital,
        operation.operationId, operation.idempotencyKey, operation.canonicalHash, operation.payloadHash])
    };
  }

  private async consent(candidate: Candidate): Promise<void> {
    if (!candidate.provider) return; // Nursing authorship uses the existing assignment boundary.
    const patient = PseudonymService.generatePatientPseudoId(candidate.patient);
    const provider = PseudonymService.generateProviderPseudoId(candidate.provider);
    const result = JSON.parse(await this.fabricGateway.evaluateTransaction('CheckConsent', patient, provider, 'DIRECT_CARE'));
    this.require(result.active === true && result.status === 'GRANTED' && result.scope === 'DIRECT_CARE' &&
      result.patientPseudoId === patient && result.providerPseudoId === provider, 'CONSENT_NOT_CONFIRMED');
    if (result.expirationTimestamp != null) this.require(Number.isFinite(Date.parse(result.expirationTimestamp)) &&
      Date.parse(result.expirationTimestamp) > Date.now(), 'CONSENT_EXPIRED');
  }

  private async recover(db: any, ref: any, treatment: boolean): Promise<boolean> {
    const candidate = await this.candidate(db, ref, treatment, r => r.get());
    await this.consent(candidate); // Never use the deferred Doctor EHR Firestore fallback.
    const key = PseudonymService.generateOpaqueRecordKey(candidate.patient, candidate.domainId);
    // Any exception (including NOT_FOUND), invalid response, or different hash
    // blocks recovery. None can authorize a new anchor or an automatic revision.
    const proof = JSON.parse(await this.fabricGateway.evaluateTransaction('GetRecordProof', key));
    this.require(proof?.recordId === key && proof.status === 'ACTIVE' && proof.sha256Hash === candidate.hash &&
      this.hash(proof.txId) && Number.isInteger(proof.version) && proof.version > 0 && this.date(proof.timestamp), 'MATCHING_COMMITTED_PROOF_REQUIRED');
    this.require(proof.metadata?.documentType === (treatment ? 'TREATMENT_PLAN' : 'CLINICAL_NOTE'), 'PROOF_TYPE_MISMATCH');
    const verification = JSON.parse(await this.fabricGateway.evaluateTransaction('VerifyRecordHash', key, candidate.hash));
    this.require(verification.verified === true && verification.status === 'VERIFIED' && verification.txId === proof.txId &&
      verification.recordId === key && verification.ledgerHash === candidate.hash, 'COMMIT_PROOF_UNCONFIRMED');
    await this.consent(candidate);
    // Reuse fresh Firestore transactions on the existing source/operation docs.
    // No operation or key is created; no expired submission lease is reclaimed.
    return db.runTransaction(async (transaction: any) => {
      const snapshot = await transaction.get(ref);
      const current = snapshot.data();
      if (current && (treatment ? current.status : current.fabricStatus) === 'COMMITTED' && !current.projectionPending) return false;
      const fresh = await this.candidate(db, ref, treatment, r => transaction.get(r));
      this.require(fresh.fingerprint === candidate.fingerprint, 'SOURCE_CHANGED_DURING_RECOVERY');
      const sourceSnapshot = await transaction.get(fresh.source);
      for (const data of [current, sourceSnapshot.data()]) {
        for (const txId of [data?.txId, data?.fabricTxId]) this.require(!txId || txId === proof.txId, 'DIFFERENT_TRANSACTION_REQUIRES_RECONCILIATION');
      }
      const projection = {
        fabricStatus: 'COMMITTED', fabricTxId: proof.txId, fabricVersion: proof.version,
        fabricTimestamp: proof.timestamp, fileHash: candidate.hash, opaqueRecordKey: key,
        lastAnchoredAt: admin.firestore.Timestamp.fromDate(new Date(proof.timestamp)),
        ...(sourceSnapshot.data()?.projectionPending !== undefined ? { projectionPending: false } : {})
      };
      transaction.update(fresh.source, projection);
      if (fresh.operation) transaction.update(fresh.operation, {
        status: 'COMMITTED', fabricTxId: proof.txId, txId: proof.txId, fabricVersion: proof.version,
        fabricTimestamp: proof.timestamp, opaqueRecordKey: key,
        ...(current.projectionPending !== undefined ? { projectionPending: false } : {})
      });
      return true;
    });
  }

  private async reconcile(treatment: boolean): Promise<Summary> {
    const summary: Summary = { processed: 0, committed: 0, failed: 0, blocked: 0 };
    if (treatment ? this.isReconcilingTreatment : this.isReconcilingNotes) return summary;
    if (treatment) this.isReconcilingTreatment = true; else this.isReconcilingNotes = true;
    try {
      const db = this.firebaseAdmin.getFirestoreInstance();
      if (!db) return summary;
      const query = treatment ? db.collection('gateway_operations').where('documentType', '==', 'TREATMENT_PLAN')
        : db.collectionGroup('clinical_notes').where('status', 'in', ['SUBMITTED', 'REVIEWED']);
      const snapshot = await query.get();
      for (const doc of snapshot.docs) {
        if (!this.eligible(doc.data(), treatment ? 'status' : 'fabricStatus')) continue;
        summary.processed++;
        try {
          if (await this.recover(db, doc.ref, treatment)) summary.committed++;
        } catch (error) {
          summary.blocked!++;
          // No patient contents, IDs, hashes, credentials or raw external errors.
          console.warn('[ReconciliationWorker] Projection blocked: ' + (error instanceof Blocked ? error.message : 'DEPENDENCY_OR_PROOF_UNAVAILABLE') + '. No new Fabric submission is approved.');
        }
      }
      return summary;
    } finally {
      if (treatment) this.isReconcilingTreatment = false; else this.isReconcilingNotes = false;
    }
  }
  public reconcilePendingClinicalNotes(): Promise<Summary> { return this.reconcile(false); }
  public reconcilePendingTreatmentOperations(): Promise<Summary> { return this.reconcile(true); }
}
