// lib/utils/vital_validator.dart
import '../models/vital_sign_model.dart';

/// Validation result for individual vital sign input fields.
class VitalValidationResult {
  final bool isValid;
  final String? errorMessage;

  const VitalValidationResult._(this.isValid, this.errorMessage);

  factory VitalValidationResult.valid() => const VitalValidationResult._(true, null);
  factory VitalValidationResult.invalid(String message) => VitalValidationResult._(false, message);
}

/// Clinical assessment result evaluating reference ranges and critical thresholds.
class VitalAssessmentResult {
  final VitalSignSeverity severity;
  final bool isCritical;
  final List<String> warnings;
  final List<String> criticalReasons;

  const VitalAssessmentResult({
    required this.severity,
    required this.isCritical,
    required this.warnings,
    required this.criticalReasons,
  });
}

/// Clinical validation and reference range evaluator for patient vital signs.
/// Strictly implements the permissible input ranges and clinical threshold logic
/// specified in OncoVault SDS (FR-M3.1 / FR3.1).
class VitalValidator {
  // ─── Permissible Input Ranges (Permissible Bounds) ─────────
  static const double minSystolic = 60.0;
  static const double maxSystolic = 250.0;

  static const double minDiastolic = 40.0;
  static const double maxDiastolic = 140.0;

  static const double minPulse = 30.0;
  static const double maxPulse = 220.0;

  static const double minTempC = 32.0;
  static const double maxTempC = 43.0;

  static const double minRespiratory = 6.0;
  static const double maxRespiratory = 60.0;

  static const double minSpo2 = 50.0;
  static const double maxSpo2 = 100.0;

  // ─── Temperature Conversion Utilities ─────────────────────
  static double celsiusToFahrenheit(double c) => (c * 9.0 / 5.0) + 32.0;
  static double fahrenheitToCelsius(double f) => (f - 32.0) * 5.0 / 9.0;

  // ─── Field-Level Input Validation ─────────────────────────

  static VitalValidationResult validateSystolic(String? input) {
    if (input == null || input.trim().isEmpty) {
      return VitalValidationResult.invalid('Systolic BP is required.');
    }
    final val = double.tryParse(input.trim());
    if (val == null) {
      return VitalValidationResult.invalid('Enter a valid numeric systolic BP.');
    }
    if (val < minSystolic || val > maxSystolic) {
      return VitalValidationResult.invalid(
        'Systolic BP must be between ${minSystolic.toInt()} and ${maxSystolic.toInt()} mmHg.',
      );
    }
    return VitalValidationResult.valid();
  }

  static VitalValidationResult validateDiastolic(String? input, {double? systolicVal}) {
    if (input == null || input.trim().isEmpty) {
      return VitalValidationResult.invalid('Diastolic BP is required.');
    }
    final val = double.tryParse(input.trim());
    if (val == null) {
      return VitalValidationResult.invalid('Enter a valid numeric diastolic BP.');
    }
    if (val < minDiastolic || val > maxDiastolic) {
      return VitalValidationResult.invalid(
        'Diastolic BP must be between ${minDiastolic.toInt()} and ${maxDiastolic.toInt()} mmHg.',
      );
    }
    if (systolicVal != null && val >= systolicVal) {
      return VitalValidationResult.invalid('Diastolic BP must be less than Systolic BP.');
    }
    return VitalValidationResult.valid();
  }

  static VitalValidationResult validatePulse(String? input) {
    if (input == null || input.trim().isEmpty) {
      return VitalValidationResult.invalid('Pulse rate is required.');
    }
    final val = double.tryParse(input.trim());
    if (val == null) {
      return VitalValidationResult.invalid('Enter a valid numeric pulse rate.');
    }
    if (val < minPulse || val > maxPulse) {
      return VitalValidationResult.invalid(
        'Pulse rate must be between ${minPulse.toInt()} and ${maxPulse.toInt()} bpm.',
      );
    }
    return VitalValidationResult.valid();
  }

