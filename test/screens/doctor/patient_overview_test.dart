import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:oncovault/models/doctor_model.dart';
import 'package:oncovault/models/blood_cancer_ehr_model.dart';
import 'package:oncovault/screens/doctor/blood_cancer_ehr_screen.dart';
import 'package:oncovault/models/patient_profile_model.dart';
import 'package:oncovault/models/treatment_plan_model.dart';
import 'package:oncovault/screens/doctor/patient_detail_screen.dart';
import 'package:oncovault/screens/doctor/add_diagnosis_screen.dart';
import 'package:oncovault/services/doctor_service.dart';
import 'package:oncovault/services/treatment_tracking_service.dart';

class Doctor extends Fake implements DoctorService {
  final profiles = <String, Future<PatientProfile?>>{};
  final journeys = <String, Stream<List<DiagnosisEntry>>>{};
  final requested = <String>[];
  final failures = <String>{};
  @override
  Stream<List<BloodCancerEhrModel>> watchBloodCancerEhrs(String id) =>
      Stream.value([]);
  @override
  Future<PatientProfile?> fetchPatient(String id) async {
    if (failures.contains(id)) throw Exception('offline');
    return profiles.containsKey(id)
        ? await profiles[id]
        : PatientProfile(
            uid: id, name: 'Demo $id', email: '', medicalId: 'ID-$id');
  }

  @override
  Stream<List<DiagnosisEntry>> watchPatientDiagnoses(String id) {
    requested.add(id);
    return journeys[id] ?? Stream.value([]);
  }
}

class Treatment extends Fake implements TreatmentTrackingService {
  List<TreatmentPlanModel> plans = [];
  @override
  Stream<List<TreatmentPlanModel>> watchPatientTreatmentPlans(String id) =>
      Stream.value(plans);
}

