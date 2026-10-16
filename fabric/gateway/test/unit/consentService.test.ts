// test/unit/consentService.test.ts
import { expect } from 'chai';
import sinon from 'sinon';
import { config } from '../../src/config/env';
import { ConsentService } from '../../src/services/consentService';
import { AuthenticatedUser } from '../../src/types';

describe('ConsentService Unit Tests', () => {
  let consentService: ConsentService;
  let mockFabricGateway: any;
  let mockReconciliation: any;

  const PATIENT_USER: AuthenticatedUser = {
    uid: 'patient-test-abc',
    role: 'patient',
    email: 'pat@example.com'
  };

  const DOCTOR_USER: AuthenticatedUser = {
    uid: 'doctor-test-xyz',
    role: 'doctor',
    email: 'doc@example.com'
  };

  const VALID_PROVIDER = 'provider-onc-001';
  const VALID_SCOPE = 'BLOOD_CANCER_RESEARCH';

  beforeEach(() => {
    mockFabricGateway = {
      evaluateTransaction: sinon.stub(),
      submitTransaction: sinon.stub()
    };

    mockReconciliation = {
      acquireLock: sinon.stub().returns(true),
      releaseLock: sinon.stub(),
      startOperation: sinon.stub().resolves({}),
      markCommitted: sinon.stub().resolves({}),
      markStatus: sinon.stub().resolves({})
    };

    consentService = new ConsentService(mockFabricGateway, mockReconciliation);
  });

  describe('Live Consent Mutation Safety Gate (Phase 2 Requirement)', () => {
    it('should block live consent grant by default when ENABLE_LIVE_CONSENT_MUTATIONS is false', async () => {
      config.enableLiveConsentMutations = false;

      try {
        await consentService.grantConsent(PATIENT_USER, VALID_PROVIDER, VALID_SCOPE);
        expect.fail('Should have blocked live consent mutation');
      } catch (err: any) {
        expect(err.message).to.include('FEATURE_DISABLED');
        expect(err.message).to.include('ENABLE_LIVE_CONSENT_MUTATIONS=false');
      }
    });

    it('should block live consent revocation by default when ENABLE_LIVE_CONSENT_MUTATIONS is false', async () => {
      config.enableLiveConsentMutations = false;

      try {
        await consentService.revokeConsent(PATIENT_USER, VALID_PROVIDER, VALID_SCOPE);
        expect.fail('Should have blocked live consent revocation');
      } catch (err: any) {
        expect(err.message).to.include('FEATURE_DISABLED');
        expect(err.message).to.include('ENABLE_LIVE_CONSENT_MUTATIONS=false');
      }
    });
  });

  describe('Patient Consent Lifecycle (When Enabled)', () => {
    beforeEach(() => {
      config.enableLiveConsentMutations = true;
    });

    afterEach(() => {
      config.enableLiveConsentMutations = false;
    });

    it('should successfully submit patient-authorized consent to chaincode', async () => {
      const mockChaincodeConsent = {
        patientPseudoId: 'pat_pseudonym_123',
        providerPseudoId: 'prov_pseudonym_456',
        scope: VALID_SCOPE,
        status: 'GRANTED',
        txId: 'tx-consent-granted-777',
        timestamp: '2026-10-16T12:00:00Z',
        authBoundary: {
          gatewayVerified: true,
          gatewayEnrollmentId: 'oncovault-gateway'
        }
      };

      mockFabricGateway.submitTransaction.resolves({
        result: JSON.stringify(mockChaincodeConsent),
        txId: 'tx-consent-granted-777'
      });

      const res = await consentService.grantConsent(PATIENT_USER, VALID_PROVIDER, VALID_SCOPE);

      expect(res.consent.status).to.equal('GRANTED');
      expect(res.patientPseudoId.startsWith('pat_')).to.be.true;
      expect(res.providerPseudoId.startsWith('prov_')).to.be.true;
      // Submitting args to Fabric never contain raw patient UID!
      const submitArgs = mockFabricGateway.submitTransaction.firstCall.args;
      expect(submitArgs).to.not.include(PATIENT_USER.uid);
    });

    it('should reject non-patient caller attempting to grant consent', async () => {
      try {
        await consentService.grantConsent(DOCTOR_USER, VALID_PROVIDER, VALID_SCOPE);
        expect.fail('Should have rejected non-patient caller');
      } catch (err: any) {
        expect(err.message).to.include('Only authenticated patients may grant');
      }
    });

    it('should reject unapproved consent scope', async () => {
      try {
        await consentService.grantConsent(PATIENT_USER, VALID_PROVIDER, 'UNAPPROVED_CUSTOM_SCOPE');
        expect.fail('Should have rejected unapproved scope');
      } catch (err: any) {
        expect(err.message).to.include('Invalid consent scope');
      }
    });
  });

  describe('Consent Queries (Active Regardless of Mutation Gate)', () => {
    it('should evaluate active consent check on ledger', async () => {
      mockFabricGateway.evaluateTransaction.resolves(JSON.stringify({
        active: true,
        status: 'GRANTED',
        scope: VALID_SCOPE
      }));

      const res = await consentService.checkConsent(PATIENT_USER, PATIENT_USER.uid, VALID_PROVIDER, VALID_SCOPE);

      expect(res.active).to.be.true;
      expect(res.status).to.equal('GRANTED');
    });

    it('should retrieve full consent audit history from ledger', async () => {
      mockFabricGateway.evaluateTransaction.resolves(JSON.stringify([
        { txId: 'tx-1', value: { status: 'GRANTED' } },
        { txId: 'tx-2', value: { status: 'REVOKED' } }
      ]));

      const history = await consentService.getConsentHistory(PATIENT_USER, PATIENT_USER.uid, VALID_PROVIDER, VALID_SCOPE);

      expect(history).to.be.an('array');
      expect(history).to.have.lengthOf(2);
      expect(history[0].value.status).to.equal('GRANTED');
      expect(history[1].value.status).to.equal('REVOKED');
    });
  });
});
