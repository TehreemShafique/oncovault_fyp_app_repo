// lib/services/treatment_tracking_service.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/treatment_plan_model.dart';
import 'fabric_gateway_service.dart';

/// Exception thrown when a treatment plan or task operation encounters a domain failure.
class TreatmentPlanException implements Exception {
  final String message;
  final String? code;
  final dynamic details;

  const TreatmentPlanException(this.message, {this.code, this.details});

  @override
  String toString() => 'TreatmentPlanException: $message (code: $code)';
}

/// Exception thrown when a doctor or nurse lacks active clinical authorization.
class TreatmentAuthorizationException extends TreatmentPlanException {
  const TreatmentAuthorizationException(super.message, {super.code, super.details});

  @override
  String toString() => 'TreatmentAuthorizationException: $message (code: $code)';
}

/// Exception thrown when treatment plan or task input fails validation.
class TreatmentValidationException extends TreatmentPlanException {
  const TreatmentValidationException(super.message, {super.code, super.details});

  @override
  String toString() => 'TreatmentValidationException: $message (code: $code)';
}

/// Model for passing new tasks into `createTreatmentPlan`.
class CreateTreatmentTaskInput {
  final String title;
  final String? instructions;
  final String? category;
  final DateTime? scheduledTime;

  const CreateTreatmentTaskInput({
    required this.title,
    this.instructions,
    this.category,
    this.scheduledTime,
  });

  Map<String, dynamic> toMap() => {
    'title': title,
    if (instructions != null) 'instructions': instructions,
    if (category != null) 'category': category,
    if (scheduledTime != null) 'scheduledTimeIso': scheduledTime!.toUtc().toIso8601String(),
  };
}

/// Service managing doctor-directed treatment plans, nurse-executed care tasks,
/// factual progress updates, and Fabric blockchain integrity verification.
class TreatmentTrackingService {
  static TreatmentTrackingService? _instance;
  static TreatmentTrackingService get instance => _instance ??= TreatmentTrackingService();
  static set instance(TreatmentTrackingService? value) => _instance = value;

  final FirebaseFirestore? _customDb;
  final FirebaseFunctions? _customFunctions;
  final FirebaseAuth? _customAuth;
  final FabricGatewayService? _customFabricGateway;

