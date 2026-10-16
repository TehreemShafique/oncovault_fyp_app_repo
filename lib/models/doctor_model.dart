// lib/models/doctor_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'doctor_availability_model.dart';

class DoctorModel {
  final String uid;
  final String name;
  final String email;
  final String medicalId;
  final String specialty;
  final String subSpecialty;
  final int experienceYears;
  final String hospital;
  final String department;
  final String phone;
  final String profileImageUrl;
  final String licenseNumber;
  final List<String> qualifications;
  final List<String> availableDays;   // ['Mon','Tue','Wed','Thu','Fri']
  final List<String> availableSlots;
  final bool isAvailable;
  final DateTime createdAt;
  final DoctorAvailability? _explicitAvailability;

  DoctorAvailability get availability =>
      _explicitAvailability ??
      DoctorAvailability.fromDoctorData({
        'availableDays': availableDays,
        'availableSlots': availableSlots,
        'isAvailable': isAvailable,
      });

  DoctorModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.medicalId,
    this.specialty = '',
    this.subSpecialty = '',
    this.experienceYears = 0,
    this.hospital = '',
    this.department = '',
    this.phone = '',
    this.profileImageUrl = '',
    this.licenseNumber = '',
    this.qualifications = const [],
    this.availableDays = const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'],
    this.availableSlots = const [
      '08:00 AM', '09:30 AM', '11:00 AM',
      '01:30 PM', '03:00 PM', '04:30 PM',
    ],
    this.isAvailable = true,
    DoctorAvailability? availability,
    required this.createdAt,
  }) : _explicitAvailability = availability;

  Map<String, dynamic> toMap() => {
    'uid':             uid,
    'name':            name,
    'email':           email,
    'medicalId':       medicalId,
    'specialty':       specialty,
    'subSpecialty':    subSpecialty,
    'experienceYears': experienceYears,
    'hospital':        hospital,
    'department':      department,
    'phone':           phone,
    'profileImageUrl': profileImageUrl,
    'licenseNumber':   licenseNumber,
    'qualifications':  qualifications,
    'availableDays':   availableDays,
    'availableSlots':  availableSlots,
    'isAvailable':     isAvailable,
    'createdAt':       Timestamp.fromDate(createdAt),
    if (_explicitAvailability != null &&
        _explicitAvailability!.state == DoctorAvailabilityState.structured)
      'availability': _explicitAvailability!.toMap(),
  };

  factory DoctorModel.fromMap(Map<String, dynamic> m) => DoctorModel(
    uid:             m['uid'] ?? '',
    name:            m['name'] ?? '',
    email:           m['email'] ?? '',
    medicalId:       m['medicalId'] ?? '',
    specialty:       m['specialty'] ?? '',
    subSpecialty:    m['subSpecialty'] ?? '',
    experienceYears: m['experienceYears'] ?? 0,
    hospital:        m['hospital'] ?? '',
    department:      m['department'] ?? '',
    phone:           m['phone'] ?? '',
    profileImageUrl: m['profileImageUrl'] ?? '',
    licenseNumber:   m['licenseNumber'] ?? '',
    qualifications:  List<String>.from(m['qualifications'] ?? []),
    availableDays:   List<String>.from(m['availableDays'] ?? []),
    availableSlots:  List<String>.from(m['availableSlots'] ?? []),
    isAvailable:     m['isAvailable'] ?? true,
    availability:    m.containsKey('availability')
        ? DoctorAvailability.fromDoctorData(m)
        : null,
    createdAt:       m['createdAt'] != null
        ? (m['createdAt'] as Timestamp).toDate()
        : DateTime.now(),
  );

  DoctorModel copyWith({
    String? specialty, String? subSpecialty, int? experienceYears,
    String? hospital, String? department, String? phone,
    String? profileImageUrl, String? licenseNumber,
    List<String>? qualifications, List<String>? availableDays,
    List<String>? availableSlots, bool? isAvailable,
    DoctorAvailability? availability,
  }) => DoctorModel(
    uid: uid, name: name, email: email, medicalId: medicalId,
    specialty: specialty ?? this.specialty,
    subSpecialty: subSpecialty ?? this.subSpecialty,
    experienceYears: experienceYears ?? this.experienceYears,
    hospital: hospital ?? this.hospital,
    department: department ?? this.department,
    phone: phone ?? this.phone,
    profileImageUrl: profileImageUrl ?? this.profileImageUrl,
    licenseNumber: licenseNumber ?? this.licenseNumber,
    qualifications: qualifications ?? this.qualifications,
    availableDays: availableDays ?? this.availableDays,
    availableSlots: availableSlots ?? this.availableSlots,
    isAvailable: isAvailable ?? this.isAvailable,
    availability: availability ?? _explicitAvailability,
    createdAt: createdAt,
  );
}

