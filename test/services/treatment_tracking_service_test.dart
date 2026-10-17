// test/services/treatment_tracking_service_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:oncovault/models/treatment_plan_model.dart';
import 'package:oncovault/services/treatment_tracking_service.dart';

void main() {
  group('Treatment Exceptions', () {
    test('TreatmentPlanException stores message and optional details', () {
      const ex = TreatmentPlanException('General error', code: 'internal', details: {'foo': 'bar'});
      expect(ex.message, 'General error');
      expect(ex.code, 'internal');
      expect(ex.details, {'foo': 'bar'});
      expect(ex.toString(), contains('TreatmentPlanException: General error (code: internal)'));
    });

    test('TreatmentAuthorizationException extends TreatmentPlanException', () {
      const ex = TreatmentAuthorizationException('Permission denied', code: 'permission-denied');
      expect(ex, isA<TreatmentPlanException>());
      expect(ex.code, 'permission-denied');
      expect(ex.toString(), contains('TreatmentAuthorizationException: Permission denied'));
    });

    test('TreatmentValidationException extends TreatmentPlanException', () {
      const ex = TreatmentValidationException('Invalid argument', code: 'invalid-argument');
      expect(ex, isA<TreatmentPlanException>());
      expect(ex.code, 'invalid-argument');
      expect(ex.toString(), contains('TreatmentValidationException: Invalid argument'));
    });
  });

  group('CreateTreatmentTaskInput', () {
    test('serializes to map with ISO dates when scheduledTime is provided', () {
      final scheduled = DateTime.utc(2026, 10, 18, 9, 0, 0);
      final input = CreateTreatmentTaskInput(
        title: 'Check Blood Pressure',
        instructions: 'Every 2 hours',
        category: 'vital_monitoring',
        scheduledTime: scheduled,
      );

      final map = input.toMap();
      expect(map['title'], 'Check Blood Pressure');
      expect(map['instructions'], 'Every 2 hours');
      expect(map['category'], 'vital_monitoring');
      expect(map['scheduledTimeIso'], '2026-10-18T09:00:00.000Z');
    });

    test('serializes to map omitting null optional fields', () {
      const input = CreateTreatmentTaskInput(title: 'Administer IV fluids');
      final map = input.toMap();
      expect(map['title'], 'Administer IV fluids');
      expect(map.containsKey('instructions'), isFalse);
      expect(map.containsKey('category'), isFalse);
      expect(map.containsKey('scheduledTimeIso'), isFalse);
    });
  });

  group('TreatmentPlanIntegrityStatus', () {
    test('computes isCommitted and isVerified correctly', () {
      const committedStatus = TreatmentPlanIntegrityStatus(
        planId: 'plan_100',
        patientId: 'patient_200',
        fabricTxId: 'tx_abc_123',
        fabricStatus: 'COMMITTED',
        fabricTimestamp: '2026-10-17T12:00:00Z',
        isAnchored: true,
        totalTasks: 5,
        completedTasks: 3,
      );

      expect(committedStatus.isCommitted, isTrue);
      expect(committedStatus.isVerified, isTrue);
      expect(committedStatus.isAnchored, isTrue);
      expect(committedStatus.totalTasks, 5);
      expect(committedStatus.completedTasks, 3);

      const pendingStatus = TreatmentPlanIntegrityStatus(
        planId: 'plan_101',
        patientId: 'patient_200',
        fabricTxId: null,
        fabricStatus: 'PENDING',
        isAnchored: false,
        totalTasks: 2,
        completedTasks: 0,
      );

      expect(pendingStatus.isCommitted, isFalse);
      expect(pendingStatus.isVerified, isFalse);
      expect(pendingStatus.isAnchored, isFalse);
    });
  });

  group('TreatmentTrackingService — Client-Side Validation', () {
    final service = TreatmentTrackingService();

    test('createTreatmentPlan rejects empty patientId', () async {
      expect(
        () => service.createTreatmentPlan(
          patientId: '',
          title: 'Induction Phase',
          clinicalObjectives: 'Remission',
          tasks: [const CreateTreatmentTaskInput(title: 'Task 1')],
        ),
        throwsA(isA<TreatmentValidationException>()),
      );
    });

    test('createTreatmentPlan rejects empty title', () async {
      expect(
        () => service.createTreatmentPlan(
          patientId: 'pat_1',
          title: '   ',
          clinicalObjectives: 'Remission',
          tasks: [const CreateTreatmentTaskInput(title: 'Task 1')],
        ),
        throwsA(isA<TreatmentValidationException>()),
      );
    });

    test('createTreatmentPlan rejects empty clinicalObjectives', () async {
      expect(
        () => service.createTreatmentPlan(
          patientId: 'pat_1',
          title: 'Induction Phase',
          clinicalObjectives: '',
          tasks: [const CreateTreatmentTaskInput(title: 'Task 1')],
        ),
        throwsA(isA<TreatmentValidationException>()),
      );
    });

    test('createTreatmentPlan rejects empty tasks list', () async {
      expect(
        () => service.createTreatmentPlan(
          patientId: 'pat_1',
          title: 'Induction Phase',
          clinicalObjectives: 'Remission',
          tasks: [],
        ),
        throwsA(isA<TreatmentValidationException>()),
      );
    });

    test('completeTreatmentTask rejects empty inputs', () async {
      expect(
        () => service.completeTreatmentTask(patientId: '', planId: 'pl_1', taskId: 'tk_1'),
        throwsA(isA<TreatmentValidationException>()),
      );
      expect(
        () => service.completeTreatmentTask(patientId: 'p_1', planId: '', taskId: 'tk_1'),
        throwsA(isA<TreatmentValidationException>()),
      );
      expect(
        () => service.completeTreatmentTask(patientId: 'p_1', planId: 'pl_1', taskId: ''),
        throwsA(isA<TreatmentValidationException>()),
      );
    });

    test('recordTreatmentProgressUpdate rejects empty clinicalSummary', () async {
      expect(
        () => service.recordTreatmentProgressUpdate(
          patientId: 'p_1',
          planId: 'pl_1',
          clinicalSummary: '  ',
        ),
        throwsA(isA<TreatmentValidationException>()),
      );
    });

    test('updateTreatmentPlanStatus rejects invalid status', () async {
      expect(
        () => service.updateTreatmentPlanStatus(
          patientId: 'p_1',
          planId: 'pl_1',
          targetStatus: 'invalid_status_xyz',
        ),
        throwsA(isA<TreatmentValidationException>()),
      );
    });
  });

  group('TreatmentTrackingService — Callable Invocations', () {
    test('createTreatmentPlan dispatches payload to custom callable hook', () async {
      Map<String, dynamic>? receivedPayload;
      final service = TreatmentTrackingService(
        customCreatePlanCallable: (data) async {
          receivedPayload = data;
          return {
            'success': true,
            'planId': 'plan_generated_001',
            'patientId': data['patientId'],
            'totalTasks': 2,
          };
        },
      );

      final result = await service.createTreatmentPlan(
        patientId: 'pat_101',
        title: 'Consolidation Cycle 1',
        clinicalObjectives: 'Monitor counts and administer supportive care',
        targetEndDate: DateTime.utc(2026, 11, 1),
        tasks: [
          const CreateTreatmentTaskInput(
            title: 'Pre-hydration',
            instructions: '1L Normal Saline over 2 hours',
            category: 'nursing_care',
          ),
          const CreateTreatmentTaskInput(
            title: 'Anti-emetic Administration',
            category: 'medication',
          ),
        ],
      );

      expect(result['success'], isTrue);
      expect(result['planId'], 'plan_generated_001');
      expect(result['totalTasks'], 2);
      expect(receivedPayload?['patientId'], 'pat_101');
      expect(receivedPayload?['title'], 'Consolidation Cycle 1');
      expect((receivedPayload?['tasks'] as List).length, 2);
    });

    test('completeTreatmentTask dispatches payload to custom callable hook', () async {
      Map<String, dynamic>? receivedPayload;
      final service = TreatmentTrackingService(
        customCompleteTaskCallable: (data) async {
          receivedPayload = data;
          return {
            'success': true,
            'taskId': data['taskId'],
            'status': 'completed',
            'completedTasks': 1,
            'totalTasks': 2,
          };
        },
      );

      final result = await service.completeTreatmentTask(
        patientId: 'pat_101',
        planId: 'plan_001',
        taskId: 'task_001',
        executionRemarks: 'Hydration administered without adverse reaction.',
      );

      expect(result['success'], isTrue);
      expect(result['taskId'], 'task_001');
      expect(result['status'], 'completed');
      expect(receivedPayload?['patientId'], 'pat_101');
      expect(receivedPayload?['planId'], 'plan_001');
      expect(receivedPayload?['taskId'], 'task_001');
      expect(receivedPayload?['executionRemarks'], contains('Hydration administered'));
    });

    test('recordTreatmentProgressUpdate dispatches payload to custom callable hook', () async {
      Map<String, dynamic>? receivedPayload;
      final service = TreatmentTrackingService(
        customRecordProgressCallable: (data) async {
          receivedPayload = data;
          return {
            'success': true,
            'updateId': 'upd_001',
            'planId': data['planId'],
          };
        },
      );

      final result = await service.recordTreatmentProgressUpdate(
        patientId: 'pat_101',
        planId: 'plan_001',
        clinicalSummary: 'Patient rested comfortably throughout morning shift.',
        patientTolerance: 'well_tolerated',
        factualObservations: 'Vitals stable; no rigors or nausea observed.',
      );

      expect(result['success'], isTrue);
      expect(result['updateId'], 'upd_001');
      expect(receivedPayload?['clinicalSummary'], contains('Patient rested'));
      expect(receivedPayload?['patientTolerance'], 'well_tolerated');
    });

    test('updateTreatmentPlanStatus dispatches valid status transition to custom callable', () async {
      Map<String, dynamic>? receivedPayload;
      final service = TreatmentTrackingService(
        customUpdateStatusCallable: (data) async {
          receivedPayload = data;
          return {
            'success': true,
            'planId': data['planId'],
            'status': data['targetStatus'],
          };
        },
      );

      final result = await service.updateTreatmentPlanStatus(
        patientId: 'pat_101',
        planId: 'plan_001',
        targetStatus: 'completed',
        statusReason: 'All scheduled consolidation tasks finished.',
      );

      expect(result['success'], isTrue);
      expect(result['status'], 'completed');
      expect(receivedPayload?['targetStatus'], 'completed');
      expect(receivedPayload?['statusReason'], contains('consolidation tasks finished'));
    });
  });

  group('TreatmentTrackingService — Functions Exception Mapping', () {
    test('maps permission-denied to TreatmentAuthorizationException', () async {
      final service = TreatmentTrackingService(
        customCompleteTaskCallable: (_) async {
          throw FirebaseFunctionsException(
            code: 'permission-denied',
            message: 'Active nurse assignment required in same hospital.',
          );
        },
      );

      expect(
        () => service.completeTreatmentTask(
          patientId: 'pat_101',
          planId: 'plan_001',
          taskId: 'task_001',
        ),
        throwsA(
          isA<TreatmentAuthorizationException>().having(
            (e) => e.code,
            'code',
            'permission-denied',
          ),
        ),
      );
    });

    test('maps invalid-argument to TreatmentValidationException', () async {
      final service = TreatmentTrackingService(
        customCreatePlanCallable: (_) async {
          throw FirebaseFunctionsException(
            code: 'invalid-argument',
            message: 'Invalid plan input structure.',
          );
        },
      );

      expect(
        () => service.createTreatmentPlan(
          patientId: 'pat_101',
          title: 'Plan Title',
          clinicalObjectives: 'Objectives',
          tasks: [const CreateTreatmentTaskInput(title: 'Task 1')],
        ),
        throwsA(
          isA<TreatmentValidationException>().having(
            (e) => e.code,
            'code',
            'invalid-argument',
          ),
        ),
      );
    });

    test('maps internal error to base TreatmentPlanException', () async {
      final service = TreatmentTrackingService(
        customRecordProgressCallable: (_) async {
          throw FirebaseFunctionsException(
            code: 'internal',
            message: 'Unexpected database error.',
          );
        },
      );

      expect(
        () => service.recordTreatmentProgressUpdate(
          patientId: 'pat_101',
          planId: 'plan_001',
          clinicalSummary: 'Summary',
        ),
        throwsA(
          isA<TreatmentPlanException>().having((e) => e.code, 'code', 'internal'),
        ),
      );
    });
  });
}
