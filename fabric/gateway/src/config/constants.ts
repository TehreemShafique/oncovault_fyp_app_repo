// src/config/constants.ts

export const ALLOWED_METADATA_KEYS = [
  'documentType',
  'recordType',
  'schemaVersion',
  'mimeType',
  'checksumAlg',
  'revision',
  'revisionReason',
  'synthetic'
] as const;

export const FORBIDDEN_PHI_TERMS = [
  'patient', 'name', 'diagnosis', 'cancer', 'mrn', 'ssn',
  'medical', 'dob', 'birth', 'chemo', 'biopsy', 'stage',
  'address', 'phone', 'email', 'hospital_id'
];

export const ALLOWED_CONSENT_SCOPES = [
  'RESEARCH_DATA_ACCESS',
  'CLINICAL_TRIAL_ACCESS',
  'ONCOLOGY_RESEARCH',
  'BLOOD_CANCER_RESEARCH',
  'DIRECT_CARE',
  'EMERGENCY_ACCESS'
] as const;

export const ERROR_CODES = {
  UNAUTHENTICATED: 'UNAUTHENTICATED',
  UNAUTHORIZED: 'UNAUTHORIZED',
  FORBIDDEN: 'FORBIDDEN',
  NOT_FOUND: 'NOT_FOUND',
  BAD_REQUEST: 'BAD_REQUEST',
  CONFLICT: 'CONFLICT',
  SERVICE_UNAVAILABLE: 'SERVICE_UNAVAILABLE',
  LEDGER_ERROR: 'LEDGER_ERROR',
  INTERNAL_ERROR: 'INTERNAL_ERROR',
  FEATURE_DISABLED: 'FEATURE_DISABLED'
} as const;

export const DOMAIN_SEPARATION = {
  PATIENT_PREFIX: 'pat_',
  PROVIDER_PREFIX: 'prov_',
  RECORD_PREFIX: 'rec_'
} as const;
