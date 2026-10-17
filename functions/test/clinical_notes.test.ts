// functions/test/clinical_notes.test.ts

import * as admin from 'firebase-admin';
import {
  saveClinicalNoteDraftHandler,
  submitClinicalNoteHandler,
  reviewClinicalNoteHandler,
} from '../src/record_clinical_note';

const PROJECT_ID = process.env.GCLOUD_PROJECT || 'demo-no-project';

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
}

if (!admin.apps.length) {
  admin.initializeApp({ projectId: PROJECT_ID });
}

const db = admin.firestore();

jest.setTimeout(60000);

describe('Phase 3C Clinical Voice Notes Callable Security & Business Logic Tests', () => {
  const hospA = 'Oncology Ward 3C-A';
  const hospB = 'Foreign Hospital 3C-B';

  const nurseA = 'nurse_3c_assigned';
  const nurseUnassigned = 'nurse_3c_unassigned';
  const nurseB = 'nurse_3c_foreign';
  const doctorA = 'doc_3c_attending';
  const doctorB = 'doc_3c_foreign';
  const patientA = 'pat_3c_main';
  const patientForeign = 'pat_3c_foreign';

  beforeAll(async () => {
    const batch = db.batch();

    // Users
    batch.set(db.collection('users').doc(nurseA), {
      uid: nurseA,
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
    batch.set(db.collection('users').doc(nurseB), {
      uid: nurseB,
      role: 'nurse',
      name: 'Nurse Foreign',
      hospitalId: hospB,
    });
    batch.set(db.collection('users').doc(doctorA), {
      uid: doctorA,
      role: 'doctor',
      name: 'Dr. House',
      hospitalId: hospA,
    });
    batch.set(db.collection('users').doc(doctorB), {
      uid: doctorB,
      role: 'doctor',
      name: 'Dr. Foreign',
      hospitalId: hospB,
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

    // Active Care Assignment: nurseA -> patientA
    batch.set(db.collection('nurse_patient_assignments').doc(`${nurseA}_${patientA}`), {
      id: `${nurseA}_${patientA}`,
      nurseId: nurseA,
      nurseName: 'Nurse Sara',
      patientId: patientA,
      patientName: 'Alice Patient',
      hospitalId: hospA,
      status: 'active',
      assignedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Doctor Consent / Treating relationship: doctorA -> patientA
    batch.set(db.collection('doctor_patient_consents').doc(`${patientA}_${doctorA}`), {
      patientId: patientA,
      doctorId: doctorA,
      status: 'granted',
      hospitalId: hospA,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await batch.commit();
  });

  // ── 1. DRAFT MANAGEMENT ──
  describe('saveClinicalNoteDraft', () => {
    test('Unauthenticated caller is rejected with unauthenticated', async () => {
      await expect(
        saveClinicalNoteDraftHandler({
          data: { patientId: patientA, rawTranscription: 'test' },
          auth: undefined,
        } as any)
      ).rejects.toMatchObject({ code: 'unauthenticated' });
    });

    test('Patient caller is rejected with permission-denied', async () => {
      await expect(
        saveClinicalNoteDraftHandler({
          data: { patientId: patientA, rawTranscription: 'test' },
          auth: { uid: patientA },
        } as any)
      ).rejects.toMatchObject({ code: 'permission-denied' });
    });

    test('Unassigned nurse is rejected when saving draft for patient without assignment', async () => {
      await expect(
        saveClinicalNoteDraftHandler({
          data: { patientId: patientA, rawTranscription: 'Patient complaining of nausea' },
          auth: { uid: nurseUnassigned },
        } as any)
      ).rejects.toMatchObject({ code: 'permission-denied' });
    });

    test('Assigned nurse successfully creates and saves draft note', async () => {
      const res = await saveClinicalNoteDraftHandler({
        data: {
          patientId: patientA,
          patientName: 'Alice Patient',
          noteType: 'progressNote',
          rawTranscription: 'Patient reports mild fatigue after chemo cycle 2.',
          nurseReviewedTranscript: 'Patient reports mild fatigue after chemotherapy cycle 2.',
          clinicalSummary: 'Tolerating cycle 2 with mild fatigue.',
          supportedExtractedSymptoms: { persistentWeaknessAndFatigue: true },
          narrativeObservations: 'Vital signs within normal limits.',
          careInterventions: 'Hydration maintained.',
        },
        auth: { uid: nurseA },
      } as any);

      expect(res.success).toBe(true);
      expect(res.status).toBe('DRAFT');
      expect(res.noteId).toBeDefined();

      const docSnap = await db.collection('patients').doc(patientA).collection('clinical_notes').doc(res.noteId).get();
      expect(docSnap.exists).toBe(true);
      const data = docSnap.data()!;
      expect(data.status).toBe('DRAFT');
      expect(data.authorUid).toBe(nurseA);
      expect(data.clinicalSummary).toBe('Tolerating cycle 2 with mild fatigue.');
    });

    test('Assigned nurse can update an existing draft they authored', async () => {
      // First save draft
      const initial = await saveClinicalNoteDraftHandler({
        data: {
          patientId: patientA,
          rawTranscription: 'Draft 1',
        },
        auth: { uid: nurseA },
      } as any);

      // Now update the same draft
      const updated = await saveClinicalNoteDraftHandler({
        data: {
          noteId: initial.noteId,
          patientId: patientA,
          rawTranscription: 'Draft 1 updated with more details',
          clinicalSummary: 'Updated summary',
        },
        auth: { uid: nurseA },
      } as any);

      expect(updated.noteId).toBe(initial.noteId);
      const docSnap = await db.collection('patients').doc(patientA).collection('clinical_notes').doc(initial.noteId).get();
      expect(docSnap.data()!.clinicalSummary).toBe('Updated summary');
    });

    test('Different nurse cannot overwrite another nurse’s draft note', async () => {
      // Create draft by nurseA
      const draft = await saveClinicalNoteDraftHandler({
        data: { patientId: patientA, rawTranscription: 'Nurse A private draft' },
        auth: { uid: nurseA },
      } as any);

      // Seed assignment for nurseUnassigned so they have assignment, but are not author
      await db.collection('nurse_patient_assignments').doc(`${nurseUnassigned}_${patientA}`).set({
        id: `${nurseUnassigned}_${patientA}`,
        nurseId: nurseUnassigned,
        patientId: patientA,
        hospitalId: hospA,
        status: 'active',
      });

      // Nurse Unassigned tries to modify Nurse A's draft
      await expect(
        saveClinicalNoteDraftHandler({
          data: {
            noteId: draft.noteId,
            patientId: patientA,
            rawTranscription: 'Hijacked draft',
          },
          auth: { uid: nurseUnassigned },
        } as any)
      ).rejects.toMatchObject({ code: 'permission-denied' });
    });
  });

  // ── 2. NOTE SUBMISSION & IMMUTABILITY ──
  describe('submitClinicalNote', () => {
    test('Assigned nurse submits note: sets SUBMITTED status and computes canonical SHA-256', async () => {
      const res = await submitClinicalNoteHandler({
        data: {
          patientId: patientA,
          patientName: 'Alice Patient',
          noteType: 'progressNote',
          rawTranscription: 'Patient reports mild fatigue after chemo cycle 2.',
          nurseReviewedTranscript: 'Patient reports mild fatigue after chemotherapy cycle 2.',
          clinicalSummary: 'Tolerating cycle 2 with mild fatigue.',
          supportedExtractedSymptoms: { persistentWeaknessAndFatigue: true },
          narrativeObservations: 'Vital signs within normal limits.',
          careInterventions: 'Hydration maintained.',
          treatmentResponseNarrative: 'Appetite intact.',
        },
        auth: { uid: nurseA },
      } as any);

      expect(res.success).toBe(true);
      expect(res.status).toBe('SUBMITTED');
      expect(res.fileHash).toBeDefined();
      expect(res.fileHash.length).toBe(64); // Valid SHA-256 hex digest

      const docSnap = await db.collection('patients').doc(patientA).collection('clinical_notes').doc(res.noteId).get();
      const note = docSnap.data()!;
      expect(note.status).toBe('SUBMITTED');
      expect(note.fileHash).toBe(res.fileHash);
      expect(note.isAmended).toBe(false);
    });

    test('Submitted note cannot be modified or re-submitted (immutability)', async () => {
      const submitted = await submitClinicalNoteHandler({
        data: {
          patientId: patientA,
          patientName: 'Alice Patient',
          noteType: 'intakeNote',
          rawTranscription: 'Immutable intake note',
          nurseReviewedTranscript: 'Immutable intake note',
          clinicalSummary: 'Initial intake completed.',
        },
        auth: { uid: nurseA },
      } as any);

      // Trying to overwrite submitted note via submitClinicalNote
      await expect(
        submitClinicalNoteHandler({
          data: {
            noteId: submitted.noteId,
            patientId: patientA,
            clinicalSummary: 'Tampered summary',
          },
          auth: { uid: nurseA },
        } as any)
      ).rejects.toMatchObject({ code: 'failed-precondition' });

      // Trying to overwrite submitted note via saveClinicalNoteDraft
      await expect(
        saveClinicalNoteDraftHandler({
          data: {
            noteId: submitted.noteId,
            patientId: patientA,
            clinicalSummary: 'Tampered draft summary',
          },
          auth: { uid: nurseA },
        } as any)
      ).rejects.toMatchObject({ code: 'failed-precondition' });
    });

    test('Submitting an amendment atomically marks original note as isAmended and links note IDs', async () => {
      // 1. Submit original note
      const original = await submitClinicalNoteHandler({
        data: {
          patientId: patientA,
          patientName: 'Alice Patient',
          noteType: 'progressNote',
          rawTranscription: 'Original assessment: Hb 11.2.',
          nurseReviewedTranscript: 'Original assessment: Hb 11.2.',
          clinicalSummary: 'Original assessment completed.',
        },
        auth: { uid: nurseA },
      } as any);

      // 2. Submit amendment
      const amendment = await submitClinicalNoteHandler({
        data: {
          patientId: patientA,
          patientName: 'Alice Patient',
          noteType: 'progressNote',
          rawTranscription: 'Amendment correction: Hb was 9.8, not 11.2.',
          nurseReviewedTranscript: 'Amendment correction: Hb was 9.8, not 11.2.',
          clinicalSummary: 'Corrected lab value for Hb.',
          amendmentOf: original.noteId,
          amendmentReason: 'Correction of laboratory value based on official lab release',
        },
        auth: { uid: nurseA },
      } as any);

      expect(amendment.success).toBe(true);

      // Verify amendment document
      const amendmentSnap = await db.collection('patients').doc(patientA).collection('clinical_notes').doc(amendment.noteId).get();
      expect(amendmentSnap.data()!.amendmentOf).toBe(original.noteId);
      expect(amendmentSnap.data()!.amendmentReason).toBe('Correction of laboratory value based on official lab release');
      expect(amendmentSnap.data()!.isAmended).toBe(false);

      // Verify original note was updated with isAmended: true and amendedByNoteId
      const originalSnap = await db.collection('patients').doc(patientA).collection('clinical_notes').doc(original.noteId).get();
      expect(originalSnap.data()!.isAmended).toBe(true);
      expect(originalSnap.data()!.amendedByNoteId).toBe(amendment.noteId);
    });
  });

  // ── 3. DOCTOR REVIEW & SIGN-OFF ──
  describe('reviewClinicalNote', () => {
    test('Non-doctor caller cannot sign off on clinical note', async () => {
      const note = await submitClinicalNoteHandler({
        data: {
          patientId: patientA,
          rawTranscription: 'Patient vitals stable',
          nurseReviewedTranscript: 'Patient vitals stable',
          clinicalSummary: 'Stable',
        },
        auth: { uid: nurseA },
      } as any);

      await expect(
        reviewClinicalNoteHandler({
          data: { patientId: patientA, noteId: note.noteId },
          auth: { uid: nurseA }, // Nurse cannot sign off
        } as any)
      ).rejects.toMatchObject({ code: 'permission-denied' });
    });

    test('Attending doctor successfully signs off without altering clinical observations', async () => {
      const note = await submitClinicalNoteHandler({
        data: {
          patientId: patientA,
          rawTranscription: 'Patient experienced mild chills during infusion.',
          nurseReviewedTranscript: 'Patient experienced mild chills during chemotherapy infusion.',
          clinicalSummary: 'Mild infusion reaction.',
          supportedExtractedSymptoms: { chillsOrSweats: true },
          narrativeObservations: 'Temp elevated to 37.8 C.',
          careInterventions: 'Infusion rate decreased.',
        },
        auth: { uid: nurseA },
      } as any);

      const reviewRes = await reviewClinicalNoteHandler({
        data: {
          patientId: patientA,
          noteId: note.noteId,
          reviewNotes: 'Reviewed infusion reaction; ordered premedication for next cycle.',
        },
        auth: { uid: doctorA },
      } as any);

      expect(reviewRes.success).toBe(true);
      expect(reviewRes.status).toBe('REVIEWED');

      const reviewedSnap = await db.collection('patients').doc(patientA).collection('clinical_notes').doc(note.noteId).get();
      const reviewedData = reviewedSnap.data()!;

      expect(reviewedData.status).toBe('REVIEWED');
      expect(reviewedData.reviewedByUid).toBe(doctorA);
      expect(reviewedData.reviewedByName).toBe('Dr. House');
      expect(reviewedData.reviewedAt).toBeDefined();
      expect(reviewedData.doctorReviewNotes).toBe('Reviewed infusion reaction; ordered premedication for next cycle.');

      // Verify clinical observations and fileHash were NOT mutated
      expect(reviewedData.clinicalSummary).toBe('Mild infusion reaction.');
      expect(reviewedData.supportedExtractedSymptoms).toEqual({ chillsOrSweats: true });
      expect(reviewedData.fileHash).toBe(note.fileHash);
    });

    test('Foreign hospital doctor is rejected by hospital tenancy check', async () => {
      const note = await submitClinicalNoteHandler({
        data: {
          patientId: patientA,
          rawTranscription: 'Testing hospital boundary',
          nurseReviewedTranscript: 'Testing hospital boundary',
          clinicalSummary: 'Hospital isolation test',
        },
        auth: { uid: nurseA },
      } as any);

      await expect(
        reviewClinicalNoteHandler({
          data: { patientId: patientA, noteId: note.noteId },
          auth: { uid: doctorB }, // Hospital B doctor
        } as any)
      ).rejects.toMatchObject({ code: 'permission-denied' });
    });
  });

  // ── 4. PHASE 3C.1 SECURITY & INTEGRITY HARDENING ──
  describe('Phase 3C.1 Security & Amendment Integrity Checks', () => {
    test('Revoking nurse assignment immediately denies subsequent note operations', async () => {
      // Revoke assignment for nurseA
      await db.collection('nurse_patient_assignments').doc(`${nurseA}_${patientA}`).update({
        status: 'revoked',
        revokedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      await expect(
        saveClinicalNoteDraftHandler({
          data: { patientId: patientA, rawTranscription: 'Post-revocation attempt' },
          auth: { uid: nurseA },
        } as any)
      ).rejects.toMatchObject({ code: 'permission-denied' });

      await expect(
        submitClinicalNoteHandler({
          data: { patientId: patientA, rawTranscription: 'Post-revocation submit' },
          auth: { uid: nurseA },
        } as any)
      ).rejects.toMatchObject({ code: 'permission-denied' });

      // Restore assignment for subsequent tests
      await db.collection('nurse_patient_assignments').doc(`${nurseA}_${patientA}`).update({
        status: 'active',
      });
    });

    test('Nurse cannot author clinical note for patient in another hospital (tenancy check)', async () => {
      await expect(
        submitClinicalNoteHandler({
          data: { patientId: patientForeign, rawTranscription: 'Cross hospital write' },
          auth: { uid: nurseA },
        } as any)
      ).rejects.toMatchObject({ code: 'permission-denied' });
    });

    test('Submission for non-existent patient fails with not-found', async () => {
      await expect(
        submitClinicalNoteHandler({
          data: { patientId: 'pat_does_not_exist_999', rawTranscription: 'Ghost patient' },
          auth: { uid: nurseA },
        } as any)
      ).rejects.toMatchObject({ code: 'not-found' });
    });

    test('Attempted author impersonation in payload is ignored and authorUid is strictly bound to caller auth.uid', async () => {
      const res = await submitClinicalNoteHandler({
        data: {
          patientId: patientA,
          authorUid: 'malicious_impersonated_uid',
          authorName: 'Dr. Fake Attending',
          authorRole: 'doctor',
          rawTranscription: 'Impersonation test',
          clinicalSummary: 'Impersonation summary',
        },
        auth: { uid: nurseA },
      } as any);

      const noteSnap = await db.collection('patients').doc(patientA).collection('clinical_notes').doc(res.noteId).get();
      const noteData = noteSnap.data()!;
      expect(noteData.authorUid).toBe(nurseA); // Must be authentic caller
      expect(noteData.authorRole).toBe('nurse'); // Must be authentic role
      expect(noteData.authorName).toBe('Nurse Sara'); // Must be authentic name
    });

    test('Amending a note without amendmentReason is rejected with invalid-argument', async () => {
      const orig = await submitClinicalNoteHandler({
        data: {
          patientId: patientA,
          rawTranscription: 'Base note for amendmentReason test',
          clinicalSummary: 'Base summary',
        },
        auth: { uid: nurseA },
      } as any);

      await expect(
        submitClinicalNoteHandler({
          data: {
            patientId: patientA,
            rawTranscription: 'Amended without reason',
            amendmentOf: orig.noteId,
            // missing amendmentReason
          },
          auth: { uid: nurseA },
        } as any)
      ).rejects.toMatchObject({ code: 'invalid-argument' });
    });

    test('Amending note itself (cyclic reference) is rejected with invalid-argument', async () => {
      await expect(
        submitClinicalNoteHandler({
          data: {
            noteId: 'self_amend_note',
            patientId: patientA,
            rawTranscription: 'Self amending note',
            amendmentOf: 'self_amend_note',
            amendmentReason: 'Self reference test',
          },
          auth: { uid: nurseA },
        } as any)
      ).rejects.toMatchObject({ code: 'invalid-argument' });
    });

    test('Amending a DRAFT note is rejected with failed-precondition', async () => {
      const draft = await saveClinicalNoteDraftHandler({
        data: {
          patientId: patientA,
          rawTranscription: 'Draft note cannot be amended',
        },
        auth: { uid: nurseA },
      } as any);

      await expect(
        submitClinicalNoteHandler({
          data: {
            patientId: patientA,
            rawTranscription: 'Attempting to amend draft',
            amendmentOf: draft.noteId,
            amendmentReason: 'Invalid draft amendment',
          },
          auth: { uid: nurseA },
        } as any)
      ).rejects.toMatchObject({ code: 'failed-precondition' });
    });

    test('Amending an ALREADY amended note is rejected with failed-precondition', async () => {
      // 1. Base note
      const base = await submitClinicalNoteHandler({
        data: {
          patientId: patientA,
          rawTranscription: 'Original note for double amend',
        },
        auth: { uid: nurseA },
      } as any);

      // 2. First amendment
      await submitClinicalNoteHandler({
        data: {
          patientId: patientA,
          rawTranscription: 'First amendment',
          amendmentOf: base.noteId,
          amendmentReason: 'First revision',
        },
        auth: { uid: nurseA },
      } as any);

      // 3. Second amendment targeting the same base note (branching/invalid amendment)
      await expect(
        submitClinicalNoteHandler({
          data: {
            patientId: patientA,
            rawTranscription: 'Second amendment targeting base',
            amendmentOf: base.noteId,
            amendmentReason: 'Conflicting revision',
          },
          auth: { uid: nurseA },
        } as any)
      ).rejects.toMatchObject({ code: 'failed-precondition' });
    });

    test('Amendment with mismatched patientId is rejected with invalid-argument', async () => {
      const orig = await submitClinicalNoteHandler({
        data: {
          patientId: patientA,
          rawTranscription: 'Patient A note',
        },
        auth: { uid: nurseA },
      } as any);

      // Temporarily give nurseA access to patientForeign to test patient mismatch logic
      try {
        await db.collection('nurse_patient_assignments').doc(`${nurseA}_${patientForeign}`).set({
          nurseId: nurseA,
          patientId: patientForeign,
          status: 'active',
        });
        await db.collection('users').doc(nurseA).update({ hospitalId: hospB });

        await expect(
          submitClinicalNoteHandler({
            data: {
              patientId: patientForeign, // Wrong patient!
              rawTranscription: 'Attempting to amend across patients',
              amendmentOf: orig.noteId,
              amendmentReason: 'Mismatched patient test',
            },
            auth: { uid: nurseA },
          } as any)
        ).rejects.toMatchObject({
          code: expect.stringMatching(/not-found|invalid-argument/),
        });
      } finally {
        // Clean up temporary grant
        await db.collection('users').doc(nurseA).update({ hospitalId: hospA });
        await db.collection('nurse_patient_assignments').doc(`${nurseA}_${patientForeign}`).delete();
      }
    });

    test('Idempotent submission retry with identical payload returns success without duplicating or throwing', async () => {
      const notePayload = {
        patientId: patientA,
        patientName: 'Alice Patient',
        noteType: 'progressNote',
        rawTranscription: 'Idempotency test transcription',
        nurseReviewedTranscript: 'Idempotency test transcription',
        clinicalSummary: 'Idempotency summary',
      };

      const firstSub = await submitClinicalNoteHandler({
        data: notePayload,
        auth: { uid: nurseA },
      } as any);

      expect(firstSub.success).toBe(true);

      // Second submission with exact same noteId and payload
      const secondSub = await submitClinicalNoteHandler({
        data: {
          ...notePayload,
          noteId: firstSub.noteId,
        },
        auth: { uid: nurseA },
      } as any);

      expect(secondSub.success).toBe(true);
      expect(secondSub.noteId).toBe(firstSub.noteId);
      expect(secondSub.fileHash).toBe(firstSub.fileHash);
    });
  });
});
