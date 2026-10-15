'use strict';

const chai = require('chai');
const sinon = require('sinon');
const sinonChai = require('sinon-chai');
const expect = chai.expect;
chai.use(sinonChai);

const OncoVaultContract = require('../lib/oncovault-contract');

describe('OncoVaultContract Unit Tests (Hardened Security Gate)', () => {
    let contract;
    let ctx;
    let mockStub;
    let mockClientIdentity;
    let stateStore;
    let historyStore;

    const VALID_RECORD_ID_1 = 'rec-synth-001';
    const VALID_HASH_V1 = 'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';
    const VALID_HASH_V2 = 'b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90a1';
    const TAMPERED_HASH = 'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';
    const INVALID_SHORT_HASH = 'a1b2c3d4e5f6';

    const VALID_PATIENT_PSEUDO = 'pat-pseudo-98124';
    const VALID_PROVIDER_PSEUDO = 'prov-onc-77312';
    const VALID_SCOPE = 'RESEARCH_DATA_ACCESS';

    beforeEach(() => {
        contract = new OncoVaultContract();
        stateStore = {};
        historyStore = {};

        mockStub = {
            getState: sinon.stub().callsFake(async (key) => {
                const val = stateStore[key];
                return val ? Buffer.from(val) : Buffer.from('');
            }),
            putState: sinon.stub().callsFake(async (key, value) => {
                const valStr = value.toString('utf8');
                stateStore[key] = valStr;
                if (!historyStore[key]) {
                    historyStore[key] = [];
                }
                historyStore[key].push({
                    txId: mockStub.getTxID(),
                    timestamp: { seconds: { low: 1776300000 }, nanos: 0 },
                    isDelete: false,
                    value: Buffer.from(valStr)
                });
            }),
            getTxID: sinon.stub().returns('tx-synth-test-99999'),
            getTxTimestamp: sinon.stub().returns({ seconds: { low: 1776300000 }, nanos: 0 }),
            getHistoryForKey: sinon.stub().callsFake(async (key) => {
                const entries = (historyStore[key] || []).slice();
                let idx = 0;
                return {
                    next: async () => {
                        if (idx < entries.length) {
                            const entry = entries[idx++];
                            return { value: entry, done: false };
                        }
                        return { value: null, done: true };
                    },
                    close: async () => {}
                };
            })
        };

        mockClientIdentity = {
            getMSPID: sinon.stub().returns('Org1MSP'),
            getID: sinon.stub().returns('x509::/C=US/ST=North Carolina/O=Hyperledger/OU=admin/CN=org1admin::/C=US/ST=North Carolina/L=Durham/O=org1.example.com/CN=ca.org1.example.com'),
            getAttributeValue: sinon.stub().callsFake((attr) => {
                if (attr === 'hf.EnrollmentID') return 'org1admin';
                if (attr === 'hf.Type') return 'admin';
                return null;
            }),
            getX509Certificate: sinon.stub().returns({
                subject: {
                    commonName: 'org1admin',
                    organizationalUnitName: 'admin'
                }
            })
        };

        ctx = {
            stub: mockStub,
            clientIdentity: mockClientIdentity
        };
    });

    describe('Record Integrity Management', () => {
        it('should successfully anchor a valid SHA-256 integrity proof with allowlisted metadata', async () => {
            const metadata = JSON.stringify({
                documentType: 'PATHOLOGY_PANEL',
                schemaVersion: '1.0',
                synthetic: true
            });
            const resultStr = await contract.AnchorRecordHash(ctx, VALID_RECORD_ID_1, VALID_HASH_V1, metadata);
            const proof = JSON.parse(resultStr);

            expect(proof.recordId).to.equal(VALID_RECORD_ID_1);
            expect(proof.sha256Hash).to.equal(VALID_HASH_V1);
            expect(proof.version).to.equal(1);
            expect(proof.txId).to.equal('tx-synth-test-99999');
            expect(proof.creatorMspId).to.equal('Org1MSP');
            expect(proof.status).to.equal('ACTIVE');
            expect(proof.metadata.documentType).to.equal('PATHOLOGY_PANEL');
            expect(proof.metadata.schemaVersion).to.equal('1.0');
            expect(mockStub.putState).to.have.been.calledOnce;
        });

        it('should strictly reject non-allowlisted metadata keys to prevent PHI leakage', async () => {
            const metadata = JSON.stringify({
                documentType: 'PATHOLOGY_PANEL',
                unapprovedCustomKey: 'some_arbitrary_value'
            });
            try {
                await contract.AnchorRecordHash(ctx, VALID_RECORD_ID_1, VALID_HASH_V1, metadata);
                expect.fail('Should have rejected non-allowlisted metadata key');
            } catch (err) {
                expect(err.message).to.include('Rejected unapproved metadata key \'unapprovedCustomKey\'');
                expect(err.message).to.include('allowlisted keys');
            }
        });

        it('should reject non-primitive metadata values', async () => {
            const metadata = JSON.stringify({
                documentType: { nested: 'object_not_permitted' }
            });
            try {
                await contract.AnchorRecordHash(ctx, VALID_RECORD_ID_1, VALID_HASH_V1, metadata);
                expect.fail('Should have rejected non-primitive value');
            } catch (err) {
                expect(err.message).to.include('Only primitive types');
            }
        });

        it('should reject invalid SHA-256 hash formatting', async () => {
            try {
                await contract.AnchorRecordHash(ctx, VALID_RECORD_ID_1, INVALID_SHORT_HASH, '{}');
                expect.fail('Should have thrown an error for invalid hash');
            } catch (err) {
                expect(err.message).to.include('must be a 64-character hexadecimal SHA-256 hash');
            }
        });

        it('should reject duplicate anchoring of an existing identical hash', async () => {
            await contract.AnchorRecordHash(ctx, VALID_RECORD_ID_1, VALID_HASH_V1, '{}');

            try {
                await contract.AnchorRecordHash(ctx, VALID_RECORD_ID_1, VALID_HASH_V1, '{}');
                expect.fail('Should have thrown duplicate anchoring error');
            } catch (err) {
                expect(err.message).to.include('Duplicate anchoring rejected');
                expect(err.message).to.include('Version 1');
            }
        });

        it('should allow legitimate record revisions by originating MSP and advance version', async () => {
            await contract.AnchorRecordHash(ctx, VALID_RECORD_ID_1, VALID_HASH_V1, '{}');

            mockStub.getTxID.returns('tx-synth-revision-10001');
            mockStub.getTxTimestamp.returns({ seconds: { low: 1776300100 }, nanos: 0 });

            const revStr = await contract.AnchorRecordHash(ctx, VALID_RECORD_ID_1, VALID_HASH_V2, '{"revisionReason": "AMENDED_ASSAY"}');
            const revision = JSON.parse(revStr);

            expect(revision.recordId).to.equal(VALID_RECORD_ID_1);
            expect(revision.sha256Hash).to.equal(VALID_HASH_V2);
            expect(revision.version).to.equal(2);
            expect(revision.previousHash).to.equal(VALID_HASH_V1);
            expect(revision.previousTxId).to.equal('tx-synth-test-99999');
            expect(revision.txId).to.equal('tx-synth-revision-10001');
        });

        it('should reject unauthorized update of record from a different MSP', async () => {
            await contract.AnchorRecordHash(ctx, VALID_RECORD_ID_1, VALID_HASH_V1, '{}');

            // Caller switches to Org2MSP
            mockClientIdentity.getMSPID.returns('Org2MSP');

            try {
                await contract.AnchorRecordHash(ctx, VALID_RECORD_ID_1, VALID_HASH_V2, '{}');
                expect.fail('Should have rejected update from different MSP');
            } catch (err) {
                expect(err.message).to.include('Unauthorized update rejected');
                expect(err.message).to.include('cannot be revised by \'Org2MSP\'');
            }
        });

        it('should verify matching record hash as authoritative', async () => {
            await contract.AnchorRecordHash(ctx, VALID_RECORD_ID_1, VALID_HASH_V1, '{}');

            const verifyStr = await contract.VerifyRecordHash(ctx, VALID_RECORD_ID_1, VALID_HASH_V1);
            const res = JSON.parse(verifyStr);

            expect(res.verified).to.be.true;
            expect(res.status).to.equal('VERIFIED');
            expect(res.recordId).to.equal(VALID_RECORD_ID_1);
            expect(res.ledgerHash).to.equal(VALID_HASH_V1);
        });

        it('should detect tampered or mismatched hash verification', async () => {
            await contract.AnchorRecordHash(ctx, VALID_RECORD_ID_1, VALID_HASH_V1, '{}');

            const verifyStr = await contract.VerifyRecordHash(ctx, VALID_RECORD_ID_1, TAMPERED_HASH);
            const res = JSON.parse(verifyStr);

            expect(res.verified).to.be.false;
            expect(res.status).to.equal('TAMPERED_OR_MISMATCH');
            expect(res.providedHash).to.equal(TAMPERED_HASH);
            expect(res.ledgerHash).to.equal(VALID_HASH_V1);
        });

        it('should retrieve historical versions across multiple revisions', async () => {
            await contract.AnchorRecordHash(ctx, VALID_RECORD_ID_1, VALID_HASH_V1, '{}');
            mockStub.getTxID.returns('tx-revision-2');
            await contract.AnchorRecordHash(ctx, VALID_RECORD_ID_1, VALID_HASH_V2, '{}');

            const historyStr = await contract.GetRecordHistory(ctx, VALID_RECORD_ID_1);
            const history = JSON.parse(historyStr);

            expect(history).to.be.an('array');
            expect(history).to.have.lengthOf(2);
            expect(history[0].value.version).to.equal(1);
            expect(history[1].value.version).to.equal(2);
        });

        it('should fail when querying a non-existent record proof', async () => {
            try {
                await contract.GetRecordProof(ctx, 'non-existent-rec-999');
                expect.fail('Should have thrown missing record error');
            } catch (err) {
                expect(err.message).to.include('does not exist on ledger');
            }
        });

        it('should reject record IDs containing PHI keywords', async () => {
            try {
                await contract.AnchorRecordHash(ctx, 'patient_name_john_doe', VALID_HASH_V1, '{}');
                expect.fail('Should have rejected recordId with PHI term');
            } catch (err) {
                expect(err.message).to.include('PHI violation rejected');
            }
        });
    });

    describe('Consent Management & Security Boundaries', () => {
        it('should allow authorized gateway identity to grant consent', async () => {
            const resStr = await contract.GrantConsent(ctx, VALID_PATIENT_PSEUDO, VALID_PROVIDER_PSEUDO, VALID_SCOPE, '2028-12-31T23:59:59Z');
            const consent = JSON.parse(resStr);

            expect(consent.patientPseudoId).to.equal(VALID_PATIENT_PSEUDO);
            expect(consent.providerPseudoId).to.equal(VALID_PROVIDER_PSEUDO);
            expect(consent.scope).to.equal(VALID_SCOPE);
            expect(consent.status).to.equal('GRANTED');
            expect(consent.authBoundary.gatewayVerified).to.be.true;
            expect(consent.authBoundary.gatewayEnrollmentId).to.equal('org1admin');
            expect(consent.authBoundary.policy).to.equal('GATEWAY_DELEGATED_PATIENT_AUTH');
        });

        it('should fail-closed and reject ordinary enrolled identity (e.g. user1) from granting consent', async () => {
            // Ordinary user1 certificate context
            mockClientIdentity.getAttributeValue.withArgs('hf.EnrollmentID').returns('user1');
            mockClientIdentity.getX509Certificate.returns({
                subject: { commonName: 'user1', organizationalUnitName: 'client' }
            });

            try {
                await contract.GrantConsent(ctx, VALID_PATIENT_PSEUDO, VALID_PROVIDER_PSEUDO, VALID_SCOPE, '2028-12-31T23:59:59Z');
                expect.fail('Should have rejected ordinary user from granting consent');
            } catch (err) {
                expect(err.message).to.include('Access Denied: Caller \'user1\'');
                expect(err.message).to.include('not an authorized OncoVault Gateway identity');
            }
        });

        it('should fail-closed and reject ordinary enrolled identity from revoking consent', async () => {
            // Granted by gateway
            await contract.GrantConsent(ctx, VALID_PATIENT_PSEUDO, VALID_PROVIDER_PSEUDO, VALID_SCOPE, '2028-12-31T23:59:59Z');

            // Attempted revocation by ordinary user1
            mockClientIdentity.getAttributeValue.withArgs('hf.EnrollmentID').returns('user1');
            mockClientIdentity.getX509Certificate.returns({
                subject: { commonName: 'user1', organizationalUnitName: 'client' }
            });

            try {
                await contract.RevokeConsent(ctx, VALID_PATIENT_PSEUDO, VALID_PROVIDER_PSEUDO, VALID_SCOPE);
                expect.fail('Should have rejected ordinary user from revoking consent');
            } catch (err) {
                expect(err.message).to.include('Access Denied: Caller \'user1\'');
                expect(err.message).to.include('not an authorized OncoVault Gateway identity');
            }
        });

        it('should verify active consent status', async () => {
            await contract.GrantConsent(ctx, VALID_PATIENT_PSEUDO, VALID_PROVIDER_PSEUDO, VALID_SCOPE, '2028-12-31T23:59:59Z');

            const checkStr = await contract.CheckConsent(ctx, VALID_PATIENT_PSEUDO, VALID_PROVIDER_PSEUDO, VALID_SCOPE);
            const check = JSON.parse(checkStr);

            expect(check.active).to.be.true;
            expect(check.status).to.equal('GRANTED');
            expect(check.patientPseudoId).to.equal(VALID_PATIENT_PSEUDO);
        });

        it('should revoke previously granted consent via authorized gateway', async () => {
            await contract.GrantConsent(ctx, VALID_PATIENT_PSEUDO, VALID_PROVIDER_PSEUDO, VALID_SCOPE, '2028-12-31T23:59:59Z');

            mockStub.getTxID.returns('tx-synth-revoke-888');
            const revokeStr = await contract.RevokeConsent(ctx, VALID_PATIENT_PSEUDO, VALID_PROVIDER_PSEUDO, VALID_SCOPE);
            const revoked = JSON.parse(revokeStr);

            expect(revoked.status).to.equal('REVOKED');
            expect(revoked.txId).to.equal('tx-synth-revoke-888');

            const checkStr = await contract.CheckConsent(ctx, VALID_PATIENT_PSEUDO, VALID_PROVIDER_PSEUDO, VALID_SCOPE);
            const check = JSON.parse(checkStr);
            expect(check.active).to.be.false;
            expect(check.status).to.equal('REVOKED');
        });

        it('should reject revoking already revoked consent', async () => {
            await contract.GrantConsent(ctx, VALID_PATIENT_PSEUDO, VALID_PROVIDER_PSEUDO, VALID_SCOPE, '2028-12-31T23:59:59Z');
            await contract.RevokeConsent(ctx, VALID_PATIENT_PSEUDO, VALID_PROVIDER_PSEUDO, VALID_SCOPE);

            try {
                await contract.RevokeConsent(ctx, VALID_PATIENT_PSEUDO, VALID_PROVIDER_PSEUDO, VALID_SCOPE);
                expect.fail('Should have rejected double revocation');
            } catch (err) {
                expect(err.message).to.include('is already REVOKED');
            }
        });

        it('should detect expired consent', async () => {
            await contract.GrantConsent(ctx, VALID_PATIENT_PSEUDO, VALID_PROVIDER_PSEUDO, VALID_SCOPE, '2020-01-01T00:00:00Z');

            const checkStr = await contract.CheckConsent(ctx, VALID_PATIENT_PSEUDO, VALID_PROVIDER_PSEUDO, VALID_SCOPE);
            const check = JSON.parse(checkStr);

            expect(check.active).to.be.false;
            expect(check.status).to.equal('EXPIRED');
        });

        it('should return NOT_FOUND for non-existent consent record', async () => {
            const checkStr = await contract.CheckConsent(ctx, 'pat-unknown', 'prov-unknown', 'UNKNOWN_SCOPE');
            const check = JSON.parse(checkStr);

            expect(check.active).to.be.false;
            expect(check.status).to.equal('NOT_FOUND');
        });

        it('should track full grant and revoke history', async () => {
            await contract.GrantConsent(ctx, VALID_PATIENT_PSEUDO, VALID_PROVIDER_PSEUDO, VALID_SCOPE, 'NEVER');
            mockStub.getTxID.returns('tx-consent-rev');
            await contract.RevokeConsent(ctx, VALID_PATIENT_PSEUDO, VALID_PROVIDER_PSEUDO, VALID_SCOPE);

            const histStr = await contract.GetConsentHistory(ctx, VALID_PATIENT_PSEUDO, VALID_PROVIDER_PSEUDO, VALID_SCOPE);
            const hist = JSON.parse(histStr);

            expect(hist).to.be.an('array');
            expect(hist).to.have.lengthOf(2);
            expect(hist[0].value.status).to.equal('GRANTED');
            expect(hist[1].value.status).to.equal('REVOKED');
        });

        it('should reject unauthorized MSP from calling consent operations', async () => {
            mockClientIdentity.getMSPID.returns('MaliciousAttackerMSP');

            try {
                await contract.GrantConsent(ctx, VALID_PATIENT_PSEUDO, VALID_PROVIDER_PSEUDO, VALID_SCOPE, 'NEVER');
                expect.fail('Should have rejected unauthorized MSP');
            } catch (err) {
                expect(err.message).to.include('Access Denied: Caller MSP \'MaliciousAttackerMSP\' is not authorized');
            }
        });

        it('should reject invalid consent scope formatting', async () => {
            try {
                await contract.GrantConsent(ctx, VALID_PATIENT_PSEUDO, VALID_PROVIDER_PSEUDO, 'invalid scope with spaces!', 'NEVER');
                expect.fail('Should have rejected invalid scope format');
            } catch (err) {
                expect(err.message).to.include('must be 3-64 uppercase alphanumeric and underscore characters');
            }
        });
    });
});
