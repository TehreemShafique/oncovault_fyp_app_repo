// test/screens/nurse/patient_treatment_plan_screen_test.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncovault/screens/nurse/patient_treatment_plan_screen.dart';
import 'package:oncovault/models/treatment_plan_model.dart';
import 'package:oncovault/models/patient_profile_model.dart';
import 'package:oncovault/models/blood_cancer_ehr_model.dart';
import 'package:oncovault/models/medical_record_model.dart';
import 'package:oncovault/services/treatment_tracking_service.dart';
import 'package:oncovault/services/doctor_service.dart';
import 'package:oncovault/services/fabric_gateway_service.dart';

class FakeDoctorService extends DoctorService {
  final PatientProfile? profileToReturn;
  final bool shouldThrow;

  FakeDoctorService({this.profileToReturn, this.shouldThrow = false});

  @override
  Future<PatientProfile?> fetchPatient(String patientId) async {
    if (shouldThrow) {
      return Future.error(Exception('Permission denied: Care assignment revoked or unauthorized.'));
    }
    return profileToReturn;
  }

  @override
  Stream<List<BloodCancerEhrModel>> watchBloodCancerEhrs(String patientId) {
    return Stream.value([]);
  }

  @override
  Stream<List<MedicalRecordModel>> watchPatientRecords(String patientId) {
    return Stream.value([]);
  }
}

class FakeTreatmentTrackingService extends TreatmentTrackingService {
  final List<TreatmentPlanModel> plans;
  final Map<String, List<TreatmentTaskModel>> tasksByPlan;
  final Map<String, List<TreatmentProgressUpdateModel>> progressByPlan;

  final Future<Map<String, dynamic>> Function({
    required String patientId,
    required String planId,
    required String taskId,
    String? executionRemarks,
  })? onCompleteTask;

  final Future<FabricProofInfo?> Function({
    required String patientId,
    required String planId,
    required String taskId,
  })? onVerifyLedger;

  FakeTreatmentTrackingService({
    this.plans = const [],
    this.tasksByPlan = const {},
    this.progressByPlan = const {},
    this.onCompleteTask,
    this.onVerifyLedger,
  });

  @override
  Stream<List<TreatmentPlanModel>> watchPatientTreatmentPlans(String patientId) {
    return Stream.value(plans);
  }

  @override
  Stream<List<TreatmentTaskModel>> watchTreatmentTasks(String patientId, String planId) {
    return Stream.value(tasksByPlan[planId] ?? []);
  }

  @override
  Stream<List<TreatmentProgressUpdateModel>> watchTreatmentProgressUpdates(
    String patientId,
    String planId,
  ) {
    return Stream.value(progressByPlan[planId] ?? []);
  }

  @override
  Stream<TreatmentPlanIntegrityStatus?> watchTreatmentPlanIntegrityStatus(
    String patientId,
    String planId,
  ) {
    final matching = plans.where((p) => p.planId == planId);
    if (matching.isEmpty) return Stream.value(null);
    final plan = matching.first;
    return Stream.value(TreatmentPlanIntegrityStatus(
      planId: plan.planId,
      patientId: plan.patientId,
      fabricTxId: plan.fabricTxId,
      fabricStatus: plan.fabricStatus,
      fabricTimestamp: plan.fabricTimestamp,
      isAnchored: plan.fabricTxId != null && plan.fabricTxId!.isNotEmpty,
      totalTasks: plan.totalTasks,
      completedTasks: plan.completedTasks,
    ));
  }

  @override
  Future<Map<String, dynamic>> completeTreatmentTask({
    required String patientId,
    required String planId,
    required String taskId,
    String? executionRemarks,
  }) async {
    if (onCompleteTask != null) {
      return onCompleteTask!(
        patientId: patientId,
        planId: planId,
        taskId: taskId,
        executionRemarks: executionRemarks,
      );
    }
    return {
      'taskId': taskId,
      'status': 'completed',
      'completedAt': DateTime.now().toIso8601String(),
    };
  }

  @override
  Future<FabricProofInfo?> verifyTreatmentTaskOnLedger({
    required String patientId,
    required String planId,
    required String taskId,
  }) async {
    if (onVerifyLedger != null) {
      return onVerifyLedger!(
        patientId: patientId,
        planId: planId,
        taskId: taskId,
      );
    }
    return const FabricProofInfo(
      recordId: 'task_plan-001_task-completed-2',
      sha256Hash: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      version: 1,
      txId: 'mock-fabric-tx-proof-777',
      timestamp: '2026-10-15T11:05:00.000Z',
      status: 'COMMITTED',
    );
  }
}

