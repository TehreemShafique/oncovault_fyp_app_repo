// functions/src/record_clinical_note.ts
import * as admin from 'firebase-admin';
import * as functions from 'firebase-functions';
import { HttpsError } from 'firebase-functions/v1/https';
import * as crypto from 'crypto';
import { verifyDoctorCareAuthorization } from './assign_nurse';

export interface ClinicalNotePayload {
  noteId?: string;
  patientId: string;
  noteType: 'intake_note' | 'progress_note' | 'shift_summary';
  rawTranscription?: string;
  nurseReviewedTranscript?: string;
  clinicalSummary?: string;
  supportedExtractedSymptoms?: Record<string, any>;
  narrativeObservations?: string;
  careInterventions?: string;
  treatmentResponseNarrative?: string;
  amendmentOf?: string;
  amendmentReason?: string;
}

export interface ReviewClinicalNotePayload {
  patientId: string;
  noteId: string;
  reviewNotes?: string;
}

export function computeCanonicalNoteHash(note: {
  noteId: string;
  patientId: string;
  noteType: string;
  authorUid: string;
  clinicalSummary?: string;
  nurseReviewedTranscript?: string;
  narrativeObservations?: string;
  careInterventions?: string;
  treatmentResponseNarrative?: string;
  supportedExtractedSymptoms?: Record<string, any>;
  amendmentOf?: string;
  amendmentReason?: string;
  createdAtIso: string;
}): string {
  const canonicalObject = {
    noteId: note.noteId,
    patientId: note.patientId,
    noteType: note.noteType,
    authorUid: note.authorUid,
    clinicalSummary: (note.clinicalSummary || '').trim(),
    nurseReviewedTranscript: (note.nurseReviewedTranscript || '').trim(),
    narrativeObservations: (note.narrativeObservations || '').trim(),
    careInterventions: (note.careInterventions || '').trim(),
    treatmentResponseNarrative: (note.treatmentResponseNarrative || '').trim(),
    supportedExtractedSymptoms: note.supportedExtractedSymptoms || {},
    amendmentOf: note.amendmentOf || '',
    amendmentReason: (note.amendmentReason || '').trim(),
    createdAtIso: note.createdAtIso,
  };
  const serialized = JSON.stringify(canonicalObject, Object.keys(canonicalObject).sort());
  return crypto.createHash('sha256').update(serialized, 'utf8').digest('hex').toLowerCase();
}

/**
 * Validates clinical authorization for recording or reviewing nursing notes.
 * Enforces role, hospital isolation, active assignment, and consent.
 */
async function authorizeClinicianForPatient(
  db: admin.firestore.Firestore,
  callerUid: string,
  patientId: string,
  requiredAction: 'write' | 'review'
): Promise<{ userRole: string; clinicianName: string; hospitalId: string }> {
  const userDoc = await db.collection('users').doc(callerUid).get();
  if (!userDoc.exists) {
    throw new HttpsError('permission-denied', 'User record not found.');
  }

  const userData = userDoc.data() || {};
  const userRole = (userData.role || '').toLowerCase();
  const clinicianName =
    userData.name ||
    (userRole === 'doctor'
      ? 'Attending Physician'
      : userRole === 'admin'
      ? 'Administrator'
      : 'Staff Nurse');
  const userHospital = userData.hospitalId || 'Oncology Ward 3A';

  // Verify patient existence and hospital scope
  const patientDoc = await db.collection('patients').doc(patientId).get();
  if (!patientDoc.exists) {
    throw new HttpsError('not-found', `Patient ${patientId} does not exist.`);
  }
  const patientData = patientDoc.data() || {};
  const patientHospital = patientData.hospitalId || 'Oncology Ward 3A';

  if (userRole !== 'admin' && userHospital !== patientHospital) {
    throw new HttpsError(
      'permission-denied',
      `Hospital boundary violation: Clinician (${userHospital}) cannot access patient in (${patientHospital}).`
    );
  }

  if (requiredAction === 'write') {
    if (userRole === 'nurse' || userRole === 'house_officer') {
      const assignmentId = `${callerUid}_${patientId}`;
      const assignDoc = await db.collection('nurse_patient_assignments').doc(assignmentId).get();
      if (!assignDoc.exists || assignDoc.data()?.status !== 'active') {
        throw new HttpsError(
          'permission-denied',
          `Nurse is not actively assigned to patient ${patientId}. Note creation denied.`
        );
      }
    } else if (userRole === 'doctor') {
      await verifyDoctorCareAuthorization(db, callerUid, patientId);
    } else if (userRole !== 'admin') {
      throw new HttpsError(
        'permission-denied',
        'Only authorized nurses, house officers, or doctors can author clinical notes.'
      );
    }
  } else if (requiredAction === 'review') {
    if (userRole !== 'doctor' && userRole !== 'admin') {
      throw new HttpsError(
        'permission-denied',
        'Only treating physicians or hospital administrators may review and sign off clinical notes.'
      );
    }
    if (userRole === 'doctor') {
      await verifyDoctorCareAuthorization(db, callerUid, patientId);
    }
  }

  return { userRole, clinicianName, hospitalId: userHospital };
}

