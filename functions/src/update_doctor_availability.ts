// functions/src/update_doctor_availability.ts

import { onCall, HttpsError } from 'firebase-functions/v2/https';
import * as admin from 'firebase-admin';
import { FieldValue } from 'firebase-admin/firestore';
import {
  parse12Hour,
  isValidIsoDate,
  isValidSlotKey,
} from './utils/time_utils';
import {
  CANONICAL_WEEKDAYS,
  SUPPORTED_DURATIONS,
  MAX_BLOCKED_DATES,
  MAX_BLOCKED_SLOTS,
  parseWeeklySchedule,
  generateDaySlots,
  WeeklySchedule,
} from './utils/availability_validator';

export interface UpdateDoctorAvailabilityRequest {
  availability: {
    slotDurationMinutes: number;
    weeklySchedule: Record<string, { enabled: boolean; startTime: string; endTime: string }>;
    blockedDates?: string[];
    blockedSlots?: string[];
  };
  isAvailable?: boolean;
}

export interface UpdateDoctorAvailabilityResponse {
  success: boolean;
  doctorId: string;
  scheduleRevision: number;
}

function serializeWeeklySchedule(weekly: WeeklySchedule): Record<string, any> {
  const result: Record<string, any> = {};
  for (const day of CANONICAL_WEEKDAYS) {
    const d = weekly.days[day];
    result[day] = {
      enabled: d.enabled,
      startTime: d.startTime,
      endTime: d.endTime,
    };
  }
  return result;
}

/**
 * Returns ISO calendar weekday (1 = Monday, ..., 7 = Sunday) for a "YYYY-MM-DD" string.
 */
function getIsoWeekday(dateKey: string): number {
  const parts = dateKey.split('-').map((p) => parseInt(p, 10));
  const utcDate = new Date(Date.UTC(parts[0], parts[1] - 1, parts[2]));
  const day = utcDate.getUTCDay(); // 0 = Sunday, 1 = Monday, ..., 6 = Saturday
  return day === 0 ? 7 : day;
}

/**
 * Trusted 2nd Generation Cloud Function handler: updateDoctorAvailability
 */
