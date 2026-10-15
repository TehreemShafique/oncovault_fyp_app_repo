'use strict';

const { Contract } = require('fabric-contract-api');

const SHA256_REGEX = /^[a-fA-F0-9]{64}$/;
const OPAQUE_ID_REGEX = /^[A-Za-z0-9_\-\.]{3,128}$/;
const ALLOWED_MSPS = ['Org1MSP', 'Org2MSP'];

// Strict metadata allowlist - prevents PHI leakage by disallowing any unapproved attributes
const ALLOWED_METADATA_KEYS = [
    'documentType',
    'recordType',
    'schemaVersion',
    'mimeType',
    'checksumAlg',
    'revision',
    'revisionReason',
    'synthetic'
];

const FORBIDDEN_PHI_TERMS = [
    'patient', 'name', 'diagnosis', 'cancer', 'mrn', 'ssn',
    'medical', 'dob', 'birth', 'chemo', 'biopsy', 'stage',
    'address', 'phone', 'email', 'hospital_id'
];

// Specific authorized gateway identities permitted to mutate patient consent.
// Ordinary organization members (e.g. user1) are fail-closed and rejected.
const AUTHORIZED_GATEWAY_IDENTITIES = [
    'oncovault-gateway',
    'org1admin',
    'org2admin'
];

class OncoVaultContract extends Contract {
    constructor() {
        super('OncoVaultContract');
    }

    async initLedger(ctx) {
        console.info('OncoVaultContract initialized successfully');
        return JSON.stringify({ status: 'INITIALIZED', contract: 'OncoVaultContract', version: '1.1.0' });
    }

    // =========================================================================
    // RECORD INTEGRITY MANAGEMENT
    // =========================================================================

    /**
     * Anchor a SHA-256 digest of a medical record on the ledger.
     * Prevents duplicate anchoring, unauthorized overwrite, and stores no PHI.
     */
    async AnchorRecordHash(ctx, recordId, sha256Hash, metadataJson) {
        this._validateCallerMsp(ctx);
        const callerMsp = ctx.clientIdentity.getMSPID();
        const callerId = ctx.clientIdentity.getID();

        this._validateOpaqueId(recordId, 'recordId');
        this._validateSha256(sha256Hash);

        const normalizedHash = sha256Hash.toLowerCase();
        const parsedMetadata = this._validateAndSanitizeMetadata(metadataJson);

        const recordKey = `RECORD_${recordId}`;
        const existingBytes = await ctx.stub.getState(recordKey);

        let newVersion = 1;
        let previousHash = null;
        let previousTxId = null;
        let creatorMspId = callerMsp;

        if (existingBytes && existingBytes.length > 0) {
            const existing = JSON.parse(existingBytes.toString('utf8'));

            // Duplicate anchoring check
            if (existing.sha256Hash === normalizedHash) {
                throw new Error(`Duplicate anchoring rejected: Record '${recordId}' is already anchored with identical hash '${normalizedHash}' (Version ${existing.version}).`);
            }

            // Unauthorized update check - only originating MSP may update the proof
            if (existing.creatorMspId && existing.creatorMspId !== callerMsp) {
                throw new Error(`Unauthorized update rejected: Record '${recordId}' was anchored by '${existing.creatorMspId}' and cannot be revised by '${callerMsp}'.`);
            }

            newVersion = (existing.version || 1) + 1;
            previousHash = existing.sha256Hash;
            previousTxId = existing.txId;
            creatorMspId = existing.creatorMspId;
        }

        const txId = ctx.stub.getTxID();
        const timestampIso = this._extractTxTimestampIso(ctx);

        const recordProof = {
            recordId,
            sha256Hash: normalizedHash,
            version: newVersion,
            txId,
            timestamp: timestampIso,
            previousHash,
            previousTxId,
            creatorMspId,
            lastUpdatedBy: callerId,
            lastUpdatedMspId: callerMsp,
            metadata: parsedMetadata,
            status: 'ACTIVE'
        };

        await ctx.stub.putState(recordKey, Buffer.from(JSON.stringify(recordProof)));
        return JSON.stringify(recordProof);
    }