// ─── Diagnosis / Prescription model (doctor adds this) ────────────────────────
class DiagnosisEntry {
  final String id;
  final String patientId;
  final String patientName;
  final String doctorId;
  final String doctorName;
  final String diagnosisTitle;
  final String diagnosisDetails;
  final String prescription;
  final String clinicalNotes;
  final String recommendations;
  final List<String> attachedReportUrls;
  final String cancerType;
  final String stage;
  final String status;   // 'stable' | 'monitoring' | 'critical' | 'follow-up'
  final bool blockchainVerified;
  final DateTime createdAt;
  final DateTime? updatedAt;

  DiagnosisEntry({
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.doctorId,
    required this.doctorName,
    required this.diagnosisTitle,
    this.diagnosisDetails = '',
    this.prescription = '',
    this.clinicalNotes = '',
    this.recommendations = '',
    this.attachedReportUrls = const [],
    this.cancerType = '',
    this.stage = '',
    this.status = 'stable',
    this.blockchainVerified = false,
    required this.createdAt,
    this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
    'id':                  id,
    'patientId':           patientId,
    'patientName':         patientName,
    'doctorId':            doctorId,
    'doctorName':          doctorName,
    'diagnosisTitle':      diagnosisTitle,
    'diagnosisDetails':    diagnosisDetails,
    'prescription':        prescription,
    'clinicalNotes':       clinicalNotes,
    'recommendations':     recommendations,
    'attachedReportUrls':  attachedReportUrls,
    'cancerType':          cancerType,
    'stage':               stage,
    'status':              status,
    'blockchainVerified':  blockchainVerified,
    'createdAt':           Timestamp.fromDate(createdAt),
    'updatedAt':           updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
  };

  factory DiagnosisEntry.fromMap(Map<String, dynamic> m) => DiagnosisEntry(
    id:                  m['id'] ?? '',
    patientId:           m['patientId'] ?? '',
    patientName:         m['patientName'] ?? '',
    doctorId:            m['doctorId'] ?? '',
    doctorName:          m['doctorName'] ?? '',
    diagnosisTitle:      m['diagnosisTitle'] ?? '',
    diagnosisDetails:    m['diagnosisDetails'] ?? '',
    prescription:        m['prescription'] ?? '',
    clinicalNotes:       m['clinicalNotes'] ?? '',
    recommendations:     m['recommendations'] ?? '',
    attachedReportUrls:  List<String>.from(m['attachedReportUrls'] ?? []),
    cancerType:          m['cancerType'] ?? '',
    stage:               m['stage'] ?? '',
    status:              m['status'] ?? 'stable',
    blockchainVerified:  m['blockchainVerified'] ?? false,
    createdAt:           m['createdAt'] != null
        ? (m['createdAt'] as Timestamp).toDate()
        : DateTime.now(),
    updatedAt:           m['updatedAt'] != null
        ? (m['updatedAt'] as Timestamp).toDate() : null,
  );
}

// ─── Critical Alert model ─────────────────────────────────────────────────────
class CriticalAlert {
  final String id;
  final String patientId;
  final String patientName;
  final String doctorId;
  final String alertType;    // 'urgent_review' | 'lab_critical' | 'missed_appt' | 'vital_alert'
  final String severity;     // 'high' | 'medium' | 'low'
  final String title;
  final String description;
  final bool isRead;
  final bool isAcknowledged;
  final DateTime? acknowledgedAt;
  final String? acknowledgedBy;
  final String? acknowledgmentNotes;
  final bool isResolved;
  final DateTime? resolvedAt;
  final String? resolvedBy;
  final String? resolutionNotes;
  final String? eventId;
  final String? observationId;
  final String? dispatchStatus;
  final String? escalationStatus;
  final Map<String, dynamic>? vitalsSummary;
  final DateTime createdAt;

