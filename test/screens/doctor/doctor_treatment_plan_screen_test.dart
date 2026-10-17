// test/screens/doctor/doctor_treatment_plan_screen_test.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncovault/screens/doctor/doctor_treatment_plan_screen.dart';
import 'package:oncovault/models/treatment_plan_model.dart';
import 'package:oncovault/services/treatment_tracking_service.dart';
import 'package:oncovault/services/fabric_gateway_service.dart';

class FakeDoctorTreatmentTrackingService extends TreatmentTrackingService {
  final List<TreatmentPlanModel> plans;
  final Map<String, List<TreatmentTaskModel>> tasksByPlan;
  final Map<String, List<TreatmentProgressUpdateModel>> progressByPlan;

  final Future<Map<String, dynamic>> Function({
    required String patientId,
    required String planId,
    required String targetStatus,
    String? statusReason,
  })? onUpdateStatus;

  final Future<FabricProofInfo?> Function({
    required String patientId,
    required String planId,
    required String taskId,
  })? onVerifyLedger;

  FakeDoctorTreatmentTrackingService({
    this.plans = const [],
    this.tasksByPlan = const {},
    this.progressByPlan = const {},
    this.onUpdateStatus,
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
  Future<Map<String, dynamic>> updateTreatmentPlanStatus({
    required String patientId,
    required String planId,
    required String targetStatus,
    String? statusReason,
  }) async {
    if (onUpdateStatus != null) {
      return onUpdateStatus!(
        patientId: patientId,
        planId: planId,
        targetStatus: targetStatus,
        statusReason: statusReason,
      );
    }
    return {
      'planId': planId,
      'status': targetStatus,
      'updatedAt': DateTime.now().toIso8601String(),
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
      recordId: 'task_patient-456_task-1',
      sha256Hash: 'sha256-mock-hash-task-999',
      version: 1,
      txId: 'tx-test-999',
      timestamp: '2026-10-17T12:00:00.000Z',
      status: 'COMMITTED',
    );
  }
}

void main() {
  late TreatmentPlanModel samplePlan;
  late List<TreatmentTaskModel> sampleTasks;
  late List<TreatmentProgressUpdateModel> sampleProgressUpdates;

  setUp(() {
    samplePlan = TreatmentPlanModel(
      planId: 'plan-101',
      patientId: 'patient-456',
      doctorId: 'doc-789',
      doctorName: 'Dr. Gregory House',
      hospitalId: 'hospital-main',
      title: 'AML Induction Protocol - 7+3 Regimen',
      clinicalObjectives: 'Induce complete morphologic remission within 28 days with bone marrow blasts < 5%.',
      status: TreatmentPlanStatus.active,
      totalTasks: 2,
      completedTasks: 1,
      startDate: DateTime.utc(2026, 10, 15, 8, 0),
      targetEndDate: DateTime.utc(2026, 11, 12, 8, 0),
      fabricTxId: 'tx-sample-plan-101',
      fabricStatus: 'COMMITTED',
      fabricTimestamp: '2026-10-15T08:05:00.000Z',
      createdAt: DateTime.utc(2026, 10, 15, 8, 0),
      updatedAt: DateTime.utc(2026, 10, 17, 10, 0),
    );

    sampleTasks = [
      TreatmentTaskModel(
        taskId: 'task-1',
        planId: 'plan-101',
        patientId: 'patient-456',
        title: 'Infuse Cytarabine 100mg/m2 IV Continuous',
        category: TreatmentTaskCategory.medication,
        instructions: 'Infuse continuously over 24 hours. Monitor infusion site and notify MD of extravasation.',
        scheduledTime: DateTime.utc(2026, 10, 17, 9, 0),
        status: TreatmentTaskStatus.completed,
        completedByNurseId: 'nurse-111',
        completedByNurseName: 'Nurse Sarah Jenkins',
        completedAt: DateTime.utc(2026, 10, 17, 9, 30),
        executionRemarks: 'Infusion completed uneventfully. Vitals stable.',
        fabricTxId: 'tx-task-1-proof',
        fabricStatus: 'COMMITTED',
        fabricTimestamp: '2026-10-17T09:35:00.000Z',
        createdAt: DateTime.utc(2026, 10, 15, 8, 0),
        updatedAt: DateTime.utc(2026, 10, 17, 9, 30),
      ),
      TreatmentTaskModel(
        taskId: 'task-2',
        planId: 'plan-101',
        patientId: 'patient-456',
        title: 'Post-chemo CBC with Differential',
        category: TreatmentTaskCategory.labCheck,
        instructions: 'Draw peripheral blood sample via PICC line for morning laboratory analysis.',
        scheduledTime: DateTime.utc(2026, 10, 18, 6, 0),
        status: TreatmentTaskStatus.pending,
        createdAt: DateTime.utc(2026, 10, 15, 8, 0),
        updatedAt: DateTime.utc(2026, 10, 15, 8, 0),
      ),
    ];

    sampleProgressUpdates = [
      TreatmentProgressUpdateModel(
        updateId: 'prog-1',
        planId: 'plan-101',
        patientId: 'patient-456',
        authorUid: 'nurse-111',
        authorName: 'Nurse Sarah Jenkins',
        authorRole: 'nurse',
        clinicalSummary: 'Patient tolerating first round of cytarabine well.',
        factualObservations: 'No nausea, fever, or bleeding observed. Vitals stable.',
        patientTolerance: 'well_tolerated',
        timestamp: DateTime.utc(2026, 10, 17, 10, 0),
        fabricTxId: 'tx-prog-1',
        fabricStatus: 'COMMITTED',
      ),
      TreatmentProgressUpdateModel(
        updateId: 'prog-2',
        planId: 'plan-101',
        patientId: 'patient-456',
        authorUid: 'doc-789',
        authorName: 'Dr. Gregory House',
        authorRole: 'doctor',
        clinicalSummary: 'Reviewed morning labs. Continue planned cytarabine dosing.',
        factualObservations: 'Platelets 45k, ANC 800. Neutropenic precautions maintained.',
        patientTolerance: 'moderate_adverse',
        timestamp: DateTime.utc(2026, 10, 17, 11, 0),
        fabricTxId: 'tx-prog-2',
        fabricStatus: 'COMMITTED',
      ),
    ];
  });

  Widget buildTestWidget({
    required TreatmentTrackingService service,
  }) {
    return MaterialApp(
      home: DoctorTreatmentPlanScreen(
        patientId: 'patient-456',
        patientName: 'Jane Smith',
        doctorId: 'doc-789',
        service: service,
      ),
    );
  }

  group('DoctorTreatmentPlanScreen Widget Tests', () {
    testWidgets('renders empty state when patient has no plans', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final service = FakeDoctorTreatmentTrackingService(plans: const []);

      await tester.pumpWidget(buildTestWidget(service: service));
      await tester.pumpAndSettle();

      expect(find.text('No Treatment Plans Established'), findsOneWidget);
      expect(find.text('Establish Treatment Plan'), findsOneWidget);
    });

    testWidgets('renders plan overview, clinical objectives, and Fabric card', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final service = FakeDoctorTreatmentTrackingService(
        plans: [samplePlan],
        tasksByPlan: {'plan-101': sampleTasks},
        progressByPlan: {'plan-101': sampleProgressUpdates},
      );

      await tester.pumpWidget(buildTestWidget(service: service));
      await tester.pumpAndSettle();

      expect(find.text('AML Induction Protocol - 7+3 Regimen'), findsOneWidget);
      expect(find.text('Induce complete morphologic remission within 28 days with bone marrow blasts < 5%.'), findsOneWidget);
      expect(find.text('Hyperledger Fabric Anchored'), findsOneWidget);
      expect(find.text('Task Execution Progress'), findsOneWidget);
      expect(find.text('1/2 (50%)'), findsOneWidget);
    });

    testWidgets('displays tasks tab with doctor instructions and completed task nurse attribution', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final service = FakeDoctorTreatmentTrackingService(
        plans: [samplePlan],
        tasksByPlan: {'plan-101': sampleTasks},
        progressByPlan: {'plan-101': sampleProgressUpdates},
      );

      await tester.pumpWidget(buildTestWidget(service: service));
      await tester.pumpAndSettle();

      // Check tasks
      expect(find.text('Infuse Cytarabine 100mg/m2 IV Continuous'), findsOneWidget);
      expect(find.text('Post-chemo CBC with Differential'), findsOneWidget);
      expect(find.text('Infuse continuously over 24 hours. Monitor infusion site and notify MD of extravasation.'), findsOneWidget);

      // Check authoritative nurse attribution on completed task
      expect(find.text('Completed by: Nurse Sarah Jenkins'), findsOneWidget);
      expect(find.text('Remarks: Infusion completed uneventfully. Vitals stable.'), findsOneWidget);
      expect(find.text('Ledger Audit Proof'), findsOneWidget);
    });

    testWidgets('filtering tasks by status works', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final service = FakeDoctorTreatmentTrackingService(
        plans: [samplePlan],
        tasksByPlan: {'plan-101': sampleTasks},
        progressByPlan: {'plan-101': sampleProgressUpdates},
      );

      await tester.pumpWidget(buildTestWidget(service: service));
      await tester.pumpAndSettle();

      // Tap Pending filter chip
      await tester.tap(find.byKey(const Key('filterChip_pending')));
      await tester.pumpAndSettle();

      expect(find.text('Post-chemo CBC with Differential'), findsOneWidget);
      expect(find.text('Infuse Cytarabine 100mg/m2 IV Continuous'), findsNothing);

      // Tap Completed filter chip
      await tester.tap(find.byKey(const Key('filterChip_completed')));
      await tester.pumpAndSettle();

      expect(find.text('Infuse Cytarabine 100mg/m2 IV Continuous'), findsOneWidget);
      expect(find.text('Post-chemo CBC with Differential'), findsNothing);

      // Tap All filter chip
      await tester.tap(find.byKey(const Key('filterChip_all')));
      await tester.pumpAndSettle();

      expect(find.text('Infuse Cytarabine 100mg/m2 IV Continuous'), findsOneWidget);
      expect(find.text('Post-chemo CBC with Differential'), findsOneWidget);
    });

