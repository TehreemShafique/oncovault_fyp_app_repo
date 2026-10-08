import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncovault/models/notification_payload.dart';
import 'package:oncovault/models/medical_record_model.dart';
import 'package:oncovault/models/appointment_model.dart';
import 'package:oncovault/models/user_model.dart';
import 'package:oncovault/services/notification_router.dart';
import 'package:oncovault/screens/patient/report_viewer_screen.dart';
import 'package:oncovault/screens/patient/appointment_detail_screen.dart';

class _TestNavigatorObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushedRoutes = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushedRoutes.add(route);
    super.didPush(route, previousRoute);
  }
}

void main() {
  group('Phase 1D Business Notification Events Tests', () {
    const phiForbiddenPatterns = [
      'wbc', 'rbc', 'hgb', 'plt', 'platelet', 'blast',
      'cancer', 'leukemia', 'stage', 'chemo', 'dosage', 'mg'
    ];

    void assertNoPhi(String text) {
      final lower = text.toLowerCase();
      for (final forbidden in phiForbiddenPatterns) {
        expect(lower.contains(forbidden), isFalse,
            reason: 'Notification content must not leak PHI pattern: $forbidden');
      }
    }

    test('Report upload notification payload is valid, PHI-minimal, and references medical record ID', () {
      const patientId = 'pt_safe_001';
      const recordId = 'rec_cbc_888';
      final now = DateTime.now();

      final notif = NotificationModel(
        id: 'notif_rep_001',
        patientId: patientId,
        title: 'New Report Available',
        body: 'A new medical report has been added to your records.',
        type: 'report',
        createdAt: now,
        referenceId: recordId,
      );

      // Verify recipient & metadata
      expect(notif.patientId, equals(patientId));
      expect(notif.type, equals('report'));
      expect(notif.referenceId, equals(recordId));
      expect(notif.referenceId, isNotNull);

      // Verify PHI safety
      assertNoPhi(notif.title);
      assertNoPhi(notif.body);

      // Convert to domain AppNotificationPayload
      final appPayload = AppNotificationPayload.fromNotificationModel(notif);
      expect(appPayload.type, equals('report'));
      expect(appPayload.referenceId, equals(recordId));
      expect(appPayload.source, equals(NotificationSource.inAppHistory));
      expect(appPayload.title, equals('New Report Available'));
    });

    test('Appointment completion notification payload is valid, PHI-minimal, and references appointment ID', () {
      const patientId = 'pt_safe_002';
      const apptId = 'appt_completed_777';
      final now = DateTime.now();

      final notif = NotificationModel(
        id: 'notif_appt_002',
        patientId: patientId,
        title: 'Appointment Completed',
        body: 'Your appointment has been marked as completed.',
        type: 'appointment',
        createdAt: now,
        referenceId: apptId,
      );

      // Verify recipient & metadata
      expect(notif.patientId, equals(patientId));
      expect(notif.type, equals('appointment'));
      expect(notif.referenceId, equals(apptId));
      expect(notif.referenceId, isNotNull);

      // Verify PHI safety
      assertNoPhi(notif.title);
      assertNoPhi(notif.body);

      // Convert to domain AppNotificationPayload
      final appPayload = AppNotificationPayload.fromNotificationModel(notif);
      expect(appPayload.type, equals('appointment'));
      expect(appPayload.referenceId, equals(apptId));
      expect(appPayload.source, equals(NotificationSource.inAppHistory));
      expect(appPayload.title, equals('Appointment Completed'));
    });

    test('Prescription notification payload references medical-record ID rather than prescription document ID', () {
      const patientId = 'pt_safe_003';
      const medicalRecordId = 'rec_rx_555';
      final now = DateTime.now();

      final notif = NotificationModel(
        id: 'notif_rx_003',
        patientId: patientId,
        title: 'New Prescription Issued',
        body: 'Dr. Jane Smith has issued a new prescription with 2 medication(s).',
        type: 'report',
        createdAt: now,
        referenceId: medicalRecordId,
      );

      expect(notif.type, equals('report'));
      expect(notif.referenceId, equals(medicalRecordId));
      assertNoPhi(notif.title);

      final appPayload = AppNotificationPayload.fromNotificationModel(notif);
      expect(appPayload.type, equals('report'));
      expect(appPayload.referenceId, equals(medicalRecordId));
    });

    test('Diagnosis notification payload includes non-null diagnosis reference ID', () {
      const patientId = 'pt_safe_004';
      const diagnosisId = 'diag_rec_333';
      final now = DateTime.now();

      final notif = NotificationModel(
        id: 'notif_diag_004',
        patientId: patientId,
        title: 'New Diagnosis Added',
        body: 'Dr. John Doe added: Clinical Assessment.',
        type: 'report',
        createdAt: now,
        referenceId: diagnosisId,
      );

      expect(notif.type, equals('report'));
      expect(notif.referenceId, equals(diagnosisId));
      expect(notif.referenceId, isNotNull);

      final appPayload = AppNotificationPayload.fromNotificationModel(notif);
      expect(appPayload.type, equals('report'));
      expect(appPayload.referenceId, equals(diagnosisId));
    });

    testWidgets('Report upload notification routes to ReportViewerScreen when record belongs to patient', (tester) async {
      const currentPatientId = 'patient_owner_01';
      const recordId = 'rec_cbc_999';
      final observer = _TestNavigatorObserver();
      final navKey = GlobalKey<NavigatorState>();

      final router = NotificationRouter(
        navigatorKey: navKey,
        currentUserIdResolver: () => currentPatientId,
        profileResolver: (uid) async => OVUser(
          uid: uid,
          name: 'Jane Patient',
          email: 'jane@oncovault.com',
          medicalId: 'OV-PT-111111',
          role: 'patient',
          createdAt: DateTime.now(),
        ),
        recordResolver: (pId, rId) async => MedicalRecordModel(
          id: rId,
          patientId: pId,
          title: 'CBC Pathology Report',
          type: RecordType.report,
          subtype: 'CBC',
          facility: 'OncoVault Lab',
          date: DateTime.now(),
          uploadedAt: DateTime.now(),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navKey,
          navigatorObservers: [observer],
          home: const Scaffold(body: Text('Base Screen')),
        ),
      );

      final payload = AppNotificationPayload.fromNotificationModel(
        NotificationModel(
          id: 'notif_100',
          patientId: currentPatientId,
          title: 'New Report Available',
          body: 'A new medical report has been added to your records.',
          type: 'report',
          createdAt: DateTime.now(),
          referenceId: recordId,
        ),
      );

      final routed = await router.routePayload(payload);
      expect(routed, isTrue);

      expect(observer.pushedRoutes, isNotEmpty);
      final pushedRoute = observer.pushedRoutes.last as MaterialPageRoute;
      final destination = pushedRoute.builder(navKey.currentContext!);
      expect(destination, isA<ReportViewerScreen>());
    });

    testWidgets('Appointment completion notification routes to AppointmentDetailScreen when appointment belongs to patient', (tester) async {
      const currentPatientId = 'patient_owner_02';
      const apptId = 'appt_completed_888';
      final observer = _TestNavigatorObserver();
      final navKey = GlobalKey<NavigatorState>();

      final router = NotificationRouter(
        navigatorKey: navKey,
        currentUserIdResolver: () => currentPatientId,
        profileResolver: (uid) async => OVUser(
          uid: uid,
          name: 'Bob Patient',
          email: 'bob@oncovault.com',
          medicalId: 'OV-PT-222222',
          role: 'patient',
          createdAt: DateTime.now(),
        ),
        appointmentResolver: (aId) async => AppointmentModel(
          id: aId,
          patientId: currentPatientId,
          patientName: 'Bob Patient',
          doctorId: 'doc_123',
          doctorName: 'Dr. Vance',
          doctorSpecialty: 'Oncology',
          appointmentDate: DateTime.now(),
          timeSlot: '10:00 AM',
          status: AppointmentStatus.completed,
          createdAt: DateTime.now(),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navKey,
          navigatorObservers: [observer],
          home: const Scaffold(body: Text('Base Screen')),
        ),
      );

      final payload = AppNotificationPayload.fromNotificationModel(
        NotificationModel(
          id: 'notif_200',
          patientId: currentPatientId,
          title: 'Appointment Completed',
          body: 'Your appointment has been marked as completed.',
          type: 'appointment',
          createdAt: DateTime.now(),
          referenceId: apptId,
        ),
      );

      final routed = await router.routePayload(payload);
      expect(routed, isTrue);

      expect(observer.pushedRoutes, isNotEmpty);
      final pushedRoute = observer.pushedRoutes.last as MaterialPageRoute;
      final destination = pushedRoute.builder(navKey.currentContext!);
      expect(destination, isA<AppointmentDetailScreen>());
    });
  });
}
