import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:oncovault/config/evaluation_scope.dart';
import 'package:oncovault/models/patient_profile_model.dart';
import 'package:oncovault/models/doctor_model.dart';
import 'package:oncovault/models/medical_record_model.dart';
import 'package:oncovault/screens/patient/patient_dashboard.dart';
import 'package:oncovault/screens/doctor/doctor_dashboard.dart';
import 'package:oncovault/screens/doctor/add_diagnosis_screen.dart';
import 'package:oncovault/screens/doctor/patient_list_screen.dart';
import 'package:oncovault/screens/doctor/full_medical_history_screen.dart';
import 'package:oncovault/services/doctor_service.dart';
import 'package:oncovault/services/appointment_service.dart';

const diagnosis =
    'Acute Lymphoblastic Leukemia'; // Explicit fictional fixture, never an application default.
PatientProfile profile(String id, {String diagnosis = ''}) => PatientProfile(
    uid: id,
    name: 'Demo $id',
    email: '',
    medicalId: 'MED-$id',
    activeDiagnosis: diagnosis);

class Doctor extends Fake implements DoctorService {
  DiagnosisEntry? saved;
  @override
  Future<void> addDiagnosis(DiagnosisEntry entry) async {
    saved = entry;
  }

  final profiles = <String, PatientProfile>{};
  @override
  Stream<List<DiagnosisEntry>> watchPatientDiagnoses(String id) =>
      Stream.value([]);
  List<MedicalRecordModel> records = [];
  @override
  Future<PatientProfile?> fetchPatient(String id) async =>
      profiles[id] ?? profile(id);
  @override
  Stream<List<PatientProfile>> watchDoctorPatients(String id) =>
      Stream.value(profiles.values.toList());
  @override
  Stream<List<MedicalRecordModel>> watchPatientRecords(String id) =>
      Stream.value(records);
}

class Appointments extends Fake implements AppointmentService {
  @override
  Stream<List<Never>> watchNotifications(String id) => Stream.value(<Never>[]);
  @override
  Stream<List<Never>> watchPatientAppointments(String id) =>
      Stream.value(<Never>[]);
}

class Db extends Fake implements FirebaseFirestore {
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      Collection();
}

// Firestore interfaces are intentionally faked; no real database is contacted.
// ignore: subtype_of_sealed_class
class Collection extends Fake
    implements CollectionReference<Map<String, dynamic>> {
  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) => Doc(path!);
}

// ignore: subtype_of_sealed_class
class Doc extends Fake implements DocumentReference<Map<String, dynamic>> {
  final String value;
  Doc(this.value);
  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get(
          [GetOptions? options]) async =>
      Snapshot(value);
}

