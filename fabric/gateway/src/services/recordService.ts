// src/services/recordService.ts
import crypto from 'crypto';
import { ALLOWED_METADATA_KEYS } from '../config/constants';
import { AuthenticatedUser, RecordProof, VerificationResult } from '../types';
import { FabricGatewayService } from './fabricGateway';
import { FirebaseAdminService } from './firebaseAdmin';
import { PseudonymService } from './pseudonymService';
import { ReconciliationService } from './reconciliationService';

export class RecordService {
  private _fabricGateway?: FabricGatewayService;
  private _firebaseAdmin?: FirebaseAdminService;
  private _reconciliation?: ReconciliationService;

  constructor(
    fabricGateway?: FabricGatewayService,
    firebaseAdmin?: FirebaseAdminService,
    reconciliation?: ReconciliationService
  ) {
    this._fabricGateway = fabricGateway;
    this._firebaseAdmin = firebaseAdmin;
    this._reconciliation = reconciliation;
  }

  private get fabricGateway(): FabricGatewayService {
    return this._fabricGateway || FabricGatewayService.getInstance();
  }

  private get firebaseAdmin(): FirebaseAdminService {
    return this._firebaseAdmin || FirebaseAdminService.getInstance();
  }

  private get reconciliation(): ReconciliationService {
    return this._reconciliation || ReconciliationService.getInstance();
  }

  /**
   * Computes SHA-256 digest from raw binary buffer.
   */
  public computeSha256(buffer: Buffer): string {
    return crypto.createHash('sha256').update(buffer).digest('hex').toLowerCase();
  }

  /**
   * Canonical serialization for metadata-only clinical records.
   */
  public computeCanonicalMetadataHash(record: Record<string, any>): string {
    const canonicalObject: Record<string, any> = {
      id: record.id,
      patientId: record.patientId,
      type: record.type,
      subtype: record.subtype || '',
      facility: record.facility || '',
      summary: record.summary || ''
    };
    const serialized = JSON.stringify(canonicalObject, Object.keys(canonicalObject).sort());
    return this.computeSha256(Buffer.from(serialized, 'utf8'));
  }

  /**
   * Canonical serialization for clinical notes, matching record_clinical_note.ts.
   */
  public computeCanonicalClinicalNoteHash(note: Record<string, any>): string {
    const canonicalObj = {
      amendmentOf: note.amendmentOf || '',
      amendmentReason: (note.amendmentReason || '').trim(),
      authorUid: note.authorUid || note.authorId || '',
      careInterventions: (note.careInterventions || '').trim(),
      clinicalSummary: (note.clinicalSummary || note.clinicalText || '').trim(),
      createdAtIso:
        note.createdAtIso ||
        (note.createdAt && typeof note.createdAt.toDate === 'function'
          ? note.createdAt.toDate().toISOString()
          : typeof note.createdAt === 'string'
          ? note.createdAt
          : ''),
      narrativeObservations: (note.narrativeObservations || '').trim(),
      noteId: note.noteId || note.id || '',
      noteType: note.noteType || '',
      nurseReviewedTranscript: (note.nurseReviewedTranscript || note.rawTranscript || '').trim(),
      patientId: note.patientId || '',
      supportedExtractedSymptoms: note.supportedExtractedSymptoms || {},
      treatmentResponseNarrative: (note.treatmentResponseNarrative || '').trim()
    };
    const serialized = JSON.stringify(canonicalObj, Object.keys(canonicalObj).sort());
    return this.computeSha256(Buffer.from(serialized, 'utf8'));
  }

  /**
   * Canonical serialization for treatment task completion, matching manage_treatment_plan.ts.
   */
  public computeCanonicalTaskHash(task: Record<string, any>): string {
    const completedAtIso =
      task.completedAtIso ||
      (task.completedAt && typeof task.completedAt.toDate === 'function'
        ? task.completedAt.toDate().toISOString()
        : task.completedAt instanceof Date
        ? task.completedAt.toISOString()
        : typeof task.completedAt === 'string'
        ? task.completedAt
        : '');

    const canonicalObject = {
      completedAtIso,
      executionRemarks: (task.executionRemarks || '').trim(),
      patientId: task.patientId || '',
      performerUid: task.completedByNurseId || task.performerUid || '',
      planId: task.planId || '',
      taskId: task.taskId || task.id || ''
    };
    const serialized = JSON.stringify(canonicalObject, Object.keys(canonicalObject).sort());
    return this.computeSha256(Buffer.from(serialized, 'utf8'));
  }

