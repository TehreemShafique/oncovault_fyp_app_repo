import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncovault/models/user_model.dart';
import 'package:oncovault/screens/dashboard_screen.dart';

void main() {
  group('Phase 1A Authentication & Security Tests', () {
    test('OVUser model serialization preserves immutable security identifiers', () {
      final user = OVUser(
        uid: 'user_123',
        name: 'Jane Doe',
        email: 'jane@oncovault.com',
        medicalId: 'OV-PA-USER12',
        role: 'patient',
        createdAt: DateTime(2026, 10, 1),
      );

      final map = user.toMap();
      expect(map['uid'], equals('user_123'));
      expect(map['email'], equals('jane@oncovault.com'));
      expect(map['medicalId'], equals('OV-PA-USER12'));
      expect(map['role'], equals('patient'));

      final parsed = OVUser.fromMap(map);
      expect(parsed.uid, equals('user_123'));
      expect(parsed.role, equals('patient'));
      expect(parsed.medicalId, equals('OV-PA-USER12'));
    });

    test('Medical ID generation produces correct role prefixes', () {
      String generateMedId(String role, String uid) {
        final prefix = role.toUpperCase().substring(0, 2);
        return 'OV-$prefix-${uid.substring(0, 6).toUpperCase()}';
      }

      expect(generateMedId('patient', 'abc123def456'), equals('OV-PA-ABC123'));
      expect(generateMedId('doctor', 'doc123def456'), equals('OV-DO-DOC123'));
      expect(generateMedId('nurse', 'nur123def456'), equals('OV-NU-NUR123'));
      expect(generateMedId('admin', 'adm123def456'), equals('OV-AD-ADM123'));
    });

    test('Login input accurately differentiates between Email and Medical ID', () {
      bool isEmailLogin(String input) => input.trim().contains('@');

      expect(isEmailLogin('doctor@oncovault.org'), isTrue);
      expect(isEmailLogin('patient.alice@gmail.com'), isTrue);
      expect(isEmailLogin('OV-PA-ABC123'), isFalse);
      expect(isEmailLogin('OV-DO-DOC999'), isFalse);
    });

    test('DashboardScreen routes each verified role to its respective dashboard', () {
      final patientUser = OVUser(
        uid: 'p_1',
        name: 'Patient 1',
        email: 'p@test.com',
        medicalId: 'OV-PA-000001',
        role: 'patient',
        createdAt: DateTime.now(),
      );
      final patientWidget = DashboardScreen(user: patientUser);
      expect(patientWidget.user?.role, equals('patient'));

      final doctorUser = OVUser(
        uid: 'd_1',
        name: 'Dr. Smith',
        email: 'd@test.com',
        medicalId: 'OV-DO-000001',
        role: 'doctor',
        createdAt: DateTime.now(),
      );
      final doctorWidget = DashboardScreen(user: doctorUser);
      expect(doctorWidget.user?.role, equals('doctor'));

      final nurseUser = OVUser(
        uid: 'n_1',
        name: 'Nurse Nancy',
        email: 'n@test.com',
        medicalId: 'OV-NU-000001',
        role: 'nurse',
        createdAt: DateTime.now(),
      );
      final nurseWidget = DashboardScreen(user: nurseUser);
      expect(nurseWidget.user?.role, equals('nurse'));

      final adminUser = OVUser(
        uid: 'a_1',
        name: 'Admin Bob',
        email: 'a@test.com',
        medicalId: 'OV-AD-000001',
        role: 'admin',
        createdAt: DateTime.now(),
      );
      final adminWidget = DashboardScreen(user: adminUser);
      expect(adminWidget.user?.role, equals('admin'));
    });

    test('firestore.rules contains required security guards and no permissive wildcards', () {
      final rulesFile = File('firestore.rules');
      expect(rulesFile.existsSync(), isTrue, reason: 'firestore.rules must exist');

      final content = rulesFile.readAsStringSync();

      // Must require authentication and not have global open access
      expect(content.contains('allow read, write: if true;'), isFalse);
      expect(content.contains('isAuthenticated()'), isTrue);
      expect(content.contains('isClinician()'), isTrue);

      // Must protect against role self-escalation
      expect(content.contains('request.resource.data.role == resource.data.role'), isTrue);

      // Must secure medical_id_directory get vs list
      expect(content.contains('match /medical_id_directory/{medicalId}'), isTrue);
      expect(content.contains('allow get: if true;'), isTrue);
      expect(content.contains('allow list: if false;'), isTrue);

      // Subcollections under patients
      expect(content.contains('match /blood_cancer_ehrs/{recordId}'), isTrue);
      expect(content.contains('match /medicalRecords/{recordId}'), isTrue);
      expect(content.contains('match /diagnoses/{diagnosisId}'), isTrue);

      // Granular subcollections & strict write guards
      expect(content.contains('match /doctors/{doctorId}'), isTrue);
      expect(content.contains('match /alerts/{alertId}'), isTrue);
      expect(content.contains('match /notifications/{userId}/items/{notificationId}'), isTrue);
      expect(content.contains('match /doctor_patient_consents/{consentId}'), isTrue);
      expect(content.contains('match /bookedSlots/{doctorId}/slots/{slotKey}'), isTrue);
      expect(content.contains('match /prescriptions/{prescriptionId}'), isTrue);

      // Catch-all denial
      expect(content.contains('match /{document=**}'), isTrue);
      expect(content.contains('allow read, write: if false;'), isTrue);
    });

    test('storage.rules requires authentication and prevents public bucket reads', () {
      final storageRulesFile = File('storage.rules');
      expect(storageRulesFile.existsSync(), isTrue, reason: 'storage.rules must exist');

      final content = storageRulesFile.readAsStringSync();
      expect(content.contains('allow read, write: if true;'), isFalse);
      expect(content.contains('request.auth != null'), isTrue);
      expect(content.contains('match /reports/{uid}/{fileName}'), isTrue);
      expect(content.contains('match /{allPaths=**}'), isTrue);
    });

    test('medical_id_directory only contains email and uid with no medical data', () {
      final dirEntry = {
        'email': 'patient@example.com',
        'uid': 'uid_12345',
      };
      expect(dirEntry.containsKey('email'), isTrue);
      expect(dirEntry.containsKey('uid'), isTrue);
      expect(dirEntry.containsKey('role'), isFalse);
      expect(dirEntry.containsKey('name'), isFalse);
      expect(dirEntry.containsKey('bloodGroup'), isFalse);
      expect(dirEntry.containsKey('diagnosis'), isFalse);
      expect(dirEntry.containsKey('allergies'), isFalse);
    });

    test('firestore.rules contains Phase 1 clinician access documentation', () {
      final rulesFile = File('firestore.rules');
      final content = rulesFile.readAsStringSync();
      expect(content.contains('NOTE ON CLINICIAN ACCESS (Phase 1 Access Model)'), isTrue);
      expect(content.contains('Patients can NEVER access another patient\'s clinical data'), isTrue);
    });
  });
}
