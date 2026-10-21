// src/services/consentService.ts
import { createHash } from 'crypto';
import { ALLOWED_CONSENT_SCOPES } from '../config/constants';
import { config } from '../config/env';
import { AuthenticatedUser, ConsentCheckResult, ConsentRecord, ConsentOperation } from '../types';
import { ConsentSubmissionError, FabricGatewayService } from './fabricGateway';
import { FirebaseAdminService } from './firebaseAdmin';
import { PseudonymService } from './pseudonymService';
import { ReconciliationService } from './reconciliationService';

export class ConsentService {
  private _fabricGateway?: FabricGatewayService;
  private _reconciliation?: ReconciliationService;
  private _firebaseAdmin?: any;

  constructor(
    fabricGateway?: FabricGatewayService,
    reconciliation?: ReconciliationService,
    firebaseAdmin?: any
  ) {
    this._fabricGateway = fabricGateway;
    this._reconciliation = reconciliation;
    this._firebaseAdmin = firebaseAdmin;
  }

  private get fabricGateway(): FabricGatewayService {
    return this._fabricGateway || FabricGatewayService.getInstance();
  }

  private get reconciliation(): ReconciliationService {
    return this._reconciliation || ReconciliationService.getInstance();
  }

  private get firebaseAdmin(): any {
    return this._firebaseAdmin || FirebaseAdminService.getInstance();
  }

  public async grantConsent(
    user: AuthenticatedUser, providerId: string, scope: string,
    expirationTimestamp = 'NEVER', idempotencyKey?: string
  ) {
    return this.mutateConsent(user, providerId, scope, 'GRANT_CONSENT', expirationTimestamp, idempotencyKey);
  }

  public async revokeConsent(user: AuthenticatedUser, providerId: string, scope: string, idempotencyKey?: string) {
    return this.mutateConsent(user, providerId, scope, 'REVOKE_CONSENT', 'NEVER', idempotencyKey);
  }

  private async authorizeConsentIdentity(user: AuthenticatedUser, providerId: string): Promise<void> {
    if (user.role !== 'patient') throw new Error('Access Denied: Only authenticated patients may change their consent.');
    if (!providerId || providerId.length < 3 || providerId !== providerId.trim() || providerId.includes('/') || providerId.length > 128) throw new Error('Invalid doctor identifier.');
    const db = this.firebaseAdmin.getFirestoreInstance();
    if (!db) throw new Error('Consent identity storage unavailable.');
    // Read raw authoritative records: getAuthoritativeUser defaults a missing role to patient.
    const [patient, doctor, provider] = await Promise.all([
      db.collection('users').doc(user.uid).get(),
      db.collection('doctors').doc(providerId).get(),
      db.collection('users').doc(providerId).get()
    ]);
    if (!patient.exists || String(patient.data()?.role || '').toLowerCase() !== 'patient' ||
        (patient.data()?.uid && patient.data().uid !== user.uid)) {
      throw new Error('Access Denied: An authoritative patient role is required.');
    }
    if (!doctor.exists || !provider.exists || String(provider.data()?.role || '').toLowerCase() !== 'doctor' ||
        (doctor.data()?.uid && doctor.data().uid !== providerId) ||
        (provider.data()?.uid && provider.data().uid !== providerId)) {
      throw new Error('Access Denied: The selected provider is not a verified registered doctor.');
    }
  }

