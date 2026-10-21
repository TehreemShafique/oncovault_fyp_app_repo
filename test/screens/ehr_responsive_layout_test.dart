import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:oncovault/models/blood_cancer_ehr_model.dart';
import 'package:oncovault/models/medical_record_model.dart';
import 'package:oncovault/models/appointment_model.dart';
import 'package:oncovault/models/patient_profile_model.dart';
import 'package:oncovault/models/vital_sign_model.dart';
import 'package:oncovault/models/doctor_model.dart';
import 'package:oncovault/services/doctor_service.dart';
import 'package:oncovault/services/nurse_service.dart';
import 'package:oncovault/services/appointment_service.dart';
import 'package:oncovault/screens/patient/blood_cancer_summary_screen.dart';
import 'package:oncovault/screens/doctor/blood_cancer_ehr_screen.dart';
import 'package:oncovault/screens/doctor/doctor_dashboard.dart';
import 'package:oncovault/screens/doctor/doctor_widgets.dart';

const longText =
    'Fictional detailed clinical description requiring natural wrapping across narrow clinical cards and fields.';
const longName = 'Fictional Patient With A Very Long Demonstration Name';
BloodCancerEhrModel record({bool missing = false}) => BloodCancerEhrModel(
    recordId: 'fictional-record',
    patientId: 'demo-patient',
    patientName: longName,
    doctorId: 'demo-doctor',
    doctorName: longName,
    createdAt: DateTime(2026, 10, 20),
    diseaseType: missing ? null : longText,
    stage: missing ? null : longText,
    diagnosisStatus: missing ? null : longText,
    chemotherapy: missing ? null : longText,
    clinicalNotes: missing ? null : longText,
    boneMarrowBiopsy: missing ? null : longText,
    aiAnalysis: missing
        ? null
        : AiAnalysisMetadata(
            prediction: longText,
            riskScore: 0.72,
            modelVersion: longText,
            analyzedAt: DateTime(2026, 10, 20),
            doctorReviewed: true),
    medications: missing ? [] : [longText],
    symptoms: const BloodCancerSymptoms(
        familyHistory: true,
        significantBruisingOrBleeding: true,
        persistentWeaknessAndFatigue: true,
        oralCavityChanges: true),
    cbc: missing
        ? const BloodCancerCbc()
        : const BloodCancerCbc(
            wbc: 11.2,
            rbc: 4.2,
            hemoglobin: 12.2,
            hematocrit: 38.4,
            platelets: 150,
            neutrophils: DifferentialCount(absolute: 5.2, percentage: 51),
            rdwCv: 14,
            rdwSd: 42));

class Doctor extends Fake implements DoctorService {
  final bool empty;
  final bool missing;
  Doctor({this.empty = false, this.missing = false});
  @override
  Stream<List<BloodCancerEhrModel>> watchBloodCancerEhrs(String id) =>
      Stream.value(empty ? [] : [record(missing: missing)]);
  @override
  Stream<List<Never>> watchDoctorNotifications(String id) => Stream.value([]);
  @override
  Stream<List<CriticalAlert>> watchAlerts(String id) => Stream.value(empty
      ? []
      : [
          CriticalAlert(
              id: 'fictional-alert',
              patientId: 'fictional-patient-long-id',
              patientName: longName,
              doctorId: 'demo-doctor',
              alertType: longText,
              severity: 'high',
              title: longText,
              description: longText,
              createdAt: DateTime(2026, 10, 20))
        ]);
  @override
  Future<Map<String, int>> fetchDashboardStats(String id) async =>
      {'totalPatients': 1234, 'pendingRequests': 123, 'criticalAlerts': 42};
  @override
  Stream<List<PatientProfile>> watchDoctorPatients(String id) =>
      Stream.value(empty
          ? []
          : [
              PatientProfile(
                  uid: 'demo-patient',
                  name: longName,
                  email: '',
                  medicalId: 'DEMO-123456789',
                  activeDiagnosis: longText)
            ]);
  @override
  Stream<List<AppointmentModel>> watchDoctorAppointments(String id) =>
      Stream.value(empty
          ? []
          : [
              AppointmentModel(
                  id: 'appt',
                  patientId: 'demo-patient',
                  patientName: longName,
                  doctorId: 'demo-doctor',
                  doctorName: longName,
                  doctorSpecialty: longText,
                  appointmentDate: DateTime.now(),
                  timeSlot: '10:30 AM',
                  status: AppointmentStatus.rescheduled,
                  createdAt: DateTime(2026),
                  notes: longText)
            ]);
}

class Records extends Fake implements MedicalRecordService {
  @override
  Stream<List<MedicalRecordModel>> watchRecords(String id,
          {RecordType? type}) =>
      Stream.value([
        MedicalRecordModel(
            id: 'rx',
            patientId: id,
            title: longText,
            type: RecordType.prescription,
            subtype: 'Prescription',
            facility: 'Demo Facility',
            date: DateTime(2026),
            uploadedAt: DateTime(2026),
            summary: longText,
            fabricTxId: 'fictional-proof-reference')
      ]);
}

