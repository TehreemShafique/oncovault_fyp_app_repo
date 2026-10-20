// functions/src/approve_appointment.ts

import { onCall, HttpsError } from 'firebase-functions/v2/https';
import * as admin from 'firebase-admin';
import { Timestamp, FieldValue } from 'firebase-admin/firestore';
import {
  toPktDate,
  buildSlotKey,
  PKT_OFFSET_MS,
} from './utils/time_utils';
import {
  parseDoctorAvailability,
  validateSlot,
  AppointmentInterval,
} from './utils/availability_validator';

export interface ApproveAppointmentRequest {
  appointmentId: string;
}

export interface ApproveAppointmentResponse {
  success: boolean;
  appointmentId: string;
  status: string;
  slotKey: string;
}

/**
 * Normalizes appointment status string, returning canonical value.
 */
function canonicalStatus(rawStatus?: string | null): string | null {
  if (!rawStatus) return null;
  const trimmed = rawStatus.trim().toLowerCase();
  switch (trimmed) {
    case 'scheduled':
    case 'pending':
      return 'scheduled';
    case 'confirmed':
    case 'approved':
      return 'confirmed';
    case 'rescheduled':
      return 'rescheduled';
    case 'cancelled':
    case 'canceled':
      return 'cancelled';
    case 'completed':
      return 'completed';
    case 'rejected':
      return 'rejected';
    default:
      return null;
  }
}

/**
 * Trusted 2nd Generation Cloud Function: approveAppointment
 */