    /**
     * Verify whether a provided SHA-256 hash matches the authoritative ledger proof.
     */
    async VerifyRecordHash(ctx, recordId, sha256Hash) {
        this._validateOpaqueId(recordId, 'recordId');
        this._validateSha256(sha256Hash);

        const recordKey = `RECORD_${recordId}`;
        const recordBytes = await ctx.stub.getState(recordKey);

        if (!recordBytes || recordBytes.length === 0) {
            throw new Error(`Record '${recordId}' does not exist on ledger.`);
        }

        const record = JSON.parse(recordBytes.toString('utf8'));
        const normalizedProvided = sha256Hash.toLowerCase();
        const isMatch = (record.sha256Hash === normalizedProvided);

        const verificationResult = {
            verified: isMatch,
            status: isMatch ? 'VERIFIED' : 'TAMPERED_OR_MISMATCH',
            recordId: record.recordId,
            version: record.version,
            ledgerHash: record.sha256Hash,
            providedHash: normalizedProvided,
            txId: record.txId,
            timestamp: record.timestamp
        };

        return JSON.stringify(verificationResult);
    }

    /**
     * Retrieve the current committed record proof from the ledger.
     */
    async GetRecordProof(ctx, recordId) {
        this._validateOpaqueId(recordId, 'recordId');

        const recordKey = `RECORD_${recordId}`;
        const recordBytes = await ctx.stub.getState(recordKey);

        if (!recordBytes || recordBytes.length === 0) {
            throw new Error(`Record '${recordId}' does not exist on ledger.`);
        }

        return recordBytes.toString('utf8');
    }

    /**
     * Retrieve the complete append-only history of a record proof.
     */
    async GetRecordHistory(ctx, recordId) {
        this._validateOpaqueId(recordId, 'recordId');

        const recordKey = `RECORD_${recordId}`;
        const history = await this._readHistory(ctx, recordKey);

        if (!history || history.length === 0) {
            throw new Error(`No ledger history found for record '${recordId}'.`);
        }

        return JSON.stringify(history);
    }

    // =========================================================================
    // CONSENT MANAGEMENT
    // =========================================================================

    /**
     * Grant data access consent between pseudonymous patient and provider.
     * Enforces fail-closed gateway identity verification.
     */
    async GrantConsent(ctx, patientPseudoId, providerPseudoId, scope, expirationTimestamp) {
        const gatewayAuth = this._validateGatewayAuthorization(ctx);
        const callerMsp = ctx.clientIdentity.getMSPID();
        const callerId = ctx.clientIdentity.getID();

        this._validateOpaqueId(patientPseudoId, 'patientPseudoId');
        this._validateOpaqueId(providerPseudoId, 'providerPseudoId');
        this._validateConsentScope(scope);

        if (expirationTimestamp && expirationTimestamp !== 'NEVER') {
            const expDate = new Date(expirationTimestamp);
            if (isNaN(expDate.getTime())) {
                throw new Error(`Invalid expirationTimestamp: '${expirationTimestamp}' is not a valid ISO date or 'NEVER'.`);
            }
        }

        const consentKey = `CONSENT_${patientPseudoId}_${providerPseudoId}_${scope}`;
        const txId = ctx.stub.getTxID();
        const timestampIso = this._extractTxTimestampIso(ctx);

        const consentRecord = {
            patientPseudoId,
            providerPseudoId,
            scope,
            status: 'GRANTED',
            grantedAt: timestampIso,
            expirationTimestamp: (expirationTimestamp && expirationTimestamp !== 'NEVER') ? expirationTimestamp : null,
            txId,
            timestamp: timestampIso,
            submittingMspId: callerMsp,
            submittingIdentity: callerId,
            authBoundary: {
                gatewayVerified: true,
                gatewayEnrollmentId: gatewayAuth.enrollmentId,
                gatewayMspId: callerMsp,
                policy: 'GATEWAY_DELEGATED_PATIENT_AUTH',
                patientAuthEnforcement: 'PENDING_OFFCHAIN_GATEWAY_TOKEN_VERIFICATION',
                note: 'Consent mutation is strictly gated to authorized Fabric gateway identities. End-user patient identity, Firebase token validation, and consent ownership must be verified off-chain by the Gateway before invoking chaincode.'
            }
        };

        await ctx.stub.putState(consentKey, Buffer.from(JSON.stringify(consentRecord)));
        return JSON.stringify(consentRecord);
    }

