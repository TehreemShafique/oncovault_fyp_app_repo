// functions/src/manage_treatment_plan.ts
import * as admin from 'firebase-admin';
import * as functions from 'firebase-functions';
import { HttpsError } from 'firebase-functions/v1/https';
import * as crypto from 'crypto';
import { verifyDoctorCareAuthorization } from './assign_nurse';
import { FcmSender } from './dispatch_critical_alert';

export interface TreatmentTaskInput {
  title: string;
  instructions?: string;
  category?: 'medication' | 'nursing_care' | 'vital_monitoring' | 'lab_check';
  scheduledTimeIso?: string;
}

export interface CreateTreatmentPlanPayload {
  planId?: string;
  patientId: string;
  title: string;
  clinicalObjectives: string;
  targetEndDateIso?: string;
  tasks: TreatmentTaskInput[];
}

export interface CompleteTreatmentTaskPayload {
  patientId: string;
  planId: string;
  taskId: string;
  executionRemarks?: string;
}

export interface RecordTreatmentProgressPayload {
  updateId?: string;
  patientId: string;
  planId: string;
  clinicalSummary: string;
  patientTolerance?: 'well_tolerated' | 'mild_adverse' | 'moderate_adverse' | 'severe_toxicity';
  factualObservations?: string;
}

export interface UpdateTreatmentPlanStatusPayload {
  patientId: string;
  planId: string;
  targetStatus: 'active' | 'completed' | 'suspended' | 'discontinued';
  statusReason?: string;
}

const VALID_TOLERANCES = [
  'well_tolerated',
  'mild_adverse',
  'moderate_adverse',
  'severe_toxicity',
];

const VALID_PLAN_STATUSES = [
  'active',
  'completed',
  'suspended',
  'discontinued',
];

/**
 * Safely parses any Firestore Timestamp, Date, string, or number into stable ISO 8601 string.
 */
export function parseTimestampIso(ts: any): string {
  if (!ts) return '';
  if (typeof ts.toDate === 'function') {
    return ts.toDate().toISOString();
  }
  if (ts instanceof Date) {
    return ts.toISOString();
  }
  if (typeof ts === 'string') {
    return ts;
  }
  if (typeof ts === 'number') {
    return new Date(ts).toISOString();
  }
  return '';
}

/**
 * Computes deterministic SHA-256 digest of task completion for Fabric ledger anchoring.
 * Derives canonical hash strictly from persisted source values and resolved Firestore timestamp.
 */
export function computeCanonicalTaskHash(task: {
  taskId: string;
  planId: string;
  patientId: string;
  performerUid?: string;
  completedByNurseId?: string;
  completedAt: any;
  executionRemarks?: string;
}): string {
  const canonicalObject = {
    completedAtIso: parseTimestampIso(task.completedAt),
    executionRemarks: (task.executionRemarks || '').trim(),
    patientId: task.patientId,
    performerUid: task.performerUid || task.completedByNurseId || '',
    planId: task.planId,
    taskId: task.taskId,
  };
  const serialized = JSON.stringify(canonicalObject, Object.keys(canonicalObject).sort());
  return crypto.createHash('sha256').update(serialized, 'utf8').digest('hex').toLowerCase();
}

/**
 * Computes deterministic SHA-256 digest of progress update for Fabric ledger anchoring.
 * Derives canonical hash strictly from persisted source values and resolved Firestore timestamp.
 */
export function computeCanonicalProgressHash(update: {
  updateId: string;
  planId: string;
  patientId: string;
  authorUid: string;
  timestamp: any;
  clinicalSummary: string;
  patientTolerance?: string;
  factualObservations?: string;
}): string {
  const canonicalObject = {
    authorUid: update.authorUid,
    clinicalSummary: (update.clinicalSummary || '').trim(),
    factualObservations: (update.factualObservations || '').trim(),
    patientId: update.patientId,
    patientTolerance: update.patientTolerance || '',
    planId: update.planId,
    timestampIso: parseTimestampIso(update.timestamp),
    updateId: update.updateId,
  };
  const serialized = JSON.stringify(canonicalObject, Object.keys(canonicalObject).sort());
  return crypto.createHash('sha256').update(serialized, 'utf8').digest('hex').toLowerCase();
}

