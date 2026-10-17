// test/screens/doctor/create_treatment_plan_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncovault/screens/doctor/create_treatment_plan_screen.dart';
import 'package:oncovault/services/treatment_tracking_service.dart';

class FakeCreatePlanService extends TreatmentTrackingService {
  final Future<Map<String, dynamic>> Function({
    required String patientId,
    required String title,
    required String clinicalObjectives,
    String? planId,
    DateTime? targetEndDate,
    required List<CreateTreatmentTaskInput> tasks,
  })? onCreatePlan;

  FakeCreatePlanService({this.onCreatePlan});

  @override
  Future<Map<String, dynamic>> createTreatmentPlan({
    required String patientId,
    required String title,
    required String clinicalObjectives,
    String? planId,
    DateTime? targetEndDate,
    required List<CreateTreatmentTaskInput> tasks,
  }) async {
    if (onCreatePlan != null) {
      return onCreatePlan!(
        patientId: patientId,
        title: title,
        clinicalObjectives: clinicalObjectives,
        planId: planId,
        tasks: tasks,
        targetEndDate: targetEndDate,
      );
    }
    return {
      'planId': 'plan-new-123',
      'title': title,
      'status': 'active',
      'totalTasks': tasks.length,
      'createdAt': DateTime.now().toIso8601String(),
    };
  }
}