  static VitalValidationResult validateTemperature(String? input, {String unit = 'C'}) {
    if (input == null || input.trim().isEmpty) {
      return VitalValidationResult.invalid('Body temperature is required.');
    }
    final val = double.tryParse(input.trim());
    if (val == null) {
      return VitalValidationResult.invalid('Enter a valid numeric temperature.');
    }

    final tempInC = unit == 'F' ? fahrenheitToCelsius(val) : val;

    if (tempInC < minTempC || tempInC > maxTempC) {
      if (unit == 'F') {
        final minF = celsiusToFahrenheit(minTempC).toStringAsFixed(1);
        final maxF = celsiusToFahrenheit(maxTempC).toStringAsFixed(1);
        return VitalValidationResult.invalid(
          'Temperature must be between $minF and $maxF °F ($minTempC–$maxTempC °C).',
        );
      }
      return VitalValidationResult.invalid(
        'Temperature must be between $minTempC and $maxTempC °C.',
      );
    }
    return VitalValidationResult.valid();
  }

  static VitalValidationResult validateRespiratory(String? input) {
    if (input == null || input.trim().isEmpty) {
      return VitalValidationResult.invalid('Respiratory rate is required.');
    }
    final val = double.tryParse(input.trim());
    if (val == null) {
      return VitalValidationResult.invalid('Enter a valid numeric respiratory rate.');
    }
    if (val < minRespiratory || val > maxRespiratory) {
      return VitalValidationResult.invalid(
        'Respiratory rate must be between ${minRespiratory.toInt()} and ${maxRespiratory.toInt()} breaths/min.',
      );
    }
    return VitalValidationResult.valid();
  }

  static VitalValidationResult validateOxygenSaturation(String? input) {
    if (input == null || input.trim().isEmpty) {
      return VitalValidationResult.invalid('Oxygen saturation (SpO2) is required.');
    }
    final val = double.tryParse(input.trim());
    if (val == null) {
      return VitalValidationResult.invalid('Enter a valid numeric SpO2 percentage.');
    }
    if (val < minSpo2 || val > maxSpo2) {
      return VitalValidationResult.invalid(
        'Oxygen saturation must be between ${minSpo2.toInt()} and ${maxSpo2.toInt()}%.',
      );
    }
    return VitalValidationResult.valid();
  }

  static VitalValidationResult validateWeight(String? input) {
    if (input == null || input.trim().isEmpty) {
      return VitalValidationResult.valid(); // Optional
    }
    final val = double.tryParse(input.trim());
    if (val == null) {
      return VitalValidationResult.invalid('Enter a valid numeric weight in kg.');
    }
    if (val < 1.0 || val > 400.0) {
      return VitalValidationResult.invalid('Weight must be between 1.0 and 400.0 kg.');
    }
    return VitalValidationResult.valid();
  }

  static VitalValidationResult validateHeight(String? input) {
    if (input == null || input.trim().isEmpty) {
      return VitalValidationResult.valid(); // Optional
    }
    final val = double.tryParse(input.trim());
    if (val == null) {
      return VitalValidationResult.invalid('Enter a valid numeric height in cm.');
    }
    if (val < 30.0 || val > 250.0) {
      return VitalValidationResult.invalid('Height must be between 30.0 and 250.0 cm.');
    }
    return VitalValidationResult.valid();
  }

  // ─── Clinical Reference Assessment ─────────────────────────

