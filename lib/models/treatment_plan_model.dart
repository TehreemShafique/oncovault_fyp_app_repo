// lib/models/treatment_plan_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

/// Supported lifecycle statuses for a Treatment Plan.
class TreatmentPlanStatus {
  static const String active = 'active';
  static const String completed = 'completed';
  static const String suspended = 'suspended';
  static const String discontinued = 'discontinued';

  static const List<String> all = [
    active,
    completed,
    suspended,
    discontinued,
  ];

  static bool isValid(String status) =>
      all.contains(status.trim().toLowerCase());
}

/// Supported lifecycle statuses for an individual Treatment Task.
class TreatmentTaskStatus {
  static const String pending = 'pending';
  static const String inProgress = 'in_progress';
  static const String completed = 'completed';
  static const String skipped = 'skipped';

  static const List<String> all = [
    pending,
    inProgress,
    completed,
    skipped,
  ];

  static bool isValid(String status) =>
      all.contains(status.trim().toLowerCase());
}

/// Supported task care categories.
class TreatmentTaskCategory {
  static const String medication = 'medication';
  static const String nursingCare = 'nursing_care';
  static const String vitalMonitoring = 'vital_monitoring';
  static const String labCheck = 'lab_check';

  static const List<String> all = [
    medication,
    nursingCare,
    vitalMonitoring,
    labCheck,
  ];

  static bool isValid(String category) =>
      all.contains(category.trim().toLowerCase());
}

/// Supported factual observations of patient tolerance.
class PatientToleranceStatus {
  static const String wellTolerated = 'well_tolerated';
  static const String mildAdverse = 'mild_adverse';
  static const String moderateAdverse = 'moderate_adverse';
  static const String severeToxicity = 'severe_toxicity';

  static const List<String> all = [
    wellTolerated,
    mildAdverse,
    moderateAdverse,
    severeToxicity,
  ];

  static bool isValid(String status) =>
      all.contains(status.trim().toLowerCase());
}

DateTime? _parseDateTime(dynamic value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  return null;
}

/// Authoritative Treatment Plan Model directed by an Attending Physician.
/// Path: `patients/{patientId}/treatment_plans/{planId}`
class TreatmentPlanModel {
  final String planId;
  final String patientId;
  final String doctorId;
  final String doctorName;
  final String hospitalId;
  final String title;
  final String clinicalObjectives;
  final String status;
  final bool hasRecordedStatus;
  final bool hasRecordedTaskCounts;
  final DateTime startDate;
  final DateTime? targetEndDate;
  final int totalTasks;
  final int completedTasks;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? fabricTxId;
  final String? fabricStatus;
  final String? fabricTimestamp;
  final String? statusReason;
  final String? statusUpdatedByUid;

  TreatmentPlanModel({
    required this.planId,
    required this.patientId,
    required this.doctorId,
    required this.doctorName,
    required this.hospitalId,
    required this.title,
    required this.clinicalObjectives,
    this.status = TreatmentPlanStatus.active,
    this.hasRecordedStatus = true,
    this.hasRecordedTaskCounts = true,
    required this.startDate,
    this.targetEndDate,
    this.totalTasks = 0,
    this.completedTasks = 0,
    required this.createdAt,
    this.updatedAt,
    this.fabricTxId,
    this.fabricStatus,
    this.fabricTimestamp,
    this.statusReason,
    this.statusUpdatedByUid,
  }) {
    if (planId.trim().isEmpty) throw ArgumentError('planId cannot be empty');
    if (patientId.trim().isEmpty) {
      throw ArgumentError('patientId cannot be empty');
    }
    if (doctorId.trim().isEmpty) {
      throw ArgumentError('doctorId cannot be empty');
    }
    if (title.trim().isEmpty) throw ArgumentError('title cannot be empty');
    if (totalTasks < 0) throw ArgumentError('totalTasks cannot be negative');
    if (completedTasks < 0) {
      throw ArgumentError('completedTasks cannot be negative');
    }
    if (completedTasks > totalTasks && totalTasks > 0) {
      throw ArgumentError(
          'completedTasks ($completedTasks) cannot exceed totalTasks ($totalTasks)');
    }
  }

