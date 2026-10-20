import * as admin from 'firebase-admin';

process.env.FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099';
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';

async function seedUserForApp(app: admin.app.App, userData: {
  uid: string;
  email: string;
  password: string;
  displayName: string;
  medicalId: string;
  role: string;
  specialty?: string;
}) {
  const auth = app.auth();
  const db = app.firestore();

  // 1. Create or update user in Auth emulator
  try {
    await auth.getUser(userData.uid);
    await auth.updateUser(userData.uid, {
      email: userData.email,
      password: userData.password,
      displayName: userData.displayName,
    });
    console.log(`[${app.name}] Auth user ${userData.uid} updated.`);
  } catch (e: any) {
    if (e.code === 'auth/user-not-found') {
      await auth.createUser({
        uid: userData.uid,
        email: userData.email,
        password: userData.password,
        displayName: userData.displayName,
      });
      console.log(`[${app.name}] Auth user ${userData.uid} created.`);
    } else {
      throw e;
    }
  }

  // 2. Add /users/{uid}
  await db.collection('users').doc(userData.uid).set({
    uid: userData.uid,
    name: userData.displayName,
    email: userData.email,
    medicalId: userData.medicalId,
    role: userData.role,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });

  // 3. Add /medical_id_directory/{medicalId}
  await db.collection('medical_id_directory').doc(userData.medicalId.toUpperCase()).set({
    uid: userData.uid,
    email: userData.email,
  }, { merge: true });

  // 4. Role specific collection
  if (userData.role === 'doctor') {
    await db.collection('doctors').doc(userData.uid).set({
      uid: userData.uid,
      id: userData.uid,
      name: userData.displayName,
      email: userData.email,
      medicalId: userData.medicalId,
      role: 'doctor',
      specialty: userData.specialty || 'Hematologist-Oncologist',
      department: 'Hematology',
      hospital: 'OncoVault Medical Center',
      isAvailable: true,
      availableDays: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'],
      availableSlots: ['09:00 AM', '10:00 AM', '11:00 AM', '02:00 PM', '03:00 PM', '04:00 PM'],
      availability: {
        slotDurationMinutes: 45,
        weeklySchedule: {
          monday: { enabled: true, startTime: '09:00', endTime: '17:00' },
          tuesday: { enabled: true, startTime: '09:00', endTime: '17:00' },
          wednesday: { enabled: true, startTime: '09:00', endTime: '17:00' },
          thursday: { enabled: true, startTime: '09:00', endTime: '17:00' },
          friday: { enabled: true, startTime: '09:00', endTime: '17:00' },
          saturday: { enabled: false, startTime: '09:00', endTime: '17:00' },
          sunday: { enabled: false, startTime: '09:00', endTime: '17:00' },
        },
        blockedDates: [],
        blockedSlots: [],
      },
    }, { merge: true });
  } else if (userData.role === 'patient') {
    await db.collection('patients').doc(userData.uid).set({
      uid: userData.uid,
      id: userData.uid,
      name: userData.displayName,
      email: userData.email,
      medicalId: userData.medicalId,
      role: 'patient',
    }, { merge: true });
  }
}

async function seedProject(projectId: string) {
  console.log(`\n--- Seeding emulator data for project: ${projectId} ---`);
  const app = admin.initializeApp({ projectId }, projectId);

  try {
    // Doctor A
    await seedUserForApp(app, {
      uid: 'doc_a_local',
      email: 'doc_a@oncovault.local',
      password: 'password123',
      displayName: 'Dr. Alice Vance',
      medicalId: 'OV-DO-DOCA01',
      role: 'doctor',
      specialty: 'Hematologist-Oncologist',
    });

    // Doctor B
    await seedUserForApp(app, {
      uid: 'doc_b_local',
      email: 'doc_b@oncovault.local',
      password: 'password123',
      displayName: 'Dr. Bob Carter',
      medicalId: 'OV-DO-DOCB02',
      role: 'doctor',
      specialty: 'Clinical Hematologist',
    });

    // Patient A
    await seedUserForApp(app, {
      uid: 'patient_a_local',
      email: 'patient_a@oncovault.local',
      password: 'password123',
      displayName: 'Arthur Dent',
      medicalId: 'OV-PA-PATA01',
      role: 'patient',
    });

    // Patient B
    await seedUserForApp(app, {
      uid: 'patient_b_local',
      email: 'patient_b@oncovault.local',
      password: 'password123',
      displayName: 'Beatrice Mills',
      medicalId: 'OV-PA-PATB02',
      role: 'patient',
    });

    console.log(`[+] Project ${projectId} successfully seeded!`);
  } finally {
    await app.delete();
  }
}

async function main() {
  const projectsToSeed = ['demo-oncovault-local', 'oncovault-8cbbc'];
  for (const proj of projectsToSeed) {
    try {
      await seedProject(proj);
    } catch (err) {
      console.error(`Failed seeding project ${proj}:`, err);
    }
  }
  console.log('\nAll emulator projects seeded successfully!');
  process.exit(0);
}

main().catch((err) => {
  console.error('Seed error:', err);
  process.exit(1);
});
