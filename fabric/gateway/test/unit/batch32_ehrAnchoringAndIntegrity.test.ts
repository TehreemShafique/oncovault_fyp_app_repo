// test/unit/batch32_ehrAnchoringAndIntegrity.test.ts
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099';

import { expect } from 'chai';
import sinon from 'sinon';
import { RecordService } from '../../src/services/recordService';
import { FirebaseAdminService } from '../../src/services/firebaseAdmin';
import { AuthenticatedUser } from '../../src/types';
import { ReconciliationService } from '../../src/services/reconciliationService';
import { MemoryFirestore } from '../helpers/memoryFirestore';

describe('Batch 3.2 — Main Blood Cancer EHR Blockchain Anchoring Tests', () => {
  let recordService: RecordService;
  let firebaseAdmin: FirebaseAdminService;
  let mockFabricGateway: any;
  let mockFirestore: any;
  let newDatabase: MemoryFirestore;

  const PATIENT_ALPHA: AuthenticatedUser = {
    uid: 'pat-ehr-alpha',
    role: 'patient',
    email: 'alpha@patient.com'
  };

  const ATTENDING_DOCTOR: AuthenticatedUser = {
    uid: 'doc-oncologist-01',
    role: 'doctor',
    email: 'doctor@hospital.com'
  };

  const NURSE: AuthenticatedUser = {
    uid: 'nurse-intake-01',
    role: 'nurse',
    email: 'nurse@hospital.com'
  };

  const sampleEhr: Record<string, any> = {
    recordId: 'ehr-blood-cancer-001',
    patientId: 'pat-ehr-alpha',
    doctorId: 'doc-oncologist-01',
    doctorName: 'Dr. Sarah Smith, MD',
    createdAt: new Date('2026-05-10T10:00:00.000Z'),
    updatedAt: new Date('2026-05-10T11:00:00.000Z'),
    diseaseType: 'Acute Leukemia',
    diagnosisSubtype: 'Acute Myeloid Leukemia (AML)',
    stage: 'Intermediate Risk',
    diagnosisStatus: 'Active Induction',
    blastCellPercentage: 28.5,
    boneMarrowBiopsy: 'Hypercellular marrow with 28% myeloblasts, CD34+, CD117+',
    chemotherapy: '7+3 Regimen (Cytarabine + Daunorubicin)',
    clinicalNotes: 'Patient admitted for 7+3 induction chemotherapy. Monitor for tumor lysis syndrome.',
    voiceTranscription: 'Dictated by Dr. Sarah Smith: Patient presents with persistent fatigue and leukocytosis.',
    medications: ['Allopurinol 300mg', 'Cytarabine 100mg/m2', 'Daunorubicin 60mg/m2', 'Ondansetron 8mg'],
    cbc: {
      WBC: 45.2,
      RBC: 2.85,
      Hemoglobin: 8.4,
      Hematocrit: 25.1,
      Platelets: 38.0,
      Neutrophils: { absolute: 1.2, percentage: 2.6 },
      Lymphocytes: { absolute: 2.1, percentage: 4.6 },
      Monocytes: { absolute: 0.8, percentage: 1.8 },
      Eosinophils: { absolute: 0.1, percentage: 0.2 },
      Basophils: { absolute: 0.05, percentage: 0.1 },
      'RDW-CV': 16.8,
      'RDW-SD': 52.4
    },
    symptoms: {
      bonePain: true,
      enlargedLiver: false,
      familyHistory: false,
      fever: true,
      frequentInfections: true,
      itchySkinOrRash: false,
      jaundice: false,
      lossOfAppetiteOrNausea: true,
      nightSweats: true,
      oralCavityChanges: false,
      persistentWeaknessAndFatigue: true,
      shortnessOfBreath: true,
      significantBruisingOrBleeding: true,
      smokes: false,
      swollenPainlessLymphNodes: true,
      visionBlurring: false
    },
    aiAnalysis: {
      doctorReviewed: true,
      modelVersion: 'OncoVault-Dual-v1.4',
      prediction: 'High probability of Acute Myeloid Leukemia (AML)',
      riskScore: 0.92
    }
  };

  beforeEach(() => {
    newDatabase = new MemoryFirestore();
    mockFabricGateway = {
      evaluateTransaction: sinon.stub(),
      submitTransaction: sinon.stub()
    };

    mockFirestore = {
      collection: sinon.stub(),
      collectionGroup: sinon.stub()
    };

    firebaseAdmin = FirebaseAdminService.getInstance();
    firebaseAdmin.setMockInstances(null, mockFirestore, null);

    recordService = new RecordService(mockFabricGateway, firebaseAdmin,
      new ReconciliationService({ getFirestoreInstance: () => newDatabase } as any));
  });

  afterEach(() => {
    sinon.restore();
  });

  describe('Task 1: Canonical Blood Cancer EHR Hash Determinism & Clinical Mutation Coverage', () => {
    it('1. should compute identical SHA-256 hash regardless of object key insertion order', () => {
      const hash1 = recordService.computeCanonicalEhrHash(sampleEhr);

      // Reorder keys completely
      const reorderedEhr: Record<string, any> = {
        medications: [...sampleEhr.medications],
        symptoms: { ...sampleEhr.symptoms },
        recordId: sampleEhr.recordId,
        cbc: { ...sampleEhr.cbc },
        doctorName: sampleEhr.doctorName,
        aiAnalysis: { ...sampleEhr.aiAnalysis },
        patientId: sampleEhr.patientId,
        diseaseType: sampleEhr.diseaseType,
        blastCellPercentage: sampleEhr.blastCellPercentage,
        createdAt: sampleEhr.createdAt,
        doctorId: sampleEhr.doctorId,
        stage: sampleEhr.stage,
        diagnosisSubtype: sampleEhr.diagnosisSubtype,
        diagnosisStatus: sampleEhr.diagnosisStatus,
        boneMarrowBiopsy: sampleEhr.boneMarrowBiopsy,
        chemotherapy: sampleEhr.chemotherapy,
        clinicalNotes: sampleEhr.clinicalNotes,
        voiceTranscription: sampleEhr.voiceTranscription
      };

      const hash2 = recordService.computeCanonicalEhrHash(reorderedEhr);
      expect(hash1).to.equal(hash2);
      expect(hash1).to.have.lengthOf(64);
    });

    it('2. should alter hash when CBC hemoglobin or platelet count is mutated', () => {
      const originalHash = recordService.computeCanonicalEhrHash(sampleEhr);

      const tamperedCbc = JSON.parse(JSON.stringify(sampleEhr));
      tamperedCbc.cbc.Hemoglobin = 12.0; // Tampered from 8.4

      const tamperedHash = recordService.computeCanonicalEhrHash(tamperedCbc);
      expect(tamperedHash).to.not.equal(originalHash);
    });

    it('3. should alter hash when differential leukocyte counts are mutated', () => {
      const originalHash = recordService.computeCanonicalEhrHash(sampleEhr);

      const tamperedDiff = JSON.parse(JSON.stringify(sampleEhr));
      tamperedDiff.cbc.Neutrophils.percentage = 15.0; // Tampered from 2.6

      const tamperedHash = recordService.computeCanonicalEhrHash(tamperedDiff);
      expect(tamperedHash).to.not.equal(originalHash);
    });

    it('4. should alter hash when any of the 16 hematologic symptoms are mutated', () => {
      const originalHash = recordService.computeCanonicalEhrHash(sampleEhr);

      const tamperedSymptoms = JSON.parse(JSON.stringify(sampleEhr));
      tamperedSymptoms.symptoms.bonePain = false; // Mutated from true to false

      const tamperedHash = recordService.computeCanonicalEhrHash(tamperedSymptoms);
      expect(tamperedHash).to.not.equal(originalHash);
    });

    it('5. should alter hash when blast cell percentage or bone marrow biopsy is modified', () => {
      const originalHash = recordService.computeCanonicalEhrHash(sampleEhr);

      const tamperedMarrow = JSON.parse(JSON.stringify(sampleEhr));
      tamperedMarrow.blastCellPercentage = 5.0; // Mutated from 28.5%

      const tamperedHash = recordService.computeCanonicalEhrHash(tamperedMarrow);
      expect(tamperedHash).to.not.equal(originalHash);
    });

    it('6. should alter hash when prescribed medications list is altered', () => {
      const originalHash = recordService.computeCanonicalEhrHash(sampleEhr);

      const tamperedMeds = JSON.parse(JSON.stringify(sampleEhr));
      tamperedMeds.medications.push('Morphine 10mg');

      const tamperedHash = recordService.computeCanonicalEhrHash(tamperedMeds);
      expect(tamperedHash).to.not.equal(originalHash);
    });

    it('7. should NOT alter hash when volatile non-clinical fields change (updatedAt, storedHash, blockchainTxId, fabricStatus)', () => {
      const originalHash = recordService.computeCanonicalEhrHash(sampleEhr);

      const ehrWithVolatileUpdates = {
        ...sampleEhr,
        updatedAt: new Date('2026-05-15T18:30:00.000Z'),
        storedHash: 'some-previous-hash',
        blockchainTxId: '0x1234567890abcdef',
        fabricStatus: 'COMMITTED',
        fabricTxId: 'tx-fabric-999',
        fabricVersion: 2,
        fabricTimestamp: '2026-05-10T10:05:00Z',
        lastAnchoredAt: new Date().toISOString()
      };

      const hashWithVolatile = recordService.computeCanonicalEhrHash(ehrWithVolatileUpdates);
      expect(hashWithVolatile).to.equal(originalHash);
    });

    it('8. should NOT include unreviewed advisory AI analysis (doctorReviewed: false) in hash', () => {
      const ehrNoAi = { ...sampleEhr, aiAnalysis: null };
      const ehrUnreviewedAi = {
        ...sampleEhr,
        aiAnalysis: {
          doctorReviewed: false,
          modelVersion: 'Experimental-AI-v2',
          prediction: 'Tentative AML prediction',
          riskScore: 0.88
        }
      };

      const hashNoAi = recordService.computeCanonicalEhrHash(ehrNoAi);
      const hashUnreviewedAi = recordService.computeCanonicalEhrHash(ehrUnreviewedAi);

      // Unreviewed AI is purely advisory and must not change the canonical clinical hash
      expect(hashUnreviewedAi).to.equal(hashNoAi);
    });

    it('9. should protect doctor-reviewed AI analysis (doctorReviewed: true) in canonical hash', () => {
      const ehrUnreviewedAi = {
        ...sampleEhr,
        aiAnalysis: {
          doctorReviewed: false,
          modelVersion: 'OncoVault-v1.4',
          prediction: 'AML',
          riskScore: 0.92
        }
      };

      const ehrReviewedAi = {
        ...sampleEhr,
        aiAnalysis: {
          doctorReviewed: true,
          modelVersion: 'OncoVault-v1.4',
          prediction: 'AML',
          riskScore: 0.92
        }
      };

      const hashUnreviewed = recordService.computeCanonicalEhrHash(ehrUnreviewedAi);
      const hashReviewed = recordService.computeCanonicalEhrHash(ehrReviewedAi);

      expect(hashReviewed).to.not.equal(hashUnreviewed);
    });
  });

  describe('Task 2: Doctor Finalization & Anchoring Gate Enforcement', () => {
    it('10. should allow attending physician to anchor finalized Blood Cancer EHR to Fabric', async () => {
      sinon.stub(recordService as any, 'assertRecordAccess').resolves();
      sinon.stub(firebaseAdmin, 'getMedicalRecord').resolves({
        ...sampleEhr,
        isBloodCancerEhr: true,
        documentType: 'BLOOD_CANCER_EHR'
      });
      sinon.stub(firebaseAdmin, 'updateRecordProof').resolves();

      const expectedHash = recordService.computeCanonicalEhrHash(sampleEhr);
      const mockProof = {
        recordId: 'opaqueKey123',
        sha256Hash: expectedHash,
        txId: 'tx-ehr-anchor-001',
        timestamp: new Date().toISOString(),
        version: 1,
        metadata: {
          documentType: 'EHR',
          schemaVersion: '2.0'
        }
      };

      mockFabricGateway.evaluateTransaction.callsFake(async (_name: string, key: string) => {
        throw { code: 2, details: [{ message: `chaincode response 500, Record '${key}' does not exist on ledger.` }] };
      });
      mockFabricGateway.submitTransaction.resolves({
        result: JSON.stringify(mockProof),
        txId: 'tx-ehr-anchor-001'
      });

      const res = await recordService.anchorRecord(
        ATTENDING_DOCTOR,
        'ehr-blood-cancer-001',
        { documentType: 'BLOOD_CANCER_EHR' },
        undefined,
        'pat-ehr-alpha'
      );

      expect(res.proof.txId).to.equal('tx-ehr-anchor-001');
      expect(res.fileHash).to.equal(expectedHash);
      expect(mockFabricGateway.submitTransaction.calledOnce).to.be.true;

      // Keep the clinical classification off-chain while preserving schema/hash.
      const metadataArg = JSON.parse(mockFabricGateway.submitTransaction.firstCall.args[3]);
      expect(metadataArg.documentType).to.equal('EHR');
      expect(metadataArg.schemaVersion).to.equal('2.0');
      const Contract = require('../../../chaincode/oncovault/lib/oncovault-contract');
      const contract = new Contract();
      expect(() => contract._validateAndSanitizeMetadata(JSON.stringify({
        documentType: 'BLOOD_CANCER_EHR', schemaVersion: '2.0'
      }))).to.throw("forbidden term 'cancer'");
      expect(contract._validateAndSanitizeMetadata(JSON.stringify(metadataArg))).to.deep.equal(metadataArg);
      expect(mockFabricGateway.submitTransaction.firstCall.args[2]).to.equal(expectedHash);
    });

    it('does not publish proof or report success after an endorsement rejection', async () => {
      sinon.stub(recordService as any, 'assertRecordAccess').resolves();
      sinon.stub(firebaseAdmin, 'getMedicalRecord').resolves({
        ...sampleEhr, isBloodCancerEhr: true, documentType: 'BLOOD_CANCER_EHR'
      });
      const update = sinon.stub(firebaseAdmin, 'updateRecordProof').resolves();
      mockFabricGateway.evaluateTransaction.callsFake(async (_name: string, key: string) => {
        throw { code: 2, details: [{ message: `chaincode response 500, Record '${key}' does not exist on ledger.` }] };
      });
      mockFabricGateway.submitTransaction.rejects(new Error('10 ABORTED: failed to endorse transaction'));
      let error: any;
      try {
        await recordService.anchorRecord(ATTENDING_DOCTOR, sampleEhr.recordId,
          { documentType: 'BLOOD_CANCER_EHR' }, undefined, sampleEhr.patientId);
      } catch (caught) { error = caught; }
      expect(error?.message).to.include('failed to endorse transaction');
      expect(update.called).to.equal(false);
      expect(mockFabricGateway.submitTransaction.calledOnce).to.equal(true);
    });

    it('11. should strictly reject nurse intake from anchoring Blood Cancer EHR directly', async () => {
      sinon.stub(recordService as any, 'assertRecordAccess').resolves();
      sinon.stub(firebaseAdmin, 'getMedicalRecord').resolves({
        ...sampleEhr,
        isBloodCancerEhr: true,
        documentType: 'BLOOD_CANCER_EHR'
      });

      try {
        await recordService.anchorRecord(
          NURSE,
          'ehr-blood-cancer-001',
          { documentType: 'BLOOD_CANCER_EHR' },
          undefined,
          'pat-ehr-alpha'
        );
        expect.fail('Nurse should have been rejected');
      } catch (err: any) {
        expect(err.message).to.include('Access Denied: Only attending physicians may finalize and anchor Blood Cancer EHRs');
      }

      expect(mockFabricGateway.submitTransaction.called).to.be.false;
    });
  });

  describe('Task 3: Blood Cancer EHR Verification Flow', () => {
    it('12. should return VERIFIED when current EHR content matches ledger proof', async () => {
      sinon.stub(recordService as any, 'assertRecordAccess').resolves();
      sinon.stub(firebaseAdmin, 'getMedicalRecord').resolves({
        ...sampleEhr,
        isBloodCancerEhr: true,
        documentType: 'BLOOD_CANCER_EHR'
      });

      const canonicalHash = recordService.computeCanonicalEhrHash(sampleEhr);
      const mockLedgerProof = {
        recordId: 'opaqueKey123',
        sha256Hash: canonicalHash,
        txId: 'tx-fabric-ehr-verified',
        timestamp: new Date().toISOString(),
        version: 1,
        metadata: {
          documentType: 'BLOOD_CANCER_EHR',
          schemaVersion: '2.0'
        }
      };

      mockFabricGateway.evaluateTransaction.withArgs('GetRecordProof').resolves(JSON.stringify(mockLedgerProof));
      mockFabricGateway.evaluateTransaction.withArgs('VerifyRecordHash').resolves(JSON.stringify({ verified: true }));

      const res = await recordService.verifyRecord(
        PATIENT_ALPHA,
        'ehr-blood-cancer-001',
        undefined,
        'pat-ehr-alpha'
      );

      expect(res.verified).to.be.true;
      expect(res.status).to.equal('VERIFIED');
      expect(res.ledgerProof?.txId).to.equal('tx-fabric-ehr-verified');
      expect(res.message).to.include('Blood Cancer EHR cryptographic integrity verified');
    });

    it('13. should return TAMPERED_OR_MISMATCH when current EHR content differs from ledger proof', async () => {
      sinon.stub(recordService as any, 'assertRecordAccess').resolves();
      // Database has tampered CBC (WBC changed from 45.2 to 5.0)
      const tamperedRecord = {
        ...sampleEhr,
        isBloodCancerEhr: true,
        documentType: 'BLOOD_CANCER_EHR',
        cbc: {
          ...sampleEhr.cbc,
          WBC: 5.0
        }
      };
      sinon.stub(firebaseAdmin, 'getMedicalRecord').resolves(tamperedRecord);

      // Ledger has original hash
      const originalLedgerHash = recordService.computeCanonicalEhrHash(sampleEhr);
      const mockLedgerProof = {
        recordId: 'opaqueKey123',
        sha256Hash: originalLedgerHash,
        txId: 'tx-fabric-ehr-original',
        timestamp: new Date().toISOString(),
        version: 1,
        metadata: {
          documentType: 'BLOOD_CANCER_EHR',
          schemaVersion: '2.0'
        }
      };

      mockFabricGateway.evaluateTransaction.withArgs('GetRecordProof').resolves(JSON.stringify(mockLedgerProof));

      const res = await recordService.verifyRecord(
        PATIENT_ALPHA,
        'ehr-blood-cancer-001',
        undefined,
        'pat-ehr-alpha'
      );

      expect(res.verified).to.be.false;
      expect(res.status).to.equal('TAMPERED_OR_MISMATCH');
      expect(res.message).to.include('INTEGRITY MISMATCH');
    });
  });
});
