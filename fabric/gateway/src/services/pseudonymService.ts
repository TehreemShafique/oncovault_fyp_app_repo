// src/services/pseudonymService.ts
import crypto from 'crypto';
import { config } from '../config/env';
import { DOMAIN_SEPARATION } from '../config/constants';

export class PseudonymService {
  private static secret: string = config.pseudonymHmacSecret;

  public static setSecret(secret: string): void {
    this.secret = secret;
  }

  /**
   * Generates a deterministic, domain-separated patient pseudonym.
   * e.g., pat_9a7d2e4... (alphanumeric and underscore, matching chaincode opaque ID regex)
   */
  public static generatePatientPseudoId(patientUid: string): string {
    if (!patientUid || typeof patientUid !== 'string' || patientUid.trim() === '') {
      throw new Error('Invalid patientUid for pseudonym generation');
    }
    const hmac = crypto.createHmac('sha256', this.secret);
    hmac.update(`domain:patient:${patientUid.trim()}`);
    const digest = hmac.digest('hex').substring(0, 32);
    return `${DOMAIN_SEPARATION.PATIENT_PREFIX}${digest}`;
  }

  /**
   * Generates a deterministic, domain-separated provider/doctor pseudonym.
   * e.g., prov_8b3c1a9...
   */
  public static generateProviderPseudoId(providerId: string): string {
    if (!providerId || typeof providerId !== 'string' || providerId.trim() === '') {
      throw new Error('Invalid providerId for pseudonym generation');
    }
    const hmac = crypto.createHmac('sha256', this.secret);
    hmac.update(`domain:provider:${providerId.trim()}`);
    const digest = hmac.digest('hex').substring(0, 32);
    return `${DOMAIN_SEPARATION.PROVIDER_PREFIX}${digest}`;
  }

  /**
   * Generates a deterministic, collision-resistant opaque ledger record key.
   * Avoids exposing patient IDs or raw database document IDs to the public chain.
   * e.g., rec_f14a89c...
   */
  public static generateOpaqueRecordKey(patientUid: string, recordId: string): string {
    if (!patientUid || !recordId) {
      throw new Error('patientUid and recordId are required to generate opaque record key');
    }
    const hmac = crypto.createHmac('sha256', this.secret);
    hmac.update(`domain:record:${patientUid.trim()}:${recordId.trim()}`);
    const digest = hmac.digest('hex').substring(0, 32);
    return `${DOMAIN_SEPARATION.RECORD_PREFIX}${digest}`;
  }
}