    /**
     * Revoke existing consent for a given patient, provider, and scope.
     * Enforces fail-closed gateway identity verification.
     */
    async RevokeConsent(ctx, patientPseudoId, providerPseudoId, scope) {
        const gatewayAuth = this._validateGatewayAuthorization(ctx);
        const callerMsp = ctx.clientIdentity.getMSPID();
        const callerId = ctx.clientIdentity.getID();

        this._validateOpaqueId(patientPseudoId, 'patientPseudoId');
        this._validateOpaqueId(providerPseudoId, 'providerPseudoId');
        this._validateConsentScope(scope);

        const consentKey = `CONSENT_${patientPseudoId}_${providerPseudoId}_${scope}`;
        const consentBytes = await ctx.stub.getState(consentKey);

        if (!consentBytes || consentBytes.length === 0) {
            throw new Error(`Consent record not found for patient '${patientPseudoId}', provider '${providerPseudoId}', scope '${scope}'.`);
        }

        const existing = JSON.parse(consentBytes.toString('utf8'));
        if (existing.status === 'REVOKED') {
            throw new Error(`Consent for patient '${patientPseudoId}', provider '${providerPseudoId}', scope '${scope}' is already REVOKED.`);
        }

        const txId = ctx.stub.getTxID();
        const timestampIso = this._extractTxTimestampIso(ctx);

        existing.status = 'REVOKED';
        existing.revokedAt = timestampIso;
        existing.txId = txId;
        existing.timestamp = timestampIso;
        existing.revokedByMspId = callerMsp;
        existing.revokedByIdentity = callerId;
        existing.revocationAuthBoundary = {
            gatewayVerified: true,
            gatewayEnrollmentId: gatewayAuth.enrollmentId,
            gatewayMspId: callerMsp,
            policy: 'GATEWAY_DELEGATED_PATIENT_AUTH'
        };

        await ctx.stub.putState(consentKey, Buffer.from(JSON.stringify(existing)));
        return JSON.stringify(existing);
    }

    /**
     * Check active consent status on the ledger.
     */
    async CheckConsent(ctx, patientPseudoId, providerPseudoId, scope) {
        this._validateOpaqueId(patientPseudoId, 'patientPseudoId');
        this._validateOpaqueId(providerPseudoId, 'providerPseudoId');
        this._validateConsentScope(scope);

        const consentKey = `CONSENT_${patientPseudoId}_${providerPseudoId}_${scope}`;
        const consentBytes = await ctx.stub.getState(consentKey);

        if (!consentBytes || consentBytes.length === 0) {
            return JSON.stringify({
                active: false,
                status: 'NOT_FOUND',
                patientPseudoId,
                providerPseudoId,
                scope
            });
        }

        const record = JSON.parse(consentBytes.toString('utf8'));

        if (record.status !== 'GRANTED') {
            return JSON.stringify({
                active: false,
                status: record.status,
                patientPseudoId,
                providerPseudoId,
                scope,
                revokedAt: record.revokedAt || null
            });
        }

        if (record.expirationTimestamp) {
            const expTime = new Date(record.expirationTimestamp).getTime();
            const currentSeconds = this._extractTxSeconds(ctx);
            if (expTime <= currentSeconds * 1000) {
                return JSON.stringify({
                    active: false,
                    status: 'EXPIRED',
                    patientPseudoId,
                    providerPseudoId,
                    scope,
                    expirationTimestamp: record.expirationTimestamp
                });
            }
        }

        return JSON.stringify({
            active: true,
            status: 'GRANTED',
            patientPseudoId,
            providerPseudoId,
            scope,
            expirationTimestamp: record.expirationTimestamp || null,
            txId: record.txId,
            timestamp: record.timestamp
        });
    }