// ignore: subtype_of_sealed_class
class Snapshot extends Fake implements DocumentSnapshot<Map<String, dynamic>> {
  final String value;
  Snapshot(this.value);
  @override
  String get id => value;
  @override
  bool get exists => true;
  @override
  Map<String, dynamic> data() =>
      {'uid': 'stale-uid', 'name': 'Demo', 'medicalId': 'DISPLAY-ID'};
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });
  Future<void> open(WidgetTester t, Widget child) async {
    t.view.physicalSize = const Size(1366, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(MaterialApp(home: Scaffold(body: child)));
    await t.pumpAndSettle();
  }

  testWidgets(
      'empty patient dashboard has no invented diagnosis, vitals or report results',
      (t) async {
    await open(
        t,
        PatientDashboardHome(
            patientId: 'a',
            patientName: 'Demo a',
            greeting: 'Hello',
            firstName: 'Demo',
            apptService: Appointments(),
            doctorService: Doctor()));
    expect(find.text(diagnosis), findsNothing);
    expect(find.text('No diagnosis recorded'), findsOneWidget);
    for (final text in [
      'Latest Vital Signs',
      'Nursing Clinical Notes',
      'Stable',
      'Blood Panels',
      'Updated 2 days ago',
      'Next available Oct 28'
    ]) {
      expect(find.textContaining(text), findsNothing);
    }
    expect(EvaluationScope.showNurseSummaries, isFalse);
  });
  testWidgets(
      'patient diagnosis remains real supplied data and clears on switch',
      (t) async {
    final d = Doctor();
    d.profiles['a'] = profile('a', diagnosis: diagnosis);
    await open(t, PatientDiagnosisCard(patientId: 'a', service: d));
    expect(find.text(diagnosis), findsOneWidget);
    await open(t, PatientDiagnosisCard(patientId: 'b', service: d));
    expect(find.text(diagnosis), findsNothing);
    expect(find.text('No diagnosis recorded'), findsOneWidget);
  });
  testWidgets(
      'recent patient row has genuine diagnosis without invented status or visit',
      (t) async {
    await open(
        t,
        RecentPatientRow(
            patient: profile('a', diagnosis: diagnosis), onTap: () {}));
    expect(find.text(diagnosis), findsOneWidget);
    expect(find.text('Stable'), findsNothing);
    expect(find.textContaining('Recently'), findsNothing);
    expect(find.text('Patient ID: MED-a'), findsOneWidget);
  });
  testWidgets(
      'patient list preserves supplied diagnosis without inferring Stable or New',
      (t) async {
    final d = Doctor();
    d.profiles['a'] = profile('a', diagnosis: diagnosis);
    d.profiles['b'] = profile('b');
    await open(t, PatientListScreen(doctorId: 'doctor', service: d));
    expect(find.text(diagnosis), findsOneWidget);
    expect(find.text('Stable'), findsNothing);
    expect(find.text('New'), findsNothing);
  });
  testWidgets('Labs has no sample CBC, doctors, dates or recommendations',
      (t) async {
    await open(t, ClinicalLabHistoryTab(patientId: 'a', service: Doctor()));
    expect(find.textContaining('No laboratory reports recorded yet.'),
        findsOneWidget);
    for (final text in [
      'Dr. Julian Marks',
      'Sep 02, 2023',
      'Mild elevation in ALT',
      'NORMAL'
    ]) {
      expect(find.textContaining(text), findsNothing);
    }
  });
  testWidgets(
      'Labs displays only matching patient reports and no fresh proof claim',
      (t) async {
    final d = Doctor();
    d.records = [
      for (final id in ['a', 'b'])
        MedicalRecordModel(
            id: 'lab-$id',
            patientId: id,
            title: 'Recorded lab $id',
            type: RecordType.report,
            subtype: 'Pathology',
            facility: 'Demo laboratory',
            doctorName: 'Demo Doctor',
            date: DateTime(2026),
            uploadedAt: DateTime(2026))
    ];
    await open(t, ClinicalLabHistoryTab(patientId: 'a', service: d));
    expect(find.text('Recorded lab a'), findsOneWidget);
    expect(find.text('Recorded lab b'), findsNothing);
    expect(find.text('Blockchain Verified'), findsNothing);
  });
  test('Firestore path UID overrides stale profile uid, never the Medical ID',
      () async {
    final db = Db();
    final p = await DoctorService(firestore: db).fetchPatient('correct-uid');
    expect(p!.uid, 'correct-uid');
    expect(p.medicalId, 'DISPLAY-ID');
  });
  test('missing diagnosis status never defaults to Stable', () {
    expect(DiagnosisEntry.fromMap({}).status, isEmpty);
  });
  testWidgets(
      'Add Diagnosis saves actual input without fabricating Fabric verification',
      (t) async {
    final d = Doctor();
    await open(
        t,
        AddDiagnosisScreen(
            patientId: 'a',
            patientName: 'Demo a',
            doctorId: 'doctor',
            doctorName: 'Demo Doctor',
            service: d));
    await t.enterText(
        find.widgetWithText(TextFormField, 'Diagnosis Title'), diagnosis);
    await t.enterText(find.widgetWithText(TextFormField, 'Diagnosis Details'),
        'Clinician-entered demonstration findings');
    final save = find.text('Save Medical Record');
    await t.ensureVisible(save);
    await t.tap(save);
    await t.pumpAndSettle();
    expect(d.saved, isNotNull);
    expect(d.saved!.patientId, 'a');
    expect(d.saved!.diagnosisTitle, diagnosis);
    expect(d.saved!.blockchainVerified, isFalse);
    expect(find.text('Record Saved!'), findsOneWidget);
  });
  testWidgets(
      '60 percent clinical history retains core EHR tabs and hides nursing-only tabs',
      (t) async {
    await open(
        t,
        FullMedicalHistoryScreen(
            patientId: 'a',
            doctorId: 'doctor',
            patientName: 'Demo a',
            service: Doctor()));
    for (final title in ['History', 'Reports', 'Prescriptions', 'Labs']) {
      expect(find.widgetWithText(Tab, title), findsOneWidget);
    }
    for (final title in ['Vitals', 'Notes']) {
      expect(find.widgetWithText(Tab, title), findsNothing);
    }
    expect(t.widget<TabBar>(find.byType(TabBar)).tabs.length, 4);
  });
}
