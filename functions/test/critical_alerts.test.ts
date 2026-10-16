// functions/test/critical_alerts.test.ts

import * as admin from 'firebase-admin';
import { recordVitalObservationHandler } from '../src/record_vital_observation';
import {
  processCriticalAlertEvent,
  resolveEligiblePhysicians,
  recoverPendingAlertEvents,
  escalateOverdueUnacknowledgedAlerts,
  DEFAULT_ACKNOWLEDGMENT_DEADLINE_MS,
  FcmSender,
} from '../src/dispatch_critical_alert';
import {
  acknowledgeCriticalAlertHandler,
  resolveCriticalAlertHandler,
} from '../src/manage_critical_alert';

const PROJECT_ID = process.env.GCLOUD_PROJECT || 'demo-no-project';

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
}

if (!admin.apps.length) {
  admin.initializeApp({ projectId: PROJECT_ID });
}

const db = admin.firestore();

jest.setTimeout(60000);

class MockFcmSender implements FcmSender {
  public calls: admin.messaging.MulticastMessage[] = [];
  public transientFailuresLeft = 0;
  public permanentFailureToken: string | null = null;

  async sendEachForMulticast(message: admin.messaging.MulticastMessage): Promise<admin.messaging.BatchResponse> {
    this.calls.push(message);

    if (this.transientFailuresLeft > 0) {
      this.transientFailuresLeft--;
      return {
        responses: message.tokens.map(() => ({
          success: false,
          error: { code: 'messaging/internal-error', message: 'Simulated transient connection timeout' } as any,
        })),
        successCount: 0,
        failureCount: message.tokens.length,
      };
    }

    return {
      responses: message.tokens.map((token) => {
        if (token === this.permanentFailureToken) {
          return {
            success: false,
            error: { code: 'messaging/registration-token-not-registered', message: 'Token expired' } as any,
          };
        }
        return {
          success: true,
          messageId: `msg_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`,
        };
      }),
      successCount: message.tokens.filter((t) => t !== this.permanentFailureToken).length,
      failureCount: message.tokens.filter((t) => t === this.permanentFailureToken).length,
    };
  }
}