    /**
     * Retrieve complete auditable grant/revoke lifecycle history for consent.
     */
    async GetConsentHistory(ctx, patientPseudoId, providerPseudoId, scope) {
        this._validateOpaqueId(patientPseudoId, 'patientPseudoId');
        this._validateOpaqueId(providerPseudoId, 'providerPseudoId');
        this._validateConsentScope(scope);

        const consentKey = `CONSENT_${patientPseudoId}_${providerPseudoId}_${scope}`;
        const history = await this._readHistory(ctx, consentKey);

        if (!history || history.length === 0) {
            throw new Error(`No consent history found for patient '${patientPseudoId}', provider '${providerPseudoId}', scope '${scope}'.`);
        }

        return JSON.stringify(history);
    }

    // =========================================================================
    // INTERNAL HELPERS & VALIDATORS
    // =========================================================================

    _validateCallerMsp(ctx) {
        if (!ctx.clientIdentity || typeof ctx.clientIdentity.getMSPID !== 'function') {
            throw new Error('Access Denied: Missing or malformed client identity context.');
        }
        const mspId = ctx.clientIdentity.getMSPID();
        if (!ALLOWED_MSPS.includes(mspId)) {
            throw new Error(`Access Denied: Caller MSP '${mspId}' is not authorized.`);
        }
        return mspId;
    }

    _validateGatewayAuthorization(ctx) {
        this._validateCallerMsp(ctx);
        const callerMsp = ctx.clientIdentity.getMSPID();

        // Extract Fabric CA enrollment ID or X509 Subject CN
        let enrollmentId = null;
        if (typeof ctx.clientIdentity.getAttributeValue === 'function') {
            enrollmentId = ctx.clientIdentity.getAttributeValue('hf.EnrollmentID');
        }
        if (!enrollmentId && typeof ctx.clientIdentity.getX509Certificate === 'function') {
            const cert = ctx.clientIdentity.getX509Certificate();
            if (cert && cert.subject && cert.subject.commonName) {
                enrollmentId = cert.subject.commonName;
            }
        }

        if (!enrollmentId || !AUTHORIZED_GATEWAY_IDENTITIES.includes(enrollmentId)) {
            throw new Error(`Access Denied: Caller '${enrollmentId || 'UNKNOWN'}' from '${callerMsp}' is not an authorized OncoVault Gateway identity. Ordinary organization identities cannot mutate patient consent without verified gateway delegation.`);
        }

        return {
            authorized: true,
            enrollmentId,
            callerMsp
        };
    }

    _validateOpaqueId(id, fieldName) {
        if (!id || typeof id !== 'string') {
            throw new Error(`Invalid ${fieldName}: must be a non-empty string.`);
        }
        const trimmed = id.trim();
        if (!OPAQUE_ID_REGEX.test(trimmed)) {
            throw new Error(`Invalid ${fieldName}: '${trimmed}' does not meet format requirements (3-128 characters, alphanumeric and _-.).`);
        }
        const lower = trimmed.toLowerCase();
        for (const term of FORBIDDEN_PHI_TERMS) {
            if (lower.includes(term)) {
                throw new Error(`PHI violation rejected: ${fieldName} contains forbidden term '${term}'.`);
            }
        }
    }

    _validateSha256(hash) {
        if (!hash || typeof hash !== 'string') {
            throw new Error('Invalid sha256Hash: must be a non-empty string.');
        }
        const trimmed = hash.trim();
        if (!SHA256_REGEX.test(trimmed)) {
            throw new Error(`Invalid sha256Hash: '${trimmed}' must be a 64-character hexadecimal SHA-256 hash.`);
        }
    }

