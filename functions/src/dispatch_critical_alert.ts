// functions/src/dispatch_critical_alert.ts

import * as admin from 'firebase-admin';
import { FieldValue, Timestamp } from 'firebase-admin/firestore';
import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { onSchedule } from 'firebase-functions/v2/scheduler';

export interface VitalsSummaryPayload {
  bloodPressure: string;
  systolicBp: number;
  diastolicBp: number;
  pulseRate: number;
  temperatureC: number;
  respiratoryRate: number;
  oxygenSaturation: number;
}

export interface CriticalAlertEventDocument {
  eventId: string;
  observationId: string;
  patientId: string;
  patientName: string;
  hospitalId: string;
  eventType: 'vital_alert';
  severity: 'high' | 'medium';
  status: 'PENDING' | 'PROCESSING' | 'COMPLETED' | 'ESCALATED' | 'FAILED';
  createdAt: FirebaseFirestore.Timestamp | FieldValue;
  attempts: number;
  lastAttemptAt?: FirebaseFirestore.Timestamp | FieldValue | null;
  processingLease?: number | null;
  leaseToken?: string | null;
  lastErrorCode?: string | null;
  completedAt?: FirebaseFirestore.Timestamp | FieldValue | null;
  criticalReasons: string[];
  warningFlags?: string[];
  vitalsSummary: VitalsSummaryPayload;
  recordedByUid: string;
  recordedByName: string;
  recordedByRole: string;
}

export interface DispatchResult {
  doctorId: string;
  alertId: string;
  status: 'DELIVERED' | 'FAILED' | 'NO_TOKENS';
  fcmMessageIds?: string[];
  errorCode?: string;
}

export interface FcmSender {
  sendEachForMulticast(message: admin.messaging.MulticastMessage): Promise<admin.messaging.BatchResponse>;
}

export const DEFAULT_ACKNOWLEDGMENT_DEADLINE_MS = 15 * 60 * 1000; // 15 minutes clinical escalation window

/**
 * Resolves authoritative physicians currently responsible for caring for [patientId].
 * Enforces active care relationships, valid hospital scopes, and strict consent status:
 * 1. Attending physicians from active care assignments.
 * 2. Physicians with active granted Fabric consent (canonical status: 'granted' or 'active').
 * 3. Physicians with active non-expired appointments (unless consent is revoked).
 * Explicitly revoked Fabric consent strictly blocks care delivery regardless of appointment status.
 * Cross-hospital leakage is strictly blocked.
 */
