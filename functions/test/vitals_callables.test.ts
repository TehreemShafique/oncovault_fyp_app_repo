// functions/test/vitals_callables.test.ts

import * as admin from 'firebase-admin';
import { assignNurseHandler, revokeNurseAssignmentHandler } from '../src/assign_nurse';
import { recordVitalObservationHandler } from '../src/record_vital_observation';

const PROJECT_ID = process.env.GCLOUD_PROJECT || 'demo-no-project';

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
}

if (!admin.apps.length) {
  admin.initializeApp({ projectId: PROJECT_ID });
}

const db = admin.firestore();

jest.setTimeout(60000);

describe('Phase 3A Nurse Vitals & Assignment Callable Security Tests', () => {
  const adminUid = 'admin_call_test';
  const doctorUid = 'doc_call_test';
  const unauthorizedDoctorUid = 'doc_unauth_test';
  const nurseUid = 'nurse_call_test';
  const targetNurseUid = 'nurse_target_test';
  const suspendedNurseUid = 'nurse_suspended_test';
  const patientUid = 'patient_call_test';
  const foreignPatientUid = 'patient_foreign_test';

  beforeAll(async () => {
    // Seed users atomically in a single batch
    const batch = db.batch();

    batch.set(db.collection('users').doc(adminUid), {
      uid: adminUid,
      role: 'admin',
      name: 'Hospital Admin',
      hospitalId: 'Oncology Ward 3A',
    });

    batch.set(db.collection('users').doc(doctorUid), {
      uid: doctorUid,
      role: 'doctor',
      name: 'Dr. Oncologist',
      hospitalId: 'Oncology Ward 3A',
    });

    batch.set(db.collection('users').doc(unauthorizedDoctorUid), {
      uid: unauthorizedDoctorUid,
      role: 'doctor',
      name: 'Dr. Stranger',
      hospitalId: 'Oncology Ward 3A',
    });

    batch.set(db.collection('users').doc(nurseUid), {
      uid: nurseUid,
      role: 'nurse',
      name: 'Nurse Ayesha',
      hospitalId: 'Oncology Ward 3A',
    });

    batch.set(db.collection('users').doc(targetNurseUid), {
      uid: targetNurseUid,
      role: 'nurse',
      name: 'Nurse Fatima',
      hospitalId: 'Oncology Ward 3A',
    });

    batch.set(db.collection('users').doc(suspendedNurseUid), {
      uid: suspendedNurseUid,
      role: 'nurse',
      name: 'Nurse Suspended',
      status: 'suspended',
      hospitalId: 'Oncology Ward 3A',
    });

    batch.set(db.collection('users').doc(patientUid), {
      uid: patientUid,
      role: 'patient',
      name: 'Tariq Mehmood',
      hospitalId: 'Oncology Ward 3A',
    });

    batch.set(db.collection('patients').doc(patientUid), {
      uid: patientUid,
      name: 'Tariq Mehmood',
      medicalId: 'OV-99901',
      hospitalId: 'Oncology Ward 3A',
    });

    batch.set(db.collection('appointments').doc('appt_auth_test'), {
      id: 'appt_auth_test',
      doctorId: doctorUid,
      patientId: patientUid,
      status: 'confirmed',
    });

    await batch.commit();
  });

  // ─── 1. ASSIGN NURSE SECURITY & PERMISSION TESTS ───────────

  test('1. assignNurse rejects unauthenticated caller', async () => {
    await expect(
      assignNurseHandler({ auth: undefined, data: { nurseId: targetNurseUid, patientId: patientUid } }, db)
    ).rejects.toThrow(/User must be authenticated/);
  });

  test('2. assignNurse rejects nurse caller attempting assignment or self-assignment', async () => {
    await expect(
      assignNurseHandler(
        { auth: { uid: nurseUid }, data: { nurseId: targetNurseUid, patientId: patientUid } },
        db
      )
    ).rejects.toThrow(/Only hospital administrators or authorized physicians/);

    await expect(
      assignNurseHandler(
        { auth: { uid: nurseUid }, data: { nurseId: nurseUid, patientId: patientUid } },
        db
      )
    ).rejects.toThrow();
  });

  test('3. assignNurse rejects doctor not authorized to treat target patient', async () => {
    await expect(
      assignNurseHandler(
        { auth: { uid: unauthorizedDoctorUid }, data: { nurseId: targetNurseUid, patientId: patientUid } },
        db
      )
    ).rejects.toThrow(/does not hold active care authorization|not authorized to treat/);
  });

  test('4. assignNurse succeeds for doctor authorized via confirmed appointment or consent', async () => {
    const res = await assignNurseHandler(
      {
        auth: { uid: doctorUid },
        data: {
          nurseId: targetNurseUid,
          patientId: patientUid,
          hospitalId: 'Oncology Ward 3A',
          notes: 'Assigned for chemotherapy vitals monitoring',
        },
      },
      db
    );

    expect(res.success).toBe(true);
    expect(res.status).toBe('active');
    expect(res.assignmentId).toBe(`${targetNurseUid}_${patientUid}`);

    const snap = await db.collection('nurse_patient_assignments').doc(res.assignmentId).get();
    expect(snap.exists).toBe(true);
    expect(snap.data()?.status).toBe('active');
    expect(snap.data()?.assignedBy).toBe(doctorUid);
  });

  test('5. assignNurse succeeds for hospital admin across hospital scope', async () => {
    const res = await assignNurseHandler(
      {
        auth: { uid: adminUid },
        data: {
          nurseId: nurseUid,
          patientId: patientUid,
          hospitalId: 'Oncology Ward 3A',
          notes: 'Admin assignment for inpatient monitoring',
        },
      },
      db
    );

    expect(res.success).toBe(true);
    expect(res.status).toBe('active');
    expect(res.assignmentId).toBe(`${nurseUid}_${patientUid}`);
  });

  test('6. assignNurse rejects if target nurse does not exist or is not active', async () => {
    await expect(
      assignNurseHandler(
        { auth: { uid: adminUid }, data: { nurseId: 'nonexistent_nurse', patientId: patientUid } },
        db
      )
    ).rejects.toThrow(/does not exist/);

    await expect(
      assignNurseHandler(
        { auth: { uid: adminUid }, data: { nurseId: suspendedNurseUid, patientId: patientUid } },
        db
      )
    ).rejects.toThrow(/is not active/);
  });

  test('7. assignNurse rejects if target patient does not exist', async () => {
    await expect(
      assignNurseHandler(
        { auth: { uid: adminUid }, data: { nurseId: targetNurseUid, patientId: 'nonexistent_patient' } },
        db
      )
    ).rejects.toThrow(/Patient .* does not exist/);
  });

  test('8. assignNurse rejects cross-hospital assignment for non-admin doctors', async () => {
    await expect(
      assignNurseHandler(
        {
          auth: { uid: doctorUid },
          data: {
            nurseId: targetNurseUid,
            patientId: patientUid,
            hospitalId: 'Cardiology Ward 9B', // Mismatched hospital scope
          },
        },
        db
      )
    ).rejects.toThrow(/Cross-hospital assignment is not permitted/);
  });

  // ─── 2. REVOKE NURSE ASSIGNMENT TESTS ─────────────────────

  test('9. revokeNurseAssignment rejects unauthenticated caller or nurse caller', async () => {
    await expect(
      revokeNurseAssignmentHandler(
        { auth: undefined, data: { nurseId: targetNurseUid, patientId: patientUid } },
        db
      )
    ).rejects.toThrow(/User must be authenticated/);

    await expect(
      revokeNurseAssignmentHandler(
        { auth: { uid: nurseUid }, data: { nurseId: targetNurseUid, patientId: patientUid } },
        db
      )
    ).rejects.toThrow(/Only administrators or physicians/);
  });

  test('10. revokeNurseAssignment succeeds for authorized doctor or admin', async () => {
    const res = await revokeNurseAssignmentHandler(
      {
        auth: { uid: doctorUid },
        data: {
          nurseId: targetNurseUid,
          patientId: patientUid,
          reason: 'Shift concluded',
        },
      },
      db
    );

    expect(res.success).toBe(true);
    expect(res.status).toBe('revoked');

    const snap = await db.collection('nurse_patient_assignments').doc(`${targetNurseUid}_${patientUid}`).get();
    expect(snap.data()?.status).toBe('revoked');
    expect(snap.data()?.revocationReason).toBe('Shift concluded');
  });

  // ─── 3. RECORD VITAL OBSERVATION SECURITY & VALIDATION TESTS ─

  test('11. recordVitalObservation rejects unauthenticated caller', async () => {
    await expect(
      recordVitalObservationHandler(
        {
          auth: undefined,
          data: {
            patientId: patientUid,
            systolicBp: 120,
            diastolicBp: 80,
            pulseRate: 72,
            temperature: 37.0,
            respiratoryRate: 16,
            oxygenSaturation: 98,
          },
        },
        db
      )
    ).rejects.toThrow(/User must be authenticated/);
  });

  test('12. recordVitalObservation rejects nurse without active care assignment (revoked or never assigned)', async () => {
    // targetNurseUid was revoked in test 10
    await expect(
      recordVitalObservationHandler(
        {
          auth: { uid: targetNurseUid },
          data: {
            patientId: patientUid,
            systolicBp: 120,
            diastolicBp: 80,
            pulseRate: 72,
            temperature: 37.0,
            respiratoryRate: 16,
            oxygenSaturation: 98,
          },
        },
        db
      )
    ).rejects.toThrow(/Nurse is not actively assigned/);
  });

  test('13. recordVitalObservation rejects out-of-range clinical measurements server-side', async () => {
    // nurseUid is actively assigned from test 5
    // Systolic 290 exceeds max 250
    await expect(
      recordVitalObservationHandler(
        {
          auth: { uid: nurseUid },
          data: {
            patientId: patientUid,
            systolicBp: 290,
            diastolicBp: 80,
            pulseRate: 72,
            temperature: 37.0,
            respiratoryRate: 16,
            oxygenSaturation: 98,
          },
        },
        db
      )
    ).rejects.toThrow(/Systolic BP must be a numeric value between 60 and 250/);

    // Diastolic >= Systolic
    await expect(
      recordVitalObservationHandler(
        {
          auth: { uid: nurseUid },
          data: {
            patientId: patientUid,
            systolicBp: 110,
            diastolicBp: 115,
            pulseRate: 72,
            temperature: 37.0,
            respiratoryRate: 16,
            oxygenSaturation: 98,
          },
        },
        db
      )
    ).rejects.toThrow(/Diastolic BP must be strictly less than Systolic BP/);

    // SpO2 < 50
    await expect(
      recordVitalObservationHandler(
        {
          auth: { uid: nurseUid },
          data: {
            patientId: patientUid,
            systolicBp: 120,
            diastolicBp: 80,
            pulseRate: 72,
            temperature: 37.0,
            respiratoryRate: 16,
            oxygenSaturation: 42,
          },
        },
        db
      )
    ).rejects.toThrow(/Oxygen saturation must be between 50 and 100%/);
  });

  test('14. recordVitalObservation succeeds for actively assigned nurse, derives nurse UID, computes server-side critical classification, and updates latest cache', async () => {
    const res = await recordVitalObservationHandler(
      {
        auth: { uid: nurseUid },
        data: {
          patientId: patientUid,
          systolicBp: 185, // Hypertensive Crisis -> Critical
          diastolicBp: 125,
          pulseRate: 135, // Severe Tachycardia -> Critical
          temperature: 39.0, // Neutropenic High Fever -> Critical
          temperatureUnit: 'C',
          respiratoryRate: 32, // Severe Tachypnea -> Critical
          oxygenSaturation: 88, // Severe Hypoxemia -> Critical
          weightKg: 70,
          heightCm: 175,
          notes: 'Patient acutely distressed in oncology ward',
        },
      },
      db
    );

    expect(res.success).toBe(true);
    expect(res.isCritical).toBe(true);
    expect(res.severity).toBe('critical');
    expect(res.criticalReasons.length).toBeGreaterThan(0);
    expect(res.observationId).toBeDefined();

    // Verify observation record stored immutably
    const obsDoc = await db
      .collection('ehr_vitals')
      .doc(patientUid)
      .collection('observations')
      .doc(res.observationId)
      .get();

    expect(obsDoc.exists).toBe(true);
    expect(obsDoc.data()?.nurseId).toBe(nurseUid);
    expect(obsDoc.data()?.nurseName).toBe('Nurse Ayesha');
    expect(obsDoc.data()?.systolicBp).toBe(185);
    expect(obsDoc.data()?.isCritical).toBe(true);

    // Verify latest cache updated
    const latestDoc = await db.collection('ehr_vitals').doc(patientUid).get();
    expect(latestDoc.exists).toBe(true);
    expect(latestDoc.data()?.latestObservationId).toBe(res.observationId);
    expect(latestDoc.data()?.isCritical).toBe(true);
    expect(latestDoc.data()?.bloodPressure).toBe('185/125 mmHg');
  });

  test('15. recordVitalObservation is idempotent on retried observationId, and delayed older readings do not overwrite newer latest cache', async () => {
    const retryObsId = 'obs_retry_idempotency_101';

    // 1. Initial submission
    const res1 = await recordVitalObservationHandler(
      {
        auth: { uid: nurseUid },
        data: {
          observationId: retryObsId,
          patientId: patientUid,
          systolicBp: 120,
          diastolicBp: 80,
          pulseRate: 75,
          temperature: 37.0,
          temperatureUnit: 'C',
          respiratoryRate: 16,
          oxygenSaturation: 98,
        },
      },
      db
    );
    expect(res1.success).toBe(true);
    expect(res1.observationId).toBe(retryObsId);

    // 2. Exact retry submission with same observationId (Idempotent replay)
    const res2 = await recordVitalObservationHandler(
      {
        auth: { uid: nurseUid },
        data: {
          observationId: retryObsId,
          patientId: patientUid,
          systolicBp: 120,
          diastolicBp: 80,
          pulseRate: 75,
          temperature: 37.0,
          temperatureUnit: 'C',
          respiratoryRate: 16,
          oxygenSaturation: 98,
        },
      },
      db
    );
    expect(res2.success).toBe(true);
    expect(res2.observationId).toBe(retryObsId);

    // 3. Delayed older reading: submit an observation with timestamp 2 hours in the past
    const twoHoursAgo = new Date(Date.now() - 2 * 3600 * 1000).toISOString();
    const delayedObsId = 'obs_delayed_past_202';

    const delayedRes = await recordVitalObservationHandler(
      {
        auth: { uid: nurseUid },
        data: {
          observationId: delayedObsId,
          patientId: patientUid,
          clientRecordedAt: twoHoursAgo,
          systolicBp: 115,
          diastolicBp: 75,
          pulseRate: 70,
          temperature: 36.8,
          temperatureUnit: 'C',
          respiratoryRate: 15,
          oxygenSaturation: 99,
        },
      },
      db
    );
    expect(delayedRes.success).toBe(true);

    // Observation history MUST contain the delayed observation
    const delayedObsDoc = await db
      .collection('ehr_vitals')
      .doc(patientUid)
      .collection('observations')
      .doc(delayedObsId)
      .get();
    expect(delayedObsDoc.exists).toBe(true);

    // But the LATEST cache MUST NOT have been overwritten by the older reading
    const latestDoc = await db.collection('ehr_vitals').doc(patientUid).get();
    expect(latestDoc.data()?.latestObservationId).toBe(retryObsId); // Still newer retryObsId, NOT delayedObsId
  });

  test('16. Authorized doctor records vitals with explicit doctor clinician attribution (no nurse impersonation)', async () => {
    const docObsId = 'obs_doctor_entry_301';

    const res = await recordVitalObservationHandler(
      {
        auth: { uid: doctorUid },
        data: {
          observationId: docObsId,
          patientId: patientUid,
          systolicBp: 130,
          diastolicBp: 85,
          pulseRate: 78,
          temperature: 36.9,
          temperatureUnit: 'C',
          respiratoryRate: 18,
          oxygenSaturation: 97,
          notes: 'Doctor clinic evaluation',
        },
      },
      db
    );

    expect(res.success).toBe(true);
    expect(res.observationId).toBe(docObsId);

    // Verify observation document in Firestore
    const obsDoc = await db
      .collection('ehr_vitals')
      .doc(patientUid)
      .collection('observations')
      .doc(docObsId)
      .get();

    expect(obsDoc.exists).toBe(true);
    const obsData = obsDoc.data();
    expect(obsData?.recordedBy).toBe(doctorUid);
    expect(obsData?.recordedByName).toBe('Dr. Oncologist');
    expect(obsData?.recordedByRole).toBe('doctor');
    expect(obsData?.doctorId).toBe(doctorUid);
    expect(obsData?.doctorName).toBe('Dr. Oncologist');
    // Ensure no nurse impersonation occurred
    expect(obsData?.nurseId).toBeUndefined();

    // Verify latest cache updated with doctor attribution
    const latestDoc = await db.collection('ehr_vitals').doc(patientUid).get();
    expect(latestDoc.exists).toBe(true);
    const latestData = latestDoc.data();
    expect(latestData?.latestObservationId).toBe(docObsId);
    expect(latestData?.lastDoctorId).toBe(doctorUid);
    expect(latestData?.lastDoctorName).toBe('Dr. Oncologist');
    expect(latestData?.recordedByRole).toBe('doctor');
  });

  test('17. Doctor with only cancelled appointment or revoked consent is rejected when recording vitals', async () => {
    const cancelledDocUid = 'doc_cancelled_test';
    const patientWithCancelled = 'pat_cancelled_test';

    await db.collection('users').doc(cancelledDocUid).set({
      uid: cancelledDocUid,
      role: 'doctor',
      name: 'Dr. Cancelled',
      hospitalId: 'Oncology Ward 3A',
    });

    await db.collection('appointments').doc('appt_cancelled_1').set({
      id: 'appt_cancelled_1',
      doctorId: cancelledDocUid,
      patientId: patientWithCancelled,
      status: 'cancelled',
    });

    // Revoked consent test
    await db.collection('doctor_patient_consents').doc('consent_revoked_1').set({
      id: 'consent_revoked_1',
      doctorId: cancelledDocUid,
      patientId: patientWithCancelled,
      status: 'granted',
      isRevoked: true, // Revoked fabric consent projection
    });

    await expect(
      recordVitalObservationHandler(
        {
          auth: { uid: cancelledDocUid },
          data: {
            patientId: patientWithCancelled,
            systolicBp: 120,
            diastolicBp: 80,
            pulseRate: 72,
            temperature: 37.0,
            respiratoryRate: 16,
            oxygenSaturation: 98,
          },
        },
        db
      )
    ).rejects.toThrow(/explicitly revoked consent|not authorized to record vitals/i);
  });

  test('18. Doctor with only cancelled appointment or revoked consent cannot assign nurses', async () => {
    const cancelledDocUid = 'doc_cancelled_assign_test';
    const patientForAssign = 'pat_cancelled_assign_test';

    await db.collection('users').doc(cancelledDocUid).set({
      uid: cancelledDocUid,
      role: 'doctor',
      name: 'Dr. Cancelled Assign',
      hospitalId: 'Oncology Ward 3A',
    });

    await db.collection('patients').doc(patientForAssign).set({
      uid: patientForAssign,
      name: 'Patient Cancelled Assign',
      hospitalId: 'Oncology Ward 3A',
    });

    await db.collection('appointments').doc('appt_cancelled_assign').set({
      id: 'appt_cancelled_assign',
      doctorId: cancelledDocUid,
      patientId: patientForAssign,
      status: 'rejected', // Rejected appointment
    });

    await expect(
      assignNurseHandler(
        {
          auth: { uid: cancelledDocUid },
          data: {
            nurseId: targetNurseUid,
            patientId: patientForAssign,
          },
        },
        db
      )
    ).rejects.toThrow(/not authorized|does not hold active care/i);
  });

  test('19. Confirmed appointment CANNOT override explicitly revoked Fabric consent for doctor clinical access', async () => {
    const revokedDocUid = 'doc_revoked_consent_override_test';
    const patConsentOverride = 'pat_revoked_consent_override_test';

    await db.collection('users').doc(revokedDocUid).set({
      uid: revokedDocUid,
      role: 'doctor',
      name: 'Dr. Revoked But Has Appt',
      hospitalId: 'Oncology Ward 3A',
    });

    await db.collection('patients').doc(patConsentOverride).set({
      uid: patConsentOverride,
      name: 'Patient Revoked Consent',
      hospitalId: 'Oncology Ward 3A',
    });

    // 1. Doctor has an active confirmed appointment
    await db.collection('appointments').doc('appt_confirmed_override').set({
      id: 'appt_confirmed_override',
      doctorId: revokedDocUid,
      patientId: patConsentOverride,
      status: 'confirmed',
      appointmentDate: new Date(),
    });

    // 2. BUT patient explicitly revoked Fabric consent projection
    await db.collection('doctor_patient_consents').doc(`${patConsentOverride}_${revokedDocUid}`).set({
      id: `${patConsentOverride}_${revokedDocUid}`,
      doctorId: revokedDocUid,
      patientId: patConsentOverride,
      status: 'revoked', // Explicitly revoked by patient on blockchain
      fabricStatus: 'COMMITTED',
    });

    // Recording vitals must be rejected despite confirmed appointment
    await expect(
      recordVitalObservationHandler(
        {
          auth: { uid: revokedDocUid },
          data: {
            patientId: patConsentOverride,
            systolicBp: 120,
            diastolicBp: 80,
            pulseRate: 72,
            temperature: 37.0,
            respiratoryRate: 16,
            oxygenSaturation: 98,
          },
        },
        db
      )
    ).rejects.toThrow(/explicitly revoked consent/i);

    // Nurse assignment must also be rejected despite confirmed appointment
    await expect(
      assignNurseHandler(
        {
          auth: { uid: revokedDocUid },
          data: {
            nurseId: targetNurseUid,
            patientId: patConsentOverride,
          },
        },
        db
      )
    ).rejects.toThrow(/explicitly revoked consent/i);
  });

  test('20. Completed historical appointment does NOT grant current care authorization', async () => {
    const completedDocUid = 'doc_completed_appt_test';
    const patCompletedAppt = 'pat_completed_appt_test';

    await db.collection('users').doc(completedDocUid).set({
      uid: completedDocUid,
      role: 'doctor',
      name: 'Dr. Completed Care',
      hospitalId: 'Oncology Ward 3A',
    });

    await db.collection('patients').doc(patCompletedAppt).set({
      uid: patCompletedAppt,
      name: 'Patient Completed Care',
      hospitalId: 'Oncology Ward 3A',
    });

    // Completed appointment from prior visit
    await db.collection('appointments').doc('appt_completed_past').set({
      id: 'appt_completed_past',
      doctorId: completedDocUid,
      patientId: patCompletedAppt,
      status: 'completed',
      appointmentDate: new Date(Date.now() - 7 * 24 * 3600 * 1000), // 7 days ago
    });

    await expect(
      recordVitalObservationHandler(
        {
          auth: { uid: completedDocUid },
          data: {
            patientId: patCompletedAppt,
            systolicBp: 120,
            diastolicBp: 80,
            pulseRate: 72,
            temperature: 37.0,
            respiratoryRate: 16,
            oxygenSaturation: 98,
          },
        },
        db
      )
    ).rejects.toThrow(/does not hold active care authorization/i);
  });

  test('21. Expired past appointment (>24h past scheduled time) does NOT grant current care authorization', async () => {
    const expiredDocUid = 'doc_expired_appt_test';
    const patExpiredAppt = 'pat_expired_appt_test';

    await db.collection('users').doc(expiredDocUid).set({
      uid: expiredDocUid,
      role: 'doctor',
      name: 'Dr. Expired Appt',
      hospitalId: 'Oncology Ward 3A',
    });

    await db.collection('patients').doc(patExpiredAppt).set({
      uid: patExpiredAppt,
      name: 'Patient Expired Appt',
      hospitalId: 'Oncology Ward 3A',
    });

    // Scheduled appointment was 3 days ago and was never completed or re-booked
    await db.collection('appointments').doc('appt_expired_past').set({
      id: 'appt_expired_past',
      doctorId: expiredDocUid,
      patientId: patExpiredAppt,
      status: 'scheduled',
      appointmentDate: new Date(Date.now() - 3 * 24 * 3600 * 1000), // 3 days ago
    });

    await expect(
      assignNurseHandler(
        {
          auth: { uid: expiredDocUid },
          data: {
            nurseId: targetNurseUid,
            patientId: patExpiredAppt,
          },
        },
        db
      )
    ).rejects.toThrow(/does not hold active care authorization/i);
  });
});
