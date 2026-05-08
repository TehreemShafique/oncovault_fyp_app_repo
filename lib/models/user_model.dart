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

  factory OVUser.fromMap(Map<String, dynamic> map) => OVUser(
    uid: map['uid'] ?? '',
    name: map['name'] ?? '',
    email: map['email'] ?? '',
    medicalId: map['medicalId'] ?? '',
    role: map['role'] ?? 'patient',
    createdAt: DateTime.parse(map['createdAt'] ?? DateTime.now().toIso8601String()),
  );
}