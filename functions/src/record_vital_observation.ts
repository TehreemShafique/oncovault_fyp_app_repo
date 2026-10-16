// functions/src/record_vital_observation.ts

import { onCall, HttpsError } from 'firebase-functions/v2/https';
import * as admin from 'firebase-admin';
import { FieldValue, Timestamp } from 'firebase-admin/firestore';
import { toPktDate } from './utils/time_utils';
import { verifyDoctorCareAuthorization } from './assign_nurse';
import { processCriticalAlertEvent, FcmSender } from './dispatch_critical_alert';

export interface RecordVitalObservationRequest {
  patientId: string;
  systolicBp: number;
  diastolicBp: number;
  pulseRate: number;
  temperature: number; // in Celsius or Fahrenheit based on temperatureUnit
  temperatureUnit?: 'C' | 'F';
  respiratoryRate: number;
  oxygenSaturation: number;
  weightKg?: number;
  heightCm?: number;
  notes?: string;
  observationId?: string; // Optional client-supplied deterministic ID for idempotency/retries
  clientRecordedAt?: string | number; // Optional clinical observation timestamp (e.g. ISO string or ms epoch)
}

export interface RecordVitalObservationResponse {
  success: boolean;
  observationId: string;
  patientId: string;
  isCritical: boolean;
  severity: 'normal' | 'warning' | 'critical';
  warningFlags: string[];
  criticalReasons: string[];
}

/**
 * Assesses clinical reference ranges and critical boundaries.
 */
function assessVitals(params: {
  systolicBp: number;
  diastolicBp: number;
  pulseRate: number;
  temperatureC: number;
  respiratoryRate: number;
  oxygenSaturation: number;
}): {
  severity: 'normal' | 'warning' | 'critical';
  isCritical: boolean;
  warnings: string[];
  criticalReasons: string[];
} {
  const warnings: string[] = [];
  const criticalReasons: string[] = [];

  const { systolicBp, diastolicBp, pulseRate, temperatureC, respiratoryRate, oxygenSaturation } =
    params;

  // 1. Blood Pressure
  if (systolicBp >= 180 || diastolicBp >= 120) {
    criticalReasons.push(`Hypertensive Crisis (BP: ${Math.round(systolicBp)}/${Math.round(diastolicBp)} mmHg)`);
  } else if (systolicBp < 80 || diastolicBp < 50) {
    criticalReasons.push(`Severe Hypotension / Shock Risk (BP: ${Math.round(systolicBp)}/${Math.round(diastolicBp)} mmHg)`);
  } else if (systolicBp >= 140 || diastolicBp >= 90) {
    warnings.push(`Stage 2 Hypertension (BP: ${Math.round(systolicBp)}/${Math.round(diastolicBp)} mmHg)`);
  } else if (systolicBp > 120 || diastolicBp > 80) {
    warnings.push(`Elevated / Pre-hypertension (BP: ${Math.round(systolicBp)}/${Math.round(diastolicBp)} mmHg)`);
  } else if (systolicBp < 90 || diastolicBp < 60) {
    warnings.push(`Mild Hypotension (BP: ${Math.round(systolicBp)}/${Math.round(diastolicBp)} mmHg)`);
  }

  // 2. Pulse Rate
  if (pulseRate > 130) {
    criticalReasons.push(`Severe Tachycardia (${Math.round(pulseRate)} bpm)`);
  } else if (pulseRate < 45) {
    criticalReasons.push(`Severe Bradycardia (${Math.round(pulseRate)} bpm)`);
  } else if (pulseRate > 100) {
    warnings.push(`Mild Tachycardia (${Math.round(pulseRate)} bpm)`);
  } else if (pulseRate < 60) {
    warnings.push(`Mild Bradycardia (${Math.round(pulseRate)} bpm)`);
  }

  // 3. Temperature (Hematologic Neutropenic Fever)
  if (temperatureC >= 38.5) {
    criticalReasons.push(`High Fever / Febrile Alert (${temperatureC.toFixed(1)} °C)`);
  } else if (temperatureC < 35.0) {
    criticalReasons.push(`Hypothermia (${temperatureC.toFixed(1)} °C)`);
  } else if (temperatureC >= 37.6) {
    warnings.push(`Low-grade Elevation (${temperatureC.toFixed(1)} °C)`);
  } else if (temperatureC < 36.5) {
    warnings.push(`Subnormal Temperature (${temperatureC.toFixed(1)} °C)`);
  }

  // 4. Respiratory Rate
  if (respiratoryRate >= 30) {
    criticalReasons.push(`Severe Tachypnea (${Math.round(respiratoryRate)} breaths/min)`);
  } else if (respiratoryRate < 10) {
    criticalReasons.push(`Severe Bradypnea (${Math.round(respiratoryRate)} breaths/min)`);
  } else if (respiratoryRate > 20) {
    warnings.push(`Elevated Respiratory Rate (${Math.round(respiratoryRate)} breaths/min)`);
  } else if (respiratoryRate < 12) {
    warnings.push(`Low Respiratory Rate (${Math.round(respiratoryRate)} breaths/min)`);
  }

  // 5. Oxygen Saturation
  if (oxygenSaturation < 90) {
    criticalReasons.push(`Severe Hypoxemia (SpO2: ${Math.round(oxygenSaturation)}%)`);
  } else if (oxygenSaturation < 95) {
    warnings.push(`Mild Hypoxia (SpO2: ${Math.round(oxygenSaturation)}%)`);
  }

  const isCritical = criticalReasons.length > 0;
  const severity = isCritical ? 'critical' : warnings.length > 0 ? 'warning' : 'normal';

  return { severity, isCritical, warnings, criticalReasons };
}