  double get overallProgressPercentage {
    if (totalTasks <= 0) return 0.0;
    final ratio = (completedTasks / totalTasks) * 100.0;
    return ratio > 100.0 ? 100.0 : double.parse(ratio.toStringAsFixed(1));
  }

  bool get isActive => status.toLowerCase() == TreatmentPlanStatus.active;
  bool get isCompleted => status.toLowerCase() == TreatmentPlanStatus.completed;
  bool get isSuspended => status.toLowerCase() == TreatmentPlanStatus.suspended;
  bool get isDiscontinued =>
      status.toLowerCase() == TreatmentPlanStatus.discontinued;

  Map<String, dynamic> toMap() => {
        'planId': planId,
        'patientId': patientId,
        'doctorId': doctorId,
        'doctorName': doctorName,
        'hospitalId': hospitalId,
        'title': title,
        'clinicalObjectives': clinicalObjectives,
        'status': status,
        'startDate': Timestamp.fromDate(startDate),
        'targetEndDate':
            targetEndDate != null ? Timestamp.fromDate(targetEndDate!) : null,
        'totalTasks': totalTasks,
        'completedTasks': completedTasks,
        'createdAt': Timestamp.fromDate(createdAt),
        'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
        'fabricTxId': fabricTxId,
        'fabricStatus': fabricStatus,
        'fabricTimestamp': fabricTimestamp,
        'statusReason': statusReason,
        'statusUpdatedByUid': statusUpdatedByUid,
      };

  factory TreatmentPlanModel.fromMap(Map<String, dynamic> map, [String? id]) {
    return TreatmentPlanModel(
      planId: id ?? map['planId'] ?? '',
      patientId: map['patientId'] ?? '',
      doctorId: map['doctorId'] ?? '',
      doctorName: map['doctorName'] ?? '',
      hospitalId: map['hospitalId'] ?? '',
      title: map['title'] ?? '',
      clinicalObjectives: map['clinicalObjectives'] ?? '',
      status: map['status'] ?? TreatmentPlanStatus.active,
      hasRecordedStatus: map['status'] is String &&
          (map['status'] as String).trim().isNotEmpty,
      hasRecordedTaskCounts:
          map['totalTasks'] is num && map['completedTasks'] is num,
      startDate: _parseDateTime(map['startDate']) ?? DateTime.now(),
      targetEndDate: _parseDateTime(map['targetEndDate']),
      totalTasks: (map['totalTasks'] as num?)?.toInt() ?? 0,
      completedTasks: (map['completedTasks'] as num?)?.toInt() ?? 0,
      createdAt: _parseDateTime(map['createdAt']) ?? DateTime.now(),
      updatedAt: _parseDateTime(map['updatedAt']),
      fabricTxId: map['fabricTxId'] as String?,
      fabricStatus: map['fabricStatus'] as String?,
      fabricTimestamp: map['fabricTimestamp'] as String?,
      statusReason: map['statusReason'] as String?,
      statusUpdatedByUid: map['statusUpdatedByUid'] as String?,
    );
  }

  TreatmentPlanModel copyWith({
    String? planId,
    String? patientId,
    String? doctorId,
    String? doctorName,
    String? hospitalId,
    String? title,
    String? clinicalObjectives,
    String? status,
    DateTime? startDate,
    DateTime? targetEndDate,
    int? totalTasks,
    int? completedTasks,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? fabricTxId,
    String? fabricStatus,
    String? fabricTimestamp,
    String? statusReason,
    String? statusUpdatedByUid,
  }) {
    return TreatmentPlanModel(
      planId: planId ?? this.planId,
      patientId: patientId ?? this.patientId,
      doctorId: doctorId ?? this.doctorId,
      doctorName: doctorName ?? this.doctorName,
      hospitalId: hospitalId ?? this.hospitalId,
      title: title ?? this.title,
      clinicalObjectives: clinicalObjectives ?? this.clinicalObjectives,
      status: status ?? this.status,
      hasRecordedStatus: status != null || hasRecordedStatus,
      hasRecordedTaskCounts: (totalTasks != null && completedTasks != null) ||
          hasRecordedTaskCounts,
      startDate: startDate ?? this.startDate,
      targetEndDate: targetEndDate ?? this.targetEndDate,
      totalTasks: totalTasks ?? this.totalTasks,
      completedTasks: completedTasks ?? this.completedTasks,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      fabricTxId: fabricTxId ?? this.fabricTxId,
      fabricStatus: fabricStatus ?? this.fabricStatus,
      fabricTimestamp: fabricTimestamp ?? this.fabricTimestamp,
      statusReason: statusReason ?? this.statusReason,
      statusUpdatedByUid: statusUpdatedByUid ?? this.statusUpdatedByUid,
    );
  }
}

