// lib/models/vital_sign_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

/// Clinical severity classification of a vital-sign reading.
enum VitalSignSeverity {
  normal,
  warning,
  critical,
}

extension VitalSignSeverityX on VitalSignSeverity {
  String get label {
    switch (this) {
      case VitalSignSeverity.normal:
        return 'Normal';
      case VitalSignSeverity.warning:
        return 'Warning';
      case VitalSignSeverity.critical:
        return 'Critical';
    }
  }
}

/// Canonical, immutable data model representing a single clinical vital-sign observation.
/// Stored in Firestore under: `ehr_vitals/{patientId}/observations/{observationId}`.
class VitalSignModel {
  final String id;
  final String patientId;
  final String nurseId;
  final String nurseName;
  final String? recordedBy;
  final String? recordedByName;
  final String? recordedByRole;
  final String? doctorId;
  final String? doctorName;
  final DateTime recordedAt;

  // Primary Clinical Measurements
  final double systolicBp;       // mmHg (permissible: 60 - 250)
  final double diastolicBp;      // mmHg (permissible: 40 - 140)
  final double pulseRate;        // bpm (permissible: 30 - 220)
  final double temperature;      // Canonical value in °C (permissible: 32.0 - 43.0 °C)
  final String temperatureUnit;  // 'C' or 'F' (unit selected at point of entry)
  final double respiratoryRate;  // breaths/min (permissible: 6 - 60)
  final double oxygenSaturation;  // SpO2 % (permissible: 50 - 100)

  // Optional Supportive Measurements
  final double? weightKg;        // Optional body weight in kg
  final double? heightCm;        // Optional height in cm
  final String notes;            // Optional clinical intake notes

  // Classification & Warning Flags
  final bool isCritical;
  final List<String> warningFlags;   // Explanations for values outside reference range
  final List<String> criticalReasons; // Explanations if flagged as critical emergency
  final VitalSignSeverity severity;

  const VitalSignModel({
    required this.id,
    required this.patientId,
    this.nurseId = '',
    this.nurseName = '',
    this.recordedBy,
    this.recordedByName,
    this.recordedByRole,
    this.doctorId,
    this.doctorName,
    required this.recordedAt,
    required this.systolicBp,
    required this.diastolicBp,
    required this.pulseRate,
    required this.temperature,
    this.temperatureUnit = 'C',
    required this.respiratoryRate,
    required this.oxygenSaturation,
    this.weightKg,
    this.heightCm,
    this.notes = '',
    this.isCritical = false,
    this.warningFlags = const [],
    this.criticalReasons = const [],
    this.severity = VitalSignSeverity.normal,
  });

  /// User-facing display name of the clinician who recorded the observation.
  String get recordedByDisplayName {
    if (recordedByName != null && recordedByName!.isNotEmpty) return recordedByName!;
    if (doctorName != null && doctorName!.isNotEmpty) return doctorName!;
    if (nurseName.isNotEmpty) return nurseName;
    return 'Clinician';
  }

  /// Whether this observation was recorded by an attending physician.
  bool get isRecordedByDoctor =>
      recordedByRole == 'doctor' || (doctorId != null && doctorId!.isNotEmpty);

  /// Displays blood pressure in canonical "120/80 mmHg" string format.
  String get bloodPressureDisplay =>
      '${systolicBp.toStringAsFixed(0)}/${diastolicBp.toStringAsFixed(0)} mmHg';

  /// Canonical temperature in Celsius (°C).
  double get temperatureCelsius => temperature;

  /// Temperature converted to Fahrenheit (°F).
  double get temperatureFahrenheit => (temperature * 9.0 / 5.0) + 32.0;

  /// Displays temperature in Celsius and Fahrenheit: e.g. "37.0 °C (98.6 °F)".
  String get temperatureDisplay {
    final tempC = temperature;
    final tempF = temperatureFahrenheit;
    if (temperatureUnit == 'F') {
      return '${tempF.toStringAsFixed(1)} °F (${tempC.toStringAsFixed(1)} °C)';
    }
    return '${tempC.toStringAsFixed(1)} °C (${tempF.toStringAsFixed(1)} °F)';
  }

