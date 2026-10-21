// test/unit/batch31_recordLookupAndSafety.test.ts
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099';

import { expect } from 'chai';
import sinon from 'sinon';
import { RecordService } from '../../src/services/recordService';
import { FirebaseAdminService } from '../../src/services/firebaseAdmin';
import { AuthenticatedUser } from '../../src/types';

describe('Batch 3.1 — Gateway Multi-Collection Support & Clinical Safety Tests', () => {
  let recordService: RecordService;
  let firebaseAdmin: FirebaseAdminService;
  let mockFabricGateway: any;
  let mockFirestore: any;

  const PATIENT_A: AuthenticatedUser = {
    uid: 'pat-alpha',
    role: 'patient',
    email: 'alpha@patient.com'
  };

  const PATIENT_B: AuthenticatedUser = {
    uid: 'pat-beta',
    role: 'patient',
    email: 'beta@patient.com'
  };

  const DOCTOR: AuthenticatedUser = {
    uid: 'doc-oncologist',
    role: 'doctor',
    email: 'doctor@hospital.com'
  };

  const UNASSIGNED_NURSE: AuthenticatedUser = {
    uid: 'nurse-unassigned',
    role: 'nurse',
    email: 'nurse@hospital.com'
  };

  beforeEach(() => {
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

    recordService = new RecordService(mockFabricGateway, firebaseAdmin);
  });

  afterEach(() => {
    sinon.restore();
  });

  describe('Task 1: Prescription Hashing Safety (No Default Route Invention)', () => {
    it('1. should preserve empty string when administration route is omitted (never default to Oral)', () => {
      const rxNoRoute = {
        id: 'rx-safety-001',
        patientId: 'pat-alpha',
        type: 'prescription',
        summary: 'Cisplatin 500mg',
        prescriptionData: {
          drugs: [
            {
              name: 'Cisplatin',
              dosage: '500mg',
              frequency: 'Once Daily',
              duration: '14 days'
              // route omitted
            }
          ]
        }
      };

      const rxWithOralRoute = {
        ...rxNoRoute,
        prescriptionData: {
          drugs: [
            {
              name: 'Cisplatin',
              dosage: '500mg',
              frequency: 'Once Daily',
              duration: '14 days',
              route: 'Oral' // explicitly oral
            }
          ]
        }
      };

      const hashNoRoute = recordService.computeCanonicalPrescriptionHash(rxNoRoute);
      const hashOralRoute = recordService.computeCanonicalPrescriptionHash(rxWithOralRoute);

      // Distinct hashes prove omitted route does NOT silently become 'Oral'
      expect(hashNoRoute).to.not.equal(hashOralRoute);
    });

    it('2. should produce distinct hashes for Oral, IV, and Subcutaneous administration routes', () => {
      const base = {
        id: 'rx-route-test',
        patientId: 'pat-alpha',
        type: 'prescription',
        summary: 'Chemotherapy Regimen',
        prescriptionData: {
          drugs: [
            {
              name: 'Antineoplastic Agent',
              dosage: '100mg',
              frequency: 'Daily'
            }
          ]
        }
      };

      const oralRx = {
        ...base,
        prescriptionData: {
          drugs: [{ ...base.prescriptionData.drugs[0], route: 'Oral' }]
        }
      };

      const ivRx = {
        ...base,
        prescriptionData: {
          drugs: [{ ...base.prescriptionData.drugs[0], route: 'IV' }]
        }
      };

      const scRx = {
        ...base,
        prescriptionData: {
          drugs: [{ ...base.prescriptionData.drugs[0], route: 'Subcutaneous' }]
        }
      };

      const hashOral = recordService.computeCanonicalPrescriptionHash(oralRx);
      const hashIV = recordService.computeCanonicalPrescriptionHash(ivRx);
      const hashSC = recordService.computeCanonicalPrescriptionHash(scRx);

      expect(hashOral).to.not.equal(hashIV);
      expect(hashOral).to.not.equal(hashSC);
      expect(hashIV).to.not.equal(hashSC);
    });

    it('3. should preserve backward compatibility for Schema 1.0 metadata-only proofs', () => {
      const legacyRx = {
        id: 'M1DOXGGk8jkufpcZlLMV',
        patientId: 'pMmOMQRA6qYipn94DvzBdZiuvmE3',
        type: 'prescription',
        subtype: 'Digital Prescription',
        facility: 'OncoVault Medical Center',
        summary: 'Cisplatin 500mg — Twice daily'
      };

      const legacyHash = recordService.computeCanonicalMetadataHash(legacyRx);
      expect(legacyHash).to.equal('135190ee8af58fa6ec6cc05eee287730205d48f23d4c5dbb2a5f7c5868c21dd7');
    });
  });

  describe('Task 2: Extended Firestore Document Lookup Support', () => {
    it('4. should resolve Blood Cancer EHR document under patients/{patientId}/blood_cancer_ehrs/{ehrId}', async () => {
      const ehrData = {
        patientId: 'pat-alpha',
        doctorId: 'doc-oncologist',
        doctorName: 'Dr. Oncologist',
        diseaseType: 'Acute Lymphoblastic Leukemia',
        stage: 'Stage II',
        cbc: { wbc: 4.5, hemoglobin: 12.0 },
        symptoms: { fever: false, bonePain: true }
      };

      const mockDoc = {
        id: 'ehr-alpha-001',
        exists: true,
        data: () => ehrData
      };

      const mockSubcollection = {
        doc: sinon.stub().withArgs('ehr-alpha-001').returns({
          get: sinon.stub().resolves(mockDoc)
        })
      };

      const mockPatientDoc = {
        collection: sinon.stub()
      };
      // When collection('medicalRecords') is called -> not found
      mockPatientDoc.collection.withArgs('medicalRecords').returns({
        doc: sinon.stub().returns({ get: sinon.stub().resolves({ exists: false }) })
      });
      // When collection('clinical_notes') is called -> not found
      mockPatientDoc.collection.withArgs('clinical_notes').returns({
        doc: sinon.stub().returns({ get: sinon.stub().resolves({ exists: false }) })
      });
      // When collection('blood_cancer_ehrs') is called -> returns mockDoc
      mockPatientDoc.collection.withArgs('blood_cancer_ehrs').returns(mockSubcollection);

      const mockPatientsColl = {
        doc: sinon.stub().withArgs('pat-alpha').returns(mockPatientDoc)
      };

      mockFirestore.collection.withArgs('medical_records').returns({
        doc: sinon.stub().returns({ get: sinon.stub().resolves({ exists: false }) })
      });
      mockFirestore.collection.withArgs('patients').returns(mockPatientsColl);
      mockFirestore.collectionGroup.returns({
        where: sinon.stub().returns({ get: sinon.stub().resolves({ empty: true }) })
      });

      const result = await firebaseAdmin.getMedicalRecord('ehr-alpha-001', 'pat-alpha');

      expect(result).to.not.be.null;
      expect(result.id).to.equal('ehr-alpha-001');
      expect(result.documentType).to.equal('BLOOD_CANCER_EHR');
      expect(result.isBloodCancerEhr).to.be.true;
      expect(result.diseaseType).to.equal('Acute Lymphoblastic Leukemia');
    });

    it('5. should resolve Diagnosis document under patients/{patientId}/diagnoses/{diagnosisId}', async () => {
      const diagData = {
        patientId: 'pat-alpha',
        doctorId: 'doc-oncologist',
        doctorName: 'Dr. Oncologist',
        diagnosisTitle: 'Confirmed B-Cell ALL',
        stage: 'Stage III',
        status: 'critical'
      };

      const mockDoc = {
        id: 'diag-alpha-001',
        exists: true,
        data: () => diagData
      };

      const mockSubcollection = {
        doc: sinon.stub().withArgs('diag-alpha-001').returns({
          get: sinon.stub().resolves(mockDoc)
        })
      };

      const mockPatientDoc = {
        collection: sinon.stub()
      };
      mockPatientDoc.collection.withArgs('medicalRecords').returns({
        doc: sinon.stub().returns({ get: sinon.stub().resolves({ exists: false }) })
      });
      mockPatientDoc.collection.withArgs('clinical_notes').returns({
        doc: sinon.stub().returns({ get: sinon.stub().resolves({ exists: false }) })
      });
      mockPatientDoc.collection.withArgs('blood_cancer_ehrs').returns({
        doc: sinon.stub().returns({ get: sinon.stub().resolves({ exists: false }) })
      });
      mockPatientDoc.collection.withArgs('diagnoses').returns(mockSubcollection);

      mockFirestore.collection.withArgs('medical_records').returns({
        doc: sinon.stub().returns({ get: sinon.stub().resolves({ exists: false }) })
      });
      mockFirestore.collection.withArgs('patients').returns({
        doc: sinon.stub().withArgs('pat-alpha').returns(mockPatientDoc)
      });
      mockFirestore.collectionGroup.returns({
        where: sinon.stub().returns({ get: sinon.stub().resolves({ empty: true }) })
      });

      const result = await firebaseAdmin.getMedicalRecord('diag-alpha-001', 'pat-alpha');

      expect(result).to.not.be.null;
      expect(result.id).to.equal('diag-alpha-001');
      expect(result.documentType).to.equal('DIAGNOSIS');
      expect(result.isDiagnosis).to.be.true;
      expect(result.diagnosisTitle).to.equal('Confirmed B-Cell ALL');
    });

    it('6. should reject cross-patient collision when document patientId differs from expectedPatientId', async () => {
      const hostileData = {
        patientId: 'victim-patient',
        diagnosisTitle: 'Confidential Biopsy Report'
      };

      const mockDoc = {
        id: 'diag-hostile-001',
        exists: true,
        data: () => hostileData
      };

      const mockPatientDoc = {
        collection: sinon.stub()
      };
      mockPatientDoc.collection.withArgs('medicalRecords').returns({
        doc: sinon.stub().returns({ get: sinon.stub().resolves({ exists: false }) })
      });
      mockPatientDoc.collection.withArgs('clinical_notes').returns({
        doc: sinon.stub().returns({ get: sinon.stub().resolves({ exists: false }) })
      });
      mockPatientDoc.collection.withArgs('blood_cancer_ehrs').returns({
        doc: sinon.stub().returns({ get: sinon.stub().resolves({ exists: false }) })
      });
      mockPatientDoc.collection.withArgs('diagnoses').returns({
        doc: sinon.stub().withArgs('diag-hostile-001').returns({
          get: sinon.stub().resolves(mockDoc)
        })
      });

      mockFirestore.collection.withArgs('medical_records').returns({
        doc: sinon.stub().returns({ get: sinon.stub().resolves({ exists: false }) })
      });
      mockFirestore.collection.withArgs('patients').returns({
        doc: sinon.stub().withArgs('attacker-patient').returns(mockPatientDoc)
      });
      mockFirestore.collectionGroup.returns({
        where: sinon.stub().returns({ get: sinon.stub().resolves({ empty: true }) })
      });

      try {
        await firebaseAdmin.getMedicalRecord('diag-hostile-001', 'attacker-patient');
        expect.fail('Should have rejected mismatched patient ID');
      } catch (err: any) {
        expect(err.message).to.include('Access Denied');
      }
    });

    it('7. should return null safely when record does not exist in any collection', async () => {
      const mockPatientDoc = {
        collection: sinon.stub().returns({
          doc: sinon.stub().returns({ get: sinon.stub().resolves({ exists: false }) })
        })
      };

      mockFirestore.collection.withArgs('medical_records').returns({
        doc: sinon.stub().returns({ get: sinon.stub().resolves({ exists: false }) })
      });
      mockFirestore.collection.withArgs('patients').returns({
        doc: sinon.stub().returns(mockPatientDoc)
      });
      mockFirestore.collectionGroup.returns({
        where: sinon.stub().returns({ get: sinon.stub().resolves({ empty: true }) })
      });

      const result = await firebaseAdmin.getMedicalRecord('nonexistent-id', 'pat-alpha');
      expect(result).to.be.null;
    });
  });

  describe('Task 3: Safe Proof Synchronization (updateRecordProof)', () => {
    it('8. should update blood_cancer_ehrs with proof fields without modifying clinical fields', async () => {
      const existingEhr = {
        patientId: 'pat-alpha',
        diseaseType: 'Acute Myeloid Leukemia',
        blastCellPercentage: 25.5
      };

      const setStub = sinon.stub().resolves();
      const mockEhrRef = {
        get: sinon.stub().resolves({ exists: true, data: () => existingEhr }),
        set: setStub
      };

      const mockPatientDoc = {
        collection: sinon.stub()
      };
      mockPatientDoc.collection.withArgs('medicalRecords').returns({
        doc: sinon.stub().returns({ get: sinon.stub().resolves({ exists: false }) })
      });
      mockPatientDoc.collection.withArgs('clinical_notes').returns({
        doc: sinon.stub().returns({ get: sinon.stub().resolves({ exists: false }) })
      });
      mockPatientDoc.collection.withArgs('blood_cancer_ehrs').returns({
        doc: sinon.stub().withArgs('ehr-001').returns(mockEhrRef)
      });
      mockPatientDoc.collection.withArgs('diagnoses').returns({
        doc: sinon.stub().returns({ get: sinon.stub().resolves({ exists: false }) })
      });

      mockFirestore.collection.withArgs('medical_records').returns({
        doc: sinon.stub().returns({ get: sinon.stub().resolves({ exists: false }) })
      });
      mockFirestore.collection.withArgs('patients').returns({
        doc: sinon.stub().withArgs('pat-alpha').returns(mockPatientDoc)
      });

      const proofData = {
        txId: 'tx-fabric-commit-101',
        fileHash: 'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789',
        version: 1,
        timestamp: '2026-10-21T00:00:00.000Z',
        opaqueRecordKey: 'opaque_rec_key_101'
      };

      await firebaseAdmin.updateRecordProof('ehr-001', proofData, 'pat-alpha');

      expect(setStub.calledOnce).to.be.true;
      const [updatePayload, options] = setStub.firstCall.args;
      expect(options).to.deep.equal({ merge: true });
      expect(updatePayload.fabricStatus).to.equal('COMMITTED');
      expect(updatePayload.fabricTxId).to.equal('tx-fabric-commit-101');
      expect(updatePayload.storedHash).to.equal(proofData.fileHash);
      expect(updatePayload.blockchainTxId).to.equal('tx-fabric-commit-101');
      // Assert clinical fields are NOT in the update payload
      expect(updatePayload.diseaseType).to.be.undefined;
      expect(updatePayload.blastCellPercentage).to.be.undefined;
    });

    it('9. should update diagnoses proof in patient subcollection and synchronize doctor mirror copy', async () => {
      const existingDiag = {
        patientId: 'pat-alpha',
        doctorId: 'doc-oncologist',
        diagnosisTitle: 'ALL Remission Phase'
      };

      const patientDiagSetStub = sinon.stub().resolves();
      const doctorDiagSetStub = sinon.stub().resolves();

      const mockPatientDiagRef = {
        get: sinon.stub().resolves({ exists: true, data: () => existingDiag }),
        set: patientDiagSetStub
      };

      const mockDoctorDiagRef = {
        get: sinon.stub().resolves({ exists: true }),
        set: doctorDiagSetStub
      };

      const mockPatientDoc = {
        collection: sinon.stub()
      };
      mockPatientDoc.collection.withArgs('medicalRecords').returns({
        doc: sinon.stub().returns({ get: sinon.stub().resolves({ exists: false }) })
      });
      mockPatientDoc.collection.withArgs('clinical_notes').returns({
        doc: sinon.stub().returns({ get: sinon.stub().resolves({ exists: false }) })
      });
      mockPatientDoc.collection.withArgs('blood_cancer_ehrs').returns({
        doc: sinon.stub().returns({ get: sinon.stub().resolves({ exists: false }) })
      });
      mockPatientDoc.collection.withArgs('diagnoses').returns({
        doc: sinon.stub().withArgs('diag-001').returns(mockPatientDiagRef)
      });

      mockFirestore.collection.withArgs('medical_records').returns({
        doc: sinon.stub().returns({ get: sinon.stub().resolves({ exists: false }) })
      });
      mockFirestore.collection.withArgs('patients').returns({
        doc: sinon.stub().withArgs('pat-alpha').returns(mockPatientDoc)
      });
      mockFirestore.collection.withArgs('doctors').returns({
        doc: sinon.stub().withArgs('doc-oncologist').returns({
          collection: sinon.stub().withArgs('diagnoses').returns({
            doc: sinon.stub().withArgs('diag-001').returns(mockDoctorDiagRef)
          })
        })
      });

      const proofData = {
        txId: 'tx-diag-anchor-202',
        fileHash: '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
        version: 1,
        timestamp: '2026-10-21T01:00:00.000Z',
        opaqueRecordKey: 'opaque_diag_key_202'
      };

      await firebaseAdmin.updateRecordProof('diag-001', proofData, 'pat-alpha');

      expect(patientDiagSetStub.calledOnce).to.be.true;
      expect(patientDiagSetStub.firstCall.args[0].fabricTxId).to.equal('tx-diag-anchor-202');
      expect(doctorDiagSetStub.calledOnce).to.be.true;
      expect(doctorDiagSetStub.firstCall.args[0].fabricTxId).to.equal('tx-diag-anchor-202');
    });
  });

  describe('Task 4: Gateway Authorization Checks', () => {
    it('10. should reject patient attempting to verify another patient record (Anti-IDOR)', async () => {
      const record = {
        id: 'ehr-alpha-001',
        patientId: 'pat-alpha'
      };

      sinon.stub(firebaseAdmin, 'getMedicalRecord').resolves(record);

      try {
        await recordService.verifyRecord(PATIENT_B, 'ehr-alpha-001');
        expect.fail('Should have thrown access denied for cross-patient access');
      } catch (err: any) {
        expect(err.message).to.include('Patients may only access their own medical records');
      }
    });

    it('11. should reject unassigned nurse attempting to anchor or verify patient record', async () => {
      const record = {
        id: 'ehr-alpha-001',
        patientId: 'pat-alpha'
      };

      sinon.stub(firebaseAdmin, 'getMedicalRecord').resolves(record);
      sinon.stub(firebaseAdmin, 'checkActiveNurseAssignment').resolves(false);

      try {
        await recordService.verifyRecord(UNASSIGNED_NURSE, 'ehr-alpha-001', undefined, 'pat-alpha');
        expect.fail('Should have rejected unassigned nurse');
      } catch (err: any) {
        expect(err.message).to.include('Nurse does not hold active assignment');
      }
    });

    it('12. should reject doctor attempting to access patient record without active consent', async () => {
      const record = {
        id: 'ehr-alpha-001',
        patientId: 'pat-alpha'
      };

      sinon.stub(firebaseAdmin, 'getMedicalRecord').resolves(record);
      mockFabricGateway.evaluateTransaction.withArgs('CheckConsent').rejects(new Error('CONSENT_NOT_FOUND'));
      sinon.stub(firebaseAdmin, 'checkDoctorPatientConsent').resolves(false);

      try {
        await recordService.verifyRecord(DOCTOR, 'ehr-alpha-001', undefined, 'pat-alpha');
        expect.fail('Should have rejected doctor without consent');
      } catch (err: any) {
        expect(err.message).to.include('Clinician does not hold active patient consent');
      }
    });
  });
});