/**
 * Trusted 2nd Generation Cloud Function: recordVitalObservation
 * Enforces authenticated clinician identity, active care assignment/doctor authorization,
 * strict input range boundaries, immutable observation persistence, idempotency on retries,
 * and race-free latest-cache synchronization where delayed readings do not overwrite newer ones.
 */
export const recordVitalObservationHandler = async (
  request: { auth?: { uid: string }; data: any },
  firestoreInstance?: admin.firestore.Firestore,
  customFcmSender?: FcmSender
): Promise<RecordVitalObservationResponse> => {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError('unauthenticated', 'User must be authenticated to record vitals.');
  }

  const callerUid = request.auth.uid;
  const db = firestoreInstance || admin.firestore();

  // 1. Verify Caller Role & Identity
  const userDoc = await db.collection('users').doc(callerUid).get();
  if (!userDoc.exists) {
    throw new HttpsError('permission-denied', 'User record not found.');
  }
  const userData = userDoc.data();
  const userRole = (userData?.role || '').toLowerCase();
  if (userRole !== 'nurse' && userRole !== 'doctor' && userRole !== 'admin') {
    throw new HttpsError('permission-denied', 'Only authorized nurses, doctors, or administrators can record patient vitals.');
  }
  const clinicianName = userData?.name || (userRole === 'doctor' ? 'Attending Physician' : userRole === 'admin' ? 'Administrator' : 'Staff Nurse');

  const payload = request.data as RecordVitalObservationRequest;
  const { patientId } = payload;
  if (!patientId || typeof patientId !== 'string' || !patientId.trim()) {
    throw new HttpsError('invalid-argument', 'Valid patientId is required.');
  }

  // 2. Authorization Check: Active Care Assignment or Doctor Relationship
  if (userRole === 'nurse') {
    const assignmentId = `${callerUid}_${patientId}`;
    const assignDoc = await db.collection('nurse_patient_assignments').doc(assignmentId).get();
    if (!assignDoc.exists || assignDoc.data()?.status !== 'active') {
      throw new HttpsError(
        'permission-denied',
        `Nurse is not actively assigned to patient ${patientId}. Access denied.`
      );
    }
  } else if (userRole === 'doctor') {
    await verifyDoctorCareAuthorization(db, callerUid, patientId);
  }

  // 3. Input Validation (SDS Permissible Bounds)
  const {
    systolicBp,
    diastolicBp,
    pulseRate,
    temperature,
    temperatureUnit = 'C',
    respiratoryRate,
    oxygenSaturation,
    weightKg,
    heightCm,
    notes = '',
    observationId: clientSuppliedObsId,
    clientRecordedAt,
  } = payload;

  if (typeof systolicBp !== 'number' || systolicBp < 60 || systolicBp > 250) {
    throw new HttpsError('invalid-argument', 'Systolic BP must be a numeric value between 60 and 250 mmHg.');
  }
  if (typeof diastolicBp !== 'number' || diastolicBp < 40 || diastolicBp > 140) {
    throw new HttpsError('invalid-argument', 'Diastolic BP must be a numeric value between 40 and 140 mmHg.');
  }
  if (diastolicBp >= systolicBp) {
    throw new HttpsError('invalid-argument', 'Diastolic BP must be strictly less than Systolic BP.');
  }
  if (typeof pulseRate !== 'number' || pulseRate < 30 || pulseRate > 220) {
    throw new HttpsError('invalid-argument', 'Pulse rate must be a numeric value between 30 and 220 bpm.');
  }

  // Normalize temperature to Celsius
  let tempC = temperature;
  if (temperatureUnit === 'F') {
    tempC = ((temperature - 32) * 5) / 9;
  }
  if (typeof tempC !== 'number' || tempC < 32.0 || tempC > 43.0) {
    throw new HttpsError('invalid-argument', 'Temperature must be between 32.0 and 43.0 °C (89.6–109.4 °F).');
  }

  if (typeof respiratoryRate !== 'number' || respiratoryRate < 6 || respiratoryRate > 60) {
    throw new HttpsError('invalid-argument', 'Respiratory rate must be between 6 and 60 breaths/min.');
  }
  if (typeof oxygenSaturation !== 'number' || oxygenSaturation < 50 || oxygenSaturation > 100) {
    throw new HttpsError('invalid-argument', 'Oxygen saturation must be between 50 and 100%.');
  }

  // 4. Clinical Assessment (Computed Server-Side — Client cannot tamper with warning/critical flags)
  const assessment = assessVitals({
    systolicBp,
    diastolicBp,
    pulseRate,
    temperatureC: tempC,
    respiratoryRate,
    oxygenSaturation,
  });

  // 5. Establish Observation ID & Timestamps
  const observationRef = clientSuppliedObsId?.trim()
    ? db.collection('ehr_vitals').doc(patientId).collection('observations').doc(clientSuppliedObsId.trim())
    : db.collection('ehr_vitals').doc(patientId).collection('observations').doc();

  const observationId = observationRef.id;
  const parentRef = db.collection('ehr_vitals').doc(patientId);

  // Clinical observation date: server-controlled, or verified past date if client specifies
  let obsDate = new Date();
  if (clientRecordedAt) {
    const parsed = new Date(clientRecordedAt);
    if (!isNaN(parsed.getTime())) {
      // Prevent observations recorded in the future (>5 mins ahead of server)
      if (parsed.getTime() <= Date.now() + 300000) {
        obsDate = parsed;
      }
    }
  }

  const dateKey = toPktDate(obsDate).dateKey;
  const nurseDailyStatsRef = db
    .collection('nurses')
    .doc(callerUid)
    .collection('daily_stats')
    .doc(dateKey);

  // 6. Atomic Transaction: Persist Observation & Race-Free Latest Cache Update
  let isReplay = false;

  await db.runTransaction(async (transaction) => {
    // Check for idempotency: if observation document already exists, absorb retry safely
    const existingObsDoc = await transaction.get(observationRef);
    if (existingObsDoc.exists) {
      isReplay = true;
      return;
    }

    const parentDoc = await transaction.get(parentRef);
    const serverNow = FieldValue.serverTimestamp();
    const obsTimestamp = Timestamp.fromDate(obsDate);

    const isDoctor = userRole === 'doctor';
    const isNurseRole = userRole === 'nurse';

    // Immutable Observation Document
    const obsData: any = {
      id: observationId,
      patientId,
      recordedBy: callerUid,
      recordedByName: clinicianName,
      recordedByRole: userRole,
      recordedAt: obsTimestamp,
      createdAt: serverNow,
      systolicBp,
      diastolicBp,
      pulseRate,
      temperature: tempC,
      temperatureUnit,
      respiratoryRate,
      oxygenSaturation,
      weightKg: weightKg || null,
      heightCm: heightCm || null,
      notes: notes || '',
      isCritical: assessment.isCritical,
      warningFlags: assessment.warnings,
      criticalReasons: assessment.criticalReasons,
      severity: assessment.severity,
    };

    if (isDoctor) {
      obsData.doctorId = callerUid;
      obsData.doctorName = clinicianName;
    } else if (isNurseRole) {
      obsData.nurseId = callerUid;
      obsData.nurseName = clinicianName;
    }

    transaction.set(observationRef, obsData);

    // Compute display values for backward-compatible latest cache
    const bpDisplay = `${Math.round(systolicBp)}/${Math.round(diastolicBp)} mmHg`;
    const tempF = (tempC * 9) / 5 + 32;
    const tempDisplay =
      temperatureUnit === 'F'
        ? `${tempF.toFixed(1)} °F (${tempC.toFixed(1)} °C)`
        : `${tempC.toFixed(1)} °C (${tempF.toFixed(1)} °F)`;

    let bmi: number | null = null;
    if (weightKg && heightCm && heightCm > 0) {
      const heightM = heightCm / 100;
      bmi = parseFloat((weightKg / (heightM * heightM)).toFixed(1));
    }

    const latestSummary: any = {
      latestObservationId: observationId,
      recordedBy: callerUid,
      recordedByName: clinicianName,
      recordedByRole: userRole,
      updatedAt: serverNow,
      recordedAt: obsTimestamp,
      bloodPressure: bpDisplay,
      systolicBp,
      diastolicBp,
      heartRate: Math.round(pulseRate),
      pulseRate,
      temperature: tempC,
      temperatureDisplay: tempDisplay,
      respiratoryRate: Math.round(respiratoryRate),
      oxygenSaturation: Math.round(oxygenSaturation),
      weight: weightKg || null,
      weightKg: weightKg || null,
      heightCm: heightCm || null,
      bmi,
      isCritical: assessment.isCritical,
      severity: assessment.severity,
      warningFlags: assessment.warnings,
      criticalReasons: assessment.criticalReasons,
      notes: notes || '',
    };

    if (isDoctor) {
      latestSummary.lastDoctorId = callerUid;
      latestSummary.lastDoctorName = clinicianName;
      latestSummary.lastRecordedByName = clinicianName;
    } else if (isNurseRole) {
      latestSummary.lastNurseId = callerUid;
      latestSummary.lastNurseName = clinicianName;
      latestSummary.lastRecordedByName = clinicianName;
    }

    // Delayed readings check: Only update latest cache if parent doesn't exist OR parent recordedAt is older
    let shouldUpdateLatest = true;
    if (parentDoc.exists) {
      const parentData = parentDoc.data();
      const existingRecordedAt = parentData?.recordedAt as Timestamp | undefined;
      if (existingRecordedAt && existingRecordedAt.toMillis() > obsDate.getTime()) {
        shouldUpdateLatest = false; // Delayed older reading: do not overwrite newer latest cache
      }
    }

    if (shouldUpdateLatest) {
      transaction.set(parentRef, latestSummary, { merge: true });
    }

    // Update nurse daily counter for SDS Mockup M9 FR-NHO.2
    if (userRole === 'nurse') {
      transaction.set(
        nurseDailyStatsRef,
        {
          vitalsRecordedToday: FieldValue.increment(1),
          dateKey,
          nurseId: callerUid,
          lastRecordedAt: serverNow,
        },
        { merge: true }
      );
    }

    // Step 1: Atomically persist durable pending alert event if observation is abnormal (critical or warning)
    const isAbnormal = assessment.isCritical || (assessment.warnings && assessment.warnings.length > 0);
    if (isAbnormal) {
      const eventRef = db.collection('critical_alert_events').doc(`event_${observationId}`);
      const alertSeverity: 'high' | 'medium' = assessment.isCritical ? 'high' : 'medium';
      transaction.set(eventRef, {
        eventId: `event_${observationId}`,
        observationId,
        patientId,
        patientName: '',
        hospitalId: userData?.hospitalId || 'Oncology Ward 3A',
        eventType: 'vital_alert',
        severity: alertSeverity,
        status: 'PENDING',
        createdAt: serverNow,
        attempts: 0,
        lastAttemptAt: null,
        processingLease: null,
        lastErrorCode: null,
        completedAt: null,
        criticalReasons: assessment.criticalReasons,
        warningFlags: assessment.warnings,
        vitalsSummary: {
          bloodPressure: bpDisplay,
          systolicBp,
          diastolicBp,
          pulseRate: Math.round(pulseRate),
          temperatureC: tempC,
          respiratoryRate: Math.round(respiratoryRate),
          oxygenSaturation: Math.round(oxygenSaturation),
        },
        recordedByUid: callerUid,
        recordedByName: clinicianName,
        recordedByRole: userRole,
      });
    }
  });

  // Step 2: Post-commit trusted alert worker dispatch (Outside transaction)
  const isAbnormal = assessment.isCritical || (assessment.warnings && assessment.warnings.length > 0);
  if (!isReplay && isAbnormal) {
    try {
      await processCriticalAlertEvent(db, `event_${observationId}`, customFcmSender);
    } catch (dispatchErr) {
      // Crash resilience: the durable event is already safely committed in critical_alert_events in status 'PENDING'.
      // A background sweeper or recovery worker will process it. Never fail the vital observation write if dispatch throws.
      console.error(`Alert dispatch deferred to recovery worker for observation ${observationId}:`, dispatchErr);
    }
  }

  return {
    success: true,
    observationId,
    patientId,
    isCritical: assessment.isCritical,
    severity: assessment.severity,
    warningFlags: assessment.warnings,
    criticalReasons: assessment.criticalReasons,
  };
};

export const recordVitalObservation = onCall(
  { region: 'us-central1' },
  recordVitalObservationHandler
);
