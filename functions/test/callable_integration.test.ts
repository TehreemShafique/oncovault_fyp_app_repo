// functions/test/callable_integration.test.ts

import * as admin from 'firebase-admin';
import { approveAppointmentHandler } from '../src/approve_appointment';
import { updateDoctorAvailabilityHandler } from '../src/update_doctor_availability';
import { buildSlotKey } from '../src/utils/time_utils';

const PROJECT_ID = process.env.GCLOUD_PROJECT || 'demo-no-project';

// Connect to Firestore Emulator if FIRESTORE_EMULATOR_HOST is set, or default
if (!process.env.FIRESTORE_EMULATOR_HOST) {
  process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
}

if (!admin.apps.length) {
  admin.initializeApp({ projectId: PROJECT_ID });
}

const db = admin.firestore();

describe('Phase 2D.2A Callable Integration Tests (Real Firestore Transactions)', () => {
  const doctorUid = 'doc_test_1';
  const patientUid = 'patient_test_1';
  const otherPatientUid = 'patient_test_2';
  const otherDoctorUid = 'doc_test_2';

  // Base schedule for doc_test_1: Monday to Friday 09:00 - 17:00, 45 min slots
  // Conforms strictly to Flutter DoctorAvailability model serialization schema
  const validAvailability = {
    slotDurationMinutes: 45,
    weeklySchedule: {
      monday: { enabled: true, startTime: '09:00', endTime: '17:00' },
      tuesday: { enabled: true, startTime: '09:00', endTime: '17:00' },
      wednesday: { enabled: true, startTime: '09:00', endTime: '17:00' },
      thursday: { enabled: true, startTime: '09:00', endTime: '17:00' },
      friday: { enabled: true, startTime: '09:00', endTime: '17:00' },
      saturday: { enabled: false, startTime: '09:00', endTime: '17:00' },
      sunday: { enabled: false, startTime: '09:00', endTime: '17:00' },
    },
    blockedDates: ['2026-12-25'],
    blockedSlots: ['2026-10-20_02:15 PM'],
  };

  beforeAll(async () => {
    // Seed users and doctor profiles
    await db.collection('users').doc(doctorUid).set({
      uid: doctorUid,
      role: 'doctor',
      name: 'Dr. Test Doctor',
      email: 'doctor@test.com',
    });

    await db.collection('doctors').doc(doctorUid).set({
      uid: doctorUid,
      name: 'Dr. Test Doctor',
      isAvailable: true,
      scheduleRevision: 1,
      availability: validAvailability,
    });

    await db.collection('users').doc(patientUid).set({
      uid: patientUid,
      role: 'patient',
      name: 'Test Patient',
      email: 'patient@test.com',
    });

    await db.collection('users').doc(otherPatientUid).set({
      uid: otherPatientUid,
      role: 'patient',
      name: 'Other Patient',
      email: 'other_patient@test.com',
    });

    await db.collection('users').doc(otherDoctorUid).set({
      uid: otherDoctorUid,
      role: 'doctor',
      name: 'Dr. Other',
    });
  });

  // Helper to create test appointment in global + patient mirror
  async function seedAppointment(
    appointmentId: string,
    overrides: {
      status?: string;
      appointmentDate?: Date;
      timeSlot?: string;
      durationMinutes?: number;
      doctorId?: string;
      patientId?: string;
      skipMirror?: boolean;
      mirrorOverrides?: any;
    } = {}
  ) {
    // Future date: 2026-10-20 is a Tuesday
    // 09:00 AM PKT = 04:00 AM UTC
    const defaultDate = new Date('2026-10-20T04:00:00Z');
    const doctorId = overrides.doctorId || doctorUid;
    const patientId = overrides.patientId || patientUid;
    const status = overrides.status || 'scheduled';
    const timeSlot = overrides.timeSlot || '09:00 AM';
    const appointmentDate = overrides.appointmentDate || defaultDate;
    const durationMinutes = overrides.durationMinutes || 45;

    const data = {
      id: appointmentId,
      doctorId,
      patientId,
      doctorName: 'Dr. Test Doctor',
      patientName: 'Test Patient',
      status,
      timeSlot,
      appointmentDate: admin.firestore.Timestamp.fromDate(appointmentDate),
      durationMinutes,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    await db.collection('appointments').doc(appointmentId).set(data);

    if (!overrides.skipMirror) {
      const mirrorData = overrides.mirrorOverrides
        ? { ...data, ...overrides.mirrorOverrides }
        : data;
      await db
        .collection('patients')
        .doc(patientId)
        .collection('appointments')
        .doc(appointmentId)
        .set(mirrorData);
    }
  }

  // Helper to clean up an appointment and associated slot
  async function cleanAppointment(appointmentId: string, patientId: string, doctorId: string, slotKey?: string) {
    await db.collection('appointments').doc(appointmentId).delete();
    await db.collection('patients').doc(patientId).collection('appointments').doc(appointmentId).delete();
    if (slotKey) {
      await db.collection('bookedSlots').doc(doctorId).collection('slots').doc(slotKey).delete();
    }
  }

  // 1. Successful approval updates global and mirrored appointment documents atomically
  test('Scenario 1: Successful approval updates global and mirrored appointment documents atomically', async () => {
    const apptId = 'scen_1_appt';
    await seedAppointment(apptId, { timeSlot: '09:00 AM' });

    const result = await approveAppointmentHandler(
      { auth: { uid: doctorUid }, data: { appointmentId: apptId } },
      db
    );

    expect(result.success).toBe(true);
    expect(result.status).toBe('confirmed');

    const globalSnap = await db.collection('appointments').doc(apptId).get();
    const mirrorSnap = await db
      .collection('patients')
      .doc(patientUid)
      .collection('appointments')
      .doc(apptId)
      .get();

    expect(globalSnap.data()?.status).toBe('confirmed');
    expect(mirrorSnap.data()?.status).toBe('confirmed');
    expect(globalSnap.data()?.slotKey).toBe(result.slotKey);
    expect(mirrorSnap.data()?.slotKey).toBe(result.slotKey);

    await cleanAppointment(apptId, patientUid, doctorUid, result.slotKey);
  });

  // 2. Successful approval creates the canonical slot lock
  test('Scenario 2: Successful approval creates the canonical slot lock', async () => {
    const apptId = 'scen_2_appt';
    await seedAppointment(apptId, { timeSlot: '09:45 AM' });

    const result = await approveAppointmentHandler(
      { auth: { uid: doctorUid }, data: { appointmentId: apptId } },
      db
    );

    const expectedSlotKey = buildSlotKey('2026-10-20', '09:45 AM');
    expect(result.slotKey).toBe(expectedSlotKey);

    const slotSnap = await db
      .collection('bookedSlots')
      .doc(doctorUid)
      .collection('slots')
      .doc(expectedSlotKey)
      .get();

    expect(slotSnap.exists).toBe(true);
    expect(slotSnap.data()?.appointmentId).toBe(apptId);
    expect(slotSnap.data()?.patientId).toBe(patientUid);
    expect(slotSnap.data()?.bookedAt).toBeDefined();

    await cleanAppointment(apptId, patientUid, doctorUid, expectedSlotKey);
  });

  // 3. An already confirmed appointment is rejected
  test('Scenario 3: An already confirmed appointment is rejected', async () => {
    const apptId = 'scen_3_appt';
    await seedAppointment(apptId, { status: 'confirmed', timeSlot: '09:00 AM' });

    await expect(
      approveAppointmentHandler(
        { auth: { uid: doctorUid }, data: { appointmentId: apptId } },
        db
      )
    ).rejects.toThrow(/already confirmed/);

    await cleanAppointment(apptId, patientUid, doctorUid);
  });

  // 4. Missing or inconsistent patient mirror is rejected
  test('Scenario 4: Missing or inconsistent patient mirror is rejected', async () => {
    const apptMissingMirror = 'scen_4_missing';
    await seedAppointment(apptMissingMirror, { skipMirror: true, timeSlot: '09:00 AM' });

    await expect(
      approveAppointmentHandler(
        { auth: { uid: doctorUid }, data: { appointmentId: apptMissingMirror } },
        db
      )
    ).rejects.toThrow(/Patient appointment mirror does not exist/);

    const apptMismatchedMirror = 'scen_4_mismatched';
    await seedAppointment(apptMismatchedMirror, {
      timeSlot: '09:00 AM',
      mirrorOverrides: { timeSlot: '09:45 AM' }, // conflicts with authoritative 09:00 AM
    });

    await expect(
      approveAppointmentHandler(
        { auth: { uid: doctorUid }, data: { appointmentId: apptMismatchedMirror } },
        db
      )
    ).rejects.toThrow(/conflicts with authoritative timeSlot/);

    await cleanAppointment(apptMissingMirror, patientUid, doctorUid);
    await cleanAppointment(apptMismatchedMirror, patientUid, doctorUid);
  });

  // 5. Foreign-owned slot lock is rejected
  test('Scenario 5: Foreign-owned slot lock is rejected', async () => {
    const apptId = 'scen_5_appt';
    const slotKey = buildSlotKey('2026-10-20', '10:30 AM');

    // Seed slot lock owned by someone else
    await db
      .collection('bookedSlots')
      .doc(doctorUid)
      .collection('slots')
      .doc(slotKey)
      .set({
        appointmentId: 'foreign_appt_id',
        patientId: otherPatientUid,
        timeSlot: '10:30 AM',
        date: new Date('2026-10-20T04:00:00Z'),
        bookedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

    await seedAppointment(apptId, { timeSlot: '10:30 AM' });

    await expect(
      approveAppointmentHandler(
        { auth: { uid: doctorUid }, data: { appointmentId: apptId } },
        db
      )
    ).rejects.toThrow(/already booked/);

    await cleanAppointment(apptId, patientUid, doctorUid, slotKey);
  });

  // 6. Corrupted self-owned slot lock is rejected
  test('Scenario 6: Corrupted self-owned slot lock is rejected', async () => {
    const apptId = 'scen_6_appt';
    const slotKey = buildSlotKey('2026-10-20', '11:15 AM');

    // Missing patientId in slot lock
    await db
      .collection('bookedSlots')
      .doc(doctorUid)
      .collection('slots')
      .doc(slotKey)
      .set({
        appointmentId: apptId,
        // missing patientId
      });

    await seedAppointment(apptId, { timeSlot: '11:15 AM' });

    await expect(
      approveAppointmentHandler(
        { auth: { uid: doctorUid }, data: { appointmentId: apptId } },
        db
      )
    ).rejects.toThrow(/corrupt or missing ownership/);

    await cleanAppointment(apptId, patientUid, doctorUid, slotKey);
  });

  // 7. Valid existing self-owned lock retains its original bookedAt timestamp
  test('Scenario 7: Valid existing self-owned lock retains its original bookedAt timestamp', async () => {
    const apptId = 'scen_7_appt';
    const slotKey = buildSlotKey('2026-10-20', '12:00 PM');
    const originalTimestamp = admin.firestore.Timestamp.fromDate(new Date('2026-10-01T10:00:00Z'));

    await db
      .collection('bookedSlots')
      .doc(doctorUid)
      .collection('slots')
      .doc(slotKey)
      .set({
        appointmentId: apptId,
        patientId: patientUid,
        timeSlot: '12:00 PM',
        bookedAt: originalTimestamp,
      });

    await seedAppointment(apptId, { timeSlot: '12:00 PM' });

    await approveAppointmentHandler(
      { auth: { uid: doctorUid }, data: { appointmentId: apptId } },
      db
    );

    const slotSnap = await db
      .collection('bookedSlots')
      .doc(doctorUid)
      .collection('slots')
      .doc(slotKey)
      .get();

    expect(slotSnap.data()?.bookedAt.toMillis()).toBe(originalTimestamp.toMillis());

    await cleanAppointment(apptId, patientUid, doctorUid, slotKey);
  });

  // 8. Valid legacy doctor availability is supported
  test('Scenario 8: Valid legacy doctor availability is supported', async () => {
    const legacyDocUid = 'doc_legacy_1';
    await db.collection('users').doc(legacyDocUid).set({
      uid: legacyDocUid,
      role: 'doctor',
      name: 'Dr. Legacy',
    });

    // Valid legacy format: 3-letter day abbreviations and 12-hour slot array
    await db.collection('doctors').doc(legacyDocUid).set({
      uid: legacyDocUid,
      name: 'Dr. Legacy',
      isAvailable: true,
      availableDays: ['Mon', 'Tue', 'Wed'],
      availableSlots: ['09:00 AM', '10:00 AM', '11:00 AM'],
      scheduleRevision: 1,
    });

    const apptId = 'scen_8_appt';
    await seedAppointment(apptId, {
      doctorId: legacyDocUid,
      timeSlot: '09:00 AM',
    });

    const result = await approveAppointmentHandler(
      { auth: { uid: legacyDocUid }, data: { appointmentId: apptId } },
      db
    );

    expect(result.success).toBe(true);

    await cleanAppointment(apptId, patientUid, legacyDocUid, result.slotKey);
  });

  // 9. Invalid/unconfigured doctor availability fails closed
  test('Scenario 9: Invalid/unconfigured doctor availability fails closed', async () => {
    const unconfigDocUid = 'doc_unconfig_1';
    await db.collection('users').doc(unconfigDocUid).set({
      uid: unconfigDocUid,
      role: 'doctor',
      name: 'Dr. Unconfig',
    });

    await db.collection('doctors').doc(unconfigDocUid).set({
      uid: unconfigDocUid,
      name: 'Dr. Unconfig',
      isAvailable: false, // Explicitly marked unavailable
    });

    const apptId = 'scen_9_appt';
    await seedAppointment(apptId, { doctorId: unconfigDocUid, timeSlot: '09:00 AM' });

    await expect(
      approveAppointmentHandler(
        { auth: { uid: unconfigDocUid }, data: { appointmentId: apptId } },
        db
      )
    ).rejects.toThrow(/temporarily marked as unavailable/);

    await cleanAppointment(apptId, patientUid, unconfigDocUid);
  });

  // 10. Blocked date, blocked slot, and disabled weekday are rejected
  test('Scenario 10: Blocked date, blocked slot, and disabled weekday are rejected', async () => {
    // A: Blocked date (2026-12-25 is Friday, a working day, but in blockedDates)
    const apptBlockedDate = 'scen_10_date';
    await seedAppointment(apptBlockedDate, {
      appointmentDate: new Date('2026-12-25T04:00:00Z'),
      timeSlot: '09:00 AM',
    });

    await expect(
      approveAppointmentHandler(
        { auth: { uid: doctorUid }, data: { appointmentId: apptBlockedDate } },
        db
      )
    ).rejects.toThrow(/Date 2026-12-25 is blocked by doctor/);

    // B: Blocked slot (2026-10-20 at 02:15 PM is in blockedSlots)
    const apptBlockedSlot = 'scen_10_slot';
    await seedAppointment(apptBlockedSlot, {
      appointmentDate: new Date('2026-10-20T09:15:00Z'),
      timeSlot: '02:15 PM',
    });

    await expect(
      approveAppointmentHandler(
        { auth: { uid: doctorUid }, data: { appointmentId: apptBlockedSlot } },
        db
      )
    ).rejects.toThrow(/individually blocked by doctor/);

    // C: Disabled weekday (Sunday: 2026-10-25)
    const apptDisabledDay = 'scen_10_day';
    await seedAppointment(apptDisabledDay, {
      appointmentDate: new Date('2026-10-25T04:00:00Z'),
      timeSlot: '09:00 AM',
    });

    await expect(
      approveAppointmentHandler(
        { auth: { uid: doctorUid }, data: { appointmentId: apptDisabledDay } },
        db
      )
    ).rejects.toThrow(/Doctor is not available on sunday/);

    await cleanAppointment(apptBlockedDate, patientUid, doctorUid);
    await cleanAppointment(apptBlockedSlot, patientUid, doctorUid);
    await cleanAppointment(apptDisabledDay, patientUid, doctorUid);
  });

  // 11. Expired PKT appointment slots are rejected
  test('Scenario 11: Expired PKT appointment slots are rejected', async () => {
    // Past date: 2020-01-01 (Wednesday)
    const pastApptId = 'scen_11_past';
    await seedAppointment(pastApptId, {
      appointmentDate: new Date('2020-01-01T04:00:00Z'),
      timeSlot: '09:00 AM',
    });

    await expect(
      approveAppointmentHandler(
        { auth: { uid: doctorUid }, data: { appointmentId: pastApptId } },
        db
      )
    ).rejects.toThrow(/has expired/);

    await cleanAppointment(pastApptId, patientUid, doctorUid);
  });

  // 12. Cross-duration overlapping appointments are rejected
  test('Scenario 12: Cross-duration overlapping appointments are rejected', async () => {
    // Seed an existing confirmed appointment from 09:00 AM to 10:00 AM (60m)
    const confirmedApptId = 'scen_12_existing';
    await seedAppointment(confirmedApptId, {
      timeSlot: '09:00 AM',
      durationMinutes: 60,
      status: 'confirmed',
    });

    // New candidate appointment starts at 09:45 AM (overlaps with 09:00 - 10:00 during 09:45..10:00)
    // 09:45 AM is on-grid for the doctor's 45-minute schedule
    const candidateApptId = 'scen_12_candidate';
    await seedAppointment(candidateApptId, {
      timeSlot: '09:45 AM',
      durationMinutes: 45,
    });

    await expect(
      approveAppointmentHandler(
        { auth: { uid: doctorUid }, data: { appointmentId: candidateApptId } },
        db
      )
    ).rejects.toThrow(/overlaps with confirmed appointment/);

    await cleanAppointment(confirmedApptId, patientUid, doctorUid);
    await cleanAppointment(candidateApptId, patientUid, doctorUid);
  });

  // 13. Two concurrent approvals for the same slot cannot both succeed
  test('Scenario 13: Two concurrent approvals for the same slot cannot both succeed', async () => {
    const apptA = 'scen_13_appt_a';
    const apptB = 'scen_13_appt_b';

    await seedAppointment(apptA, { timeSlot: '03:00 PM' });
    await seedAppointment(apptB, { timeSlot: '03:00 PM' });

    const docBefore = (await db.collection('doctors').doc(doctorUid).get()).data();
    const prevRev = docBefore?.scheduleRevision || 1;

    // Execute concurrently
    const [resA, resB] = await Promise.allSettled([
      approveAppointmentHandler({ auth: { uid: doctorUid }, data: { appointmentId: apptA } }, db),
      approveAppointmentHandler({ auth: { uid: doctorUid }, data: { appointmentId: apptB } }, db),
    ]);

    // Exactly one must succeed, one must fail
    const succeeded = [resA, resB].filter((r) => r.status === 'fulfilled');
    const rejected = [resA, resB].filter((r) => r.status === 'rejected');

    expect(succeeded.length).toBe(1);
    expect(rejected.length).toBe(1);

    const winningApptId = (resA.status === 'fulfilled') ? apptA : apptB;
    const losingApptId = (resA.status === 'fulfilled') ? apptB : apptA;

    // Verify winning appointment is confirmed
    const winningSnap = await db.collection('appointments').doc(winningApptId).get();
    expect(winningSnap.data()?.status).toBe('confirmed');

    // Verify losing appointment remains unchanged in 'scheduled' status
    const losingSnap = await db.collection('appointments').doc(losingApptId).get();
    const losingMirror = await db.collection('patients').doc(patientUid).collection('appointments').doc(losingApptId).get();
    expect(losingSnap.data()?.status).toBe('scheduled');
    expect(losingMirror.data()?.status).toBe('scheduled');

    // Verify slot lock is owned strictly by the winner (no duplicate locks)
    const slotKey = buildSlotKey('2026-10-20', '03:00 PM');
    const slotSnap = await db.collection('bookedSlots').doc(doctorUid).collection('slots').doc(slotKey).get();
    expect(slotSnap.exists).toBe(true);
    expect(slotSnap.data()?.appointmentId).toBe(winningApptId);

    // Verify doctor revision incremented by exactly 1
    const docAfter = (await db.collection('doctors').doc(doctorUid).get()).data();
    expect(docAfter?.scheduleRevision).toBe(prevRev + 1);

    await cleanAppointment(apptA, patientUid, doctorUid, slotKey);
    await cleanAppointment(apptB, patientUid, doctorUid);
  });

  // 14. Two concurrent approvals for different overlapping intervals cannot both succeed
  test('Scenario 14: Two concurrent approvals for different overlapping intervals cannot both succeed', async () => {
    // Both 09:00 AM and 09:45 AM are valid on-grid slots for 45-min schedule
    // Appt 1: 09:00 AM with duration 60m (09:00 to 10:00)
    // Appt 2: 09:45 AM with duration 45m (09:45 to 10:30)
    // Overlap interval: 09:45 to 10:00
    const apptOverlap1 = 'scen_14_appt_1';
    const apptOverlap2 = 'scen_14_appt_2';

    await seedAppointment(apptOverlap1, { timeSlot: '09:00 AM', durationMinutes: 60 });
    await seedAppointment(apptOverlap2, { timeSlot: '09:45 AM', durationMinutes: 45 });

    const docBefore = (await db.collection('doctors').doc(doctorUid).get()).data();
    const prevRev = docBefore?.scheduleRevision || 1;

    const [res1, res2] = await Promise.allSettled([
      approveAppointmentHandler({ auth: { uid: doctorUid }, data: { appointmentId: apptOverlap1 } }, db),
      approveAppointmentHandler({ auth: { uid: doctorUid }, data: { appointmentId: apptOverlap2 } }, db),
    ]);

    const succeeded = [res1, res2].filter((r) => r.status === 'fulfilled');
    const rejected = [res1, res2].filter((r) => r.status === 'rejected');

    expect(succeeded.length).toBe(1);
    expect(rejected.length).toBe(1);

    const winningApptId = (res1.status === 'fulfilled') ? apptOverlap1 : apptOverlap2;
    const losingApptId = (res1.status === 'fulfilled') ? apptOverlap2 : apptOverlap1;

    // Verify winner is confirmed
    const winningSnap = await db.collection('appointments').doc(winningApptId).get();
    expect(winningSnap.data()?.status).toBe('confirmed');

    // Verify loser is unchanged
    const losingSnap = await db.collection('appointments').doc(losingApptId).get();
    const losingMirror = await db.collection('patients').doc(patientUid).collection('appointments').doc(losingApptId).get();
    expect(losingSnap.data()?.status).toBe('scheduled');
    expect(losingMirror.data()?.status).toBe('scheduled');

    // Verify doctor revision incremented by exactly 1
    const docAfter = (await db.collection('doctors').doc(doctorUid).get()).data();
    expect(docAfter?.scheduleRevision).toBe(prevRev + 1);

    const slotKey1 = buildSlotKey('2026-10-20', '09:00 AM');
    const slotKey2 = buildSlotKey('2026-10-20', '09:45 AM');
    await cleanAppointment(apptOverlap1, patientUid, doctorUid, slotKey1);
    await cleanAppointment(apptOverlap2, patientUid, doctorUid, slotKey2);
  });

  // 15. Failed transactions leave appointment, mirror, doctor revision, and slot lock unchanged
  test('Scenario 15: Failed transactions leave appointment, mirror, doctor revision, and slot lock unchanged', async () => {
    const apptId = 'scen_15_appt';
    await seedAppointment(apptId, {
      timeSlot: '09:00 AM',
      mirrorOverrides: { status: 'cancelled' }, // Intentional mismatch to fail tx
    });

    const docBefore = (await db.collection('doctors').doc(doctorUid).get()).data();
    const prevRev = docBefore?.scheduleRevision;

    await expect(
      approveAppointmentHandler(
        { auth: { uid: doctorUid }, data: { appointmentId: apptId } },
        db
      )
    ).rejects.toThrow(/does not match global status/);

    // Verify state is clean
    const apptAfter = (await db.collection('appointments').doc(apptId).get()).data();
    const docAfter = (await db.collection('doctors').doc(doctorUid).get()).data();
    const slotKey = buildSlotKey('2026-10-20', '09:00 AM');
    const slotSnap = await db.collection('bookedSlots').doc(doctorUid).collection('slots').doc(slotKey).get();

    expect(apptAfter?.status).toBe('scheduled');
    expect(docAfter?.scheduleRevision).toBe(prevRev);
    expect(slotSnap.exists).toBe(false);

    await cleanAppointment(apptId, patientUid, doctorUid);
  });

  // 16. Completed historical slot locks are not modified
  test('Scenario 16: Completed historical slot locks are not modified', async () => {
    const apptId = 'scen_16_completed';
    const slotKey = buildSlotKey('2026-10-20', '03:45 PM');
    const completedTimestamp = admin.firestore.Timestamp.fromDate(new Date('2026-10-01T12:00:00Z'));

    await db
      .collection('bookedSlots')
      .doc(doctorUid)
      .collection('slots')
      .doc(slotKey)
      .set({
        appointmentId: apptId,
        patientId: patientUid,
        timeSlot: '03:45 PM',
        status: 'completed',
        bookedAt: completedTimestamp,
      });

    await seedAppointment(apptId, {
      status: 'completed',
      timeSlot: '03:45 PM',
    });

    await expect(
      approveAppointmentHandler(
        { auth: { uid: doctorUid }, data: { appointmentId: apptId } },
        db
      )
    ).rejects.toThrow(/terminal status "completed"/);

    const slotAfter = await db
      .collection('bookedSlots')
      .doc(doctorUid)
      .collection('slots')
      .doc(slotKey)
      .get();

    expect(slotAfter.data()?.status).toBe('completed');
    expect(slotAfter.data()?.bookedAt.toMillis()).toBe(completedTimestamp.toMillis());

    await cleanAppointment(apptId, patientUid, doctorUid, slotKey);
  });

  // 17. Doctor updates availability via trusted Cloud Function in real Firestore transaction
  test('Scenario 17: Doctor updates schedule through updateDoctorAvailabilityHandler inside real Firestore transaction', async () => {
    const docBefore = (await db.collection('doctors').doc(doctorUid).get()).data();
    const prevRev = docBefore?.scheduleRevision || 1;

    const newAvailability = {
      slotDurationMinutes: 30,
      weeklySchedule: {
        monday: { enabled: true, startTime: '08:30', endTime: '16:30' },
        tuesday: { enabled: true, startTime: '08:30', endTime: '16:30' },
        wednesday: { enabled: true, startTime: '08:30', endTime: '16:30' },
        thursday: { enabled: true, startTime: '08:30', endTime: '16:30' },
        friday: { enabled: true, startTime: '08:30', endTime: '16:30' },
        saturday: { enabled: false, startTime: '09:00', endTime: '17:00' },
        sunday: { enabled: false, startTime: '09:00', endTime: '17:00' },
      },
      blockedDates: ['2026-11-15'],
      blockedSlots: ['2026-10-21_10:00 AM'],
    };

    const result = await updateDoctorAvailabilityHandler(
      {
        auth: { uid: doctorUid },
        data: { availability: newAvailability, isAvailable: true },
      },
      db
    );

    expect(result.success).toBe(true);
    expect(result.doctorId).toBe(doctorUid);
    expect(result.scheduleRevision).toBe(prevRev + 1);

    const docAfter = (await db.collection('doctors').doc(doctorUid).get()).data();
    expect(docAfter?.scheduleRevision).toBe(prevRev + 1);
    expect(docAfter?.availability.slotDurationMinutes).toBe(30);
    expect(docAfter?.availability.blockedDates).toContain('2026-11-15');
    expect(docAfter?.availability.blockedSlots).toContain('2026-10-21_10:00 AM');
    expect(docAfter?.availableDays).toContain('Mon');
    expect(docAfter?.availableDays).toContain('Fri');
    expect(docAfter?.availableSlots).toContain('08:30 AM');
  });

  // 18. Non-doctor caller fails closed without modifying doctor profile or revision
  test('Scenario 18: Non-doctor caller fails closed without modifying doctor profile or revision', async () => {
    const docBefore = (await db.collection('doctors').doc(doctorUid).get()).data();
    const prevRev = docBefore?.scheduleRevision;

    await expect(
      updateDoctorAvailabilityHandler(
        {
          auth: { uid: patientUid }, // Patient trying to update
          data: {
            availability: validAvailability,
          },
        },
        db
      )
    ).rejects.toThrow(/not authorized as a doctor/);

    const docAfter = (await db.collection('doctors').doc(doctorUid).get()).data();
    expect(docAfter?.scheduleRevision).toBe(prevRev);
    expect(docAfter?.availability.slotDurationMinutes).toBe(docBefore?.availability.slotDurationMinutes);
  });

  // 19. Concurrency guard: confirmed appointments cannot be invalidated by schedule updates
  test('Scenario 19: Confirmed appointments cannot be invalidated by changing weekdays, hours, or blocking', async () => {
    // 1. Seed a confirmed appointment slot for Tuesday 2026-10-20 at 09:00 AM
    const confirmedSlotKey = '2026-10-20_09:00 AM';
    await db
      .collection('bookedSlots')
      .doc(doctorUid)
      .collection('slots')
      .doc(confirmedSlotKey)
      .set({
        appointmentId: 'appt_concurrency_guard',
        patientId: patientUid,
        date: '2026-10-20',
        time: '09:00 AM',
        status: 'confirmed',
        bookedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

    const docBefore = (await db.collection('doctors').doc(doctorUid).get()).data();
    const prevRev = docBefore?.scheduleRevision;

    // Attempt A: Block the confirmed date (2026-10-20)
    await expect(
      updateDoctorAvailabilityHandler(
        {
          auth: { uid: doctorUid },
          data: {
            availability: {
              ...validAvailability,
              blockedDates: ['2026-10-20'],
            },
          },
        },
        db
      )
    ).rejects.toThrow(/Cannot block date 2026-10-20/);

    // Attempt B: Block the confirmed slot (2026-10-20_09:00 AM)
    await expect(
      updateDoctorAvailabilityHandler(
        {
          auth: { uid: doctorUid },
          data: {
            availability: {
              ...validAvailability,
              blockedSlots: [confirmedSlotKey],
            },
          },
        },
        db
      )
    ).rejects.toThrow(/Cannot block slot 2026-10-20_09:00 AM/);

    // Attempt C: Disable Tuesday
    await expect(
      updateDoctorAvailabilityHandler(
        {
          auth: { uid: doctorUid },
          data: {
            availability: {
              ...validAvailability,
              weeklySchedule: {
                ...validAvailability.weeklySchedule,
                tuesday: { enabled: false, startTime: '09:00', endTime: '17:00' },
              },
            },
          },
        },
        db
      )
    ).rejects.toThrow(/Cannot disable tuesday/);

    // Attempt D: Change hours so that 09:00 AM falls outside (e.g. 10:00 to 17:00)
    await expect(
      updateDoctorAvailabilityHandler(
        {
          auth: { uid: doctorUid },
          data: {
            availability: {
              ...validAvailability,
              weeklySchedule: {
                ...validAvailability.weeklySchedule,
                tuesday: { enabled: true, startTime: '10:00', endTime: '17:00' },
              },
            },
          },
        },
        db
      )
    ).rejects.toThrow(/falls outside new working hours/);

    // Verify state was NOT modified by any of the failed transactions
    const docAfter = (await db.collection('doctors').doc(doctorUid).get()).data();
    expect(docAfter?.scheduleRevision).toBe(prevRev);
    expect(docAfter?.availability.slotDurationMinutes).toBe(docBefore?.availability.slotDurationMinutes);

    // Clean up confirmed slot
    await db
      .collection('bookedSlots')
      .doc(doctorUid)
      .collection('slots')
      .doc(confirmedSlotKey)
      .delete();
  });

  // 20. Concurrent transactions do not overwrite each other
  test('Scenario 20: Concurrent appointment approval and schedule update both commit safely', async () => {
    const apptId = 'scen_20_concurrent_appt';
    // Use Thursday 09:00 AM for approval
    const thursdayDate = new Date('2026-10-22T04:00:00Z');
    await seedAppointment(apptId, {
      appointmentDate: thursdayDate,
      timeSlot: '09:00 AM',
    });

    const docBefore = (await db.collection('doctors').doc(doctorUid).get()).data();
    const prevRev = docBefore?.scheduleRevision;

    // Schedule update that does NOT conflict with Thursday 09:00 AM (changes duration to 45 min, blocks a different date)
    const safeSchedule = {
      slotDurationMinutes: 45,
      weeklySchedule: validAvailability.weeklySchedule,
      blockedDates: ['2026-11-20'],
      blockedSlots: [],
    };

    // Execute concurrently
    const [approvalResult, availResult] = await Promise.all([
      approveAppointmentHandler(
        { auth: { uid: doctorUid }, data: { appointmentId: apptId } },
        db
      ),
      updateDoctorAvailabilityHandler(
        { auth: { uid: doctorUid }, data: { availability: safeSchedule } },
        db
      ),
    ]);

    expect(approvalResult.success).toBe(true);
    expect(availResult.success).toBe(true);

    // The scheduleRevision should have incremented twice: once by approval, once by availability update
    const docAfter = (await db.collection('doctors').doc(doctorUid).get()).data();
    expect(docAfter?.scheduleRevision).toBe(prevRev + 2);

    // Verify appointment was confirmed
    const apptAfter = (await db.collection('appointments').doc(apptId).get()).data();
    expect(apptAfter?.status).toBe('confirmed');

    // Verify schedule update took effect
    expect(docAfter?.availability.blockedDates).toContain('2026-11-20');

    await cleanAppointment(apptId, patientUid, doctorUid, '2026-10-22_09:00 AM');
  });
});
