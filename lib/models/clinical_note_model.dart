// lib/models/clinical_note_model.dart
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';

enum ClinicalNoteType {
  intakeNote,
  progressNote,
  shiftSummary,
}

extension ClinicalNoteTypeX on ClinicalNoteType {
  String get label {
    switch (this) {
      case ClinicalNoteType.intakeNote:
        return 'Intake Note';
      case ClinicalNoteType.progressNote:
        return 'Progress Note';
      case ClinicalNoteType.shiftSummary:
        return 'Shift Summary';
    }
  }

  String get firestoreValue {
    switch (this) {
      case ClinicalNoteType.intakeNote:
        return 'intake_note';
      case ClinicalNoteType.progressNote:
        return 'progress_note';
      case ClinicalNoteType.shiftSummary:
        return 'shift_summary';
    }
  }

  static ClinicalNoteType fromString(String? s) {
    switch (s?.toLowerCase().trim()) {
      case 'intake_note':
      case 'intakenote':
        return ClinicalNoteType.intakeNote;
      case 'shift_summary':
      case 'shiftsummary':
        return ClinicalNoteType.shiftSummary;
      case 'progress_note':
      case 'progressnote':
      default:
        return ClinicalNoteType.progressNote;
    }
  }
}

enum ClinicalNoteStatus {
  draft,
  submitted,
  reviewed,
  amended,
}

extension ClinicalNoteStatusX on ClinicalNoteStatus {
  String get label {
    switch (this) {
      case ClinicalNoteStatus.draft:
        return 'Draft';
      case ClinicalNoteStatus.submitted:
        return 'Submitted';
      case ClinicalNoteStatus.reviewed:
        return 'Reviewed';
      case ClinicalNoteStatus.amended:
        return 'Amended';
    }
  }

  String get firestoreValue => name.toUpperCase();

  static ClinicalNoteStatus fromString(String? s) {
    switch (s?.toUpperCase().trim()) {
      case 'DRAFT':
        return ClinicalNoteStatus.draft;
      case 'REVIEWED':
        return ClinicalNoteStatus.reviewed;
      case 'AMENDED':
        return ClinicalNoteStatus.amended;
      case 'SUBMITTED':
      default:
        return ClinicalNoteStatus.submitted;
    }
  }
}

class ClinicalNoteModel {
  final String noteId;
  final String patientId;
  final String patientName;
  final ClinicalNoteType noteType;
  final String authorUid;
  final String authorName;
  final String authorRole; // 'nurse', 'house_officer', 'doctor'
  final String? hospitalId;

  // Transcription & NLP Review
  final String rawTranscription;
  final String nurseReviewedTranscript;
  final String clinicalSummary;
  final Map<String, dynamic> supportedExtractedSymptoms;

  // Nursing Care Documentation
  final String narrativeObservations;
  final String careInterventions;
  final String treatmentResponseNarrative;

  // Lifecycle & Audit
  final ClinicalNoteStatus status;
  final DateTime createdAt;
  final DateTime? submittedAt;
  final DateTime? reviewedAt;
  final String? reviewedByUid;
  final String? reviewedByName;
  final String? doctorReviewNotes;

  // Immutability & Amendment tracking
  final String? amendmentOf;
  final String? amendmentReason;
  final bool isAmended;
  final String? amendedByNoteId;
  final String? createdAtIso;

  // Hyperledger Fabric Integrity
  final String? fileHash;
  final String? fabricStatus;
  final String? fabricTxId;
  final int? fabricVersion;
  final DateTime? fabricTimestamp;
  final String? opaqueRecordKey;

  const ClinicalNoteModel({
    required this.noteId,
    required this.patientId,
    required this.patientName,
    required this.noteType,
    required this.authorUid,
    required this.authorName,
    required this.authorRole,
    this.hospitalId,
    this.rawTranscription = '',
    this.nurseReviewedTranscript = '',
    this.clinicalSummary = '',
    this.supportedExtractedSymptoms = const {},
    this.narrativeObservations = '',
    this.careInterventions = '',
    this.treatmentResponseNarrative = '',
    this.status = ClinicalNoteStatus.submitted,
    required this.createdAt,
    this.submittedAt,
    this.reviewedAt,
    this.reviewedByUid,
    this.reviewedByName,
    this.doctorReviewNotes,
    this.amendmentOf,
    this.amendmentReason,
    this.isAmended = false,
    this.amendedByNoteId,
    this.createdAtIso,
    this.fileHash,
    this.fabricStatus,
    this.fabricTxId,
    this.fabricVersion,
    this.fabricTimestamp,
    this.opaqueRecordKey,
  });

