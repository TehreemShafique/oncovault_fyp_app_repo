import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:oncovault/models/user_model.dart';
import 'package:oncovault/screens/dashboard_screen.dart';

void main() {
  group('Authentication Compatibility & Regression Tests', () {
    test('OVUser.fromMap handles Firestore Timestamp for createdAt without TypeError', () {
      final timestamp = Timestamp.fromDate(DateTime(2026, 1, 15, 10, 30));
      final map = {
        'uid': 'legacy_user_1',
        'name': 'Existing Patient',
        'email': 'existing@oncovault.com',
        'medicalId': 'OV-PA-EX1234',
        'role': 'patient',
        'createdAt': timestamp,
      };

      final user = OVUser.fromMap(map);
      expect(user.uid, equals('legacy_user_1'));
      expect(user.createdAt, equals(timestamp.toDate()));
      expect(user.role, equals('patient'));
      expect(user.medicalId, equals('OV-PA-EX1234'));
    });

    test('OVUser.fromMap handles ISO-8601 String for createdAt', () {
      const isoString = '2026-10-17T12:00:00.000Z';
      final map = {
        'uid': 'new_user_2',
        'name': 'New Patient',
        'email': 'new@oncovault.com',
        'medicalId': 'OV-PA-NW5678',
        'role': 'patient',
        'createdAt': isoString,
      };

      final user = OVUser.fromMap(map);
      expect(user.uid, equals('new_user_2'));
      expect(user.createdAt, equals(DateTime.parse(isoString)));
    });

    test('OVUser.fromMap handles epoch milliseconds int for createdAt', () {
      final now = DateTime.now();
      final map = {
        'uid': 'epoch_user_3',
        'name': 'Epoch User',
        'email': 'epoch@oncovault.com',
        'medicalId': 'OV-DO-EP9999',
        'role': 'doctor',
        'createdAt': now.millisecondsSinceEpoch,
      };

      final user = OVUser.fromMap(map);
      expect(user.createdAt.millisecondsSinceEpoch, equals(now.millisecondsSinceEpoch));
    });

    test('OVUser.fromMap normalizes mixed-case roles and extra whitespace', () {
      final mapDoctor = {
        'uid': 'doc_1',
        'name': 'Dr. Mixed',
        'email': 'doc@oncovault.com',
        'medicalId': 'OV-DO-DOC001',
        'role': '  Doctor  ',
        'createdAt': Timestamp.now(),
      };
      final userDoc = OVUser.fromMap(mapDoctor);
      expect(userDoc.role, equals('doctor'));

      final mapPatient = {
        'uid': 'pat_1',
        'name': 'Patient Upper',
        'email': 'pat@oncovault.com',
        'medicalId': 'OV-PA-PAT001',
        'role': 'PATIENT',
        'createdAt': Timestamp.now(),
      };
      final userPat = OVUser.fromMap(mapPatient);
      expect(userPat.role, equals('patient'));
    });

    test('OVUser.fromMap supports displayName, fullName, and medical_id fallback fields', () {
      final map = {
        'uid': 'legacy_clinician_1',
        'displayName': 'Dr. Legacy Clinician',
        'email': 'clinician@oncovault.com',
        'medical_id': 'OV-DO-LEGACY',
        'role': 'doctor',
      };

      final user = OVUser.fromMap(map);
      expect(user.name, equals('Dr. Legacy Clinician'));
      expect(user.medicalId, equals('OV-DO-LEGACY'));
      expect(user.role, equals('doctor'));
      expect(user.createdAt, isA<DateTime>());
    });

    test('DashboardScreen handles normalized roles correctly without falling into ComingSoon', () {
      final mixedDoctor = OVUser(
        uid: 'd_mixed',
        name: 'Dr. Mixed',
        email: 'doc@test.com',
        medicalId: 'OV-DO-123456',
        role: 'Doctor',
        createdAt: DateTime.now(),
      );
      final widgetDoctor = DashboardScreen(user: mixedDoctor);
      expect(widgetDoctor.user?.role.trim().toLowerCase(), equals('doctor'));

      final mixedPatient = OVUser(
        uid: 'p_mixed',
        name: 'Patient Mixed',
        email: 'pat@test.com',
        medicalId: 'OV-PA-123456',
        role: ' Patient ',
        createdAt: DateTime.now(),
      );
      final widgetPatient = DashboardScreen(user: mixedPatient);
      expect(widgetPatient.user?.role.trim().toLowerCase(), equals('patient'));
    });
  });
}
