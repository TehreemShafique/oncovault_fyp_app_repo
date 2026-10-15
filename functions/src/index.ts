// functions/src/index.ts

import * as admin from 'firebase-admin';

// Initialize Firebase Admin SDK
if (!admin.apps.length) {
  admin.initializeApp();
}

// Export Cloud Functions
export { approveAppointment } from './approve_appointment';
