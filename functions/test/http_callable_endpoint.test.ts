// functions/test/http_callable_endpoint.test.ts

import * as admin from 'firebase-admin';

const PROJECT_ID = 'demo-no-project';
const FUNCTIONS_URL = 'http://127.0.0.1:5001/demo-no-project/us-central1/approveAppointment';
const AVAILABILITY_URL = 'http://127.0.0.1:5001/demo-no-project/us-central1/updateDoctorAvailability';
const AUTH_URL = 'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=fake-key';

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
}
if (!process.env.FIREBASE_AUTH_EMULATOR_HOST) {
  process.env.FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099';
}

if (!admin.apps.length) {
  admin.initializeApp({ projectId: PROJECT_ID });
}

const db = admin.firestore();
const auth = admin.auth();

describe('Phase 2D.2A HTTP Callable Endpoint Wire Protocol Tests', () => {
  const doctorUid = 'http_doc_1';
  const patientUid = 'http_patient_1';
  const foreignDocUid = 'http_doc_2';

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
    blockedDates: [],
    blockedSlots: [],
  };

  let doctorIdToken: string;
  let patientIdToken: string;
  let foreignDocIdToken: string;

  // Helper to exchange custom token for ID token via Auth emulator REST API
  async function getIdToken(uid: string): Promise<string> {
    const customToken = await auth.createCustomToken(uid);
    const resp = await fetch(AUTH_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ token: customToken, returnSecureToken: true }),
    });
    const data: any = await resp.json();
    if (!data.idToken) {
      throw new Error(`Failed to exchange custom token for ID token: ${JSON.stringify(data)}`);
    }
    return data.idToken;
  }

  beforeAll(async () => {
    // 1. Seed doctor and patient user records in Firestore
    await db.collection('users').doc(doctorUid).set({
      uid: doctorUid,
      role: 'doctor',
      name: 'Dr. Endpoint Tester',
      email: 'doctor@endpoint.com',
    });

    await db.collection('doctors').doc(doctorUid).set({
      uid: doctorUid,
      name: 'Dr. Endpoint Tester',
      isAvailable: true,
      scheduleRevision: 1,
      availability: validAvailability,
    });

    await db.collection('users').doc(patientUid).set({
      uid: patientUid,
      role: 'patient',
      name: 'Endpoint Patient',
      email: 'patient@endpoint.com',
    });

    await db.collection('users').doc(foreignDocUid).set({
      uid: foreignDocUid,
      role: 'doctor',
      name: 'Dr. Foreign Doctor',
      email: 'foreigndoc@endpoint.com',
    });

    await db.collection('doctors').doc(foreignDocUid).set({
      uid: foreignDocUid,
      name: 'Dr. Foreign Doctor',
      isAvailable: true,
      scheduleRevision: 1,
      availability: validAvailability,
    });

    // 2. Obtain ID tokens from Auth emulator
    doctorIdToken = await getIdToken(doctorUid);
    patientIdToken = await getIdToken(patientUid);
    foreignDocIdToken = await getIdToken(foreignDocUid);
  });

  async function seedAppointment(appointmentId: string, timeSlot = '09:00 AM') {
    const appointmentDate = new Date('2026-10-20T04:00:00Z'); // Tuesday 09:00 AM PKT
    const data = {
      id: appointmentId,
      doctorId: doctorUid,
      patientId: patientUid,
      doctorName: 'Dr. Endpoint Tester',
      patientName: 'Endpoint Patient',
      status: 'scheduled',
      timeSlot,
      appointmentDate: admin.firestore.Timestamp.fromDate(appointmentDate),
      durationMinutes: 45,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    await db.collection('appointments').doc(appointmentId).set(data);
    await db
      .collection('patients')
      .doc(patientUid)
      .collection('appointments')
      .doc(appointmentId)
      .set(data);
  }

  // 1. Unauthenticated requests are rejected
  test('1. Unauthenticated request over HTTP protocol is rejected with 401 UNAUTHENTICATED', async () => {
    const resp = await fetch(FUNCTIONS_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ data: { appointmentId: 'http_appt_unauth' } }),
    });

    expect(resp.status).toBe(401);
    const body: any = await resp.json();
    expect(body.error).toBeDefined();
    expect(body.error.status).toBe('UNAUTHENTICATED');
  });

  // 2. Unauthorized patient caller is rejected
  test('2. Unauthorized user request (patient role) over HTTP protocol is rejected with 403 PERMISSION_DENIED', async () => {
    const apptId = 'http_appt_patient';
    await seedAppointment(apptId);

    const resp = await fetch(FUNCTIONS_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${patientIdToken}`,
      },
      body: JSON.stringify({ data: { appointmentId: apptId } }),
    });

    expect(resp.status).toBe(403);
    const body: any = await resp.json();
    expect(body.error).toBeDefined();
    expect(body.error.status).toBe('PERMISSION_DENIED');
  });

  // 3. Unauthorized foreign doctor caller is rejected
  test('3. Foreign doctor caller attempting approval is rejected with 403 PERMISSION_DENIED', async () => {
    const apptId = 'http_appt_foreign';
    await seedAppointment(apptId, '09:45 AM');

    const resp = await fetch(FUNCTIONS_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${foreignDocIdToken}`,
      },
      body: JSON.stringify({ data: { appointmentId: apptId } }),
    });

    expect(resp.status).toBe(403);
    const body: any = await resp.json();
    expect(body.error).toBeDefined();
    expect(body.error.status).toBe('PERMISSION_DENIED');
  });

  // 4. Authenticated assigned doctor successfully approves valid scheduled appointment
  test('4. Authenticated assigned doctor successfully approves scheduled appointment over HTTP protocol', async () => {
    const apptId = 'http_appt_success';
    await seedAppointment(apptId, '10:30 AM');

    const resp = await fetch(FUNCTIONS_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${doctorIdToken}`,
      },
      body: JSON.stringify({ data: { appointmentId: apptId } }),
    });

    expect(resp.status).toBe(200);
    const body: any = await resp.json();
    expect(body.result).toBeDefined();
    expect(body.result.success).toBe(true);
    expect(body.result.status).toBe('confirmed');
    expect(body.result.slotKey).toBe('2026-10-20_10:30 AM');

    // Verify global appointment update
    const globalSnap = await db.collection('appointments').doc(apptId).get();
    expect(globalSnap.data()?.status).toBe('confirmed');
    expect(globalSnap.data()?.slotKey).toBe('2026-10-20_10:30 AM');

    // Verify patient mirror update
    const mirrorSnap = await db
      .collection('patients')
      .doc(patientUid)
      .collection('appointments')
      .doc(apptId)
      .get();
    expect(mirrorSnap.data()?.status).toBe('confirmed');
    expect(mirrorSnap.data()?.slotKey).toBe('2026-10-20_10:30 AM');

    // Verify canonical slot lock
    const slotSnap = await db
      .collection('bookedSlots')
      .doc(doctorUid)
      .collection('slots')
      .doc('2026-10-20_10:30 AM')
      .get();
    expect(slotSnap.exists).toBe(true);
    expect(slotSnap.data()?.appointmentId).toBe(apptId);
    expect(slotSnap.data()?.patientId).toBe(patientUid);
  });

  // 5. Conflicting / already confirmed appointment returns error
  test('5. Callable endpoint returns 400 FAILED_PRECONDITION for already-confirmed appointment', async () => {
    const apptId = 'http_appt_success'; // Same appointment as test 4, now confirmed

    const resp = await fetch(FUNCTIONS_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${doctorIdToken}`,
      },
      body: JSON.stringify({ data: { appointmentId: apptId } }),
    });

    expect(resp.status).toBe(400);
    const body: any = await resp.json();
    expect(body.error).toBeDefined();
    expect(body.error.status).toBe('FAILED_PRECONDITION');
    expect(body.error.message).toMatch(/already confirmed/);
  });

  // 6. updateDoctorAvailability: Unauthenticated requests rejected with 401
  test('6. updateDoctorAvailability: Unauthenticated request over HTTP protocol is rejected with 401 UNAUTHENTICATED', async () => {
    const resp = await fetch(AVAILABILITY_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ data: { availability: validAvailability } }),
    });

    expect(resp.status).toBe(401);
    const body: any = await resp.json();
    expect(body.error).toBeDefined();
    expect(body.error.status).toBe('UNAUTHENTICATED');
  });

  // 7. updateDoctorAvailability: Patient caller rejected with 403
  test('7. updateDoctorAvailability: Patient caller over HTTP protocol is rejected with 403 PERMISSION_DENIED', async () => {
    const resp = await fetch(AVAILABILITY_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${patientIdToken}`,
      },
      body: JSON.stringify({ data: { availability: validAvailability } }),
    });

    expect(resp.status).toBe(403);
    const body: any = await resp.json();
    expect(body.error).toBeDefined();
    expect(body.error.status).toBe('PERMISSION_DENIED');
  });

  // 8. updateDoctorAvailability: Authenticated doctor updates schedule successfully
  test('8. updateDoctorAvailability: Authenticated doctor updates schedule via HTTP wire protocol', async () => {
    const docBefore = (await db.collection('doctors').doc(doctorUid).get()).data();
    const prevRev = docBefore?.scheduleRevision || 1;

    const updatedSchedule = {
      slotDurationMinutes: 60,
      weeklySchedule: validAvailability.weeklySchedule,
      blockedDates: ['2026-12-31'],
      blockedSlots: [],
    };

    const resp = await fetch(AVAILABILITY_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${doctorIdToken}`,
      },
      body: JSON.stringify({
        data: {
          availability: updatedSchedule,
          isAvailable: true,
        },
      }),
    });

    expect(resp.status).toBe(200);
    const body: any = await resp.json();
    expect(body.result).toBeDefined();
    expect(body.result.success).toBe(true);
    expect(body.result.doctorId).toBe(doctorUid);
    expect(body.result.scheduleRevision).toBe(prevRev + 1);

    const docAfter = (await db.collection('doctors').doc(doctorUid).get()).data();
    expect(docAfter?.scheduleRevision).toBe(prevRev + 1);
    expect(docAfter?.availability.slotDurationMinutes).toBe(60);
    expect(docAfter?.availability.blockedDates).toContain('2026-12-31');
  });
});