export async function resolveEligiblePhysicians(
  db: admin.firestore.Firestore,
  patientId: string,
  targetHospitalId?: string
): Promise<{ doctorId: string; doctorName: string; hospitalId: string }[]> {
  const eligibleDoctorMap = new Map<string, { doctorId: string; doctorName: string; hospitalId: string }>();

  // Resolve target patient profile and hospital scope
  let effectiveHospital = targetHospitalId;
  if (!effectiveHospital) {
    const patDoc = await db.collection('patients').doc(patientId).get();
    if (patDoc.exists) {
      effectiveHospital = patDoc.data()?.hospitalId || 'Oncology Ward 3A';
    } else {
      const uDoc = await db.collection('users').doc(patientId).get();
      effectiveHospital = uDoc.data()?.hospitalId || 'Oncology Ward 3A';
    }
  }

  // 1. Check all consent records for patient in doctor_patient_consents projection
  const consentSnap = await db
    .collection('doctor_patient_consents')
    .where('patientId', '==', patientId)
    .get();

  const revokedDoctorIds = new Set<string>();
  const activeConsentDoctorIds = new Set<string>();

  for (const doc of consentSnap.docs) {
    const data = doc.data();
    const docId = data.doctorId;
    if (!docId) continue;
    const status = (data.status || '').toLowerCase();
    if (status === 'revoked' || data.isRevoked === true || data.revoked === true) {
      revokedDoctorIds.add(docId);
    } else if (status === 'granted' || status === 'active') {
      activeConsentDoctorIds.add(docId);
    }
  }

  // 2. Check active nurse assignments for patient (assignedBy physician)
  const assignSnap = await db
    .collection('nurse_patient_assignments')
    .where('patientId', '==', patientId)
    .where('status', '==', 'active')
    .get();

  const candidateDoctorIds = new Set<string>();
  for (const doc of assignSnap.docs) {
    const data = doc.data();
    const assignedBy = data.assignedBy;
    if (assignedBy && !revokedDoctorIds.has(assignedBy)) {
      candidateDoctorIds.add(assignedBy);
    }
  }

  // Add active consent doctors
  for (const docId of activeConsentDoctorIds) {
    if (!revokedDoctorIds.has(docId)) {
      candidateDoctorIds.add(docId);
    }
  }

  // 3. Check current appointments (unless consent is revoked)
  const nowMs = Date.now();
  const apptSnap = await db
    .collection('appointments')
    .where('patientId', '==', patientId)
    .limit(20)
    .get();

  for (const doc of apptSnap.docs) {
    const data = doc.data();
    const docId = data.doctorId;
    if (!docId || revokedDoctorIds.has(docId)) continue;

    const status = (data.status || '').toLowerCase();
    if (!['confirmed', 'approved', 'scheduled', 'rescheduled'].includes(status)) {
      continue;
    }

    // Check expiration (>24h past scheduled time)
    if (data.appointmentDate) {
      let apptTime: number | null = null;
      if (typeof data.appointmentDate.toMillis === 'function') {
        apptTime = data.appointmentDate.toMillis();
      } else if (data.appointmentDate instanceof Date) {
        apptTime = data.appointmentDate.getTime();
      } else if (typeof data.appointmentDate === 'string') {
        const parsed = Date.parse(data.appointmentDate);
        if (!isNaN(parsed)) apptTime = parsed;
      }

      if (apptTime !== null && apptTime < nowMs - 24 * 60 * 60 * 1000) {
        continue; // Expired historical appointment
      }
    }

    candidateDoctorIds.add(docId);
  }

  // 4. Validate doctor user records, direct consent documents & hospital scope
  for (const docId of candidateDoctorIds) {
    // Check direct consent doc explicitly: doctor_patient_consents/{patientId}_{docId}
    const directConsentDoc = await db
      .collection('doctor_patient_consents')
      .doc(`${patientId}_${docId}`)
      .get();

    if (directConsentDoc.exists) {
      const cData = directConsentDoc.data();
      const cStatus = (cData?.status || '').toLowerCase();
      if (cStatus === 'revoked' || cData?.isRevoked === true || cData?.revoked === true) {
        revokedDoctorIds.add(docId);
        continue; // Explicit revocation denies access regardless of appointments
      }
      if (cStatus === 'granted' || cStatus === 'active') {
        activeConsentDoctorIds.add(docId);
      }
    }

    if (revokedDoctorIds.has(docId)) {
      continue;
    }

    const userDoc = await db.collection('users').doc(docId).get();
    if (!userDoc.exists) continue;
    const userData = userDoc.data();
    if ((userData?.role || '').toLowerCase() !== 'doctor') continue;
    if (userData?.status === 'inactive' || userData?.status === 'suspended') continue;

    const docHospital = userData?.hospitalId || 'Oncology Ward 3A';
    if (effectiveHospital && docHospital !== effectiveHospital) {
      continue; // Block cross-hospital notification
    }

    eligibleDoctorMap.set(docId, {
      doctorId: docId,
      doctorName: userData?.name || 'Attending Physician',
      hospitalId: docHospital,
    });
  }

  return Array.from(eligibleDoctorMap.values());
}

/**
 * Dispatches a single critical or warning alert event idempotently.
 * 1. Transactionally claims event lease with unique fencing token.
 * 2. Resolves eligible physicians.
 * 3. Creates deterministic alerts (`alert_${observationId}_${doctorId}`).
 * 4. Dispatches privacy-safe FCM notifications (high priority for critical, normal for warning).
 * 5. Handles missing tokens, send failures, and supervisor escalation for critical alerts.
 */