export const approveAppointmentHandler = async (
  request: { auth?: { uid: string }; data: any },
  firestoreInstance?: admin.firestore.Firestore
): Promise<ApproveAppointmentResponse> => {
  // 1. Fail-closed authentication check
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError(
      'unauthenticated',
      'Doctor approval requires an authenticated session.'
    );
  }
  const callerUid = request.auth.uid.trim();

  // 2. Validate request payload
  const appointmentId = request.data?.appointmentId?.toString()?.trim();
  if (!appointmentId) {
    throw new HttpsError(
      'invalid-argument',
      'Appointment approval requires a non-empty appointmentId.'
    );
  }

  const db = firestoreInstance || admin.firestore();

  // 3. Verify caller role in /users/{uid}
  const userSnap = await db.collection('users').doc(callerUid).get();
  if (!userSnap.exists) {
    throw new HttpsError(
      'permission-denied',
      'Caller user profile does not exist.'
    );
  }
  const userRole = userSnap.data()?.role;
  if (userRole !== 'doctor') {
    throw new HttpsError(
      'permission-denied',
      'Caller is not authorized as a doctor.'
    );
  }

  // 4. Verify doctor document exists in /doctors/{uid}
  const doctorRef = db.collection('doctors').doc(callerUid);
  const doctorSnap = await doctorRef.get();
  if (!doctorSnap.exists) {
    throw new HttpsError(
      'permission-denied',
      'Doctor profile not found in doctors collection.'
    );
  }

  let confirmedDate: Date | null = null;
  let confirmedTimeSlot = '';
  let confirmedDoctorName = '';
  let confirmedPatientId = '';
  let finalSlotKey = '';

  const apptRef = db.collection('appointments').doc(appointmentId);

  // 5. Run atomic Firestore transaction
  await db.runTransaction(async (tx) => {
    // ── PHASE 1: ALL READS MUST PRECEDE ALL WRITES ──

    // 1. Read authoritative global appointment
    const apptSnap = await tx.get(apptRef);
    if (!apptSnap.exists) {
      throw new HttpsError(
        'not-found',
        `Appointment document ${appointmentId} not found.`
      );
    }
    const apptData = apptSnap.data() || {};

    // Verify assigned doctor ownership
    const serverDoctorId = (apptData.doctorId || '').toString().trim();
    if (!serverDoctorId || serverDoctorId !== callerUid) {
      throw new HttpsError(
        'permission-denied',
        'Authenticated doctor UID does not match the appointment doctor ID.'
      );
    }

    // Verify appointment status eligibility
    const rawStatus = (apptData.status || '').toString().trim();
    const canon = canonicalStatus(rawStatus);
    if (!canon) {
      throw new HttpsError(
        'failed-precondition',
        `Appointment document ${appointmentId} status is invalid or empty.`
      );
    }

    if (canon === 'confirmed') {
      throw new HttpsError(
        'failed-precondition',
        `Appointment ${appointmentId} is already confirmed.`
      );
    }

    if (canon === 'completed' || canon === 'rejected' || canon === 'cancelled') {
      throw new HttpsError(
        'failed-precondition',
        `Appointment ${appointmentId} is in terminal status "${rawStatus}", cannot be confirmed.`
      );
    }

    if (canon !== 'scheduled' && canon !== 'rescheduled') {
      throw new HttpsError(
        'failed-precondition',
        `Appointment ${appointmentId} in status "${rawStatus}" is not eligible for approval.`
      );
    }

    // Validate authoritative fields
    const serverPatientId = (apptData.patientId || '').toString().trim();
    if (!serverPatientId) {
      throw new HttpsError(
        'failed-precondition',
        `Authoritative appointment ${appointmentId} is missing patientId.`
      );
    }

    const rawServerDate = apptData.appointmentDate;
    if (!rawServerDate || typeof rawServerDate.toDate !== 'function') {
      throw new HttpsError(
        'failed-precondition',
        `Authoritative appointment ${appointmentId} has missing or invalid appointmentDate.`
      );
    }
    const serverAppointmentDate: Date = rawServerDate.toDate();

    const serverTimeSlot = (apptData.timeSlot || '').toString().trim();
    if (!serverTimeSlot) {
      throw new HttpsError(
        'failed-precondition',
        `Authoritative appointment ${appointmentId} is missing timeSlot.`
      );
    }

    const serverDuration = typeof apptData.durationMinutes === 'number'
      ? apptData.durationMinutes
      : 45;

    // 2. Read patient mirror document
    const mirrorRef = db
      .collection('patients')
      .doc(serverPatientId)
      .collection('appointments')
      .doc(appointmentId);

    const mirrorSnap = await tx.get(mirrorRef);
    if (!mirrorSnap.exists) {
      throw new HttpsError(
        'failed-precondition',
        `Patient appointment mirror does not exist at /patients/${serverPatientId}/appointments/${appointmentId}.`
      );
    }

    const mirrorData = mirrorSnap.data() || {};
    const mirrorDoctorId = (mirrorData.doctorId || '').toString().trim();
    const mirrorPatientId = (mirrorData.patientId || '').toString().trim();
    const mirrorRawStatus = (mirrorData.status || '').toString().trim();

    if (mirrorDoctorId !== serverDoctorId || mirrorPatientId !== serverPatientId) {
      throw new HttpsError(
        'failed-precondition',
        'Patient appointment mirror contains mismatched identity fields.'
      );
    }

    const mirrorCanon = canonicalStatus(mirrorRawStatus);
    if (mirrorCanon !== canon) {
      throw new HttpsError(
        'failed-precondition',
        `Patient appointment mirror status "${mirrorRawStatus}" does not match global status "${rawStatus}".`
      );
    }

    const rawMirrorDate = mirrorData.appointmentDate;
    if (!rawMirrorDate || typeof rawMirrorDate.toDate !== 'function') {
      throw new HttpsError(
        'failed-precondition',
        'Patient appointment mirror has missing or invalid appointmentDate.'
      );
    }
    const mirrorDate: Date = rawMirrorDate.toDate();

    const { dateKey: serverDateKey, weekday: serverWeekday, year: sY, month: sM, day: sD } =
      toPktDate(serverAppointmentDate);
    const { dateKey: mirrorDateKey } = toPktDate(mirrorDate);

    if (serverDateKey !== mirrorDateKey) {
      throw new HttpsError(
        'failed-precondition',
        'Patient appointment mirror date conflicts with authoritative date.'
      );
    }

    const mirrorTimeSlot = (mirrorData.timeSlot || '').toString().trim();
    if (mirrorTimeSlot !== serverTimeSlot) {
      throw new HttpsError(
        'failed-precondition',
        `Patient appointment mirror timeSlot "${mirrorTimeSlot}" conflicts with authoritative timeSlot "${serverTimeSlot}".`
      );
    }

    // 3. Derive canonical slotKey and check slot lock
    const authoritativeSlotKey = buildSlotKey(serverDateKey, serverTimeSlot);
    finalSlotKey = authoritativeSlotKey;

    const slotRef = db
      .collection('bookedSlots')
      .doc(serverDoctorId)
      .collection('slots')
      .doc(authoritativeSlotKey);

    const slotSnap = await tx.get(slotRef);
    let shouldWriteSlotLock = true;

    if (slotSnap.exists) {
      const slotData = slotSnap.data() || {};
      const lockApptId = (slotData.appointmentId || '').toString().trim();
      const lockPatientId = (slotData.patientId || '').toString().trim();

      if (!lockApptId || !lockPatientId) {
        throw new HttpsError(
          'failed-precondition',
          `Slot lock ${authoritativeSlotKey} is corrupt or missing ownership information.`
        );
      }

      if (lockApptId !== appointmentId) {
        throw new HttpsError(
          'already-exists',
          `Slot ${authoritativeSlotKey} is already booked by appointment ${lockApptId}.`
        );
      }

      if (lockPatientId !== serverPatientId) {
        throw new HttpsError(
          'failed-precondition',
          `Slot lock ${authoritativeSlotKey} patient ID conflicts with authoritative appointment.`
        );
      }

      // Existing valid lock for this appointment: preserve original bookedAt
      shouldWriteSlotLock = false;
    }

    // 4. Read doctor document inside transaction for coordination
    const txDoctorSnap = await tx.get(doctorRef);
    const txDoctorData = txDoctorSnap.data() || {};

    // 5. Validate doctor availability against Phase 2D.1 domain rules
    const availability = parseDoctorAvailability(txDoctorData);
    const isDoctorAvailable = txDoctorData.isAvailable !== false;

    const validation = validateSlot({
      dateKey: serverDateKey,
      weekday: serverWeekday,
      timeSlot: serverTimeSlot,
      durationMinutes: serverDuration,
      availability,
      isDoctorAvailable,
    });

    if (!validation.valid) {
      throw new HttpsError(
        'failed-precondition',
        validation.reason || 'Doctor is not available at requested slot.'
      );
    }

    // 6. Cross-duration interval overlap & concurrency protection
    // Compute PKT calendar day start/end boundaries in UTC
    const dayStartUtcMs = Date.UTC(sY, sM - 1, sD, 0, 0, 0) - PKT_OFFSET_MS;
    const dayEndUtcMs = Date.UTC(sY, sM - 1, sD, 23, 59, 59, 999) - PKT_OFFSET_MS;

    const dayStartTimestamp = Timestamp.fromMillis(dayStartUtcMs);
    const dayEndTimestamp = Timestamp.fromMillis(dayEndUtcMs);

    const targetInterval = AppointmentInterval.fromSlot(
      serverDateKey,
      serverTimeSlot,
      serverDuration
    );

    if (!targetInterval) {
      throw new HttpsError(
        'failed-precondition',
        `Unable to construct valid appointment interval for slot ${serverTimeSlot}.`
      );
    }

    const dayQuery = db
      .collection('appointments')
      .where('doctorId', '==', serverDoctorId)
      .where('appointmentDate', '>=', dayStartTimestamp)
      .where('appointmentDate', '<=', dayEndTimestamp);

    const querySnap = await tx.get(dayQuery);

    for (const doc of querySnap.docs) {
      if (doc.id === appointmentId) continue;
      const otherData = doc.data() || {};
      const otherCanon = canonicalStatus((otherData.status || '').toString());

      if (otherCanon === 'confirmed') {
        const otherSlot = (otherData.timeSlot || '').toString().trim();
        const otherDur = typeof otherData.durationMinutes === 'number'
          ? otherData.durationMinutes
          : 45;
        const otherInterval = AppointmentInterval.fromSlot(
          serverDateKey,
          otherSlot,
          otherDur
        );

        if (otherInterval && targetInterval.overlaps(otherInterval)) {
          throw new HttpsError(
            'already-exists',
            `Slot ${serverTimeSlot} (${serverDuration}m) overlaps with confirmed appointment ${doc.id} at ${otherSlot} (${otherDur}m).`
          );
        }
      }
    }

    // Capture verified fields for post-commit notification
    confirmedDate = serverAppointmentDate;
    confirmedTimeSlot = serverTimeSlot;
    confirmedDoctorName = (apptData.doctorName || '').toString().trim() || (userSnap.data()?.name || 'Doctor');
    confirmedPatientId = serverPatientId;

    // ── PHASE 2: ATOMIC WRITES ──
    const nowTimestamp = FieldValue.serverTimestamp();
    const updatePayload = {
      status: 'confirmed',
      slotKey: authoritativeSlotKey,
      updatedAt: nowTimestamp,
    };

    tx.update(apptRef, updatePayload);
    tx.update(mirrorRef, updatePayload);

    if (shouldWriteSlotLock) {
      tx.set(slotRef, {
        appointmentId,
        patientId: serverPatientId,
        patientName: apptData.patientName || '',
        date: rawServerDate,
        timeSlot: serverTimeSlot,
        bookedAt: nowTimestamp,
      });
    }

    // Advance scheduleRevision on doctor document to serialize concurrent doctor transactions
    const currentRevision = typeof txDoctorData.scheduleRevision === 'number'
      ? txDoctorData.scheduleRevision
      : 0;

    tx.update(doctorRef, {
      scheduleRevision: currentRevision + 1,
      lastBookingAt: nowTimestamp,
    });
  });

  // 6. Post-transaction Notification: strictly executed outside transaction callback
  if (confirmedPatientId) {
    try {
      const dateFormatted = confirmedDate
        ? (confirmedDate as Date).toISOString().substring(0, 10)
        : '';
      await db
        .collection('notifications')
        .doc(confirmedPatientId)
        .collection('items')
        .add({
          patientId: confirmedPatientId,
          title: 'Appointment Approved ✓',
          body: `Your appointment with ${confirmedDoctorName} on ${dateFormatted} at ${confirmedTimeSlot} has been approved.`,
          type: 'appointment',
          referenceId: appointmentId,
          createdAt: FieldValue.serverTimestamp(),
        });
    } catch (notifErr) {
      // Per Section 8: Notification failure must NEVER fail the confirmed appointment
      console.warn('Post-transaction notification delivery failed:', notifErr);
    }
  }

  return {
    success: true,
    appointmentId,
    status: 'confirmed',
    slotKey: finalSlotKey,
  };
};

/**
 * 2nd Generation Cloud Function export
 */
export const approveAppointment = onCall(
  {
    region: 'us-central1',
    cors: true,
    enforceAppCheck: false,
    invoker: 'public',
  },
  async (request) => {
    return approveAppointmentHandler(request);
  }
);
