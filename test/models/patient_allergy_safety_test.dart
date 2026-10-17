// test/models/patient_allergy_safety_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:oncovault/models/patient_profile_model.dart';

void main() {
  group('Clinical Allergy Safety Tests (3 Distinct States)', () {
    test('State 1 — Confirmed known allergies: returns confirmedKnown and extracts active allergens', () {
      final profile = PatientProfile(
        uid: 'p-1',
        name: 'John Doe',
        email: 'john@example.com',
        medicalId: 'OV-001',
        allergies: ['Penicillin', 'Sulfa drugs', 'Latex'],
      );

      expect(profile.allergyStatus, PatientAllergyStatus.confirmedKnown);
      expect(profile.confirmedAllergies, equals(['Penicillin', 'Sulfa drugs', 'Latex']));
    });

    test('State 2 — Explicitly confirmed no known allergies via hasNoKnownAllergies flag', () {
      final profile = PatientProfile(
        uid: 'p-2',
        name: 'Jane Doe',
        email: 'jane@example.com',
        medicalId: 'OV-002',
        hasNoKnownAllergies: true,
      );

      expect(profile.allergyStatus, PatientAllergyStatus.confirmedNone);
      expect(profile.confirmedAllergies, isEmpty);
    });

    test('State 2 — Explicitly confirmed no known allergies via explicit NKDA token in list', () {
      final profile1 = PatientProfile(
        uid: 'p-3a',
        name: 'Alice',
        email: 'alice@example.com',
        medicalId: 'OV-003a',
        allergies: ['NKDA'],
      );
      final profile2 = PatientProfile(
        uid: 'p-3b',
        name: 'Bob',
        email: 'bob@example.com',
        medicalId: 'OV-003b',
        allergies: ['No Known Drug Allergies'],
      );
      final profile3 = PatientProfile(
        uid: 'p-3c',
        name: 'Charlie',
        email: 'charlie@example.com',
        medicalId: 'OV-003c',
        allergies: ['none'],
      );

      expect(profile1.allergyStatus, PatientAllergyStatus.confirmedNone);
      expect(profile2.allergyStatus, PatientAllergyStatus.confirmedNone);
      expect(profile3.allergyStatus, PatientAllergyStatus.confirmedNone);
      expect(profile1.confirmedAllergies, isEmpty);
    });

    test('State 3 — Missing, unknown, or unrecorded data: NEVER inferred as NKDA', () {
      // Null allergies field
      final profileNull = PatientProfile(
        uid: 'p-4a',
        name: 'David',
        email: 'david@example.com',
        medicalId: 'OV-004a',
        allergies: null,
      );
      // Empty list without explicit confirmation
      final profileEmpty = PatientProfile(
        uid: 'p-4b',
        name: 'Emma',
        email: 'emma@example.com',
        medicalId: 'OV-004b',
        allergies: [],
      );
      // List with only whitespace
      final profileWhitespace = PatientProfile(
        uid: 'p-4c',
        name: 'Frank',
        email: 'frank@example.com',
        medicalId: 'OV-004c',
        allergies: ['   ', ''],
      );

      expect(profileNull.allergyStatus, PatientAllergyStatus.notRecorded);
      expect(profileEmpty.allergyStatus, PatientAllergyStatus.notRecorded);
      expect(profileWhitespace.allergyStatus, PatientAllergyStatus.notRecorded);
      expect(profileNull.confirmedAllergies, isEmpty);
    });

    test('Serialization round-trip preserves explicit allergy states accurately', () {
      final mapWithAllergens = {
        'uid': 'p-5',
        'name': 'Grace',
        'email': 'grace@example.com',
        'medicalId': 'OV-005',
        'allergies': ['Aspirin'],
      };
      final p1 = PatientProfile.fromMap(mapWithAllergens);
      expect(p1.allergyStatus, PatientAllergyStatus.confirmedKnown);
      expect(p1.confirmedAllergies, ['Aspirin']);

      final mapWithNkda = {
        'uid': 'p-6',
        'name': 'Henry',
        'email': 'henry@example.com',
        'medicalId': 'OV-006',
        'hasNoKnownAllergies': true,
      };
      final p2 = PatientProfile.fromMap(mapWithNkda);
      expect(p2.allergyStatus, PatientAllergyStatus.confirmedNone);

      final mapWithoutField = {
        'uid': 'p-7',
        'name': 'Isabel',
        'email': 'isabel@example.com',
        'medicalId': 'OV-007',
      };
      final p3 = PatientProfile.fromMap(mapWithoutField);
      expect(p3.allergyStatus, PatientAllergyStatus.notRecorded);
    });
  });
}