  /** Recover an EXISTING operation only. This path never calls any Fabric submit method. */
  public async reconcileConsent(user: AuthenticatedUser, providerId: string, scope: string) {
    await this.authorizeConsentIdentity(user, providerId);
    const normalizedScope = scope.trim().toUpperCase();
    if (!(ALLOWED_CONSENT_SCOPES as readonly string[]).includes(normalizedScope)) throw new Error('Invalid consent scope.');
    const patientPseudoId = PseudonymService.generatePatientPseudoId(user.uid);
    const providerPseudoId = PseudonymService.generateProviderPseudoId(providerId);
    const guardId = `consent_scope_${this.hash(JSON.stringify([patientPseudoId, providerPseudoId, normalizedScope]))}`;
    let current = await this.reconciliation.getPendingConsentOperation(guardId);
    if (!current) return { operationStatus: 'NONE' };
    if (current.patientId !== user.uid || current.providerId !== providerId || current.scope !== normalizedScope) {
      throw new Error('Access Denied: Consent operation identity mismatch.');
    }
    // Even a saved COMMITTED operation is independently checked before recovery/projection.
    current = await this.recoverConsentOperation(user, current, patientPseudoId, providerPseudoId);
    return this.finishConsentOperation(current, patientPseudoId, providerPseudoId);
  }

  private async recoverConsentOperation(user: AuthenticatedUser, current: ConsentOperation, patient: string, provider: string) {
    if (current.status === 'FAILED') throw new Error('CONSENT_REJECTED: The previous request was not committed.');
    if (current.txId) {
      let history: any[];
      try { history = await this.getConsentHistory(user, user.uid, current.providerId, current.scope); }
      catch (_) { throw new Error('CONSENT_PENDING: The previous transaction could not be verified. Retry the same request later.'); }
      const entry = history.find(item => item.txId === current.txId && item.isDelete !== true);
      if (entry) {
        const consent = this.validateReceipt(entry.value, current.txId, current, patient, provider);
        return this.reconciliation.updateConsentOperation(current, {
          status: 'COMMITTED', consent, txId: consent.txId, blockTimestamp: consent.timestamp, projectionPending: true
        });
      }
    }
    // Empty history cannot prove non-commit or authorize a new submission.
    throw new Error('CONSENT_PENDING: The previous request is not yet confirmed. Do not create another grant or revocation.');
  }

  private async finishConsentOperation(current: ConsentOperation, patientPseudoId: string, providerPseudoId: string) {
    if (current.projectionPending) {
      try { current = await this.reconciliation.projectConsentOperation(current); }
      catch (_) { /* Verified commit remains successful; retry projection only. */ }
    }
    return {
      consent: current.consent!, patientPseudoId, providerPseudoId,
      operationId: current.operationId, operationStatus: 'COMMITTED',
      projectionStatus: current.projectionPending ? 'PENDING' : 'SYNCED'
    };
  }

  private hash(value: string): string { return createHash('sha256').update(value).digest('hex'); }

