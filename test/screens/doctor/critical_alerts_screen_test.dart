// test/screens/doctor/critical_alerts_screen_test.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncovault/models/doctor_model.dart';
import 'package:oncovault/screens/doctor/critical_alerts_screen.dart';
import 'package:oncovault/services/doctor_service.dart';

void main() {
  final testAlert1 = CriticalAlert(
    id: 'alert_001',
    patientId: 'patient_001',
    patientName: 'Jane Doe',
    doctorId: 'doctor_123',
    alertType: 'vital_alert',
    severity: 'high',
    title: 'Critical Vital Alert: Jane Doe',
    description: 'Severe Hypertensive Crisis (BP: 190/115 mmHg)',
    isRead: false,
    isAcknowledged: false,
    eventId: 'event_001',
    observationId: 'obs_001',
    vitalsSummary: {
      'bloodPressure': '190/115 mmHg',
      'heartRate': 120,
      'temperature': 39.2,
      'oxygenSaturation': 89,
    },
    createdAt: DateTime(2026, 10, 17, 10, 0),
  );

  final testAlert2 = CriticalAlert(
    id: 'alert_002',
    patientId: 'patient_002',
    patientName: 'John Smith',
    doctorId: 'doctor_123',
    alertType: 'vital_alert',
    severity: 'medium',
    title: 'Abnormal Vitals: John Smith',
    description: 'Tachycardia and mild fever',
    isRead: true,
    isAcknowledged: true,
    acknowledgedAt: DateTime(2026, 10, 17, 10, 30),
    acknowledgedBy: 'doctor_123',
    acknowledgmentNotes: 'Ordered repeat vitals in 30 mins.',
    eventId: 'event_002',
    observationId: 'obs_002',
    vitalsSummary: {
      'bloodPressure': '135/85 mmHg',
      'heartRate': 105,
      'temperature': 38.3,
      'oxygenSaturation': 96,
    },
    createdAt: DateTime(2026, 10, 17, 9, 30),
  );

  Widget createWidgetUnderTest({
    required Stream<List<CriticalAlert>> stream,
    AcknowledgeAlertCallable? acknowledgeCallable,
    ResolveAlertCallable? resolveCallable,
  }) {
    final mockService = DoctorService(
      watchAlertsStream: (_) => stream,
      acknowledgeCallable: acknowledgeCallable,
      resolveCallable: resolveCallable,
    );

    return MaterialApp(
      home: CriticalAlertsScreen(
        doctorId: 'doctor_123',
        doctorService: mockService,
      ),
    );
  }

  testWidgets('Renders empty state when no alerts exist', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final streamCtrl = StreamController<List<CriticalAlert>>.broadcast();

    await tester.pumpWidget(createWidgetUnderTest(stream: streamCtrl.stream));
    streamCtrl.add([]);
    await tester.pumpAndSettle();

    expect(find.text('Critical Alerts'), findsOneWidget);
    expect(find.text('All Clear'), findsOneWidget);
    expect(find.text('No pending critical alerts at this time.'), findsOneWidget);

    await streamCtrl.close();
  });

  testWidgets('Renders summary chips and alert list with unacknowledged state', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final streamCtrl = StreamController<List<CriticalAlert>>.broadcast();

    await tester.pumpWidget(createWidgetUnderTest(stream: streamCtrl.stream));
    streamCtrl.add([testAlert1, testAlert2]);
    await tester.pumpAndSettle();

    // Summary Chips: 1 unacknowledged, 1 high, 1 medium
    expect(find.text('Unacknowledged'), findsOneWidget);
    expect(find.text('High Severity'), findsOneWidget);
    expect(find.text('Medium'), findsOneWidget);

    // Alert 1 (Unacknowledged)
    expect(find.text('Jane Doe'), findsOneWidget);
    expect(find.text('Severe Hypertensive Crisis (BP: 190/115 mmHg)'), findsOneWidget);
    expect(find.text('UNACKNOWLEDGED'), findsOneWidget);
    expect(find.text('Acknowledge'), findsOneWidget);
    expect(find.text('View Patient Vitals →'), findsWidgets);

    // Alert 2 (Acknowledged)
    expect(find.text('John Smith'), findsOneWidget);
    expect(find.text('Tachycardia and mild fever'), findsOneWidget);
    expect(find.text('ACKNOWLEDGED'), findsOneWidget);
    expect(find.text('Resolve'), findsOneWidget);

    await streamCtrl.close();
  });

  testWidgets('Tapping Acknowledge invokes service callable directly', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final streamCtrl = StreamController<List<CriticalAlert>>.broadcast();

    String? ackDoctorId;
    String? ackAlertId;

    await tester.pumpWidget(createWidgetUnderTest(
      stream: streamCtrl.stream,
      acknowledgeCallable: ({required alertId, required doctorId, notes}) async {
        ackDoctorId = doctorId;
        ackAlertId = alertId;
        return {'success': true};
      },
    ));
    streamCtrl.add([testAlert1]);
    await tester.pumpAndSettle();

    // Find and tap Acknowledge button
    final ackBtn = find.text('Acknowledge');
    expect(ackBtn, findsOneWidget);
    await tester.tap(ackBtn);
    await tester.pumpAndSettle();

    expect(ackDoctorId, 'doctor_123');
    expect(ackAlertId, 'alert_001');

    await streamCtrl.close();
  });

  testWidgets('Tapping Resolve invokes service callable directly', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final streamCtrl = StreamController<List<CriticalAlert>>.broadcast();

    String? resDoctorId;
    String? resAlertId;

    await tester.pumpWidget(createWidgetUnderTest(
      stream: streamCtrl.stream,
      resolveCallable: ({required alertId, required doctorId, notes}) async {
        resDoctorId = doctorId;
        resAlertId = alertId;
        return {'success': true};
      },
    ));
    streamCtrl.add([testAlert2]); // testAlert2 is already acknowledged
    await tester.pumpAndSettle();

    // Find and tap Resolve button
    final resBtn = find.text('Resolve');
    expect(resBtn, findsOneWidget);
    await tester.tap(resBtn);
    await tester.pumpAndSettle();

    expect(resDoctorId, 'doctor_123');
    expect(resAlertId, 'alert_002');

    await streamCtrl.close();
  });
}
