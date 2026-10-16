// test/vital_validator_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:oncovault/models/vital_sign_model.dart';
import 'package:oncovault/utils/vital_validator.dart';

void main() {
  group('VitalValidator Clinical Bounds & Unit Conversion Tests', () {
    test('Temperature conversion between Celsius and Fahrenheit', () {
      expect(VitalValidator.celsiusToFahrenheit(37.0), closeTo(98.6, 0.01));
      expect(VitalValidator.celsiusToFahrenheit(0.0), closeTo(32.0, 0.01));
      expect(VitalValidator.celsiusToFahrenheit(100.0), closeTo(212.0, 0.01));

      expect(VitalValidator.fahrenheitToCelsius(98.6), closeTo(37.0, 0.01));
      expect(VitalValidator.fahrenheitToCelsius(32.0), closeTo(0.0, 0.01));
    });

    group('Permissible Input Range Validations', () {
      test('validateSystolic rejects out-of-bound (<60 or >250) or malformed inputs', () {
        expect(VitalValidator.validateSystolic(null).isValid, isFalse);
        expect(VitalValidator.validateSystolic('').isValid, isFalse);
        expect(VitalValidator.validateSystolic('abc').isValid, isFalse);
        expect(VitalValidator.validateSystolic('59').isValid, isFalse);
        expect(VitalValidator.validateSystolic('251').isValid, isFalse);

        expect(VitalValidator.validateSystolic('60').isValid, isTrue);
        expect(VitalValidator.validateSystolic('120').isValid, isTrue);
        expect(VitalValidator.validateSystolic('250').isValid, isTrue);
      });

      test('validateDiastolic rejects out-of-bound (<40 or >140) or >= systolic', () {
        expect(VitalValidator.validateDiastolic(null).isValid, isFalse);
        expect(VitalValidator.validateDiastolic('39').isValid, isFalse);
        expect(VitalValidator.validateDiastolic('141').isValid, isFalse);
        expect(VitalValidator.validateDiastolic('80', systolicVal: 80).isValid, isFalse);
        expect(VitalValidator.validateDiastolic('90', systolicVal: 85).isValid, isFalse);

        expect(VitalValidator.validateDiastolic('40').isValid, isTrue);
        expect(VitalValidator.validateDiastolic('80', systolicVal: 120).isValid, isTrue);
        expect(VitalValidator.validateDiastolic('140', systolicVal: 150).isValid, isTrue);
      });

      test('validatePulse rejects out-of-bound (<30 or >220)', () {
        expect(VitalValidator.validatePulse('29').isValid, isFalse);
        expect(VitalValidator.validatePulse('221').isValid, isFalse);

        expect(VitalValidator.validatePulse('30').isValid, isTrue);
        expect(VitalValidator.validatePulse('72').isValid, isTrue);
        expect(VitalValidator.validatePulse('220').isValid, isTrue);
      });

      test('validateTemperature enforces 32.0–43.0 °C and equivalent in °F', () {
        expect(VitalValidator.validateTemperature('31.9', unit: 'C').isValid, isFalse);
        expect(VitalValidator.validateTemperature('43.1', unit: 'C').isValid, isFalse);
        expect(VitalValidator.validateTemperature('37.0', unit: 'C').isValid, isTrue);

        // In Fahrenheit (32 C = 89.6 F, 43 C = 109.4 F)
        expect(VitalValidator.validateTemperature('89.0', unit: 'F').isValid, isFalse);
        expect(VitalValidator.validateTemperature('110.0', unit: 'F').isValid, isFalse);
        expect(VitalValidator.validateTemperature('98.6', unit: 'F').isValid, isTrue);
      });

      test('validateRespiratory rejects out-of-bound (<6 or >60)', () {
        expect(VitalValidator.validateRespiratory('5').isValid, isFalse);
        expect(VitalValidator.validateRespiratory('61').isValid, isFalse);

        expect(VitalValidator.validateRespiratory('6').isValid, isTrue);
        expect(VitalValidator.validateRespiratory('16').isValid, isTrue);
        expect(VitalValidator.validateRespiratory('60').isValid, isTrue);
      });

      test('validateOxygenSaturation rejects out-of-bound (<50 or >100)', () {
        expect(VitalValidator.validateOxygenSaturation('49').isValid, isFalse);
        expect(VitalValidator.validateOxygenSaturation('101').isValid, isFalse);

        expect(VitalValidator.validateOxygenSaturation('50').isValid, isTrue);
        expect(VitalValidator.validateOxygenSaturation('98').isValid, isTrue);
        expect(VitalValidator.validateOxygenSaturation('100').isValid, isTrue);
      });
    });

    group('Clinical Reference Assessment & Severity Classification', () {
      test('Normal healthy vitals produce normal severity with zero warnings or critical flags', () {
        final result = VitalValidator.assessVitals(
          systolicBp: 118.0,
          diastolicBp: 78.0,
          pulseRate: 72.0,
          temperatureC: 36.8,
          respiratoryRate: 16.0,
          oxygenSaturation: 99.0,
        );

        expect(result.severity, equals(VitalSignSeverity.normal));
        expect(result.isCritical, isFalse);
        expect(result.warnings, isEmpty);
        expect(result.criticalReasons, isEmpty);
      });

      test('Mildly abnormal values produce warning status without escalating to critical emergency', () {
        final result = VitalValidator.assessVitals(
          systolicBp: 135.0, // Pre-hypertension warning
          diastolicBp: 85.0,
          pulseRate: 105.0,  // Mild tachycardia warning
          temperatureC: 37.8, // Low-grade elevation
          respiratoryRate: 22.0, // Mild elevation
          oxygenSaturation: 93.0, // Mild hypoxia
        );

        expect(result.severity, equals(VitalSignSeverity.warning));
        expect(result.isCritical, isFalse);
        expect(result.warnings, isNotEmpty);
        expect(result.criticalReasons, isEmpty);
        expect(result.warnings.any((w) => w.contains('Pre-hypertension')), isTrue);
        expect(result.warnings.any((w) => w.contains('Tachycardia')), isTrue);
      });

      test('Hypertensive crisis (BP >= 180/120) triggers critical classification', () {
        final result = VitalValidator.assessVitals(
          systolicBp: 185.0,
          diastolicBp: 122.0,
          pulseRate: 80.0,
          temperatureC: 37.0,
          respiratoryRate: 16.0,
          oxygenSaturation: 98.0,
        );

        expect(result.severity, equals(VitalSignSeverity.critical));
        expect(result.isCritical, isTrue);
        expect(result.criticalReasons.any((r) => r.contains('Hypertensive Crisis')), isTrue);
      });

      test('Neutropenic high fever (>= 38.5 C) in blood cancer triggers critical classification', () {
        final result = VitalValidator.assessVitals(
          systolicBp: 115.0,
          diastolicBp: 75.0,
          pulseRate: 90.0,
          temperatureC: 39.2, // High fever
          respiratoryRate: 18.0,
          oxygenSaturation: 97.0,
        );

        expect(result.severity, equals(VitalSignSeverity.critical));
        expect(result.isCritical, isTrue);
        expect(result.criticalReasons.any((r) => r.contains('Febrile Alert')), isTrue);
      });

      test('Severe hypoxemia (SpO2 < 90%) triggers critical classification', () {
        final result = VitalValidator.assessVitals(
          systolicBp: 120.0,
          diastolicBp: 80.0,
          pulseRate: 95.0,
          temperatureC: 37.0,
          respiratoryRate: 24.0,
          oxygenSaturation: 87.0, // Severe hypoxemia
        );

        expect(result.severity, equals(VitalSignSeverity.critical));
        expect(result.isCritical, isTrue);
        expect(result.criticalReasons.any((r) => r.contains('Severe Hypoxemia')), isTrue);
      });
    });
  });
}