/**
 * Canonical check for active nurse-patient care assignment.
 * Enforces authoritative persisted schema:
 * - Document path: nurse_patient_assignments/${nurseUid}_${patientId}
 * - status must be strictly 'active' (revoked, missing, or unknown rejected)
 * - nurseId must match caller UID
 * - patientId must match target patient ID
 * - hospitalId must be present, valid string, and strictly match patient hospital scope
 * - Inconsistent or legacy flags (such as isActive: true without status: 'active') cannot grant access
 */
export async function verifyActiveNurseAssignment(
  db: admin.firestore.Firestore,
  nurseUid: string,
  patientId: string,
  expectedHospitalId: string
): Promise<void> {
  const assignmentId = `${nurseUid}_${patientId}`;
  const assignDoc = await db.collection('nurse_patient_assignments').doc(assignmentId).get();
  if (!assignDoc.exists) {
    throw new HttpsError(
      'permission-denied',
      `Nurse is not actively assigned to patient ${patientId}. Access denied.`
    );
  }

  const assignData = assignDoc.data() || {};

  // 1. Strict status check: must be exactly 'active'
  if (assignData.status !== 'active') {
    throw new HttpsError(
      'permission-denied',
      `Nurse assignment for patient ${patientId} is not active (status: ${assignData.status || 'unknown'}). Access denied.`
    );
  }

  // 2. Identity match: nurseId must match caller and patientId must match target patient
  if (assignData.nurseId !== nurseUid || assignData.patientId !== patientId) {
    throw new HttpsError(
      'permission-denied',
      `Assignment document identity mismatch for patient ${patientId}. Access denied.`
    );
  }

  // 3. Strict Hospital Scope Validation:
  // Hospital identity must be present, valid non-empty string, and strictly match patient hospital
  if (!expectedHospitalId || typeof expectedHospitalId !== 'string' || !expectedHospitalId.trim()) {
    throw new HttpsError(
      'failed-precondition',
      `Invalid patient hospital scope (${expectedHospitalId}) for assignment verification.`
    );
  }

  if (
    !assignData.hospitalId ||
    typeof assignData.hospitalId !== 'string' ||
    assignData.hospitalId.trim() !== expectedHospitalId.trim()
  ) {
    throw new HttpsError(
      'permission-denied',
      `Hospital scope mismatch or missing: Assignment hospital (${assignData.hospitalId || 'none'}) does not match patient hospital (${expectedHospitalId}). Access denied.`
    );
  }
}

/**
 * Validates clinician identity, hospital isolation boundary, and role assignment.
 */
async function authorizeClinicianForTreatment(
  db: admin.firestore.Firestore,
  callerUid: string,
  patientId: string,
  requiredRole: 'doctor' | 'nurse' | 'any_clinician'
): Promise<{ userRole: string; clinicianName: string; hospitalId: string }> {
  const userDoc = await db.collection('users').doc(callerUid).get();
  if (!userDoc.exists) {
    throw new HttpsError('permission-denied', 'User record not found.');
  }

  const userData = userDoc.data() || {};
  const userRole = (userData.role || '').toLowerCase();
  const clinicianName =
    userData.name ||
    (userRole === 'doctor'
      ? 'Attending Physician'
      : userRole === 'admin'
      ? 'Administrator'
      : 'Staff Nurse');
  const userHospital = userData.hospitalId || 'Oncology Ward 3A';

  const patientDoc = await db.collection('patients').doc(patientId).get();
  if (!patientDoc.exists) {
    throw new HttpsError('not-found', `Patient ${patientId} does not exist.`);
  }
  const patientData = patientDoc.data() || {};
  const patientHospital = patientData.hospitalId || 'Oncology Ward 3A';

  if (userRole !== 'admin' && userHospital !== patientHospital) {
    throw new HttpsError(
      'permission-denied',
      `Hospital boundary violation: Clinician (${userHospital}) cannot access patient in (${patientHospital}).`
    );
  }

  if (requiredRole === 'doctor') {
    if (userRole !== 'doctor' && userRole !== 'admin') {
      throw new HttpsError(
        'permission-denied',
        'Only authorized attending physicians can author or manage treatment plans.'
      );
    }
    if (userRole === 'doctor') {
      await verifyDoctorCareAuthorization(db, callerUid, patientId);
    }
  } else if (requiredRole === 'nurse') {
    if (userRole !== 'nurse' && userRole !== 'admin') {
      throw new HttpsError(
        'permission-denied',
        'Only assigned nurses can execute and complete treatment tasks.'
      );
    }
    if (userRole === 'nurse') {
      await verifyActiveNurseAssignment(db, callerUid, patientId, patientHospital);
    }
  } else if (requiredRole === 'any_clinician') {
    if (userRole === 'nurse') {
      await verifyActiveNurseAssignment(db, callerUid, patientId, patientHospital);
    } else if (userRole === 'doctor') {
      await verifyDoctorCareAuthorization(db, callerUid, patientId);
    } else if (userRole !== 'admin') {
      throw new HttpsError(
        'permission-denied',
        'Only authorized clinical staff can perform this operation.'
      );
    }
  }

  return { userRole, clinicianName, hospitalId: userHospital };
}