class Nurse extends Fake implements NurseService {
  @override
  Stream<VitalSignModel?> watchLatestPatientVitals(String id) =>
      Stream.value(VitalSignModel(
          id: 'v',
          patientId: id,
          recordedAt: DateTime(2026),
          nurseName: longName,
          systolicBp: 120,
          diastolicBp: 80,
          pulseRate: 72,
          temperature: 37,
          respiratoryRate: 16,
          oxygenSaturation: 98));
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });
  Future<void> open(
      WidgetTester t, Widget child, double width, double scale) async {
    t.view.physicalSize = Size(width, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(MaterialApp(
        builder: (_, child) => MediaQuery(
            data: MediaQueryData(
                size: Size(width, 900), textScaler: TextScaler.linear(scale)),
            child: child!),
        home: child));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  }

  Future<void> scrollAll(WidgetTester t) async {
    final scroll = find
        .byType(Scrollable)
        .evaluate()
        .where(
            (e) => (e.widget as Scrollable).axisDirection == AxisDirection.down)
        .first;
    final state = (scroll as StatefulElement).state as ScrollableState;
    for (var i = 0; i < 100; i++) {
      final end = state.position.maxScrollExtent;
      if (state.position.pixels >= end) break;
      state.position.jumpTo((state.position.pixels + 500).clamp(0.0, end));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    }
  }

  for (final width in [320.0, 375.0, 430.0, 768.0, 1366.0]) {
    for (final scale in [1.0, 1.8]) {
      testWidgets('patient complete EHR $width text $scale', (t) async {
        await open(
            t,
            BloodCancerSummaryScreen(
                patientId: 'demo-patient',
                doctorService: Doctor(),
                recordService: Records(),
                nurseService: Nurse()),
            width,
            scale);
        await scrollAll(t);
      });
      testWidgets('doctor view and edit EHR $width text $scale', (t) async {
        await open(
            t,
            BloodCancerEhrScreen(
                patientId: 'demo-patient',
                patientName: longName,
                doctorId: 'demo-doctor',
                doctorName: longName,
                doctorService: Doctor()),
            width,
            scale);
        await scrollAll(t);
        await t.tap(find.text('Edit Mode'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        final scroll = find
            .byType(Scrollable)
            .evaluate()
            .where((e) =>
                (e.widget as Scrollable).axisDirection == AxisDirection.down)
            .first;
        ((scroll as StatefulElement).state as ScrollableState)
            .position
            .jumpTo(0);
        await t.pumpAndSettle();
        await scrollAll(t);
        expect(find.text('Save Updates'), findsWidgets);
      });
      testWidgets('doctor dashboard $width text $scale', (t) async {
        await open(
            t,
            Scaffold(
                body: DoctorDashboardHome(
                    doctorId: 'demo-doctor',
                    doctorName: longName,
                    service: Doctor()),
                bottomNavigationBar:
                    DoctorDashboardNavigation(current: 0, onTap: (_) {})),
            width,
            scale);
        await scrollAll(t);
      });
    }
    testWidgets('empty doctor EHR $width', (t) async {
      await open(
          t,
          BloodCancerEhrScreen(
              patientId: 'demo-patient',
              patientName: longName,
              doctorId: 'demo-doctor',
              doctorName: longName,
              doctorService: Doctor(empty: true)),
          width,
          1.8);
    });
    testWidgets('empty doctor dashboard $width', (t) async {
      await open(
          t,
          Scaffold(
              body: DoctorDashboardHome(
                  doctorId: 'demo-doctor',
                  doctorName: longName,
                  service: Doctor(empty: true)),
              bottomNavigationBar:
                  DoctorDashboardNavigation(current: 0, onTap: (_) {})),
          width,
          1.8);
      await scrollAll(t);
    });
    testWidgets('empty patient EHR $width', (t) async {
      await open(
          t,
          BloodCancerSummaryScreen(
              patientId: 'demo-patient',
              doctorService: Doctor(empty: true),
              recordService: Records(),
              nurseService: Nurse()),
          width,
          1.8);
    });
    testWidgets('missing optional EHR fields $width', (t) async {
      await open(
          t,
          BloodCancerEhrScreen(
              patientId: 'demo-patient',
              patientName: longName,
              doctorId: 'demo-doctor',
              doctorName: longName,
              doctorService: Doctor(missing: true)),
          width,
          1.8);
      await scrollAll(t);
    });
  }
  testWidgets('shared badge remains bounded at the reported 48 pixel width',
      (t) async {
    await open(
        t,
        const Scaffold(
            body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(width: 48, child: BlockchainBadge()))),
        320,
        1);
  });
  testWidgets(
      'prescription card content reproduces 48px width without overflow',
      (t) async {
    final prescription = MedicalRecordModel(
        id: 'rx',
        patientId: 'demo-patient',
        title: longText,
        type: RecordType.prescription,
        subtype: 'Prescription',
        facility: 'Demo',
        date: DateTime(2026),
        uploadedAt: DateTime(2026),
        summary: longText,
        fabricTxId: 'fictional-proof');
    await open(
        t,
        Scaffold(
            body: SingleChildScrollView(
                child: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                        width: 74,
                        child: PatientPrescriptionPreview(
                            record: prescription))))),
        320,
        1);
    expect(t.getSize(find.byType(ResponsiveActionRow)).width, 48);
    expect(t.takeException(), isNull);
  });
}