  /**
   * Canonical serialization for treatment progress updates, matching manage_treatment_plan.ts.
   */
  public computeCanonicalProgressHash(update: Record<string, any>): string {
    const timestampIso =
      update.timestampIso ||
      (update.timestamp && typeof update.timestamp.toDate === 'function'
        ? update.timestamp.toDate().toISOString()
        : update.timestamp instanceof Date
        ? update.timestamp.toISOString()
        : typeof update.timestamp === 'string'
        ? update.timestamp
        : '');

    const canonicalObject = {
      authorUid: update.authorUid || update.authorId || '',
      clinicalSummary: (update.clinicalSummary || '').trim(),
      factualObservations: (update.factualObservations || '').trim(),
      patientId: update.patientId || '',
      patientTolerance: update.patientTolerance || '',
      planId: update.planId || '',
      timestampIso,
      updateId: update.updateId || update.id || ''
    };
    const serialized = JSON.stringify(canonicalObject, Object.keys(canonicalObject).sort());
    return this.computeSha256(Buffer.from(serialized, 'utf8'));
  }

  /**
   * Anchors a medical record hash on the Hyperledger Fabric ledger.
   */
  public async anchorRecord(
    user: AuthenticatedUser,
    recordId: string,
    providedMetadata?: Record<string, any>,
    idempotencyKey?: string,
    patientId?: string
  ): Promise<{ proof: RecordProof; opaqueRecordKey: string; fileHash: string }> {
    const lockKey = `anchor:${recordId}`;
    if (!this.reconciliation.acquireLock(lockKey)) {
      throw new Error(`Conflict: An anchor operation is already in progress for record '${recordId}'.`);
    }

    try {
      // 1. Fetch authoritative Firestore medical record
      const record = await this.firebaseAdmin.getMedicalRecord(recordId, patientId);
      if (!record) {
        throw new Error(`Medical record '${recordId}' not found.`);
      }

      if (record.status === 'DRAFT') {
        throw new Error(`Cannot anchor clinical record '${recordId}' because it is in DRAFT status.`);
      }

      // 2. Authorize record access (strictly fail-closed)
      await this.assertRecordAccess(user, record.patientId);

      // 3. Obtain file bytes and calculate SHA-256 hash server-side
      let fileHash = '';
      if (record.isClinicalNote) {
        fileHash = this.computeCanonicalClinicalNoteHash(record);
      } else if (record.fileUrl && record.fileUrl.trim() !== '') {
        const fileBuffer = await this.firebaseAdmin.getFileBytes(record.fileUrl);
        fileHash = this.computeSha256(fileBuffer);
      } else {
        // Metadata-only record: use deterministic canonical hash
        fileHash = this.computeCanonicalMetadataHash(record);
      }

      // 4. Server-controlled operation identity derived from patientId, recordId, and content fileHash
      // Client-generated random idempotency keys cannot bypass server-controlled deduplication
      const serverOpId =
        'op_anchor_' +
        crypto.createHash('sha256').update(`${record.patientId}:${recordId}:${fileHash}`).digest('hex').substring(0, 24);

      // 5. Generate deterministic opaque ledger record key
      const opaqueRecordKey = PseudonymService.generateOpaqueRecordKey(record.patientId, recordId);

      // 6. Check durable operation state across process restarts
      const priorOp = await this.reconciliation.getOperationAsync(serverOpId);
      if (priorOp && priorOp.status === 'COMMITTED') {
        try {
          const existingProofStr = await this.fabricGateway.evaluateTransaction('GetRecordProof', opaqueRecordKey);
          const existingProof: RecordProof = JSON.parse(existingProofStr);
          if (existingProof.sha256Hash.toLowerCase() === fileHash.toLowerCase()) {
            await this.firebaseAdmin.updateRecordProof(recordId, {
              txId: existingProof.txId,
              fileHash,
              version: existingProof.version,
              timestamp: existingProof.timestamp,
              opaqueRecordKey
            }, record.patientId);
            return { proof: existingProof, opaqueRecordKey, fileHash };
          }
        } catch (_) {
          // Re-evaluate on ledger below
        }
      }

      await this.reconciliation.startOperation(serverOpId, 'ANCHOR_RECORD', recordId, idempotencyKey);

      // 7. Sanitize metadata against strict chaincode allowlist
      const sanitizedMeta: Record<string, any> = {
        documentType: record.isClinicalNote ? 'CLINICAL_NOTE' : (record.type || 'MEDICAL_RECORD').toUpperCase(),
        schemaVersion: '1.0'
      };
      if (providedMetadata && typeof providedMetadata === 'object') {
        for (const key of Object.keys(providedMetadata)) {
          if ((ALLOWED_METADATA_KEYS as readonly string[]).includes(key)) {
            sanitizedMeta[key] = providedMetadata[key];
          }
        }
      }

      // 8. Check existing ledger proof to ensure idempotent retry or legitimate revision
      try {
        const existingProofStr = await this.fabricGateway.evaluateTransaction('GetRecordProof', opaqueRecordKey);
        const existingProof: RecordProof = JSON.parse(existingProofStr);

        if (existingProof.sha256Hash.toLowerCase() === fileHash.toLowerCase()) {
          // Already anchored with identical hash — idempotent success
          await this.firebaseAdmin.updateRecordProof(recordId, {
            txId: existingProof.txId,
            fileHash,
            version: existingProof.version,
            timestamp: existingProof.timestamp,
            opaqueRecordKey
          }, record.patientId);
          await this.reconciliation.markCommitted(serverOpId, existingProof.txId, existingProof.timestamp);
          return { proof: existingProof, opaqueRecordKey, fileHash };
        } else {
          // Legitimate revision: mark revisionReason in metadata
          sanitizedMeta.revision = (existingProof.version || 1) + 1;
          sanitizedMeta.revisionReason = providedMetadata?.revisionReason || 'AMENDED_ASSAY';
        }
      } catch (err: any) {
        // Record not on ledger yet: fresh anchor
      }

      // 9. Submit transaction to real Fabric chaincode
      const { result, txId } = await this.fabricGateway.submitTransaction(
        'AnchorRecordHash',
        opaqueRecordKey,
        fileHash,
        JSON.stringify(sanitizedMeta)
      );

      const proof: RecordProof = JSON.parse(result);

      // 10. Update Firestore record with genuine proof metadata
      try {
        await this.firebaseAdmin.updateRecordProof(recordId, {
          txId: proof.txId || txId || '',
          fileHash,
          version: proof.version,
          timestamp: proof.timestamp,
          opaqueRecordKey
        }, record.patientId);
      } catch (dbErr: any) {
        // Fabric commit succeeded but Firestore write had an issue: mark UNCERTAIN_RETRYABLE
        await this.reconciliation.markStatus(
          serverOpId,
          'UNCERTAIN_RETRYABLE',
          `Ledger committed [tx: ${txId}], but Firestore sync failed: ${dbErr.message}`
        );
        throw new Error(`Ledger committed successfully, but local metadata synchronization failed: ${dbErr.message}`);
      }

      await this.reconciliation.markCommitted(serverOpId, proof.txId, proof.timestamp);
      return { proof, opaqueRecordKey, fileHash };
    } catch (err: any) {
      const fallbackOpId = `op_anchor_${recordId}`;
      await this.reconciliation.markStatus(fallbackOpId, 'FAILED', err.message);
      throw err;
    } finally {
      this.reconciliation.releaseLock(lockKey);
    }
  }