  /// Computes a deterministic canonical SHA-256 hash of the clinical note content.
  /// Used for tamper verification and Hyperledger Fabric anchoring.
  String computeCanonicalHash({String? createdAtIsoOverride}) {
    final effectiveIso = createdAtIsoOverride ??
        createdAtIso ??
        createdAt.toUtc().toIso8601String();
    final canonicalMap = <String, dynamic>{
      'amendmentOf': amendmentOf ?? '',
      'amendmentReason': (amendmentReason ?? '').trim(),
      'authorUid': authorUid,
      'careInterventions': careInterventions.trim(),
      'clinicalSummary': clinicalSummary.trim(),
      'createdAtIso': effectiveIso,
      'narrativeObservations': narrativeObservations.trim(),
      'noteId': noteId,
      'noteType': noteType.firestoreValue,
      'nurseReviewedTranscript': nurseReviewedTranscript.trim(),
      'patientId': patientId,
      'supportedExtractedSymptoms': supportedExtractedSymptoms,
      'treatmentResponseNarrative': treatmentResponseNarrative.trim(),
    };
    final sortedKeys = canonicalMap.keys.toList()..sort();
    final orderedMap = {for (final k in sortedKeys) k: canonicalMap[k]};
    final serialized = jsonEncode(orderedMap);
    return sha256.convert(utf8.encode(serialized)).toString().toLowerCase();
  }

  Map<String, dynamic> toMap() => {
        'noteId': noteId,
        'patientId': patientId,
        'patientName': patientName,
        'noteType': noteType.firestoreValue,
        'authorUid': authorUid,
        'authorName': authorName,
        'authorRole': authorRole,
        if (hospitalId != null && hospitalId!.isNotEmpty) 'hospitalId': hospitalId,
        'rawTranscription': rawTranscription,
        'nurseReviewedTranscript': nurseReviewedTranscript,
        'clinicalSummary': clinicalSummary,
        'supportedExtractedSymptoms': supportedExtractedSymptoms,
        'narrativeObservations': narrativeObservations,
        'careInterventions': careInterventions,
        'treatmentResponseNarrative': treatmentResponseNarrative,
        'status': status.firestoreValue,
        'createdAt': Timestamp.fromDate(createdAt),
        if (createdAtIso != null && createdAtIso!.isNotEmpty) 'createdAtIso': createdAtIso,
        if (submittedAt != null) 'submittedAt': Timestamp.fromDate(submittedAt!),
        if (reviewedAt != null) 'reviewedAt': Timestamp.fromDate(reviewedAt!),
        if (reviewedByUid != null) 'reviewedByUid': reviewedByUid,
        if (reviewedByName != null) 'reviewedByName': reviewedByName,
        if (doctorReviewNotes != null && doctorReviewNotes!.isNotEmpty)
          'doctorReviewNotes': doctorReviewNotes,
        if (amendmentOf != null && amendmentOf!.isNotEmpty) 'amendmentOf': amendmentOf,
        if (amendmentReason != null && amendmentReason!.isNotEmpty)
          'amendmentReason': amendmentReason,
        'isAmended': isAmended,
        if (amendedByNoteId != null && amendedByNoteId!.isNotEmpty)
          'amendedByNoteId': amendedByNoteId,
        if (fileHash != null && fileHash!.isNotEmpty) 'fileHash': fileHash,
        if (fabricStatus != null && fabricStatus!.isNotEmpty) 'fabricStatus': fabricStatus,
        if (fabricTxId != null && fabricTxId!.isNotEmpty) 'fabricTxId': fabricTxId,
        if (fabricVersion != null) 'fabricVersion': fabricVersion,
        if (fabricTimestamp != null) 'fabricTimestamp': Timestamp.fromDate(fabricTimestamp!),
        if (opaqueRecordKey != null && opaqueRecordKey!.isNotEmpty)
          'opaqueRecordKey': opaqueRecordKey,
      };

  /// Client-safe write map (omits privileged Fabric metadata)
  Map<String, dynamic> toClientFirestoreMap() {
    final map = toMap();
    map.remove('fabricStatus');
    map.remove('fabricTxId');
    map.remove('fabricVersion');
    map.remove('fabricTimestamp');
    map.remove('opaqueRecordKey');
    return map;
  }

