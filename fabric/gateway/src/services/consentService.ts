// src/services/consentService.ts
import { ALLOWED_CONSENT_SCOPES } from '../config/constants';
import { config } from '../config/env';
import { AuthenticatedUser, ConsentCheckResult, ConsentRecord } from '../types';
import { FabricGatewayService } from './fabricGateway';
import { FirebaseAdminService } from './firebaseAdmin';
import { PseudonymService } from './pseudonymService';
import { ReconciliationService } from './reconciliationService';

export class ConsentService {
  private _fabricGateway?: FabricGatewayService;
  private _reconciliation?: ReconciliationService;

  constructor(
    fabricGateway?: FabricGatewayService,
    reconciliation?: ReconciliationService
  ) {
    this._fabricGateway = fabricGateway;
    this._reconciliation = reconciliation;
  }

  private get fabricGateway(): FabricGatewayService {
    return this._fabricGateway || FabricGatewayService.getInstance();
  }

  private get reconciliation(): ReconciliationService {
    return this._reconciliation || ReconciliationService.getInstance();
  }

  /**
   * Grants patient consent to a provider on the Fabric ledger.
   * Only the authenticated patient may grant consent for themselves.
   */
  public async grantConsent(
    user: AuthenticatedUser,
    providerId: string,
    scope: string,
    expirationTimestamp: string = 'NEVER',
    idempotencyKey?: string
  ): Promise<{ consent: ConsentRecord; patientPseudoId: string; providerPseudoId: string }> {
    // 1. Safety Gate Check: Keep live consent mutations disabled by default until Phase 3
    if (!config.enableLiveConsentMutations) {
      throw new Error(
        'FEATURE_DISABLED: Live on-chain consent mutations are disabled by default (ENABLE_LIVE_CONSENT_MUTATIONS=false) until Firestore direct mutation bypass paths are decommissioned in Phase 3.'
      );
    }

    // 2. Strict Patient Authorization: only the patient themselves may grant consent
    if (user.role !== 'patient') {
      throw new Error('Access Denied: Only authenticated patients may grant clinical or research consent.');
    }

    // 3. Scope validation
    const normalizedScope = scope.trim().toUpperCase();
    if (!(ALLOWED_CONSENT_SCOPES as readonly string[]).includes(normalizedScope)) {
      throw new Error(`Invalid consent scope '${scope}'. Permitted scopes: ${ALLOWED_CONSENT_SCOPES.join(', ')}`);
    }

    // 4. Generate domain-separated pseudonyms (Anti-PHI)
    const patientPseudoId = PseudonymService.generatePatientPseudoId(user.uid);
    const providerPseudoId = PseudonymService.generateProviderPseudoId(providerId);

    const lockKey = `consent:${patientPseudoId}:${providerPseudoId}:${normalizedScope}`;
    if (!this.reconciliation.acquireLock(lockKey)) {
      throw new Error('Conflict: A consent operation for this patient and provider is already in progress.');
    }

    const operationId = `op_grant_${Date.now()}`;
    await this.reconciliation.startOperation(operationId, 'GRANT_CONSENT', `${patientPseudoId}_${providerPseudoId}`, idempotencyKey);

    try {
      // 5. Submit transaction to real Fabric chaincode
      const { result, txId } = await this.fabricGateway.submitTransaction(
        'GrantConsent',
        patientPseudoId,
        providerPseudoId,
        normalizedScope,
        expirationTimestamp
      );

      const consent: ConsentRecord = JSON.parse(result);
      await this.reconciliation.markCommitted(operationId, consent.txId || txId || '', consent.timestamp);

      // 6. Synchronize Firestore projection via Admin SDK
      try {
        const firestore = FirebaseAdminService.getInstance().getFirestoreInstance();
        if (firestore) {
          const docId = `${user.uid}_${providerId}`;
          await firestore.collection('doctor_patient_consents').doc(docId).set({
            id: docId,
            patientId: user.uid,
            doctorId: providerId,
            scope: normalizedScope,
            status: 'granted',
            fabricTxId: consent.txId || txId || '',
            fabricStatus: 'COMMITTED',
            blockchainVerified: true
          }, { merge: true });
        }
      } catch (syncErr: any) {
        await this.reconciliation.markStatus(
          operationId,
          'UNCERTAIN_RETRYABLE',
          `Fabric committed (${txId}) but Firestore projection sync failed: ${syncErr.message}`
        );
      }

      return { consent, patientPseudoId, providerPseudoId };
    } catch (err: any) {
      await this.reconciliation.markStatus(operationId, 'FAILED', err.message);
      throw err;
    } finally {
      this.reconciliation.releaseLock(lockKey);
    }
  }