  // Optional dependency injection hooks for unit/mock testing
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> data)? _customCreatePlanCallable;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> data)? _customCompleteTaskCallable;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> data)? _customRecordProgressCallable;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> data)? _customUpdateStatusCallable;

  TreatmentTrackingService({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    FirebaseAuth? auth,
    FabricGatewayService? fabricGateway,
    Future<Map<String, dynamic>> Function(Map<String, dynamic> data)? customCreatePlanCallable,
    Future<Map<String, dynamic>> Function(Map<String, dynamic> data)? customCompleteTaskCallable,
    Future<Map<String, dynamic>> Function(Map<String, dynamic> data)? customRecordProgressCallable,
    Future<Map<String, dynamic>> Function(Map<String, dynamic> data)? customUpdateStatusCallable,
  })  : _customDb = firestore,
        _customFunctions = functions,
        _customAuth = auth,
        _customFabricGateway = fabricGateway,
        _customCreatePlanCallable = customCreatePlanCallable,
        _customCompleteTaskCallable = customCompleteTaskCallable,
        _customRecordProgressCallable = customRecordProgressCallable,
        _customUpdateStatusCallable = customUpdateStatusCallable;

  FirebaseFirestore get _db => _customDb ?? FirebaseFirestore.instance;
  FirebaseFunctions get _functions =>
      _customFunctions ?? FirebaseFunctions.instanceFor(region: 'us-central1');
  FirebaseAuth get _auth => _customAuth ?? FirebaseAuth.instance;
  FabricGatewayService get _fabricGateway =>
      _customFabricGateway ?? FabricGatewayService.instance;

  String? get currentUserId {
    try {
      return _auth.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  // ─── Collection References ───────────────────────────────────
  CollectionReference _treatmentPlans(String patientId) =>
      _db.collection('patients').doc(patientId).collection('treatment_plans');

  CollectionReference _treatmentTasks(String patientId, String planId) =>
      _treatmentPlans(patientId).doc(planId).collection('tasks');

  CollectionReference _progressUpdates(String patientId, String planId) =>
      _treatmentPlans(patientId).doc(planId).collection('progress_updates');

  // ─── Real-Time Streams ──────────────────────────────────────

  /// Real-time stream of all treatment plans for [patientId], ordered newest first.
  Stream<List<TreatmentPlanModel>> watchPatientTreatmentPlans(String patientId) {
    return _treatmentPlans(patientId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => TreatmentPlanModel.fromMap(
                  d.data() as Map<String, dynamic>,
                  d.id,
                ))
            .toList());
  }

  /// Real-time stream of a single treatment plan by [patientId] and [planId].
  Stream<TreatmentPlanModel?> watchTreatmentPlan(String patientId, String planId) {
    return _treatmentPlans(patientId).doc(planId).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      return TreatmentPlanModel.fromMap(
        snap.data() as Map<String, dynamic>,
        snap.id,
      );
    });
  }

  /// Real-time stream of tasks under [planId] for [patientId], ordered by creation.
  Stream<List<TreatmentTaskModel>> watchTreatmentTasks(
    String patientId,
    String planId,
  ) {
    return _treatmentTasks(patientId, planId)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => TreatmentTaskModel.fromMap(
                  d.data() as Map<String, dynamic>,
                  d.id,
                ))
            .toList());
  }

  /// Real-time stream of pending/in-progress tasks for [planId].
  Stream<List<TreatmentTaskModel>> watchPendingTreatmentTasks(
    String patientId,
    String planId,
  ) {
    return watchTreatmentTasks(patientId, planId).map(
      (tasks) => tasks.where((t) => t.isPending || t.isInProgress).toList(),
    );
  }

  /// Real-time stream of factual treatment progress updates for [planId], ordered newest first.
  Stream<List<TreatmentProgressUpdateModel>> watchTreatmentProgressUpdates(
    String patientId,
    String planId,
  ) {
    return _progressUpdates(patientId, planId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => TreatmentProgressUpdateModel.fromMap(
                  d.data() as Map<String, dynamic>,
                  d.id,
                ))
            .toList());
  }

  /// Real-time stream of treatment plan integrity and blockchain verification status.
  Stream<TreatmentPlanIntegrityStatus?> watchTreatmentPlanIntegrityStatus(
    String patientId,
    String planId,
  ) {
    return watchTreatmentPlan(patientId, planId).map((plan) {
      if (plan == null) return null;
      return TreatmentPlanIntegrityStatus(
        planId: plan.planId,
        patientId: plan.patientId,
        fabricTxId: plan.fabricTxId,
        fabricStatus: plan.fabricStatus,
        fabricTimestamp: plan.fabricTimestamp,
        isAnchored: plan.fabricTxId != null && plan.fabricTxId!.trim().isNotEmpty,
        totalTasks: plan.totalTasks,
        completedTasks: plan.completedTasks,
      );
    });
  }

  // ─── Fetch Methods ──────────────────────────────────────────

  /// Fetches a single treatment plan by [patientId] and [planId].
  Future<TreatmentPlanModel?> fetchTreatmentPlan(
    String patientId,
    String planId,
  ) async {
    final doc = await _treatmentPlans(patientId).doc(planId).get();
    if (!doc.exists || doc.data() == null) return null;
    return TreatmentPlanModel.fromMap(
      doc.data() as Map<String, dynamic>,
      doc.id,
    );
  }

  /// Fetches a single treatment task by [patientId], [planId], and [taskId].
  Future<TreatmentTaskModel?> fetchTreatmentTask(
    String patientId,
    String planId,
    String taskId,
  ) async {
    final doc = await _treatmentTasks(patientId, planId).doc(taskId).get();
    if (!doc.exists || doc.data() == null) return null;
    return TreatmentTaskModel.fromMap(
      doc.data() as Map<String, dynamic>,
      doc.id,
    );
  }

  // ─── Cloud Function Operations ──────────────────────────────

  /// Creates a new doctor-directed treatment plan with structured actionable tasks.
  Future<Map<String, dynamic>> createTreatmentPlan({
    required String patientId,
    required String title,
    required String clinicalObjectives,
    String? planId,
    DateTime? targetEndDate,
    required List<CreateTreatmentTaskInput> tasks,
  }) async {
    if (patientId.trim().isEmpty) {
      throw const TreatmentValidationException('patientId cannot be empty');
    }
    if (title.trim().isEmpty) {
      throw const TreatmentValidationException('title cannot be empty');
    }
    if (clinicalObjectives.trim().isEmpty) {
      throw const TreatmentValidationException('clinicalObjectives cannot be empty');
    }
    if (tasks.isEmpty) {
      throw const TreatmentValidationException('At least one treatment task is required');
    }

    final payload = <String, dynamic>{
      'patientId': patientId.trim(),
      'title': title.trim(),
      'clinicalObjectives': clinicalObjectives.trim(),
      if (planId != null && planId.trim().isNotEmpty) 'planId': planId.trim(),
      if (targetEndDate != null)
        'targetEndDateIso': targetEndDate.toUtc().toIso8601String(),
      'tasks': tasks.map((t) => t.toMap()).toList(),
    };

    try {
      if (_customCreatePlanCallable != null) {
        return await _customCreatePlanCallable!(payload);
      }
      final callable = _functions.httpsCallable('createTreatmentPlan');
      final result = await callable.call<Map<String, dynamic>>(payload);
      return Map<String, dynamic>.from(result.data);
    } catch (e) {
      throw _mapFunctionsException(e);
    }
  }

  /// Completes an actionable treatment task executed by an authorized assigned nurse.
  Future<Map<String, dynamic>> completeTreatmentTask({
    required String patientId,
    required String planId,
    required String taskId,
    String? executionRemarks,
  }) async {
    if (patientId.trim().isEmpty) {
      throw const TreatmentValidationException('patientId cannot be empty');
    }
    if (planId.trim().isEmpty) {
      throw const TreatmentValidationException('planId cannot be empty');
    }
    if (taskId.trim().isEmpty) {
      throw const TreatmentValidationException('taskId cannot be empty');
    }

    final payload = <String, dynamic>{
      'patientId': patientId.trim(),
      'planId': planId.trim(),
      'taskId': taskId.trim(),
      if (executionRemarks != null && executionRemarks.trim().isNotEmpty)
        'executionRemarks': executionRemarks.trim(),
    };

    try {
      if (_customCompleteTaskCallable != null) {
        return await _customCompleteTaskCallable!(payload);
      }
      final callable = _functions.httpsCallable('completeTreatmentTask');
      final result = await callable.call<Map<String, dynamic>>(payload);
      return Map<String, dynamic>.from(result.data);
    } catch (e) {
      throw _mapFunctionsException(e);
    }
  }

  /// Records a factual treatment progress observation by an authorized doctor or nurse.
  Future<Map<String, dynamic>> recordTreatmentProgressUpdate({
    required String patientId,
    required String planId,
    required String clinicalSummary,
    String? updateId,
    String? patientTolerance,
    String? factualObservations,
  }) async {
    if (patientId.trim().isEmpty) {
      throw const TreatmentValidationException('patientId cannot be empty');
    }
    if (planId.trim().isEmpty) {
      throw const TreatmentValidationException('planId cannot be empty');
    }
    if (clinicalSummary.trim().isEmpty) {
      throw const TreatmentValidationException('clinicalSummary cannot be empty');
    }

    final payload = <String, dynamic>{
      'patientId': patientId.trim(),
      'planId': planId.trim(),
      'clinicalSummary': clinicalSummary.trim(),
      if (updateId != null && updateId.trim().isNotEmpty)
        'updateId': updateId.trim(),
      if (patientTolerance != null && patientTolerance.trim().isNotEmpty)
        'patientTolerance': patientTolerance.trim(),
      if (factualObservations != null && factualObservations.trim().isNotEmpty)
        'factualObservations': factualObservations.trim(),
    };

    try {
      if (_customRecordProgressCallable != null) {
        return await _customRecordProgressCallable!(payload);
      }
      final callable = _functions.httpsCallable('recordTreatmentProgressUpdate');
      final result = await callable.call<Map<String, dynamic>>(payload);
      return Map<String, dynamic>.from(result.data);
    } catch (e) {
      throw _mapFunctionsException(e);
    }
  }

  /// Updates the lifecycle status of a treatment plan (authorized doctor only).
  Future<Map<String, dynamic>> updateTreatmentPlanStatus({
    required String patientId,
    required String planId,
    required String targetStatus,
    String? statusReason,
  }) async {
    if (patientId.trim().isEmpty) {
      throw const TreatmentValidationException('patientId cannot be empty');
    }
    if (planId.trim().isEmpty) {
      throw const TreatmentValidationException('planId cannot be empty');
    }
    if (!TreatmentPlanStatus.isValid(targetStatus)) {
      throw TreatmentValidationException('Invalid targetStatus: $targetStatus');
    }

    final payload = <String, dynamic>{
      'patientId': patientId.trim(),
      'planId': planId.trim(),
      'targetStatus': targetStatus.trim().toLowerCase(),
      if (statusReason != null && statusReason.trim().isNotEmpty)
        'statusReason': statusReason.trim(),
    };

    try {
      if (_customUpdateStatusCallable != null) {
        return await _customUpdateStatusCallable!(payload);
      }
      final callable = _functions.httpsCallable('updateTreatmentPlanStatus');
      final result = await callable.call<Map<String, dynamic>>(payload);
      return Map<String, dynamic>.from(result.data);
    } catch (e) {
      throw _mapFunctionsException(e);
    }
  }

  // ─── Fabric Blockchain Integrity Verification ──────────────

  /// Verifies whether a completed treatment task is anchored and verified on Hyperledger Fabric.
  Future<FabricProofInfo?> verifyTreatmentTaskOnLedger({
    required String patientId,
    required String planId,
    required String taskId,
  }) async {
    final domainRecordId = 'task_${planId}_$taskId';
    try {
      return await _fabricGateway.getRecordProof(
        domainRecordId,
        patientId: patientId,
      );
    } catch (_) {
      return null;
    }
  }

  /// Verifies whether a treatment progress update is anchored and verified on Hyperledger Fabric.
  Future<FabricProofInfo?> verifyProgressUpdateOnLedger({
    required String patientId,
    required String planId,
    required String updateId,
  }) async {
    final domainRecordId = 'tp_${planId}_$updateId';
    try {
      return await _fabricGateway.getRecordProof(
        domainRecordId,
        patientId: patientId,
      );
    } catch (_) {
      return null;
    }
  }

  // ─── Error Handling & Mapping ───────────────────────────────

  TreatmentPlanException _mapFunctionsException(dynamic error) {
    if (error is TreatmentPlanException) return error;

    if (error is FirebaseFunctionsException) {
      final code = error.code.toLowerCase();
      final msg = error.message ?? error.details?.toString() ?? 'Cloud Function invocation error';

      if (code == 'permission-denied' || code == 'unauthenticated') {
        return TreatmentAuthorizationException(msg, code: code, details: error.details);
      }
      if (code == 'invalid-argument' || code == 'failed-precondition') {
        return TreatmentValidationException(msg, code: code, details: error.details);
      }
      return TreatmentPlanException(msg, code: code, details: error.details);
    }

    return TreatmentPlanException(error.toString());
  }
}
