// lib/models/patient_profile_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class PatientProfile {
  final String uid;
  final String name;
  final String email;
  final String medicalId;
  final String phone;
  final String address;
  final String gender;
  final DateTime? dateOfBirth;
  final String bloodType;
  final List<String> allergies;
  final String profileImageUrl;
  final String activeDiagnosis;
  final String diagnosisPhase;
  final DateTime? diagnosisStartDate;
  final int diagnosisDurationWeeks;

  PatientProfile({
    required this.uid,
    required this.name,
    required this.email,
    required this.medicalId,
    this.phone = '',
    this.address = '',
    this.gender = '',
    this.dateOfBirth,
    this.bloodType = '',
    this.allergies = const [],
    this.profileImageUrl = '',
    this.activeDiagnosis = '',
    this.diagnosisPhase = '',
    this.diagnosisStartDate,
    this.diagnosisDurationWeeks = 0,
  });

  int? get age {
    if (dateOfBirth == null) return null;
    final now = DateTime.now();
    int age = now.year - dateOfBirth!.year;
    if (now.month < dateOfBirth!.month ||
        (now.month == dateOfBirth!.month && now.day < dateOfBirth!.day)) age--;
    return age;
  }

  Map<String, dynamic> toMap() => {
    'uid':                    uid,
    'name':                   name,
    'email':                  email,
    'medicalId':              medicalId,
    'phone':                  phone,
    'address':                address,
    'gender':                 gender,
    'dateOfBirth':            dateOfBirth != null ? Timestamp.fromDate(dateOfBirth!) : null,
    'bloodType':              bloodType,
    'allergies':              allergies,
    'profileImageUrl':        profileImageUrl,
    'activeDiagnosis':        activeDiagnosis,
    'diagnosisPhase':         diagnosisPhase,
    'diagnosisStartDate':     diagnosisStartDate != null ? Timestamp.fromDate(diagnosisStartDate!) : null,
    'diagnosisDurationWeeks': diagnosisDurationWeeks,
  };

  factory PatientProfile.fromMap(Map<String, dynamic> m) => PatientProfile(
    uid:                    m['uid'] ?? '',
    name:                   m['name'] ?? '',
    email:                  m['email'] ?? '',
    medicalId:              m['medicalId'] ?? '',
    phone:                  m['phone'] ?? '',
    address:                m['address'] ?? '',
    gender:                 m['gender'] ?? '',
    dateOfBirth:            m['dateOfBirth'] != null ? (m['dateOfBirth'] as Timestamp).toDate() : null,
    bloodType:              m['bloodType'] ?? '',
    allergies:              List<String>.from(m['allergies'] ?? []),
    profileImageUrl:        m['profileImageUrl'] ?? '',
    activeDiagnosis:        m['activeDiagnosis'] ?? '',
    diagnosisPhase:         m['diagnosisPhase'] ?? '',
    diagnosisStartDate:     m['diagnosisStartDate'] != null ? (m['diagnosisStartDate'] as Timestamp).toDate() : null,
    diagnosisDurationWeeks: m['diagnosisDurationWeeks'] ?? 0,
  );

  PatientProfile copyWith({
    String? name, String? phone, String? address, String? gender,
    DateTime? dateOfBirth, String? bloodType, List<String>? allergies,
    String? profileImageUrl, String? activeDiagnosis, String? diagnosisPhase,
    DateTime? diagnosisStartDate, int? diagnosisDurationWeeks,
  }) => PatientProfile(
    uid: uid, name: name ?? this.name, email: email, medicalId: medicalId,
    phone: phone ?? this.phone, address: address ?? this.address,
    gender: gender ?? this.gender, dateOfBirth: dateOfBirth ?? this.dateOfBirth,
    bloodType: bloodType ?? this.bloodType, allergies: allergies ?? this.allergies,
    profileImageUrl: profileImageUrl ?? this.profileImageUrl,
    activeDiagnosis: activeDiagnosis ?? this.activeDiagnosis,
    diagnosisPhase: diagnosisPhase ?? this.diagnosisPhase,
    diagnosisStartDate: diagnosisStartDate ?? this.diagnosisStartDate,
    diagnosisDurationWeeks: diagnosisDurationWeeks ?? this.diagnosisDurationWeeks,
  );
}

// Static doctor data — will be replaced by doctor module later
class DoctorInfo {
  final String id;
  final String name;
  final String specialty;
  final String imageUrl;
  final int experienceYears;
  final String badge;
  final List<String> availableSlots; // e.g. ["09:30 AM", "11:00 AM"]

  const DoctorInfo({
    required this.id,
    required this.name,
    required this.specialty,
    this.imageUrl = '',
    required this.experienceYears,
    this.badge = '',
    this.availableSlots = const [],
  });

  // Placeholder doctors — replace with Firestore query when doctor module is built
  static List<DoctorInfo> get mockDoctors => [
    const DoctorInfo(
      id: 'dr_aris_thorne',
      name: 'Dr. Aris Thorne',
      specialty: 'Senior Oncologist',
      experienceYears: 12,
      badge: 'Highly Recommended',
      availableSlots: ['08:00 AM', '09:30 AM', '11:00 AM', '01:30 PM', '03:00 PM'],
    ),
    const DoctorInfo(
      id: 'dr_elena_vance',
      name: 'Dr. Elena Vance',
      specialty: 'Radiation Specialist',
      experienceYears: 8,
      badge: 'Next Available: Today',
      availableSlots: ['09:30 AM', '11:00 AM', '01:30 PM', '04:30 PM'],
    ),
    const DoctorInfo(
      id: 'dr_julian_marsh',
      name: 'Dr. Julian Marsh',
      specialty: 'Surgical Oncologist',
      experienceYears: 20,
      badge: "Patient's Choice 2023",
      availableSlots: ['08:00 AM', '11:00 AM', '03:00 PM', '04:30 PM'],
    ),
    const DoctorInfo(
      id: 'dr_sarah_jenkins',
      name: 'Dr. Sarah Jenkins',
      specialty: 'Medical Oncologist',
      experienceYears: 15,
      badge: '',
      availableSlots: ['09:30 AM', '01:30 PM', '03:00 PM'],
    ),
  ];
}