DiagnosisEntry entry(String patient, String title, DateTime date,
        {bool verified = false}) =>
    DiagnosisEntry(
        id: title,
        patientId: patient,
        patientName: '',
        doctorId: 'doctor',
        doctorName: '',
        diagnosisTitle: title,
        diagnosisDetails: 'Recorded observation',
        createdAt: date,
        blockchainVerified: verified);
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });
  Future<void> open(WidgetTester t, Doctor doctor, {String id = 'a'}) async {
    t.view.physicalSize = const Size(1366, 1800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(MaterialApp(
        home: PatientDetailScreen(
            patientId: id,
            doctorId: 'doctor',
            doctorService: doctor,
            treatmentService: Treatment())));
    await t.pumpAndSettle();
  }

  testWidgets('real profile shown without diagnosis badge or invented status',
      (t) async {
    final d = Doctor();
    d.profiles['a'] = Future.value(PatientProfile(
        uid: 'a',
        name: 'Demo Name',
        email: '',
        medicalId: 'REAL-ID',
        dateOfBirth: DateTime(2000, 1, 1),
        address: 'Example City',
        bloodType: 'AB+',
        activeDiagnosis: 'Leukemia badge'));
    await open(t, d);
    expect(find.text('Demo Name'), findsWidgets);
    expect(find.text('PATIENT ID: REAL-ID'), findsOneWidget);
    expect(find.text('AB+'), findsOneWidget);
    expect(find.text('Example City'), findsOneWidget);
    expect(find.text('Leukemia badge'), findsNothing);
    expect(find.text('Stable'), findsNothing);
    expect(find.textContaining('years old'), findsOneWidget);
  });
  testWidgets('missing profile values remain neutral', (t) async {
    final d = Doctor();
    d.profiles['a'] = Future.value(
        PatientProfile(uid: 'a', name: '', email: '', medicalId: ''));
    await open(t, d);
    expect(find.text('Name not recorded'), findsWidgets);
    expect(find.text('Age not recorded'), findsOneWidget);
    expect(find.text('Not recorded'), findsNWidgets(2));
    expect(find.textContaining('22 years'), findsNothing);
    expect(find.textContaining('Rawalpindi'), findsNothing);
  });
  testWidgets('AI and nurse sections absent; legitimate actions remain',
      (t) async {
    await open(t, Doctor());
    for (final text in [
      'AI Insights',
      'REAL-TIME',
      'Treatment Response',
      'Risk Alert',
      'Next Suggestion',
      'Latest Vital Signs',
      'Nursing Clinical Notes'
    ]) {
      expect(find.text(text), findsNothing);
    }
    expect(find.text('Open Patient EHR'), findsOneWidget);
    expect(find.text('Add Diagnosis'), findsOneWidget);
    expect(find.text('Treatment Plan & Supervision'), findsOneWidget);
    final action = t.widget<FloatingActionButton>(find.byWidgetPredicate(
        (w) => w is FloatingActionButton && w.heroTag == 'diagnosis'));
    expect(action.onPressed, isNotNull);
    await t.tap(find.text('Add Diagnosis'));
    await t.pumpAndSettle();
    expect(find.byType(AddDiagnosisScreen), findsOneWidget);
  });
  testWidgets('journey patient filtered and newest first without false proof',
      (t) async {
    final d = Doctor();
    d.journeys['a'] = Stream.value([
      entry('a', 'Older event', DateTime(2025)),
      entry('b', 'Other patient', DateTime(2026)),
      entry('a', 'Newer event', DateTime(2026), verified: true)
    ]);
    await open(t, d);
    expect(find.text('Other patient'), findsNothing);
    expect(t.getTopLeft(find.text('Newer event')).dy,
        lessThan(t.getTopLeft(find.text('Older event')).dy));
    expect(find.text('Blockchain verification not checked'), findsNWidgets(2));
    expect(find.text('Blockchain Verified'), findsNothing);
  });
  testWidgets('empty history has exact neutral message', (t) async {
    await open(t, Doctor());
    expect(find.text('No clinical history recorded yet.'), findsOneWidget);
  });
  testWidgets('history errors are not empty records', (t) async {
    final d = Doctor();
    d.journeys['a'] = Stream.error(Exception('denied'));
    await open(t, d);
    expect(find.text('Clinical history unavailable.'), findsOneWidget);
    expect(find.text('No clinical history recorded yet.'), findsNothing);
  });
  testWidgets('switch clears old patient and ignores late profile response',
      (t) async {
    final d = Doctor();
    final pending = Completer<PatientProfile?>();
    d.profiles['a'] = pending.future;
    Widget screen(String id) => MaterialApp(
        home: PatientDetailScreen(
            patientId: id,
            doctorId: 'doctor',
            doctorService: d,
            treatmentService: Treatment()));
    t.view.physicalSize = const Size(1366, 1800);
    t.view.devicePixelRatio = 1;
    await t.pumpWidget(screen('a'));
    await t.pump();
    await t.pumpWidget(screen('b'));
    await t.pumpAndSettle();
    pending.complete(PatientProfile(
        uid: 'a', name: 'Stale patient', email: '', medicalId: 'old'));
    await t.pumpAndSettle();
    expect(find.text('Stale patient'), findsNothing);
    expect(find.text('Demo b'), findsWidgets);
  });
  testWidgets('switch patient refreshes profile and history', (t) async {
    final d = Doctor();
    d.journeys['a'] = Stream.value([entry('a', 'Old history', DateTime(2025))]);
    d.journeys['b'] = Stream.value([entry('b', 'New history', DateTime(2026))]);
    await open(t, d);
    expect(find.text('Old history'), findsOneWidget);
    await open(t, d, id: 'b');
    expect(find.text('Demo a'), findsNothing);
    expect(find.text('Old history'), findsNothing);
    expect(find.text('New history'), findsOneWidget);
    expect(d.requested, containsAll(['a', 'b']));
  });
  testWidgets('failed patient fetch gives neutral feedback', (t) async {
    final d = Doctor();
    d.failures.add('a');
    await open(t, d);
    expect(find.text('Patient information unavailable.'), findsOneWidget);
  });
  testWidgets('Open Patient EHR keeps the selected patient and doctor',
      (t) async {
    await open(t, Doctor());
    await t.tap(find.text('Open Patient EHR'));
    await t.pumpAndSettle();
    final ehr =
        t.widget<BloodCancerEhrScreen>(find.byType(BloodCancerEhrScreen));
    expect(ehr.patientId, 'a');
    expect(ehr.doctorId, 'doctor');
  });
  testWidgets('missing diagnosis timestamp is never displayed as today',
      (t) async {
    final d = Doctor();
    d.journeys['a'] = Stream.value([
      DiagnosisEntry.fromMap(
          {'patientId': 'a', 'diagnosisTitle': 'Undated event'})
    ]);
    await open(t, d);
    expect(find.text('Date not recorded'), findsOneWidget);
  });
  test(
      'missing treatment fields retain provenance instead of implying clinical facts',
      () {
    final plan = TreatmentPlanModel.fromMap(
        {'planId': 'p', 'patientId': 'a', 'doctorId': 'd', 'title': 'Plan'});
    expect(plan.hasRecordedStatus, isFalse);
    expect(plan.hasRecordedTaskCounts, isFalse);
    expect(plan.copyWith(title: 'Updated').hasRecordedStatus, isFalse);
  });
  testWidgets(
      'genuine supplied leukemia diagnosis remains visible in Clinical Journey',
      (t) async {
    final d = Doctor();
    d.journeys['a'] = Stream.value(
        [entry('a', 'Acute Lymphoblastic Leukemia', DateTime(2026, 5, 14))]);
    await open(t, d);
    expect(find.text('Acute Lymphoblastic Leukemia'), findsOneWidget);
    expect(find.text('MAY 14, 2026'), findsOneWidget);
    expect(find.text('Blockchain verification not checked'), findsOneWidget);
  });
}
