// test/services/clinical_notes_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:oncovault/services/nurse_service.dart';
import 'package:oncovault/services/doctor_service.dart';

void main() {
  group('NurseService and DoctorService Clinical Notes Integration Hooks', () {
    test('NurseService.saveClinicalNoteDraft invokes custom callable hook', () async {
      Map<String, dynamic>? receivedPayload;
      final service = NurseService(
        customSaveNoteDraftCallable: (data) async {
          receivedPayload = data;
          return {
            'success': true,
            'noteId': 'note_draft_1',
            'status': 'DRAFT',
          };
        },
      );

      final result = await service.saveClinicalNoteDraft({
        'patientId': 'pat_10',
        'rawTranscription': 'Nurse draft text',
        'clinicalSummary': 'Draft summary',
      });

      expect(result['success'], true);
      expect(result['noteId'], 'note_draft_1');
      expect(receivedPayload?['patientId'], 'pat_10');
      expect(receivedPayload?['rawTranscription'], 'Nurse draft text');
    });

    test('NurseService.submitClinicalNote invokes custom callable hook', () async {
      Map<String, dynamic>? receivedPayload;
      final service = NurseService(
        customSubmitNoteCallable: (data) async {
          receivedPayload = data;
          return {
            'success': true,
            'noteId': 'note_sub_1',
            'status': 'SUBMITTED',
            'fileHash': 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
          };
        },
      );

      final result = await service.submitClinicalNote({
        'patientId': 'pat_10',
        'patientName': 'Alice',
        'noteType': 'progressNote',
        'nurseReviewedTranscript': 'Finalized transcript',
        'clinicalSummary': 'Finalized summary',
      });

      expect(result['success'], true);
      expect(result['status'], 'SUBMITTED');
      expect(result['fileHash'], isNotEmpty);
      expect(receivedPayload?['patientName'], 'Alice');
    });

    test('DoctorService.reviewClinicalNote invokes custom callable hook', () async {
      String? reviewedPatientId;
      String? reviewedNoteId;
      String? doctorNotes;

      final service = DoctorService(
        reviewClinicalNoteCallable: ({
          required String patientId,
          required String noteId,
          String? reviewNotes,
        }) async {
          reviewedPatientId = patientId;
          reviewedNoteId = noteId;
          doctorNotes = reviewNotes;
          return {
            'success': true,
            'noteId': noteId,
            'status': 'REVIEWED',
          };
        },
      );

      final result = await service.reviewClinicalNote(
        patientId: 'pat_10',
        noteId: 'note_sub_1',
        reviewNotes: 'Reviewed and concurred with nursing plan.',
      );

      expect(result['success'], true);
      expect(result['status'], 'REVIEWED');
      expect(reviewedPatientId, 'pat_10');
      expect(reviewedNoteId, 'note_sub_1');
      expect(doctorNotes, 'Reviewed and concurred with nursing plan.');
    });
  });
}