export async function processCriticalAlertEvent(
  db: admin.firestore.Firestore,
  eventId: string,
  customFcmSender?: FcmSender
): Promise<{ success: boolean; results: DispatchResult[]; escalated: boolean }> {
  const eventRef = db.collection('critical_alert_events').doc(eventId);
  const nowMs = Date.now();
  const leaseDurationMs = 30000; // 30 second processing lease
  const leaseToken = `${nowMs}_${Math.random().toString(36).substring(2, 9)}`;

  // 1. Atomic Lease Claim with Fencing Token
  let eventData: CriticalAlertEventDocument | null = null;
  const leaseClaimed = await db.runTransaction(async (transaction) => {
    const snap = await transaction.get(eventRef);
    if (!snap.exists) return false;

    const data = snap.data() as CriticalAlertEventDocument;
    if (data.status === 'COMPLETED') {
      return false; // Already completed idempotently
    }

    // Check if another worker holds an active lease
    if (data.status === 'PROCESSING' && data.processingLease && data.processingLease > nowMs) {
      return false; // Currently locked by active worker
    }

    eventData = data;
    transaction.update(eventRef, {
      status: 'PROCESSING',
      attempts: (data.attempts || 0) + 1,
      lastAttemptAt: FieldValue.serverTimestamp(),
      processingLease: nowMs + leaseDurationMs,
      leaseToken,
    });
    return true;
  });

  const validEventData = eventData as CriticalAlertEventDocument | null;
  if (!leaseClaimed || !validEventData) {
    return { success: false, results: [], escalated: false };
  }

  const {
    observationId,
    patientId,
    criticalReasons,
    warningFlags,
    vitalsSummary,
    recordedByUid,
    recordedByName,
    hospitalId,
  } = validEventData;

  const isCritical = validEventData.severity === 'high';
  const alertSeverity = validEventData.severity || 'high';

  // Resolve Patient Name if missing
  let patientDisplayName = validEventData.patientName;
  if (!patientDisplayName || !patientDisplayName.trim()) {
    const pSnap = await db.collection('patients').doc(patientId).get();
    patientDisplayName = pSnap.data()?.name || 'Blood Cancer Patient';
  }

  // 2. Resolve Eligible Attending Physicians
  const physicians = await resolveEligiblePhysicians(db, patientId, hospitalId);
  const results: DispatchResult[] = [];
  let supervisorEscalationNeeded = false;
  let escalationReason = '';

  if (physicians.length === 0 && isCritical) {
    supervisorEscalationNeeded = true;
    escalationReason = 'NO_ELIGIBLE_PHYSICIAN';
  }

  // 3. Create Durable Alerts & Dispatch Push Notifications per Physician
  const fcm = customFcmSender || admin.messaging();

  for (const phys of physicians) {
    const alertId = `alert_${observationId}_${phys.doctorId}`;
    const alertRef = db.collection('doctors').doc(phys.doctorId).collection('alerts').doc(alertId);
    const notifRef = db.collection('notifications').doc(phys.doctorId).collection('items').doc(alertId);

    const description =
      criticalReasons && criticalReasons.length > 0
        ? criticalReasons.join('; ')
        : warningFlags && warningFlags.length > 0
        ? warningFlags.join('; ')
        : 'Abnormal vital readings recorded.';

    const alertTitle = isCritical
      ? 'Critical Vital Alert'
      : `Abnormal Vital Warning: ${patientDisplayName}`;

    const serverNow = FieldValue.serverTimestamp();

    // Persist durable alert & notification in transaction
    await db.runTransaction(async (t) => {
      const existingAlert = await t.get(alertRef);
      if (!existingAlert.exists) {
        t.set(alertRef, {
          id: alertId,
          alertId,
          eventId,
          observationId,
          patientId,
          patientName: patientDisplayName,
          doctorId: phys.doctorId,
          doctorName: phys.doctorName,
          hospitalId: phys.hospitalId || hospitalId || 'Oncology Ward 3A',
          alertType: 'vital_alert',
          severity: alertSeverity,
          title: alertTitle,
          description,
          clinicalSummary: description,
          vitalsSummary: vitalsSummary || {},
          recordedByUid: recordedByUid || null,
          recordedByName: recordedByName || null,
          isRead: false,
          isAcknowledged: false,
          acknowledgedAt: null,
          acknowledgedBy: null,
          isResolved: false,
          resolvedAt: null,
          resolvedBy: null,
          createdAt: serverNow,
          dispatchStatus: 'PENDING',
          dispatchAttempts: 0,
          escalationStatus: 'NONE',
        });

        t.set(notifRef, {
          id: alertId,
          patientId,
          title: alertTitle,
          body: isCritical
            ? 'Critical vital signs recorded for patient. Immediate review required.'
            : 'Abnormal vital signs recorded for patient. Please review when available.',
          type: 'vital_alert',
          referenceId: alertId,
          isRead: false,
          createdAt: serverNow,
        });
      }
    });

    // 4. Fetch FCM Device Tokens from users/{doctorId}/deviceTokens
    const tokenSnap = await db
      .collection('users')
      .doc(phys.doctorId)
      .collection('deviceTokens')
      .limit(10)
      .get();

    const tokenDocs = tokenSnap.docs;
    const tokens = tokenDocs
      .map((d) => (d.data().fcmToken as string || '').trim())
      .filter((t) => t.length > 0);

    if (tokens.length === 0) {
      // Missing tokens: record NO_TOKENS outcome; escalate to supervisor if critical
      await alertRef.update({
        dispatchStatus: 'NO_TOKENS',
        escalationStatus: isCritical ? 'ESCALATED' : 'NONE',
        lastDispatchError: 'Doctor has no active registered FCM device tokens.',
      });
      results.push({
        doctorId: phys.doctorId,
        alertId,
        status: 'NO_TOKENS',
        errorCode: 'NO_TOKENS',
      });
      if (isCritical) {
        supervisorEscalationNeeded = true;
        escalationReason = 'NO_TOKENS';
      }
      continue;
    }

    // 5. Compose Privacy-Safe FCM Payload (Zero PHI in transit)
    const fcmMessage: admin.messaging.MulticastMessage = {
      tokens,
      notification: {
        title: isCritical ? 'Critical patient alert' : 'Abnormal vital signs update',
        body: isCritical
          ? 'Open OncoVault to review an urgent clinical alert.'
          : 'New vital signs warning recorded for your patient.',
      },
      data: {
        type: 'vital_alert',
        referenceId: alertId,
        alertId,
        patientId,
        priority: isCritical ? 'high' : 'normal',
      },
      android: {
        priority: isCritical ? 'high' : 'normal',
        notification: {
          channelId: isCritical ? 'oncovault_critical_vitals' : 'oncovault_vital_updates',
          priority: isCritical ? 'max' : 'default',
          defaultSound: isCritical,
        },
      },
      apns: {
        headers: {
          'apns-priority': isCritical ? '10' : '5',
        },
        payload: {
          aps: {
            sound: isCritical ? 'default' : undefined,
          },
        },
      },
    };

    // 6. Bounded Retry Loop (Up to 3 attempts with exponential backoff)
    let sendSuccess = false;
    let successfulMessageIds: string[] = [];
    let lastError = '';
    const maxRetries = 3;

    for (let attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        const batchResponse = await fcm.sendEachForMulticast(fcmMessage);
        const expiredTokensToDelete: string[] = [];

        batchResponse.responses.forEach((resp, idx) => {
          if (resp.success && resp.messageId) {
            successfulMessageIds.push(resp.messageId);
          } else if (resp.error) {
            const code = resp.error.code;
            if (
              code === 'messaging/registration-token-not-registered' ||
              code === 'messaging/invalid-registration-token'
            ) {
              expiredTokensToDelete.push(tokenDocs[idx].id);
            }
            lastError = resp.error.message || code;
          }
        });

        // Clean up permanent invalid token errors from users/{doctorId}/deviceTokens
        for (const tid of expiredTokensToDelete) {
          try {
            await db
              .collection('users')
              .doc(phys.doctorId)
              .collection('deviceTokens')
              .doc(tid)
              .delete();
          } catch (_) {}
        }

        if (successfulMessageIds.length > 0) {
          sendSuccess = true;
          break; // Successfully accepted by FCM
        }
      } catch (err: any) {
        lastError = err?.message || String(err);
      }

      // Exponential backoff delay on retry: 50ms, 100ms
      if (attempt < maxRetries) {
        await new Promise((r) => setTimeout(r, 50 * Math.pow(2, attempt - 1)));
      }
    }

    if (sendSuccess) {
      await alertRef.update({
        dispatchStatus: 'DELIVERED',
        dispatchAttempts: maxRetries,
        fcmMessageIds: successfulMessageIds,
        lastDispatchedAt: FieldValue.serverTimestamp(),
      });
      results.push({
        doctorId: phys.doctorId,
        alertId,
        status: 'DELIVERED',
        fcmMessageIds: successfulMessageIds,
      });
    } else {
      await alertRef.update({
        dispatchStatus: 'FAILED',
        dispatchAttempts: maxRetries,
        lastDispatchError: lastError,
        escalationStatus: isCritical ? 'ESCALATED' : 'NONE',
        lastDispatchedAt: FieldValue.serverTimestamp(),
      });
      results.push({
        doctorId: phys.doctorId,
        alertId,
        status: 'FAILED',
        errorCode: lastError,
      });
      if (isCritical) {
        supervisorEscalationNeeded = true;
        escalationReason = 'FCM_DELIVERY_FAILURE';
      }
    }
  }

  // 7. Supervisor Escalation if Required (Critical Emergencies Only)
  if (supervisorEscalationNeeded && isCritical) {
    await escalateToSupervisors(db, {
      eventId,
      observationId,
      patientId,
      patientName: patientDisplayName,
      hospitalId: hospitalId || 'Oncology Ward 3A',
      reason: escalationReason,
      criticalReasons: criticalReasons || [],
      vitalsSummary,
    });
  }

  // 8. Complete Event Record with Lease Fencing Token Validation
  const finalStatus =
    supervisorEscalationNeeded && physicians.length === 0 ? 'ESCALATED' : 'COMPLETED';

  await db.runTransaction(async (t) => {
    const snap = await t.get(eventRef);
    if (!snap.exists) return;
    const currentData = snap.data() as CriticalAlertEventDocument;
    // Fencing token validation: if lease was taken over by another worker, do not overwrite
    if (currentData.leaseToken && currentData.leaseToken !== leaseToken) {
      return;
    }
    t.update(eventRef, {
      status: finalStatus,
      processingLease: null,
      completedAt: FieldValue.serverTimestamp(),
      dispatchResults: results,
      escalated: supervisorEscalationNeeded,
    });
  });

  return {
    success: true,
    results,
    escalated: supervisorEscalationNeeded,
  };
}