/**
 * Handler for Physician Treatment Plan Creation (Doctor Only).
 */
export async function createTreatmentPlanHandler(
  request: { auth?: { uid: string }; data: any },
  firestoreInstance?: admin.firestore.Firestore,
  customFcmSender?: FcmSender
): Promise<{ success: boolean; planId: string; totalTasks: number; status: string; notifiedNurses?: string[] }> {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError('unauthenticated', 'User must be authenticated.');
  }

  const callerUid = request.auth.uid;
  const db = firestoreInstance || admin.firestore();
  const payload = request.data as CreateTreatmentPlanPayload;

  if (!payload || !payload.patientId || typeof payload.patientId !== 'string') {
    throw new HttpsError('invalid-argument', 'Valid patientId is required.');
  }

  const title = (payload.title || '').trim();
  if (title.length < 3 || title.length > 200) {
    throw new HttpsError('invalid-argument', 'Plan title must be between 3 and 200 characters.');
  }

  const clinicalObjectives = (payload.clinicalObjectives || '').trim();
  if (clinicalObjectives.length < 5 || clinicalObjectives.length > 2000) {
    throw new HttpsError(
      'invalid-argument',
      'Clinical objectives must be between 5 and 2000 characters.'
    );
  }

  if (!Array.isArray(payload.tasks) || payload.tasks.length === 0 || payload.tasks.length > 50) {
    throw new HttpsError('invalid-argument', 'Treatment plan must contain between 1 and 50 tasks.');
  }

  for (let i = 0; i < payload.tasks.length; i++) {
    const t = payload.tasks[i];
    const taskTitle = (t.title || '').trim();
    if (taskTitle.length < 3 || taskTitle.length > 200) {
      throw new HttpsError(
        'invalid-argument',
        `Task #${i + 1} title must be between 3 and 200 characters.`
      );
    }
    if (t.instructions && t.instructions.length > 1000) {
      throw new HttpsError(
        'invalid-argument',
        `Task #${i + 1} instructions must not exceed 1000 characters.`
      );
    }
  }

  const { clinicianName, hospitalId } = await authorizeClinicianForTreatment(
    db,
    callerUid,
    payload.patientId,
    'doctor'
  );

  const planRef = payload.planId?.trim()
    ? db.collection('patients').doc(payload.patientId).collection('treatment_plans').doc(payload.planId.trim())
    : db.collection('patients').doc(payload.patientId).collection('treatment_plans').doc();

  const planId = planRef.id;

  await db.runTransaction(async (transaction) => {
    const existingSnap = await transaction.get(planRef);
    if (existingSnap.exists) {
      const data = existingSnap.data() || {};
      if (data.doctorId === callerUid && data.title === title) {
        return; // Idempotent retry
      }
      throw new HttpsError('already-exists', `Treatment plan '${planId}' already exists.`);
    }

    const serverNow = admin.firestore.FieldValue.serverTimestamp();

    const planData: Record<string, any> = {
      planId,
      patientId: payload.patientId,
      doctorId: callerUid,
      doctorName: clinicianName,
      hospitalId,
      title,
      clinicalObjectives,
      status: 'active',
      startDate: serverNow,
      targetEndDate: payload.targetEndDateIso ? admin.firestore.Timestamp.fromDate(new Date(payload.targetEndDateIso)) : null,
      totalTasks: payload.tasks.length,
      completedTasks: 0,
      createdAt: serverNow,
      updatedAt: serverNow,
      fabricStatus: 'NOT_ANCHORED',
    };

    transaction.set(planRef, planData);

    for (let i = 0; i < payload.tasks.length; i++) {
      const t = payload.tasks[i];
      const taskRef = planRef.collection('tasks').doc();
      const taskData: Record<string, any> = {
        taskId: taskRef.id,
        planId,
        patientId: payload.patientId,
        title: t.title.trim(),
        instructions: (t.instructions || '').trim(),
        category: t.category || 'nursing_care',
        scheduledTime: t.scheduledTimeIso ? admin.firestore.Timestamp.fromDate(new Date(t.scheduledTimeIso)) : null,
        status: 'pending',
        completedByNurseId: null,
        completedByNurseName: null,
        completedAt: null,
        executionRemarks: null,
        skipReason: null,
        createdAt: serverNow,
        updatedAt: serverNow,
      };
      transaction.set(taskRef, taskData);
    }
  });

  // Post-transaction Notification (FR3.4, FR-M3.4): Notify actively assigned ward nurses
  let notifiedNurses: string[] = [];
  try {
    const notifResult = await dispatchTreatmentTaskNotification(
      db,
      payload.patientId,
      planId,
      title,
      clinicianName,
      hospitalId,
      payload.tasks.length,
      customFcmSender
    );
    notifiedNurses = notifResult.dispatchedToNurseIds;
  } catch (notifErr) {
    console.warn(`[TreatmentPlan] Post-transaction task notification failed for plan ${planId}:`, notifErr);
  }

  return { success: true, planId, totalTasks: payload.tasks.length, status: 'active', notifiedNurses };
}

