// functions/src/manage_critical_alert.ts

import { onCall, HttpsError } from 'firebase-functions/v2/https';
import * as admin from 'firebase-admin';
import { FieldValue } from 'firebase-admin/firestore';

export interface AcknowledgeAlertRequest {
  doctorId: string;
  alertId: string;
  notes?: string;
}

export interface ResolveAlertRequest {
  doctorId: string;
  alertId: string;
  notes?: string;
}

export interface AlertActionResponse {
  success: boolean;
  alertId: string;
  doctorId: string;
  status: string;
  timestamp: string;
}

/**
 * Callable: acknowledgeCriticalAlert
 * Enforces doctor ownership, records server-side timestamp and clinician UID.
 */
export const acknowledgeCriticalAlertHandler = async (
  request: { auth?: { uid: string }; data: any },
  firestoreInstance?: admin.firestore.Firestore
): Promise<AlertActionResponse> => {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError('unauthenticated', 'User must be authenticated to acknowledge alerts.');
  }

  const callerUid = request.auth.uid;
  const db = firestoreInstance || admin.firestore();

  const userDoc = await db.collection('users').doc(callerUid).get();
  if (!userDoc.exists) {
    throw new HttpsError('permission-denied', 'User record not found.');
  }
  const userRole = (userDoc.data()?.role || '').toLowerCase();
  if (userRole !== 'doctor' && userRole !== 'admin') {
    throw new HttpsError('permission-denied', 'Only authorized physicians or administrators can acknowledge clinical alerts.');
  }

  const { doctorId, alertId, notes = '' } = request.data as AcknowledgeAlertRequest;
  if (!doctorId || typeof doctorId !== 'string' || !doctorId.trim()) {
    throw new HttpsError('invalid-argument', 'Valid doctorId is required.');
  }
  if (!alertId || typeof alertId !== 'string' || !alertId.trim()) {
    throw new HttpsError('invalid-argument', 'Valid alertId is required.');
  }

  // Doctor ownership protection: cannot acknowledge on behalf of another doctor
  if (userRole !== 'admin' && callerUid !== doctorId) {
    throw new HttpsError(
      'permission-denied',
      'Physicians cannot acknowledge critical alerts assigned to another doctor.'
    );
  }

  const alertRef = db.collection('doctors').doc(doctorId).collection('alerts').doc(alertId);
  const alertSnap = await alertRef.get();
  if (!alertSnap.exists) {
    throw new HttpsError('not-found', `Critical alert ${alertId} does not exist for doctor ${doctorId}.`);
  }

  const alertData = alertSnap.data();
  if (alertData?.isResolved === true) {
    throw new HttpsError('failed-precondition', 'Cannot acknowledge an alert that has already been resolved.');
  }

  const serverNow = FieldValue.serverTimestamp();
  await alertRef.update({
    isRead: true,
    isAcknowledged: true,
    acknowledgedAt: serverNow,
    acknowledgedBy: callerUid,
    acknowledgmentNotes: notes,
  });

  // Also update corresponding in-app notification item if it exists
  const notifRef = db.collection('notifications').doc(doctorId).collection('items').doc(alertId);
  try {
    const notifSnap = await notifRef.get();
    if (notifSnap.exists) {
      await notifRef.update({ isRead: true });
    }
  } catch (_) {}

  return {
    success: true,
    alertId,
    doctorId,
    status: 'ACKNOWLEDGED',
    timestamp: new Date().toISOString(),
  };
};

/**
 * Callable: resolveCriticalAlert
 * Enforces that an alert MUST be acknowledged before it can be marked resolved.
 */
export const resolveCriticalAlertHandler = async (
  request: { auth?: { uid: string }; data: any },
  firestoreInstance?: admin.firestore.Firestore
): Promise<AlertActionResponse> => {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError('unauthenticated', 'User must be authenticated to resolve alerts.');
  }

  const callerUid = request.auth.uid;
  const db = firestoreInstance || admin.firestore();

  const userDoc = await db.collection('users').doc(callerUid).get();
  if (!userDoc.exists) {
    throw new HttpsError('permission-denied', 'User record not found.');
  }
  const userRole = (userDoc.data()?.role || '').toLowerCase();
  if (userRole !== 'doctor' && userRole !== 'admin') {
    throw new HttpsError('permission-denied', 'Only authorized physicians or administrators can resolve clinical alerts.');
  }

  const { doctorId, alertId, notes = '' } = request.data as ResolveAlertRequest;
  if (!doctorId || typeof doctorId !== 'string' || !doctorId.trim()) {
    throw new HttpsError('invalid-argument', 'Valid doctorId is required.');
  }
  if (!alertId || typeof alertId !== 'string' || !alertId.trim()) {
    throw new HttpsError('invalid-argument', 'Valid alertId is required.');
  }

  // Doctor ownership protection
  if (userRole !== 'admin' && callerUid !== doctorId) {
    throw new HttpsError(
      'permission-denied',
      'Physicians cannot resolve critical alerts assigned to another doctor.'
    );
  }

  const alertRef = db.collection('doctors').doc(doctorId).collection('alerts').doc(alertId);
  const alertSnap = await alertRef.get();
  if (!alertSnap.exists) {
    throw new HttpsError('not-found', `Critical alert ${alertId} does not exist for doctor ${doctorId}.`);
  }

  const alertData = alertSnap.data();

  // Strict state machine: ACTIVE -> ACKNOWLEDGED -> RESOLVED
  if (!alertData?.isAcknowledged) {
    throw new HttpsError(
      'failed-precondition',
      'Alert must be explicitly acknowledged by the recipient physician before it can be resolved.'
    );
  }

  const serverNow = FieldValue.serverTimestamp();
  await alertRef.update({
    isResolved: true,
    resolvedAt: serverNow,
    resolvedBy: callerUid,
    resolutionNotes: notes,
  });

  return {
    success: true,
    alertId,
    doctorId,
    status: 'RESOLVED',
    timestamp: new Date().toISOString(),
  };
};

export const acknowledgeCriticalAlert = onCall(
  { region: 'us-central1' },
  acknowledgeCriticalAlertHandler
);

export const resolveCriticalAlert = onCall(
  { region: 'us-central1' },
  resolveCriticalAlertHandler
);
