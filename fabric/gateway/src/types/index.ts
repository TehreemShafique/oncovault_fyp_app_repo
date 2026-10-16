// src/types/index.ts

export type UserRole = 'patient' | 'doctor' | 'nurse' | 'admin';

export interface AuthenticatedUser {
  uid: string;
  email?: string;
  role: UserRole;
  medicalId?: string;
  name?: string;
}

export interface AuthenticatedRequest extends Express.Request {
  user?: AuthenticatedUser;
  idempotencyKey?: string;
}

export type RecordVerificationStatus =
  | 'VERIFIED'
  | 'TAMPERED_OR_MISMATCH'
  | 'NOT_ANCHORED'
  | 'PENDING'
  | 'VERIFICATION_UNAVAILABLE';

export interface RecordProof {
  recordId: string;
  sha256Hash: string;
  version: number;
  txId: string;
  timestamp: string;
  previousHash: string | null;
  previousTxId: string | null;
  creatorMspId: string;
  lastUpdatedBy: string;
  lastUpdatedMspId: string;
  metadata?: Record<string, any>;
  status: string;
}

export interface VerificationResult {
  verified: boolean;
  status: RecordVerificationStatus;
  recordId: string;
  targetHash: string;
  ledgerProof?: RecordProof;
  message: string;
}

export type ConsentStatus = 'GRANTED' | 'REVOKED' | 'EXPIRED' | 'NOT_FOUND';

export interface ConsentCheckResult {
  active: boolean;
  status: ConsentStatus;
  patientPseudoId: string;
  providerPseudoId: string;
  scope: string;
  expirationTimestamp?: string;
  revokedAt?: string | null;
  txId?: string;
  timestamp?: string;
}

export interface ConsentRecord {
  patientPseudoId: string;
  providerPseudoId: string;
  scope: string;
  status: ConsentStatus;
  grantedAt: string;
  expirationTimestamp: string;
  txId: string;
  timestamp: string;
  submittingMspId: string;
  submittingIdentity: string;
  authBoundary: {
    gatewayVerified: boolean;
    gatewayEnrollmentId: string;
    gatewayMspId: string;
    policy: string;
    patientAuthEnforcement: string;
    note: string;
  };
  revokedAt?: string;
  revokedByMspId?: string;
  revokedByIdentity?: string;
}

export type OperationStatus = 'PENDING' | 'COMMITTED' | 'FAILED' | 'UNCERTAIN_RETRYABLE';

export interface DurableOperation {
  operationId: string;
  idempotencyKey?: string;
  operationType: 'ANCHOR_RECORD' | 'GRANT_CONSENT' | 'REVOKE_CONSENT';
  entityId: string;
  status: OperationStatus;
  txId?: string;
  blockTimestamp?: string;
  error?: string;
  attempts: number;
  createdAt: string;
  updatedAt: string;
}

export interface ApiResponse<T = any> {
  success: boolean;
  data?: T;
  error?: {
    code: string;
    message: string;
    details?: any;
  };
}
