// lib/models/nurse_assignment_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a trusted hospital care assignment linking a nurse to a patient.
/// Stored in Firestore under: `nurse_patient_assignments/{nurseId}_{patientId}`.
class NursePatientAssignment {
  final String id;           // Canonical composite ID: "${nurseId}_${patientId}"
  final String nurseId;
  final String nurseName;
  final String patientId;
  final String patientName;
  final String assignedBy;   // UID of assigning hospital administrator or attending physician
  final String hospitalId;
  final String status;       // 'active' | 'revoked' | 'completed'
  final DateTime assignedAt;
  final DateTime? updatedAt;
  final String notes;

  const NursePatientAssignment({
    required this.id,
    required this.nurseId,
    required this.nurseName,
    required this.patientId,
    required this.patientName,
    required this.assignedBy,
    this.hospitalId = 'Oncology Ward 3A',
    this.status = 'active',
    required this.assignedAt,
    this.updatedAt,
    this.notes = '',
  });

  bool get isActive => status.toLowerCase() == 'active';

  Map<String, dynamic> toMap() => {
    'id': id,
    'nurseId': nurseId,
    'nurseName': nurseName,
    'patientId': patientId,
    'patientName': patientName,
    'assignedBy': assignedBy,
    'hospitalId': hospitalId,
    'status': status,
    'assignedAt': Timestamp.fromDate(assignedAt),
    'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
    'notes': notes,
  };

  factory NursePatientAssignment.fromMap(Map<String, dynamic> m, {String? docId}) {
    DateTime parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      return DateTime.now();
    }

    return NursePatientAssignment(
      id: docId ?? (m['id'] as String? ?? ''),
      nurseId: m['nurseId'] as String? ?? '',
      nurseName: m['nurseName'] as String? ?? '',
      patientId: m['patientId'] as String? ?? '',
      patientName: m['patientName'] as String? ?? '',
      assignedBy: m['assignedBy'] as String? ?? '',
      hospitalId: m['hospitalId'] as String? ?? 'Oncology Ward 3A',
      status: m['status'] as String? ?? 'active',
      assignedAt: parseDate(m['assignedAt']),
      updatedAt: m['updatedAt'] != null ? parseDate(m['updatedAt']) : null,
      notes: m['notes'] as String? ?? '',
    );
  }
}
