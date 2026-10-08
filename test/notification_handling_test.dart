import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'package:oncovault/models/notification_payload.dart';
import 'package:oncovault/models/medical_record_model.dart';
import 'package:oncovault/models/appointment_model.dart';
import 'package:oncovault/models/user_model.dart';
import 'package:oncovault/services/notification_router.dart';
import 'package:oncovault/services/notification_service.dart';
import 'package:oncovault/services/foreground_notification_presenter.dart';

import 'package:oncovault/screens/patient/appointment_detail_screen.dart';
import 'package:oncovault/screens/patient/appointment_list_screen.dart';
import 'package:oncovault/screens/patient/report_viewer_screen.dart';
import 'package:oncovault/screens/patient/medical_records_screen.dart';
import 'package:oncovault/screens/patient/notifications_screen.dart';
import 'package:oncovault/screens/doctor/appointment_detail_doctor_screen.dart';
import 'package:oncovault/screens/doctor/appointment_requests_screen.dart';
import 'package:oncovault/screens/doctor/critical_alerts_screen.dart';
import 'package:oncovault/screens/doctor/doctor_notifications_screen.dart';
import 'package:oncovault/services/doctor_service.dart';

class _FakeDoctorService implements DoctorService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestNavigatorObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushedRoutes = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushedRoutes.add(route);
    super.didPush(route, previousRoute);
  }
}