/// Actionable Clinical Care Task defined by a Doctor and executed by a Nurse.
/// Path: `patients/{patientId}/treatment_plans/{planId}/tasks/{taskId}`
class TreatmentTaskModel {
  final String taskId;
  final String planId;
  final String patientId;
  final String title;
  final String instructions;
  final String category;
  final DateTime? scheduledTime;
  final String status;
  final String? completedByNurseId;
  final String? completedByNurseName;
  final DateTime? completedAt;
  final String? executionRemarks;
  final String? skipReason;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? fabricStatus;
  final String? fabricTxId;
  final String? fabricTimestamp;

  TreatmentTaskModel({
    required this.taskId,
    required this.planId,
    required this.patientId,
    required this.title,
    required this.instructions,
    this.category = TreatmentTaskCategory.nursingCare,
    this.scheduledTime,
    this.status = TreatmentTaskStatus.pending,
    this.completedByNurseId,
    this.completedByNurseName,
    this.completedAt,
    this.executionRemarks,
    this.skipReason,
    required this.createdAt,
    this.updatedAt,
    this.fabricStatus,
    this.fabricTxId,
    this.fabricTimestamp,
  }) {
    if (taskId.trim().isEmpty) throw ArgumentError('taskId cannot be empty');
    if (planId.trim().isEmpty) throw ArgumentError('planId cannot be empty');
    if (patientId.trim().isEmpty) {
      throw ArgumentError('patientId cannot be empty');
    }
    if (title.trim().isEmpty) throw ArgumentError('title cannot be empty');
    if (isCompleted &&
        (completedByNurseId == null || completedByNurseId!.trim().isEmpty)) {
      throw ArgumentError(
          'completed task must have completedByNurseId (BR-3.6)');
    }
    if (isCompleted && completedAt == null) {
      throw ArgumentError('completed task must have completedAt timestamp');
    }
  }

  bool get isPending => status.toLowerCase() == TreatmentTaskStatus.pending;
  bool get isInProgress =>
      status.toLowerCase() == TreatmentTaskStatus.inProgress;
  bool get isCompleted => status.toLowerCase() == TreatmentTaskStatus.completed;
  bool get isSkipped => status.toLowerCase() == TreatmentTaskStatus.skipped;

  // Hyperledger Fabric integrity status getters
  bool get isAnchored => fabricStatus?.toUpperCase() == 'COMMITTED';
  bool get isPendingAnchoring => fabricStatus?.toUpperCase() == 'PENDING';
  bool get isProcessingAnchoring => fabricStatus?.toUpperCase() == 'PROCESSING';
  bool get isFailedRetryable =>
      fabricStatus?.toUpperCase() == 'FAILED_RETRYABLE';
  bool get isFailedPermanent =>
      fabricStatus?.toUpperCase() == 'FAILED_PERMANENT';
  bool get hasAnchoringFailed => isFailedRetryable || isFailedPermanent;

  Map<String, dynamic> toMap() => {
        'taskId': taskId,
        'planId': planId,
        'patientId': patientId,
        'title': title,
        'instructions': instructions,
        'category': category,
        'scheduledTime':
            scheduledTime != null ? Timestamp.fromDate(scheduledTime!) : null,
        'status': status,
        'completedByNurseId': completedByNurseId,
        'completedByNurseName': completedByNurseName,
        'completedAt':
            completedAt != null ? Timestamp.fromDate(completedAt!) : null,
        'executionRemarks': executionRemarks,
        'skipReason': skipReason,
        'createdAt': Timestamp.fromDate(createdAt),
        'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
        'fabricStatus': fabricStatus,
        'fabricTxId': fabricTxId,
        'fabricTimestamp': fabricTimestamp,
      };