  /// Calculates Body Mass Index (BMI) if weight and height are provided.
  double? get bmi {
    if (weightKg != null && heightCm != null && heightCm! > 0) {
      final heightM = heightCm! / 100.0;
      return double.parse((weightKg! / (heightM * heightM)).toStringAsFixed(1));
    }
    return null;
  }

  /// Serializes the observation to a Map for Firestore persistence in:
  /// `ehr_vitals/{patientId}/observations/{observationId}`.
  Map<String, dynamic> toMap() => {
    'id': id,
    'patientId': patientId,
    'recordedBy': recordedBy ?? (doctorId ?? nurseId),
    'recordedByName': recordedByName ?? (doctorName ?? nurseName),
    'recordedByRole': recordedByRole ?? (doctorId != null ? 'doctor' : 'nurse'),
    if (nurseId.isNotEmpty) 'nurseId': nurseId,
    if (nurseName.isNotEmpty) 'nurseName': nurseName,
    if (doctorId != null && doctorId!.isNotEmpty) 'doctorId': doctorId,
    if (doctorName != null && doctorName!.isNotEmpty) 'doctorName': doctorName,
    'recordedAt': Timestamp.fromDate(recordedAt),
    'systolicBp': systolicBp,
    'diastolicBp': diastolicBp,
    'pulseRate': pulseRate,
    'temperature': temperature,
    'temperatureUnit': temperatureUnit,
    'respiratoryRate': respiratoryRate,
    'oxygenSaturation': oxygenSaturation,
    'weightKg': weightKg,
    'heightCm': heightCm,
    'notes': notes,
    'isCritical': isCritical,
    'warningFlags': warningFlags,
    'criticalReasons': criticalReasons,
    'severity': severity.name,
  };

  /// Serializes into the flat legacy cache structure for `/ehr_vitals/{patientId}`.
  /// Fully preserves backward compatibility with `DoctorService.fetchEhrVitals` and `_VitalsGrid`.
  Map<String, dynamic> toLatestSummaryMap() => {
    'latestObservationId': id,
    'recordedBy': recordedBy ?? (doctorId ?? nurseId),
    'recordedByName': recordedByName ?? (doctorName ?? nurseName),
    'recordedByRole': recordedByRole ?? (doctorId != null ? 'doctor' : 'nurse'),
    if (nurseId.isNotEmpty) 'lastNurseId': nurseId,
    if (nurseName.isNotEmpty) 'lastNurseName': nurseName,
    if (doctorId != null && doctorId!.isNotEmpty) 'lastDoctorId': doctorId,
    if (doctorName != null && doctorName!.isNotEmpty) 'lastDoctorName': doctorName,
    'updatedAt': Timestamp.fromDate(recordedAt),
    'recordedAt': Timestamp.fromDate(recordedAt),
    'bloodPressure': bloodPressureDisplay,
    'systolicBp': systolicBp,
    'diastolicBp': diastolicBp,
    'heartRate': pulseRate.round(),
    'pulseRate': pulseRate,
    'temperature': temperature,
    'temperatureDisplay': temperatureDisplay,
    'respiratoryRate': respiratoryRate.round(),
    'oxygenSaturation': oxygenSaturation.round(),
    'weight': weightKg,
    'weightKg': weightKg,
    'heightCm': heightCm,
    'bmi': bmi,
    'isCritical': isCritical,
    'severity': severity.name,
    'warningFlags': warningFlags,
    'criticalReasons': criticalReasons,
    'notes': notes,
  };

  factory VitalSignModel.fromMap(Map<String, dynamic> m, {String? docId}) {
    DateTime parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      return DateTime.now();
    }

    double parseDouble(dynamic val, [double defaultVal = 0.0]) {
      if (val == null) return defaultVal;
      if (val is num) return val.toDouble();
      if (val is String) return double.tryParse(val) ?? defaultVal;
      return defaultVal;
    }

    final sevStr = m['severity'] as String? ?? 'normal';
    final severity = VitalSignSeverity.values.firstWhere(
      (e) => e.name == sevStr,
      orElse: () => (m['isCritical'] == true) ? VitalSignSeverity.critical : VitalSignSeverity.normal,
    );

