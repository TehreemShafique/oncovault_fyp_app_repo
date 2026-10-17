// functions/test/treatment_plans.test.ts
import * as admin from 'firebase-admin';
import {
  createTreatmentPlanHandler,
  completeTreatmentTaskHandler,
  recordTreatmentProgressUpdateHandler,
  updateTreatmentPlanStatusHandler,
} from '../src/manage_treatment_plan';

const PROJECT_ID = process.env.GCLOUD_PROJECT || 'demo-no-project';

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
}

if (!admin.apps.length) {
  admin.initializeApp({ projectId: PROJECT_ID });
}

const db = admin.firestore();

jest.setTimeout(60000);

describe('Phase 3D.1 Treatment Plan Backend Operations & Security Tests', () => {
  const hospA = 'Oncology Ward 3D-A';
  const hospB = 'Foreign Hospital 3D-B';

  const docAttending = 'doc_3d_attending';
  const docUnrelated = 'doc_3d_unrelated';
  const docForeign = 'doc_3d_foreign';

  const nurseAssigned = 'nurse_3d_assigned';
  const nurseUnassigned = 'nurse_3d_unassigned';
  const nurseForeign = 'nurse_3d_foreign';
  const nurseRevoked = 'nurse_3d_revoked';
  const nurseOtherPatient = 'nurse_3d_other_pat';
  const nurseInconsistent = 'nurse_3d_inconsistent';
  const nurseLegacy = 'nurse_3d_legacy';
  const nurseNoHosp = 'nurse_3d_no_hosp';
  const houseOfficer = 'user_3d_house_officer';

  const patientA = 'pat_3d_main';
  const patientForeign = 'pat_3d_foreign';

  beforeAll(async () => {
    const batch = db.batch();

    // Users
    batch.set(db.collection('users').doc(docAttending), {
      uid: docAttending,
      role: 'doctor',
      name: 'Dr. House',
      hospitalId: hospA,
    });
    batch.set(db.collection('users').doc(docUnrelated), {
      uid: docUnrelated,
      role: 'doctor',
      name: 'Dr. Unrelated',
      hospitalId: hospA,
    });
    batch.set(db.collection('users').doc(docForeign), {
      uid: docForeign,
      role: 'doctor',
      name: 'Dr. Foreign',
      hospitalId: hospB,
    });

    batch.set(db.collection('users').doc(nurseAssigned), {
      uid: nurseAssigned,
      role: 'nurse',
      name: 'Nurse Sara',
      hospitalId: hospA,
    });
    batch.set(db.collection('users').doc(nurseUnassigned), {
      uid: nurseUnassigned,
      role: 'nurse',
      name: 'Nurse Stranger',
      hospitalId: hospA,
    });
    batch.set(db.collection('users').doc(nurseForeign), {
      uid: nurseForeign,
      role: 'nurse',
      name: 'Nurse Foreign',
      hospitalId: hospB,
    });
    batch.set(db.collection('users').doc(nurseRevoked), {
      uid: nurseRevoked,
      role: 'nurse',
      name: 'Nurse Revoked',
      hospitalId: hospA,
    });
    batch.set(db.collection('users').doc(nurseOtherPatient), {
      uid: nurseOtherPatient,
      role: 'nurse',
      name: 'Nurse Other Patient',
      hospitalId: hospA,
    });
    batch.set(db.collection('users').doc(nurseInconsistent), {
      uid: nurseInconsistent,
      role: 'nurse',
      name: 'Nurse Inconsistent',
      hospitalId: hospA,
    });
    batch.set(db.collection('users').doc(nurseLegacy), {
      uid: nurseLegacy,
      role: 'nurse',
      name: 'Nurse Legacy',
      hospitalId: hospA,
    });
    batch.set(db.collection('users').doc(nurseNoHosp), {
      uid: nurseNoHosp,
      role: 'nurse',
      name: 'Nurse No Hosp',
      hospitalId: hospA,
    });
    batch.set(db.collection('users').doc(houseOfficer), {
      uid: houseOfficer,
      role: 'house_officer',
      name: 'Dr. Junior HO',
      hospitalId: hospA,
    });

    batch.set(db.collection('users').doc(patientA), {
      uid: patientA,
      role: 'patient',
      name: 'Alice Patient',
      hospitalId: hospA,
    });
    batch.set(db.collection('users').doc(patientForeign), {
      uid: patientForeign,
      role: 'patient',
      name: 'Bob Foreign Patient',
      hospitalId: hospB,
    });

    // Patient Profiles
    batch.set(db.collection('patients').doc(patientA), {
      uid: patientA,
      name: 'Alice Patient',
      hospitalId: hospA,
    });
    batch.set(db.collection('patients').doc(patientForeign), {
      uid: patientForeign,
      name: 'Bob Foreign Patient',
      hospitalId: hospB,
    });

    // Doctor Care Consent: docAttending -> patientA
    batch.set(db.collection('doctor_patient_consents').doc(`${patientA}_${docAttending}`), {
      patientId: patientA,
      doctorId: docAttending,
      status: 'granted',
      hospitalId: hospA,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Active Care Assignment: nurseAssigned -> patientA
    batch.set(db.collection('nurse_patient_assignments').doc(`${nurseAssigned}_${patientA}`), {
      id: `${nurseAssigned}_${patientA}`,
      nurseId: nurseAssigned,
      nurseName: 'Nurse Sara',
      patientId: patientA,
      patientName: 'Alice Patient',
      hospitalId: hospA,
      status: 'active',
      assignedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Revoked assignment: nurseRevoked -> patientA
    batch.set(db.collection('nurse_patient_assignments').doc(`${nurseRevoked}_${patientA}`), {
      id: `${nurseRevoked}_${patientA}`,
      nurseId: nurseRevoked,
      nurseName: 'Nurse Revoked',
      patientId: patientA,
      patientName: 'Alice Patient',
      hospitalId: hospA,
      status: 'revoked',
      revokedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Assignment for another patient: nurseOtherPatient -> patientForeign
    batch.set(db.collection('nurse_patient_assignments').doc(`${nurseOtherPatient}_${patientForeign}`), {
      id: `${nurseOtherPatient}_${patientForeign}`,
      nurseId: nurseOtherPatient,
      nurseName: 'Nurse Other Patient',
      patientId: patientForeign,
      patientName: 'Bob Foreign Patient',
      hospitalId: hospA,
      status: 'active',
      assignedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Inconsistent assignment: isActive: true but status: 'revoked'
    batch.set(db.collection('nurse_patient_assignments').doc(`${nurseInconsistent}_${patientA}`), {
      id: `${nurseInconsistent}_${patientA}`,
      nurseId: nurseInconsistent,
      nurseName: 'Nurse Inconsistent',
      patientId: patientA,
      patientName: 'Alice Patient',
      hospitalId: hospA,
      isActive: true,
      status: 'revoked',
      assignedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Legacy assignment: isActive: true without status: 'active'
    batch.set(db.collection('nurse_patient_assignments').doc(`${nurseLegacy}_${patientA}`), {
      id: `${nurseLegacy}_${patientA}`,
      nurseId: nurseLegacy,
      nurseName: 'Nurse Legacy',
      patientId: patientA,
      patientName: 'Alice Patient',
      hospitalId: hospA,
      isActive: true,
      assignedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Assignment with missing hospitalId: nurseNoHosp -> patientA
    batch.set(db.collection('nurse_patient_assignments').doc(`${nurseNoHosp}_${patientA}`), {
      id: `${nurseNoHosp}_${patientA}`,
      nurseId: nurseNoHosp,
      nurseName: 'Nurse No Hosp',
      patientId: patientA,
      patientName: 'Alice Patient',
      status: 'active',
      assignedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await batch.commit();
  });

  describe('createTreatmentPlan', () => {
    test('Unauthenticated caller is rejected with unauthenticated', async () => {
      await expect(
        createTreatmentPlanHandler({
          auth: undefined,
          data: { patientId: patientA, title: 'Plan', clinicalObjectives: 'Objectives', tasks: [{ title: 'Task 1' }] },
        })
      ).rejects.toThrow('User must be authenticated.');
    });

    test('Nurse cannot create treatment plan (doctor only)', async () => {
      await expect(
        createTreatmentPlanHandler({
          auth: { uid: nurseAssigned },
          data: { patientId: patientA, title: 'Plan', clinicalObjectives: 'Objectives', tasks: [{ title: 'Task 1' }] },
        })
      ).rejects.toThrow('Only authorized attending physicians can author or manage treatment plans.');
    });

    test('Unrelated doctor (no consent/appointment) cannot create treatment plan', async () => {
      await expect(
        createTreatmentPlanHandler({
          auth: { uid: docUnrelated },
          data: { patientId: patientA, title: 'Plan', clinicalObjectives: 'Objectives', tasks: [{ title: 'Task 1' }] },
        })
      ).rejects.toThrow();
    });

    test('Cross-hospital doctor is rejected by hospital boundary check', async () => {
      await expect(
        createTreatmentPlanHandler({
          auth: { uid: docForeign },
          data: { patientId: patientA, title: 'Plan', clinicalObjectives: 'Objectives', tasks: [{ title: 'Task 1' }] },
        })
      ).rejects.toThrow('Hospital boundary violation');
    });

    test('Rejects invalid input (empty title, invalid task count, or empty objectives)', async () => {
      // Empty title
      await expect(
        createTreatmentPlanHandler({
          auth: { uid: docAttending },
          data: { patientId: patientA, title: '  ', clinicalObjectives: 'Objectives', tasks: [{ title: 'Task 1' }] },
        })
      ).rejects.toThrow('Plan title must be between 3 and 200 characters.');

      // Empty tasks array
      await expect(
        createTreatmentPlanHandler({
          auth: { uid: docAttending },
          data: { patientId: patientA, title: 'Valid Plan', clinicalObjectives: 'Objectives', tasks: [] },
        })
      ).rejects.toThrow('Treatment plan must contain between 1 and 50 tasks.');
    });

    test('Authorized attending doctor successfully creates treatment plan with tasks atomically', async () => {
      const res = await createTreatmentPlanHandler({
        auth: { uid: docAttending },
        data: {
          patientId: patientA,
          title: 'AML Induction Protocol Plan',
          clinicalObjectives: 'Complete induction course and assess bone marrow response.',
          tasks: [
            { title: 'Administer IV Hydration 1000mL', instructions: 'Infuse over 4 hours' },
            { title: 'Vital signs pre-medication check', instructions: 'Record BP, HR, Temp' },
          ],
        },
      });

      expect(res.success).toBe(true);
      expect(res.planId).toBeDefined();
      expect(res.totalTasks).toBe(2);
      expect(res.status).toBe('active');

      const planDoc = await db
        .collection('patients')
        .doc(patientA)
        .collection('treatment_plans')
        .doc(res.planId)
        .get();

      expect(planDoc.exists).toBe(true);
      const data = planDoc.data()!;
      expect(data.doctorId).toBe(docAttending);
      expect(data.doctorName).toBe('Dr. House');
      expect(data.hospitalId).toBe(hospA);
      expect(data.completedTasks).toBe(0);
      expect(data.totalTasks).toBe(2);

      const tasksSnap = await planDoc.ref.collection('tasks').get();
      expect(tasksSnap.docs.length).toBe(2);
      expect(tasksSnap.docs[0].data().status).toBe('pending');
    });

    test('Idempotent submission returns success without duplicating', async () => {
      const customPlanId = 'plan_idempotent_test';
      const payload = {
        planId: customPlanId,
        patientId: patientA,
        title: 'Idempotent Plan Test',
        clinicalObjectives: 'Verify idempotency handling.',
        tasks: [{ title: 'Check vitals' }],
      };

      const res1 = await createTreatmentPlanHandler({ auth: { uid: docAttending }, data: payload });
      expect(res1.planId).toBe(customPlanId);

      const res2 = await createTreatmentPlanHandler({ auth: { uid: docAttending }, data: payload });
      expect(res2.planId).toBe(customPlanId);
    });
  });

  describe('completeTreatmentTask', () => {
    let testPlanId: string;
    let taskId1: string;
    let taskId2: string;

    beforeEach(async () => {
      const planRes = await createTreatmentPlanHandler({
        auth: { uid: docAttending },
        data: {
          patientId: patientA,
          title: 'Execution Test Plan',
          clinicalObjectives: 'Test nurse task execution and counter increment.',
          tasks: [
            { title: 'Task 1: Pre-treatment IV infusion' },
            { title: 'Task 2: Post-treatment observation' },
          ],
        },
      });
      testPlanId = planRes.planId;

      const tasksSnap = await db
        .collection('patients')
        .doc(patientA)
        .collection('treatment_plans')
        .doc(testPlanId)
        .collection('tasks')
        .get();

      taskId1 = tasksSnap.docs[0].id;
      taskId2 = tasksSnap.docs[1].id;
    });

    test('Unassigned nurse cannot complete task (FR-M3.5)', async () => {
      await expect(
        completeTreatmentTaskHandler({
          auth: { uid: nurseUnassigned },
          data: { patientId: patientA, planId: testPlanId, taskId: taskId1 },
        })
      ).rejects.toThrow('Nurse is not actively assigned to patient');
    });

    test('Doctor cannot complete nurse treatment task (role isolation)', async () => {
      await expect(
        completeTreatmentTaskHandler({
          auth: { uid: docAttending },
          data: { patientId: patientA, planId: testPlanId, taskId: taskId1 },
        })
      ).rejects.toThrow('Only assigned nurses can execute and complete treatment tasks.');
    });

    test('House Officer role cannot execute completeTreatmentTask without supported role', async () => {
      await expect(
        completeTreatmentTaskHandler({
          auth: { uid: houseOfficer },
          data: { patientId: patientA, planId: testPlanId, taskId: taskId1 },
        })
      ).rejects.toThrow('Only assigned nurses can execute and complete treatment tasks.');
    });

    test('Revoked nurse assignment is rejected with permission-denied', async () => {
      await expect(
        completeTreatmentTaskHandler({
          auth: { uid: nurseRevoked },
          data: { patientId: patientA, planId: testPlanId, taskId: taskId1 },
        })
      ).rejects.toThrow('is not active (status: revoked)');
    });

    test('Assignment belonging to another patient fails with permission-denied', async () => {
      await expect(
        completeTreatmentTaskHandler({
          auth: { uid: nurseOtherPatient },
          data: { patientId: patientA, planId: testPlanId, taskId: taskId1 },
        })
      ).rejects.toThrow('is not actively assigned to patient');
    });

    test('Inconsistent assignment (isActive: true but status: revoked) cannot silently grant access', async () => {
      await expect(
        completeTreatmentTaskHandler({
          auth: { uid: nurseInconsistent },
          data: { patientId: patientA, planId: testPlanId, taskId: taskId1 },
        })
      ).rejects.toThrow('is not active (status: revoked)');
    });

    test('Legacy assignment (isActive: true without status: active) cannot grant access', async () => {
      await expect(
        completeTreatmentTaskHandler({
          auth: { uid: nurseLegacy },
          data: { patientId: patientA, planId: testPlanId, taskId: taskId1 },
        })
      ).rejects.toThrow('is not active');
    });

    test('Cross-hospital nurse is rejected by hospital boundary check', async () => {
      await expect(
        completeTreatmentTaskHandler({
          auth: { uid: nurseForeign },
          data: { patientId: patientA, planId: testPlanId, taskId: taskId1 },
        })
      ).rejects.toThrow('Hospital boundary violation');
    });

    test('Assignment with missing or empty hospitalId fails closed with permission-denied', async () => {
      await expect(
        completeTreatmentTaskHandler({
          auth: { uid: nurseNoHosp },
          data: { patientId: patientA, planId: testPlanId, taskId: taskId1 },
        })
      ).rejects.toThrow('Hospital scope mismatch or missing');
    });

    test('Assigned nurse completes task: records server-authoritative identity and increments counter (BR-3.6)', async () => {
      const res = await completeTreatmentTaskHandler({
        auth: { uid: nurseAssigned },
        data: {
          patientId: patientA,
          planId: testPlanId,
          taskId: taskId1,
          executionRemarks: 'Infusion completed on schedule without adverse reactions.',
        },
      });

      expect(res.success).toBe(true);
      expect(res.taskId).toBe(taskId1);

      // Verify task document
      const taskDoc = await db
        .collection('patients')
        .doc(patientA)
        .collection('treatment_plans')
        .doc(testPlanId)
        .collection('tasks')
        .doc(taskId1)
        .get();

      const taskData = taskDoc.data()!;
      expect(taskData.status).toBe('completed');
      expect(taskData.completedByNurseId).toBe(nurseAssigned); // Authoritative non-repudiation
      expect(taskData.completedByNurseName).toBe('Nurse Sara');
      expect(taskData.executionRemarks).toContain('Infusion completed');
      expect(taskData.completedAt).toBeDefined();

      // Verify parent plan counter increment
      const planDoc = await db
        .collection('patients')
        .doc(patientA)
        .collection('treatment_plans')
        .doc(testPlanId)
        .get();

      expect(planDoc.data()!.completedTasks).toBe(1);

      // Verify gateway_operations record enqueued for Phase 3D.2 Fabric reconciliation
      const opDoc = await db.collection('gateway_operations').doc(`op_task_${patientA}_${testPlanId}_${taskId1}`).get();
      expect(opDoc.exists).toBe(true);
      const opData = opDoc.data()!;
      expect(opData.status).toBe('PENDING');
      expect(opData.recordType).toBe('TREATMENT_TASK_COMPLETION');
      expect(opData.documentType).toBe('TREATMENT_PLAN');
      expect(opData.sourceDocPath).toBe(`patients/${patientA}/treatment_plans/${testPlanId}/tasks/${taskId1}`);
    });

    test('Fake performer identity in payload is ignored and bound to caller auth.uid', async () => {
      await completeTreatmentTaskHandler({
        auth: { uid: nurseAssigned },
        data: {
          patientId: patientA,
          planId: testPlanId,
          taskId: taskId1,
          completedByNurseId: 'fake_nurse_attacker', // Malicious attempt to spoof performer
          executionRemarks: 'Verified vitals',
        },
      });

      const taskDoc = await db
        .collection('patients')
        .doc(patientA)
        .collection('treatment_plans')
        .doc(testPlanId)
        .collection('tasks')
        .doc(taskId1)
        .get();

      expect(taskDoc.data()!.completedByNurseId).toBe(nurseAssigned); // Must be authentic caller
    });

    test('Completed task cannot be completed again (replay protection)', async () => {
      // First completion succeeds
      await completeTreatmentTaskHandler({
        auth: { uid: nurseAssigned },
        data: { patientId: patientA, planId: testPlanId, taskId: taskId1 },
      });

      // Second completion fails closed
      await expect(
        completeTreatmentTaskHandler({
          auth: { uid: nurseAssigned },
          data: { patientId: patientA, planId: testPlanId, taskId: taskId1 },
        })
      ).rejects.toThrow('is already marked as completed.');

      // Counter was not double-incremented
      const planDoc = await db
        .collection('patients')
        .doc(patientA)
        .collection('treatment_plans')
        .doc(testPlanId)
        .get();
      expect(planDoc.data()!.completedTasks).toBe(1);
    });

    test('Genuine concurrent execution against same pending task: exactly one succeeds, one fails, counter increments once', async () => {
      // Concurrently dispatch two completion requests against the same pending taskId1
      const [res1, res2] = await Promise.allSettled([
        completeTreatmentTaskHandler({
          auth: { uid: nurseAssigned },
          data: {
            patientId: patientA,
            planId: testPlanId,
            taskId: taskId1,
            executionRemarks: 'Concurrent Worker 1',
          },
        }),
        completeTreatmentTaskHandler({
          auth: { uid: nurseAssigned },
          data: {
            patientId: patientA,
            planId: testPlanId,
            taskId: taskId1,
            executionRemarks: 'Concurrent Worker 2',
          },
        }),
      ]);

      const fulfilled = [res1, res2].filter((r) => r.status === 'fulfilled');
      const rejected = [res1, res2].filter((r) => r.status === 'rejected');

      // Exactly one completion accepted; the other safely rejected
      expect(fulfilled.length).toBe(1);
      expect(rejected.length).toBe(1);

      const rejectionReason = (rejected[0] as PromiseRejectedResult).reason?.message || '';
      expect(rejectionReason).toMatch(/already marked as completed|failed-precondition/i);

      // Verify parent plan completedTasks counter is incremented by exactly one (1, not 2)
      const planDoc = await db
        .collection('patients')
        .doc(patientA)
        .collection('treatment_plans')
        .doc(testPlanId)
        .get();

      expect(planDoc.data()!.completedTasks).toBe(1);

      // Verify task completion record attribution
      const taskDoc = await db
        .collection('patients')
        .doc(patientA)
        .collection('treatment_plans')
        .doc(testPlanId)
        .collection('tasks')
        .doc(taskId1)
        .get();

      const taskData = taskDoc.data()!;
      expect(taskData.status).toBe('completed');
      expect(taskData.completedByNurseId).toBe(nurseAssigned);
      expect(taskData.completedAt).toBeDefined();
    });

    test('Completing final task does NOT automatically approve treatment-plan closure', async () => {
      // Complete Task 1
      await completeTreatmentTaskHandler({
        auth: { uid: nurseAssigned },
        data: { patientId: patientA, planId: testPlanId, taskId: taskId1 },
      });

      // Complete Task 2 (final task)
      await completeTreatmentTaskHandler({
        auth: { uid: nurseAssigned },
        data: { patientId: patientA, planId: testPlanId, taskId: taskId2 },
      });

      const planDoc = await db
        .collection('patients')
        .doc(patientA)
        .collection('treatment_plans')
        .doc(testPlanId)
        .get();

      const planData = planDoc.data()!;
      expect(planData.completedTasks).toBe(2);
      expect(planData.totalTasks).toBe(2);
      // Status MUST remain active until doctor authorizes medical closure
      expect(planData.status).toBe('active');
    });

    test('Task completion is rejected on a suspended or discontinued plan', async () => {
      // Doctor suspends the plan
      await updateTreatmentPlanStatusHandler({
        auth: { uid: docAttending },
        data: { patientId: patientA, planId: testPlanId, targetStatus: 'suspended', statusReason: 'Awaiting lab results' },
      });

      // Nurse attempts completion on suspended plan
      await expect(
        completeTreatmentTaskHandler({
          auth: { uid: nurseAssigned },
          data: { patientId: patientA, planId: testPlanId, taskId: taskId1 },
        })
      ).rejects.toThrow('Treatment plan is in \'suspended\' status');
    });
  });

  describe('recordTreatmentProgressUpdate', () => {
    let testPlanId: string;

    beforeEach(async () => {
      const planRes = await createTreatmentPlanHandler({
        auth: { uid: docAttending },
        data: {
          patientId: patientA,
          title: 'Progress Update Test Plan',
          clinicalObjectives: 'Evaluate progress logging.',
          tasks: [{ title: 'Daily assessment' }],
        },
      });
      testPlanId = planRes.planId;
    });

    test('Assigned nurse successfully logs timestamped progress update and enqueues gateway operation', async () => {
      const res = await recordTreatmentProgressUpdateHandler({
        auth: { uid: nurseAssigned },
        data: {
          patientId: patientA,
          planId: testPlanId,
          clinicalSummary: 'Patient responded favorably to hydration protocol. Afebrile.',
          patientTolerance: 'well_tolerated',
          factualObservations: 'HR 76 bpm, BP 118/76 mmHg.',
        },
      });

      expect(res.success).toBe(true);
      expect(res.updateId).toBeDefined();
      expect(res.status).toBe('PENDING');

      // Verify progress update document
      const updateDoc = await db
        .collection('patients')
        .doc(patientA)
        .collection('treatment_plans')
        .doc(testPlanId)
        .collection('progress_updates')
        .doc(res.updateId)
        .get();

      expect(updateDoc.exists).toBe(true);
      const updateData = updateDoc.data()!;
      expect(updateData.authorUid).toBe(nurseAssigned);
      expect(updateData.authorName).toBe('Nurse Sara');
      expect(updateData.authorRole).toBe('nurse');
      expect(updateData.patientTolerance).toBe('well_tolerated');
      expect(updateData.fabricStatus).toBe('PENDING');

      // Verify gateway_operations entry for durable Fabric reconciliation
      const opDoc = await db.collection('gateway_operations').doc(`op_tp_${patientA}_${testPlanId}_${res.updateId}`).get();
      expect(opDoc.exists).toBe(true);
      const opData = opDoc.data()!;
      expect(opData.operationType).toBe('ANCHOR_RECORD');
      expect(opData.recordType).toBe('TREATMENT_PROGRESS');
      expect(opData.documentType).toBe('TREATMENT_PLAN');
      expect(opData.status).toBe('PENDING');
      expect(opData.sourceDocPath).toBe(`patients/${patientA}/treatment_plans/${testPlanId}/progress_updates/${res.updateId}`);
    });

    test('Attending doctor can also record treatment progress update', async () => {
      const res = await recordTreatmentProgressUpdateHandler({
        auth: { uid: docAttending },
        data: {
          patientId: patientA,
          planId: testPlanId,
          clinicalSummary: 'Physician round: Remission goals on track.',
          patientTolerance: 'well_tolerated',
        },
      });

      expect(res.success).toBe(true);
    });

    test('Assignment with missing or empty hospitalId fails closed with permission-denied', async () => {
      await expect(
        recordTreatmentProgressUpdateHandler({
          auth: { uid: nurseNoHosp },
          data: {
            patientId: patientA,
            planId: testPlanId,
            clinicalSummary: 'Observation note with invalid hospital assignment.',
          },
        })
      ).rejects.toThrow('Hospital scope mismatch or missing');
    });

    test('Unassigned nurse cannot record progress update', async () => {
      await expect(
        recordTreatmentProgressUpdateHandler({
          auth: { uid: nurseUnassigned },
          data: {
            patientId: patientA,
            planId: testPlanId,
            clinicalSummary: 'Unauthorized observation note.',
          },
        })
      ).rejects.toThrow('Nurse is not actively assigned to patient');
    });

    test('Rejects invalid patient tolerance enum', async () => {
      await expect(
        recordTreatmentProgressUpdateHandler({
          auth: { uid: nurseAssigned },
          data: {
            patientId: patientA,
            planId: testPlanId,
            clinicalSummary: 'Valid clinical summary.',
            patientTolerance: 'invalid_tolerance_value' as any,
          },
        })
      ).rejects.toThrow('Invalid patientTolerance');
    });
  });

  describe('updateTreatmentPlanStatus (Physician Lifecycle Management)', () => {
    let testPlanId: string;

    beforeEach(async () => {
      const planRes = await createTreatmentPlanHandler({
        auth: { uid: docAttending },
        data: {
          patientId: patientA,
          title: 'Lifecycle Test Plan',
          clinicalObjectives: 'Test plan status transitions.',
          tasks: [{ title: 'Scheduled check' }],
        },
      });
      testPlanId = planRes.planId;
    });

    test('Nurse cannot alter plan status (doctor only)', async () => {
      await expect(
        updateTreatmentPlanStatusHandler({
          auth: { uid: nurseAssigned },
          data: { patientId: patientA, planId: testPlanId, targetStatus: 'completed' },
        })
      ).rejects.toThrow('Only authorized attending physicians can author or manage treatment plans.');
    });

    test('Attending doctor can suspend and reactivate treatment plan', async () => {
      // Suspend
      const suspendRes = await updateTreatmentPlanStatusHandler({
        auth: { uid: docAttending },
        data: { patientId: patientA, planId: testPlanId, targetStatus: 'suspended', statusReason: 'Low platelet count' },
      });
      expect(suspendRes.status).toBe('suspended');

      let planDoc = await db
        .collection('patients')
        .doc(patientA)
        .collection('treatment_plans')
        .doc(testPlanId)
        .get();
      expect(planDoc.data()!.status).toBe('suspended');
      expect(planDoc.data()!.statusReason).toBe('Low platelet count');

      // Reactivate
      const reactivateRes = await updateTreatmentPlanStatusHandler({
        auth: { uid: docAttending },
        data: { patientId: patientA, planId: testPlanId, targetStatus: 'active', statusReason: 'Platelets normalized' },
      });
      expect(reactivateRes.status).toBe('active');
    });

    test('Attending doctor can medically close/complete the plan', async () => {
      const completeRes = await updateTreatmentPlanStatusHandler({
        auth: { uid: docAttending },
        data: { patientId: patientA, planId: testPlanId, targetStatus: 'completed', statusReason: 'Protocol successfully finished' },
      });
      expect(completeRes.status).toBe('completed');

      const planDoc = await db
        .collection('patients')
        .doc(patientA)
        .collection('treatment_plans')
        .doc(testPlanId)
        .get();
      expect(planDoc.data()!.status).toBe('completed');
    });
  });

  // ── 5. TREATMENT TASK ASSIGNMENT NOTIFICATIONS (FR3.4, FR-M3.4) ─────────────
  describe('Treatment Task Assignment Notifications (FR3.4, FR-M3.4)', () => {
    let mockSentMessages: any[] = [];
    const mockFcmSender = {
      sendEachForMulticast: async (msg: any) => {
        mockSentMessages.push(msg);
        return {
          responses: msg.tokens.map((_: any, idx: number) => ({
            success: true,
            messageId: `fcm-msg-treatment-${idx + 1}`,
          })),
          successCount: msg.tokens.length,
          failureCount: 0,
        };
      },
    };

    beforeEach(async () => {
      mockSentMessages = [];
      // Register device token for actively assigned nurse
      await db
        .collection('users')
        .doc(nurseAssigned)
        .collection('deviceTokens')
        .doc('token_nurse_1')
        .set({
          fcmToken: 'fcm_token_nurse_assigned_abc123',
          platform: 'android',
          createdAt: new Date(),
        });
    });

    test('createTreatmentPlan dispatches high-priority push notification and durable in-app record to assigned nurse', async () => {
      const planRes = await createTreatmentPlanHandler(
        {
          auth: { uid: docAttending },
          data: {
            patientId: patientA,
            title: 'Induction Phase Tasks',
            clinicalObjectives: 'Administer cytarabine and monitor for tumor lysis',
            tasks: [
              { title: 'Pre-hydration IV saline 1000ml', category: 'nursing_care' },
              { title: 'Monitor urine output q2h', category: 'vital_monitoring' },
            ],
          },
        },
        db,
        mockFcmSender as any
      );

      expect(planRes.success).toBe(true);
      expect(planRes.notifiedNurses).toContain(nurseAssigned);

      // Verify FCM push dispatch
      expect(mockSentMessages.length).toBe(1);
      const sent = mockSentMessages[0];
      expect(sent.tokens).toContain('fcm_token_nurse_assigned_abc123');
      expect(sent.android.priority).toBe('high');
      expect(sent.apns.headers['apns-priority']).toBe('10');
      // Verify NO sensitive patient PHI in push payload
      expect(sent.notification.title).toBe('New Treatment Tasks Assigned');
      expect(sent.notification.body).toContain('2 care task(s)');
      expect(sent.notification.body).not.toContain('cytarabine'); // Zero PHI leakage

      // Verify durable in-app notification audit record
      const notifSnap = await db
        .collection('notifications')
        .doc(nurseAssigned)
        .collection('items')
        .doc(`task_assign_${planRes.planId}_${nurseAssigned}`)
        .get();

      expect(notifSnap.exists).toBe(true);
      const notifData = notifSnap.data()!;
      expect(notifData.type).toBe('treatment_task');
      expect(notifData.patientId).toBe(patientA);
      expect(notifData.referenceId).toBe(planRes.planId);
      expect(notifData.fcmDispatch.status).toBe('DELIVERED');
      expect(notifData.fcmDispatch.messageIds).toContain('fcm-msg-treatment-1');
    });

    test('Nurse with revoked assignment is NOT notified of newly created treatment tasks', async () => {
      // Revoke assignment
      await db
        .collection('nurse_patient_assignments')
        .doc(`${nurseAssigned}_${patientA}`)
        .update({ status: 'revoked', updatedAt: new Date() });

      const planRes = await createTreatmentPlanHandler(
        {
          auth: { uid: docAttending },
          data: {
            patientId: patientA,
            title: 'Post-Revocation Care Plan',
            clinicalObjectives: 'Strict monitoring plan for secondary team',
            tasks: [{ title: 'Daily CBC panel', category: 'lab_check' }],
          },
        },
        db,
        mockFcmSender as any
      );

      expect(planRes.success).toBe(true);
      expect(planRes.notifiedNurses).not.toContain(nurseAssigned);
      expect(mockSentMessages.length).toBe(0); // Zero push notifications dispatched to revoked nurse
    });

    test('Nurse from another hospital is NOT notified (cross-hospital boundary enforced)', async () => {
      // Seed a nurse belonging to a different hospital assigned to patientA (anomaly state)
      const foreignNurse = 'nurse_foreign_hosp';
      await db.collection('users').doc(foreignNurse).set({
        uid: foreignNurse,
        role: 'nurse',
        hospitalId: 'Different Ward 9',
        status: 'active',
        name: 'Nurse Other Hospital',
      });
      await db.collection('nurse_patient_assignments').doc(`${foreignNurse}_${patientA}`).set({
        id: `${foreignNurse}_${patientA}`,
        nurseId: foreignNurse,
        patientId: patientA,
        hospitalId: 'Different Ward 9',
        status: 'active',
      });

      const planRes = await createTreatmentPlanHandler(
        {
          auth: { uid: docAttending },
          data: {
            patientId: patientA,
            title: 'Cross-Hospital Isolation Plan',
            clinicalObjectives: 'Confirm isolation boundary blocks external push',
            tasks: [{ title: 'Check vitals', category: 'vital_monitoring' }],
          },
        },
        db,
        mockFcmSender as any
      );

      expect(planRes.success).toBe(true);
      expect(planRes.notifiedNurses).not.toContain(foreignNurse);
    });

    test('Retry mechanism attempts FCM dispatch up to 3 times on transient failure', async () => {
      // Ensure nurse assignment is active with matching hospitalId (hospA)
      await db
        .collection('nurse_patient_assignments')
        .doc(`${nurseAssigned}_${patientA}`)
        .set({
          id: `${nurseAssigned}_${patientA}`,
          nurseId: nurseAssigned,
          nurseName: 'Nurse Sara',
          patientId: patientA,
          patientName: 'Alice Patient',
          hospitalId: hospA,
          status: 'active',
          assignedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

      let callCount = 0;
      const retryFcmSender = {
        sendEachForMulticast: async (msg: any) => {
          callCount++;
          if (callCount < 2) {
            throw new Error('FCM 503 Service Unavailable');
          }
          return {
            responses: [{ success: true, messageId: 'fcm-retry-success-id' }],
            successCount: 1,
            failureCount: 0,
          };
        },
      };

      const planRes = await createTreatmentPlanHandler(
        {
          auth: { uid: docAttending },
          data: {
            patientId: patientA,
            title: 'Retry Verification Plan',
            clinicalObjectives: 'Verify exponential retry recovery',
            tasks: [{ title: 'IV infusion', category: 'medication' }],
          },
        },
        db,
        retryFcmSender as any
      );

      expect(planRes.success).toBe(true);
      expect(callCount).toBe(2); // Recovered on attempt 2

      const notifDoc = await db
        .collection('notifications')
        .doc(nurseAssigned)
        .collection('items')
        .doc(`task_assign_${planRes.planId}_${nurseAssigned}`)
        .get();

      expect(notifDoc.exists).toBe(true);
      expect(notifDoc.data()!.fcmDispatch.status).toBe('DELIVERED');
      expect(notifDoc.data()!.fcmDispatch.attempts).toBe(2);
    });
  });
});