/**
 * Dispatches high-priority push notifications and creates durable in-app notifications
 * for nurses actively assigned to the patient (FR3.4, FR-M3.4).
 * Enforces:
 * - Active patient assignment status ('active')
 * - Hospital boundary isolation (matching hospitalId)
 * - Zero PHI in push payloads
 * - Max 3 retry attempts with exponential backoff
 * - Durable delivery attempt logging
 * - Idempotency
 */
export async function dispatchTreatmentTaskNotification(
  db: admin.firestore.Firestore,
  patientId: string,
  planId: string,
  planTitle: string,
  doctorName: string,
  hospitalId: string,
  taskCount: number,
  customFcmSender?: FcmSender
): Promise<{ dispatchedToNurseIds: string[] }> {
  const assignSnap = await db
    .collection('nurse_patient_assignments')
    .where('patientId', '==', patientId)
    .where('status', '==', 'active')
    .get();

  if (assignSnap.empty) {
    return { dispatchedToNurseIds: [] };
  }

  const fcm = customFcmSender || admin.messaging();
  const dispatchedNurses: string[] = [];

  for (const doc of assignSnap.docs) {
    const data = doc.data();
    const nurseId = data.nurseId;
    if (!nurseId) continue;

    // Hospital boundary check
    if (data.hospitalId && hospitalId && data.hospitalId !== hospitalId) {
      continue;
    }

    // Verify nurse user record
    const userDoc = await db.collection('users').doc(nurseId).get();
    if (!userDoc.exists) continue;
    const userData = userDoc.data() || {};
    if (userData.status === 'inactive' || userData.status === 'suspended') continue;
    if (userData.hospitalId && hospitalId && userData.hospitalId !== hospitalId) continue;

    const notifId = `task_assign_${planId}_${nurseId}`;
    const notifRef = db.collection('notifications').doc(nurseId).collection('items').doc(notifId);

    const existingNotif = await notifRef.get();
    if (existingNotif.exists && existingNotif.data()?.fcmDispatch?.status === 'DELIVERED') {
      dispatchedNurses.push(nurseId);
      continue;
    }

    // Fetch device tokens
    const tokensSnap = await db.collection('users').doc(nurseId).collection('deviceTokens').get();
    const tokens = tokensSnap.docs
      .map((d) => (d.data().fcmToken as string || '').trim())
      .filter((t) => t.length > 0);

    const serverNow = admin.firestore.FieldValue.serverTimestamp();
    const pushTitle = 'New Treatment Tasks Assigned';
    const pushBody = `Dr. ${doctorName} assigned ${taskCount} care task(s) for patient ${patientId}.`;

    let dispatchStatus: 'DELIVERED' | 'NO_TOKENS' | 'FAILED' = tokens.length === 0 ? 'NO_TOKENS' : 'FAILED';
    let successfulMessageIds: string[] = [];
    let lastError: string | null = null;
    let attempts = 0;

    if (tokens.length > 0) {
      const fcmMessage: admin.messaging.MulticastMessage = {
        tokens,
        notification: {
          title: pushTitle,
          body: pushBody,
        },
        data: {
          type: 'treatment_task',
          patientId,
          planId,
        },
        android: {
          priority: 'high',
          notification: {
            channelId: 'treatment_tasks',
            priority: 'high',
          },
        },
        apns: {
          payload: {
            aps: {
              sound: 'default',
              badge: 1,
            },
          },
          headers: {
            'apns-priority': '10',
          },
        },
      };

      for (let attempt = 1; attempt <= 3; attempt++) {
        attempts = attempt;
        try {
          const batchResponse = await fcm.sendEachForMulticast(fcmMessage);
          const validIds: string[] = [];
          batchResponse.responses.forEach((resp) => {
            if (resp.success && resp.messageId) {
              validIds.push(resp.messageId);
            }
          });
          if (validIds.length > 0) {
            successfulMessageIds = validIds;
            dispatchStatus = 'DELIVERED';
            break;
          } else {
            lastError = 'FCM multicast returned 0 successful message deliveries.';
          }
        } catch (err: any) {
          lastError = err?.message || String(err);
          if (attempt < 3) {
            await new Promise((r) => setTimeout(r, 100 * Math.pow(2, attempt - 1)));
          }
        }
      }
    }

    await notifRef.set({
      id: notifId,
      patientId,
      title: pushTitle,
      body: pushBody,
      type: 'treatment_task',
      isRead: false,
      referenceId: planId,
      createdAt: serverNow,
      fcmDispatch: {
        status: dispatchStatus,
        attempts,
        tokenCount: tokens.length,
        messageIds: successfulMessageIds,
        lastError,
        dispatchedAt: serverNow,
      },
    }, { merge: true });

    dispatchedNurses.push(nurseId);
  }

  return { dispatchedToNurseIds: dispatchedNurses };
}