  factory TreatmentTaskModel.fromMap(Map<String, dynamic> map, [String? id]) {
    return TreatmentTaskModel(
      taskId: id ?? map['taskId'] ?? '',
      planId: map['planId'] ?? '',
      patientId: map['patientId'] ?? '',
      title: map['title'] ?? '',
      instructions: map['instructions'] ?? '',
      category: map['category'] ?? TreatmentTaskCategory.nursingCare,
      scheduledTime: _parseDateTime(map['scheduledTime']),
      status: map['status'] ?? TreatmentTaskStatus.pending,
      completedByNurseId: map['completedByNurseId'] as String?,
      completedByNurseName: map['completedByNurseName'] as String?,
      completedAt: _parseDateTime(map['completedAt']),
      executionRemarks: map['executionRemarks'] as String?,
      skipReason: map['skipReason'] as String?,
      createdAt: _parseDateTime(map['createdAt']) ?? DateTime.now(),
      updatedAt: _parseDateTime(map['updatedAt']),
      fabricStatus: map['fabricStatus'] as String?,
      fabricTxId: map['fabricTxId'] as String?,
      fabricTimestamp: map['fabricTimestamp'] as String?,
    );
  }

  TreatmentTaskModel copyWith({
    String? taskId,
    String? planId,
    String? patientId,
    String? title,
    String? instructions,
    String? category,
    DateTime? scheduledTime,
    String? status,
    String? completedByNurseId,
    String? completedByNurseName,
    DateTime? completedAt,
    String? executionRemarks,
    String? skipReason,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? fabricStatus,
    String? fabricTxId,
    String? fabricTimestamp,
  }) {
    return TreatmentTaskModel(
      taskId: taskId ?? this.taskId,
      planId: planId ?? this.planId,
      patientId: patientId ?? this.patientId,
      title: title ?? this.title,
      instructions: instructions ?? this.instructions,
      category: category ?? this.category,
      scheduledTime: scheduledTime ?? this.scheduledTime,
      status: status ?? this.status,
      completedByNurseId: completedByNurseId ?? this.completedByNurseId,
      completedByNurseName: completedByNurseName ?? this.completedByNurseName,
      completedAt: completedAt ?? this.completedAt,
      executionRemarks: executionRemarks ?? this.executionRemarks,
      skipReason: skipReason ?? this.skipReason,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      fabricStatus: fabricStatus ?? this.fabricStatus,
      fabricTxId: fabricTxId ?? this.fabricTxId,
      fabricTimestamp: fabricTimestamp ?? this.fabricTimestamp,
    );
  }
}

/// Factual Treatment Progress Update recorded by an Assigned Nurse or Attending Doctor.
/// Path: `patients/{patientId}/treatment_plans/{planId}/progress_updates/{updateId}`
class TreatmentProgressUpdateModel {
  final String updateId;
  final String planId;
  final String patientId;
  final String authorUid;
  final String authorName;
  final String authorRole;
  final DateTime timestamp;
  final String clinicalSummary;
  final String? patientTolerance;
  final String? factualObservations;
  final String? fabricTxId;
  final String? fabricStatus;
  final String? fabricTimestamp;

  TreatmentProgressUpdateModel({
    required this.updateId,
    required this.planId,
    required this.patientId,
    required this.authorUid,
    required this.authorName,
    required this.authorRole,
    required this.timestamp,
    required this.clinicalSummary,
    this.patientTolerance,
    this.factualObservations,
    this.fabricTxId,
    this.fabricStatus,
    this.fabricTimestamp,
  }) {
    if (updateId.trim().isEmpty) {
      throw ArgumentError('updateId cannot be empty');
    }
    if (planId.trim().isEmpty) throw ArgumentError('planId cannot be empty');
    if (patientId.trim().isEmpty) {
      throw ArgumentError('patientId cannot be empty');
    }
    if (authorUid.trim().isEmpty) {
      throw ArgumentError('authorUid cannot be empty');
    }
    if (clinicalSummary.trim().isEmpty) {
      throw ArgumentError('clinicalSummary cannot be empty');
    }
  }

  // Hyperledger Fabric integrity status getters
  bool get isAnchored => fabricStatus?.toUpperCase() == 'COMMITTED';
  bool get isPendingAnchoring => fabricStatus?.toUpperCase() == 'PENDING';
  bool get isProcessingAnchoring => fabricStatus?.toUpperCase() == 'PROCESSING';
  bool get isFailedRetryable =>
      fabricStatus?.toUpperCase() == 'FAILED_RETRYABLE';
  bool get isFailedPermanent =>
      fabricStatus?.toUpperCase() == 'FAILED_PERMANENT';
  bool get hasAnchoringFailed => isFailedRetryable || isFailedPermanent;

