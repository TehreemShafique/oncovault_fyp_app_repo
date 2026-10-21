// src/services/firebaseAdmin.ts
import * as admin from 'firebase-admin';
import * as fs from 'fs';
import { config } from '../config/env';
import { AuthenticatedUser } from '../types';

export class FirebaseAdminService {
  private static instance: FirebaseAdminService | null = null;
  private app: admin.app.App | null = null;
  private auth: admin.auth.Auth | null = null;
  private firestore: admin.firestore.Firestore | null = null;
  private storage: admin.storage.Storage | null = null;
  private configured: boolean = false;

  private constructor() {
    this.initialize();
  }

  public static getInstance(): FirebaseAdminService {
    if (!FirebaseAdminService.instance) {
      FirebaseAdminService.instance = new FirebaseAdminService();
    }
    return FirebaseAdminService.instance;
  }

  public static resetInstance(): void {
    FirebaseAdminService.instance = null;
  }

  private initialize(): void {
    if (admin.apps.length > 0) {
      this.app = admin.apps[0]!;
      this.auth = admin.auth(this.app);
      this.firestore = admin.firestore(this.app);
      this.storage = admin.storage(this.app);
      this.configured = true;
      return;
    }

    try {
      const { projectId, storageBucket, serviceAccountPath } = config.firebase;

      if (serviceAccountPath && fs.existsSync(serviceAccountPath)) {
        const serviceAccount = JSON.parse(fs.readFileSync(serviceAccountPath, 'utf8'));
        this.app = admin.initializeApp({
          credential: admin.credential.cert(serviceAccount),
          projectId: serviceAccount.project_id || projectId,
          storageBucket
        });
      } else if (process.env.FIREBASE_AUTH_EMULATOR_HOST || process.env.FIRESTORE_EMULATOR_HOST) {
        this.app = admin.initializeApp({
          projectId,
          storageBucket
        });
      } else {
        // Safe check: do not invent credentials.
        // Attempt Application Default Credentials (ADC) from environment or standard credential stores
        try {
          this.app = admin.initializeApp({
            credential: admin.credential.applicationDefault(),
            projectId,
            storageBucket
          });
        } catch {
          // If no ADC available, attempt project-only init (for token verification against public keys)
          try {
            this.app = admin.initializeApp({
              projectId,
              storageBucket
            });
          } catch {
            this.configured = false;
            return;
          }
        }
      }

      this.auth = admin.auth(this.app);
      this.firestore = admin.firestore(this.app);
      this.storage = admin.storage(this.app);
      this.configured = true;
    } catch (err: any) {
      this.configured = false;
    }
  }

  public isConfigured(): boolean {
    return this.configured && this.app !== null;
  }

  /**
   * For unit testing: allows injecting custom Auth, Firestore and Storage mocks.
   */
  public setMockInstances(mockAuth: any, mockFirestore: any, mockStorage: any): void {
    this.auth = mockAuth;
    this.firestore = mockFirestore;
    this.storage = mockStorage;
    this.configured = true;
  }

  public async verifyIdToken(idToken: string): Promise<admin.auth.DecodedIdToken> {
    if (!this.auth) {
      throw new Error('Firebase Auth is not configured. Service account or emulator required.');
    }
    return await this.auth.verifyIdToken(idToken, true);
  }

  /**
   * Looks up authoritative user document in Firestore `users/{uid}`.
   * Never trusts client-reported roles.
   */
  public async getAuthoritativeUser(uid: string): Promise<AuthenticatedUser | null> {
    if (!this.firestore) {
      throw new Error('Firestore is not configured.');
    }
    const doc = await this.firestore.collection('users').doc(uid).get();
    if (!doc.exists) {
      return null;
    }
    const data = doc.data() as any;
    return {
      uid,
      email: data.email,
      name: data.name,
      role: (data.role || 'patient').toLowerCase(),
      medicalId: data.medicalId
    };
  }

  public getFirestoreInstance(): admin.firestore.Firestore | null {
    return this.firestore;
  }

  public getAuthInstance(): admin.auth.Auth | null {
    return this.auth;
  }

