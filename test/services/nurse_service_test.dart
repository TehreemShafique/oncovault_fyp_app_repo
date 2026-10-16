// test/services/nurse_service_test.dart
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncovault/models/nurse_assignment_model.dart';
import 'package:oncovault/models/vital_sign_model.dart';
import 'package:oncovault/services/nurse_service.dart';

void main() {
  group('NurseAuthorizationException', () {
    test('instantiates with message, patientId, and nurseId', () {
      const ex = NurseAuthorizationException(
        'Nurse not assigned to patient',
        patientId: 'patient_001',
        nurseId: 'nurse_001',
      );
      expect(ex.message, 'Nurse not assigned to patient');
      expect(ex.patientId, 'patient_001');
      expect(ex.nurseId, 'nurse_001');
      expect(ex.toString(), contains('NurseAuthorizationException'));
      expect(ex.toString(), contains('patient_001'));
    });
  });

  group('NursePatientAssignment', () {
    test('correctly serializes and deserializes', () {
      final now = DateTime.now();
      final assignment = NursePatientAssignment(
        id: 'nurse_123_patient_456',
        nurseId: 'nurse_123',
        nurseName: 'Amina Khan',
        patientId: 'patient_456',
        patientName: 'Bilal Ahmed',
        assignedBy: 'admin_001',
        assignedAt: now,
        status: 'active',
        hospitalId: 'Hematology Ward 3A',
        notes: 'Morning shift',
      );

      final map = assignment.toMap();
      expect(map['nurseId'], 'nurse_123');
      expect(map['patientId'], 'patient_456');
      expect(map['status'], 'active');
      expect(map['hospitalId'], 'Hematology Ward 3A');
      expect(assignment.isActive, isTrue);

      final fromMap = NursePatientAssignment.fromMap(map, docId: 'nurse_123_patient_456');
      expect(fromMap.id, 'nurse_123_patient_456');
      expect(fromMap.nurseName, 'Amina Khan');
      expect(fromMap.patientName, 'Bilal Ahmed');
      expect(fromMap.status, 'active');
      expect(fromMap.isActive, isTrue);
    });

    test('isActive returns false for revoked or completed assignments', () {
      final revoked = NursePatientAssignment(
        id: 'test_revoked',
        nurseId: 'n1',
        nurseName: 'N1',
        patientId: 'p1',
        patientName: 'P1',
        assignedBy: 'admin',
        assignedAt: DateTime.now(),
        status: 'revoked',
      );
      expect(revoked.isActive, isFalse);

      final completed = NursePatientAssignment(
        id: 'test_completed',
        nurseId: 'n1',
        nurseName: 'N1',
        patientId: 'p1',
        patientName: 'P1',
        assignedBy: 'admin',
        assignedAt: DateTime.now(),
        status: 'completed',
      );
      expect(completed.isActive, isFalse);
    });
  });

  group('NurseService Validation & Backward Compatibility', () {
    test('recordVitalObservation rejects client-side out-of-range bounds immediately', () async {
      final service = NurseService();

      // Systolic 20 mmHg is below permissible bound (60-250)
      expect(
        () => service.recordVitalObservation(
          patientId: 'patient_456',
          patientName: 'Bilal Ahmed',
          systolicBp: 20,
          diastolicBp: 80,
          pulseRate: 75,
          temperatureCelsius: 37.0,
          respiratoryRate: 16,
          oxygenSaturation: 98,
        ),
        throwsA(isA<ArgumentError>()),
      );

      // Pulse 250 bpm is above permissible bound (30-220)
      expect(
        () => service.recordVitalObservation(
          patientId: 'patient_456',
          patientName: 'Bilal Ahmed',
          systolicBp: 120,
          diastolicBp: 80,
          pulseRate: 250,
          temperatureCelsius: 37.0,
          respiratoryRate: 16,
          oxygenSaturation: 98,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('toLatestSummaryMap preserves backward-compatible EHR fields', () {
      final obs = VitalSignModel(
        id: 'obs_999',
        patientId: 'p_100',
        nurseId: 'n_200',
        nurseName: 'Nurse Sara',
        recordedAt: DateTime(2026, 10, 16, 14, 30),
        systolicBp: 125,
        diastolicBp: 82,
        pulseRate: 74,
        temperature: 37.1,
        temperatureUnit: 'C',
        respiratoryRate: 17,
        oxygenSaturation: 99,
        weightKg: 68.5,
        heightCm: 172.0,
        notes: 'Routine checkup',
        warningFlags: [],
        criticalReasons: [],
        severity: VitalSignSeverity.normal,
      );

      final summary = obs.toLatestSummaryMap();
      expect(summary['bloodPressure'], '125/82 mmHg');
      expect(summary['heartRate'], 74);
      expect(summary['temperature'], 37.1);
      expect(summary['temperatureDisplay'], '37.1 °C (98.8 °F)');
      expect(summary['respiratoryRate'], 17);
      expect(summary['oxygenSaturation'], 99);
      expect(summary['weight'], 68.5);
      expect(summary['latestObservationId'], 'obs_999');
      expect(summary['lastNurseId'], 'n_200');
      expect(summary['lastNurseName'], 'Nurse Sara');
    });

    test('recordVitalObservation dispatches via custom callable hook and returns created model', () async {
      final service = NurseService(
        customRecordCallable: (data) async {
          expect(data['patientId'], 'patient_456');
          expect(data['systolicBp'], 120.0);
          expect(data['diastolicBp'], 80.0);
          return {'observationId': 'obs_server_assigned_123'};
        },
      );

      final result = await service.recordVitalObservation(
        patientId: 'patient_456',
        systolicBp: 120,
        diastolicBp: 80,
        pulseRate: 72,
        temperatureCelsius: 37.0,
        respiratoryRate: 16,
        oxygenSaturation: 98,
      );

      expect(result.id, 'obs_server_assigned_123');
      expect(result.patientId, 'patient_456');
      expect(result.systolicBp, 120.0);
    });

    test('recordVitalObservation fails closed when callable rejects authorization', () async {
      final service = NurseService(
        customRecordCallable: (data) async {
          throw NurseAuthorizationException(
            'Nurse is not assigned to this patient.',
            patientId: data['patientId'],
            nurseId: 'nurse_test',
          );
        },
      );

      expect(
        () => service.recordVitalObservation(
          patientId: 'patient_456',
          systolicBp: 120,
          diastolicBp: 80,
          pulseRate: 72,
          temperatureCelsius: 37.0,
          respiratoryRate: 16,
          oxygenSaturation: 98,
        ),
        throwsA(isA<NurseAuthorizationException>()),
      );
    });

    test('pktDateKeyStream accurately emits current key and switches on clock event across midnight PKT', () async {
      final clockCtrl = StreamController<DateTime>();

      // 11:59:50 PM PKT on 2026-10-16 -> UTC is 18:59:50
      final beforeMidnightUtc = DateTime.utc(2026, 10, 16, 18, 59, 50);
      // 00:00:10 AM PKT on 2026-10-17 -> UTC is 19:00:10
      final afterMidnightUtc = DateTime.utc(2026, 10, 16, 19, 0, 10);

      final keyStream = NurseService.pktDateKeyStream(clockStream: clockCtrl.stream);
      final emittedKeys = <String>[];
      final sub = keyStream.listen(emittedKeys.add);

      clockCtrl.add(beforeMidnightUtc);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(emittedKeys, ['2026-10-16']);

      // Clock tick crossing midnight
      clockCtrl.add(afterMidnightUtc);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(emittedKeys, ['2026-10-16', '2026-10-17']);

      await sub.cancel();
      await clockCtrl.close();
    });

    test('VitalSignModel with doctor attribution distinguishes doctor from nurse without impersonation', () {
      final doctorObs = VitalSignModel(
        id: 'obs_doc_888',
        patientId: 'p_777',
        doctorId: 'dr_oncologist_1',
        doctorName: 'Dr. Oncologist',
        recordedBy: 'dr_oncologist_1',
        recordedByName: 'Dr. Oncologist',
        recordedByRole: 'doctor',
        recordedAt: DateTime(2026, 10, 16, 16, 0),
        systolicBp: 135,
        diastolicBp: 88,
        pulseRate: 76,
        temperature: 37.2,
        temperatureUnit: 'C',
        respiratoryRate: 18,
        oxygenSaturation: 97,
        notes: 'Doctor round notes',
      );

      expect(doctorObs.isRecordedByDoctor, isTrue);
      expect(doctorObs.recordedByDisplayName, 'Dr. Oncologist');
      expect(doctorObs.doctorId, 'dr_oncologist_1');
      expect(doctorObs.doctorName, 'Dr. Oncologist');
      expect(doctorObs.nurseId, isEmpty);

      final map = doctorObs.toMap();
      expect(map['recordedBy'], 'dr_oncologist_1');
      expect(map['recordedByName'], 'Dr. Oncologist');
      expect(map['recordedByRole'], 'doctor');
      expect(map['doctorId'], 'dr_oncologist_1');
      expect(map['doctorName'], 'Dr. Oncologist');
      expect(map.containsKey('nurseId'), isFalse);

      final summary = doctorObs.toLatestSummaryMap();
      expect(summary['lastDoctorId'], 'dr_oncologist_1');
      expect(summary['lastDoctorName'], 'Dr. Oncologist');
      expect(summary['recordedByRole'], 'doctor');
      expect(summary.containsKey('lastNurseId'), isFalse);

      final reconstructed = VitalSignModel.fromMap(map, docId: 'obs_doc_888');
      expect(reconstructed.isRecordedByDoctor, isTrue);
      expect(reconstructed.recordedByDisplayName, 'Dr. Oncologist');
      expect(reconstructed.doctorId, 'dr_oncologist_1');
      expect(reconstructed.doctorName, 'Dr. Oncologist');
    });
  });
}
