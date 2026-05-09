// lib/models/medical_record_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

enum RecordType { report, prescription, medicalHistory, diagnosis }

extension RecordTypeX on RecordType {
  String get label {
    switch (this) {
      case RecordType.report:         return 'Report';
      case RecordType.prescription:   return 'Prescription';
      case RecordType.medicalHistory: return 'Medical History';
      case RecordType.diagnosis:      return 'Diagnosis';
    }
  }
  String get firestoreValue => name;
}

RecordType recordTypeFromString(String s) =>
    RecordType.values.firstWhere(
          (e) => e.name == s,
      orElse: () => RecordType.report,
    );

class MedicalRecordModel {
  final String id;
  final String patientId;
  final String title;
  final RecordType type;
  final String subtype;
  final String facility;
  final String doctorName;
  final DateTime date;
  final String fileUrl;
  final String fileType;
  final String summary;
  final DateTime uploadedAt;
  final bool isArchived;
  final String fileHash;     // ← added for integrity verification

  MedicalRecordModel({
    required this.id,
    required this.patientId,
    required this.title,
    required this.type,
    required this.subtype,
    required this.facility,
    this.doctorName  = '',
    required this.date,
    this.fileUrl     = '',
    this.fileType    = 'pdf',
    this.summary     = '',
    required this.uploadedAt,
    this.isArchived  = false,
    this.fileHash    = '',   // ← defaults to empty
  });

  Map<String, dynamic> toMap() => {
    'id':          id,
    'patientId':   patientId,
    'title':       title,
    'type':        type.firestoreValue,
    'subtype':     subtype,
    'facility':    facility,
    'doctorName':  doctorName,
    'date':        Timestamp.fromDate(date),
    'fileUrl':     fileUrl,
    'fileType':    fileType,
    'summary':     summary,
    'uploadedAt':  Timestamp.fromDate(uploadedAt),
    'isArchived':  isArchived,
    'fileHash':    fileHash,
  };

  factory MedicalRecordModel.fromMap(Map<String, dynamic> m) =>
      MedicalRecordModel(
        id:          m['id']        ?? '',
        patientId:   m['patientId'] ?? '',
        title:       m['title']     ?? '',
        type:        recordTypeFromString(m['type'] ?? 'report'),
        subtype:     m['subtype']   ?? '',
        facility:    m['facility']  ?? '',
        doctorName:  m['doctorName'] ?? '',
        date:        (m['date'] as Timestamp).toDate(),
        fileUrl:     m['fileUrl']   ?? '',
        fileType:    m['fileType']  ?? 'pdf',
        summary:     m['summary']   ?? '',
        uploadedAt:  (m['uploadedAt'] as Timestamp).toDate(),
        isArchived:  m['isArchived'] ?? false,
        fileHash:    m['fileHash']  ?? '',
      );
}

// ─────────────────────────────────────────────────────────────────
// NotificationModel — used by appointment_service + notifications_screen
// ─────────────────────────────────────────────────────────────────
class NotificationModel {
  final String id;
  final String patientId;
  final String title;
  final String body;
  final String type;
  final bool isRead;
  final DateTime createdAt;
  final String? referenceId;

  NotificationModel({
    required this.id,
    required this.patientId,
    required this.title,
    required this.body,
    required this.type,
    this.isRead       = false,
    required this.createdAt,
    this.referenceId,
  });

  Map<String, dynamic> toMap() => {
    'id':          id,
    'patientId':   patientId,
    'title':       title,
    'body':        body,
    'type':        type,
    'isRead':      isRead,
    'createdAt':   Timestamp.fromDate(createdAt),
    'referenceId': referenceId,
  };

  factory NotificationModel.fromMap(Map<String, dynamic> m) =>
      NotificationModel(
        id:          m['id']        ?? '',
        patientId:   m['patientId'] ?? '',
        title:       m['title']     ?? '',
        body:        m['body']      ?? '',
        type:        m['type']      ?? 'general',
        isRead:      m['isRead']    ?? false,
        createdAt:   (m['createdAt'] as Timestamp).toDate(),
        referenceId: m['referenceId'],
      );

  NotificationModel copyWith({bool? isRead}) => NotificationModel(
    id          : id,
    patientId   : patientId,
    title       : title,
    body        : body,
    type        : type,
    isRead      : isRead ?? this.isRead,
    createdAt   : createdAt,
    referenceId : referenceId,
  );
}