// test/unit/consentService.test.ts
import { expect } from 'chai';
import sinon from 'sinon';
import { config } from '../../src/config/env';
import { ConsentService } from '../../src/services/consentService';
import { FirebaseAdminService } from '../../src/services/firebaseAdmin';
import { AuthenticatedUser } from '../../src/types';
import { PseudonymService } from '../../src/services/pseudonymService';

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
      submitTransaction: sinon.stub(),
      submitConsentTransaction: sinon.stub()
    };

    mockReconciliation = {
      claimConsentOperation: sinon.stub().callsFake(async (operation: any) => ({ operation, claimed: true })),
      updateConsentOperation: sinon.stub().callsFake(async (operation: any, changes: any) => ({ ...operation, ...changes })),
      projectConsentOperation: sinon.stub().callsFake(async (operation: any) => ({ ...operation, projectionPending: false })),
      acquireLock: sinon.stub().returns(true),
      releaseLock: sinon.stub(),
      startOperation: sinon.stub().resolves({}),
      markCommitted: sinon.stub().resolves({}),
      markStatus: sinon.stub().resolves({})
    };

    const mockFirestore = {
      collection: sinon.stub().returns({
        doc: sinon.stub().returns({
          set: sinon.stub().resolves({}),
          get: sinon.stub().callsFake(async () => ({ exists: true, data: () => ({ role: 'patient' }) }))
        })
      })
    };
    mockFirestore.collection.callsFake((name: string) => ({ doc: (id: string) => ({
      get: async () => ({ exists: true, data: () => ({ role: id === PATIENT_USER.uid ? 'patient' : 'doctor' }) })
    }) }));
    const mockFirebaseAdmin = {
      getFirestoreInstance: sinon.stub().returns(mockFirestore)
    };

    consentService = new ConsentService(mockFabricGateway, mockReconciliation, mockFirebaseAdmin);
  });

  describe('Live Consent Mutation Safety Gate (Phase 2 Requirement)', () => {
    it('should block live consent grant by default when ENABLE_LIVE_CONSENT_MUTATIONS is false', async () => {
      config.enableLiveConsentMutations = false;

      try {
        await consentService.grantConsent(PATIENT_USER, VALID_PROVIDER, VALID_SCOPE, 'NEVER', 'fictional-request-key-001');
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
        patientPseudoId: PseudonymService.generatePatientPseudoId(PATIENT_USER.uid),
        providerPseudoId: PseudonymService.generateProviderPseudoId(VALID_PROVIDER),
        scope: VALID_SCOPE,
        status: 'GRANTED',
        txId: 'tx-consent-granted-777',
        timestamp: '2026-10-16T12:00:00Z',
        authBoundary: {
          gatewayVerified: true,
          gatewayEnrollmentId: 'oncovault-gateway'
        }
      };

      mockFabricGateway.evaluateTransaction.resolves(JSON.stringify({ active: false, status: 'NOT_FOUND' }));
      mockFabricGateway.submitConsentTransaction.callsFake(async (_name: string, _args: string[], prepared: any) => {
        await prepared('tx-consent-granted-777');
        return { result: JSON.stringify(mockChaincodeConsent), txId: 'tx-consent-granted-777' };
      });

      const res = await consentService.grantConsent(PATIENT_USER, VALID_PROVIDER, VALID_SCOPE, 'NEVER', 'fictional-request-key-001');

      expect(res.consent.status).to.equal('GRANTED');
      expect(res.patientPseudoId.startsWith('pat_')).to.be.true;
      expect(res.providerPseudoId.startsWith('prov_')).to.be.true;
      // Submitting args to Fabric never contain raw patient UID!
      const submitArgs = mockFabricGateway.submitConsentTransaction.firstCall.args[1];
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
        await consentService.grantConsent(PATIENT_USER, VALID_PROVIDER, 'UNAPPROVED_CUSTOM_SCOPE', 'NEVER', 'fictional-request-key-001');
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
  describe('Read-only consent history response normalization', () => {
    function emptyHistoryError() {
      const patient = PseudonymService.generatePatientPseudoId(PATIENT_USER.uid);
      const provider = PseudonymService.generateProviderPseudoId(VALID_PROVIDER);
      return Object.assign(new Error('evaluate failed'), {
        code: 2,
        details: [{ message: `chaincode response 500, No consent history found for patient '${patient}', provider '${provider}', scope 'DIRECT_CARE'.` }]
      });
    }

    it('normalizes the observed peer empty-history response to an empty array', async () => {
      mockFabricGateway.evaluateTransaction.rejects(emptyHistoryError());
      const history = await consentService.getConsentHistory(PATIENT_USER, PATIENT_USER.uid, VALID_PROVIDER, 'DIRECT_CARE');
      expect(history).to.deep.equal([]);
      expect(mockFabricGateway.evaluateTransaction.firstCall.args[0]).to.equal('GetConsentHistory');
      expect(mockFabricGateway.submitTransaction.called).to.equal(false);
    });

    it('preserves an explicit successful empty history result', async () => {
      mockFabricGateway.evaluateTransaction.resolves('[]');
      expect(await consentService.getConsentHistory(PATIENT_USER, PATIENT_USER.uid, VALID_PROVIDER, 'DIRECT_CARE')).to.deep.equal([]);
    });

    for (const variant of ['timeout', 'disabled', 'permission', 'missing-details', 'wrong-key', 'mixed-peer']) {
      it(`does not convert ${variant} failures into empty history`, async () => {
        const error = emptyHistoryError();
        if (variant === 'timeout') error.code = 4;
        if (variant === 'disabled') error.details[0].message = 'history database is not enabled';
        if (variant === 'permission') error.details[0].message = 'Access Denied';
        if (variant === 'missing-details') error.details = [];
        if (variant === 'wrong-key') error.details[0].message = error.details[0].message.replace('DIRECT_CARE', 'OTHER_SCOPE');
        if (variant === 'mixed-peer') error.details.push({message: 'peer unavailable'});
        mockFabricGateway.evaluateTransaction.rejects(error);
        let caught: unknown;
        try {
          await consentService.getConsentHistory(PATIENT_USER, PATIENT_USER.uid, VALID_PROVIDER, 'DIRECT_CARE');
        } catch (err) { caught = err; }
        expect(caught).to.equal(error);
      });
    }

    it('rejects a malformed successful history payload', async () => {
      mockFabricGateway.evaluateTransaction.resolves('{}');
      let caught: any;
      try {
        await consentService.getConsentHistory(PATIENT_USER, PATIENT_USER.uid, VALID_PROVIDER, 'DIRECT_CARE');
      } catch (err) { caught = err; }
      expect(caught?.message).to.include('Invalid consent history response');
    });
  });

});