  public getStorageInstance(): admin.storage.Storage | null {
    return this.storage;
  }

  /**
   * Looks up authoritative medical record in Firestore `medical_records/{recordId}`
   * or patient subcollection `patients/{patientId}/medicalRecords/{recordId}`.
   * Strictly enforces patient ownership and rejects ambiguous/conflicting matches.
   */
  public async getMedicalRecord(recordId: string, expectedPatientId?: string): Promise<any | null> {
    if (!this.firestore) {
      throw new Error('Firestore is not configured.');
    }

    let globalRecord: any = null;
    let patientRecord: any = null;

    // 1. Check global `medical_records` collection
    const globalDoc = await this.firestore.collection('medical_records').doc(recordId).get();
    if (globalDoc.exists) {
      globalRecord = { id: globalDoc.id, ...globalDoc.data() };
    }

    // 2. Check patient-specific subcollection if patientId provided
    if (expectedPatientId) {
      const patientDoc = await this.firestore
        .collection('patients')
        .doc(expectedPatientId)
        .collection('medicalRecords')
        .doc(recordId)
        .get();
      if (patientDoc.exists) {
        patientRecord = { id: patientDoc.id, ...patientDoc.data() };
      }
    }

    // 3. Ambiguity & Conflict Validation
    if (globalRecord && patientRecord) {
      if (globalRecord.patientId && patientRecord.patientId && globalRecord.patientId !== patientRecord.patientId) {
        throw new Error(
          `Conflict: Ambiguous record documents for ID '${recordId}'. Global record patient (${globalRecord.patientId}) differs from patient subcollection (${patientRecord.patientId}).`
        );
      }
      return globalRecord;
    }

    if (globalRecord) {
      if (expectedPatientId && globalRecord.patientId && globalRecord.patientId !== expectedPatientId) {
        throw new Error(
          `Access Denied: Record '${recordId}' belongs to patient '${globalRecord.patientId}', not expected patient '${expectedPatientId}'.`
        );
      }
      return globalRecord;
    }

    if (patientRecord) {
      return patientRecord;
    }

    // 4. Fallback: query collectionGroup `medicalRecords`
    try {
      const cgSnap = await this.firestore
        .collectionGroup('medicalRecords')
        .where('id', '==', recordId)
        .get();

      if (!cgSnap.empty) {
        const patientIds = new Set(cgSnap.docs.map(d => (d.data() as any).patientId));
        if (patientIds.size > 1) {
          throw new Error(
            `Conflict: Ambiguous record ID '${recordId}' found across multiple patients: ${Array.from(patientIds).join(', ')}`
          );
        }
        const doc = cgSnap.docs[0];
        const data: any = { id: doc.id, ...(doc.data() as any) };
        if (expectedPatientId && data.patientId && data.patientId !== expectedPatientId) {
          throw new Error(
            `Access Denied: Record '${recordId}' belongs to patient '${data.patientId}', not expected patient '${expectedPatientId}'.`
          );
        }
        return data;
      }
    } catch (err: any) {
      if (err.message && (err.message.includes('Conflict') || err.message.includes('Access Denied'))) {
        throw err;
      }
    }

    // 5. Check patient clinical_notes subcollection if expectedPatientId provided
    if (expectedPatientId) {
      const noteDoc = await this.firestore
        .collection('patients')
        .doc(expectedPatientId)
        .collection('clinical_notes')
        .doc(recordId)
        .get();
      if (noteDoc.exists) {
        return { id: noteDoc.id, isClinicalNote: true, documentType: 'CLINICAL_NOTE', ...noteDoc.data() };
      }
    }

    // 6. Check patient blood_cancer_ehrs subcollection if expectedPatientId provided
    if (expectedPatientId) {
      const ehrDoc = await this.firestore
        .collection('patients')
        .doc(expectedPatientId)
        .collection('blood_cancer_ehrs')
        .doc(recordId)
        .get();
      if (ehrDoc.exists) {
        const ehrData = ehrDoc.data() as any;
        if (ehrData && ehrData.patientId && ehrData.patientId !== expectedPatientId) {
          throw new Error(
            `Access Denied: Blood Cancer EHR '${recordId}' belongs to patient '${ehrData.patientId}', not expected patient '${expectedPatientId}'.`
          );
        }
        return {
          id: ehrDoc.id,
          patientId: expectedPatientId,
          documentType: 'BLOOD_CANCER_EHR',
          isBloodCancerEhr: true,
          ...ehrData
        };
      }
    }

    // 7. Check patient diagnoses subcollection if expectedPatientId provided
    if (expectedPatientId) {
      const diagDoc = await this.firestore
        .collection('patients')
        .doc(expectedPatientId)
        .collection('diagnoses')
        .doc(recordId)
        .get();
      if (diagDoc.exists) {
        const diagData = diagDoc.data() as any;
        if (diagData && diagData.patientId && diagData.patientId !== expectedPatientId) {
          throw new Error(
            `Access Denied: Diagnosis '${recordId}' belongs to patient '${diagData.patientId}', not expected patient '${expectedPatientId}'.`
          );
        }
        return {
          id: diagDoc.id,
          patientId: expectedPatientId,
          documentType: 'DIAGNOSIS',
          isDiagnosis: true,
          ...diagData
        };
      }
    }

    // 8. Fallback for blood_cancer_ehrs if expectedPatientId not provided
    if (!expectedPatientId) {
      try {
        const ehrCgSnap = await this.firestore
          .collectionGroup('blood_cancer_ehrs')
          .where('recordId', '==', recordId)
          .get();
        if (!ehrCgSnap.empty) {
          const doc = ehrCgSnap.docs[0];
          const data = doc.data() as any;
          const pid = doc.ref.parent.parent?.id || data.patientId;
          return {
            id: doc.id,
            patientId: pid,
            documentType: 'BLOOD_CANCER_EHR',
            isBloodCancerEhr: true,
            ...data
          };
        }
      } catch (_) {}
    }

    return null;
  }