/**
 * Handler for Bedside Task Completion (Assigned Nurse / House Officer Only).
 * Implements strict non-repudiable attribution (BR-3.6) and atomic progress counter increment.
 */
export async function completeTreatmentTaskHandler(
  request: { auth?: { uid: string }; data: any },
  firestoreInstance?: admin.firestore.Firestore
): Promise<{ success: boolean; taskId: string; planId: string; completedAt: string }> {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError('unauthenticated', 'User must be authenticated.');
  }

  const callerUid = request.auth.uid;
  const db = firestoreInstance || admin.firestore();
  const payload = request.data as CompleteTreatmentTaskPayload;

  if (!payload || !payload.patientId || !payload.planId || !payload.taskId) {
    throw new HttpsError('invalid-argument', 'patientId, planId, and taskId are required.');
  }

  const { clinicianName, hospitalId } = await authorizeClinicianForTreatment(
    db,
    callerUid,
    payload.patientId,
    'nurse'
  );

  const planRef = db
    .collection('patients')
    .doc(payload.patientId)
    .collection('treatment_plans')
    .doc(payload.planId);

  const taskRef = planRef.collection('tasks').doc(payload.taskId);

  let completionIso = '';

  await db.runTransaction(async (transaction) => {
    const planSnap = await transaction.get(planRef);
    if (!planSnap.exists) {
      throw new HttpsError('not-found', `Treatment plan '${payload.planId}' not found.`);
    }

    const planData = planSnap.data() || {};
    if (planData.status !== 'active') {
      throw new HttpsError(
        'failed-precondition',
        `Cannot execute task: Treatment plan is in '${planData.status}' status (only active plans permit execution).`
      );
    }

    const taskSnap = await transaction.get(taskRef);
    if (!taskSnap.exists) {
      throw new HttpsError('not-found', `Treatment task '${payload.taskId}' not found.`);
    }

    const taskData = taskSnap.data() || {};
    if (taskData.status === 'completed') {
      throw new HttpsError(
        'failed-precondition',
        `Task '${payload.taskId}' is already marked as completed.`
      );
    }

    if (taskData.status === 'skipped') {
      throw new HttpsError(
        'failed-precondition',
        `Cannot complete task '${payload.taskId}' because it was previously marked as skipped.`
      );
    }

    if (taskData.status !== 'pending' && taskData.status !== 'in_progress') {
      throw new HttpsError(
        'failed-precondition',
        `Cannot complete task '${payload.taskId}' because it is in '${taskData.status}' status (must be pending or in_progress).`
      );
    }

    const serverNow = admin.firestore.FieldValue.serverTimestamp();
    completionIso = new Date().toISOString();

    // 1. Update task with server-authoritative nurse identity and timestamp (BR-3.6)
    transaction.update(taskRef, {
      status: 'completed',
      completedAt: serverNow,
      completedByNurseId: callerUid,
      completedByNurseName: clinicianName,
      executionRemarks: (payload.executionRemarks || '').trim() || null,
      updatedAt: serverNow,
      fabricStatus: 'PENDING',
    });

    // 2. Atomically increment completedTasks counter on parent plan
    const currentCompleted = (planData.completedTasks as number) || 0;
    const newCompleted = currentCompleted + 1;

    transaction.update(planRef, {
      completedTasks: newCompleted,
      updatedAt: serverNow,
      // Note: We deliberately do NOT change plan status to completed automatically.
      // Medical closure remains a distinct doctor-authorized lifecycle action.
    });

    // 3. Enqueue durable gateway_operations record for Fabric ledger anchoring (Phase 3D.2 readiness)
    const opId = `op_task_${payload.patientId}_${payload.planId}_${payload.taskId}`;
    const opRef = db.collection('gateway_operations').doc(opId);
    const opData = {
      operationId: opId,
      operationType: 'ANCHOR_RECORD',
      recordId: payload.taskId,
      planId: payload.planId,
      patientId: payload.patientId,
      hospitalId,
      status: 'PENDING',
      recordType: 'TREATMENT_TASK_COMPLETION',
      documentType: 'TREATMENT_PLAN',
      sourceDocPath: `patients/${payload.patientId}/treatment_plans/${payload.planId}/tasks/${payload.taskId}`,
      retryCount: 0,
      createdAt: serverNow,
    };
    transaction.set(opRef, opData);
  });

  return {
    success: true,
    taskId: payload.taskId,
    planId: payload.planId,
    completedAt: completionIso,
  };
}

