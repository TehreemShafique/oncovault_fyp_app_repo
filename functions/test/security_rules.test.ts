// functions/test/security_rules.test.ts

import * as fs from 'fs';
import * as path from 'path';
import {
  initializeTestEnvironment,
  RulesTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';

const RULES_PATH = path.resolve(__dirname, '../../firestore.rules');
const rulesContent = fs.readFileSync(RULES_PATH, 'utf8');

describe('Phase 2D.2A Firestore Security Rules Test Suite', () => {
  let testEnv: RulesTestEnvironment;

  beforeAll(async () => {
    testEnv = await initializeTestEnvironment({
      projectId: 'oncovault-rules-test',
      firestore: {
        rules: rulesContent,
        host: '127.0.0.1',
        port: 8080,
      },
    });
  });

  afterAll(async () => {
    if (testEnv) {
      await testEnv.cleanup();
    }
  });

  beforeEach(async () => {
    if (testEnv) {
      await testEnv.clearFirestore();
    }
  });

  // Helper to seed documents using privileged context
  async function seedDoc(docPath: string, data: any) {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc(docPath).set(data);
    });
  }

  // ── 1. USER ROLE SECURITY ──
  describe('User Role Security & Self-Registration', () => {
    test('Self-registration with role "patient" is allowed', async () => {
      const patientContext = testEnv.authenticatedContext('patient_1');
      await assertSucceeds(
        patientContext.firestore().doc('users/patient_1').set({
          uid: 'patient_1',
          role: 'patient',
          name: 'Patient One',
          email: 'p1@test.com',
        })
      );
    });

    test('Self-registration attempting to assign role "doctor" is blocked', async () => {
      const maliciousContext = testEnv.authenticatedContext('attacker_1');
      await assertFails(
        maliciousContext.firestore().doc('users/attacker_1').set({
          uid: 'attacker_1',
          role: 'doctor', // Privilege escalation attempt
          name: 'Fake Doctor',
          email: 'fake@test.com',
        })
      );
    });

    test('Self-registration attempting to assign role "admin" is blocked', async () => {
      const maliciousContext = testEnv.authenticatedContext('attacker_2');
      await assertFails(
        maliciousContext.firestore().doc('users/attacker_2').set({
          uid: 'attacker_2',
          role: 'admin',
          name: 'Fake Admin',
          email: 'admin@test.com',
        })
      );
    });

    test('User cannot update their own role from patient to doctor', async () => {
      await seedDoc('users/patient_2', {
        uid: 'patient_2',
        role: 'patient',
        name: 'Patient Two',
      });

      const patientContext = testEnv.authenticatedContext('patient_2');
      await assertFails(
        patientContext.firestore().doc('users/patient_2').update({
          role: 'doctor',
        })
      );
    });
  });

  // ── 2. DOCTOR COORDINATION METADATA ──
  describe('Doctor Coordination Metadata Protection', () => {
    beforeEach(async () => {
      await seedDoc('users/doc_1', { uid: 'doc_1', role: 'doctor' });
      await seedDoc('doctors/doc_1', {
        uid: 'doc_1',
        name: 'Dr. Smith',
        scheduleRevision: 5,
      });
    });

    test('Doctor can update their profile without mutating scheduleRevision', async () => {
      const docContext = testEnv.authenticatedContext('doc_1');
      await assertSucceeds(
        docContext.firestore().doc('doctors/doc_1').update({
          name: 'Dr. Smith Updated',
        })
      );
    });

    test('Doctor directly mutating scheduleRevision is blocked', async () => {
      const docContext = testEnv.authenticatedContext('doc_1');
      await assertFails(
        docContext.firestore().doc('doctors/doc_1').update({
          scheduleRevision: 99, // Backend coordination field protected
        })
      );
    });

    test('Doctor directly mutating availability map is blocked', async () => {
      const docContext = testEnv.authenticatedContext('doc_1');
      await assertFails(
        docContext.firestore().doc('doctors/doc_1').update({
          availability: {
            slotDurationMinutes: 15,
            weeklySchedule: {},
            blockedDates: [],
            blockedSlots: [],
          },
        })
      );
    });

    test('Doctor directly mutating availableDays is blocked', async () => {
      const docContext = testEnv.authenticatedContext('doc_1');
      await assertFails(
        docContext.firestore().doc('doctors/doc_1').update({
          availableDays: ['Mon', 'Tue'],
        })
      );
    });

    test('Doctor directly mutating availableSlots is blocked', async () => {
      const docContext = testEnv.authenticatedContext('doc_1');
      await assertFails(
        docContext.firestore().doc('doctors/doc_1').update({
          availableSlots: ['09:00 AM'],
        })
      );
    });

    test('Patient attempting to update doctor document is blocked', async () => {
      const patientContext = testEnv.authenticatedContext('patient_1');
      await assertFails(
        patientContext.firestore().doc('doctors/doc_1').update({
          name: 'Hacked Doctor Name',
        })
      );
    });

    test('Unauthenticated caller attempting to update doctor document is blocked', async () => {
      const unauthContext = testEnv.unauthenticatedContext();
      await assertFails(
        unauthContext.firestore().doc('doctors/doc_1').update({
          name: 'Hacked Doctor Name',
        })
      );
    });
  });

  // ── 3. APPOINTMENT CREATION INTEGRITY ──
  describe('Appointment Creation Invariants', () => {
    beforeEach(async () => {
      await seedDoc('users/patient_1', { uid: 'patient_1', role: 'patient' });
      await seedDoc('users/doc_1', { uid: 'doc_1', role: 'doctor' });
    });

    test('Valid initial booking batch in "scheduled" status is allowed', async () => {
      const patientContext = testEnv.authenticatedContext('patient_1');
      const db = patientContext.firestore();
      const apptId = 'appt_101';
      const now = new Date();

      const payload = {
        id: apptId,
        patientId: 'patient_1',
        patientName: 'Patient One',
        doctorId: 'doc_1',
        doctorName: 'Dr. Smith',
        doctorSpecialty: 'Oncology',
        appointmentDate: now,
        timeSlot: '09:30 AM',
        status: 'scheduled',
        createdAt: now,
      };

      const batch = db.batch();
      batch.set(db.doc(`appointments/${apptId}`), payload);
      batch.set(db.doc(`patients/patient_1/appointments/${apptId}`), payload);

      await assertSucceeds(batch.commit());
    });

    test('Direct client creation in "confirmed" status is blocked', async () => {
      const patientContext = testEnv.authenticatedContext('patient_1');
      const db = patientContext.firestore();
      const apptId = 'appt_102';
      const now = new Date();

      const payload = {
        id: apptId,
        patientId: 'patient_1',
        patientName: 'Patient One',
        doctorId: 'doc_1',
        doctorName: 'Dr. Smith',
        doctorSpecialty: 'Oncology',
        appointmentDate: now,
        timeSlot: '09:30 AM',
        status: 'confirmed', // Malicious attempt to bypass doctor approval
        createdAt: now,
      };

      const batch = db.batch();
      batch.set(db.doc(`appointments/${apptId}`), payload);
      batch.set(db.doc(`patients/patient_1/appointments/${apptId}`), payload);

      await assertFails(batch.commit());
    });

    test('Isolated global create without patient mirror is blocked', async () => {
      const patientContext = testEnv.authenticatedContext('patient_1');
      const db = patientContext.firestore();
      const apptId = 'appt_103';
      const now = new Date();

      const payload = {
        id: apptId,
        patientId: 'patient_1',
        patientName: 'Patient One',
        doctorId: 'doc_1',
        doctorName: 'Dr. Smith',
        doctorSpecialty: 'Oncology',
        appointmentDate: now,
        timeSlot: '09:30 AM',
        status: 'scheduled',
        createdAt: now,
      };

      // Writing only global, missing mirror
      await assertFails(db.doc(`appointments/${apptId}`).set(payload));
    });
  });

  // ── 4. STATE MACHINE & ACTOR TRANSITIONS ──
  describe('Appointment State Machine Transitions', () => {
    const apptId = 'appt_201';
    const now = new Date();

    beforeEach(async () => {
      await seedDoc('users/patient_1', { uid: 'patient_1', role: 'patient' });
      await seedDoc('users/doc_1', { uid: 'doc_1', role: 'doctor' });

      // Seed baseline scheduled appointment
      const baseAppt = {
        id: apptId,
        patientId: 'patient_1',
        doctorId: 'doc_1',
        appointmentDate: now,
        timeSlot: '09:30 AM',
        status: 'scheduled',
        createdAt: now,
      };
      await seedDoc(`appointments/${apptId}`, baseAppt);
      await seedDoc(`patients/patient_1/appointments/${apptId}`, baseAppt);
    });

    test('Direct client transition from "scheduled" to "confirmed" is blocked', async () => {
      const docContext = testEnv.authenticatedContext('doc_1');
      const db = docContext.firestore();

      const batch = db.batch();
      batch.update(db.doc(`appointments/${apptId}`), { status: 'confirmed' });
      batch.update(db.doc(`patients/patient_1/appointments/${apptId}`), { status: 'confirmed' });

      await assertFails(batch.commit());
    });

    test('Patient cannot mark appointment as completed', async () => {
      // Transition appointment to confirmed first via backend
      await seedDoc(`appointments/${apptId}`, {
        id: apptId,
        patientId: 'patient_1',
        doctorId: 'doc_1',
        appointmentDate: now,
        timeSlot: '09:30 AM',
        status: 'confirmed',
        createdAt: now,
      });
      await seedDoc(`patients/patient_1/appointments/${apptId}`, {
        id: apptId,
        patientId: 'patient_1',
        doctorId: 'doc_1',
        appointmentDate: now,
        timeSlot: '09:30 AM',
        status: 'confirmed',
        createdAt: now,
      });

      const patientContext = testEnv.authenticatedContext('patient_1');
      const db = patientContext.firestore();

      const batch = db.batch();
      batch.update(db.doc(`appointments/${apptId}`), { status: 'completed' });
      batch.update(db.doc(`patients/patient_1/appointments/${apptId}`), { status: 'completed' });

      await assertFails(batch.commit());
    });

    test('Doctor can complete a confirmed appointment', async () => {
      await seedDoc(`appointments/${apptId}`, {
        id: apptId,
        patientId: 'patient_1',
        doctorId: 'doc_1',
        appointmentDate: now,
        timeSlot: '09:30 AM',
        status: 'confirmed',
        createdAt: now,
      });
      await seedDoc(`patients/patient_1/appointments/${apptId}`, {
        id: apptId,
        patientId: 'patient_1',
        doctorId: 'doc_1',
        appointmentDate: now,
        timeSlot: '09:30 AM',
        status: 'confirmed',
        createdAt: now,
      });

      const docContext = testEnv.authenticatedContext('doc_1');
      const db = docContext.firestore();

      const batch = db.batch();
      batch.update(db.doc(`appointments/${apptId}`), { status: 'completed' });
      batch.update(db.doc(`patients/patient_1/appointments/${apptId}`), { status: 'completed' });

      await assertSucceeds(batch.commit());
    });

    test('Doctor cannot complete an unconfirmed scheduled appointment', async () => {
      const docContext = testEnv.authenticatedContext('doc_1');
      const db = docContext.firestore();

      const batch = db.batch();
      batch.update(db.doc(`appointments/${apptId}`), { status: 'completed' });
      batch.update(db.doc(`patients/patient_1/appointments/${apptId}`), { status: 'completed' });

      await assertFails(batch.commit());
    });

    test('Doctor can reject an unconfirmed scheduled appointment', async () => {
      const docContext = testEnv.authenticatedContext('doc_1');
      const db = docContext.firestore();

      const batch = db.batch();
      batch.update(db.doc(`appointments/${apptId}`), { status: 'rejected' });
      batch.update(db.doc(`patients/patient_1/appointments/${apptId}`), { status: 'rejected' });

      await assertSucceeds(batch.commit());
    });

    test('Terminal state immutability: completed appointment cannot be modified', async () => {
      await seedDoc(`appointments/${apptId}`, {
        id: apptId,
        patientId: 'patient_1',
        doctorId: 'doc_1',
        appointmentDate: now,
        timeSlot: '09:30 AM',
        status: 'completed',
        createdAt: now,
      });
      await seedDoc(`patients/patient_1/appointments/${apptId}`, {
        id: apptId,
        patientId: 'patient_1',
        doctorId: 'doc_1',
        appointmentDate: now,
        timeSlot: '09:30 AM',
        status: 'completed',
        createdAt: now,
      });

      const docContext = testEnv.authenticatedContext('doc_1');
      const db = docContext.firestore();

      const batch = db.batch();
      batch.update(db.doc(`appointments/${apptId}`), { status: 'scheduled' });
      batch.update(db.doc(`patients/patient_1/appointments/${apptId}`), { status: 'scheduled' });

      await assertFails(batch.commit());
    });
  });

  // ── 5. BOOKED-SLOT LOCK INVARIANTS ──
  describe('Booked-Slot Lock Protection', () => {
    const slotKey = '2026-10-20_09:30 AM';
    const apptId = 'appt_301';
    const now = new Date();

    beforeEach(async () => {
      await seedDoc('users/patient_1', { uid: 'patient_1', role: 'patient' });
      await seedDoc('users/patient_2', { uid: 'patient_2', role: 'patient' });
      await seedDoc('users/doc_1', { uid: 'doc_1', role: 'doctor' });

      await seedDoc(`appointments/${apptId}`, {
        id: apptId,
        patientId: 'patient_1',
        doctorId: 'doc_1',
        appointmentDate: now,
        timeSlot: '09:30 AM',
        status: 'confirmed',
        createdAt: now,
      });
      await seedDoc(`patients/patient_1/appointments/${apptId}`, {
        id: apptId,
        patientId: 'patient_1',
        doctorId: 'doc_1',
        appointmentDate: now,
        timeSlot: '09:30 AM',
        status: 'confirmed',
        createdAt: now,
      });
      await seedDoc(`bookedSlots/doc_1/slots/${slotKey}`, {
        appointmentId: apptId,
        patientId: 'patient_1',
        date: now,
        timeSlot: '09:30 AM',
        bookedAt: now,
      });
    });

    test('Client direct slot lock creation is blocked', async () => {
      const patientContext = testEnv.authenticatedContext('patient_1');
      await assertFails(
        patientContext.firestore().doc('bookedSlots/doc_1/slots/2026-10-21_10:00 AM').set({
          appointmentId: 'rogue_appt',
          patientId: 'patient_1',
        })
      );
    });

    test('Isolated slot lock deletion without appointment transition is blocked', async () => {
      const patientContext = testEnv.authenticatedContext('patient_1');
      await assertFails(
        patientContext.firestore().doc(`bookedSlots/doc_1/slots/${slotKey}`).delete()
      );
    });

    test('Foreign patient cannot delete slot lock', async () => {
      const foreignContext = testEnv.authenticatedContext('patient_2');
      const db = foreignContext.firestore();

      const batch = db.batch();
      batch.update(db.doc(`appointments/${apptId}`), { status: 'cancelled' });
      batch.update(db.doc(`patients/patient_1/appointments/${apptId}`), { status: 'cancelled' });
      batch.delete(db.doc(`bookedSlots/doc_1/slots/${slotKey}`));

      await assertFails(batch.commit());
    });

    test('Valid appointment cancellation safely deletes slot lock', async () => {
      const patientContext = testEnv.authenticatedContext('patient_1');
      const db = patientContext.firestore();

      const batch = db.batch();
      batch.update(db.doc(`appointments/${apptId}`), { status: 'cancelled' });
      batch.update(db.doc(`patients/patient_1/appointments/${apptId}`), { status: 'cancelled' });
      batch.delete(db.doc(`bookedSlots/doc_1/slots/${slotKey}`));

      await assertSucceeds(batch.commit());
    });

    test('Completed historical slot lock cannot be deleted', async () => {
      // Mark appointment completed
      await seedDoc(`appointments/${apptId}`, {
        id: apptId,
        patientId: 'patient_1',
        doctorId: 'doc_1',
        appointmentDate: now,
        timeSlot: '09:30 AM',
        status: 'completed',
        createdAt: now,
      });
      await seedDoc(`patients/patient_1/appointments/${apptId}`, {
        id: apptId,
        patientId: 'patient_1',
        doctorId: 'doc_1',
        appointmentDate: now,
        timeSlot: '09:30 AM',
        status: 'completed',
        createdAt: now,
      });

      const patientContext = testEnv.authenticatedContext('patient_1');
      const db = patientContext.firestore();

      // Attempting to delete slot lock of completed appointment
      await assertFails(
        db.doc(`bookedSlots/doc_1/slots/${slotKey}`).delete()
      );
    });
  });
});
