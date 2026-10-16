// test/vital_sign_model_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:oncovault/models/vital_sign_model.dart';

void main() {
  group('VitalSignModel Domain & Serialization Tests', () {
    final now = DateTime(2026, 10, 17, 10, 30);

    final sampleModel = VitalSignModel(
      id: 'obs_101',
      patientId: 'patient_001',
      nurseId: 'nurse_001',
      nurseName: 'Nurse Jackie',
      recordedAt: now,
      systolicBp: 120.0,
      diastolicBp: 80.0,
      pulseRate: 72.0,
      temperature: 37.0,
      temperatureUnit: 'C',
      respiratoryRate: 16.0,
      oxygenSaturation: 98.0,
      weightKg: 70.0,
      heightCm: 175.0,
      notes: 'Patient resting comfortably.',
      isCritical: false,
      warningFlags: const [],
      criticalReasons: const [],
      severity: VitalSignSeverity.normal,
    );

    test('Computed properties: bloodPressureDisplay, temperatureDisplay, bmi', () {
      expect(sampleModel.bloodPressureDisplay, equals('120/80 mmHg'));
      expect(sampleModel.temperatureDisplay, contains('37.0 °C'));
      expect(sampleModel.temperatureDisplay, contains('98.6 °F'));
      expect(sampleModel.bmi, equals(22.9)); // 70 / (1.75^2) = 22.857 -> 22.9
    });

    test('Serialization toMap contains all Firestore observation fields', () {
      final map = sampleModel.toMap();
      expect(map['id'], equals('obs_101'));
      expect(map['patientId'], equals('patient_001'));
      expect(map['nurseId'], equals('nurse_001'));
      expect(map['nurseName'], equals('Nurse Jackie'));
      expect(map['recordedAt'], isA<Timestamp>());
      expect(map['systolicBp'], equals(120.0));
      expect(map['diastolicBp'], equals(80.0));
      expect(map['pulseRate'], equals(72.0));
      expect(map['temperature'], equals(37.0));
      expect(map['temperatureUnit'], equals('C'));
      expect(map['respiratoryRate'], equals(16.0));
      expect(map['oxygenSaturation'], equals(98.0));
      expect(map['weightKg'], equals(70.0));
      expect(map['heightCm'], equals(175.0));
      expect(map['notes'], equals('Patient resting comfortably.'));
      expect(map['isCritical'], isFalse);
      expect(map['severity'], equals('normal'));
    });

    test('toLatestSummaryMap satisfies legacy cache format and preserves backward compatibility', () {
      final cache = sampleModel.toLatestSummaryMap();
      expect(cache['latestObservationId'], equals('obs_101'));
      expect(cache['lastNurseId'], equals('nurse_001'));
      expect(cache['bloodPressure'], equals('120/80 mmHg'));
      expect(cache['heartRate'], equals(72));
      expect(cache['temperature'], equals(37.0));
      expect(cache['oxygenSaturation'], equals(98));
      expect(cache['respiratoryRate'], equals(16));
      expect(cache['weight'], equals(70.0));
      expect(cache['bmi'], equals(22.9));
    });

    test('Round-trip deserialization fromMap correctly rebuilds model', () {
      final map = sampleModel.toMap();
      final reconstructed = VitalSignModel.fromMap(map, docId: 'obs_101');

      expect(reconstructed.id, equals('obs_101'));
      expect(reconstructed.patientId, equals('patient_001'));
      expect(reconstructed.nurseId, equals('nurse_001'));
      expect(reconstructed.nurseName, equals('Nurse Jackie'));
      expect(reconstructed.systolicBp, equals(120.0));
      expect(reconstructed.diastolicBp, equals(80.0));
      expect(reconstructed.pulseRate, equals(72.0));
      expect(reconstructed.temperature, equals(37.0));
      expect(reconstructed.respiratoryRate, equals(16.0));
      expect(reconstructed.oxygenSaturation, equals(98.0));
      expect(reconstructed.weightKg, equals(70.0));
      expect(reconstructed.heightCm, equals(175.0));
      expect(reconstructed.isCritical, isFalse);
      expect(reconstructed.severity, equals(VitalSignSeverity.normal));
    });

    test('copyWith produces modified immutable copy', () {
      final modified = sampleModel.copyWith(
        systolicBp: 185.0,
        isCritical: true,
        severity: VitalSignSeverity.critical,
        criticalReasons: ['Hypertensive Crisis (BP: 185/80 mmHg)'],
      );

      expect(modified.id, equals(sampleModel.id));
      expect(modified.systolicBp, equals(185.0));
      expect(modified.isCritical, isTrue);
      expect(modified.severity, equals(VitalSignSeverity.critical));
      expect(modified.criticalReasons.first, contains('Hypertensive Crisis'));
      // Original remains unchanged
      expect(sampleModel.systolicBp, equals(120.0));
      expect(sampleModel.isCritical, isFalse);
    });
  });
}