  Map<String, dynamic> toMap() => {
        'updateId': updateId,
        'planId': planId,
        'patientId': patientId,
        'authorUid': authorUid,
        'authorName': authorName,
        'authorRole': authorRole,
        'timestamp': Timestamp.fromDate(timestamp),
        'clinicalSummary': clinicalSummary,
        'patientTolerance': patientTolerance,
        'factualObservations': factualObservations,
        'fabricTxId': fabricTxId,
        'fabricStatus': fabricStatus,
        'fabricTimestamp': fabricTimestamp,
      };

  factory TreatmentProgressUpdateModel.fromMap(
    Map<String, dynamic> map, [
    String? id,
  ]) {
    return TreatmentProgressUpdateModel(
      updateId: id ?? map['updateId'] ?? '',
      planId: map['planId'] ?? '',
      patientId: map['patientId'] ?? '',
      authorUid: map['authorUid'] ?? '',
      authorName: map['authorName'] ?? '',
      authorRole: map['authorRole'] ?? '',
      timestamp: _parseDateTime(map['timestamp']) ?? DateTime.now(),
      clinicalSummary: map['clinicalSummary'] ?? '',
      patientTolerance: map['patientTolerance'] as String?,
      factualObservations: map['factualObservations'] as String?,
      fabricTxId: map['fabricTxId'] as String?,
      fabricStatus: map['fabricStatus'] as String?,
      fabricTimestamp: map['fabricTimestamp'] as String?,
    );
  }

  TreatmentProgressUpdateModel copyWith({
    String? updateId,
    String? planId,
    String? patientId,
    String? authorUid,
    String? authorName,
    String? authorRole,
    DateTime? timestamp,
    String? clinicalSummary,
    String? patientTolerance,
    String? factualObservations,
    String? fabricTxId,
    String? fabricStatus,
    String? fabricTimestamp,
  }) {
    return TreatmentProgressUpdateModel(
      updateId: updateId ?? this.updateId,
      planId: planId ?? this.planId,
      patientId: patientId ?? this.patientId,
      authorUid: authorUid ?? this.authorUid,
      authorName: authorName ?? this.authorName,
      authorRole: authorRole ?? this.authorRole,
      timestamp: timestamp ?? this.timestamp,
      clinicalSummary: clinicalSummary ?? this.clinicalSummary,
      patientTolerance: patientTolerance ?? this.patientTolerance,
      factualObservations: factualObservations ?? this.factualObservations,
      fabricTxId: fabricTxId ?? this.fabricTxId,
      fabricStatus: fabricStatus ?? this.fabricStatus,
      fabricTimestamp: fabricTimestamp ?? this.fabricTimestamp,
    );
  }
}

/// Represents the integrity and Hyperledger Fabric verification status of a treatment plan.
class TreatmentPlanIntegrityStatus {
  final String planId;
  final String patientId;
  final String? fabricTxId;
  final String? fabricStatus;
  final String? fabricTimestamp;
  final bool isAnchored;
  final int totalTasks;
  final int completedTasks;

  const TreatmentPlanIntegrityStatus({
    required this.planId,
    required this.patientId,
    this.fabricTxId,
    this.fabricStatus,
    this.fabricTimestamp,
    required this.isAnchored,
    required this.totalTasks,
    required this.completedTasks,
  });

  bool get isCommitted => fabricStatus?.toUpperCase() == 'COMMITTED';
  bool get isPending => fabricStatus?.toUpperCase() == 'PENDING';
  bool get isProcessing => fabricStatus?.toUpperCase() == 'PROCESSING';
  bool get isFailedRetryable =>
      fabricStatus?.toUpperCase() == 'FAILED_RETRYABLE';
  bool get isFailedPermanent =>
      fabricStatus?.toUpperCase() == 'FAILED_PERMANENT';
  bool get hasFailed => isFailedRetryable || isFailedPermanent;
  bool get isVerified =>
      isAnchored && fabricTxId != null && fabricTxId!.isNotEmpty;
}