/**
 * Handler for saving or updating an unconfirmed DRAFT clinical note.
 */
export async function saveClinicalNoteDraftHandler(
  request: { auth?: { uid: string }; data: any },
  firestoreInstance?: admin.firestore.Firestore
): Promise<{ success: boolean; noteId: string; status: string }> {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError('unauthenticated', 'User must be authenticated.');
  }

  const callerUid = request.auth.uid;
  const db = firestoreInstance || admin.firestore();
  const payload = request.data as ClinicalNotePayload;

  if (!payload.patientId || typeof payload.patientId !== 'string') {
    throw new HttpsError('invalid-argument', 'Valid patientId is required.');
  }

  const { userRole, clinicianName, hospitalId } = await authorizeClinicianForPatient(
    db,
    callerUid,
    payload.patientId,
    'write'
  );

  const noteRef = payload.noteId?.trim()
    ? db.collection('patients').doc(payload.patientId).collection('clinical_notes').doc(payload.noteId.trim())
    : db.collection('patients').doc(payload.patientId).collection('clinical_notes').doc();

  const noteId = noteRef.id;

  await db.runTransaction(async (t) => {
    const existingSnap = await t.get(noteRef);
    if (existingSnap.exists) {
      const existingData = existingSnap.data() || {};
      if (existingData.authorUid !== callerUid && userRole !== 'admin') {
        throw new HttpsError('permission-denied', 'Cannot modify a draft authored by another clinician.');
      }
      if (existingData.status !== 'DRAFT') {
        throw new HttpsError(
          'failed-precondition',
          `Cannot modify note in status '${existingData.status}'. Only drafts are editable.`
        );
      }
    }

    const serverNow = admin.firestore.FieldValue.serverTimestamp();
    const draftData: Record<string, any> = {
      noteId,
      patientId: payload.patientId,
      noteType: payload.noteType || 'progress_note',
      authorUid: callerUid,
      authorName: clinicianName,
      authorRole: userRole,
      hospitalId,
      rawTranscription: payload.rawTranscription || '',
      nurseReviewedTranscript: payload.nurseReviewedTranscript || '',
      clinicalSummary: payload.clinicalSummary || '',
      supportedExtractedSymptoms: payload.supportedExtractedSymptoms || {},
      narrativeObservations: payload.narrativeObservations || '',
      careInterventions: payload.careInterventions || '',
      treatmentResponseNarrative: payload.treatmentResponseNarrative || '',
      status: 'DRAFT',
      updatedAt: serverNow,
    };

    if (!existingSnap.exists) {
      draftData.createdAt = serverNow;
      draftData.isAmended = false;
      draftData.fabricStatus = 'NOT_ANCHORED';
      if (payload.amendmentOf) {
        draftData.amendmentOf = payload.amendmentOf;
      }
    }

    t.set(noteRef, draftData, { merge: true });
  });

  return { success: true, noteId, status: 'DRAFT' };
}

/**
 * Handler for explicitly confirming and SUBMITTING a finalized clinical note.
 * Computes canonical hash, makes content immutable, and links amendments atomically.
 */
