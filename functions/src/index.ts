// functions/src/index.ts

import * as admin from 'firebase-admin';

// Initialize Firebase Admin SDK
if (!admin.apps.length) {
  admin.initializeApp();
}

// Export Cloud Functions
export { approveAppointment } from './approve_appointment';
export { updateDoctorAvailability } from './update_doctor_availability';
export { assignNurse, revokeNurseAssignment } from './assign_nurse';
export { recordVitalObservation } from './record_vital_observation';