    _validateConsentScope(scope) {
        if (!scope || typeof scope !== 'string') {
            throw new Error('Invalid consent scope: must be a non-empty string.');
        }
        const trimmed = scope.trim();
        if (!/^[A-Z0-9_]{3,64}$/.test(trimmed)) {
            throw new Error(`Invalid consent scope: '${trimmed}' must be 3-64 uppercase alphanumeric and underscore characters.`);
        }
    }

    _validateAndSanitizeMetadata(metadataJson) {
        if (!metadataJson || metadataJson.trim() === '') {
            return {};
        }
        let parsed;
        try {
            parsed = typeof metadataJson === 'object' ? metadataJson : JSON.parse(metadataJson);
        } catch (err) {
            throw new Error(`Invalid metadataJson: must be valid JSON string (${err.message}).`);
        }
        if (typeof parsed !== 'object' || Array.isArray(parsed) || parsed === null) {
            throw new Error('Invalid metadataJson: must be a JSON object.');
        }

        // Strict Allowlist Enforcement
        const keys = Object.keys(parsed);
        const sanitized = {};

        for (const k of keys) {
            if (!ALLOWED_METADATA_KEYS.includes(k)) {
                throw new Error(`Rejected unapproved metadata key '${k}': Only allowlisted keys (${ALLOWED_METADATA_KEYS.join(', ')}) are permitted to prevent PHI leakage.`);
            }

            const val = parsed[k];
            const valType = typeof val;

            if (valType !== 'string' && valType !== 'number' && valType !== 'boolean') {
                throw new Error(`Invalid value for metadata key '${k}': Only primitive types (string, number, boolean) are permitted.`);
            }

            if (valType === 'string') {
                if (val.length > 128) {
                    throw new Error(`Value for metadata key '${k}' exceeds maximum allowed length of 128 characters.`);
                }
                const lowerVal = val.toLowerCase();
                for (const phi of FORBIDDEN_PHI_TERMS) {
                    if (lowerVal.includes(phi)) {
                        throw new Error(`PHI violation rejected: metadata value for '${k}' contains forbidden term '${phi}'.`);
                    }
                }
            }

            sanitized[k] = val;
        }

        return sanitized;
    }

    _extractTxSeconds(ctx) {
        const timestamp = ctx.stub.getTxTimestamp();
        if (timestamp && timestamp.seconds) {
            return typeof timestamp.seconds.low !== 'undefined'
                ? timestamp.seconds.low
                : Number(timestamp.seconds);
        }
        return Math.floor(Date.now() / 1000);
    }

    _extractTxTimestampIso(ctx) {
        const seconds = this._extractTxSeconds(ctx);
        return new Date(seconds * 1000).toISOString();
    }

    async _readHistory(ctx, key) {
        const iterator = await ctx.stub.getHistoryForKey(key);
        const history = [];
        try {
            while (true) {
                const res = await iterator.next();
                if (res.value && res.value.value) {
                    const txId = res.value.txId;
                    const isDelete = res.value.isDelete;
                    let parsedValue = null;
                    const rawStr = res.value.value.toString('utf8');
                    try {
                        parsedValue = JSON.parse(rawStr);
                    } catch (e) {
                        parsedValue = rawStr;
                    }
                    let seconds = 0;
                    if (res.value.timestamp && res.value.timestamp.seconds) {
                        seconds = typeof res.value.timestamp.seconds.low !== 'undefined'
                            ? res.value.timestamp.seconds.low
                            : Number(res.value.timestamp.seconds);
                    }
                    const timestampIso = new Date(seconds * 1000).toISOString();
                    history.push({
                        txId,
                        timestamp: timestampIso,
                        isDelete,
                        value: parsedValue
                    });
                }
                if (res.done) {
                    break;
                }
            }
        } finally {
            if (iterator && typeof iterator.close === 'function') {
                await iterator.close();
            }
        }
        return history;
    }
}

module.exports = OncoVaultContract;