  factory ClinicalNoteModel.fromMap(Map<String, dynamic> map, {String? docId}) {
    DateTime parseDate(dynamic val, DateTime fallback) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val) ?? fallback;
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      return fallback;
    }

    final cDate = parseDate(map['createdAt'], DateTime.now());
    final sDate = map['submittedAt'] != null ? parseDate(map['submittedAt'], cDate) : null;
    final rDate = map['reviewedAt'] != null ? parseDate(map['reviewedAt'], cDate) : null;
    final fDate = map['fabricTimestamp'] != null ? parseDate(map['fabricTimestamp'], cDate) : null;

    Map<String, dynamic> symptoms = {};
    if (map['supportedExtractedSymptoms'] is Map) {
      symptoms = Map<String, dynamic>.from(map['supportedExtractedSymptoms'] as Map);
    }

    return ClinicalNoteModel(
      noteId: docId ?? map['noteId']?.toString() ?? '',
      patientId: map['patientId']?.toString() ?? '',
      patientName: map['patientName']?.toString() ?? 'Patient',
      noteType: ClinicalNoteTypeX.fromString(map['noteType']?.toString()),
      authorUid: map['authorUid']?.toString() ?? '',
      authorName: map['authorName']?.toString() ?? 'Clinician',
      authorRole: map['authorRole']?.toString() ?? 'nurse',
      hospitalId: map['hospitalId']?.toString(),
      rawTranscription: map['rawTranscription']?.toString() ?? '',
      nurseReviewedTranscript: map['nurseReviewedTranscript']?.toString() ?? '',
      clinicalSummary: map['clinicalSummary']?.toString() ?? '',
      supportedExtractedSymptoms: symptoms,
      narrativeObservations: map['narrativeObservations']?.toString() ?? '',
      careInterventions: map['careInterventions']?.toString() ?? '',
      treatmentResponseNarrative: map['treatmentResponseNarrative']?.toString() ?? '',
      status: ClinicalNoteStatusX.fromString(map['status']?.toString()),
      createdAt: cDate,
      submittedAt: sDate,
      reviewedAt: rDate,
      reviewedByUid: map['reviewedByUid']?.toString(),
      reviewedByName: map['reviewedByName']?.toString(),
      doctorReviewNotes: map['doctorReviewNotes']?.toString(),
      amendmentOf: map['amendmentOf']?.toString(),
      amendmentReason: map['amendmentReason']?.toString(),
      isAmended: map['isAmended'] as bool? ?? false,
      amendedByNoteId: map['amendedByNoteId']?.toString(),
      createdAtIso: map['createdAtIso']?.toString() ?? cDate.toUtc().toIso8601String(),
      fileHash: map['fileHash']?.toString(),
      fabricStatus: map['fabricStatus']?.toString(),
      fabricTxId: map['fabricTxId']?.toString(),
      fabricVersion: (map['fabricVersion'] as num?)?.toInt(),
      fabricTimestamp: fDate,
      opaqueRecordKey: map['opaqueRecordKey']?.toString(),
    );
  }

  ClinicalNoteModel copyWith({
    String? noteId,
    String? patientId,
    String? patientName,
    ClinicalNoteType? noteType,
    String? authorUid,
    String? authorName,
    String? authorRole,
    String? hospitalId,
    String? rawTranscription,
    String? nurseReviewedTranscript,
    String? clinicalSummary,
    Map<String, dynamic>? supportedExtractedSymptoms,
    String? narrativeObservations,
    String? careInterventions,
    String? treatmentResponseNarrative,
    ClinicalNoteStatus? status,
    DateTime? createdAt,
    DateTime? submittedAt,
    DateTime? reviewedAt,
    String? reviewedByUid,
    String? reviewedByName,
    String? doctorReviewNotes,
    String? amendmentOf,
    String? amendmentReason,
    bool? isAmended,
    String? amendedByNoteId,
    String? createdAtIso,
    String? fileHash,
    String? fabricStatus,
    String? fabricTxId,
    int? fabricVersion,
    DateTime? fabricTimestamp,
    String? opaqueRecordKey,
  }) {
    return ClinicalNoteModel(
      noteId: noteId ?? this.noteId,
      patientId: patientId ?? this.patientId,
      patientName: patientName ?? this.patientName,
      noteType: noteType ?? this.noteType,
      authorUid: authorUid ?? this.authorUid,
      authorName: authorName ?? this.authorName,
      authorRole: authorRole ?? this.authorRole,
      hospitalId: hospitalId ?? this.hospitalId,
      rawTranscription: rawTranscription ?? this.rawTranscription,
      nurseReviewedTranscript: nurseReviewedTranscript ?? this.nurseReviewedTranscript,
      clinicalSummary: clinicalSummary ?? this.clinicalSummary,
      supportedExtractedSymptoms: supportedExtractedSymptoms ?? this.supportedExtractedSymptoms,
      narrativeObservations: narrativeObservations ?? this.narrativeObservations,
      careInterventions: careInterventions ?? this.careInterventions,
      treatmentResponseNarrative: treatmentResponseNarrative ?? this.treatmentResponseNarrative,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      submittedAt: submittedAt ?? this.submittedAt,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      reviewedByUid: reviewedByUid ?? this.reviewedByUid,
      reviewedByName: reviewedByName ?? this.reviewedByName,
      doctorReviewNotes: doctorReviewNotes ?? this.doctorReviewNotes,
      amendmentOf: amendmentOf ?? this.amendmentOf,
      amendmentReason: amendmentReason ?? this.amendmentReason,
      isAmended: isAmended ?? this.isAmended,
      amendedByNoteId: amendedByNoteId ?? this.amendedByNoteId,
      createdAtIso: createdAtIso ?? this.createdAtIso,
      fileHash: fileHash ?? this.fileHash,
      fabricStatus: fabricStatus ?? this.fabricStatus,
      fabricTxId: fabricTxId ?? this.fabricTxId,
      fabricVersion: fabricVersion ?? this.fabricVersion,
      fabricTimestamp: fabricTimestamp ?? this.fabricTimestamp,
      opaqueRecordKey: opaqueRecordKey ?? this.opaqueRecordKey,
    );
  }
}
