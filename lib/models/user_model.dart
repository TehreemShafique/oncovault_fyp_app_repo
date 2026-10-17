import 'package:cloud_firestore/cloud_firestore.dart';

class OVUser {
  final String uid;
  final String name;
  final String email;
  final String medicalId;
  final String role; // patient | doctor | nurse | admin
  final DateTime createdAt;

  OVUser({
    required this.uid,
    required this.name,
    required this.email,
    required this.medicalId,
    required this.role,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'uid': uid,
    'name': name,
    'email': email,
    'medicalId': medicalId,
    'role': role,
    'createdAt': createdAt.toIso8601String(),
  };

  static DateTime _parseDate(dynamic val) {
    if (val == null) return DateTime.now();
    if (val is Timestamp) return val.toDate();
    if (val is DateTime) return val;
    if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
    if (val is String) {
      final parsed = DateTime.tryParse(val);
      if (parsed != null) return parsed;
    }
    return DateTime.now();
  }

  factory OVUser.fromMap(Map<String, dynamic> map) => OVUser(
    uid: (map['uid'] ?? '').toString(),
    name: (map['name'] ?? map['displayName'] ?? map['fullName'] ?? '').toString(),
    email: (map['email'] ?? '').toString(),
    medicalId: (map['medicalId'] ?? map['medical_id'] ?? '').toString(),
    role: (map['role'] ?? 'patient').toString().trim().toLowerCase(),
    createdAt: _parseDate(map['createdAt']),
  );
}