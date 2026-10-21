import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:oncovault/models/appointment_model.dart';
import 'package:oncovault/services/appointment_service.dart';
import 'package:oncovault/services/doctor_service.dart';
import 'package:oncovault/screens/doctor/appointment_requests_screen.dart';
import 'package:oncovault/screens/patient/appointment_list_screen.dart';
import 'package:oncovault/screens/doctor/voice_transcription_screen.dart';

final records = [
  for (final status in AppointmentStatus.values)
    AppointmentModel(
        id: status.name,
        patientId: 'patient',
        patientName: 'Patient ${status.name}',
        doctorId: 'doctor',
        doctorName: 'Doctor ${status.name}',
        doctorSpecialty: 'Oncology',
        appointmentDate: DateTime(2026, 10, 20),
        timeSlot: '10:00 AM',
        status: status,
        createdAt: DateTime(2026))
];

class Doctor extends Fake implements DoctorService {
  @override
  Stream<List<AppointmentModel>> watchDoctorAppointments(String id) =>
      Stream.value(records);
  @override
  Stream<List<AppointmentModel>> watchPendingAppointments(String id) =>
      Stream.value([records.first]);
}

class Patient extends Fake implements AppointmentService {
  @override
  Stream<List<AppointmentModel>> watchPatientAppointments(String id) =>
      Stream.value(records);
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });
  for (final width in [360.0, 1366.0]) {
    for (final doctor in [true, false]) {
      testWidgets(
          '${doctor ? "doctor" : "patient"} tabs fill evenly and retain filters at $width',
          (t) async {
        t.view.physicalSize = Size(width, 900);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        await t.pumpWidget(MaterialApp(
            home: doctor
                ? AppointmentRequestsScreen(
                    doctorId: 'doctor',
                    doctorName: 'Demo Doctor',
                    service: Doctor())
                : AppointmentListScreen(
                    patientId: 'patient',
                    patientName: 'Demo Patient',
                    service: Patient())));
        await t.pumpAndSettle();
        final bar = t.widget<TabBar>(find.byType(TabBar));
        expect(bar.indicatorSize, TabBarIndicatorSize.tab);
        expect(bar.isScrollable, isFalse);
        expect(bar.indicatorPadding, EdgeInsets.zero);
        final labels =
            doctor ? ['Pending', 'Upcoming', 'Past'] : ['Upcoming', 'Past'];
        final centers = [
          for (final label in labels)
            t.getCenter(find.widgetWithText(Tab, label)).dx
        ];
        final slot = t.getSize(find.byType(TabBar)).width / labels.length;
        for (var i = 1; i < centers.length; i++) {
          expect(centers[i] - centers[i - 1], closeTo(slot, 1));
        }
        for (final label in labels) {
          await t.tap(find.widgetWithText(Tab, label));
          await t.pumpAndSettle();
          final prefix = doctor ? 'Patient' : 'Doctor';
          final expected = label == 'Pending'
              ? ['scheduled']
              : label == 'Upcoming'
                  ? [if (!doctor) 'scheduled', 'confirmed', 'rescheduled']
                  : ['cancelled', 'completed', 'rejected'];
          for (final status in AppointmentStatus.values) {
            expect(find.text('$prefix ${status.name}'),
                expected.contains(status.name) ? findsOneWidget : findsNothing);
          }
          expect(t.takeException(), isNull);
        }
      });
    }
    testWidgets('NLP has one doctor title and no templates at $width',
        (t) async {
      t.view.physicalSize = Size(width, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(const MaterialApp(
          home: VoiceTranscriptionScreen(
              patientId: 'demo',
              patientName: 'Demo Patient',
              doctorId: 'doctor',
              doctorName: 'Dr. Wania Hamid')));
      await t.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('Attending: Dr. Wania Hamid'), findsOneWidget);
      expect(find.textContaining('Dr. Dr.'), findsNothing);
      for (final label in [
        'Quick Clinical Templates',
        'Leukemia Follow-up (Bruising & CBC)',
        'Acute Presentation with Cytopenias',
        'AML Remission Assessment'
      ]) {
        expect(find.text(label), findsNothing);
      }
      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
      final input = find.byType(TextField);
      expect(input, findsOneWidget);
      await t.enterText(input, 'Fictional demonstration transcript');
      expect(find.text('Fictional demonstration transcript'), findsOneWidget);
      final button =
          find.widgetWithText(ElevatedButton, 'Extract Clinical Information');
      await t.ensureVisible(button);
      await t.pump();
      expect(t.widget<ElevatedButton>(button).onPressed, isNotNull);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  }
  for (final name in [
    'Wania Hamid',
    'Dr. Wania Hamid',
    ' dr . Wania Hamid ',
    'Dr.Wania Hamid',
    'Dr Wania Hamid',
    'Dr.. Wania Hamid',
    'Dr. Dr. Wania Hamid'
  ]) {
    test('doctor title normalized for $name', () {
      expect(formatAttendingDoctorName(name), 'Dr. Wania Hamid');
    });
  }
  test('no mistaken title removal for Drew and no invented name', () {
    expect(formatAttendingDoctorName('Drew'), 'Dr. Drew');
    expect(formatAttendingDoctorName(''), 'Not recorded');
  });
}