export async function submitClinicalNoteHandler(
  request: { auth?: { uid: string }; data: any },
  firestoreInstance?: admin.firestore.Firestore
): Promise<{ success: boolean; noteId: string; status: string; fileHash: string }> {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError('unauthenticated', 'User must be authenticated.');
  }

  const callerUid = request.auth.uid;
  const db = firestoreInstance || admin.firestore();
  const payload = request.data as ClinicalNotePayload;

  if (!payload.patientId || typeof payload.patientId !== 'string') {
    throw new HttpsError('invalid-argument', 'Valid patientId is required.');
  }

  const { userRole, clinicianName, hospitalId } = await authorizeClinicianForPatient(
    db,
    callerUid,
    payload.patientId,
    'write'
  );

  const noteRef = payload.noteId?.trim()
    ? db.collection('patients').doc(payload.patientId).collection('clinical_notes').doc(payload.noteId.trim())
    : db.collection('patients').doc(payload.patientId).collection('clinical_notes').doc();

  const noteId = noteRef.id;
  const now = new Date();
  let fileHash = '';

  await db.runTransaction(async (t) => {
    const existingSnap = await t.get(noteRef);
    const existingData = existingSnap.exists ? existingSnap.data() || {} : null;

    let createdAtIso = now.toISOString();
    if (existingData?.createdAtIso) {
      createdAtIso = existingData.createdAtIso;
    } else if (existingData?.createdAt && typeof existingData.createdAt.toDate === 'function') {
      createdAtIso = existingData.createdAt.toDate().toISOString();
    }

    // Compute canonical SHA-256 hash
    fileHash = computeCanonicalNoteHash({
      noteId,
      patientId: payload.patientId,
      noteType: payload.noteType || 'progress_note',
      authorUid: callerUid,
      clinicalSummary: payload.clinicalSummary,
      nurseReviewedTranscript: payload.nurseReviewedTranscript,
      narrativeObservations: payload.narrativeObservations,
      careInterventions: payload.careInterventions,
      treatmentResponseNarrative: payload.treatmentResponseNarrative,
      supportedExtractedSymptoms: payload.supportedExtractedSymptoms,
      amendmentOf: payload.amendmentOf,
      amendmentReason: payload.amendmentReason,
      createdAtIso,
    });

    if (existingData) {
      if (existingData.authorUid !== callerUid && userRole !== 'admin') {
        throw new HttpsError('permission-denied', 'Cannot submit note authored by another clinician.');
      }
      if (existingData.status === 'SUBMITTED' || existingData.status === 'REVIEWED') {
        // Idempotent retry: if payload and fileHash match identically, succeed gracefully
        if (existingData.fileHash === fileHash) {
          return;
        }
        throw new HttpsError(
          'failed-precondition',
          `Note '${noteId}' is already finalized in status '${existingData.status}'. Use amendment instead.`
        );
      }
    }

    // If this note is an amendment, verify and mark the original note
    if (payload.amendmentOf) {
      if (payload.amendmentOf === noteId) {
        throw new HttpsError('invalid-argument', 'A clinical note cannot amend itself.');
      }
      if (!payload.amendmentReason || !payload.amendmentReason.trim()) {
        throw new HttpsError(
          'invalid-argument',
          'An explicit amendmentReason is required when amending a clinical note.'
        );
      }
      const originalRef = db
        .collection('patients')
        .doc(payload.patientId)
        .collection('clinical_notes')
        .doc(payload.amendmentOf);
      const origSnap = await t.get(originalRef);
      if (!origSnap.exists) {
        throw new HttpsError(
          'not-found',
          `Original note '${payload.amendmentOf}' for amendment does not exist.`
        );
      }
      const origData = origSnap.data() || {};
      if (origData.status === 'DRAFT') {
        throw new HttpsError(
          'failed-precondition',
          'Cannot amend a draft note. Finalize the original note first.'
        );
      }
      if (origData.isAmended) {
        throw new HttpsError(
          'failed-precondition',
          `Original note '${payload.amendmentOf}' is already amended by note '${origData.amendedByNoteId}'. Amend the latest note version.`
        );
      }
      if (origData.patientId !== payload.patientId) {
        throw new HttpsError(
          'invalid-argument',
          `Amendment patient mismatch: original note patient '${origData.patientId}' does not match '${payload.patientId}'.`
        );
      }
      if (origData.authorUid !== callerUid && userRole !== 'admin') {
        throw new HttpsError(
          'permission-denied',
          'Cannot amend a clinical note authored by another clinician.'
        );
      }
      // Update original note to mark it as amended, preserving its full content
      t.update(originalRef, {
        isAmended: true,
        amendedByNoteId: noteId,
        amendedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    const serverNow = admin.firestore.FieldValue.serverTimestamp();
    const finalData = {
      noteId,
      patientId: payload.patientId,
      noteType: payload.noteType || 'progress_note',
      authorUid: callerUid,
      authorName: clinicianName,
      authorRole: userRole,
      hospitalId,
      rawTranscription: payload.rawTranscription || '',
      nurseReviewedTranscript: payload.nurseReviewedTranscript || '',
      clinicalSummary: payload.clinicalSummary || '',
      supportedExtractedSymptoms: payload.supportedExtractedSymptoms || {},
      narrativeObservations: payload.narrativeObservations || '',
      careInterventions: payload.careInterventions || '',
      treatmentResponseNarrative: payload.treatmentResponseNarrative || '',
      status: 'SUBMITTED',
      createdAt: existingData?.createdAt ? existingData.createdAt : serverNow,
      createdAtIso,
      submittedAt: serverNow,
      fileHash,
      fabricStatus: 'PENDING',
      isAmended: false,
      amendmentOf: payload.amendmentOf || null,
      amendmentReason: payload.amendmentReason ? payload.amendmentReason.trim() : null,
    };

    t.set(noteRef, finalData, { merge: true });
  });

  return { success: true, noteId, status: 'SUBMITTED', fileHash };
}

/**
 * Handler for an attending physician to REVIEW and sign off on a submitted nursing note.
 * Doctor cannot rewrite clinical findings, but records verification and optional comments.
 */
export async function reviewClinicalNoteHandler(
  request: { auth?: { uid: string }; data: any },
  firestoreInstance?: admin.firestore.Firestore
): Promise<{ success: boolean; noteId: string; status: string; reviewedAt: string }> {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError('unauthenticated', 'User must be authenticated.');
  }

  const callerUid = request.auth.uid;
  const db = firestoreInstance || admin.firestore();
  const payload = request.data as ReviewClinicalNotePayload;

  if (!payload.patientId || !payload.noteId) {
    throw new HttpsError('invalid-argument', 'patientId and noteId are required.');
  }

  const { clinicianName } = await authorizeClinicianForPatient(
    db,
    callerUid,
    payload.patientId,
    'review'
  );

  const noteRef = db
    .collection('patients')
    .doc(payload.patientId)
    .collection('clinical_notes')
    .doc(payload.noteId);

  const now = new Date();

  await db.runTransaction(async (t) => {
    const snap = await t.get(noteRef);
    if (!snap.exists) {
      throw new HttpsError('not-found', `Clinical note '${payload.noteId}' not found.`);
    }

    const data = snap.data() || {};
    if (data.status === 'DRAFT') {
      throw new HttpsError(
        'failed-precondition',
        'Cannot review an unconfirmed DRAFT note. Nurse must submit the note first.'
      );
    }

    t.update(noteRef, {
      status: 'REVIEWED',
      reviewedByUid: callerUid,
      reviewedByName: clinicianName,
      reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
      doctorReviewNotes: (payload.reviewNotes || '').trim(),
    });
  });

  return {
    success: true,
    noteId: payload.noteId,
    status: 'REVIEWED',
    reviewedAt: now.toISOString(),
  };
}

// Firebase Cloud Function Callable Exports
export const saveClinicalNoteDraft = functions.https.onCall(async (data, context) => {
  return await saveClinicalNoteDraftHandler({ auth: context.auth, data });
});

export const submitClinicalNote = functions.https.onCall(async (data, context) => {
  return await submitClinicalNoteHandler({ auth: context.auth, data });
});

export const reviewClinicalNote = functions.https.onCall(async (data, context) => {
  return await reviewClinicalNoteHandler({ auth: context.auth, data });
});
