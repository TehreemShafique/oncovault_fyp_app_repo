// lib/models/doctor_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

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
    required this.createdAt,
  });

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
  final String alertType;    // 'urgent_review' | 'lab_critical' | 'missed_appt' | 'vitals'
  final String severity;     // 'high' | 'medium' | 'low'
  final String title;
  final String description;
  final bool isRead;
  final bool isResolved;
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
    this.isResolved = false,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'id':          id,
    'patientId':   patientId,
    'patientName': patientName,
    'doctorId':    doctorId,
    'alertType':   alertType,
    'severity':    severity,
    'title':       title,
    'description': description,
    'isRead':      isRead,
    'isResolved':  isResolved,
    'createdAt':   Timestamp.fromDate(createdAt),
  };

  factory CriticalAlert.fromMap(Map<String, dynamic> m) => CriticalAlert(
    id:          m['id'] ?? '',
    patientId:   m['patientId'] ?? '',
    patientName: m['patientName'] ?? '',
    doctorId:    m['doctorId'] ?? '',
    alertType:   m['alertType'] ?? '',
    severity:    m['severity'] ?? 'medium',
    title:       m['title'] ?? '',
    description: m['description'] ?? '',
    isRead:      m['isRead'] ?? false,
    isResolved:  m['isResolved'] ?? false,
    createdAt:   m['createdAt'] != null
        ? (m['createdAt'] as Timestamp).toDate()
        : DateTime.now(),
  );

  CriticalAlert copyWith({bool? isRead, bool? isResolved}) => CriticalAlert(
    id: id, patientId: patientId, patientName: patientName,
    doctorId: doctorId, alertType: alertType, severity: severity,
    title: title, description: description,
    isRead: isRead ?? this.isRead,
    isResolved: isResolved ?? this.isResolved,
    createdAt: createdAt,
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