  /**
   * Checks whether a nurse holds an active assignment for a patient in `nurse_patient_assignments`.
   */
  public async checkActiveNurseAssignment(nurseId: string, patientId: string): Promise<boolean> {
    if (!this.firestore) {
      throw new Error('Firestore is not configured.');
    }
    const docId = `${nurseId}_${patientId}`;
    const directDoc = await this.firestore.collection('nurse_patient_assignments').doc(docId).get();
    if (directDoc.exists) {
      const data = directDoc.data() as any;
      if (data && data.status === 'active') {
        return true;
      }
    }
    return false;
  }

  /**
   * Checks whether a clinician holds an active grant for a patient in `doctor_patient_consents`.
   */
  public async checkDoctorPatientConsent(doctorId: string, patientId: string): Promise<boolean> {
    if (!this.firestore) {
      throw new Error('Firestore is not configured.');
    }
    // Check specific document ${patientId}_${doctorId}
    const docId = `${patientId}_${doctorId}`;
    const directDoc = await this.firestore.collection('doctor_patient_consents').doc(docId).get();
    if (directDoc.exists) {
      const data = directDoc.data() as any;
      if (data && data.status === 'granted') {
        return true;
      }
    }

    // Query collection where doctorId and patientId match with status granted
    const snap = await this.firestore
      .collection('doctor_patient_consents')
      .where('doctorId', '==', doctorId)
      .where('patientId', '==', patientId)
      .where('status', '==', 'granted')
      .limit(1)
      .get();

    return !snap.empty;
  }

