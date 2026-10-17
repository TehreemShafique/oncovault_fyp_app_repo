// test/screens/nurse/record_treatment_progress_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncovault/screens/nurse/record_treatment_progress_screen.dart';
import 'package:oncovault/services/treatment_tracking_service.dart';

class MockTreatmentTrackingService extends TreatmentTrackingService {
  final Future<Map<String, dynamic>> Function({
    required String patientId,
    required String planId,
    required String clinicalSummary,
    String? updateId,
    String? patientTolerance,
    String? factualObservations,
  })? onRecordProgress;

  MockTreatmentTrackingService({this.onRecordProgress});

  @override
  Future<Map<String, dynamic>> recordTreatmentProgressUpdate({
    required String patientId,
    required String planId,
    required String clinicalSummary,
    String? updateId,
    String? patientTolerance,
    String? factualObservations,
  }) async {
    if (onRecordProgress != null) {
      return onRecordProgress!(
        patientId: patientId,
        planId: planId,
        clinicalSummary: clinicalSummary,
        updateId: updateId,
        patientTolerance: patientTolerance,
        factualObservations: factualObservations,
      );
    }
    return {
      'updateId': 'mock-upd-1',
      'hash': 'mock-hash-1',
      'recordedAt': DateTime.now().toIso8601String(),
    };
  }
}

void main() {
  group('RecordTreatmentProgressScreen Widget Tests', () {
    testWidgets('renders all form fields, labels, and submit button', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: RecordTreatmentProgressScreen(
            patientId: 'patient-123',
            patientName: 'Jane Smith',
            planId: 'plan-456',
            planTitle: 'Consolidation Phase A',
            service: MockTreatmentTrackingService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Record Progress Update'), findsOneWidget);
      expect(find.text('Jane Smith'), findsOneWidget);
      expect(find.text('Target Treatment Plan'), findsOneWidget);
      expect(find.text('Consolidation Phase A'), findsOneWidget);
      expect(find.byKey(const Key('progressSummaryField')), findsOneWidget);
      expect(find.byKey(const Key('patientToleranceDropdown')), findsOneWidget);
      expect(find.byKey(const Key('factualObservationsField')), findsOneWidget);
      expect(find.byKey(const Key('submitProgressButton')), findsOneWidget);
    });

    testWidgets('blocks submission when clinical summary is empty or < 5 characters', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      bool serviceCalled = false;
      final mockService = MockTreatmentTrackingService(
        onRecordProgress: ({
          required patientId,
          required planId,
          required clinicalSummary,
          updateId,
          patientTolerance,
          factualObservations,
        }) async {
          serviceCalled = true;
          return {};
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RecordTreatmentProgressScreen(
            patientId: 'patient-123',
            patientName: 'Jane Smith',
            planId: 'plan-456',
            planTitle: 'Consolidation Phase A',
            service: mockService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap submit with empty summary
      await tester.tap(find.byKey(const Key('submitProgressButton')));
      await tester.pumpAndSettle();

      expect(find.text('Please enter a clinical progress summary.'), findsOneWidget);
      expect(serviceCalled, isFalse);

      // Enter 3 chars (less than 5)
      await tester.enterText(find.byKey(const Key('progressSummaryField')), 'Good');
      await tester.tap(find.byKey(const Key('submitProgressButton')));
      await tester.pumpAndSettle();

      expect(find.text('Summary must be at least 5 characters.'), findsOneWidget);
      expect(serviceCalled, isFalse);
    });

    testWidgets('successfully submits progress with tolerance and observations', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      String? capturedSummary;
      String? capturedTolerance;
      String? capturedObservations;

      final mockService = MockTreatmentTrackingService(
        onRecordProgress: ({
          required patientId,
          required planId,
          required clinicalSummary,
          updateId,
          patientTolerance,
          factualObservations,
        }) async {
          capturedSummary = clinicalSummary;
          capturedTolerance = patientTolerance;
          capturedObservations = factualObservations;
          return {
            'updateId': 'prog-xyz',
            'hash': 'abc123hash',
            'recordedAt': DateTime.now().toIso8601String(),
          };
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RecordTreatmentProgressScreen(
            patientId: 'patient-123',
            patientName: 'Jane Smith',
            planId: 'plan-456',
            planTitle: 'Consolidation Phase A',
            service: mockService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter summary
      await tester.enterText(
        find.byKey(const Key('progressSummaryField')),
        'Patient tolerated high-dose cytarabine cycle without immediate adverse reaction.',
      );

      // Select tolerance from dropdown
      await tester.tap(find.byKey(const Key('patientToleranceDropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Well Tolerated').last);
      await tester.pumpAndSettle();

      // Enter factual observations
      await tester.enterText(
        find.byKey(const Key('factualObservationsField')),
        'Vital signs stable: BP 118/76, HR 72, Afebrile. IV access patent.',
      );

      // Submit
      await tester.tap(find.byKey(const Key('submitProgressButton')));
      await tester.pump(); // Start async call

      expect(capturedSummary, contains('high-dose cytarabine'));
      expect(capturedTolerance, equals('well_tolerated'));
      expect(capturedObservations, contains('BP 118/76'));

      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Treatment progress update recorded successfully.'), findsOneWidget);
    });

    testWidgets('displays error snackbar when service throws TreatmentPlanException', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockService = MockTreatmentTrackingService(
        onRecordProgress: ({
          required patientId,
          required planId,
          required clinicalSummary,
          updateId,
          patientTolerance,
          factualObservations,
        }) async {
          throw const TreatmentAuthorizationException('Nurse is not actively assigned to this patient.');
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RecordTreatmentProgressScreen(
            patientId: 'patient-123',
            patientName: 'Jane Smith',
            planId: 'plan-456',
            planTitle: 'Consolidation Phase A',
            service: mockService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('progressSummaryField')),
        'Patient report after morning rounds.',
      );

      await tester.tap(find.byKey(const Key('submitProgressButton')));
      await tester.pumpAndSettle();

      expect(find.text('Nurse is not actively assigned to this patient.'), findsOneWidget);
    });
  });
}