  private async mutateConsent(
    user: AuthenticatedUser, providerId: string, scope: string,
    operationType: 'GRANT_CONSENT' | 'REVOKE_CONSENT', expiration: string, key?: string
  ) {
    if (!config.enableLiveConsentMutations) {
      throw new Error('FEATURE_DISABLED: Live consent mutations are disabled (ENABLE_LIVE_CONSENT_MUTATIONS=false).');
    }
    if (user.role !== 'patient') {
      throw new Error('Access Denied: Only authenticated patients may grant or revoke consent.');
    }
    if (!key || !/^[A-Za-z0-9_-]{16,128}$/.test(key)) {
      throw new Error('Invalid consent idempotency key; a stable request identifier is required.');
    }
    if (!providerId || providerId.length < 3 || providerId !== providerId.trim() || providerId.includes('/') || providerId.length > 128) {
      throw new Error('Invalid doctor identifier.');
    }
    const normalizedScope = scope.trim().toUpperCase();
    if (!(ALLOWED_CONSENT_SCOPES as readonly string[]).includes(normalizedScope)) {
      throw new Error('Invalid consent scope.');
    }
    await this.authorizeConsentIdentity(user, providerId);
    // Normalize only valid ISO date-time input. Future validation happens AFTER replay lookup.
    if (expiration !== 'NEVER') {
      const parts = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,3})?(?:Z|[+-]\d{2}:\d{2})$/.exec(expiration);
      if (!parts || !Number.isFinite(Date.parse(expiration))) throw new Error('Invalid consent expiration date.');
      const [, y, m, d, h, minute, second] = parts;
      const calendar = new Date(Date.UTC(+y, +m - 1, +d));
      if (calendar.getUTCFullYear() !== +y || calendar.getUTCMonth() !== +m - 1 || calendar.getUTCDate() !== +d ||
          +h > 23 || +minute > 59 || +second > 59) throw new Error('Invalid consent expiration date.');
      expiration = new Date(expiration).toISOString();
    }
    const patientPseudoId = PseudonymService.generatePatientPseudoId(user.uid);
    const providerPseudoId = PseudonymService.generateProviderPseudoId(providerId);
    const now = new Date().toISOString();
    const operation: ConsentOperation = {
      operationId: `consent_${this.hash(JSON.stringify([user.uid, key]))}`,
      fingerprint: this.hash(JSON.stringify([user.uid, providerId, normalizedScope, operationType, expiration])),
      guardId: `consent_scope_${this.hash(JSON.stringify([patientPseudoId, providerPseudoId, normalizedScope]))}`,
      operationType, patientId: user.uid, providerId, scope: normalizedScope,
      expirationTimestamp: expiration, entityId: `${patientPseudoId}_${providerPseudoId}_${normalizedScope}`,
      status: 'PENDING', attempts: 1, projectionPending: false, createdAt: now, updatedAt: now
    };
    const claim = await this.reconciliation.claimConsentOperation(operation);
    let current = claim.operation;
    if (!claim.claimed) {
      if (current.status === 'FAILED') throw new Error('CONSENT_REJECTED: The previous request was not committed.');
      if (current.status !== 'COMMITTED') {
        current = await this.recoverConsentOperation(user, current, patientPseudoId, providerPseudoId);
      }
    } else {
      // Validate future expiry only for a NEW logical request, not a replay of a prior receipt.
      if (expiration !== 'NEVER' && Date.parse(expiration) <= Date.now()) {
        await this.reconciliation.updateConsentOperation(current, { status: 'FAILED' }, true);
        throw new Error('Invalid consent expiration: it must be a future date.');
      }
      try {
        // A fresh key is not permission to repeat a grant already active on the ledger.
        try {
          const state = await this.checkConsent(user, user.uid, providerId, normalizedScope);
          const validGrant = operationType === 'GRANT_CONSENT' && state.active === false &&
            ['NOT_FOUND', 'REVOKED', 'EXPIRED'].includes(state.status);
          const validRevoke = operationType === 'REVOKE_CONSENT' && state.active === true && state.status === 'GRANTED';
          if (!validGrant && !validRevoke) throw new Error('Consent state does not permit this operation.');
        } catch (_) { throw new ConsentSubmissionError('NOT_SUBMITTED'); }
        const args = [patientPseudoId, providerPseudoId, normalizedScope];
        if (operationType === 'GRANT_CONSENT') args.push(expiration);
        const result = await this.fabricGateway.submitConsentTransaction(
          operationType === 'GRANT_CONSENT' ? 'GrantConsent' : 'RevokeConsent', args,
          async txId => {
            current = await this.reconciliation.updateConsentOperation(current, { txId });
          }
        );
        const consent = this.validateReceipt(JSON.parse(result.result), result.txId, current, patientPseudoId, providerPseudoId);
        current = await this.reconciliation.updateConsentOperation(current, {
          status: 'COMMITTED', consent, txId: consent.txId, blockTimestamp: consent.timestamp, projectionPending: true
        });
      } catch (err) {
        const definite = err instanceof ConsentSubmissionError && err.outcome !== 'UNCERTAIN';
        try {
          await this.reconciliation.updateConsentOperation(current, {
            status: definite ? 'FAILED' : 'UNCERTAIN_RETRYABLE'
          }, definite);
        } catch (_) { /* Durable PENDING claim remains blocking even when persistence is unavailable. */ }
        throw new Error(definite
          ? 'CONSENT_REJECTED: The request was not committed. No automatic retry was submitted.'
          : 'CONSENT_PENDING: The transaction outcome is not confirmed. Do not submit a new request.');
      }
    }
    return this.finishConsentOperation(current, patientPseudoId, providerPseudoId);
  }

  private validateReceipt(value: any, txId: string, operation: ConsentOperation, patient: string, provider: string): ConsentRecord {
    const expected = operation.operationType === 'GRANT_CONSENT' ? 'GRANTED' : 'REVOKED';
    if (!txId || operation.txId !== txId || value?.txId !== txId || value?.patientPseudoId !== patient || value?.providerPseudoId !== provider ||
        value?.scope !== operation.scope || value?.status !== expected || !value?.timestamp ||
        !Number.isFinite(Date.parse(value.timestamp)) ||
        (expected === 'GRANTED' && (value.expirationTimestamp ?? 'NEVER') !== operation.expirationTimestamp)) {
      throw new Error('Invalid Fabric consent receipt.');
    }
    return value as ConsentRecord;
  }

  /**
   * Evaluates active consent status on the ledger.
   */
  public async checkConsent(
    user: AuthenticatedUser,
    targetPatientId: string,
    providerId: string,
    scope: string
  ): Promise<ConsentCheckResult> {
    // Patients can check their own; providers can check if they hold consent for a patient
    if (user.role === 'patient' && user.uid !== targetPatientId) {
      throw new Error('Access Denied: Patients may only check their own consent records.');
    }
    if ((user.role === 'doctor' || user.role === 'nurse') && user.uid !== providerId) {
      throw new Error('Access Denied: Clinicians may only query consent where they are the recipient provider.');
    }

    const patientPseudoId = PseudonymService.generatePatientPseudoId(targetPatientId);
    const providerPseudoId = PseudonymService.generateProviderPseudoId(providerId);
    const normalizedScope = scope.trim().toUpperCase();

    const resultStr = await this.fabricGateway.evaluateTransaction(
      'CheckConsent',
      patientPseudoId,
      providerPseudoId,
      normalizedScope
    );

    return JSON.parse(resultStr);
  }

  /**
   * Evaluates full consent grant and revoke audit trail on the ledger.
   */
  public async getConsentHistory(
    user: AuthenticatedUser,
    targetPatientId: string,
    providerId: string,
    scope: string
  ): Promise<any[]> {
    if (user.role === 'patient' && user.uid !== targetPatientId) {
      throw new Error('Access Denied: Patients may only view their own consent audit history.');
    }

    const patientPseudoId = PseudonymService.generatePatientPseudoId(targetPatientId);
    const providerPseudoId = PseudonymService.generateProviderPseudoId(providerId);
    const normalizedScope = scope.trim().toUpperCase();

    let resultStr: string;
    try {
      resultStr = await this.fabricGateway.evaluateTransaction(
        'GetConsentHistory', patientPseudoId, providerPseudoId, normalizedScope
      );
    } catch (err: any) {
      // The deployed contract throws after a successful, empty history scan.
      // Normalize only that exact peer response for this key/scope. Transport,
      // permission, disabled-history and mixed-peer errors must still fail.
      const emptyMessage = `No consent history found for patient '${patientPseudoId}', provider '${providerPseudoId}', scope '${normalizedScope}'.`;
      const details = err?.details;
      if (err?.code === 2 && Array.isArray(details) && details.length > 0 &&
          details.every((detail: any) => detail?.message === emptyMessage ||
            detail?.message === `chaincode response 500, ${emptyMessage}`)) {
        return [];
      }
      throw err;
    }

    const history: unknown = JSON.parse(resultStr);
    if (!Array.isArray(history)) {
      throw new Error('Invalid consent history response from Fabric.');
    }
    return history;
  }
}