  /**
   * Downloads exact binary file buffer from Firebase Storage using verified storage path.
   */
  public async getFileBytes(storagePathOrUrl: string): Promise<Buffer> {
    if (!this.storage) {
      throw new Error('Firebase Storage is not configured.');
    }

    const bucketName = config.firebase.storageBucket;
    const bucket = this.storage.bucket(bucketName);

    // If a full storage URL is passed, extract object path
    let objectPath = storagePathOrUrl;
    if (storagePathOrUrl.startsWith('gs://')) {
      objectPath = storagePathOrUrl.replace(/^gs:\/\/[^/]+\//, '');
    } else if (storagePathOrUrl.includes('firebasestorage.googleapis.com')) {
      const match = storagePathOrUrl.match(/\/o\/([^?]+)/);
      if (match && match[1]) {
        objectPath = decodeURIComponent(match[1]);
      }
    }

    const file = bucket.file(objectPath);
    const [exists] = await file.exists();
    if (!exists) {
      throw new Error(`File not found in storage bucket at path: ${objectPath}`);
    }

    const [buffer] = await file.download();
    return buffer;
  }

  /**
   * Updates medical record in Firestore with genuine Fabric proof metadata.
   */
  public async updateRecordProof(
    recordId: string,
    proofData: {
      txId: string;
      fileHash: string;
      version: number;
      timestamp: string;
      opaqueRecordKey: string;
    },
    patientId?: string
  ): Promise<void> {
    if (!this.firestore) {
      throw new Error('Firestore is not configured.');
    }
    const updatePayload = {
      fileHash: proofData.fileHash,
      fabricStatus: 'COMMITTED',
      fabricTxId: proofData.txId,
      fabricVersion: proofData.version,
      fabricTimestamp: proofData.timestamp,
      opaqueRecordKey: proofData.opaqueRecordKey,
      lastAnchoredAt: admin.firestore.FieldValue.serverTimestamp()
    };

    // Update global collection only if the document exists and belongs to verified patient
    const globalRef = this.firestore.collection('medical_records').doc(recordId);
    const globalSnap = await globalRef.get();
    if (globalSnap.exists) {
      const gData = globalSnap.data() as any;
      if (!patientId || !gData.patientId || gData.patientId === patientId) {
        await globalRef.set(updatePayload, { merge: true });
      }
    }

    // Also update patient subcollection if patientId is known
    if (patientId) {
      try {
        const patientRef = this.firestore
          .collection('patients')
          .doc(patientId)
          .collection('medicalRecords')
          .doc(recordId);
        const pSnap = await patientRef.get();
        if (pSnap.exists) {
          await patientRef.set(updatePayload, { merge: true });
        }
      } catch (_) {
        // Non-blocking if subcollection does not exist
      }

      try {
        const noteRef = this.firestore
          .collection('patients')
          .doc(patientId)
          .collection('clinical_notes')
          .doc(recordId);
        const nSnap = await noteRef.get();
        if (nSnap.exists) {
          await noteRef.set(updatePayload, { merge: true });
        }
      } catch (_) {
        // Non-blocking if clinical_notes subcollection does not exist
      }

      try {
        const ehrRef = this.firestore
          .collection('patients')
          .doc(patientId)
          .collection('blood_cancer_ehrs')
          .doc(recordId);
        const eSnap = await ehrRef.get();
        if (eSnap.exists) {
          const ehrPayload = {
            ...updatePayload,
            storedHash: proofData.fileHash,
            blockchainTxId: proofData.txId
          };
          await ehrRef.set(ehrPayload, { merge: true });
        }
      } catch (_) {
        // Non-blocking if blood_cancer_ehrs subcollection does not exist
      }

      try {
        const diagRef = this.firestore
          .collection('patients')
          .doc(patientId)
          .collection('diagnoses')
          .doc(recordId);
        const dSnap = await diagRef.get();
        if (dSnap.exists) {
          await diagRef.set(updatePayload, { merge: true });
          const dData = dSnap.data() as any;
          if (dData && dData.doctorId) {
            try {
              const docDiagRef = this.firestore
                .collection('doctors')
                .doc(dData.doctorId)
                .collection('diagnoses')
                .doc(recordId);
              const docSnap = await docDiagRef.get();
              if (docSnap.exists) {
                await docDiagRef.set(updatePayload, { merge: true });
              }
            } catch (_) {}
          }
        }
      } catch (_) {
        // Non-blocking if diagnoses subcollection does not exist
      }
    }
  }

  public checkReadiness(): { configured: boolean; projectId: string; error?: string } {
    return {
      configured: this.isConfigured(),
      projectId: config.firebase.projectId,
      ...(!this.isConfigured() ? { error: 'Missing service account credentials or emulator configuration' } : {})
    };
  }
}