/**
 * Durable supervisor escalation mechanism:
 * Notifies Hospital Administrators when an emergency alert has no physician or fails delivery.
 */
export async function escalateToSupervisors(
  db: admin.firestore.Firestore,
  params: {
    eventId: string;
    observationId: string;
    patientId: string;
    patientName: string;
    hospitalId: string;
    reason: string;
    criticalReasons: string[];
    vitalsSummary: VitalsSummaryPayload;
  }
): Promise<void> {
  const { eventId, observationId, patientId, patientName, hospitalId, reason, criticalReasons, vitalsSummary } =
    params;

  const adminSnap = await db
    .collection('users')
    .where('role', '==', 'admin')
    .limit(10)
    .get();

  const escalationId = `esc_${observationId}`;
  const escRef = db.collection('escalated_alerts').doc(escalationId);

  await escRef.set({
    id: escalationId,
    eventId,
    observationId,
    patientId,
    patientName,
    hospitalId,
    reason,
    criticalReasons,
    vitalsSummary,
    createdAt: FieldValue.serverTimestamp(),
    status: 'ACTIVE_ESCALATION',
    isResolved: false,
  });

  for (const aDoc of adminSnap.docs) {
    const aData = aDoc.data();
    if (aData?.hospitalId && aData.hospitalId !== hospitalId) continue;

    const adminAlertId = `esc_${observationId}_${aDoc.id}`;
    await db
      .collection('doctors')
      .doc(aDoc.id)
      .collection('alerts')
      .doc(adminAlertId)
      .set({
        id: adminAlertId,
        alertId: adminAlertId,
        eventId,
        observationId,
        patientId,
        patientName,
        doctorId: aDoc.id,
        hospitalId,
        alertType: 'vital_alert',
        severity: 'high',
        title: 'ESCALATED VITAL ALERT (SUPERVISOR ACTION REQUIRED)',
        description: `Patient ${patientName} triggered critical vitals with supervisor escalation. Reason: ${reason}. Findings: ${criticalReasons.join('; ')}`,
        clinicalSummary: criticalReasons.join('; '),
        vitalsSummary: vitalsSummary || {},
        createdAt: FieldValue.serverTimestamp(),
        isRead: false,
        isAcknowledged: false,
        isResolved: false,
        escalationStatus: 'ESCALATED',
      });
  }
}