  /**
   * Revokes previously granted patient consent on the Fabric ledger.
   * Only the authenticated patient may revoke their own consent.
   */
  public async revokeConsent(
    user: AuthenticatedUser,
    providerId: string,
    scope: string,
    idempotencyKey?: string
  ): Promise<{ consent: ConsentRecord; patientPseudoId: string; providerPseudoId: string }> {
    // 1. Safety Gate Check
    if (!config.enableLiveConsentMutations) {
      throw new Error(
        'FEATURE_DISABLED: Live on-chain consent mutations are disabled by default (ENABLE_LIVE_CONSENT_MUTATIONS=false) until Firestore direct mutation bypass paths are decommissioned in Phase 3.'
      );
    }

    // 2. Strict Patient Authorization
    if (user.role !== 'patient') {
      throw new Error('Access Denied: Only authenticated patients may revoke their clinical consent.');
    }

    const normalizedScope = scope.trim().toUpperCase();
    const patientPseudoId = PseudonymService.generatePatientPseudoId(user.uid);
    const providerPseudoId = PseudonymService.generateProviderPseudoId(providerId);

    const lockKey = `consent:${patientPseudoId}:${providerPseudoId}:${normalizedScope}`;
    if (!this.reconciliation.acquireLock(lockKey)) {
      throw new Error('Conflict: A consent operation for this patient and provider is already in progress.');
    }

    const operationId = `op_revoke_${Date.now()}`;
    await this.reconciliation.startOperation(operationId, 'REVOKE_CONSENT', `${patientPseudoId}_${providerPseudoId}`, idempotencyKey);

    try {
      const { result, txId } = await this.fabricGateway.submitTransaction(
        'RevokeConsent',
        patientPseudoId,
        providerPseudoId,
        normalizedScope
      );

      const consent: ConsentRecord = JSON.parse(result);
      await this.reconciliation.markCommitted(operationId, consent.txId || txId || '', consent.timestamp);

      // 3. Synchronize Firestore projection via Admin SDK
      try {
        const firestore = FirebaseAdminService.getInstance().getFirestoreInstance();
        if (firestore) {
          const docId = `${user.uid}_${providerId}`;
          await firestore.collection('doctor_patient_consents').doc(docId).set({
            status: 'revoked',
            fabricTxId: consent.txId || txId || '',
            fabricStatus: 'COMMITTED',
            blockchainVerified: true
          }, { merge: true });
        }
      } catch (syncErr: any) {
        await this.reconciliation.markStatus(
          operationId,
          'UNCERTAIN_RETRYABLE',
          `Fabric committed (${txId}) but Firestore projection sync failed: ${syncErr.message}`
        );
      }

      return { consent, patientPseudoId, providerPseudoId };
    } catch (err: any) {
      await this.reconciliation.markStatus(operationId, 'FAILED', err.message);
      throw err;
    } finally {
      this.reconciliation.releaseLock(lockKey);
    }
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

    const resultStr = await this.fabricGateway.evaluateTransaction(
      'GetConsentHistory',
      patientPseudoId,
      providerPseudoId,
      normalizedScope
    );

    return JSON.parse(resultStr);
  }
}