/**
 * Handler for Recording Timestamped Treatment Progress Updates.
 */
export async function recordTreatmentProgressUpdateHandler(
  request: { auth?: { uid: string }; data: any },
  firestoreInstance?: admin.firestore.Firestore
): Promise<{ success: boolean; updateId: string; planId: string; status: string }> {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError('unauthenticated', 'User must be authenticated.');
  }

  const callerUid = request.auth.uid;
  const db = firestoreInstance || admin.firestore();
  const payload = request.data as RecordTreatmentProgressPayload;

  if (!payload || !payload.patientId || !payload.planId) {
    throw new HttpsError('invalid-argument', 'patientId and planId are required.');
  }

  const clinicalSummary = (payload.clinicalSummary || '').trim();
  if (clinicalSummary.length < 5 || clinicalSummary.length > 2000) {
    throw new HttpsError(
      'invalid-argument',
      'Clinical progress summary must be between 5 and 2000 characters.'
    );
  }

  if (payload.patientTolerance && !VALID_TOLERANCES.includes(payload.patientTolerance)) {
    throw new HttpsError(
      'invalid-argument',
      `Invalid patientTolerance. Must be one of: ${VALID_TOLERANCES.join(', ')}`
    );
  }

  const { userRole, clinicianName, hospitalId } = await authorizeClinicianForTreatment(
    db,
    callerUid,
    payload.patientId,
    'any_clinician'
  );

  const planRef = db
    .collection('patients')
    .doc(payload.patientId)
    .collection('treatment_plans')
    .doc(payload.planId);

  const planSnap = await planRef.get();
  if (!planSnap.exists) {
    throw new HttpsError('not-found', `Treatment plan '${payload.planId}' not found.`);
  }

  const planData = planSnap.data() || {};
  if (planData.status !== 'active') {
    throw new HttpsError(
      'failed-precondition',
      `Cannot record progress: Treatment plan is in '${planData.status}' status.`
    );
  }

  const updateRef = payload.updateId?.trim()
    ? planRef.collection('progress_updates').doc(payload.updateId.trim())
    : planRef.collection('progress_updates').doc();

  const updateId = updateRef.id;
  const serverNow = admin.firestore.FieldValue.serverTimestamp();

  const updateData: Record<string, any> = {
    updateId,
    planId: payload.planId,
    patientId: payload.patientId,
    authorUid: callerUid,
    authorName: clinicianName,
    authorRole: userRole,
    timestamp: serverNow,
    clinicalSummary,
    patientTolerance: payload.patientTolerance || null,
    factualObservations: (payload.factualObservations || '').trim() || null,
    fabricStatus: 'PENDING',
    createdAt: serverNow,
  };

  const opId = `op_tp_${payload.patientId}_${payload.planId}_${updateId}`;
  const opRef = db.collection('gateway_operations').doc(opId);
  const opData = {
    operationId: opId,
    operationType: 'ANCHOR_RECORD',
    recordId: updateId,
    planId: payload.planId,
    patientId: payload.patientId,
    hospitalId,
    status: 'PENDING',
    recordType: 'TREATMENT_PROGRESS',
    documentType: 'TREATMENT_PLAN',
    sourceDocPath: `patients/${payload.patientId}/treatment_plans/${payload.planId}/progress_updates/${updateId}`,
    retryCount: 0,
    createdAt: serverNow,
  };

  const batch = db.batch();
  batch.set(updateRef, updateData);
  batch.set(opRef, opData);
  await batch.commit();

  return { success: true, updateId, planId: payload.planId, status: 'PENDING' };
}