    final recBy = m['recordedBy'] as String?;
    final recByName = m['recordedByName'] as String?;
    final recRole = m['recordedByRole'] as String?;
    final mDoctorId = m['doctorId'] as String? ?? m['lastDoctorId'] as String?;
    final mDoctorName = m['doctorName'] as String? ?? m['lastDoctorName'] as String?;
    final nId = m['nurseId'] as String? ?? (m['lastNurseId'] as String? ?? (recRole == 'doctor' ? '' : (recBy ?? '')));
    final nName = m['nurseName'] as String? ?? (m['lastNurseName'] as String? ?? (recRole == 'doctor' ? '' : (recByName ?? '')));

    return VitalSignModel(
      id: (docId != null && docId.isNotEmpty) ? docId : (m['id'] as String? ?? ''),
      patientId: m['patientId'] as String? ?? '',
      nurseId: nId,
      nurseName: nName,
      recordedBy: recBy,
      recordedByName: recByName,
      recordedByRole: recRole,
      doctorId: mDoctorId,
      doctorName: mDoctorName,
      recordedAt: parseDate(m['recordedAt'] ?? m['updatedAt']),
      systolicBp: parseDouble(m['systolicBp'], 120.0),
      diastolicBp: parseDouble(m['diastolicBp'], 80.0),
      pulseRate: parseDouble(m['pulseRate'] ?? m['heartRate'], 72.0),
      temperature: parseDouble(m['temperature'], 37.0),
      temperatureUnit: m['temperatureUnit'] as String? ?? 'C',
      respiratoryRate: parseDouble(m['respiratoryRate'], 16.0),
      oxygenSaturation: parseDouble(m['oxygenSaturation'], 98.0),
      weightKg: m['weightKg'] != null ? parseDouble(m['weightKg']) : (m['weight'] != null ? parseDouble(m['weight']) : null),
      heightCm: m['heightCm'] != null ? parseDouble(m['heightCm']) : null,
      notes: m['notes'] as String? ?? '',
      isCritical: m['isCritical'] as bool? ?? false,
      warningFlags: List<String>.from(m['warningFlags'] ?? []),
      criticalReasons: List<String>.from(m['criticalReasons'] ?? []),
      severity: severity,
    );
  }

  VitalSignModel copyWith({
    String? id,
    String? patientId,
    String? nurseId,
    String? nurseName,
    String? recordedBy,
    String? recordedByName,
    String? recordedByRole,
    String? doctorId,
    String? doctorName,
    DateTime? recordedAt,
    double? systolicBp,
    double? diastolicBp,
    double? pulseRate,
    double? temperature,
    String? temperatureUnit,
    double? respiratoryRate,
    double? oxygenSaturation,
    double? weightKg,
    double? heightCm,
    String? notes,
    bool? isCritical,
    List<String>? warningFlags,
    List<String>? criticalReasons,
    VitalSignSeverity? severity,
  }) =>
      VitalSignModel(
        id: id ?? this.id,
        patientId: patientId ?? this.patientId,
        nurseId: nurseId ?? this.nurseId,
        nurseName: nurseName ?? this.nurseName,
        recordedBy: recordedBy ?? this.recordedBy,
        recordedByName: recordedByName ?? this.recordedByName,
        recordedByRole: recordedByRole ?? this.recordedByRole,
        doctorId: doctorId ?? this.doctorId,
        doctorName: doctorName ?? this.doctorName,
        recordedAt: recordedAt ?? this.recordedAt,
        systolicBp: systolicBp ?? this.systolicBp,
        diastolicBp: diastolicBp ?? this.diastolicBp,
        pulseRate: pulseRate ?? this.pulseRate,
        temperature: temperature ?? this.temperature,
        temperatureUnit: temperatureUnit ?? this.temperatureUnit,
        respiratoryRate: respiratoryRate ?? this.respiratoryRate,
        oxygenSaturation: oxygenSaturation ?? this.oxygenSaturation,
        weightKg: weightKg ?? this.weightKg,
        heightCm: heightCm ?? this.heightCm,
        notes: notes ?? this.notes,
        isCritical: isCritical ?? this.isCritical,
        warningFlags: warningFlags ?? this.warningFlags,
        criticalReasons: criticalReasons ?? this.criticalReasons,
        severity: severity ?? this.severity,
      );
}