/**
 * Sweeper mechanism for alerts submitted to FCM but remaining unacknowledged by physician.
 * Escalates to hospital supervisor if alert is unacknowledged past deadline.
 * Deterministic document IDs prevent duplicate escalations on repeated runs.
 */
export async function escalateOverdueUnacknowledgedAlerts(
  db: admin.firestore.Firestore,
  options?: {
    deadlineMs?: number;
    currentTimeMs?: number;
  }
): Promise<{ checkedCount: number; escalatedCount: number }> {
  const nowMs = options?.currentTimeMs ?? Date.now();
  const deadlineMs = options?.deadlineMs ?? DEFAULT_ACKNOWLEDGMENT_DEADLINE_MS;
  const cutoffTimestamp = Timestamp.fromMillis(nowMs - deadlineMs);

  const alertsSnap = await db
    .collectionGroup('alerts')
    .where('severity', '==', 'high')
    .where('isAcknowledged', '==', false)
    .where('isResolved', '==', false)
    .where('createdAt', '<=', cutoffTimestamp)
    .limit(50)
    .get();

  let escalatedCount = 0;

  for (const doc of alertsSnap.docs) {
    const alertData = doc.data();
    const alertId = alertData.id || alertData.alertId || doc.id;
    const doctorId = alertData.doctorId;
    const observationId = alertData.observationId || alertId;
    const patientId = alertData.patientId;
    const patientName = alertData.patientName || 'Blood Cancer Patient';
    const hospitalId = alertData.hospitalId || 'Oncology Ward 3A';

    if (alertData.escalationStatus === 'OVERDUE_ESCALATED') {
      continue;
    }

    const alertRef = doc.ref;
    const escId = `esc_overdue_${alertId}`;
    const escRef = db.collection('escalated_alerts').doc(escId);

    const didEscalate = await db.runTransaction(async (t) => {
      const freshSnap = await t.get(alertRef);
      if (!freshSnap.exists) return false;
      const freshData = freshSnap.data();

      if (freshData?.isAcknowledged === true || freshData?.isResolved === true) {
        return false;
      }
      if (freshData?.escalationStatus === 'OVERDUE_ESCALATED') {
        return false;
      }

      const escSnap = await t.get(escRef);
      if (!escSnap.exists) {
        t.set(escRef, {
          id: escId,
          escalationType: 'OVERDUE_UNACKNOWLEDGED',
          alertId,
          observationId,
          patientId,
          patientName,
          doctorId,
          hospitalId,
          reason: `High-priority vital alert unacknowledged by physician within ${Math.round(deadlineMs / 60000)} minute clinical escalation window.`,
          criticalReasons: freshData?.clinicalSummary ? [freshData.clinicalSummary] : [],
          vitalsSummary: freshData?.vitalsSummary || {},
          createdAt: FieldValue.serverTimestamp(),
          status: 'ACTIVE_ESCALATION',
          isResolved: false,
        });
      }

      t.update(alertRef, {
        escalationStatus: 'OVERDUE_ESCALATED',
        escalatedAt: FieldValue.serverTimestamp(),
      });

      return true;
    });

    if (didEscalate) {
      escalatedCount++;
    }
  }

  return { checkedCount: alertsSnap.size, escalatedCount };
}

