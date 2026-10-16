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

  // ── 7. BATCH 2B ANTI-TAMPER & BLOCKCHAIN PROOF SECURITY RULES ──
  describe('Batch 2B Anti-Tamper & Blockchain Proof Security Rules', () => {
    const patId = 'patient_proof_test';
    const recId = 'rec_anti_tamper_001';
    const now = new Date();

    beforeEach(async () => {
      // Seed user profile
      await seedDoc(`users/${patId}`, {
        uid: patId,
        role: 'patient',
        name: 'Proof Test Patient',
        email: 'proof@test.com',
      });
    });

    test('Legitimate clinical medical record creation without proof fields is allowed', async () => {
      const patientContext = testEnv.authenticatedContext(patId);
      const db = patientContext.firestore();

      await assertSucceeds(
        db.doc(`medical_records/${recId}`).set({
          id: recId,
          patientId: patId,
          title: 'Blood CBC Panel',
          type: 'report',
          subtype: 'Laboratory',
          facility: 'Oncology Clinic',
          fileUrl: 'https://storage.googleapis.com/test/cbc.pdf',
          fileHash: 'a'.repeat(64),
          isArchived: false,
          uploadedAt: now,
        })
      );
    });

    test('Malicious client attempting to inject fabricStatus on create is blocked', async () => {
      const patientContext = testEnv.authenticatedContext(patId);
      const db = patientContext.firestore();

      await assertFails(
        db.doc(`medical_records/${recId}`).set({
          id: recId,
          patientId: patId,
          title: 'Forged Record',
          type: 'report',
          fileUrl: 'https://storage.googleapis.com/test/forged.pdf',
          fileHash: 'b'.repeat(64),
          fabricStatus: 'COMMITTED', // Forged privilege field
          uploadedAt: now,
        })
      );
    });

    test('Malicious client attempting to inject fabricTxId on create is blocked', async () => {
      const patientContext = testEnv.authenticatedContext(patId);
      const db = patientContext.firestore();

      await assertFails(
        db.doc(`medical_records/${recId}`).set({
          id: recId,
          patientId: patId,
          title: 'Forged Record 2',
          type: 'report',
          fileUrl: 'https://storage.googleapis.com/test/forged2.pdf',
          fileHash: 'c'.repeat(64),
          fabricTxId: 'fake_fabric_tx_id_999',
          uploadedAt: now,
        })
      );
    });

    test('Direct client write to doctor_patient_consents is strictly blocked (fails closed)', async () => {
      const patientContext = testEnv.authenticatedContext(patId);
      const db = patientContext.firestore();

      await assertFails(
        db.doc(`doctor_patient_consents/${patId}_doc_1`).set({
          id: `${patId}_doc_1`,
          patientId: patId,
          doctorId: 'doc_1',
          scope: 'BLOOD_CANCER_RESEARCH',
          status: 'granted',
        })
      );
    });

    test('Client access to internal gateway_operations is completely denied (read & write)', async () => {
      const patientContext = testEnv.authenticatedContext(patId);
      const db = patientContext.firestore();

      await assertFails(
        db.doc('gateway_operations/op_secret_123').get()
      );
      await assertFails(
        db.doc('gateway_operations/op_secret_123').set({
          status: 'COMMITTED',
        })
      );
    });

    test('Malicious client attempting to tamper with fabricStatus on update is blocked', async () => {
      await seedDoc(`medical_records/${recId}`, {
        id: recId,
        patientId: patId,
        title: 'Original Record',
        type: 'report',
        fileUrl: 'https://storage.googleapis.com/test/original.pdf',
        fileHash: 'a'.repeat(64),
        uploadedAt: now,
      });

      const patientContext = testEnv.authenticatedContext(patId);
      const db = patientContext.firestore();

      await assertFails(
        db.doc(`medical_records/${recId}`).update({
          fabricStatus: 'COMMITTED',
        })
      );
    });

    test('Malicious client attempting to tamper with blockchainProof on update is blocked', async () => {
      await seedDoc(`medical_records/${recId}`, {
        id: recId,
        patientId: patId,
        title: 'Original Record',
        type: 'report',
        fileUrl: 'https://storage.googleapis.com/test/original.pdf',
        fileHash: 'a'.repeat(64),
        uploadedAt: now,
      });

      const patientContext = testEnv.authenticatedContext(patId);
      const db = patientContext.firestore();

      await assertFails(
        db.doc(`medical_records/${recId}`).update({
          blockchainProof: {
            txId: 'fake_tx_123',
            valid: true,
          },
        })
      );
    });

    test('Malicious patient attempting to write to another patient nested medical record is blocked', async () => {
      await seedDoc('users/patient_2', {
        uid: 'patient_2',
        role: 'patient',
        name: 'Foreign Patient',
      });
      const foreignPatientContext = testEnv.authenticatedContext('patient_2');
      const db = foreignPatientContext.firestore();

      await assertFails(
        db.doc(`patients/${patId}/medicalRecords/${recId}`).set({
          id: recId,
          patientId: patId,
          title: 'Unauthorized Nested Record',
          type: 'report',
          fileUrl: 'https://storage.googleapis.com/test/unauth.pdf',
          fileHash: 'a'.repeat(64),
          uploadedAt: now,
        })
      );
    });

    test('Patient attempting to inject fabricStatus in nested medical record is blocked', async () => {
      const patientContext = testEnv.authenticatedContext(patId);
      const db = patientContext.firestore();

      await assertFails(
        db.doc(`patients/${patId}/medicalRecords/${recId}`).set({
          id: recId,
          patientId: patId,
          title: 'Forged Nested Record',
          type: 'report',
          fileUrl: 'https://storage.googleapis.com/test/nested.pdf',
          fileHash: 'a'.repeat(64),
          fabricStatus: 'COMMITTED',
          uploadedAt: now,
        })
      );
    });
  });

  // ── 7. PHASE 3A: NURSE VITALS & CARE ASSIGNMENT SECURITY RULES ──
  describe('Phase 3A Nurse Vitals & Care Assignment Security', () => {
    const nurseId = 'nurse_jackie';
    const unassignedNurseId = 'nurse_stranger';
    const patId = 'pat_phase3a';
    const foreignPatId = 'pat_other';
    const docId = 'dr_thorne';
    const adminId = 'admin_sys';
    const obsId = 'obs_test_001';

    beforeEach(async () => {
      // Seed Users
      await seedDoc(`users/${nurseId}`, { uid: nurseId, role: 'nurse', name: 'Nurse Jackie' });
      await seedDoc(`users/${unassignedNurseId}`, { uid: unassignedNurseId, role: 'nurse', name: 'Nurse Stranger' });
      await seedDoc(`users/${patId}`, { uid: patId, role: 'patient', name: 'Phase3A Patient' });
      await seedDoc(`users/${foreignPatId}`, { uid: foreignPatId, role: 'patient', name: 'Foreign Patient' });
      await seedDoc(`users/${docId}`, { uid: docId, role: 'doctor', name: 'Dr. Thorne' });
      await seedDoc(`users/${adminId}`, { uid: adminId, role: 'admin', name: 'Admin Sys' });

      // Seed an active assignment for nurse_jackie to pat_phase3a
      await seedDoc(`nurse_patient_assignments/${nurseId}_${patId}`, {
        id: `${nurseId}_${patId}`,
        nurseId,
        patientId: patId,
        status: 'active',
        assignedBy: adminId,
        assignedAt: new Date(),
      });
    });

    test('Nurse attempting self-assignment via direct client write is strictly blocked', async () => {
      const nurseContext = testEnv.authenticatedContext(unassignedNurseId);
      const db = nurseContext.firestore();

      await assertFails(
        db.doc(`nurse_patient_assignments/${unassignedNurseId}_${patId}`).set({
          id: `${unassignedNurseId}_${patId}`,
          nurseId: unassignedNurseId,
          patientId: patId,
          status: 'active',
          assignedBy: unassignedNurseId,
        })
      );
    });

    test('Direct client writes to nurse_patient_assignments are strictly blocked (callable-only backend)', async () => {
      const adminContext = testEnv.authenticatedContext(adminId);
      const db = adminContext.firestore();

      await assertFails(
        db.doc(`nurse_patient_assignments/${unassignedNurseId}_${patId}`).set({
          id: `${unassignedNurseId}_${patId}`,
          nurseId: unassignedNurseId,
          patientId: patId,
          status: 'active',
          assignedBy: adminId,
        })
      );
    });

    test('Actively assigned nurse can read patient ehr_vitals and observations', async () => {
      await seedDoc(`ehr_vitals/${patId}`, {
        bloodPressure: '120/80 mmHg',
        updatedAt: new Date(),
      });

      const nurseContext = testEnv.authenticatedContext(nurseId);
      const db = nurseContext.firestore();

      await assertSucceeds(db.doc(`ehr_vitals/${patId}`).get());
    });

    test('Unassigned nurse is blocked from reading patient ehr_vitals', async () => {
      await seedDoc(`ehr_vitals/${patId}`, {
        bloodPressure: '120/80 mmHg',
        updatedAt: new Date(),
      });

      const unassignedContext = testEnv.authenticatedContext(unassignedNurseId);
      const db = unassignedContext.firestore();

      await assertFails(db.doc(`ehr_vitals/${patId}`).get());
    });

    test('Patient can read their own vitals, but cannot read foreign patient vitals', async () => {
      await seedDoc(`ehr_vitals/${patId}`, { bloodPressure: '120/80 mmHg' });

      const patientContext = testEnv.authenticatedContext(patId);
      const db = patientContext.firestore();
      await assertSucceeds(db.doc(`ehr_vitals/${patId}`).get());

      const foreignContext = testEnv.authenticatedContext(foreignPatId);
      const foreignDb = foreignContext.firestore();
      await assertFails(foreignDb.doc(`ehr_vitals/${patId}`).get());
    });

    test('Direct client observation write is blocked even for assigned nurse (must route via Cloud Function)', async () => {
      const nurseContext = testEnv.authenticatedContext(nurseId);
      const db = nurseContext.firestore();

      await assertFails(
        db.doc(`ehr_vitals/${patId}/observations/${obsId}`).set({
          id: obsId,
          patientId: patId,
          nurseId,
          nurseName: 'Nurse Jackie',
          recordedAt: new Date(),
          systolicBp: 120,
          diastolicBp: 80,
          pulseRate: 72,
          temperature: 37.0,
          respiratoryRate: 16,
          oxygenSaturation: 98,
        })
      );
    });

    test('Direct client write to latest-vitals cache is blocked', async () => {
      const nurseContext = testEnv.authenticatedContext(nurseId);
      const db = nurseContext.firestore();

      await assertFails(
        db.doc(`ehr_vitals/${patId}`).set({
          bloodPressure: '120/80 mmHg',
          updatedAt: new Date(),
        })
      );
    });

    test('Unassigned nurse is blocked from creating vital observation', async () => {
      const unassignedContext = testEnv.authenticatedContext(unassignedNurseId);
      const db = unassignedContext.firestore();

      await assertFails(
        db.doc(`ehr_vitals/${patId}/observations/${obsId}`).set({
          id: obsId,
          patientId: patId,
          nurseId: unassignedNurseId,
          nurseName: 'Nurse Stranger',
          recordedAt: new Date(),
          systolicBp: 120,
          diastolicBp: 80,
          pulseRate: 72,
          temperature: 37.0,
          respiratoryRate: 16,
          oxygenSaturation: 98,
        })
      );
    });

    test('Nurse attempting to spoof another nurse UID is blocked', async () => {
      const nurseContext = testEnv.authenticatedContext(nurseId);
      const db = nurseContext.firestore();

      await assertFails(
        db.doc(`ehr_vitals/${patId}/observations/${obsId}`).set({
          id: obsId,
          patientId: patId,
          nurseId: 'fake_nurse_uid', // Spoof attempt
          nurseName: 'Fake Nurse',
          recordedAt: new Date(),
          systolicBp: 120,
          diastolicBp: 80,
          pulseRate: 72,
          temperature: 37.0,
          respiratoryRate: 16,
          oxygenSaturation: 98,
        })
      );
    });

    test('Observation with out-of-range clinical bounds is rejected by security rules', async () => {
      const nurseContext = testEnv.authenticatedContext(nurseId);
      const db = nurseContext.firestore();

      // Systolic BP 300 is above permissible max 250
      await assertFails(
        db.doc(`ehr_vitals/${patId}/observations/${obsId}`).set({
          id: obsId,
          patientId: patId,
          nurseId,
          nurseName: 'Nurse Jackie',
          recordedAt: new Date(),
          systolicBp: 300,
          diastolicBp: 80,
          pulseRate: 72,
          temperature: 37.0,
          respiratoryRate: 16,
          oxygenSaturation: 98,
        })
      );
    });

    test('Patient attempting to write vital observation is blocked (strictly read-only)', async () => {
      const patientContext = testEnv.authenticatedContext(patId);
      const db = patientContext.firestore();

      await assertFails(
        db.doc(`ehr_vitals/${patId}/observations/${obsId}`).set({
          id: obsId,
          patientId: patId,
          nurseId: patId,
          nurseName: 'Patient Self',
          recordedAt: new Date(),
          systolicBp: 120,
          diastolicBp: 80,
          pulseRate: 72,
          temperature: 37.0,
          respiratoryRate: 16,
          oxygenSaturation: 98,
        })
      );
    });

    test('Historical observations are strictly IMMUTABLE (update and delete are blocked)', async () => {
      await seedDoc(`ehr_vitals/${patId}/observations/${obsId}`, {
        id: obsId,
        patientId: patId,
        nurseId,
        nurseName: 'Nurse Jackie',
        systolicBp: 120,
        diastolicBp: 80,
        pulseRate: 72,
        temperature: 37.0,
        respiratoryRate: 16,
        oxygenSaturation: 98,
      });

      const nurseContext = testEnv.authenticatedContext(nurseId);
      const db = nurseContext.firestore();

      // Update attempt must fail
      await assertFails(
        db.doc(`ehr_vitals/${patId}/observations/${obsId}`).update({
          systolicBp: 130,
        })
      );

      // Delete attempt must fail
      await assertFails(
        db.doc(`ehr_vitals/${patId}/observations/${obsId}`).delete()
      );
    });

    test('Nurse cannot create phantom reports_uploaded record without active patient assignment', async () => {
      // Seed a real medical record
      const testReportId = 'rep_unassigned_test_01';
      await seedDoc(`medical_records/${testReportId}`, {
        id: testReportId,
        patientId: patId,
        title: 'CBC Report',
      });

      const unassignedContext = testEnv.authenticatedContext(unassignedNurseId);
      const db = unassignedContext.firestore();

      // Nurse Stranger is NOT assigned to patId -> must be rejected
      await assertFails(
        db.doc(`nurses/${unassignedNurseId}/reports_uploaded/${testReportId}`).set({
          reportId: testReportId,
          patientId: patId,
          uploadedAt: new Date(),
        })
      );
    });

    test('Nurse cannot create phantom reports_uploaded record when referenced medical record does not exist', async () => {
      const ghostReportId = 'rep_phantom_ghost_999';
      const nurseContext = testEnv.authenticatedContext(nurseId);
      const db = nurseContext.firestore();

      // Nurse Jackie is assigned to patId, but rep_phantom_ghost_999 does not exist in medical_records
      await assertFails(
        db.doc(`nurses/${nurseId}/reports_uploaded/${ghostReportId}`).set({
          reportId: ghostReportId,
          patientId: patId,
          uploadedAt: new Date(),
        })
      );
    });

    test('Nurse can create reports_uploaded record when actively assigned and referenced medical record exists with matching uploadedBy', async () => {
      const validReportId = 'rep_legit_verified_01';
      await seedDoc(`medical_records/${validReportId}`, {
        id: validReportId,
        patientId: patId,
        title: 'Verified Lab CBC',
        uploadedBy: nurseId, // Authoritative uploader is nurse_jackie
      });

      const nurseContext = testEnv.authenticatedContext(nurseId);
      const db = nurseContext.firestore();

      await assertSucceeds(
        db.doc(`nurses/${nurseId}/reports_uploaded/${validReportId}`).set({
          reportId: validReportId,
          patientId: patId,
          uploadedAt: new Date(),
        })
      );

      // Verify anti-tamper: nurse cannot mutate or delete the verified metric record
      await assertFails(
        db.doc(`nurses/${nurseId}/reports_uploaded/${validReportId}`).update({
          patientId: foreignPatId,
        })
      );
      await assertFails(
        db.doc(`nurses/${nurseId}/reports_uploaded/${validReportId}`).delete()
      );
    });

    test('Nurse B cannot claim Nurse A uploaded report even if both are assigned to the same patient', async () => {
      const nurseAReportId = 'rep_nurse_a_exclusive';
      // Seed medical record uploaded by nurse_jackie
      await seedDoc(`medical_records/${nurseAReportId}`, {
        id: nurseAReportId,
        patientId: patId,
        title: 'Nurse Jackie Lab Upload',
        uploadedBy: nurseId, // Authoritative uploader is nurse_jackie
      });

      // Seed active care assignment for Nurse Stranger to patId
      await seedDoc(`nurse_patient_assignments/${unassignedNurseId}_${patId}`, {
        id: `${unassignedNurseId}_${patId}`,
        nurseId: unassignedNurseId,
        patientId: patId,
        status: 'active',
        assignedBy: adminId,
        assignedAt: new Date(),
      });

      const strangerContext = testEnv.authenticatedContext(unassignedNurseId);
      const strangerDb = strangerContext.firestore();

      // Nurse Stranger attempts to claim Nurse Jackie's report in their own reports_uploaded
      await assertFails(
        strangerDb.doc(`nurses/${unassignedNurseId}/reports_uploaded/${nurseAReportId}`).set({
          reportId: nurseAReportId,
          patientId: patId,
          uploadedAt: new Date(),
        })
      );
    });
  });

  describe('Phase 3B Critical Vital Alerts & Pipeline Security', () => {
    const docId = 'doc_rule_test_3b';
    const strangerDocId = 'doc_stranger_3b';
    const patId = 'pat_rule_test_3b';
    const alertId = 'alert_test_3b_001';
    const eventId = 'event_test_3b_001';

    beforeEach(async () => {
      await seedDoc(`users/${docId}`, { uid: docId, role: 'doctor', hospitalId: 'Oncology Ward 3A' });
      await seedDoc(`users/${strangerDocId}`, { uid: strangerDocId, role: 'doctor', hospitalId: 'Oncology Ward 3A' });
      await seedDoc(`users/${patId}`, { uid: patId, role: 'patient', hospitalId: 'Oncology Ward 3A' });

      // Seed authoritative alert in docId inbox
      await seedDoc(`doctors/${docId}/alerts/${alertId}`, {
        id: alertId,
        alertId: alertId,
        doctorId: docId,
        patientId: patId,
        alertType: 'vital_alert',
        severity: 'high',
        isRead: false,
        isAcknowledged: false,
        isResolved: false,
        createdAt: new Date(),
      });
    });

    test('Client direct write to critical_alert_events is strictly blocked', async () => {
      const docContext = testEnv.authenticatedContext(docId);
      const db = docContext.firestore();

      await assertFails(
        db.doc(`critical_alert_events/${eventId}`).set({
          eventId,
          patientId: patId,
          status: 'PENDING',
        })
      );
    });

    test('Client direct creation of doctor critical alert is blocked (anti-forgery)', async () => {
      const docContext = testEnv.authenticatedContext(docId);
      const db = docContext.firestore();

      await assertFails(
        db.doc(`doctors/${docId}/alerts/forged_alert_001`).set({
          id: 'forged_alert_001',
          doctorId: docId,
          patientId: patId,
          alertType: 'vital_alert',
          severity: 'high',
          isAcknowledged: false,
        })
      );
    });

    test('Doctor can read their own critical alerts', async () => {
      const docContext = testEnv.authenticatedContext(docId);
      const db = docContext.firestore();

      await assertSucceeds(db.doc(`doctors/${docId}/alerts/${alertId}`).get());
    });

    test('Foreign doctor cannot read another doctor critical alerts', async () => {
      const strangerContext = testEnv.authenticatedContext(strangerDocId);
      const db = strangerContext.firestore();

      await assertFails(db.doc(`doctors/${docId}/alerts/${alertId}`).get());
    });

    test('Doctor can update isRead on their alert, but cannot mutate clinical or acknowledgment fields directly', async () => {
      const docContext = testEnv.authenticatedContext(docId);
      const db = docContext.firestore();

      // Updating isRead alone succeeds
      await assertSucceeds(db.doc(`doctors/${docId}/alerts/${alertId}`).update({ isRead: true }));

      // Attempting to directly mutate isAcknowledged via client write is blocked
      await assertFails(db.doc(`doctors/${docId}/alerts/${alertId}`).update({ isAcknowledged: true }));

      // Attempting to directly mutate isResolved via client write is blocked
      await assertFails(db.doc(`doctors/${docId}/alerts/${alertId}`).update({ isResolved: true }));
    });

    test('Direct deletion of critical alerts is strictly blocked (audit trail immutability)', async () => {
      const docContext = testEnv.authenticatedContext(docId);
      const db = docContext.firestore();

      await assertFails(db.doc(`doctors/${docId}/alerts/${alertId}`).delete());
    });
  });

  describe('Phase 3B.1 Escalated Alerts Security & Hospital Isolation', () => {
    const hospA = 'Oncology Ward 3A';
    const hospB = 'Hematology Ward 5B';

    const adminA = 'admin_hosp_a';
    const adminB = 'admin_hosp_b';
    const docA_assigned = 'doc_a_assigned';
    const docA_stranger = 'doc_a_stranger';
    const nurseA_assigned = 'nurse_a_assigned';
    const nurseA_unassigned = 'nurse_a_unassigned';
    const patA = 'pat_hosp_a';
    const escId = 'esc_security_test_001';

    beforeEach(async () => {
      // Seed users
      await seedDoc(`users/${adminA}`, { uid: adminA, role: 'admin', hospitalId: hospA });
      await seedDoc(`users/${adminB}`, { uid: adminB, role: 'admin', hospitalId: hospB });
      await seedDoc(`users/${docA_assigned}`, { uid: docA_assigned, role: 'doctor', hospitalId: hospA });
      await seedDoc(`users/${docA_stranger}`, { uid: docA_stranger, role: 'doctor', hospitalId: hospA });
      await seedDoc(`users/${nurseA_assigned}`, { uid: nurseA_assigned, role: 'nurse', hospitalId: hospA });
      await seedDoc(`users/${nurseA_unassigned}`, { uid: nurseA_unassigned, role: 'nurse', hospitalId: hospA });
      await seedDoc(`users/${patA}`, { uid: patA, role: 'patient', hospitalId: hospA });

      // Seed nurse assignment for nurseA_assigned to patA
      await seedDoc(`nurse_patient_assignments/${nurseA_assigned}_${patA}`, {
        nurseId: nurseA_assigned,
        patientId: patA,
        status: 'active',
      });

      // Seed granted Fabric consent for docA_assigned to patA
      await seedDoc(`doctor_patient_consents/${patA}_${docA_assigned}`, {
        patientId: patA,
        doctorId: docA_assigned,
        status: 'granted',
      });

      // Seed authoritative escalated alert for patA in hospA
      await seedDoc(`escalated_alerts/${escId}`, {
        id: escId,
        observationId: 'obs_esc_001',
        patientId: patA,
        hospitalId: hospA,
        doctorId: docA_assigned,
        status: 'ACTIVE_ESCALATION',
        reason: 'Severe Hypoxemia SpO2 86%',
      });
    });

    test('Same-hospital administrator can read escalated alert', async () => {
      const ctx = testEnv.authenticatedContext(adminA);
      await assertSucceeds(ctx.firestore().doc(`escalated_alerts/${escId}`).get());
    });

    test('Foreign-hospital administrator is BLOCKED from reading escalated alert (hospital isolation)', async () => {
      const ctx = testEnv.authenticatedContext(adminB);
      await assertFails(ctx.firestore().doc(`escalated_alerts/${escId}`).get());
    });

    test('Actively assigned nurse in same hospital can read escalated alert', async () => {
      const ctx = testEnv.authenticatedContext(nurseA_assigned);
      await assertSucceeds(ctx.firestore().doc(`escalated_alerts/${escId}`).get());
    });

    test('Unassigned nurse in same hospital is BLOCKED from reading escalated alert', async () => {
      const ctx = testEnv.authenticatedContext(nurseA_unassigned);
      await assertFails(ctx.firestore().doc(`escalated_alerts/${escId}`).get());
    });

    test('Authorized doctor with granted consent in same hospital can read escalated alert', async () => {
      const ctx = testEnv.authenticatedContext(docA_assigned);
      await assertSucceeds(ctx.firestore().doc(`escalated_alerts/${escId}`).get());
    });

    test('Unrelated doctor in same hospital without consent is BLOCKED from reading escalated alert', async () => {
      const ctx = testEnv.authenticatedContext(docA_stranger);
      await assertFails(ctx.firestore().doc(`escalated_alerts/${escId}`).get());
    });

    test('Patient is strictly BLOCKED from reading escalated alerts', async () => {
      const ctx = testEnv.authenticatedContext(patA);
      await assertFails(ctx.firestore().doc(`escalated_alerts/${escId}`).get());
    });

    test('Direct client write to escalated_alerts is strictly BLOCKED', async () => {
      const ctx = testEnv.authenticatedContext(adminA);
      await assertFails(
        ctx.firestore().doc(`escalated_alerts/client_forged_esc`).set({
          id: 'client_forged_esc',
          patientId: patA,
          hospitalId: hospA,
        })
      );
    });
  });
});
