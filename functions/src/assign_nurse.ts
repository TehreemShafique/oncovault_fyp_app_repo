// functions/src/assign_nurse.ts

import { onCall, HttpsError } from 'firebase-functions/v2/https';
import * as admin from 'firebase-admin';
import { FieldValue } from 'firebase-admin/firestore';

export interface AssignNurseRequest {
  nurseId: string;
  patientId: string;
  hospitalId?: string;
  notes?: string;
}

export interface AssignNurseResponse {
  success: boolean;
  assignmentId: string;
  nurseId: string;
  patientId: string;
  status: string;
}

export interface RevokeNurseAssignmentRequest {
  nurseId: string;
  patientId: string;
  reason?: string;
}

/**
 * Verifies that a doctor holds legitimate, active care authorization for a patient.
 * 1. Checks Fabric-synchronized consent records in `doctor_patient_consents`.
 *    - If consent is explicitly revoked (`status === 'revoked'` or `isRevoked === true` or `revoked === true`),
 *      access is immediately denied. An appointment CANNOT override an explicitly revoked consent.
 *    - If active granted consent exists (`status === 'granted'` and not revoked), authorization is granted.
 * 2. If no consent record exists, checks active current care coordination appointments.
 *    - Status must be in ['confirmed', 'approved', 'scheduled', 'rescheduled'].
 *    - Completed historical appointments (`status === 'completed'`) or cancelled/rejected appointments
 *      are strictly rejected and cannot grant current care authorization.
 *    - Expired historical appointments (>24 hours past scheduled date) are rejected.
 */
export async function verifyDoctorCareAuthorization(
  db: admin.firestore.Firestore,
  doctorId: string,
  patientId: string
): Promise<void> {
  const consentSnap = await db
    .collection('doctor_patient_consents')
    .where('doctorId', '==', doctorId)
    .where('patientId', '==', patientId)
    .limit(10)
    .get();

  const directDoc = await db.collection('doctor_patient_consents').doc(`${patientId}_${doctorId}`).get();

  const allConsentDocs: any[] = consentSnap.docs.map((d) => d.data());
  if (directDoc.exists) {
    allConsentDocs.push(directDoc.data());
  }

  // 1. Check if consent has been explicitly revoked
  const isExplicitlyRevoked = allConsentDocs.some((c) => {
    const status = (c.status || '').toLowerCase();
    return status === 'revoked' || c.isRevoked === true || c.revoked === true;
  });

  if (isExplicitlyRevoked) {
    throw new HttpsError(
      'permission-denied',
      `Patient ${patientId} has explicitly revoked consent for doctor ${doctorId}. Care access is denied.`
    );
  }

  // 2. Check if active granted consent exists
  const hasActiveConsent = allConsentDocs.some((c) => {
    const status = (c.status || '').toLowerCase();
    return status === 'granted' && c.isRevoked !== true && c.revoked !== true;
  });

  if (hasActiveConsent) {
    return;
  }

  // 3. If no consent record exists, check legitimate appointment-based care coordination
  const apptSnap = await db
    .collection('appointments')
    .where('doctorId', '==', doctorId)
    .where('patientId', '==', patientId)
    .limit(10)
    .get();

  const nowMs = Date.now();
  const validAppts = apptSnap.docs.filter((d) => {
    const data = d.data();
    const status = (data?.status || '').toLowerCase();

    // Reject completed historical appointments or cancelled/rejected
    if (['completed', 'cancelled', 'canceled', 'rejected'].includes(status)) {
      return false;
    }

    if (!['confirmed', 'approved', 'scheduled', 'rescheduled'].includes(status)) {
      return false;
    }

    // Check if appointment is expired (>24 hours in the past)
    if (data?.appointmentDate) {
      let apptTime: number | null = null;
      if (typeof data.appointmentDate.toMillis === 'function') {
        apptTime = data.appointmentDate.toMillis();
      } else if (data.appointmentDate instanceof Date) {
        apptTime = data.appointmentDate.getTime();
      } else if (typeof data.appointmentDate === 'string') {
        const parsed = Date.parse(data.appointmentDate);
        if (!isNaN(parsed)) apptTime = parsed;
      }

      if (apptTime !== null) {
        const twentyFourHours = 24 * 60 * 60 * 1000;
        if (apptTime < nowMs - twentyFourHours) {
          return false;
        }
      }
    }

    return true;
  });

  if (validAppts.length === 0) {
    throw new HttpsError(
      'permission-denied',
      `Doctor ${doctorId} does not hold active care authorization or valid current appointment for patient ${patientId}.`
    );
  }
}

/**
 * Trusted handler for assigning a nurse to a patient.
 * Callable by Hospital Administrators and Attending Physicians.
 * Enforces that nurses cannot self-assign patients through direct client operations.
 */