void main() {
  group('Phase 1C AppNotificationPayload Contract & Sanitization Tests', () {
    test('converts RemoteMessage to AppNotificationPayload with type & refId normalization', () {
      const msg = RemoteMessage(
        messageId: 'msg_001',
        data: {
          'type': ' APPOINTMENT ',
          'referenceId': ' appt_999 ',
          'title': 'Appointment Update',
          'body': 'Your appointment time changed',
        },
      );

      final payload = AppNotificationPayload.fromRemoteMessage(
        msg,
        source: NotificationSource.fcmTap,
      );

      expect(payload.messageId, equals('msg_001'));
      expect(payload.type, equals('appointment'));
      expect(payload.referenceId, equals('appt_999'));
      expect(payload.title, equals('Appointment Update'));
      expect(payload.body, equals('Your appointment time changed'));
      expect(payload.source, equals(NotificationSource.fcmTap));
    });

    test('tolerates empty data and missing notification block safely', () {
      const msg = RemoteMessage(messageId: 'msg_empty');

      final payload = AppNotificationPayload.fromRemoteMessage(
        msg,
        source: NotificationSource.fcmForeground,
      );

      expect(payload.messageId, equals('msg_empty'));
      expect(payload.type, equals('general'));
      expect(payload.referenceId, isNull);
      expect(payload.title, equals('OncoVault Notification'));
      expect(payload.body, isEmpty);
      expect(payload.source, equals(NotificationSource.fcmForeground));
    });

    test('maps Firestore NotificationModel to AppNotificationPayload correctly', () {
      final notif = NotificationModel(
        id: 'notif_123',
        patientId: 'patient_456',
        title: 'Report Ready',
        body: 'Your lab report has been uploaded',
        type: 'REPORT',
        createdAt: DateTime.now(),
        referenceId: 'rec_789',
      );

      final payload = AppNotificationPayload.fromNotificationModel(notif);

      expect(payload.messageId, equals('notif_123'));
      expect(payload.type, equals('report'));
      expect(payload.referenceId, equals('rec_789'));
      expect(payload.title, equals('Report Ready'));
      expect(payload.body, equals('Your lab report has been uploaded'));
      expect(payload.source, equals(NotificationSource.inAppHistory));
    });

    test('toSafeDiagnosticString excludes sensitive clinical details', () {
      const payload = AppNotificationPayload(
        messageId: 'msg_diag_1',
        type: 'report',
        referenceId: 'rec_secret',
        title: 'Sensitive Title',
        body: 'Sensitive clinical details',
        source: NotificationSource.fcmForeground,
      );

      final diag = payload.toSafeDiagnosticString();
      expect(diag.contains('msg_diag_1'), isTrue);
      expect(diag.contains('report'), isTrue);
      expect(diag.contains('hasRefId: true'), isTrue);
      expect(diag.contains('Sensitive Title'), isFalse);
      expect(diag.contains('Sensitive clinical details'), isFalse);
    });
  });

  group('Phase 1C NotificationRouter Role-Aware Routing & Authorization Tests', () {
    late GlobalKey<NavigatorState> testNavKey;
    late _TestNavigatorObserver testObserver;

    setUp(() {
      testNavKey = GlobalKey<NavigatorState>();
      testObserver = _TestNavigatorObserver();
    });

    Widget buildTestApp(Widget home) {
      return MaterialApp(
        navigatorKey: testNavKey,
        navigatorObservers: [testObserver],
        home: Scaffold(body: home),
      );
    }

    testWidgets('Patient authorized appointment routes to AppointmentDetailScreen', (tester) async {
      await tester.pumpWidget(buildTestApp(const Text('Dashboard')));

      final targetAppt = AppointmentModel(
        id: 'appt_1',
        patientId: 'p_user_1',
        patientName: 'Patient One',
        doctorId: 'd_user_1',
        doctorName: 'Dr. House',
        doctorSpecialty: 'Oncology',
        appointmentDate: DateTime.now(),
        timeSlot: '10:00 AM',
        status: AppointmentStatus.approved,
        createdAt: DateTime.now(),
      );

      final router = NotificationRouter(
        navigatorKey: testNavKey,
        currentUserIdResolver: () => 'p_user_1',
        profileResolver: (uid) async => OVUser(
          uid: 'p_user_1',
          name: 'Patient One',
          email: 'p1@test.com',
          medicalId: 'OV-PA-000001',
          role: 'patient',
          createdAt: DateTime.now(),
        ),
        appointmentResolver: (id) async => id == 'appt_1' ? targetAppt : null,
      );

      const payload = AppNotificationPayload(
        type: 'appointment',
        referenceId: 'appt_1',
        title: 'Approved',
        body: 'Your appointment is confirmed',
        source: NotificationSource.fcmTap,
      );

      final success = await router.routePayload(payload);
      expect(success, isTrue);

      expect(testObserver.pushedRoutes, isNotEmpty);
      final pushedRoute = testObserver.pushedRoutes.last as MaterialPageRoute;
      final destination = pushedRoute.builder(testNavKey.currentContext!);
      expect(destination, isA<AppointmentDetailScreen>());
      expect((destination as AppointmentDetailScreen).appointment.id, equals('appt_1'));
      expect(destination.patientId, equals('p_user_1'));
    });

    testWidgets('Patient appointment belonging to different patient falls back to AppointmentListScreen (IDOR prevention)', (tester) async {
      await tester.pumpWidget(buildTestApp(const Text('Dashboard')));

      final otherAppt = AppointmentModel(
        id: 'appt_other',
        patientId: 'different_patient_id',
        patientName: 'Someone Else',
        doctorId: 'd_user_1',
        doctorName: 'Dr. House',
        doctorSpecialty: 'Oncology',
        appointmentDate: DateTime.now(),
        timeSlot: '10:00 AM',
        status: AppointmentStatus.approved,
        createdAt: DateTime.now(),
      );

      final router = NotificationRouter(
        navigatorKey: testNavKey,
        currentUserIdResolver: () => 'p_user_1',
        profileResolver: (uid) async => OVUser(
          uid: 'p_user_1',
          name: 'Patient One',
          email: 'p1@test.com',
          medicalId: 'OV-PA-000001',
          role: 'patient',
          createdAt: DateTime.now(),
        ),
        appointmentResolver: (id) async => otherAppt,
      );

      const payload = AppNotificationPayload(
        type: 'appointment',
        referenceId: 'appt_other',
        title: 'Approved',
        body: 'Unowned appointment',
        source: NotificationSource.fcmTap,
      );

      final success = await router.routePayload(payload);
      expect(success, isTrue);

      expect(testObserver.pushedRoutes, isNotEmpty);
      final pushedRoute = testObserver.pushedRoutes.last as MaterialPageRoute;
      final destination = pushedRoute.builder(testNavKey.currentContext!);
      expect(destination, isA<AppointmentListScreen>());
    });

    testWidgets('Patient missing appointment or null referenceId falls back to AppointmentListScreen', (tester) async {
      await tester.pumpWidget(buildTestApp(const Text('Dashboard')));

      final router = NotificationRouter(
        navigatorKey: testNavKey,
        currentUserIdResolver: () => 'p_user_1',
        profileResolver: (uid) async => OVUser(
          uid: 'p_user_1',
          name: 'Patient One',
          email: 'p1@test.com',
          medicalId: 'OV-PA-000001',
          role: 'patient',
          createdAt: DateTime.now(),
        ),
        appointmentResolver: (id) async => null,
      );

      const payload = AppNotificationPayload(
        type: 'appointment',
        referenceId: 'non_existent_appt',
        title: 'Notice',
        body: 'Details missing',
        source: NotificationSource.fcmTap,
      );

      final success = await router.routePayload(payload);
      expect(success, isTrue);

      expect(testObserver.pushedRoutes, isNotEmpty);
      final pushedRoute = testObserver.pushedRoutes.last as MaterialPageRoute;
      final destination = pushedRoute.builder(testNavKey.currentContext!);
      expect(destination, isA<AppointmentListScreen>());
    });

    testWidgets('Patient authorized report routes to ReportViewerScreen', (tester) async {
      await tester.pumpWidget(buildTestApp(const Text('Dashboard')));

      final testRecord = MedicalRecordModel(
        id: 'rec_1',
        patientId: 'p_user_1',
        title: 'Blood Panel',
        type: RecordType.report,
        subtype: 'Pathology',
        facility: 'Main Lab',
        date: DateTime.now(),
        uploadedAt: DateTime.now(),
      );

      final router = NotificationRouter(
        navigatorKey: testNavKey,
        currentUserIdResolver: () => 'p_user_1',
        profileResolver: (uid) async => OVUser(
          uid: 'p_user_1',
          name: 'Patient One',
          email: 'p1@test.com',
          medicalId: 'OV-PA-000001',
          role: 'patient',
          createdAt: DateTime.now(),
        ),
        recordResolver: (pid, rid) async => (pid == 'p_user_1' && rid == 'rec_1') ? testRecord : null,
      );

      const payload = AppNotificationPayload(
        type: 'report',
        referenceId: 'rec_1',
        title: 'Report',
        body: 'Results are ready',
        source: NotificationSource.fcmTap,
      );

      final success = await router.routePayload(payload);
      expect(success, isTrue);

      expect(testObserver.pushedRoutes, isNotEmpty);
      final pushedRoute = testObserver.pushedRoutes.last as MaterialPageRoute;
      final destination = pushedRoute.builder(testNavKey.currentContext!);
      expect(destination, isA<ReportViewerScreen>());
      expect((destination as ReportViewerScreen).record.id, equals('rec_1'));
    });

    testWidgets('Patient report without referenceId routes to MedicalRecordsScreen', (tester) async {
      await tester.pumpWidget(buildTestApp(const Text('Dashboard')));

      final router = NotificationRouter(
        navigatorKey: testNavKey,
        currentUserIdResolver: () => 'p_user_1',
        profileResolver: (uid) async => OVUser(
          uid: 'p_user_1',
          name: 'Patient One',
          email: 'p1@test.com',
          medicalId: 'OV-PA-000001',
          role: 'patient',
          createdAt: DateTime.now(),
        ),
      );

      const payload = AppNotificationPayload(
        type: 'report',
        referenceId: null,
        title: 'Diagnosis Added',
        body: 'A diagnosis was recorded',
        source: NotificationSource.fcmTap,
      );

      final success = await router.routePayload(payload);
      expect(success, isTrue);

      expect(testObserver.pushedRoutes, isNotEmpty);
      final pushedRoute = testObserver.pushedRoutes.last as MaterialPageRoute;
      final destination = pushedRoute.builder(testNavKey.currentContext!);
      expect(destination, isA<MedicalRecordsScreen>());
    });

    testWidgets('Patient receiving vital_alert is protected from doctor screen and falls back to NotificationsScreen', (tester) async {
      await tester.pumpWidget(buildTestApp(const Text('Dashboard')));

      final router = NotificationRouter(
        navigatorKey: testNavKey,
        currentUserIdResolver: () => 'p_user_1',
        profileResolver: (uid) async => OVUser(
          uid: 'p_user_1',
          name: 'Patient One',
          email: 'p1@test.com',
          medicalId: 'OV-PA-000001',
          role: 'patient',
          createdAt: DateTime.now(),
        ),
      );

      const payload = AppNotificationPayload(
        type: 'vital_alert',
        referenceId: 'alert_99',
        title: 'Critical Alert',
        body: 'High severity vitals',
        source: NotificationSource.fcmTap,
      );

      final success = await router.routePayload(payload);
      expect(success, isTrue);

      expect(testObserver.pushedRoutes, isNotEmpty);
      final pushedRoute = testObserver.pushedRoutes.last as MaterialPageRoute;
      final destination = pushedRoute.builder(testNavKey.currentContext!);
      expect(destination, isA<NotificationsScreen>());
    });

    testWidgets('Doctor authorized appointment routes to AppointmentDetailDoctorScreen', (tester) async {
      await tester.pumpWidget(buildTestApp(const Text('Doctor Dashboard')));

      final targetAppt = AppointmentModel(
        id: 'appt_doc_1',
        patientId: 'p_user_99',
        patientName: 'Patient Ray',
        doctorId: 'd_user_1',
        doctorName: 'Dr. House',
        doctorSpecialty: 'Oncology',
        appointmentDate: DateTime.now(),
        timeSlot: '11:00 AM',
        status: AppointmentStatus.pending,
        createdAt: DateTime.now(),
      );

      final router = NotificationRouter(
        navigatorKey: testNavKey,
        currentUserIdResolver: () => 'd_user_1',
        profileResolver: (uid) async => OVUser(
          uid: 'd_user_1',
          name: 'Dr. House',
          email: 'doc@test.com',
          medicalId: 'OV-DO-000001',
          role: 'doctor',
          createdAt: DateTime.now(),
        ),
        appointmentResolver: (id) async => id == 'appt_doc_1' ? targetAppt : null,
        doctorServiceFactory: () => _FakeDoctorService(),
      );

      const payload = AppNotificationPayload(
        type: 'appointment',
        referenceId: 'appt_doc_1',
        title: 'New Request',
        body: 'Appointment requested',
        source: NotificationSource.fcmTap,
      );

      final success = await router.routePayload(payload);
      expect(success, isTrue);

      expect(testObserver.pushedRoutes, isNotEmpty);
      final pushedRoute = testObserver.pushedRoutes.last as MaterialPageRoute;
      final destination = pushedRoute.builder(testNavKey.currentContext!);
      expect(destination, isA<AppointmentDetailDoctorScreen>());
      expect((destination as AppointmentDetailDoctorScreen).appointment.id, equals('appt_doc_1'));
    });

    testWidgets('Doctor appointment belonging to another doctor falls back to AppointmentRequestsScreen', (tester) async {
      await tester.pumpWidget(buildTestApp(const Text('Doctor Dashboard')));

      final otherAppt = AppointmentModel(
        id: 'appt_other_doc',
        patientId: 'p_user_99',
        patientName: 'Patient Ray',
        doctorId: 'different_doctor_id',
        doctorName: 'Dr. Wilson',
        doctorSpecialty: 'Oncology',
        appointmentDate: DateTime.now(),
        timeSlot: '11:00 AM',
        status: AppointmentStatus.pending,
        createdAt: DateTime.now(),
      );

      final router = NotificationRouter(
        navigatorKey: testNavKey,
        currentUserIdResolver: () => 'd_user_1',
        profileResolver: (uid) async => OVUser(
          uid: 'd_user_1',
          name: 'Dr. House',
          email: 'doc@test.com',
          medicalId: 'OV-DO-000001',
          role: 'doctor',
          createdAt: DateTime.now(),
        ),
        appointmentResolver: (id) async => otherAppt,
      );

      const payload = AppNotificationPayload(
        type: 'appointment',
        referenceId: 'appt_other_doc',
        title: 'New Request',
        body: 'Appointment for Wilson',
        source: NotificationSource.fcmTap,
      );

      final success = await router.routePayload(payload);
      expect(success, isTrue);

      expect(testObserver.pushedRoutes, isNotEmpty);
      final pushedRoute = testObserver.pushedRoutes.last as MaterialPageRoute;
      final destination = pushedRoute.builder(testNavKey.currentContext!);
      expect(destination, isA<AppointmentRequestsScreen>());
    });

    testWidgets('Doctor vital_alert routes to CriticalAlertsScreen', (tester) async {
      await tester.pumpWidget(buildTestApp(const Text('Doctor Dashboard')));

      final router = NotificationRouter(
        navigatorKey: testNavKey,
        currentUserIdResolver: () => 'd_user_1',
        profileResolver: (uid) async => OVUser(
          uid: 'd_user_1',
          name: 'Dr. House',
          email: 'doc@test.com',
          medicalId: 'OV-DO-000001',
          role: 'doctor',
          createdAt: DateTime.now(),
        ),
      );

      const payload = AppNotificationPayload(
        type: 'vital_alert',
        referenceId: 'alert_1',
        title: 'Critical Vitals',
        body: 'WBC elevated',
        source: NotificationSource.fcmTap,
      );

      final success = await router.routePayload(payload);
      expect(success, isTrue);

      expect(testObserver.pushedRoutes, isNotEmpty);
      final pushedRoute = testObserver.pushedRoutes.last as MaterialPageRoute;
      final destination = pushedRoute.builder(testNavKey.currentContext!);
      expect(destination, isA<CriticalAlertsScreen>());
    });

    testWidgets('Doctor report routes to DoctorNotificationsScreen', (tester) async {
      await tester.pumpWidget(buildTestApp(const Text('Doctor Dashboard')));

      final router = NotificationRouter(
        navigatorKey: testNavKey,
        currentUserIdResolver: () => 'd_user_1',
        profileResolver: (uid) async => OVUser(
          uid: 'd_user_1',
          name: 'Dr. House',
          email: 'doc@test.com',
          medicalId: 'OV-DO-000001',
          role: 'doctor',
          createdAt: DateTime.now(),
        ),
      );

      const payload = AppNotificationPayload(
        type: 'report',
        referenceId: 'rec_something',
        title: 'Report Alert',
        body: 'Report updated',
        source: NotificationSource.fcmTap,
      );

      final success = await router.routePayload(payload);
      expect(success, isTrue);

      expect(testObserver.pushedRoutes, isNotEmpty);
      final pushedRoute = testObserver.pushedRoutes.last as MaterialPageRoute;
      final destination = pushedRoute.builder(testNavKey.currentContext!);
      expect(destination, isA<DoctorNotificationsScreen>());
    });

    testWidgets('Unsupported types fallback to role notification inbox', (tester) async {
      await tester.pumpWidget(buildTestApp(const Text('Patient Dashboard')));

      final router = NotificationRouter(
        navigatorKey: testNavKey,
        currentUserIdResolver: () => 'p_user_1',
        profileResolver: (uid) async => OVUser(
          uid: 'p_user_1',
          name: 'Patient One',
          email: 'p1@test.com',
          medicalId: 'OV-PA-000001',
          role: 'patient',
          createdAt: DateTime.now(),
        ),
      );

      const payload = AppNotificationPayload(
        type: 'consent',
        referenceId: 'con_123',
        title: 'Consent Request',
        body: 'Doctor requested access',
        source: NotificationSource.fcmTap,
      );

      final success = await router.routePayload(payload);
      expect(success, isTrue);

      expect(testObserver.pushedRoutes, isNotEmpty);
      final pushedRoute = testObserver.pushedRoutes.last as MaterialPageRoute;
      final destination = pushedRoute.builder(testNavKey.currentContext!);
      expect(destination, isA<NotificationsScreen>());
    });

    testWidgets('Unauthenticated user rejects navigation safely', (tester) async {
      await tester.pumpWidget(buildTestApp(const Text('App Root')));

      final router = NotificationRouter(
        navigatorKey: testNavKey,
        currentUserIdResolver: () => null,
      );

      const payload = AppNotificationPayload(
        type: 'appointment',
        referenceId: 'appt_1',
        title: 'Appt',
        body: 'Appt info',
        source: NotificationSource.fcmTap,
      );

      final success = await router.routePayload(payload);
      expect(success, isFalse);
      // No extra route was pushed beyond the initial home route
      expect(testObserver.pushedRoutes.length, equals(1));
    });

    testWidgets('Navigator unavailable returns false safely', (tester) async {
      final unattachedKey = GlobalKey<NavigatorState>();

      final router = NotificationRouter(
        navigatorKey: unattachedKey,
        currentUserIdResolver: () => 'p_user_1',
      );

      const payload = AppNotificationPayload(
        type: 'appointment',
        referenceId: 'appt_1',
        title: 'Appt',
        body: 'Appt info',
        source: NotificationSource.fcmTap,
      );

      final success = await router.routePayload(payload);
      expect(success, isFalse);
    });
  });

  group('Phase 1C Lifecycle, Presenter & Coordinator Tests', () {
    test('consumeInitialAppPayload clears payload upon consumption', () {
      final service = NotificationService();
      expect(service.initialAppPayload, isNull);

      const testPayload = AppNotificationPayload(
        messageId: 'launch_001',
        type: 'appointment',
        referenceId: 'appt_100',
        title: 'Appointment Confirmed',
        body: 'Confirmed for 10am',
        source: NotificationSource.fcmColdStart,
      );

      service.setInitialAppPayloadForTesting(testPayload);
      expect(service.initialAppPayload, isNotNull);
      expect(service.initialAppPayload?.messageId, equals('launch_001'));

      final consumed = service.consumeInitialAppPayload();
      expect(consumed?.messageId, equals('launch_001'));
      expect(service.initialAppPayload, isNull);
    });

    testWidgets('ForegroundNotificationPresenter presents SnackBar without auto-navigation', (tester) async {
      final testKey = GlobalKey<NavigatorState>();

      await tester.pumpWidget(MaterialApp(
        navigatorKey: testKey,
        home: const Scaffold(
          body: Center(child: Text('Home')),
        ),
      ));
      await tester.pumpAndSettle();

      final presenter = ForegroundNotificationPresenter(navigatorKey: testKey);

      const payload = AppNotificationPayload(
        messageId: 'fg_01',
        type: 'report',
        title: 'New Pathology Report',
        body: 'Your results are available now',
        source: NotificationSource.fcmForeground,
      );

      final presented = presenter.presentForegroundNotification(payload);
      expect(presented, isTrue);

      await tester.pump();
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('New Pathology Report'), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);

      // Verify no automatic navigation occurred
      expect(find.text('Home'), findsOneWidget);
    });
  });
}