/**
 * Handler for Physician Plan Management Lifecycle (Doctor Only).
 * Supports suspension, discontinuation, reactivation, and closure while preserving all execution history.
 */
export async function updateTreatmentPlanStatusHandler(
  request: { auth?: { uid: string }; data: any },
  firestoreInstance?: admin.firestore.Firestore
): Promise<{ success: boolean; planId: string; status: string }> {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError('unauthenticated', 'User must be authenticated.');
  }

  const callerUid = request.auth.uid;
  const db = firestoreInstance || admin.firestore();
  const payload = request.data as UpdateTreatmentPlanStatusPayload;

  if (!payload || !payload.patientId || !payload.planId || !payload.targetStatus) {
    throw new HttpsError('invalid-argument', 'patientId, planId, and targetStatus are required.');
  }

  if (!VALID_PLAN_STATUSES.includes(payload.targetStatus)) {
    throw new HttpsError(
      'invalid-argument',
      `Invalid targetStatus. Must be one of: ${VALID_PLAN_STATUSES.join(', ')}`
    );
  }

  await authorizeClinicianForTreatment(db, callerUid, payload.patientId, 'doctor');

  const planRef = db
    .collection('patients')
    .doc(payload.patientId)
    .collection('treatment_plans')
    .doc(payload.planId);

  await db.runTransaction(async (transaction) => {
    const snap = await transaction.get(planRef);
    if (!snap.exists) {
      throw new HttpsError('not-found', `Treatment plan '${payload.planId}' not found.`);
    }

    const prevData = snap.data() || {};
    const fromStatus = prevData.status || 'active';
    const serverNow = admin.firestore.FieldValue.serverTimestamp();
    const historyEntry = {
      fromStatus,
      toStatus: payload.targetStatus,
      reason: (payload.statusReason || '').trim() || null,
      updatedByUid: callerUid,
      updatedAt: new Date().toISOString(),
    };

    transaction.update(planRef, {
      status: payload.targetStatus,
      statusReason: (payload.statusReason || '').trim() || null,
      statusUpdatedByUid: callerUid,
      statusHistory: admin.firestore.FieldValue.arrayUnion(historyEntry),
      updatedAt: serverNow,
    });
  });

  return { success: true, planId: payload.planId, status: payload.targetStatus };
}

// ── Firebase Callable Cloud Functions ────────────────────────────────────────

export const createTreatmentPlan = functions.https.onCall(async (data, context) => {
  return await createTreatmentPlanHandler({ auth: context.auth, data });
});

export const completeTreatmentTask = functions.https.onCall(async (data, context) => {
  return await completeTreatmentTaskHandler({ auth: context.auth, data });
});

export const recordTreatmentProgressUpdate = functions.https.onCall(async (data, context) => {
  return await recordTreatmentProgressUpdateHandler({ auth: context.auth, data });
});

export const updateTreatmentPlanStatus = functions.https.onCall(async (data, context) => {
  return await updateTreatmentPlanStatusHandler({ auth: context.auth, data });
});
