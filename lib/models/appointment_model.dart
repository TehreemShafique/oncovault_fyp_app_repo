// lib/models/appointment_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

enum AppointmentStatus { pending, approved, rejected, completed, cancelled, rescheduled }

extension AppointmentStatusX on AppointmentStatus {
  String get label {
    switch (this) {
      case AppointmentStatus.pending:     return 'Pending';
      case AppointmentStatus.approved:    return 'Approved';
      case AppointmentStatus.rejected:    return 'Rejected';
      case AppointmentStatus.completed:   return 'Completed';
      case AppointmentStatus.cancelled:   return 'Cancelled';
      case AppointmentStatus.rescheduled: return 'Rescheduled';
    }
  }

  String get firestoreValue => name; // 'pending', 'approved', etc.
}

AppointmentStatus statusFromString(String s) {
  return AppointmentStatus.values.firstWhere(
        (e) => e.name == s,
    orElse: () => AppointmentStatus.pending,
  );
}

class AppointmentModel {
  final String id;
  final String patientId;
  final String patientName;
  final String doctorId;       // Firebase UID or placeholder for future doctor module
  final String doctorName;
  final String doctorSpecialty;
  final String doctorImage;    // URL or empty string
  final DateTime appointmentDate;
  final String timeSlot;       // e.g. "09:30 AM"
  final int durationMinutes;
  final AppointmentStatus status;
  final String notes;          // Patient notes
  final String doctorNotes;    // Set by doctor module later
  final DateTime createdAt;
  final DateTime? updatedAt;
  final bool isCancellable;    // within 24h policy

  AppointmentModel({
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.doctorId,
    required this.doctorName,
    required this.doctorSpecialty,
    this.doctorImage = '',
    required this.appointmentDate,
    required this.timeSlot,
    this.durationMinutes = 45,
    required this.status,
    this.notes = '',
    this.doctorNotes = '',
    required this.createdAt,
    this.updatedAt,
    this.isCancellable = true,
  });

  Map<String, dynamic> toMap() => {
    'id':               id,
    'patientId':        patientId,
    'patientName':      patientName,
    'doctorId':         doctorId,
    'doctorName':       doctorName,
    'doctorSpecialty':  doctorSpecialty,
    'doctorImage':      doctorImage,
    'appointmentDate':  Timestamp.fromDate(appointmentDate),
    'timeSlot':         timeSlot,
    'durationMinutes':  durationMinutes,
    'status':           status.firestoreValue,
    'notes':            notes,
    'doctorNotes':      doctorNotes,
    'createdAt':        Timestamp.fromDate(createdAt),
    'updatedAt':        updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
    'isCancellable':    isCancellable,
  };

  factory AppointmentModel.fromMap(Map<String, dynamic> m) => AppointmentModel(
    id:               m['id'] ?? '',
    patientId:        m['patientId'] ?? '',
    patientName:      m['patientName'] ?? '',
    doctorId:         m['doctorId'] ?? '',
    doctorName:       m['doctorName'] ?? '',
    doctorSpecialty:  m['doctorSpecialty'] ?? '',
    doctorImage:      m['doctorImage'] ?? '',
    appointmentDate:  (m['appointmentDate'] as Timestamp).toDate(),
    timeSlot:         m['timeSlot'] ?? '',
    durationMinutes:  m['durationMinutes'] ?? 45,
    status:           statusFromString(m['status'] ?? 'pending'),
    notes:            m['notes'] ?? '',
    doctorNotes:      m['doctorNotes'] ?? '',
    createdAt:        (m['createdAt'] as Timestamp).toDate(),
    updatedAt:        m['updatedAt'] != null ? (m['updatedAt'] as Timestamp).toDate() : null,
    isCancellable:    m['isCancellable'] ?? true,
  );

  AppointmentModel copyWith({
    AppointmentStatus? status,
    String? notes,
    String? doctorNotes,
    DateTime? appointmentDate,
    String? timeSlot,
    DateTime? updatedAt,
    bool? isCancellable,
  }) => AppointmentModel(
    id: id, patientId: patientId, patientName: patientName,
    doctorId: doctorId, doctorName: doctorName, doctorSpecialty: doctorSpecialty,
    doctorImage: doctorImage,
    appointmentDate: appointmentDate ?? this.appointmentDate,
    timeSlot: timeSlot ?? this.timeSlot,
    durationMinutes: durationMinutes,
    status: status ?? this.status,
    notes: notes ?? this.notes,
    doctorNotes: doctorNotes ?? this.doctorNotes,
    createdAt: createdAt,
    updatedAt: updatedAt ?? DateTime.now(),
    isCancellable: isCancellable ?? this.isCancellable,
  );
}