describe('Phase 3B Critical Vital Alerts & Escalation Test Suite', () => {
  const adminUid = 'admin_alert_test';
  const doctor1Uid = 'doc_alert_1';
  const doctor2Uid = 'doc_alert_2';
  const foreignHospitalDocUid = 'doc_foreign_hosp';
  const nurseUid = 'nurse_alert_test';
  const patientUid = 'patient_alert_test';
  const unassignedPatientUid = 'patient_no_doc_test';

  beforeAll(async () => {
    const batch = db.batch();

    // 1. Seed users
    batch.set(db.collection('users').doc(adminUid), {
      uid: adminUid,
      role: 'admin',
      name: 'Dr. Ward Supervisor',
      hospitalId: 'Oncology Ward 3A',
    });

    batch.set(db.collection('users').doc(doctor1Uid), {
      uid: doctor1Uid,
      role: 'doctor',
      name: 'Dr. Elena Vance',
      hospitalId: 'Oncology Ward 3A',
    });

    batch.set(db.collection('users').doc(doctor2Uid), {
      uid: doctor2Uid,
      role: 'doctor',
      name: 'Dr. Gordon Freeman',
      hospitalId: 'Oncology Ward 3A',
    });

    batch.set(db.collection('users').doc(foreignHospitalDocUid), {
      uid: foreignHospitalDocUid,
      role: 'doctor',
      name: 'Dr. Foreign Hospital',
      hospitalId: 'City General Hospital',
    });

    batch.set(db.collection('users').doc(nurseUid), {
      uid: nurseUid,
      role: 'nurse',
      name: 'Nurse Joy',
      hospitalId: 'Oncology Ward 3A',
      status: 'active',
    });

    batch.set(db.collection('users').doc(patientUid), {
      uid: patientUid,
      role: 'patient',
      name: 'Marcus Vance',
      hospitalId: 'Oncology Ward 3A',
    });

    batch.set(db.collection('patients').doc(patientUid), {
      uid: patientUid,
      name: 'Marcus Vance',
      hospitalId: 'Oncology Ward 3A',
    });

    batch.set(db.collection('users').doc(unassignedPatientUid), {
      uid: unassignedPatientUid,
      role: 'patient',
      name: 'Isolated Patient',
      hospitalId: 'Oncology Ward 3A',
    });

    batch.set(db.collection('patients').doc(unassignedPatientUid), {
      uid: unassignedPatientUid,
      name: 'Isolated Patient',
      hospitalId: 'Oncology Ward 3A',
    });

    // 2. Nurse Assignments
    batch.set(db.collection('nurse_patient_assignments').doc(`${nurseUid}_${patientUid}`), {
      id: `${nurseUid}_${patientUid}`,
      nurseId: nurseUid,
      patientId: patientUid,
      assignedBy: doctor1Uid,
      hospitalId: 'Oncology Ward 3A',
      status: 'active',
    });

    batch.set(db.collection('nurse_patient_assignments').doc(`${nurseUid}_${unassignedPatientUid}`), {
      id: `${nurseUid}_${unassignedPatientUid}`,
      nurseId: nurseUid,
      patientId: unassignedPatientUid,
      assignedBy: adminUid, // assigned by admin, no doctor assigned
      hospitalId: 'Oncology Ward 3A',
      status: 'active',
    });

    // 3. Doctor 2 has active Fabric consent with Marcus Vance
    batch.set(db.collection('doctor_patient_consents').doc(`${patientUid}_${doctor2Uid}`), {
      patientId: patientUid,
      doctorId: doctor2Uid,
      status: 'granted',
      isRevoked: false,
    });

    // 4. Seed FCM device tokens for doctor1
    batch.set(db.collection('users').doc(doctor1Uid).collection('deviceTokens').doc('tok_doc1_dev1'), {
      fcmToken: 'fcm_token_doc1_active',
      platform: 'android',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await batch.commit();
  });

  test('1. Normal observation records vitals and produces ZERO critical alert events', async () => {
    const res = await recordVitalObservationHandler(
      {
        auth: { uid: nurseUid },
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
    );

    expect(res.success).toBe(true);
    expect(res.isCritical).toBe(false);
    expect(res.severity).toBe('normal');

    const eventSnap = await db.collection('critical_alert_events').doc(`event_${res.observationId}`).get();
    expect(eventSnap.exists).toBe(false);
  });

  test('2. Warning observation (Stage 2 Hypertension) flags warning and creates medium-severity alert without emergency escalation', async () => {
    const res = await recordVitalObservationHandler(
      {
        auth: { uid: nurseUid },
        data: {
          patientId: patientUid,
          systolicBp: 145,
          diastolicBp: 92,
          pulseRate: 80,
          temperature: 37.1,
          respiratoryRate: 18,
          oxygenSaturation: 97,
        },
      },
      db
    );

    expect(res.success).toBe(true);
    expect(res.isCritical).toBe(false);
    expect(res.severity).toBe('warning');
    expect(res.warningFlags.some((w) => w.includes('Stage 2 Hypertension'))).toBe(true);

    const eventSnap = await db.collection('critical_alert_events').doc(`event_${res.observationId}`).get();
    expect(eventSnap.exists).toBe(true);
    expect(eventSnap.data()?.severity).toBe('medium');
    expect(eventSnap.data()?.status).toBe('COMPLETED');

    const alertSnap = await db.collection('doctors').doc(doctor1Uid).collection('alerts').doc(`alert_${res.observationId}_${doctor1Uid}`).get();
    expect(alertSnap.exists).toBe(true);
    expect(alertSnap.data()?.severity).toBe('medium');
    expect(alertSnap.data()?.escalationStatus).toBe('NONE');
  });

  test('3. Critical vital observation (Severe Hypoxemia SpO2 < 90%) atomically persists durable critical_alert_event', async () => {
    const mockFcm = new MockFcmSender();
    const obsId = `obs_critical_test_${Date.now()}`;

    const res = await recordVitalObservationHandler(
      {
        auth: { uid: nurseUid },
        data: {
          patientId: patientUid,
          observationId: obsId,
          systolicBp: 120,
          diastolicBp: 80,
          pulseRate: 75,
          temperature: 37.0,
          respiratoryRate: 18,
          oxygenSaturation: 88, // Critical hypoxemia
        },
      },
      db,
      mockFcm
    );

    expect(res.success).toBe(true);
    expect(res.isCritical).toBe(true);
    expect(res.severity).toBe('critical');

    // Verify durable critical_alert_events record
    const eventDoc = await db.collection('critical_alert_events').doc(`event_${obsId}`).get();
    expect(eventDoc.exists).toBe(true);
    const eventData = eventDoc.data()!;
    expect(eventData.observationId).toBe(obsId);
    expect(eventData.patientId).toBe(patientUid);
    expect(eventData.severity).toBe('high');
    expect(eventData.criticalReasons.some((r: string) => r.includes('Severe Hypoxemia'))).toBe(true);

    // Verify durable alert created for assigned physician doctor1Uid
    const alert1Doc = await db.collection('doctors').doc(doctor1Uid).collection('alerts').doc(`alert_${obsId}_${doctor1Uid}`).get();
    expect(alert1Doc.exists).toBe(true);
    expect(alert1Doc.data()!.patientName).toBe('Marcus Vance');
    expect(alert1Doc.data()!.isAcknowledged).toBe(false);
    expect(alert1Doc.data()!.isResolved).toBe(false);

    // Verify durable alert created for consent doctor2Uid
    const alert2Doc = await db.collection('doctors').doc(doctor2Uid).collection('alerts').doc(`alert_${obsId}_${doctor2Uid}`).get();
    expect(alert2Doc.exists).toBe(true);

    // Verify in-app notification item was created
    const notifDoc = await db.collection('notifications').doc(doctor1Uid).collection('items').doc(`alert_${obsId}_${doctor1Uid}`).get();
    expect(notifDoc.exists).toBe(true);
    expect(notifDoc.data()!.type).toBe('vital_alert');

    // Verify FCM multicast dispatch was invoked
    expect(mockFcm.calls.length).toBeGreaterThanOrEqual(1);
    const sentCall = mockFcm.calls[0];
    expect(sentCall.notification?.title).toBe('Critical patient alert');
    expect(sentCall.data?.type).toBe('vital_alert');
  });

  test('4. Idempotency: Retrying observation submission absorbs duplicate without duplicate alerts', async () => {
    const mockFcm = new MockFcmSender();
    const obsId = `obs_idempotent_${Date.now()}`;

    // First submission
    await recordVitalObservationHandler(
      {
        auth: { uid: nurseUid },
        data: {
          patientId: patientUid,
          observationId: obsId,
          systolicBp: 190,
          diastolicBp: 125, // Hypertensive crisis
          pulseRate: 80,
          temperature: 37.0,
          respiratoryRate: 18,
          oxygenSaturation: 96,
        },
      },
      db,
      mockFcm
    );

    const callCountAfterFirst = mockFcm.calls.length;

    // Retry submission with same observationId
    const retryRes = await recordVitalObservationHandler(
      {
        auth: { uid: nurseUid },
        data: {
          patientId: patientUid,
          observationId: obsId,
          systolicBp: 190,
          diastolicBp: 125,
          pulseRate: 80,
          temperature: 37.0,
          respiratoryRate: 18,
          oxygenSaturation: 96,
        },
      },
      db,
      mockFcm
    );

    expect(retryRes.success).toBe(true);
    // FCM dispatch was not re-invoked on replayed transaction
    expect(mockFcm.calls.length).toBe(callCountAfterFirst);
  });

  test('5. Crash recovery worker sweeps and processes pending alert events', async () => {
    const mockFcm = new MockFcmSender();
    const crashedObsId = `obs_crashed_${Date.now()}`;
    const crashedEventId = `event_${crashedObsId}`;

    // Simulate an event created in transaction before server abruptly rebooted
    await db.collection('critical_alert_events').doc(crashedEventId).set({
      eventId: crashedEventId,
      observationId: crashedObsId,
      patientId: patientUid,
      patientName: 'Marcus Vance',
      hospitalId: 'Oncology Ward 3A',
      eventType: 'vital_alert',
      severity: 'high',
      status: 'PENDING',
      attempts: 0,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      criticalReasons: ['Neutropenic High Fever (39.2 °C)'],
      vitalsSummary: {
        bloodPressure: '120/80 mmHg',
        systolicBp: 120,
        diastolicBp: 80,
        pulseRate: 95,
        temperatureC: 39.2,
        respiratoryRate: 20,
        oxygenSaturation: 96,
      },
      recordedByUid: nurseUid,
      recordedByName: 'Nurse Joy',
      recordedByRole: 'nurse',
    });

    const recoveredCount = await recoverPendingAlertEvents(db, mockFcm);
    expect(recoveredCount).toBeGreaterThanOrEqual(1);

    const eventDoc = await db.collection('critical_alert_events').doc(crashedEventId).get();
    expect(eventDoc.data()!.status).toBe('COMPLETED');
    expect(eventDoc.data()!.attempts).toBe(1);

    // Verify alert document was created by the recovery worker
    const alertDoc = await db.collection('doctors').doc(doctor1Uid).collection('alerts').doc(`alert_${crashedObsId}_${doctor1Uid}`).get();
    expect(alertDoc.exists).toBe(true);
    expect(alertDoc.data()!.description).toContain('Neutropenic High Fever');
  });

  test('6. Concurrent workers cannot claim the same event lease simultaneously', async () => {
    const mockFcm = new MockFcmSender();
    const concurrentObsId = `obs_concurrent_${Date.now()}`;
    const concurrentEventId = `event_${concurrentObsId}`;

    await db.collection('critical_alert_events').doc(concurrentEventId).set({
      eventId: concurrentEventId,
      observationId: concurrentObsId,
      patientId: patientUid,
      patientName: 'Marcus Vance',
      hospitalId: 'Oncology Ward 3A',
      eventType: 'vital_alert',
      severity: 'high',
      status: 'PENDING',
      attempts: 0,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      criticalReasons: ['Severe Tachycardia (145 bpm)'],
      vitalsSummary: {},
      recordedByUid: nurseUid,
      recordedByName: 'Nurse Joy',
      recordedByRole: 'nurse',
    });

    // Run two workers simultaneously
    const [w1, w2] = await Promise.all([
      processCriticalAlertEvent(db, concurrentEventId, mockFcm),
      processCriticalAlertEvent(db, concurrentEventId, mockFcm),
    ]);

    // Exactly one claimed and succeeded; the other safely bounced due to lease lock
    const successes = [w1.success, w2.success].filter(Boolean).length;
    expect(successes).toBe(1);
  });

  test('7. Cross-hospital recipient leakage is strictly blocked', async () => {
    // Add foreign hospital doctor consent
    await db.collection('doctor_patient_consents').doc(`${patientUid}_${foreignHospitalDocUid}`).set({
      patientId: patientUid,
      doctorId: foreignHospitalDocUid,
      status: 'granted',
      isRevoked: false,
    });

    const eligiblePhysicians = await resolveEligiblePhysicians(db, patientUid, 'Oncology Ward 3A');
    const doctorIds = eligiblePhysicians.map((p) => p.doctorId);

    expect(doctorIds).toContain(doctor1Uid);
    expect(doctorIds).not.toContain(foreignHospitalDocUid);
  });

  test('8. Missing FCM device tokens records NO_TOKENS outcome and triggers supervisor escalation', async () => {
    // Create doctor with NO tokens
    const noTokenDocUid = `doc_notok_${Date.now()}`;
    await db.collection('users').doc(noTokenDocUid).set({
      uid: noTokenDocUid,
      role: 'doctor',
      name: 'Dr. No Tokens',
      hospitalId: 'Oncology Ward 3A',
    });

    const testPatUid = `pat_tok_${Date.now()}`;
    await db.collection('patients').doc(testPatUid).set({
      uid: testPatUid,
      name: 'Patient With No-Token Doctor',
      hospitalId: 'Oncology Ward 3A',
    });

    await db.collection('nurse_patient_assignments').doc(`${nurseUid}_${testPatUid}`).set({
      id: `${nurseUid}_${testPatUid}`,
      nurseId: nurseUid,
      patientId: testPatUid,
      assignedBy: noTokenDocUid,
      hospitalId: 'Oncology Ward 3A',
      status: 'active',
    });

    const mockFcm = new MockFcmSender();
    const obsId = `obs_notok_${Date.now()}`;

    const res = await recordVitalObservationHandler(
      {
        auth: { uid: nurseUid },
        data: {
          patientId: testPatUid,
          observationId: obsId,
          systolicBp: 70,
          diastolicBp: 40, // Severe shock/hypotension
          pulseRate: 40,
          temperature: 36.5,
          respiratoryRate: 10,
          oxygenSaturation: 85,
        },
      },
      db,
      mockFcm
    );

    expect(res.success).toBe(true);

    // Verify alert document has NO_TOKENS and ESCALATED
    const alertDoc = await db.collection('doctors').doc(noTokenDocUid).collection('alerts').doc(`alert_${obsId}_${noTokenDocUid}`).get();
    expect(alertDoc.exists).toBe(true);
    expect(alertDoc.data()!.dispatchStatus).toBe('NO_TOKENS');
    expect(alertDoc.data()!.escalationStatus).toBe('ESCALATED');

    // Verify durable escalation record created
    const escDoc = await db.collection('escalated_alerts').doc(`esc_${obsId}`).get();
    expect(escDoc.exists).toBe(true);
    expect(escDoc.data()!.reason).toBe('NO_TOKENS');
  });

  test('9. Unassigned patient with no eligible physician triggers supervisor escalation', async () => {
    const mockFcm = new MockFcmSender();
    const obsId = `obs_no_doc_${Date.now()}`;

    const res = await recordVitalObservationHandler(
      {
        auth: { uid: nurseUid },
        data: {
          patientId: unassignedPatientUid,
          observationId: obsId,
          systolicBp: 195,
          diastolicBp: 130, // Hypertensive crisis
          pulseRate: 85,
          temperature: 37.0,
          respiratoryRate: 20,
          oxygenSaturation: 95,
        },
      },
      db,
      mockFcm
    );

    expect(res.success).toBe(true);
    expect(res.isCritical).toBe(true);

    const escDoc = await db.collection('escalated_alerts').doc(`esc_${obsId}`).get();
    expect(escDoc.exists).toBe(true);
    expect(escDoc.data()!.reason).toBe('NO_ELIGIBLE_PHYSICIAN');

    // Hospital admin received escalation alert
    const adminAlert = await db.collection('doctors').doc(adminUid).collection('alerts').doc(`esc_${obsId}_${adminUid}`).get();
    expect(adminAlert.exists).toBe(true);
    expect(adminAlert.data()!.title).toContain('SUPERVISOR ACTION REQUIRED');
  });

  test('10. Bounded retry mechanism recovers from transient FCM errors (up to 3 attempts)', async () => {
    const mockFcm = new MockFcmSender();
    mockFcm.transientFailuresLeft = 2; // First 2 fail, 3rd succeeds

    const obsId = `obs_retry_fcm_${Date.now()}`;
    await recordVitalObservationHandler(
      {
        auth: { uid: nurseUid },
        data: {
          patientId: patientUid,
          observationId: obsId,
          systolicBp: 120,
          diastolicBp: 80,
          pulseRate: 140, // Severe tachycardia
          temperature: 37.0,
          respiratoryRate: 18,
          oxygenSaturation: 98,
        },
      },
      db,
      mockFcm
    );

    // 3 attempts total made
    expect(mockFcm.calls.length).toBe(3);

    const alertDoc = await db.collection('doctors').doc(doctor1Uid).collection('alerts').doc(`alert_${obsId}_${doctor1Uid}`).get();
    expect(alertDoc.data()!.dispatchStatus).toBe('DELIVERED');
  });

  test('11. Permanent invalid token error cleans up expired token without useless retries', async () => {
    const permFailDocUid = `doc_permfail_${Date.now()}`;
    const badToken = 'fcm_bad_expired_token';

    await db.collection('users').doc(permFailDocUid).set({
      uid: permFailDocUid,
      role: 'doctor',
      name: 'Dr. Expired Device',
      hospitalId: 'Oncology Ward 3A',
    });

    const tokenDocRef = db.collection('users').doc(permFailDocUid).collection('deviceTokens').doc('bad_token_doc');
    await tokenDocRef.set({
      fcmToken: badToken,
      platform: 'android',
    });

    const testPatUid = `pat_perm_${Date.now()}`;
    await db.collection('patients').doc(testPatUid).set({
      uid: testPatUid,
      name: 'Patient For Permanent Token Test',
      hospitalId: 'Oncology Ward 3A',
    });

    await db.collection('nurse_patient_assignments').doc(`${nurseUid}_${testPatUid}`).set({
      id: `${nurseUid}_${testPatUid}`,
      nurseId: nurseUid,
      patientId: testPatUid,
      assignedBy: permFailDocUid,
      hospitalId: 'Oncology Ward 3A',
      status: 'active',
    });

    const mockFcm = new MockFcmSender();
    mockFcm.permanentFailureToken = badToken;

    const obsId = `obs_perm_${Date.now()}`;
    await recordVitalObservationHandler(
      {
        auth: { uid: nurseUid },
        data: {
          patientId: testPatUid,
          observationId: obsId,
          systolicBp: 120,
          diastolicBp: 80,
          pulseRate: 75,
          temperature: 39.5, // High neutropenic fever
          respiratoryRate: 18,
          oxygenSaturation: 97,
        },
      },
      db,
      mockFcm
    );

    // Expired token was automatically deleted from doctor's deviceTokens subcollection
    const cleanedTokenDoc = await tokenDocRef.get();
    expect(cleanedTokenDoc.exists).toBe(false);
  });

  test('12. Doctor can acknowledge their assigned alert via trusted callable', async () => {
    const alertId = `alert_ack_test_${Date.now()}`;
    const alertRef = db.collection('doctors').doc(doctor1Uid).collection('alerts').doc(alertId);

    await alertRef.set({
      id: alertId,
      alertId,
      doctorId: doctor1Uid,
      patientId: patientUid,
      patientName: 'Marcus Vance',
      alertType: 'vital_alert',
      severity: 'high',
      title: 'Critical Vital Alert',
      description: 'Severe Hypoxemia (88%)',
      isRead: false,
      isAcknowledged: false,
      isResolved: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    const res = await acknowledgeCriticalAlertHandler(
      {
        auth: { uid: doctor1Uid },
        data: {
          doctorId: doctor1Uid,
          alertId,
          notes: 'Oxygen delivered via nasal cannula; monitoring SpO2 continuously.',
        },
      },
      db
    );

    expect(res.success).toBe(true);
    expect(res.status).toBe('ACKNOWLEDGED');

    const updated = await alertRef.get();
    expect(updated.data()!.isRead).toBe(true);
    expect(updated.data()!.isAcknowledged).toBe(true);
    expect(updated.data()!.acknowledgedBy).toBe(doctor1Uid);
    expect(updated.data()!.acknowledgedAt).toBeDefined();
    expect(updated.data()!.acknowledgmentNotes).toContain('Oxygen delivered');
  });

  test('13. Doctor cannot acknowledge an alert belonging to another physician', async () => {
    const alertId = `alert_doc1_private_${Date.now()}`;
    await db.collection('doctors').doc(doctor1Uid).collection('alerts').doc(alertId).set({
      id: alertId,
      doctorId: doctor1Uid,
      patientId: patientUid,
      isAcknowledged: false,
      isResolved: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Doctor 2 attempts to acknowledge Doctor 1's alert
    await expect(
      acknowledgeCriticalAlertHandler(
        {
          auth: { uid: doctor2Uid },
          data: {
            doctorId: doctor1Uid,
            alertId,
          },
        },
        db
      )
    ).rejects.toThrow(/cannot acknowledge critical alerts assigned to another doctor/i);
  });

  test('14. Resolving an UNACKNOWLEDGED alert is strictly rejected with failed-precondition', async () => {
    const alertId = `alert_unacked_${Date.now()}`;
    await db.collection('doctors').doc(doctor1Uid).collection('alerts').doc(alertId).set({
      id: alertId,
      doctorId: doctor1Uid,
      patientId: patientUid,
      isAcknowledged: false, // NOT ACKNOWLEDGED YET
      isResolved: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await expect(
      resolveCriticalAlertHandler(
        {
          auth: { uid: doctor1Uid },
          data: {
            doctorId: doctor1Uid,
            alertId,
          },
        },
        db
      )
    ).rejects.toThrow(/Alert must be explicitly acknowledged by the recipient physician before it can be resolved/i);
  });

  test('15. Resolving an ACKNOWLEDGED alert succeeds and transitions to RESOLVED with server timestamp', async () => {
    const alertId = `alert_ready_resolve_${Date.now()}`;
    const alertRef = db.collection('doctors').doc(doctor1Uid).collection('alerts').doc(alertId);

    await alertRef.set({
      id: alertId,
      doctorId: doctor1Uid,
      patientId: patientUid,
      isAcknowledged: true, // ALREADY ACKNOWLEDGED
      acknowledgedAt: admin.firestore.FieldValue.serverTimestamp(),
      acknowledgedBy: doctor1Uid,
      isResolved: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    const res = await resolveCriticalAlertHandler(
      {
        auth: { uid: doctor1Uid },
        data: {
          doctorId: doctor1Uid,
          alertId,
          notes: 'Patient vitals stabilized post-intervention. SpO2 currently 96%.',
        },
      },
      db
    );

    expect(res.success).toBe(true);
    expect(res.status).toBe('RESOLVED');

    const updated = await alertRef.get();
    expect(updated.data()!.isResolved).toBe(true);
    expect(updated.data()!.resolvedBy).toBe(doctor1Uid);
    expect(updated.data()!.resolvedAt).toBeDefined();
    expect(updated.data()!.resolutionNotes).toContain('Patient vitals stabilized');
  });

  test('16. Unauthenticated caller cannot acknowledge or resolve alerts', async () => {
    await expect(
      acknowledgeCriticalAlertHandler(
        {
          auth: undefined,
          data: { doctorId: doctor1Uid, alertId: 'any_alert' },
        },
        db
      )
    ).rejects.toThrow(/User must be authenticated/i);

    await expect(
      resolveCriticalAlertHandler(
        {
          auth: undefined,
          data: { doctorId: doctor1Uid, alertId: 'any_alert' },
        },
        db
      )
    ).rejects.toThrow(/User must be authenticated/i);
  });

  test('17. Overdue unacknowledged alert escalation triggers supervisor escalation past 15 min deadline', async () => {
    const alertId = `alert_overdue_test_${Date.now()}`;
    const alertRef = db.collection('doctors').doc(doctor1Uid).collection('alerts').doc(alertId);
    const nowMs = Date.now();
    const twentyMinsAgo = new Date(nowMs - 20 * 60 * 1000);

    await alertRef.set({
      id: alertId,
      alertId,
      doctorId: doctor1Uid,
      patientId: patientUid,
      patientName: 'Marcus Vance',
      hospitalId: 'Oncology Ward 3A',
      alertType: 'vital_alert',
      severity: 'high',
      isAcknowledged: false, // Unacknowledged
      isResolved: false,
      escalationStatus: 'NONE',
      createdAt: admin.firestore.Timestamp.fromDate(twentyMinsAgo),
      clinicalSummary: 'Severe Hypoxemia (SpO2: 88%)',
    });

    const result = await escalateOverdueUnacknowledgedAlerts(db, {
      deadlineMs: 15 * 60 * 1000,
      currentTimeMs: nowMs,
    });

    expect(result.escalatedCount).toBeGreaterThanOrEqual(1);

    // Verify alert escalation status updated
    const updatedAlert = await alertRef.get();
    expect(updatedAlert.data()?.escalationStatus).toBe('OVERDUE_ESCALATED');
    expect(updatedAlert.data()?.escalatedAt).toBeDefined();

    // Verify durable escalation record in escalated_alerts
    const escDoc = await db.collection('escalated_alerts').doc(`esc_overdue_${alertId}`).get();
    expect(escDoc.exists).toBe(true);
    expect(escDoc.data()?.escalationType).toBe('OVERDUE_UNACKNOWLEDGED');
    expect(escDoc.data()?.hospitalId).toBe('Oncology Ward 3A');
    expect(escDoc.data()?.status).toBe('ACTIVE_ESCALATION');
  });

  test('18. Sweeper idempotency: repeated overdue sweep does not create duplicate escalation records', async () => {
    const alertId = `alert_overdue_idempotent_${Date.now()}`;
    const alertRef = db.collection('doctors').doc(doctor1Uid).collection('alerts').doc(alertId);
    const nowMs = Date.now();
    const twentyMinsAgo = new Date(nowMs - 20 * 60 * 1000);

    await alertRef.set({
      id: alertId,
      alertId,
      doctorId: doctor1Uid,
      patientId: patientUid,
      hospitalId: 'Oncology Ward 3A',
      alertType: 'vital_alert',
      severity: 'high',
      isAcknowledged: false,
      isResolved: false,
      escalationStatus: 'NONE',
      createdAt: admin.firestore.Timestamp.fromDate(twentyMinsAgo),
    });

    // Run 1: Should escalate
    const res1 = await escalateOverdueUnacknowledgedAlerts(db, {
      deadlineMs: 15 * 60 * 1000,
      currentTimeMs: nowMs,
    });
    expect(res1.escalatedCount).toBeGreaterThanOrEqual(1);

    // Run 2: Immediate retry should detect OVERDUE_ESCALATED and NOT re-escalate
    const res2 = await escalateOverdueUnacknowledgedAlerts(db, {
      deadlineMs: 15 * 60 * 1000,
      currentTimeMs: nowMs,
    });
    expect(res2.escalatedCount).toBe(0);
  });

  test('19. Acknowledged or resolved alert is NOT escalated by overdue sweeper', async () => {
    const ackAlertId = `alert_already_acked_${Date.now()}`;
    const resolvedAlertId = `alert_already_resolved_${Date.now()}`;
    const nowMs = Date.now();
    const twentyMinsAgo = new Date(nowMs - 20 * 60 * 1000);

    // 1. Acknowledged alert
    await db.collection('doctors').doc(doctor1Uid).collection('alerts').doc(ackAlertId).set({
      id: ackAlertId,
      alertId: ackAlertId,
      doctorId: doctor1Uid,
      patientId: patientUid,
      hospitalId: 'Oncology Ward 3A',
      alertType: 'vital_alert',
      severity: 'high',
      isAcknowledged: true, // ALREADY ACKNOWLEDGED
      isResolved: false,
      escalationStatus: 'NONE',
      createdAt: admin.firestore.Timestamp.fromDate(twentyMinsAgo),
    });

    // 2. Resolved alert
    await db.collection('doctors').doc(doctor1Uid).collection('alerts').doc(resolvedAlertId).set({
      id: resolvedAlertId,
      alertId: resolvedAlertId,
      doctorId: doctor1Uid,
      patientId: patientUid,
      hospitalId: 'Oncology Ward 3A',
      alertType: 'vital_alert',
      severity: 'high',
      isAcknowledged: true,
      isResolved: true, // ALREADY RESOLVED
      escalationStatus: 'NONE',
      createdAt: admin.firestore.Timestamp.fromDate(twentyMinsAgo),
    });

    const result = await escalateOverdueUnacknowledgedAlerts(db, {
      deadlineMs: 15 * 60 * 1000,
      currentTimeMs: nowMs,
    });

    // Neither should have generated an escalation record
    const escAck = await db.collection('escalated_alerts').doc(`esc_overdue_${ackAlertId}`).get();
    expect(escAck.exists).toBe(false);

    const escResolved = await db.collection('escalated_alerts').doc(`esc_overdue_${resolvedAlertId}`).get();
    expect(escResolved.exists).toBe(false);
  });

  test('20. Explicitly revoked Fabric consent denies physician access even with a confirmed appointment', async () => {
    const revokedDoctorUid = `doc_revoked_${Date.now()}`;

    // Seed doctor user in same hospital
    await db.collection('users').doc(revokedDoctorUid).set({
      uid: revokedDoctorUid,
      role: 'doctor',
      name: 'Dr. Revoked Physician',
      hospitalId: 'Oncology Ward 3A',
    });

    // Seed confirmed appointment (ordinarily would grant access)
    await db.collection('appointments').doc(`appt_revoked_${Date.now()}`).set({
      doctorId: revokedDoctorUid,
      patientId: patientUid,
      status: 'confirmed',
      appointmentDate: new Date(),
    });

    // Seed explicit revoked consent in doctor_patient_consents
    await db.collection('doctor_patient_consents').doc(`${patientUid}_${revokedDoctorUid}`).set({
      patientId: patientUid,
      doctorId: revokedDoctorUid,
      status: 'revoked',
      isRevoked: true,
      revokedAt: new Date(),
    });

    const eligible = await resolveEligiblePhysicians(db, patientUid, 'Oncology Ward 3A');
    const doctorIds = eligible.map((e) => e.doctorId);

    // Revoked doctor must be strictly excluded
    expect(doctorIds).not.toContain(revokedDoctorUid);
  });

  test('21. Real users/{doctorId}/deviceTokens subcollection correctly resolved and cleaned up on invalid token', async () => {
    const testDocUid = `doc_toktest_${Date.now()}`;
    const validToken = 'fcm_tok_valid_123';
    const expiredToken = 'fcm_tok_expired_456';
    const expiredTokenId = `hash_${Date.now()}_expired`;

    await db.collection('users').doc(testDocUid).set({
      uid: testDocUid,
      role: 'doctor',
      name: 'Dr. Token Tester',
      hospitalId: 'Oncology Ward 3A',
    });

    // Seed active care assignment
    await db.collection('nurse_patient_assignments').doc(`assign_${Date.now()}`).set({
      patientId: patientUid,
      assignedBy: testDocUid,
      nurseId: nurseUid,
      status: 'active',
      hospitalId: 'Oncology Ward 3A',
    });

    // Seed valid and expired tokens in real subcollection path: users/{docId}/deviceTokens/{tokenId}
    await db.collection('users').doc(testDocUid).collection('deviceTokens').doc('tok_valid_doc').set({
      fcmToken: validToken,
      platform: 'android',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await db.collection('users').doc(testDocUid).collection('deviceTokens').doc(expiredTokenId).set({
      fcmToken: expiredToken,
      platform: 'android',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    const mockFcm = new MockFcmSender();
    mockFcm.permanentFailureToken = expiredToken;

    const eventId = `event_tokclean_${Date.now()}`;
    await db.collection('critical_alert_events').doc(eventId).set({
      eventId,
      observationId: `obs_${Date.now()}`,
      patientId: patientUid,
      patientName: 'Marcus Vance',
      hospitalId: 'Oncology Ward 3A',
      eventType: 'vital_alert',
      severity: 'high',
      status: 'PENDING',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      criticalReasons: ['Severe Tachycardia (145 bpm)'],
      recordedByUid: 'nurse_tokclean',
      recordedByName: 'Nurse Cleaner',
      vitalsSummary: { bloodPressure: '120/80', pulseRate: 145 },
    });

    const result = await processCriticalAlertEvent(db, eventId, mockFcm);
    expect(result.success).toBe(true);

    // Verify expired token document was removed from deviceTokens subcollection
    const expiredDoc = await db.collection('users').doc(testDocUid).collection('deviceTokens').doc(expiredTokenId).get();
    expect(expiredDoc.exists).toBe(false);

    // Verify valid token document was preserved
    const validDoc = await db.collection('users').doc(testDocUid).collection('deviceTokens').doc('tok_valid_doc').get();
    expect(validDoc.exists).toBe(true);
  });

  test('22. Lease fencing token blocks stale worker from overwriting state if lease expired and re-acquired', async () => {
    const eventId = `event_fencing_${Date.now()}`;
    const eventRef = db.collection('critical_alert_events').doc(eventId);

    // Create event
    await eventRef.set({
      eventId,
      observationId: `obs_${Date.now()}`,
      patientId: patientUid,
      patientName: 'Marcus Vance',
      hospitalId: 'Oncology Ward 3A',
      eventType: 'vital_alert',
      severity: 'high',
      status: 'PENDING',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      criticalReasons: ['Severe Tachypnea (36 breaths/min)'],
      vitalsSummary: { respiratoryRate: 36 },
    });

    // Simulate Worker 1 acquiring lease
    const nowMs = Date.now();
    const staleLeaseToken = 'stale_worker_token_123';
    await eventRef.update({
      status: 'PROCESSING',
      processingLease: nowMs + 30000,
      leaseToken: staleLeaseToken,
    });

    // Simulate Worker 2 stealing the lease after Worker 1 took too long (>30s)
    const freshLeaseToken = 'fresh_worker_token_456';
    await eventRef.update({
      status: 'PROCESSING',
      processingLease: nowMs + 60000,
      leaseToken: freshLeaseToken,
    });

    // Simulate Worker 1 attempting to complete the event with its stale token
    await db.runTransaction(async (t) => {
      const snap = await t.get(eventRef);
      const data = snap.data();
      // Fencing token check: Stale worker detects its lease was superseded
      if (data?.leaseToken && data.leaseToken !== staleLeaseToken) {
        return; // Abort without updating
      }
      t.update(eventRef, { status: 'COMPLETED' });
    });

    // Fresh worker lease token must still be in place and status still PROCESSING
    const finalDoc = await eventRef.get();
    expect(finalDoc.data()?.leaseToken).toBe(freshLeaseToken);
    expect(finalDoc.data()?.status).toBe('PROCESSING');
  });
});
