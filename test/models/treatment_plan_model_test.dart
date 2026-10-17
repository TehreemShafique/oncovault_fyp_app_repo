// test/models/treatment_plan_model_test.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncovault/models/treatment_plan_model.dart';

void main() {
  group('TreatmentPlanModel Tests', () {
    test('serializes and deserializes TreatmentPlanModel correctly', () {
      final now = DateTime.utc(2026, 10, 17, 10, 0, 0);
      final target = DateTime.utc(2026, 11, 1, 10, 0, 0);

      final plan = TreatmentPlanModel(
        planId: 'plan_001',
        patientId: 'pat_001',
        doctorId: 'doc_001',
        doctorName: 'Dr. John Doe',
        hospitalId: 'HOSP_A',
        title: 'Induction Phase Protocol',
        clinicalObjectives: 'Achieve complete hematologic remission.',
        status: TreatmentPlanStatus.active,
        startDate: now,
        targetEndDate: target,
        totalTasks: 10,
        completedTasks: 4,
        createdAt: now,
        updatedAt: now,
        fabricTxId: 'tx_fabric_123',
        fabricStatus: 'COMMITTED',
        fabricTimestamp: '2026-10-17T10:05:00Z',
      );

      final map = plan.toMap();
      expect(map['planId'], 'plan_001');
      expect(map['patientId'], 'pat_001');
      expect(map['doctorId'], 'doc_001');
      expect(map['title'], 'Induction Phase Protocol');
      expect(map['status'], 'active');
      expect(map['totalTasks'], 10);
      expect(map['completedTasks'], 4);
      expect(map['startDate'], isA<Timestamp>());
      expect(map['targetEndDate'], isA<Timestamp>());

      final restored = TreatmentPlanModel.fromMap(map, 'plan_001');
      expect(restored.planId, 'plan_001');
      expect(restored.patientId, 'pat_001');
      expect(restored.doctorId, 'doc_001');
      expect(restored.doctorName, 'Dr. John Doe');
      expect(restored.hospitalId, 'HOSP_A');
      expect(restored.title, 'Induction Phase Protocol');
      expect(restored.clinicalObjectives, 'Achieve complete hematologic remission.');
      expect(restored.status, TreatmentPlanStatus.active);
      expect(restored.totalTasks, 10);
      expect(restored.completedTasks, 4);
      expect(restored.overallProgressPercentage, 40.0);
      expect(restored.isActive, isTrue);
      expect(restored.isCompleted, isFalse);
      expect(restored.fabricTxId, 'tx_fabric_123');
      expect(restored.fabricStatus, 'COMMITTED');
    });

    test('progress calculation handles zero totalTasks, partial, and 100%', () {
      final now = DateTime.utc(2026, 10, 17, 10, 0, 0);

      final zeroTasks = TreatmentPlanModel(
        planId: 'plan_zero',
        patientId: 'pat_001',
        doctorId: 'doc_001',
        doctorName: 'Dr. John',
        hospitalId: 'HOSP_A',
        title: 'Empty Plan',
        clinicalObjectives: 'Evaluation only',
        startDate: now,
        totalTasks: 0,
        completedTasks: 0,
        createdAt: now,
      );
      expect(zeroTasks.overallProgressPercentage, 0.0);

      final partialTasks = zeroTasks.copyWith(totalTasks: 3, completedTasks: 1);
      expect(partialTasks.overallProgressPercentage, 33.3);

      final fullTasks = zeroTasks.copyWith(totalTasks: 5, completedTasks: 5);
      expect(fullTasks.overallProgressPercentage, 100.0);
    });

    test('validates negative task counts and completedTasks exceeding totalTasks', () {
      final now = DateTime.utc(2026, 10, 17, 10, 0, 0);

      expect(
        () => TreatmentPlanModel(
          planId: 'p1',
          patientId: 'pat1',
          doctorId: 'doc1',
          doctorName: 'Dr.',
          hospitalId: 'H1',
          title: 'Plan',
          clinicalObjectives: 'Obj',
          startDate: now,
          totalTasks: -1,
          completedTasks: 0,
          createdAt: now,
        ),
        throwsArgumentError,
      );

      expect(
        () => TreatmentPlanModel(
          planId: 'p1',
          patientId: 'pat1',
          doctorId: 'doc1',
          doctorName: 'Dr.',
          hospitalId: 'H1',
          title: 'Plan',
          clinicalObjectives: 'Obj',
          startDate: now,
          totalTasks: 2,
          completedTasks: 5,
          createdAt: now,
        ),
        throwsArgumentError,
      );
    });

    test('validates empty required strings', () {
      final now = DateTime.utc(2026, 10, 17, 10, 0, 0);

      expect(
        () => TreatmentPlanModel(
          planId: '',
          patientId: 'pat1',
          doctorId: 'doc1',
          doctorName: 'Dr.',
          hospitalId: 'H1',
          title: 'Plan',
          clinicalObjectives: 'Obj',
          startDate: now,
          createdAt: now,
        ),
        throwsArgumentError,
      );

      expect(
        () => TreatmentPlanModel(
          planId: 'p1',
          patientId: '',
          doctorId: 'doc1',
          doctorName: 'Dr.',
          hospitalId: 'H1',
          title: 'Plan',
          clinicalObjectives: 'Obj',
          startDate: now,
          createdAt: now,
        ),
        throwsArgumentError,
      );
    });

    test('supports status validation and helper getters', () {
      expect(TreatmentPlanStatus.isValid('active'), isTrue);
      expect(TreatmentPlanStatus.isValid('completed'), isTrue);
      expect(TreatmentPlanStatus.isValid('suspended'), isTrue);
      expect(TreatmentPlanStatus.isValid('discontinued'), isTrue);
      expect(TreatmentPlanStatus.isValid('unknown_status'), isFalse);
    });
  });

  group('TreatmentTaskModel Tests', () {
    test('serializes and deserializes TreatmentTaskModel correctly', () {
      final now = DateTime.utc(2026, 10, 17, 10, 0, 0);
      final scheduled = DateTime.utc(2026, 10, 17, 12, 0, 0);

      final task = TreatmentTaskModel(
        taskId: 'task_101',
        planId: 'plan_001',
        patientId: 'pat_001',
        title: 'Administer IV Normal Saline 500mL',
        instructions: 'Infuse over 2 hours via infusion pump.',
        category: TreatmentTaskCategory.nursingCare,
        scheduledTime: scheduled,
        status: TreatmentTaskStatus.pending,
        createdAt: now,
      );

      final map = task.toMap();
      expect(map['taskId'], 'task_101');
      expect(map['title'], 'Administer IV Normal Saline 500mL');
      expect(map['status'], 'pending');
      expect(map['category'], 'nursing_care');
      expect(map['scheduledTime'], isA<Timestamp>());

      final restored = TreatmentTaskModel.fromMap(map, 'task_101');
      expect(restored.taskId, 'task_101');
      expect(restored.isPending, isTrue);
      expect(restored.isCompleted, isFalse);
      expect(restored.instructions, 'Infuse over 2 hours via infusion pump.');
    });

    test('enforces completed task invariants: completedByNurseId and completedAt required', () {
      final now = DateTime.utc(2026, 10, 17, 10, 0, 0);

      // Missing completedByNurseId
      expect(
        () => TreatmentTaskModel(
          taskId: 't1',
          planId: 'p1',
          patientId: 'pat1',
          title: 'Vitals check',
          instructions: 'Measure BP',
          status: TreatmentTaskStatus.completed,
          completedAt: now,
          createdAt: now,
        ),
        throwsArgumentError,
      );

      // Missing completedAt
      expect(
        () => TreatmentTaskModel(
          taskId: 't1',
          planId: 'p1',
          patientId: 'pat1',
          title: 'Vitals check',
          instructions: 'Measure BP',
          status: TreatmentTaskStatus.completed,
          completedByNurseId: 'nurse_123',
          createdAt: now,
        ),
        throwsArgumentError,
      );

      // Valid completed task
      final validCompleted = TreatmentTaskModel(
        taskId: 't1',
        planId: 'p1',
        patientId: 'pat1',
        title: 'Vitals check',
        instructions: 'Measure BP',
        status: TreatmentTaskStatus.completed,
        completedByNurseId: 'nurse_123',
        completedByNurseName: 'Nurse Sara',
        completedAt: now,
        executionRemarks: 'BP 120/80 mmHg, patient resting comfortably.',
        createdAt: now,
      );
      expect(validCompleted.isCompleted, isTrue);
      expect(validCompleted.completedByNurseId, 'nurse_123');
      expect(validCompleted.executionRemarks, contains('120/80'));
    });

    test('supports task category and status helpers', () {
      expect(TreatmentTaskStatus.isValid('pending'), isTrue);
      expect(TreatmentTaskStatus.isValid('in_progress'), isTrue);
      expect(TreatmentTaskStatus.isValid('completed'), isTrue);
      expect(TreatmentTaskStatus.isValid('skipped'), isTrue);
      expect(TreatmentTaskStatus.isValid('deleted'), isFalse);

      expect(TreatmentTaskCategory.isValid('medication'), isTrue);
      expect(TreatmentTaskCategory.isValid('nursing_care'), isTrue);
      expect(TreatmentTaskCategory.isValid('vital_monitoring'), isTrue);
      expect(TreatmentTaskCategory.isValid('lab_check'), isTrue);
      expect(TreatmentTaskCategory.isValid('surgery'), isFalse);
    });
  });

  group('TreatmentProgressUpdateModel Tests', () {
    test('serializes and deserializes TreatmentProgressUpdateModel correctly', () {
      final now = DateTime.utc(2026, 10, 17, 10, 30, 0);

      final update = TreatmentProgressUpdateModel(
        updateId: 'upd_001',
        planId: 'plan_001',
        patientId: 'pat_001',
        authorUid: 'nurse_123',
        authorName: 'Nurse Sara',
        authorRole: 'nurse',
        timestamp: now,
        clinicalSummary: 'Patient completed hydration phase with no emesis.',
        patientTolerance: PatientToleranceStatus.wellTolerated,
        factualObservations: 'Afebrile, vital signs within normal parameters.',
        fabricStatus: 'PENDING',
      );

      final map = update.toMap();
      expect(map['updateId'], 'upd_001');
      expect(map['authorUid'], 'nurse_123');
      expect(map['clinicalSummary'], contains('hydration phase'));
      expect(map['patientTolerance'], 'well_tolerated');
      expect(map['fabricStatus'], 'PENDING');
      expect(map['timestamp'], isA<Timestamp>());

      final restored = TreatmentProgressUpdateModel.fromMap(map, 'upd_001');
      expect(restored.updateId, 'upd_001');
      expect(restored.authorName, 'Nurse Sara');
      expect(restored.authorRole, 'nurse');
      expect(restored.patientTolerance, 'well_tolerated');
      expect(restored.factualObservations, contains('Afebrile'));
    });

    test('validates required fields on progress update', () {
      final now = DateTime.utc(2026, 10, 17, 10, 30, 0);

      expect(
        () => TreatmentProgressUpdateModel(
          updateId: '',
          planId: 'p1',
          patientId: 'pat1',
          authorUid: 'n1',
          authorName: 'Nurse',
          authorRole: 'nurse',
          timestamp: now,
          clinicalSummary: 'Summary',
        ),
        throwsArgumentError,
      );

      expect(
        () => TreatmentProgressUpdateModel(
          updateId: 'u1',
          planId: 'p1',
          patientId: 'pat1',
          authorUid: 'n1',
          authorName: 'Nurse',
          authorRole: 'nurse',
          timestamp: now,
          clinicalSummary: '',
        ),
        throwsArgumentError,
      );
    });

    test('supports patient tolerance status validation', () {
      expect(PatientToleranceStatus.isValid('well_tolerated'), isTrue);
      expect(PatientToleranceStatus.isValid('mild_adverse'), isTrue);
      expect(PatientToleranceStatus.isValid('moderate_adverse'), isTrue);
      expect(PatientToleranceStatus.isValid('severe_toxicity'), isTrue);
      expect(PatientToleranceStatus.isValid('unconscious'), isFalse);
    });
  });
}