export const updateDoctorAvailabilityHandler = async (
  request: { auth?: { uid: string }; data: any },
  firestoreInstance?: admin.firestore.Firestore
): Promise<UpdateDoctorAvailabilityResponse> => {
  // 1. Fail-closed authentication check
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError(
      'unauthenticated',
      'Doctor availability updates require an authenticated session.'
    );
  }
  const callerUid = request.auth.uid.trim();

  const db = firestoreInstance || admin.firestore();

  // 2. Verify caller role in /users/{uid}
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

  // 3. Verify doctor document exists in /doctors/{uid}
  const doctorRef = db.collection('doctors').doc(callerUid);
  const doctorSnap = await doctorRef.get();
  if (!doctorSnap.exists) {
    throw new HttpsError(
      'permission-denied',
      'Doctor profile not found in doctors collection.'
    );
  }

  // 4. Validate request payload existence
  const rawData = request.data || {};
  const rawAvail = rawData.availability;
  if (!rawAvail || typeof rawAvail !== 'object' || Array.isArray(rawAvail)) {
    throw new HttpsError(
      'invalid-argument',
      'Doctor availability update requires an availability configuration payload.'
    );
  }

  // Validate slotDurationMinutes
  const duration = rawAvail.slotDurationMinutes;
  if (typeof duration !== 'number' || !SUPPORTED_DURATIONS.includes(duration)) {
    throw new HttpsError(
      'invalid-argument',
      `slotDurationMinutes must be one of [${SUPPORTED_DURATIONS.join(', ')}]. Received: ${duration}`
    );
  }

  // Validate weeklySchedule
  const parsedWeekly = parseWeeklySchedule(rawAvail.weeklySchedule, duration);
  if (!parsedWeekly) {
    throw new HttpsError(
      'invalid-argument',
      'weeklySchedule is malformed. All 7 weekdays must be specified with valid startTime < endTime and fit at least one slot.'
    );
  }

  // Validate blockedDates
  const rawBlockedDates = rawAvail.blockedDates ?? [];
  if (!Array.isArray(rawBlockedDates) || rawBlockedDates.length > MAX_BLOCKED_DATES) {
    throw new HttpsError(
      'invalid-argument',
      `blockedDates must be an array of at most ${MAX_BLOCKED_DATES} ISO dates.`
    );
  }
  const newBlockedDates = new Set<string>();
  for (const d of rawBlockedDates) {
    if (typeof d !== 'string' || !isValidIsoDate(d)) {
      throw new HttpsError(
        'invalid-argument',
        `Invalid blocked date format: "${d}". Expected "YYYY-MM-DD".`
      );
    }
    if (newBlockedDates.has(d)) {
      throw new HttpsError(
        'invalid-argument',
        `Duplicate blocked date detected: "${d}".`
      );
    }
    newBlockedDates.add(d);
  }

  // Validate blockedSlots
  const rawBlockedSlots = rawAvail.blockedSlots ?? [];
  if (!Array.isArray(rawBlockedSlots) || rawBlockedSlots.length > MAX_BLOCKED_SLOTS) {
    throw new HttpsError(
      'invalid-argument',
      `blockedSlots must be an array of at most ${MAX_BLOCKED_SLOTS} slot keys.`
    );
  }
  const newBlockedSlots = new Set<string>();
  for (const s of rawBlockedSlots) {
    if (typeof s !== 'string' || !isValidSlotKey(s)) {
      throw new HttpsError(
        'invalid-argument',
        `Invalid blocked slot key format: "${s}". Expected "YYYY-MM-DD_hh:mm AM/PM".`
      );
    }
    if (newBlockedSlots.has(s)) {
      throw new HttpsError(
        'invalid-argument',
        `Duplicate blocked slot detected: "${s}".`
      );
    }
    newBlockedSlots.add(s);
  }

  let finalRevision = 0;

  // 5. Execute atomic transaction to guard confirmed appointments & coordinate revisions
  await db.runTransaction(async (tx) => {
    // Read doctor document inside transaction
    const txDocSnap = await tx.get(doctorRef);
    if (!txDocSnap.exists) {
      throw new HttpsError('not-found', 'Doctor profile not found.');
    }
    const txDoctorData = txDocSnap.data() || {};
    const currentRevision = typeof txDoctorData.scheduleRevision === 'number'
      ? txDoctorData.scheduleRevision
      : 0;

    // Read all active confirmed slots for this doctor from /bookedSlots/{doctorId}/slots
    const bookedSlotsRef = db.collection('bookedSlots').doc(callerUid).collection('slots');
    const bookedSlotsSnap = await tx.get(bookedSlotsRef);

    for (const slotDoc of bookedSlotsSnap.docs) {
      const slotData = slotDoc.data() || {};
      const slotKey = slotDoc.id; // "YYYY-MM-DD_hh:mm AM/PM"
      const underscoreIdx = slotKey.indexOf('_');
      if (underscoreIdx === -1) continue;

      const dateKey = slotKey.substring(0, underscoreIdx);
      const timeSlot = slotKey.substring(underscoreIdx + 1);

      // Check 1: Does the new schedule block this confirmed date?
      if (newBlockedDates.has(dateKey)) {
        throw new HttpsError(
          'failed-precondition',
          `Cannot block date ${dateKey}: existing confirmed appointment (${slotData.appointmentId || slotKey}) is scheduled on this date.`
        );
      }

      // Check 2: Does the new schedule block this specific confirmed slot?
      if (newBlockedSlots.has(slotKey)) {
        throw new HttpsError(
          'failed-precondition',
          `Cannot block slot ${slotKey}: existing confirmed appointment is scheduled at this time.`
        );
      }

      // Check 3: Is the weekday enabled in the new weekly schedule?
      const isoWeekday = getIsoWeekday(dateKey);
      const weekdayKey = CANONICAL_WEEKDAYS[isoWeekday - 1];
      const daySchedule = parsedWeekly.days[weekdayKey];

      if (!daySchedule || !daySchedule.enabled) {
        throw new HttpsError(
          'failed-precondition',
          `Cannot disable ${weekdayKey}: existing confirmed appointment is scheduled on ${dateKey} at ${timeSlot}.`
        );
      }

      // Check 4: Does the confirmed slot start and end within the new working hours?
      const startMin = parse12Hour(timeSlot);
      if (startMin !== null) {
        const slotDuration = typeof slotData.durationMinutes === 'number'
          ? slotData.durationMinutes
          : duration;
        const endMin = startMin + slotDuration;

        if (startMin < daySchedule.startMinutes || endMin > daySchedule.endMinutes) {
          throw new HttpsError(
            'failed-precondition',
            `Cannot reduce working hours on ${weekdayKey}: existing confirmed appointment on ${dateKey} at ${timeSlot} falls outside new working hours (${daySchedule.startTime}–${daySchedule.endTime}).`
          );
        }
      }
    }

    // Advance scheduleRevision to coordinate concurrent approvals and updates
    finalRevision = currentRevision + 1;
    const nowTimestamp = FieldValue.serverTimestamp();

    const availabilityData = {
      slotDurationMinutes: duration,
      weeklySchedule: serializeWeeklySchedule(parsedWeekly),
      blockedDates: Array.from(newBlockedDates).sort(),
      blockedSlots: Array.from(newBlockedSlots).sort(),
      updatedAt: nowTimestamp,
    };

    const updatePayload: Record<string, any> = {
      availability: availabilityData,
      scheduleRevision: finalRevision,
      updatedAt: nowTimestamp,
    };

    if (typeof rawData.isAvailable === 'boolean') {
      updatePayload.isAvailable = rawData.isAvailable;
    } else if (typeof rawAvail.isAvailable === 'boolean') {
      updatePayload.isAvailable = rawAvail.isAvailable;
    }

    // Mirror to legacy availableDays and availableSlots for backward compatibility
    const legacyDays: string[] = [];
    const dayToAbbr: Record<string, string> = {
      monday: 'Mon',
      tuesday: 'Tue',
      wednesday: 'Wed',
      thursday: 'Thu',
      friday: 'Fri',
      saturday: 'Sat',
      sunday: 'Sun',
    };
    for (const d of CANONICAL_WEEKDAYS) {
      if (parsedWeekly.days[d]?.enabled) {
        legacyDays.push(dayToAbbr[d]);
      }
    }
    updatePayload.availableDays = legacyDays;

    const firstEnabled = Object.values(parsedWeekly.days).find((d) => d.enabled);
    if (firstEnabled) {
      updatePayload.availableSlots = generateDaySlots(firstEnabled, duration);
    }

    tx.update(doctorRef, updatePayload);
  });

  return {
    success: true,
    doctorId: callerUid,
    scheduleRevision: finalRevision,
  };
};

export const updateDoctorAvailability = onCall(
  {
    region: 'us-central1',
    enforceAppCheck: false,
  },
  async (request) => {
    return updateDoctorAvailabilityHandler(request);
  }
);
