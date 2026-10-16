// test/screens/nurse/record_vitals_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncovault/screens/nurse/record_vitals_screen.dart';

void main() {
  Widget createWidgetUnderTest() {
    return const MaterialApp(
      home: RecordVitalsScreen(
        patientId: 'PT-10023',
        patientName: 'Amina Bibi',
        doctorId: 'DOC-501',
        doctorName: 'Dr. Tariq Mahmood',
      ),
    );
  }

  testWidgets('RecordVitalsScreen renders patient context and all required fields', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pumpAndSettle();

    // Patient Context
    expect(find.text('Record Patient Vitals'), findsOneWidget);
    expect(find.text('Amina Bibi'), findsOneWidget);
    expect(find.text('Patient ID: PT-10023'), findsOneWidget);
    expect(find.text('Attending Doctor: Dr. Tariq Mahmood'), findsOneWidget);

    // Required Vital Sign Fields
    expect(find.text('Systolic BP'), findsOneWidget);
    expect(find.text('Diastolic BP'), findsOneWidget);
    expect(find.text('Pulse Rate'), findsOneWidget);
    expect(find.text('Resp. Rate'), findsOneWidget);
    expect(find.text('Temperature'), findsOneWidget);
    expect(find.text('Oxygen Sat. (SpO2)'), findsOneWidget);

    // Save Button
    expect(find.text('Save & Record Vitals'), findsOneWidget);
  });

  testWidgets('RecordVitalsScreen shows validation errors for empty fields on submit', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pumpAndSettle();

    // Tap Save button without entering values
    final saveButton = find.text('Save & Record Vitals');
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    // Form validators should fire and show error messages
    expect(find.textContaining('required'), findsWidgets);
  });

  testWidgets('RecordVitalsScreen live updates warning banner when elevated BP is entered', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pumpAndSettle();

    // Enter high systolic BP (150 mmHg)
    final systolicFinder = find.widgetWithText(TextFormField, '');
    expect(systolicFinder, findsWidgets);

    // Enter in systolic text field
    await tester.enterText(systolicFinder.first, '150');
    await tester.pump();

    // Warning banner should become visible
    expect(find.text('Abnormal Vital Sign Warnings'), findsOneWidget);
    expect(find.textContaining('Hypertension'), findsOneWidget);
  });

  testWidgets('Temperature toggle switches between Celsius and Fahrenheit', (WidgetTester tester) async {
    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pumpAndSettle();

    // Initially says "Switch to °F"
    final toggleBtn = find.text('Switch to °F');
    expect(toggleBtn, findsOneWidget);
    expect(find.text('°C'), findsOneWidget);

    // Tap to switch
    await tester.tap(toggleBtn);
    await tester.pump();

    // Now says "Switch to °C" and suffix is °F
    expect(find.text('Switch to °C'), findsOneWidget);
    expect(find.text('°F'), findsOneWidget);
  });
}