  CriticalAlert({
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.doctorId,
    required this.alertType,
    required this.severity,
    required this.title,
    required this.description,
    this.isRead = false,
    this.isAcknowledged = false,
    this.acknowledgedAt,
    this.acknowledgedBy,
    this.acknowledgmentNotes,
    this.isResolved = false,
    this.resolvedAt,
    this.resolvedBy,
    this.resolutionNotes,
    this.eventId,
    this.observationId,
    this.dispatchStatus,
    this.escalationStatus,
    this.vitalsSummary,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'id':                  id,
    'alertId':             id,
    'patientId':           patientId,
    'patientName':         patientName,
    'doctorId':            doctorId,
    'alertType':           alertType,
    'severity':            severity,
    'title':               title,
    'description':         description,
    'isRead':              isRead,
    'isAcknowledged':      isAcknowledged,
    'acknowledgedAt':      acknowledgedAt != null ? Timestamp.fromDate(acknowledgedAt!) : null,
    'acknowledgedBy':      acknowledgedBy,
    'acknowledgmentNotes': acknowledgmentNotes,
    'isResolved':          isResolved,
    'resolvedAt':          resolvedAt != null ? Timestamp.fromDate(resolvedAt!) : null,
    'resolvedBy':          resolvedBy,
    'resolutionNotes':     resolutionNotes,
    'eventId':             eventId,
    'observationId':       observationId,
    'dispatchStatus':      dispatchStatus,
    'escalationStatus':    escalationStatus,
    if (vitalsSummary != null) 'vitalsSummary': vitalsSummary,
    'createdAt':           Timestamp.fromDate(createdAt),
  };

  factory CriticalAlert.fromMap(Map<String, dynamic> m) {
    DateTime? parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val);
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      return null;
    }

    return CriticalAlert(
      id:                  m['id'] ?? m['alertId'] ?? '',
      patientId:           m['patientId'] ?? '',
      patientName:         m['patientName'] ?? '',
      doctorId:            m['doctorId'] ?? '',
      alertType:           m['alertType'] ?? '',
      severity:            m['severity'] ?? 'medium',
      title:               m['title'] ?? '',
      description:         m['description'] ?? '',
      isRead:              m['isRead'] ?? false,
      isAcknowledged:      m['isAcknowledged'] ?? false,
      acknowledgedAt:      parseDate(m['acknowledgedAt']),
      acknowledgedBy:      m['acknowledgedBy'],
      acknowledgmentNotes: m['acknowledgmentNotes'],
      isResolved:          m['isResolved'] ?? false,
      resolvedAt:          parseDate(m['resolvedAt']),
      resolvedBy:          m['resolvedBy'],
      resolutionNotes:     m['resolutionNotes'],
      eventId:             m['eventId'],
      observationId:       m['observationId'],
      dispatchStatus:      m['dispatchStatus'],
      escalationStatus:    m['escalationStatus'],
      vitalsSummary:       m['vitalsSummary'] is Map ? Map<String, dynamic>.from(m['vitalsSummary']) : null,
      createdAt:           parseDate(m['createdAt']) ?? DateTime.now(),
    );
  }

  CriticalAlert copyWith({
    bool? isRead,
    bool? isAcknowledged,
    DateTime? acknowledgedAt,
    String? acknowledgedBy,
    String? acknowledgmentNotes,
    bool? isResolved,
    DateTime? resolvedAt,
    String? resolvedBy,
    String? resolutionNotes,
    String? dispatchStatus,
    String? escalationStatus,
  }) => CriticalAlert(
    id:                  id,
    patientId:           patientId,
    patientName:         patientName,
    doctorId:            doctorId,
    alertType:           alertType,
    severity:            severity,
    title:               title,
    description:         description,
    isRead:              isRead ?? this.isRead,
    isAcknowledged:      isAcknowledged ?? this.isAcknowledged,
    acknowledgedAt:      acknowledgedAt ?? this.acknowledgedAt,
    acknowledgedBy:      acknowledgedBy ?? this.acknowledgedBy,
    acknowledgmentNotes: acknowledgmentNotes ?? this.acknowledgmentNotes,
    isResolved:          isResolved ?? this.isResolved,
    resolvedAt:          resolvedAt ?? this.resolvedAt,
    resolvedBy:          resolvedBy ?? this.resolvedBy,
    resolutionNotes:     resolutionNotes ?? this.resolutionNotes,
    eventId:             eventId,
    observationId:       observationId,
    dispatchStatus:      dispatchStatus ?? this.dispatchStatus,
    escalationStatus:    escalationStatus ?? this.escalationStatus,
    vitalsSummary:       vitalsSummary,
    createdAt:           createdAt,
  );
}

// ─── Schedule Entry ───────────────────────────────────────────────────────────
class ScheduleEntry {
  final String id;
  final String doctorId;
  final String title;
  final String location;
  final String type;    // 'consultation' | 'board_meeting' | 'review' | 'lab'
  final DateTime startTime;
  final DateTime endTime;
  final String? patientId;
  final String? patientName;
  final bool isNew;

  const ScheduleEntry({
    required this.id,
    required this.doctorId,
    required this.title,
    required this.location,
    required this.type,
    required this.startTime,
    required this.endTime,
    this.patientId,
    this.patientName,
    this.isNew = false,
  });
}