// functions/src/index.ts

import * as admin from 'firebase-admin';

// Initialize Firebase Admin SDK
if (!admin.apps.length) {
  admin.initializeApp({
    projectId: process.env.GCLOUD_PROJECT || 'demo-oncovault-local',
  });
}

// Export Cloud Functions
export { approveAppointment } from './approve_appointment';
export { updateDoctorAvailability } from './update_doctor_availability';
export { assignNurse, revokeNurseAssignment } from './assign_nurse';
export { recordVitalObservation } from './record_vital_observation';
export { acknowledgeCriticalAlert, resolveCriticalAlert } from './manage_critical_alert';
export {
  dispatchCriticalAlertOnCreate,
  recoverCriticalAlertEventsOnSchedule,
} from './dispatch_critical_alert';
export {
  saveClinicalNoteDraft,
  submitClinicalNote,
  reviewClinicalNote,
} from './record_clinical_note';
export {
  createTreatmentPlan,
  completeTreatmentTask,
  recordTreatmentProgressUpdate,
  updateTreatmentPlanStatus,
} from './manage_treatment_plan';
