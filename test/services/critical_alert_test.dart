// test/services/critical_alert_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:oncovault/models/doctor_model.dart';
import 'package:oncovault/services/doctor_service.dart';

void main() {
  group('CriticalAlert Model Tests', () {
    final now = DateTime(2026, 10, 17, 12, 0);

    final alert = CriticalAlert(
      id: 'alert_obs123_doc456',
      patientId: 'patient_001',
      patientName: 'Jane Doe',
      doctorId: 'doctor_456',
      alertType: 'vital_alert',
      severity: 'high',
      title: 'Critical Vital Alert: Jane Doe',
      description: 'Severe Hypertensive Crisis (BP: 190/115 mmHg)',
      isRead: false,
      isAcknowledged: false,
      eventId: 'event_obs123',
      observationId: 'obs123',
      dispatchStatus: 'SENT',
      escalationStatus: 'NONE',
      vitalsSummary: {
        'bloodPressure': '190/115 mmHg',
        'heartRate': 118,
        'temperature': 39.5,
        'oxygenSaturation': 88,
        'criticalReasons': ['Severe Hypertensive Crisis', 'Hypoxia'],
      },
      createdAt: now,
    );

    test('CriticalAlert serialization contains all fields', () {
      final map = alert.toMap();

      expect(map['id'], 'alert_obs123_doc456');
      expect(map['alertId'], 'alert_obs123_doc456');
      expect(map['patientId'], 'patient_001');
      expect(map['patientName'], 'Jane Doe');
      expect(map['doctorId'], 'doctor_456');
      expect(map['alertType'], 'vital_alert');
      expect(map['severity'], 'high');
      expect(map['title'], contains('Critical Vital Alert'));
      expect(map['description'], contains('Severe Hypertensive Crisis'));
      expect(map['isRead'], isFalse);
      expect(map['isAcknowledged'], isFalse);
      expect(map['acknowledgedAt'], isNull);
      expect(map['isResolved'], isFalse);
      expect(map['eventId'], 'event_obs123');
      expect(map['observationId'], 'obs123');
      expect(map['dispatchStatus'], 'SENT');
      expect(map['escalationStatus'], 'NONE');
      expect(map['vitalsSummary']['bloodPressure'], '190/115 mmHg');
      expect(map['createdAt'], isA<Timestamp>());
    });

    test('CriticalAlert deserialization fromMap correctly reconstructs model', () {
      final map = alert.toMap();
      final reconstructed = CriticalAlert.fromMap(map);

      expect(reconstructed.id, 'alert_obs123_doc456');
      expect(reconstructed.patientId, 'patient_001');
      expect(reconstructed.patientName, 'Jane Doe');
      expect(reconstructed.doctorId, 'doctor_456');
      expect(reconstructed.alertType, 'vital_alert');
      expect(reconstructed.severity, 'high');
      expect(reconstructed.isRead, isFalse);
      expect(reconstructed.isAcknowledged, isFalse);
      expect(reconstructed.isResolved, isFalse);
      expect(reconstructed.eventId, 'event_obs123');
      expect(reconstructed.observationId, 'obs123');
      expect(reconstructed.vitalsSummary?['heartRate'], 118);
    });

    test('Legacy alert deserialization falls back safely to default values', () {
      final legacyMap = {
        'id': 'legacy_alert_001',
        'patientId': 'p_old',
        'patientName': 'Old Patient',
        'doctorId': 'd_old',
        'alertType': 'urgent_review',
        'severity': 'medium',
        'title': 'Review needed',
        'description': 'Follow up scheduled',
        'isRead': true,
        'createdAt': Timestamp.now(),
      };

      final legacy = CriticalAlert.fromMap(legacyMap);
      expect(legacy.id, 'legacy_alert_001');
      expect(legacy.isAcknowledged, isFalse);
      expect(legacy.acknowledgedAt, isNull);
      expect(legacy.acknowledgedBy, isNull);
      expect(legacy.isResolved, isFalse);
      expect(legacy.resolvedAt, isNull);
      expect(legacy.eventId, isNull);
      expect(legacy.observationId, isNull);
      expect(legacy.dispatchStatus, isNull);
      expect(legacy.vitalsSummary, isNull);
    });

    test('copyWith produces modified immutable copy', () {
      final ackTime = DateTime(2026, 10, 17, 12, 15);
      final acknowledged = alert.copyWith(
        isAcknowledged: true,
        acknowledgedAt: ackTime,
        acknowledgedBy: 'doctor_456',
        acknowledgmentNotes: 'IV labetalol administered immediately.',
      );

      expect(acknowledged.isAcknowledged, isTrue);
      expect(acknowledged.acknowledgedAt, ackTime);
      expect(acknowledged.acknowledgedBy, 'doctor_456');
      expect(acknowledged.acknowledgmentNotes, 'IV labetalol administered immediately.');
      // Original alert unchanged
      expect(alert.isAcknowledged, isFalse);
      expect(alert.acknowledgedAt, isNull);
    });

    test('copyWith handles resolution state transition', () {
      final resTime = DateTime(2026, 10, 17, 13, 0);
      final resolved = alert.copyWith(
        isAcknowledged: true,
        isResolved: true,
        resolvedAt: resTime,
        resolvedBy: 'doctor_456',
        resolutionNotes: 'BP normalized to 130/85 mmHg after therapy.',
      );

      expect(resolved.isAcknowledged, isTrue);
      expect(resolved.isResolved, isTrue);
      expect(resolved.resolvedAt, resTime);
      expect(resolved.resolvedBy, 'doctor_456');
      expect(resolved.resolutionNotes, contains('BP normalized'));
    });
  });

  group('DoctorService Critical Alert Lifecycle Tests', () {
    test('acknowledgeAlert invokes custom callable hook with correct parameters', () async {
      String? capturedDoctorId;
      String? capturedAlertId;
      String? capturedNotes;

      final service = DoctorService(
        acknowledgeCallable: ({required alertId, required doctorId, notes}) async {
          capturedDoctorId = doctorId;
          capturedAlertId = alertId;
          capturedNotes = notes;
          return {
            'success': true,
            'alertId': alertId,
            'isAcknowledged': true,
          };
        },
      );

      await service.acknowledgeAlert(
        'dr_oncologist_1',
        'alert_obs_999_dr_oncologist_1',
        notes: 'Reviewing critical vitals now.',
      );

      expect(capturedDoctorId, 'dr_oncologist_1');
      expect(capturedAlertId, 'alert_obs_999_dr_oncologist_1');
      expect(capturedNotes, 'Reviewing critical vitals now.');
    });

    test('resolveAlert invokes custom callable hook with correct parameters', () async {
      String? capturedDoctorId;
      String? capturedAlertId;
      String? capturedNotes;

      final service = DoctorService(
        resolveCallable: ({required alertId, required doctorId, notes}) async {
          capturedDoctorId = doctorId;
          capturedAlertId = alertId;
          capturedNotes = notes;
          return {
            'success': true,
            'alertId': alertId,
            'isResolved': true,
          };
        },
      );

      await service.resolveAlert(
        'dr_oncologist_1',
        'alert_obs_999_dr_oncologist_1',
        notes: 'Patient stabilized. Transferred to step-down unit.',
      );

      expect(capturedDoctorId, 'dr_oncologist_1');
      expect(capturedAlertId, 'alert_obs_999_dr_oncologist_1');
      expect(capturedNotes, contains('Patient stabilized'));
    });

    test('acknowledgeAlert propagates error when backend callable rejects request', () async {
      final service = DoctorService(
        acknowledgeCallable: ({required alertId, required doctorId, notes}) async {
          throw Exception('Permission denied: caller is not assigned physician');
        },
      );

      expect(
        () => service.acknowledgeAlert('dr_stranger', 'alert_obs_999'),
        throwsA(isA<Exception>()),
      );
    });

    test('resolveAlert propagates error when backend rejects unacknowledged alert resolution', () async {
      final service = DoctorService(
        resolveCallable: ({required alertId, required doctorId, notes}) async {
          throw Exception('Failed precondition: Alert must be acknowledged before it can be resolved');
        },
      );

      expect(
        () => service.resolveAlert('dr_oncologist_1', 'alert_obs_999'),
        throwsA(isA<Exception>()),
      );
    });
  });
}