  /**
   * Verifies the authenticity and integrity of a medical record against the ledger.
   */
  public async verifyRecord(
    user: AuthenticatedUser,
    recordId: string,
    clientSpecifiedHash?: string,
    patientId?: string
  ): Promise<VerificationResult> {
    const record = await this.firebaseAdmin.getMedicalRecord(recordId, patientId);
    if (!record) {
      return {
        verified: false,
        status: 'NOT_ANCHORED',
        recordId,
        targetHash: clientSpecifiedHash || '',
        message: `Record '${recordId}' not found in database.`
      };
    }

    await this.assertRecordAccess(user, record.patientId);

    const opaqueRecordKey = PseudonymService.generateOpaqueRecordKey(record.patientId, recordId);
    let targetHash = clientSpecifiedHash || record.fileHash || '';

    // If no hash provided, compute from actual storage bytes or clinical note
    if (!targetHash) {
      if (record.isClinicalNote) {
        targetHash = this.computeCanonicalClinicalNoteHash(record);
      } else if (record.fileUrl) {
        try {
          const bytes = await this.firebaseAdmin.getFileBytes(record.fileUrl);
          targetHash = this.computeSha256(bytes);
        } catch {
          targetHash = '';
        }
      } else {
        targetHash = this.computeCanonicalMetadataHash(record);
      }
    }

    if (!targetHash) {
      return {
        verified: false,
        status: 'NOT_ANCHORED',
        recordId,
        targetHash: '',
        message: 'No file hash or storage file available to verify.'
      };
    }

    try {
      const verifyResStr = await this.fabricGateway.evaluateTransaction(
        'VerifyRecordHash',
        opaqueRecordKey,
        targetHash
      );
      const verifyRes = JSON.parse(verifyResStr);

      let ledgerProof: RecordProof | undefined;
      try {
        const proofStr = await this.fabricGateway.evaluateTransaction('GetRecordProof', opaqueRecordKey);
        ledgerProof = JSON.parse(proofStr);
      } catch {}

      if (verifyRes.verified) {
        return {
          verified: true,
          status: 'VERIFIED',
          recordId,
          targetHash,
          ledgerProof,
          message: 'Record integrity verified against immutable Hyperledger Fabric ledger.'
        };
      } else {
        return {
          verified: false,
          status: 'TAMPERED_OR_MISMATCH',
          recordId,
          targetHash,
          ledgerProof,
          message: 'Record hash does not match the ledger proof (potential tampering or mismatch).'
        };
      }
    } catch (err: any) {
      if (err.message && err.message.includes('not found')) {
        return {
          verified: false,
          status: 'NOT_ANCHORED',
          recordId,
          targetHash,
          message: 'Record has not been anchored on the blockchain ledger.'
        };
      }
      return {
        verified: false,
        status: 'VERIFICATION_UNAVAILABLE',
        recordId,
        targetHash,
        message: `Ledger verification unavailable: ${err.message}`
      };
    }
  }