  /// Evaluates clinical reference ranges and explicit critical thresholds.
  /// Categorizes findings into: Normal, Warning, or Critical.
  static VitalAssessmentResult assessVitals({
    required double systolicBp,
    required double diastolicBp,
    required double pulseRate,
    required double temperatureC,
    required double respiratoryRate,
    required double oxygenSaturation,
  }) {
    final warnings = <String>[];
    final criticalReasons = <String>[];

    // 1. Blood Pressure Evaluation
    if (systolicBp >= 180.0 || diastolicBp >= 120.0) {
      criticalReasons.add('Hypertensive Crisis (BP: ${systolicBp.toInt()}/${diastolicBp.toInt()} mmHg)');
    } else if (systolicBp < 80.0 || diastolicBp < 50.0) {
      criticalReasons.add('Severe Hypotension / Shock Risk (BP: ${systolicBp.toInt()}/${diastolicBp.toInt()} mmHg)');
    } else if (systolicBp >= 140.0 || diastolicBp >= 90.0) {
      warnings.add('Stage 2 Hypertension (BP: ${systolicBp.toInt()}/${diastolicBp.toInt()} mmHg)');
    } else if (systolicBp > 120.0 || diastolicBp > 80.0) {
      warnings.add('Elevated / Pre-hypertension (BP: ${systolicBp.toInt()}/${diastolicBp.toInt()} mmHg)');
    } else if (systolicBp < 90.0 || diastolicBp < 60.0) {
      warnings.add('Mild Hypotension (BP: ${systolicBp.toInt()}/${diastolicBp.toInt()} mmHg)');
    }

    // 2. Pulse Rate Evaluation
    if (pulseRate > 130.0) {
      criticalReasons.add('Severe Tachycardia (${pulseRate.toInt()} bpm)');
    } else if (pulseRate < 45.0) {
      criticalReasons.add('Severe Bradycardia (${pulseRate.toInt()} bpm)');
    } else if (pulseRate > 100.0) {
      warnings.add('Mild Tachycardia (${pulseRate.toInt()} bpm)');
    } else if (pulseRate < 60.0) {
      warnings.add('Mild Bradycardia (${pulseRate.toInt()} bpm)');
    }

    // 3. Temperature Evaluation (Hematologic Oncology Context: Neutropenic Fever)
    if (temperatureC >= 38.5) {
      criticalReasons.add('High Fever / Febrile Alert (${temperatureC.toStringAsFixed(1)} °C)');
    } else if (temperatureC < 35.0) {
      criticalReasons.add('Hypothermia (${temperatureC.toStringAsFixed(1)} °C)');
    } else if (temperatureC >= 37.6) {
      warnings.add('Low-grade Elevation (${temperatureC.toStringAsFixed(1)} °C)');
    } else if (temperatureC < 36.5) {
      warnings.add('Subnormal Temperature (${temperatureC.toStringAsFixed(1)} °C)');
    }

    // 4. Respiratory Rate Evaluation
    if (respiratoryRate >= 30.0) {
      criticalReasons.add('Severe Tachypnea (${respiratoryRate.toInt()} breaths/min)');
    } else if (respiratoryRate < 10.0) {
      criticalReasons.add('Severe Bradypnea (${respiratoryRate.toInt()} breaths/min)');
    } else if (respiratoryRate > 20.0) {
      warnings.add('Elevated Respiratory Rate (${respiratoryRate.toInt()} breaths/min)');
    } else if (respiratoryRate < 12.0) {
      warnings.add('Low Respiratory Rate (${respiratoryRate.toInt()} breaths/min)');
    }

    // 5. Oxygen Saturation (SpO2) Evaluation
    if (oxygenSaturation < 90.0) {
      criticalReasons.add('Severe Hypoxemia (SpO2: ${oxygenSaturation.toInt()}%)');
    } else if (oxygenSaturation < 95.0) {
      warnings.add('Mild Hypoxia (SpO2: ${oxygenSaturation.toInt()}%)');
    }

    final isCritical = criticalReasons.isNotEmpty;
    final severity = isCritical
        ? VitalSignSeverity.critical
        : (warnings.isNotEmpty ? VitalSignSeverity.warning : VitalSignSeverity.normal);

    return VitalAssessmentResult(
      severity: severity,
      isCritical: isCritical,
      warnings: warnings,
      criticalReasons: criticalReasons,
    );
  }
}
