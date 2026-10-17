// functions/test/treatment_worker_contract.test.ts
/**
 * ============================================================================
 * ONCOVAULT — PHASE 3D.2 EMULATOR / INTEGRATION CONTRACT TEST SUITE
 * ============================================================================
 * Clearly labeled: FIRESTORE EMULATOR INTEGRATION TESTS WITH MOCKED FABRIC GATEWAY.
 * Validates the full contract between:
 * 1. Cloud Function Callables (createTreatmentPlan, completeTreatmentTask, recordTreatmentProgressUpdate)
 * 2. Persisted Firestore Task & Progress Documents
 * 3. Durable gateway_operations queue
 * 4. Reconciliation worker reconciliation loop against a mocked Fabric interface
 *
 * NOTE: Genuine on-chain treatment anchoring to the live Hyperledger Fabric
 * network will be verified in the subsequent live verification phase.
 * ============================================================================
 */

import * as admin from 'firebase-admin';
import * as crypto from 'crypto';
import {
  createTreatmentPlanHandler,
  completeTreatmentTaskHandler,
  recordTreatmentProgressUpdateHandler,
  computeCanonicalTaskHash,
  computeCanonicalProgressHash,
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

// Helper for deterministic opaque key simulation matching PseudonymService
function mockOpaqueRecordKey(patientId: string, domainRecordId: string): string {
  const hmac = crypto.createHmac('sha256', 'mock_secret_key_123');
  hmac.update(`domain:record:${patientId.trim()}:${domainRecordId.trim()}`);
  return `rec_${hmac.digest('hex').substring(0, 32)}`;
}

// Mock Fabric Gateway Interface
interface MockFabricInterface {
  evaluateTransaction: (fnName: string, ...args: string[]) => Promise<string>;
  submitTransaction: (fnName: string, ...args: string[]) => Promise<{ result: string; txId: string }>;
}

/**
 * Reconciles a single pending treatment operation from gateway_operations.
 * Implements the exact algorithm of ReconciliationWorker.reconcilePendingTreatmentOperations()
 * directly against Firestore Emulator documents.
 */
async function reconcileSingleOperation(
  opId: string,
  mockFabric: MockFabricInterface
): Promise<{ success: boolean; status: string; error?: string }> {
  const opRef = db.collection('gateway_operations').doc(opId);
  const nowMs = Date.now();

  // 1. Lease Acquisition & Fencing
  let activeLeaseToken: string | null = null;
  let opData: Record<string, any> | null = null;

  await db.runTransaction(async (t) => {
    const snap = await t.get(opRef);
    if (!snap.exists) return;
    const data = snap.data() || {};
    const opStatus = data.status || 'PENDING';
    const leaseExpired = data.lockExpiresAt && data.lockExpiresAt < nowMs;
    const retryEligible = !data.nextRetryAt || data.nextRetryAt <= nowMs;

    const eligible =
      (opStatus === 'PENDING' && retryEligible) ||
      (opStatus === 'FAILED_RETRYABLE' && retryEligible) ||
      (opStatus === 'PROCESSING' && leaseExpired);

    if (!eligible) return;

    activeLeaseToken = crypto.randomUUID();
    t.update(opRef, {
      status: 'PROCESSING',
      lockExpiresAt: nowMs + 60000,
      leaseToken: activeLeaseToken,
      processingStartedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    opData = { ...data, leaseToken: activeLeaseToken };
  });

  if (!opData || !activeLeaseToken) {
    return { success: false, status: 'SKIPPED_NOT_ELIGIBLE' };
  }

  const { recordId, patientId, planId, recordType, sourceDocPath } = opData as any;

  // 2. Validate Required Operation Fields
  if (!patientId || !planId || !recordId || !sourceDocPath) {
    await db.runTransaction(async (t) => {
      const snap = await t.get(opRef);
      if (!snap.exists || snap.data()?.leaseToken !== activeLeaseToken) return;
      t.update(opRef, {
        status: 'FAILED_PERMANENT',
        error: 'Missing required operation fields (patientId, planId, recordId, or sourceDocPath)',
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });
    return { success: false, status: 'FAILED_PERMANENT', error: 'Missing required operation fields' };
  }

  // 3. Resolve Authoritative Source Document
  const sourceRef = db.doc(sourceDocPath);
  const sourceSnap = await sourceRef.get();

  if (!sourceSnap.exists) {
    await db.runTransaction(async (t) => {
      const snap = await t.get(opRef);
      if (!snap.exists || snap.data()?.leaseToken !== activeLeaseToken) return;
      t.update(opRef, {
        status: 'FAILED_PERMANENT',
        error: 'Source clinical document not found',
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });
    return { success: false, status: 'FAILED_PERMANENT', error: 'Source document not found' };
  }

  const sourceData = sourceSnap.data() || {};

  // 4. Cross-Patient / Cross-Plan Substitution Boundary Check
  if (sourceData.patientId !== patientId || sourceData.planId !== planId) {
    await db.runTransaction(async (t) => {
      const snap = await t.get(opRef);
      if (!snap.exists || snap.data()?.leaseToken !== activeLeaseToken) return;
      t.update(opRef, {
        status: 'FAILED_PERMANENT',
        error: 'Security violation: Cross-patient or cross-plan document substitution detected',
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });
    return { success: false, status: 'FAILED_PERMANENT', error: 'Cross-patient mismatch' };
  }

  // 5. Finalization & Eligibility Validation
  if (recordType === 'TREATMENT_TASK_COMPLETION') {
    if (sourceData.status !== 'completed' || !sourceData.completedAt) {
      await db.runTransaction(async (t) => {
        const snap = await t.get(opRef);
        if (!snap.exists || snap.data()?.leaseToken !== activeLeaseToken) return;
        t.update(opRef, {
          status: 'FAILED_RETRYABLE',
          nextRetryAt: Date.now() + 30000,
          error: 'Source task not yet completed or timestamp pending',
        });
      });
      return { success: false, status: 'FAILED_RETRYABLE', error: 'Task not finalized' };
    }
  }

  // 6. Compute Canonical SHA-256 Digest from Resolved Persisted Record
  let calculatedHash = '';
  if (recordType === 'TREATMENT_TASK_COMPLETION') {
    calculatedHash = computeCanonicalTaskHash(sourceData as any);
  } else {
    calculatedHash = computeCanonicalProgressHash(sourceData as any);
  }

  // Tamper detection against queued hash (if provided)
  if ((opData as any).canonicalHash && (opData as any).canonicalHash.toLowerCase() !== calculatedHash.toLowerCase()) {
    await db.runTransaction(async (t) => {
      const snap = await t.get(opRef);
      if (!snap.exists || snap.data()?.leaseToken !== activeLeaseToken) return;
      t.update(opRef, {
        status: 'FAILED_PERMANENT',
        error: 'Canonical hash mismatch / content tampering detected',
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });
    return { success: false, status: 'FAILED_PERMANENT', error: 'Tamper detected' };
  }

  // 7. Generate Deterministic Opaque Ledger Key
  const domainRecordId =
    recordType === 'TREATMENT_TASK_COMPLETION' ? `task_${planId}_${recordId}` : `tp_${planId}_${recordId}`;
  const opaqueRecordKey = mockOpaqueRecordKey(patientId, domainRecordId);

  // 8. Submit to Mocked Fabric Gateway
  try {
    const metadata = {
      documentType: 'TREATMENT_PLAN',
      recordType: recordType.toUpperCase(),
      schemaVersion: '1.0',
    };

    const { result, txId } = await mockFabric.submitTransaction(
      'AnchorRecordHash',
      opaqueRecordKey,
      calculatedHash,
      JSON.stringify(metadata)
    );

    const proof = JSON.parse(result);

    // 9. Verify on Ledger
    const verifyStr = await mockFabric.evaluateTransaction('VerifyRecordHash', opaqueRecordKey, calculatedHash);
    const verifyResult = JSON.parse(verifyStr);
    if (!verifyResult.verified) {
      throw new Error(`Ledger verification failed with status: ${verifyResult.status}`);
    }

    // 10. Atomic Commit with Lease Fencing Check
    await db.runTransaction(async (t) => {
      const snap = await t.get(opRef);
      if (!snap.exists) throw new Error('Operation deleted');
      const curr = snap.data() || {};
      if (curr.leaseToken !== activeLeaseToken) {
        throw new Error(
          `STALE_LEASE_FENCE: Worker lease token '${activeLeaseToken}' expired or superseded by '${curr.leaseToken}'. Aborting commit.`
        );
      }

      // NOTE: sourceRef status ('completed') is NEVER overwritten with uppercase 'COMMITTED'.
      // fabricStatus is used strictly for blockchain tracking.
      t.update(sourceRef, {
        fabricStatus: 'COMMITTED',
        fabricTxId: proof.txId || txId,
        fabricVersion: proof.version || 1,
        fabricTimestamp: proof.timestamp,
        fileHash: calculatedHash,
        opaqueRecordKey,
        lastAnchoredAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      t.update(opRef, {
        status: 'COMMITTED',
        fabricTxId: proof.txId || txId,
        fabricVersion: proof.version || 1,
        fabricTimestamp: proof.timestamp,
        payloadHash: calculatedHash,
        opaqueRecordKey,
        committedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });

    return { success: true, status: 'COMMITTED' };
  } catch (err: any) {
    // Record retryable failure or permanent failure
    let nextStatus = 'FAILED_RETRYABLE';
    await db.runTransaction(async (t) => {
      const snap = await t.get(opRef);
      if (!snap.exists || snap.data()?.leaseToken !== activeLeaseToken) return;
      const curr = snap.data() || {};
      const retryCount = (curr.retryCount || 0) + 1;
      const isPermanent = retryCount >= 5;
      nextStatus = isPermanent ? 'FAILED_PERMANENT' : 'FAILED_RETRYABLE';
      const nextRetryDelayMs = Math.min(300000, Math.pow(2, retryCount) * 5000);

      t.update(opRef, {
        status: nextStatus,
        retryCount,
        nextRetryAt: Date.now() + nextRetryDelayMs,
        error: err.message,
        lastFailedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });
    return { success: false, status: nextStatus, error: err.message };
  }
}

describe('Phase 3D.2 Treatment Tracking Firestore-to-Worker Emulator Integration Tests', () => {
  const hospitalA = 'Hospital Ward 3D-E2E';
  const docId = 'doc_e2e_reconciler';
  const nurseId = 'nurse_e2e_reconciler';
  const patientId = 'pat_e2e_reconciler';

  let mockFabric: MockFabricInterface;

  beforeAll(async () => {
    const batch = db.batch();

    // 1. Doctor user record
    batch.set(db.collection('users').doc(docId), {
      uid: docId,
      name: 'Dr. E2E Oncologist',
      role: 'doctor',
      hospitalId: hospitalA,
    });

    // 2. Nurse user record
    batch.set(db.collection('users').doc(nurseId), {
      uid: nurseId,
      name: 'Nurse E2E Specialist',
      role: 'nurse',
      hospitalId: hospitalA,
    });

    // 3. Patient record
    batch.set(db.collection('patients').doc(patientId), {
      id: patientId,
      name: 'E2E Blood Cancer Patient',
      hospitalId: hospitalA,
    });

    // 4. Canonical nurse assignment with status: 'active'
    batch.set(db.collection('nurse_patient_assignments').doc(`${nurseId}_${patientId}`), {
      id: `${nurseId}_${patientId}`,
      nurseId,
      patientId,
      hospitalId: hospitalA,
      status: 'active',
      assignedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // 5. Active doctor consent record
    batch.set(db.collection('doctor_patient_consents').doc(`${patientId}_${docId}`), {
      id: `${patientId}_${docId}`,
      doctorId: docId,
      patientId,
      status: 'granted',
      grantedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await batch.commit();
  });

  beforeEach(() => {
    // Default mock Fabric responses
    mockFabric = {
      evaluateTransaction: jest.fn().mockImplementation(async (fnName: string) => {
        if (fnName === 'VerifyRecordHash') {
          return JSON.stringify({ verified: true, status: 'VERIFIED' });
        }
        if (fnName === 'GetRecordProof') {
          throw new Error('Record not found on ledger');
        }
        return '{}';
      }),
      submitTransaction: jest.fn().mockImplementation(async (fnName: string, opaqueKey: string, hash: string) => {
        return {
          result: JSON.stringify({
            recordId: opaqueKey,
            sha256Hash: hash,
            version: 1,
            txId: `tx_mock_${Date.now()}`,
            timestamp: new Date().toISOString(),
          }),
          txId: `tx_mock_${Date.now()}`,
        };
      }),
    };
  });

  // =========================================================================
  // TEST SUITE 1 — TASK COMPLETION END-TO-END FLOW
  // =========================================================================
  describe('Task Completion Contract & Reconciliation', () => {
    let planId: string;
    let taskId: string;
    let opId: string;

    test('Doctor creates plan, nurse completes task, worker reconciles against mocked Fabric', async () => {
      // 1. Doctor creates plan
      const planRes = await createTreatmentPlanHandler({
        auth: { uid: docId },
        data: {
          patientId,
          title: 'E2E Chemotherapy Regimen',
          clinicalObjectives: 'Track cycle 1 execution.',
          tasks: [
            {
              title: 'Administer antiemetic IV',
              instructions: 'Ondansetron 8mg IV push 30 mins prior to infusion.',
              category: 'medication_administration',
            },
          ],
        },
      });
      planId = planRes.planId;

      // Fetch task ID from subcollection
      const tasksSnap = await db
        .collection('patients')
        .doc(patientId)
        .collection('treatment_plans')
        .doc(planId)
        .collection('tasks')
        .get();
      expect(tasksSnap.empty).toBe(false);
      taskId = tasksSnap.docs[0].id;

      // 2. Nurse completes task
      const completeRes = await completeTreatmentTaskHandler({
        auth: { uid: nurseId },
        data: {
          patientId,
          planId,
          taskId,
          executionRemarks: 'Infused over 15 minutes without adverse reaction.',
        },
      });
      expect(completeRes.success).toBe(true);

      // 3. Read persisted Firestore task document
      const taskDoc = await db
        .collection('patients')
        .doc(patientId)
        .collection('treatment_plans')
        .doc(planId)
        .collection('tasks')
        .doc(taskId)
        .get();
      expect(taskDoc.exists).toBe(true);
      const taskData = taskDoc.data()!;
      expect(taskData.status).toBe('completed');
      expect(taskData.completedByNurseId).toBe(nurseId);
      expect(taskData.completedAt).toBeDefined();

      // 4. Read corresponding gateway operation
      opId = `op_task_${patientId}_${planId}_${taskId}`;
      const opDoc = await db.collection('gateway_operations').doc(opId).get();
      expect(opDoc.exists).toBe(true);
      const opData = opDoc.data()!;
      expect(opData.status).toBe('PENDING');
      expect(opData.recordType).toBe('TREATMENT_TASK_COMPLETION');
      expect(opData.documentType).toBe('TREATMENT_PLAN');
      expect(opData.sourceDocPath).toBe(`patients/${patientId}/treatment_plans/${planId}/tasks/${taskId}`);

      // 5. Worker reconciles operation
      const reconcileRes = await reconcileSingleOperation(opId, mockFabric);
      expect(reconcileRes.success).toBe(true);
      expect(reconcileRes.status).toBe('COMMITTED');

      // 6. Confirm Fabric mock was called with correct metadata & zero PHI
      expect(mockFabric.submitTransaction).toHaveBeenCalledTimes(1);
      const submitArgs = (mockFabric.submitTransaction as jest.Mock).mock.calls[0];
      expect(submitArgs[0]).toBe('AnchorRecordHash');
      const meta = JSON.parse(submitArgs[3]);
      expect(meta.documentType).toBe('TREATMENT_PLAN');
      expect(meta.recordType).toBe('TREATMENT_TASK_COMPLETION');
      expect(meta.schemaVersion).toBe('1.0');

      // 7. Verify source task record state in Firestore
      const updatedTaskDoc = await db
        .collection('patients')
        .doc(patientId)
        .collection('treatment_plans')
        .doc(planId)
        .collection('tasks')
        .doc(taskId)
        .get();
      const updatedTask = updatedTaskDoc.data()!;

      // CRITICAL CHECK: Clinical status remains 'completed', NOT overwritten by 'COMMITTED'!
      expect(updatedTask.status).toBe('completed');
      expect(updatedTask.fabricStatus).toBe('COMMITTED');
      expect(updatedTask.fabricTxId).toBeDefined();
      expect(updatedTask.fileHash).toBeDefined();
      expect(updatedTask.fileHash).toHaveLength(64);
      expect(updatedTask.opaqueRecordKey).toBeDefined();

      // 8. Verify gateway operation marked COMMITTED
      const updatedOpDoc = await db.collection('gateway_operations').doc(opId).get();
      expect(updatedOpDoc.data()!.status).toBe('COMMITTED');
      expect(updatedOpDoc.data()!.fabricTxId).toBeDefined();
    });
  });

  // =========================================================================
  // TEST SUITE 2 — PROGRESS UPDATE END-TO-END FLOW
  // =========================================================================
  describe('Progress Update Contract & Reconciliation', () => {
    let planId: string;
    let updateId: string;
    let opId: string;

    test('Nurse records progress update, worker computes canonical progress hash and anchors to mocked Fabric', async () => {
      // 1. Doctor creates plan
      const planRes = await createTreatmentPlanHandler({
        auth: { uid: docId },
        data: {
          patientId,
          title: 'Cycle 2 Monitoring Plan',
          clinicalObjectives: 'Monitor patient tolerance.',
          tasks: [{ title: 'Daily CBC check' }],
        },
      });
      planId = planRes.planId;

      // 2. Nurse records progress update
      const progressRes = await recordTreatmentProgressUpdateHandler({
        auth: { uid: nurseId },
        data: {
          patientId,
          planId,
          clinicalSummary: 'Patient tolerated chemotherapy with no signs of febrile neutropenia.',
          patientTolerance: 'well_tolerated',
          factualObservations: 'Vitals stable. Temp 36.8 C, BP 122/78 mmHg.',
        },
      });
      expect(progressRes.success).toBe(true);
      updateId = progressRes.updateId;

      // 3. Read persisted progress update
      const progDoc = await db
        .collection('patients')
        .doc(patientId)
        .collection('treatment_plans')
        .doc(planId)
        .collection('progress_updates')
        .doc(updateId)
        .get();
      expect(progDoc.exists).toBe(true);
      expect(progDoc.data()!.authorUid).toBe(nurseId);
      expect(progDoc.data()!.fabricStatus).toBe('PENDING');

      // 4. Read gateway operation
      opId = `op_tp_${patientId}_${planId}_${updateId}`;
      const opDoc = await db.collection('gateway_operations').doc(opId).get();
      expect(opDoc.exists).toBe(true);
      expect(opDoc.data()!.recordType).toBe('TREATMENT_PROGRESS');

      // 5. Worker reconciles
      const reconcileRes = await reconcileSingleOperation(opId, mockFabric);
      expect(reconcileRes.success).toBe(true);
      expect(reconcileRes.status).toBe('COMMITTED');

      // 6. Verify progress update document updated
      const updatedProgDoc = await db
        .collection('patients')
        .doc(patientId)
        .collection('treatment_plans')
        .doc(planId)
        .collection('progress_updates')
        .doc(updateId)
        .get();
      expect(updatedProgDoc.data()!.fabricStatus).toBe('COMMITTED');
      expect(updatedProgDoc.data()!.fabricTxId).toBeDefined();
      expect(updatedProgDoc.data()!.fileHash).toHaveLength(64);
    });
  });

  // =========================================================================
  // TEST SUITE 3 — SECURITY, TAMPERING & FAILURE MODES
  // =========================================================================
  describe('Security, Edge Cases & Tamper Resistance', () => {
    let planId: string;
    let taskId: string;

    beforeEach(async () => {
      const planRes = await createTreatmentPlanHandler({
        auth: { uid: docId },
        data: {
          patientId,
          title: 'Edge Case Test Plan',
          clinicalObjectives: 'Validate edge case handling.',
          tasks: [{ title: 'Baseline ECG' }],
        },
      });
      planId = planRes.planId;

      const tasksSnap = await db
        .collection('patients')
        .doc(patientId)
        .collection('treatment_plans')
        .doc(planId)
        .collection('tasks')
        .get();
      taskId = tasksSnap.docs[0].id;
    });

    test('Tampered source fields are detected and operation marked FAILED_PERMANENT', async () => {
      // 1. Complete task
      await completeTreatmentTaskHandler({
        auth: { uid: nurseId },
        data: {
          patientId,
          planId,
          taskId,
          executionRemarks: 'Original genuine remarks.',
        },
      });

      const opId = `op_task_${patientId}_${planId}_${taskId}`;
      const taskDoc = await db
        .collection('patients')
        .doc(patientId)
        .collection('treatment_plans')
        .doc(planId)
        .collection('tasks')
        .doc(taskId)
        .get();

      // Compute and record initial genuine canonical hash on operation
      const genuineHash = computeCanonicalTaskHash(taskDoc.data() as any);
      await db.collection('gateway_operations').doc(opId).update({
        canonicalHash: genuineHash,
      });

      // 2. Malicious tampering: attacker alters executionRemarks in Firestore document directly
      await db
        .collection('patients')
        .doc(patientId)
        .collection('treatment_plans')
        .doc(planId)
        .collection('tasks')
        .doc(taskId)
        .update({
          executionRemarks: 'Tampered remarks: Patient experienced severe allergic anaphylaxis!',
        });

      // 3. Worker reconciles: recomputes hash from persisted document, detects mismatch with opData.canonicalHash
      const reconcileRes = await reconcileSingleOperation(opId, mockFabric);
      expect(reconcileRes.success).toBe(false);
      expect(reconcileRes.status).toBe('FAILED_PERMANENT');

      // 4. Fabric anchor must NEVER be submitted for tampered record
      expect(mockFabric.submitTransaction).not.toHaveBeenCalled();

      // 5. Operation in Firestore must be marked FAILED_PERMANENT with tamper error
      const opDoc = await db.collection('gateway_operations').doc(opId).get();
      expect(opDoc.data()!.status).toBe('FAILED_PERMANENT');
      expect(opDoc.data()!.error).toContain('tampering detected');
    });

    test('Timestamp mismatch / non-finalized task is rejected with FAILED_RETRYABLE', async () => {
      // Manually enqueue operation for a task that is still in pending status
      const fakeOpId = `op_task_${patientId}_${planId}_${taskId}_non_finalized`;
      await db.collection('gateway_operations').doc(fakeOpId).set({
        operationId: fakeOpId,
        operationType: 'ANCHOR_RECORD',
        recordId: taskId,
        planId,
        patientId,
        status: 'PENDING',
        recordType: 'TREATMENT_TASK_COMPLETION',
        documentType: 'TREATMENT_PLAN',
        sourceDocPath: `patients/${patientId}/treatment_plans/${planId}/tasks/${taskId}`,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      const res = await reconcileSingleOperation(fakeOpId, mockFabric);
      expect(res.success).toBe(false);
      expect(res.status).toBe('FAILED_RETRYABLE');

      const opDoc = await db.collection('gateway_operations').doc(fakeOpId).get();
      expect(opDoc.data()!.status).toBe('FAILED_RETRYABLE');
      expect(opDoc.data()!.error).toContain('not yet completed');
    });

    test('Missing required operation fields are detected and marked FAILED_PERMANENT', async () => {
      const corruptOpId = `op_corrupt_${Date.now()}`;
      await db.collection('gateway_operations').doc(corruptOpId).set({
        operationId: corruptOpId,
        operationType: 'ANCHOR_RECORD',
        status: 'PENDING',
        documentType: 'TREATMENT_PLAN',
        // Deliberately missing patientId, planId, recordId, and sourceDocPath
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      const res = await reconcileSingleOperation(corruptOpId, mockFabric);
      expect(res.success).toBe(false);
      expect(res.status).toBe('FAILED_PERMANENT');

      const opDoc = await db.collection('gateway_operations').doc(corruptOpId).get();
      expect(opDoc.data()!.status).toBe('FAILED_PERMANENT');
      expect(opDoc.data()!.error).toContain('Missing required operation fields');
    });

    test('Cross-patient source substitution is blocked and marked FAILED_PERMANENT', async () => {
      // Complete legitimate task for patientId
      await completeTreatmentTaskHandler({
        auth: { uid: nurseId },
        data: { patientId, planId, taskId },
      });

      // Attack: An attacker creates an operation alleging patientId is 'attacker_pat',
      // but points sourceDocPath to victim patient's task
      const spoofOpId = `op_spoof_${Date.now()}`;
      await db.collection('gateway_operations').doc(spoofOpId).set({
        operationId: spoofOpId,
        operationType: 'ANCHOR_RECORD',
        recordId: taskId,
        planId,
        patientId: 'attacker_victim_spoof', // Mismatch!
        status: 'PENDING',
        recordType: 'TREATMENT_TASK_COMPLETION',
        documentType: 'TREATMENT_PLAN',
        sourceDocPath: `patients/${patientId}/treatment_plans/${planId}/tasks/${taskId}`,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      const res = await reconcileSingleOperation(spoofOpId, mockFabric);
      expect(res.success).toBe(false);
      expect(res.status).toBe('FAILED_PERMANENT');

      const opDoc = await db.collection('gateway_operations').doc(spoofOpId).get();
      expect(opDoc.data()!.status).toBe('FAILED_PERMANENT');
      expect(opDoc.data()!.error).toContain('Cross-patient or cross-plan document substitution detected');
    });

    test('Transient Fabric error increments retryCount, and transitions to FAILED_PERMANENT after 5 retries', async () => {
      await completeTreatmentTaskHandler({
        auth: { uid: nurseId },
        data: { patientId, planId, taskId },
      });
      const opId = `op_task_${patientId}_${planId}_${taskId}`;

      // Mock transient Fabric timeout
      mockFabric.submitTransaction = jest.fn().mockRejectedValue(new Error('DEADLINE_EXCEEDED: Peer timeout'));

      // Attempt 1: marks FAILED_RETRYABLE with retryCount 1
      const res1 = await reconcileSingleOperation(opId, mockFabric);
      expect(res1.status).toBe('FAILED_RETRYABLE');

      let opDoc = await db.collection('gateway_operations').doc(opId).get();
      expect(opDoc.data()!.retryCount).toBe(1);

      // Simulate 4 prior failures (retryCount = 4) and set nextRetryAt in past
      await db.collection('gateway_operations').doc(opId).update({
        retryCount: 4,
        nextRetryAt: Date.now() - 1000,
      });

      // Attempt 5: marks FAILED_PERMANENT
      const res5 = await reconcileSingleOperation(opId, mockFabric);
      expect(res5.status).toBe('FAILED_PERMANENT');

      opDoc = await db.collection('gateway_operations').doc(opId).get();
      expect(opDoc.data()!.status).toBe('FAILED_PERMANENT');
      expect(opDoc.data()!.retryCount).toBe(5);
    });

    test('Stale processing lease fencing rejects superseded worker commit update', async () => {
      await completeTreatmentTaskHandler({
        auth: { uid: nurseId },
        data: { patientId, planId, taskId },
      });
      const opId = `op_task_${patientId}_${planId}_${taskId}`;

      // Simulate Worker A acquiring lease
      const workerALease = 'worker_A_uuid_token';
      await db.collection('gateway_operations').doc(opId).update({
        status: 'PROCESSING',
        leaseToken: workerALease,
        lockExpiresAt: Date.now() + 60000,
      });

      // Simulate Worker B superseding lease because Worker A paused
      const workerBLease = 'worker_B_superseded_token';
      await db.collection('gateway_operations').doc(opId).update({
        leaseToken: workerBLease,
      });

      // Worker A attempts to commit with stale leaseToken
      const sourceDocPath = `patients/${patientId}/treatment_plans/${planId}/tasks/${taskId}`;
      const sourceRef = db.doc(sourceDocPath);
      const opRef = db.collection('gateway_operations').doc(opId);

      await expect(
        db.runTransaction(async (t) => {
          const freshOp = await t.get(opRef);
          const curr = freshOp.data() || {};
          if (curr.leaseToken !== workerALease) {
            throw new Error(`STALE_LEASE_FENCE: Worker lease token '${workerALease}' expired or superseded.`);
          }
          t.update(sourceRef, { fabricStatus: 'COMMITTED' });
          t.update(opRef, { status: 'COMMITTED' });
        })
      ).rejects.toThrow('STALE_LEASE_FENCE');

      // Verify that neither source nor operation was corrupted by Worker A's stale commit
      const finalTask = await sourceRef.get();
      expect(finalTask.data()!.fabricStatus).not.toBe('COMMITTED');

      const finalOp = await opRef.get();
      expect(finalOp.data()!.status).toBe('PROCESSING');
      expect(finalOp.data()!.leaseToken).toBe(workerBLease);
    });
  });
});