void main() {
  group('PatientTreatmentPlanScreen Widget Tests', () {
    late TreatmentPlanModel testPlan;
    late TreatmentTaskModel pendingTask;
    late TreatmentTaskModel completedTask;
    late TreatmentProgressUpdateModel progressUpdate;

    setUp(() {
      testPlan = TreatmentPlanModel(
        planId: 'plan-001',
        patientId: 'patient-test-1',
        doctorId: 'doc-123',
        doctorName: 'Dr. Gregory House',
        hospitalId: 'hospital-main',
        title: '7+3 Induction Protocol',
        clinicalObjectives: 'Achieve complete morphologic remission within 28 days.',
        status: TreatmentPlanStatus.active,
        startDate: DateTime.utc(2026, 10, 15, 9, 0),
        totalTasks: 2,
        completedTasks: 1,
        fabricTxId: 'fabric-tx-plan-999',
        fabricStatus: 'COMMITTED',
        fabricTimestamp: '2026-10-15T10:00:00.000Z',
        createdAt: DateTime.utc(2026, 10, 15, 9, 30),
      );

      pendingTask = TreatmentTaskModel(
        taskId: 'task-pending-1',
        planId: 'plan-001',
        patientId: 'patient-test-1',
        title: 'Administer Pre-Chemo Antiemetic',
        instructions: 'Ondansetron 8mg IV piggyback over 15 minutes prior to infusion.',
        category: TreatmentTaskCategory.medication,
        status: TreatmentTaskStatus.pending,
        scheduledTime: DateTime.utc(2026, 10, 16, 8, 0),
        fabricTxId: 'fabric-tx-task-pending',
        fabricStatus: 'COMMITTED',
        createdAt: DateTime.utc(2026, 10, 15, 9, 35),
      );

      completedTask = TreatmentTaskModel(
        taskId: 'task-completed-2',
        planId: 'plan-001',
        patientId: 'patient-test-1',
        title: 'Baseline Complete Blood Count (CBC)',
        instructions: 'Draw 5mL EDTA tube from central venous catheter.',
        category: TreatmentTaskCategory.labCheck,
        status: TreatmentTaskStatus.completed,
        completedByNurseId: 'nurse-456',
        completedByNurseName: 'Nurse Sarah Jenkins',
        completedAt: DateTime.utc(2026, 10, 15, 11, 0),
        executionRemarks: 'Drawn from lumen A. Sample sent to hematology lab.',
        fabricTxId: 'fabric-tx-task-completed',
        fabricStatus: 'COMMITTED',
        fabricTimestamp: '2026-10-15T11:05:00.000Z',
        createdAt: DateTime.utc(2026, 10, 15, 9, 35),
      );

      progressUpdate = TreatmentProgressUpdateModel(
        updateId: 'prog-001',
        planId: 'plan-001',
        patientId: 'patient-test-1',
        authorUid: 'nurse-456',
        authorName: 'Nurse Sarah Jenkins',
        authorRole: 'nurse',
        clinicalSummary: 'Patient resting comfortably. Vitals monitored q2h and stable.',
        patientTolerance: 'well_tolerated',
        factualObservations: 'No nausea, vomiting, or acute hypersensitivity observed.',
        fabricTxId: 'fabric-tx-prog-001',
        fabricStatus: 'COMMITTED',
        timestamp: DateTime.utc(2026, 10, 15, 14, 0),
      );
    });

    testWidgets('renders plan header, objectives, Fabric integrity card, and tab bar', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeService = FakeTreatmentTrackingService(
        plans: [testPlan],
        tasksByPlan: {'plan-001': [pendingTask, completedTask]},
        progressByPlan: {'plan-001': [progressUpdate]},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: PatientTreatmentPlanScreen(
            patientId: 'patient-test-1',
            patientName: 'Jane Smith',
            service: fakeService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Header
      expect(find.text('Treatment Progress Tracking'), findsOneWidget);
      expect(find.text('Patient: Jane Smith'), findsOneWidget);

      // Plan Details
      expect(find.text('7+3 Induction Protocol'), findsOneWidget);
      expect(find.text('Attending: Dr. Gregory House'), findsOneWidget);
      expect(find.text('Achieve complete morphologic remission within 28 days.'), findsOneWidget);

      // Blockchain integrity card
      expect(find.text('Hyperledger Fabric Anchored'), findsOneWidget);

      // Tabs
      expect(find.text('Clinical Tasks'), findsOneWidget);
      expect(find.text('Progress Timeline'), findsOneWidget);
      expect(find.text('EHR Summary'), findsOneWidget);
    });

    testWidgets('displays tasks tab with pending and completed cards and filters', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeService = FakeTreatmentTrackingService(
        plans: [testPlan],
        tasksByPlan: {'plan-001': [pendingTask, completedTask]},
        progressByPlan: {'plan-001': [progressUpdate]},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: PatientTreatmentPlanScreen(
            patientId: 'patient-test-1',
            patientName: 'Jane Smith',
            service: fakeService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Pending task
      expect(find.text('Administer Pre-Chemo Antiemetic'), findsOneWidget);
      expect(find.text('Execute Task'), findsOneWidget);

      // Completed task
      expect(find.text('Baseline Complete Blood Count (CBC)'), findsOneWidget);
      expect(find.text('Completed by: Nurse Sarah Jenkins'), findsOneWidget);
      expect(find.text('Remarks: Drawn from lumen A. Sample sent to hematology lab.'), findsOneWidget);

      // Filter: tap "Pending (1)" chip
      await tester.tap(find.text('Pending (1)'));
      await tester.pumpAndSettle();

      expect(find.text('Administer Pre-Chemo Antiemetic'), findsOneWidget);
      expect(find.text('Baseline Complete Blood Count (CBC)'), findsNothing);

      // Filter: tap "Completed (1)" chip
      await tester.tap(find.text('Completed (1)'));
      await tester.pumpAndSettle();

      expect(find.text('Administer Pre-Chemo Antiemetic'), findsNothing);
      expect(find.text('Baseline Complete Blood Count (CBC)'), findsOneWidget);
    });

    testWidgets('opens task execution dialog and successfully completes task', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      String? capturedRemarks;
      String? capturedTaskId;

      final fakeService = FakeTreatmentTrackingService(
        plans: [testPlan],
        tasksByPlan: {'plan-001': [pendingTask, completedTask]},
        progressByPlan: {'plan-001': [progressUpdate]},
        onCompleteTask: ({
          required patientId,
          required planId,
          required taskId,
          executionRemarks,
        }) async {
          capturedTaskId = taskId;
          capturedRemarks = executionRemarks;
          return {'success': true};
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: PatientTreatmentPlanScreen(
            patientId: 'patient-test-1',
            patientName: 'Jane Smith',
            service: fakeService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap "Execute Task" on pending task
      await tester.tap(find.text('Execute Task'));
      await tester.pumpAndSettle();

      // Verify Dialog opens
      expect(find.text('Confirm Task Execution'), findsOneWidget);
      expect(find.text('Administer Pre-Chemo Antiemetic'), findsAtLeastNWidgets(1));
      expect(find.byKey(const Key('taskRemarksInput')), findsOneWidget);
      expect(find.byKey(const Key('confirmTaskExecutionButton')), findsOneWidget);

      // Enter execution remarks
      await tester.enterText(
        find.byKey(const Key('taskRemarksInput')),
        'Infusion started at 08:05, completed at 08:20 without extravasation.',
      );

      // Confirm execution
      await tester.tap(find.byKey(const Key('confirmTaskExecutionButton')));
      await tester.pump(); // trigger async call

      expect(capturedTaskId, equals('task-pending-1'));
      expect(capturedRemarks, contains('Infusion started at 08:05'));

      await tester.pumpAndSettle();

      // Verify success snackbar
      expect(find.text('Task "Administer Pre-Chemo Antiemetic" completed successfully.'), findsOneWidget);
    });

    testWidgets('handles task completion error and shows error snackbar', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeService = FakeTreatmentTrackingService(
        plans: [testPlan],
        tasksByPlan: {'plan-001': [pendingTask]},
        onCompleteTask: ({
          required patientId,
          required planId,
          required taskId,
          executionRemarks,
        }) async {
          throw const TreatmentAuthorizationException('Nurse assignment revoked or inactive.');
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: PatientTreatmentPlanScreen(
            patientId: 'patient-test-1',
            patientName: 'Jane Smith',
            service: fakeService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Execute Task'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('confirmTaskExecutionButton')));
      await tester.pumpAndSettle();

      expect(find.text('Nurse assignment revoked or inactive.'), findsOneWidget);
    });

    testWidgets('ledger verification button invokes on-chain proof check', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      bool verifiedCalled = false;
      final fakeService = FakeTreatmentTrackingService(
        plans: [testPlan],
        tasksByPlan: {'plan-001': [completedTask]},
        onVerifyLedger: ({
          required patientId,
          required planId,
          required taskId,
        }) async {
          verifiedCalled = true;
          return const FabricProofInfo(
            recordId: 'task_plan-001_task-completed-2',
            sha256Hash: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
            version: 1,
            txId: 'mock-fabric-tx-proof-777',
            timestamp: '2026-10-15T11:05:00.000Z',
            status: 'COMMITTED',
          );
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: PatientTreatmentPlanScreen(
            patientId: 'patient-test-1',
            patientName: 'Jane Smith',
            service: fakeService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find ledger verification button on completed task
      final verifyButton = find.byKey(const Key('verifyLedgerButton_task-completed-2'));
      expect(verifyButton, findsOneWidget);

      await tester.tap(verifyButton);
      await tester.pumpAndSettle();

      expect(verifiedCalled, isTrue);
      expect(find.text('Ledger Verification'), findsOneWidget);
      expect(find.text('Record Status: ANCHORED & VERIFIED'), findsOneWidget);
      expect(find.textContaining('mock-fabric-tx-proof-777'), findsOneWidget);
    });

    testWidgets('timeline tab renders progress updates with tolerance badge', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeService = FakeTreatmentTrackingService(
        plans: [testPlan],
        tasksByPlan: {'plan-001': [pendingTask, completedTask]},
        progressByPlan: {'plan-001': [progressUpdate]},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: PatientTreatmentPlanScreen(
            patientId: 'patient-test-1',
            patientName: 'Jane Smith',
            service: fakeService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Timeline tab
      await tester.tap(find.text('Progress Timeline'));
      await tester.pumpAndSettle();

      expect(find.text('Patient resting comfortably. Vitals monitored q2h and stable.'), findsOneWidget);
      expect(find.text('Tolerance: WELL TOLERATED'), findsOneWidget);
      expect(find.text('Observations: No nausea, vomiting, or acute hypersensitivity observed.'), findsOneWidget);
      expect(find.text('Nurse Sarah Jenkins'), findsOneWidget);

      // Verify navigation button exists
      expect(find.byKey(const Key('recordProgressNavButton')), findsOneWidget);
    });

    testWidgets('EHR Summary tab: State 1 — renders confirmed known allergies with warning chips', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeService = FakeTreatmentTrackingService(plans: [testPlan]);
      final fakeDoctorService = FakeDoctorService(
        profileToReturn: PatientProfile(
          uid: 'patient-test-1',
          name: 'Jane Smith',
          email: 'jane@test.com',
          medicalId: 'OV-001',
          allergies: ['Penicillin', 'Sulfa'],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: PatientTreatmentPlanScreen(
            patientId: 'patient-test-1',
            patientName: 'Jane Smith',
            service: fakeService,
            doctorService: fakeDoctorService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('EHR Summary'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Documented Patient Allergies (2):'), findsOneWidget);
      expect(find.text('Penicillin'), findsOneWidget);
      expect(find.text('Sulfa'), findsOneWidget);
    });

    testWidgets('EHR Summary tab: State 2 — renders explicitly confirmed NKDA badge', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeService = FakeTreatmentTrackingService(plans: [testPlan]);
      final fakeDoctorService = FakeDoctorService(
        profileToReturn: PatientProfile(
          uid: 'patient-test-1',
          name: 'Jane Smith',
          email: 'jane@test.com',
          medicalId: 'OV-001',
          hasNoKnownAllergies: true,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: PatientTreatmentPlanScreen(
            patientId: 'patient-test-1',
            patientName: 'Jane Smith',
            service: fakeService,
            doctorService: fakeDoctorService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('EHR Summary'));
      await tester.pumpAndSettle();

      expect(find.text('Confirmed No Known Allergies (NKDA)'), findsOneWidget);
      expect(find.text('Explicitly documented in patient medical record.'), findsOneWidget);
    });

    testWidgets('EHR Summary tab: State 3 — renders not documented warning when data is missing/null', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeService = FakeTreatmentTrackingService(plans: [testPlan]);
      final fakeDoctorService = FakeDoctorService(
        profileToReturn: PatientProfile(
          uid: 'patient-test-1',
          name: 'Jane Smith',
          email: 'jane@test.com',
          medicalId: 'OV-001',
          allergies: null, // Unrecorded!
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: PatientTreatmentPlanScreen(
            patientId: 'patient-test-1',
            patientName: 'Jane Smith',
            service: fakeService,
            doctorService: fakeDoctorService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('EHR Summary'));
      await tester.pumpAndSettle();

      expect(find.text('Allergy status: Not documented'), findsOneWidget);
      expect(find.textContaining('No allergy assessment recorded.'), findsOneWidget);
      expect(find.text('No known allergies documented (NKDA)'), findsNothing);
    });

    testWidgets('EHR Summary tab: Authorization/read failure renders unverified safety warning', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeService = FakeTreatmentTrackingService(plans: [testPlan]);
      final fakeDoctorService = FakeDoctorService(shouldThrow: true);

      await tester.pumpWidget(
        MaterialApp(
          home: PatientTreatmentPlanScreen(
            patientId: 'patient-test-1',
            patientName: 'Jane Smith',
            service: fakeService,
            doctorService: fakeDoctorService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('EHR Summary'));
      await tester.pumpAndSettle();

      expect(find.text('Allergy status: Not documented'), findsOneWidget);
      expect(find.text('No known allergies documented (NKDA)'), findsNothing);
    });
  });
}
