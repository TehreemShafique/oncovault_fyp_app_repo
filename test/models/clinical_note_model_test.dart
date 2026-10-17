// test/models/clinical_note_model_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:oncovault/models/clinical_note_model.dart';

void main() {
  group('ClinicalNoteModel Unit Tests', () {
    test('computes deterministic canonical SHA-256 hash', () {
      final note1 = ClinicalNoteModel(
        noteId: 'note_123',
        patientId: 'patient_456',
        patientName: 'Jane Doe',
        noteType: ClinicalNoteType.progressNote,
        authorUid: 'nurse_789',
        authorName: 'Nurse Bob',
        authorRole: 'nurse',
        hospitalId: 'HOSP_01',
        rawTranscription: 'Patient reported fatigue.',
        nurseReviewedTranscript: 'Patient reported severe fatigue and fever.',
        clinicalSummary: 'Leukemia follow-up note.',
        supportedExtractedSymptoms: {'fatigue': true, 'fever': true},
        narrativeObservations: 'Pale conjunctiva.',
        careInterventions: 'IV hydration started.',
        treatmentResponseNarrative: 'Responding well.',
        status: ClinicalNoteStatus.submitted,
        createdAt: DateTime.utc(2026, 10, 17, 10, 0, 0),
        submittedAt: DateTime.utc(2026, 10, 17, 10, 5, 0),
      );

      final note2 = ClinicalNoteModel(
        noteId: 'note_123',
        patientId: 'patient_456',
        patientName: 'Jane Doe',
        noteType: ClinicalNoteType.progressNote,
        authorUid: 'nurse_789',
        authorName: 'Nurse Bob',
        authorRole: 'nurse',
        hospitalId: 'HOSP_01',
        rawTranscription: 'Patient reported fatigue.',
        nurseReviewedTranscript: 'Patient reported severe fatigue and fever.',
        clinicalSummary: 'Leukemia follow-up note.',
        supportedExtractedSymptoms: {'fatigue': true, 'fever': true},
        narrativeObservations: 'Pale conjunctiva.',
        careInterventions: 'IV hydration started.',
        treatmentResponseNarrative: 'Responding well.',
        status: ClinicalNoteStatus.submitted,
        createdAt: DateTime.utc(2026, 10, 17, 10, 0, 0),
        submittedAt: DateTime.utc(2026, 10, 17, 10, 5, 0),
      );

      final hash1 = note1.computeCanonicalHash();
      final hash2 = note2.computeCanonicalHash();

      expect(hash1.length, 64);
      expect(hash1, equals(hash2));

      // Hash changes if clinical summary changes
      final noteModified = note1.copyWith(clinicalSummary: 'Different summary');
      expect(noteModified.computeCanonicalHash(), isNot(equals(hash1)));
    });

    test('serializes to and from Map correctly', () {
      final now = DateTime.utc(2026, 10, 17, 12, 0, 0);
      final note = ClinicalNoteModel(
        noteId: 'note_abc',
        patientId: 'pat_1',
        patientName: 'John Smith',
        noteType: ClinicalNoteType.intakeNote,
        authorUid: 'nurse_1',
        authorName: 'Nurse Alice',
        authorRole: 'nurse',
        hospitalId: 'HOSP_MAIN',
        rawTranscription: 'Intake voice recording raw text',
        nurseReviewedTranscript: 'Intake voice recording reviewed text',
        clinicalSummary: 'Initial inpatient admission note.',
        supportedExtractedSymptoms: {'fever': true, 'bruising': false},
        narrativeObservations: 'Alert and oriented x3.',
        careInterventions: 'Vitals monitored every 4 hours.',
        treatmentResponseNarrative: 'Baseline established.',
        status: ClinicalNoteStatus.submitted,
        createdAt: now,
        submittedAt: now,
        reviewedAt: now,
        reviewedByUid: 'doc_1',
        reviewedByName: 'Dr. House',
        doctorReviewNotes: 'Agreed with care plan.',
        amendmentOf: 'note_orig',
        isAmended: false,
        fileHash: 'abcdef1234567890',
      );

      final map = note.toMap();
      expect(map['noteId'], 'note_abc');
      expect(map['patientId'], 'pat_1');
      expect(map['noteType'], 'intake_note');
      expect(map['status'], 'SUBMITTED');
      expect(map['doctorReviewNotes'], 'Agreed with care plan.');

      final reconstructed = ClinicalNoteModel.fromMap(map, docId: 'note_abc');
      expect(reconstructed.noteId, note.noteId);
      expect(reconstructed.patientId, note.patientId);
      expect(reconstructed.noteType, note.noteType);
      expect(reconstructed.status, note.status);
      expect(reconstructed.supportedExtractedSymptoms['fever'], true);
      expect(reconstructed.supportedExtractedSymptoms['bruising'], false);
      expect(reconstructed.doctorReviewNotes, 'Agreed with care plan.');
    });

    test('handles amendment linking properties', () {
      final now = DateTime.utc(2026, 10, 17, 10, 0, 0);
      final original = ClinicalNoteModel(
        noteId: 'note_001',
        patientId: 'pat_1',
        patientName: 'John',
        noteType: ClinicalNoteType.progressNote,
        authorUid: 'nurse_1',
        authorName: 'Nurse A',
        authorRole: 'nurse',
        hospitalId: 'HOSP_1',
        rawTranscription: 'Patient stable.',
        nurseReviewedTranscript: 'Patient stable.',
        status: ClinicalNoteStatus.submitted,
        createdAt: now,
      );

      expect(original.isAmended, false);
      expect(original.amendmentOf, isNull);

      final superseded = original.copyWith(
        isAmended: true,
        amendedByNoteId: 'note_002',
      );
      expect(superseded.isAmended, true);
      expect(superseded.amendedByNoteId, 'note_002');

      final amendment = ClinicalNoteModel(
        noteId: 'note_002',
        patientId: 'pat_1',
        patientName: 'John',
        noteType: ClinicalNoteType.progressNote,
        authorUid: 'nurse_1',
        authorName: 'Nurse A',
        authorRole: 'nurse',
        hospitalId: 'HOSP_1',
        rawTranscription: 'Correction: Patient has low platelets.',
        nurseReviewedTranscript: 'Correction: Patient has low platelets.',
        status: ClinicalNoteStatus.submitted,
        amendmentOf: 'note_001',
        amendmentReason: 'Corrected lab values after re-test.',
        createdAt: now.add(const Duration(hours: 1)),
      );

      expect(amendment.amendmentOf, 'note_001');
      expect(amendment.amendmentReason, 'Corrected lab values after re-test.');
      expect(amendment.isAmended, false);

      final amendmentMap = amendment.toMap();
      expect(amendmentMap['amendmentReason'], 'Corrected lab values after re-test.');
      final roundtrip = ClinicalNoteModel.fromMap(amendmentMap, docId: 'note_002');
      expect(roundtrip.amendmentReason, 'Corrected lab values after re-test.');

      // Changing amendmentReason changes canonical hash
      final differentReason = amendment.copyWith(amendmentReason: 'Alternative reason');
      expect(amendment.computeCanonicalHash(), isNot(equals(differentReason.computeCanonicalHash())));
    });
  });
}