export const assignNurseHandler = async (
  request: { auth?: { uid: string }; data: any },
  firestoreInstance?: admin.firestore.Firestore
): Promise<AssignNurseResponse> => {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError('unauthenticated', 'User must be authenticated.');
  }

  const callerUid = request.auth.uid;
  const db = firestoreInstance || admin.firestore();

  // Verify caller role: must be admin or doctor (authorized clinical leadership)
  const callerUserDoc = await db.collection('users').doc(callerUid).get();
  if (!callerUserDoc.exists) {
    throw new HttpsError('permission-denied', 'Caller user record not found.');
  }
  const callerData = callerUserDoc.data();
  const callerRole = (callerData?.role || '').toLowerCase();
  if (callerRole !== 'admin' && callerRole !== 'doctor') {
    throw new HttpsError(
      'permission-denied',
      'Only hospital administrators or authorized physicians can assign nurses to patients.'
    );
  }

  const { nurseId, patientId, hospitalId, notes } = request.data as AssignNurseRequest;
  if (!nurseId || typeof nurseId !== 'string' || !nurseId.trim()) {
    throw new HttpsError('invalid-argument', 'Valid nurseId is required.');
  }
  if (!patientId || typeof patientId !== 'string' || !patientId.trim()) {
    throw new HttpsError('invalid-argument', 'Valid patientId is required.');
  }

  // Prevent self-assignment
  if (callerUid === nurseId) {
    throw new HttpsError('permission-denied', 'Nurses cannot assign patients to themselves.');
  }

  // Verify target nurse exists and has role 'nurse'
  const nurseDoc = await db.collection('users').doc(nurseId).get();
  if (!nurseDoc.exists) {
    throw new HttpsError('not-found', `Nurse user ${nurseId} does not exist.`);
  }
  const nurseData = nurseDoc.data();
  if ((nurseData?.role || '').toLowerCase() !== 'nurse') {
    throw new HttpsError('failed-precondition', `Target user ${nurseId} is not a registered nurse.`);
  }
  if (nurseData?.status && (nurseData.status === 'inactive' || nurseData.status === 'suspended')) {
    throw new HttpsError('failed-precondition', `Target nurse ${nurseId} is not active.`);
  }

  // Verify target patient exists (in patients or users)
  let patientName = 'Patient';
  const patientDoc = await db.collection('patients').doc(patientId).get();
  if (patientDoc.exists) {
    patientName = patientDoc.data()?.name || patientName;
  } else {
    const userPatientDoc = await db.collection('users').doc(patientId).get();
    if (!userPatientDoc.exists) {
      throw new HttpsError('not-found', `Patient ${patientId} does not exist.`);
    }
    const uData = userPatientDoc.data();
    if (uData?.role && uData.role !== 'patient') {
      throw new HttpsError('not-found', `Target user ${patientId} is not a registered patient.`);
    }
    patientName = uData?.name || patientName;
  }

  // Attending doctor authorization check
  if (callerRole === 'doctor') {
    await verifyDoctorCareAuthorization(db, callerUid, patientId);
  }

  // Cross-hospital scope check
  const effectiveHospitalId = hospitalId || callerData?.hospitalId || 'Oncology Ward 3A';
  if (callerRole !== 'admin') {
    if (callerData?.hospitalId && hospitalId && callerData.hospitalId !== hospitalId) {
      throw new HttpsError('permission-denied', 'Cross-hospital assignment is not permitted.');
    }
    if (nurseData?.hospitalId && effectiveHospitalId && nurseData.hospitalId !== effectiveHospitalId) {
      throw new HttpsError(
        'permission-denied',
        `Nurse ${nurseId} belongs to a different hospital scope (${nurseData.hospitalId}).`
      );
    }
  }

  const assignmentId = `${nurseId}_${patientId}`;
  const assignmentRef = db.collection('nurse_patient_assignments').doc(assignmentId);

  const payload = {
    id: assignmentId,
    nurseId,
    nurseName: nurseData?.name || 'Staff Nurse',
    patientId,
    patientName,
    assignedBy: callerUid,
    hospitalId: effectiveHospitalId,
    status: 'active',
    assignedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
    notes: notes || '',
  };

  await assignmentRef.set(payload, { merge: true });

  return {
    success: true,
    assignmentId,
    nurseId,
    patientId,
    status: 'active',
  };
};

/**
 * Revokes an existing nurse-patient care assignment.
 */
export const revokeNurseAssignmentHandler = async (
  request: { auth?: { uid: string }; data: any },
  firestoreInstance?: admin.firestore.Firestore
): Promise<{ success: boolean; assignmentId: string; status: string }> => {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError('unauthenticated', 'User must be authenticated.');
  }

  const callerUid = request.auth.uid;
  const db = firestoreInstance || admin.firestore();

  const callerUserDoc = await db.collection('users').doc(callerUid).get();
  if (!callerUserDoc.exists) {
    throw new HttpsError('permission-denied', 'Caller user record not found.');
  }
  const callerRole = (callerUserDoc.data()?.role || '').toLowerCase();
  if (callerRole !== 'admin' && callerRole !== 'doctor') {
    throw new HttpsError(
      'permission-denied',
      'Only administrators or physicians can revoke nurse assignments.'
    );
  }

  const { nurseId, patientId, reason } = request.data as RevokeNurseAssignmentRequest;
  if (!nurseId || !patientId) {
    throw new HttpsError('invalid-argument', 'Valid nurseId and patientId are required.');
  }
  const assignmentId = `${nurseId}_${patientId}`;
  const assignmentRef = db.collection('nurse_patient_assignments').doc(assignmentId);

  const snap = await assignmentRef.get();
  if (!snap.exists) {
    throw new HttpsError('not-found', `Assignment ${assignmentId} does not exist.`);
  }

  const assignData = snap.data();
  if (callerRole === 'doctor' && assignData?.assignedBy !== callerUid) {
    // If not the original assigner, verify doctor is currently authorized for the patient
    await verifyDoctorCareAuthorization(db, callerUid, patientId);
  }

  await assignmentRef.update({
    status: 'revoked',
    revokedAt: FieldValue.serverTimestamp(),
    revokedBy: callerUid,
    revocationReason: reason || 'Shift completed or care reassigned',
    updatedAt: FieldValue.serverTimestamp(),
  });

  return {
    success: true,
    assignmentId,
    status: 'revoked',
  };
};

export const assignNurse = onCall({ region: 'us-central1' }, assignNurseHandler);
export const revokeNurseAssignment = onCall({ region: 'us-central1' }, revokeNurseAssignmentHandler);