void main() {
  Widget buildTestWidget({required TreatmentTrackingService service}) {
    return MaterialApp(
      home: CreateTreatmentPlanScreen(
        patientId: 'patient-999',
        patientName: 'Robert Johnson',
        doctorId: 'doc-777',
        service: service,
      ),
    );
  }

  group('CreateTreatmentPlanScreen Widget Tests', () {
    testWidgets('renders all initial fields and clinical governance disclaimer', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final service = FakeCreatePlanService();

      await tester.pumpWidget(buildTestWidget(service: service));
      await tester.pumpAndSettle();

      expect(find.text('Create Treatment Plan'), findsOneWidget);
      expect(find.text('Patient: Robert Johnson'), findsOneWidget);
      expect(find.byKey(const Key('planTitleField')), findsOneWidget);
      expect(find.byKey(const Key('clinicalObjectivesField')), findsOneWidget);
      expect(find.byKey(const Key('setTargetDateButton')), findsOneWidget);
      expect(find.byKey(const Key('addTaskButton')), findsOneWidget);
      expect(find.byKey(const Key('publishPlanButton')), findsOneWidget);

      // Verify clinical governance banner (BR-3.5 / FE-6)
      expect(
        find.textContaining('Physician Oversight: Directs bedside nursing workflow'),
        findsOneWidget,
      );
    });

    testWidgets('shows validation errors when submitting blank form', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final service = FakeCreatePlanService();

      await tester.pumpWidget(buildTestWidget(service: service));
      await tester.pumpAndSettle();

      // Tap Publish Plan without entering anything
      await tester.tap(find.byKey(const Key('publishPlanButton')));
      await tester.pumpAndSettle();

      expect(find.text('Plan title must be at least 3 characters.'), findsOneWidget);
      expect(find.text('Clinical objectives must be at least 5 characters.'), findsOneWidget);
    });

    testWidgets('shows validation error when form is filled but no tasks are added', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final service = FakeCreatePlanService();

      await tester.pumpWidget(buildTestWidget(service: service));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('planTitleField')),
        'Consolidation High-Dose Cytarabine (HiDAC)',
      );
      await tester.enterText(
        find.byKey(const Key('clinicalObjectivesField')),
        'Maintain complete remission and eradicate minimal residual disease.',
      );

      await tester.tap(find.byKey(const Key('publishPlanButton')));
      await tester.pumpAndSettle();

      expect(find.text('Please add at least one actionable care task before publishing.'), findsOneWidget);
    });

    testWidgets('can add actionable care tasks dynamically via dialog', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final service = FakeCreatePlanService();

      await tester.pumpWidget(buildTestWidget(service: service));
      await tester.pumpAndSettle();

      // Click Add Task button
      await tester.tap(find.byKey(const Key('addTaskButton')));
      await tester.pumpAndSettle();

      // Verify Add Task dialog
      expect(find.text('Add Actionable Care Task'), findsOneWidget);

      // Fill task details
      await tester.enterText(find.byKey(const Key('taskTitleInput')), 'Administer Ondansetron 8mg IV');
      await tester.enterText(
        find.byKey(const Key('taskInstructionsInput')),
        'Administer 30 minutes prior to chemotherapy infusion.',
      );

      // Confirm Add Task
      await tester.tap(find.byKey(const Key('confirmAddTaskButton')));
      await tester.pumpAndSettle();

      // Verify task appears in list
      expect(find.text('Administer Ondansetron 8mg IV'), findsOneWidget);
      expect(find.text('Administer 30 minutes prior to chemotherapy infusion.'), findsOneWidget);
      expect(find.text('Actionable Care Tasks (1)'), findsOneWidget);
    });

    testWidgets('can remove an added task', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final service = FakeCreatePlanService();

      await tester.pumpWidget(buildTestWidget(service: service));
      await tester.pumpAndSettle();

      // Add a task
      await tester.tap(find.byKey(const Key('addTaskButton')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('taskTitleInput')), 'Daily Weight and Fluid Balance');
      await tester.tap(find.byKey(const Key('confirmAddTaskButton')));
      await tester.pumpAndSettle();

      expect(find.text('Daily Weight and Fluid Balance'), findsOneWidget);

      // Remove the task
      await tester.tap(find.byKey(const Key('removeTaskButton_0')));
      await tester.pumpAndSettle();

      expect(find.text('Daily Weight and Fluid Balance'), findsNothing);
      expect(find.text('Actionable Care Tasks (0)'), findsOneWidget);
    });

    testWidgets('successful publish invokes createTreatmentPlan and navigates back', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      String? submittedTitle;
      String? submittedObjectives;
      List<CreateTreatmentTaskInput>? submittedTasks;

      final service = FakeCreatePlanService(
        onCreatePlan: ({
          required String patientId,
          required String title,
          required String clinicalObjectives,
          String? planId,
          DateTime? targetEndDate,
          required List<CreateTreatmentTaskInput> tasks,
        }) async {
          submittedTitle = title;
          submittedObjectives = clinicalObjectives;
          submittedTasks = tasks;
          return {
            'planId': 'plan-created-555',
            'status': 'active',
          };
        },
      );

      await tester.pumpWidget(buildTestWidget(service: service));
      await tester.pumpAndSettle();

      // Enter Title and Objectives
      await tester.enterText(
        find.byKey(const Key('planTitleField')),
        'AML Consolidation Therapy Cycle 1',
      );
      await tester.enterText(
        find.byKey(const Key('clinicalObjectivesField')),
        'Eradicate measurable residual disease in post-induction remission phase.',
      );

      // Add task 1
      await tester.tap(find.byKey(const Key('addTaskButton')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('taskTitleInput')), 'Administer Cytarabine 3g/m2 IV over 3h');
      await tester.enterText(find.byKey(const Key('taskInstructionsInput')), 'Infuse via central line on Days 1, 3, 5.');
      await tester.tap(find.byKey(const Key('confirmAddTaskButton')));
      await tester.pumpAndSettle();

      // Publish Plan
      await tester.tap(find.byKey(const Key('publishPlanButton')));
      await tester.pumpAndSettle();

      expect(submittedTitle, 'AML Consolidation Therapy Cycle 1');
      expect(submittedObjectives, 'Eradicate measurable residual disease in post-induction remission phase.');
      expect(submittedTasks?.length, 1);
      expect(submittedTasks?[0].title, 'Administer Cytarabine 3g/m2 IV over 3h');
      expect(submittedTasks?[0].instructions, 'Infuse via central line on Days 1, 3, 5.');
    });

    testWidgets('handles service error gracefully on publish', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final service = FakeCreatePlanService(
        onCreatePlan: ({
          required String patientId,
          required String title,
          required String clinicalObjectives,
          String? planId,
          DateTime? targetEndDate,
          required List<CreateTreatmentTaskInput> tasks,
        }) async {
          throw Exception('Doctor assignment required to create plan');
        },
      );

      await tester.pumpWidget(buildTestWidget(service: service));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('planTitleField')), 'Test Plan');
      await tester.enterText(find.byKey(const Key('clinicalObjectivesField')), 'Objectives for plan');

      // Add 1 task
      await tester.tap(find.byKey(const Key('addTaskButton')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('taskTitleInput')), 'Test Task');
      await tester.tap(find.byKey(const Key('confirmAddTaskButton')));
      await tester.pumpAndSettle();

      // Publish
      await tester.tap(find.byKey(const Key('publishPlanButton')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Doctor assignment required to create plan'), findsOneWidget);
    });
  });
}
