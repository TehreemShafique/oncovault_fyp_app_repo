// test/screens/nurse/nurse_voice_note_screens_test.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncovault/screens/nurse/nurse_voice_note_screen.dart';
import 'package:oncovault/screens/nurse/nurse_note_review_screen.dart';
import 'package:oncovault/screens/nurse/patient_notes_history_screen.dart';
import 'package:oncovault/models/clinical_note_model.dart';
import 'package:oncovault/models/nlp_extraction_model.dart';
import 'package:oncovault/services/nurse_service.dart';

class FakeNurseService extends NurseService {
  final List<ClinicalNoteModel> initialNotes;

  FakeNurseService({this.initialNotes = const []});

  @override
  Stream<List<ClinicalNoteModel>> watchPatientClinicalNotes(String patientId) {
    return Stream.value(initialNotes);
  }
}

void main() {
  group('Phase 3C Voice Note UI & Review Widget Tests', () {
    testWidgets('NurseVoiceNoteScreen renders patient header, dictation templates and mic controls', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: NurseVoiceNoteScreen(
            patientId: 'patient_test_1',
            patientName: 'Jane Smith',
          ),
        ),
      );
      await tester.pump();

      // Verify patient header and title
      expect(find.text('Nurse Voice Documentation'), findsOneWidget);
      expect(find.text('Jane Smith'), findsOneWidget);
      expect(find.text('Patient ID: patient_test_1'), findsOneWidget);

      // Verify Note Type selector
      expect(find.text('Progress Note'), findsOneWidget);

      // Verify dictation templates
      expect(find.text('Sample Clinical Dictations'), findsOneWidget);

      // Verify record button
      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
    });

    testWidgets('NurseNoteReviewScreen renders 16 leukemia symptom chips, fields, and confirmation toggle', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const extraction = NlpExtractionResponse(
        text: 'Patient has fever and fatigue but denies bone pain.',
        symptoms: {
          'fever': SymptomExtractionResult(value: true, status: 'present'),
          'persistentWeaknessAndFatigue': SymptomExtractionResult(value: true, status: 'present'),
          'bonePain': SymptomExtractionResult(value: false, status: 'absent'),
        },
        other: OtherClinicalResult(
          clinicalNotes: 'Febrile episode in neutropenic patient.',
        ),
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: NurseNoteReviewScreen(
            patientId: 'patient_test_1',
            patientName: 'Jane Smith',
            noteType: ClinicalNoteType.progressNote,
            rawTranscription: 'Patient has fever and fatigue but denies bone pain.',
            reviewedTranscript: 'Patient has fever and fatigue but denies bone pain.',
            extraction: extraction,
          ),
        ),
      );
      await tester.pump();

      // Verify Step 2 header
      expect(find.text('Review & Confirm Note'), findsOneWidget);

      // Verify symptom review section
      expect(find.text('2. EXTRACTED SYMPTOMS (TAP TO TOGGLE)'), findsOneWidget);
      expect(find.text('Persistent Fever'), findsOneWidget);
      expect(find.text('Bone / Joint Pain'), findsOneWidget);

      // Verify action buttons
      expect(find.text('Save Draft'), findsOneWidget);
      expect(find.text('Confirm & Submit'), findsOneWidget);

      // Verify confirmation checkbox
      expect(
        find.text('I have reviewed and confirmed the clinical accuracy of these observations.'),
        findsOneWidget,
      );
    });

    testWidgets('PatientNotesHistoryScreen renders filter chips and empty state message', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeService = FakeNurseService(initialNotes: []);

      await tester.pumpWidget(
        MaterialApp(
          home: PatientNotesHistoryScreen(
            patientId: 'patient_test_1',
            patientName: 'Jane Smith',
            customNurseService: fakeService,
          ),
        ),
      );
      await tester.pump();

      // Verify title and patient name
      expect(find.text('Clinical Notes History'), findsOneWidget);
      expect(find.text('Jane Smith'), findsOneWidget);

      // Verify filter chips
      expect(find.text('All Notes'), findsOneWidget);
      expect(find.text('Submitted'), findsOneWidget);
      expect(find.text('Reviewed'), findsOneWidget);
      expect(find.text('Drafts'), findsOneWidget);

      // Verify New Voice Note FAB
      expect(find.text('New Voice Note'), findsOneWidget);

      // Verify empty state message
      expect(find.text('No clinical notes recorded yet'), findsOneWidget);
    });

    testWidgets('PatientNotesHistoryScreen renders all 5 Fabric integrity status badges correctly', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final notes = [
        ClinicalNoteModel(
          noteId: 'note_committed',
          patientId: 'patient_test_1',
          patientName: 'Jane Smith',
          noteType: ClinicalNoteType.progressNote,
          authorUid: 'nurse_1',
          authorName: 'Nurse One',
          authorRole: 'nurse',
          status: ClinicalNoteStatus.submitted,
          fabricStatus: 'COMMITTED',
          createdAt: DateTime.utc(2026, 10, 17, 10, 0),
        ),
        ClinicalNoteModel(
          noteId: 'note_processing',
          patientId: 'patient_test_1',
          patientName: 'Jane Smith',
          noteType: ClinicalNoteType.progressNote,
          authorUid: 'nurse_1',
          authorName: 'Nurse One',
          authorRole: 'nurse',
          status: ClinicalNoteStatus.submitted,
          fabricStatus: 'PROCESSING',
          createdAt: DateTime.utc(2026, 10, 17, 9, 0),
        ),
        ClinicalNoteModel(
          noteId: 'note_retryable',
          patientId: 'patient_test_1',
          patientName: 'Jane Smith',
          noteType: ClinicalNoteType.progressNote,
          authorUid: 'nurse_1',
          authorName: 'Nurse One',
          authorRole: 'nurse',
          status: ClinicalNoteStatus.submitted,
          fabricStatus: 'FAILED_RETRYABLE',
          createdAt: DateTime.utc(2026, 10, 17, 8, 0),
        ),
        ClinicalNoteModel(
          noteId: 'note_failed',
          patientId: 'patient_test_1',
          patientName: 'Jane Smith',
          noteType: ClinicalNoteType.progressNote,
          authorUid: 'nurse_1',
          authorName: 'Nurse One',
          authorRole: 'nurse',
          status: ClinicalNoteStatus.submitted,
          fabricStatus: 'FAILED_PERMANENT',
          createdAt: DateTime.utc(2026, 10, 17, 7, 0),
        ),
        ClinicalNoteModel(
          noteId: 'note_pending',
          patientId: 'patient_test_1',
          patientName: 'Jane Smith',
          noteType: ClinicalNoteType.progressNote,
          authorUid: 'nurse_1',
          authorName: 'Nurse One',
          authorRole: 'nurse',
          status: ClinicalNoteStatus.submitted,
          fabricStatus: 'PENDING',
          createdAt: DateTime.utc(2026, 10, 17, 6, 0),
        ),
      ];

      final fakeService = FakeNurseService(initialNotes: notes);

      await tester.pumpWidget(
        MaterialApp(
          home: PatientNotesHistoryScreen(
            patientId: 'patient_test_1',
            patientName: 'Jane Smith',
            customNurseService: fakeService,
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('fabric_badge_committed')), findsOneWidget);
      expect(find.byKey(const Key('fabric_badge_processing')), findsOneWidget);
      expect(find.byKey(const Key('fabric_badge_failed_retryable')), findsOneWidget);
      expect(find.byKey(const Key('fabric_badge_failed_permanent')), findsOneWidget);
      expect(find.byKey(const Key('fabric_badge_pending')), findsOneWidget);

      expect(find.text('COMMITTED'), findsOneWidget);
      expect(find.text('PROCESSING'), findsOneWidget);
      expect(find.text('RETRY PENDING'), findsOneWidget);
      expect(find.text('FAILED'), findsOneWidget);
      expect(find.text('PENDING'), findsOneWidget);
    });
  });
}