    testWidgets('opens status change dialog and can suspend plan', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      String? updatedStatus;
      String? updateReason;

      final service = FakeDoctorTreatmentTrackingService(
        plans: [samplePlan],
        tasksByPlan: {'plan-101': sampleTasks},
        progressByPlan: {'plan-101': sampleProgressUpdates},
        onUpdateStatus: ({
          required String patientId,
          required String planId,
          required String targetStatus,
          String? statusReason,
        }) async {
          updatedStatus = targetStatus;
          updateReason = statusReason;
          return {'success': true};
        },
      );

      await tester.pumpWidget(buildTestWidget(service: service));
      await tester.pumpAndSettle();

      // Tap Suspend Plan button
      final suspendBtn = find.byKey(const Key('suspendPlanButton'));
      expect(suspendBtn, findsOneWidget);
      await tester.tap(suspendBtn);
      await tester.pumpAndSettle();

      // Check dialog
      expect(find.text('Suspend Treatment Plan'), findsOneWidget);
      expect(find.byKey(const Key('statusReasonInput')), findsOneWidget);

      // Enter clinical rationale
      await tester.enterText(
        find.byKey(const Key('statusReasonInput')),
        'Patient presented with neutropenic fever, hold cytarabine.',
      );

      // Tap Confirm
      await tester.tap(find.byKey(const Key('confirmStatusChangeButton')));
      await tester.pumpAndSettle();

      expect(updatedStatus, 'suspended');
      expect(updateReason, 'Patient presented with neutropenic fever, hold cytarabine.');
    });

    testWidgets('opens medical closure dialog and marks plan completed (BR-3.5 physician closure)', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      String? updatedStatus;
      String? updateReason;

      final service = FakeDoctorTreatmentTrackingService(
        plans: [samplePlan],
        tasksByPlan: {'plan-101': sampleTasks},
        progressByPlan: {'plan-101': sampleProgressUpdates},
        onUpdateStatus: ({
          required String patientId,
          required String planId,
          required String targetStatus,
          String? statusReason,
        }) async {
          updatedStatus = targetStatus;
          updateReason = statusReason;
          return {'success': true};
        },
      );

      await tester.pumpWidget(buildTestWidget(service: service));
      await tester.pumpAndSettle();

      // Tap Complete (Medical Closure) button
      final completeBtn = find.byKey(const Key('completePlanButton'));
      expect(completeBtn, findsOneWidget);
      await tester.tap(completeBtn);
      await tester.pumpAndSettle();

      // Check dialog
      expect(find.text('Complete Treatment Plan (Medical Closure)'), findsOneWidget);
      expect(find.byKey(const Key('statusReasonInput')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('statusReasonInput')),
        'Achieved complete remission. 28-day induction cycle successfully completed.',
      );

      await tester.tap(find.byKey(const Key('confirmStatusChangeButton')));
      await tester.pumpAndSettle();

      expect(updatedStatus, 'completed');
      expect(updateReason, 'Achieved complete remission. 28-day induction cycle successfully completed.');
    });

    testWidgets('verifying task on ledger shows proof dialog', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final service = FakeDoctorTreatmentTrackingService(
        plans: [samplePlan],
        tasksByPlan: {'plan-101': sampleTasks},
        progressByPlan: {'plan-101': sampleProgressUpdates},
      );

      await tester.pumpWidget(buildTestWidget(service: service));
      await tester.pumpAndSettle();

      // Tap Ledger Audit Proof
      final proofBtn = find.byKey(const Key('verifyLedgerButton_task-1'));
      expect(proofBtn, findsOneWidget);
      await tester.tap(proofBtn);
      await tester.pumpAndSettle();

      expect(find.text('Ledger Verification'), findsOneWidget);
      expect(find.text('Transaction ID: tx-test-999'), findsOneWidget);
      expect(find.text('Record Status: ANCHORED & VERIFIED'), findsOneWidget);
    });

    testWidgets('timeline tab shows nurse and doctor updates with tolerance badges', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final service = FakeDoctorTreatmentTrackingService(
        plans: [samplePlan],
        tasksByPlan: {'plan-101': sampleTasks},
        progressByPlan: {'plan-101': sampleProgressUpdates},
      );

      await tester.pumpWidget(buildTestWidget(service: service));
      await tester.pumpAndSettle();

      // Switch to Timeline tab
      await tester.tap(find.text('Progress Timeline'));
      await tester.pumpAndSettle();

      expect(find.text('Nurse Sarah Jenkins'), findsOneWidget);
      expect(find.text('NURSE'), findsOneWidget);
      expect(find.text('Patient tolerating first round of cytarabine well.'), findsOneWidget);
      expect(find.text('Tolerance: WELL TOLERATED'), findsOneWidget);

      expect(find.text('Dr. Gregory House'), findsOneWidget);
      expect(find.text('DOCTOR'), findsOneWidget);
      expect(find.text('Reviewed morning labs. Continue planned cytarabine dosing.'), findsOneWidget);
      expect(find.text('Tolerance: MODERATE ADVERSE'), findsOneWidget);

      expect(find.byKey(const Key('recordProgressNavButton')), findsOneWidget);
    });

    testWidgets('EHR tab renders read-only mobile view', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final service = FakeDoctorTreatmentTrackingService(
        plans: [samplePlan],
        tasksByPlan: {'plan-101': sampleTasks},
        progressByPlan: {'plan-101': sampleProgressUpdates},
      );

      await tester.pumpWidget(buildTestWidget(service: service));
      await tester.pumpAndSettle();

      // Switch to EHR tab
      await tester.tap(find.text('EHR Summary'));
      await tester.pumpAndSettle();

      expect(find.text('Authorized EHR View (FE-5 / FR3.5)'), findsOneWidget);
      expect(
        find.textContaining('Patient records displayed are scoped strictly to the attending physician care team'),
        findsOneWidget,
      );
    });
  });
}