  /**
   * Retrieves the current record proof from Fabric.
   */
  public async getRecordProof(user: AuthenticatedUser, recordId: string, patientId?: string): Promise<RecordProof> {
    const record = await this.firebaseAdmin.getMedicalRecord(recordId, patientId);
    if (!record) {
      throw new Error(`Record '${recordId}' not found.`);
    }

    await this.assertRecordAccess(user, record.patientId);
    const opaqueRecordKey = PseudonymService.generateOpaqueRecordKey(record.patientId, recordId);

    const proofStr = await this.fabricGateway.evaluateTransaction('GetRecordProof', opaqueRecordKey);
    return JSON.parse(proofStr);
  }

  /**
   * Retrieves the full revision history of a record proof from Fabric.
   */
  public async getRecordHistory(user: AuthenticatedUser, recordId: string, patientId?: string): Promise<any[]> {
    const record = await this.firebaseAdmin.getMedicalRecord(recordId, patientId);
    if (!record) {
      throw new Error(`Record '${recordId}' not found.`);
    }

    await this.assertRecordAccess(user, record.patientId);
    const opaqueRecordKey = PseudonymService.generateOpaqueRecordKey(record.patientId, recordId);

    const historyStr = await this.fabricGateway.evaluateTransaction('GetRecordHistory', opaqueRecordKey);
    return JSON.parse(historyStr);
  }

  /**
   * Enforces that the authenticated caller has legitimate clinical or patient access.
   */
  private async assertRecordAccess(user: AuthenticatedUser, patientId: string): Promise<void> {
    if (user.role === 'admin') {
      return;
    }
    if (user.role === 'patient') {
      if (user.uid !== patientId) {
        throw new Error('Access Denied: Patients may only access their own medical records.');
      }
      return;
    }
    if (user.role === 'nurse') {
      const isAssigned = await this.firebaseAdmin.checkActiveNurseAssignment(user.uid, patientId);
      if (!isAssigned) {
        throw new Error('Access Denied: Nurse does not hold active assignment for this patient.');
      }
      return;
    }
    if (user.role === 'doctor') {
      // 1. Evaluate Fabric ledger consent first (strictly fail-closed if revoked or inactive)
      try {
        const patientPseudoId = PseudonymService.generatePatientPseudoId(patientId);
        const providerPseudoId = PseudonymService.generateProviderPseudoId(user.uid);
        const consentResStr = await this.fabricGateway.evaluateTransaction(
          'CheckConsent',
          patientPseudoId,
          providerPseudoId,
          'BLOOD_CANCER_RESEARCH'
        );
        if (consentResStr) {
          const consentRes = JSON.parse(consentResStr);
          if (consentRes.active === true) {
            return;
          }
          if (consentRes.status === 'REVOKED' || consentRes.active === false) {
            throw new Error('Access Denied: Patient consent has been revoked or is inactive on Hyperledger Fabric ledger.');
          }
        }
      } catch (fabricErr: any) {
        if (fabricErr.message && fabricErr.message.includes('Access Denied')) {
          throw fabricErr;
        }
        // In local/mock testing where CheckConsent is not stubbed, proceed to checkDoctorPatientConsent
      }

      const hasConsent = await this.firebaseAdmin.checkDoctorPatientConsent(user.uid, patientId);
      if (!hasConsent) {
        throw new Error('Access Denied: Clinician does not hold active patient consent for this record.');
      }
      return;
    }
    throw new Error('Access Denied: Unauthorized role.');
  }
}