/**
 * Scheduled or on-demand crash-recovery worker.
 * Sweeps stuck pending events or expired leases and dispatches them safely.
 */
export async function recoverPendingAlertEvents(
  db: admin.firestore.Firestore,
  customFcmSender?: FcmSender
): Promise<number> {
  const nowMs = Date.now();
  const pendingSnap = await db
    .collection('critical_alert_events')
    .where('status', 'in', ['PENDING', 'PROCESSING'])
    .limit(20)
    .get();

  let recoveredCount = 0;
  for (const doc of pendingSnap.docs) {
    const data = doc.data() as CriticalAlertEventDocument;
    // Process if pending or lease expired
    if (data.status === 'PENDING' || (data.processingLease && data.processingLease < nowMs)) {
      await processCriticalAlertEvent(db, doc.id, customFcmSender);
      recoveredCount++;
    }
  }

  return recoveredCount;
}

// ─── Registered Cloud Functions (v2) ──────────────────────────────────────────

/**
 * Registered Firestore Document Trigger:
 * Executes automatically upon creation of any critical/warning alert event document.
 * Ensures alert delivery survives callable termination.
 */
export const dispatchCriticalAlertOnCreate = onDocumentCreated(
  {
    document: 'critical_alert_events/{eventId}',
    region: 'us-central1',
  },
  async (event) => {
    if (!event.data) return;
    const db = admin.firestore();
    await processCriticalAlertEvent(db, event.params.eventId);
  }
);

/**
 * Registered Cloud Scheduler Recovery Function:
 * Runs periodically to recover stuck pending/leased events and escalate overdue unacknowledged alerts.
 * Note: Requires Cloud Scheduler API and GCP Blaze billing plan in live production.
 */
export const recoverCriticalAlertEventsOnSchedule = onSchedule(
  {
    schedule: 'every 5 minutes',
    region: 'us-central1',
    timeZone: 'Asia/Karachi',
  },
  async () => {
    const db = admin.firestore();
    await recoverPendingAlertEvents(db);
    await escalateOverdueUnacknowledgedAlerts(db);
  }
);
