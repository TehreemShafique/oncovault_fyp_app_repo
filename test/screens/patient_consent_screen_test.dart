import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncovault/models/doctor_model.dart';
import 'package:oncovault/models/user_model.dart';
import 'package:oncovault/screens/patient/patient_consent_screen.dart';
import 'package:oncovault/services/consent_service.dart';
import 'package:oncovault/services/fabric_gateway_service.dart';

class FakeConsentService extends ConsentService {
  Map<String, dynamic> result = {'active': false, 'status': 'NOT_FOUND'};
  Completer<Map<String, dynamic>>? pending;
  Object? lookupError;
  Object? mutationError;
  String? projectionStatus;
  int recoveries = 0;
  final List<Object> recoveryResponses = [];
  Map<String, dynamic> recoveryResult = {'operationStatus': 'NONE'};
  @override
  Future<Map<String, dynamic>> reconcileConsent(
      {required String doctorId}) async {
    recoveries++;
    if (recoveryResponses.isNotEmpty) {
      final response = recoveryResponses.removeAt(0);
      if (response is Map<String, dynamic>) return response;
      throw response;
    }
    return recoveryResult;
  }

  List<Map<String, dynamic>> history = [];
  Object? historyError;
  @override
  Future<List<Map<String, dynamic>>> getHistory(
      {required String patientId, required String doctorId}) async {
    if (historyError != null) throw historyError!;
    return history;
  }

  String? checkedDoctorId;
  int checks = 0;
  int grants = 0;
  int revocations = 0;

  @override
  Future<Map<String, dynamic>> checkConsent(
      {required String patientId, required String doctorId}) async {
    checks++;
    checkedDoctorId = doctorId;
    if (lookupError != null) throw lookupError!;
    if (pending != null) return await pending!.future;
    return result;
  }

  @override
  Future<Map<String, dynamic>> grantConsent({required String doctorId}) async {
    grants++;
    if (mutationError != null) throw mutationError!;
    return {
      'status': 'GRANTED',
      'txId': 'fictional-grant-proof',
      if (projectionStatus != null) 'projectionStatus': projectionStatus
    };
  }

  @override
  Future<Map<String, dynamic>> revokeConsent({required String doctorId}) async {
    revocations++;
    if (mutationError != null) throw mutationError!;
    return {'status': 'REVOKED', 'txId': 'fictional-revocation-proof'};
  }
}

void main() {
  final doctor = DoctorModel(
      uid: 'fictional-doctor',
      name: 'Dr. Demo Avery',
      email: 'demo@example.test',
      medicalId: 'DEMO-001',
      specialty: 'Hematology',
      hospital: 'Demonstration Hospital',
      createdAt: DateTime(2026));

  Future<void> mount(WidgetTester tester, FakeConsentService service,
      {Stream<List<DoctorModel>>? doctors,
      Size size = const Size(1366, 768)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(
        home: PatientConsentScreen(
      patientId: 'fictional-patient',
      consentService: service,
      doctorsStream: doctors ?? Stream.value([doctor]),
    )));
    await tester.pump();
    addTearDown(() async => tester.pumpWidget(const SizedBox.shrink()));
  }

  Future<void> selectDoctor(WidgetTester tester) async {
    await tester.tap(find.byType(ConsentDoctorDropdown));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dr. Demo Avery').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  for (final revoke in [false, true]) {
    testWidgets(
        'delayed ${revoke ? 'revocation' : 'grant'} recovers after 409 without resubmission',
        (tester) async {
      final service = FakeConsentService()
        ..result = revoke
            ? {'active': true, 'status': 'GRANTED'}
            : {'active': false, 'status': 'NOT_FOUND'}
        ..mutationError = TimeoutException('demo lost response');
      service.recoveryResponses.addAll([
        const FabricGatewayException(
            code: 'CONSENT_PENDING',
            message: 'Still processing',
            statusCode: 409),
        {
          'status': revoke ? 'REVOKED' : 'GRANTED',
          'txId': 'demo-confirmed-transaction',
          'projectionStatus': 'SYNCED'
        },
      ]);
      await mount(tester, service);
      await selectDoctor(tester);
      await tester.tap(find.text(revoke ? 'Revoke Access' : 'Grant Access'));
      await tester.pumpAndSettle();
      await tester
          .tap(find.text(revoke ? 'Confirm revocation' : 'Confirm grant'));
      await tester.pumpAndSettle();
      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('Grant Access'), findsNothing);
      expect(find.text('Revoke Access'), findsNothing);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('Pending'), findsOneWidget);
      expect(service.recoveries, 1);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text(revoke ? 'Revoked' : 'Active'),
          findsNWidgets(revoke ? 2 : 1));
      expect(
          find.textContaining(
              'Your previous access change is not yet confirmed.'),
          findsNothing);
      expect(service.recoveries, 2);
      expect(service.grants, revoke ? 0 : 1);
      expect(service.revocations, revoke ? 1 : 0);
      await tester.pump(const Duration(minutes: 1));
      expect(service.recoveries, 2);
    });
  }

  testWidgets(
      'unavailable Fabric leaves outcome pending and stops after three checks',
      (tester) async {
    final service = FakeConsentService()
      ..mutationError = TimeoutException('demo timeout');
    service.recoveryResponses.addAll(List.filled(
        3,
        const FabricGatewayException(
            code: 'INTERNAL_ERROR',
            message: 'Fabric unavailable',
            statusCode: 500)));
    await mount(tester, service);
    await selectDoctor(tester);
    await tester.tap(find.text('Grant Access'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm grant'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    }
    expect(find.text('Pending'), findsOneWidget);
    expect(
        find.textContaining('Automatic checks have paused.'), findsOneWidget);
    expect(find.text('Check request outcome'), findsOneWidget);
    expect(find.text('Grant Access'), findsNothing);
    expect(find.text('Revoke Access'), findsNothing);
    await tester.pump(const Duration(minutes: 2));
    expect(service.recoveries, 3);
    expect(service.grants, 1);
    expect(service.revocations, 0);
  });

  testWidgets(
      'committed consent with pending projection offers a truthful sync retry',
      (tester) async {
    final service = FakeConsentService()..projectionStatus = 'PENDING';
    await mount(tester, service);
    await selectDoctor(tester);
    await tester.tap(find.text('Grant Access'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm grant'));
    await tester.pumpAndSettle();
    expect(find.text('Sync access update'), findsOneWidget);
    expect(find.text('Revoke Access'), findsNothing);
    await tester.tap(find.text('Sync access update'));
    await tester.pumpAndSettle();
    expect(find.text('Sync confirmed access change?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(service.grants, 1);
  });

  testWidgets(
      'uncertain mutation reports pending without displaying false success',
      (tester) async {
    final service = FakeConsentService()
      ..mutationError = const FabricGatewayException(
          code: 'CONSENT_PENDING', message: 'Outcome unknown', statusCode: 409);
    await mount(tester, service);
    await selectDoctor(tester);
    await tester.tap(find.text('Grant Access'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm grant'));
    await tester.pumpAndSettle();
    expect(
        find.textContaining(
            'Your previous access change is not yet confirmed.'),
        findsOneWidget);
    expect(find.text('Grant Access'), findsNothing);
    expect(find.text('Revoke Access'), findsNothing);
    expect(service.grants, 1);
    expect(find.text('Check request outcome'), findsOneWidget);
    await tester.tap(find.text('Check request outcome'));
    await tester.pumpAndSettle();
    expect(service.recoveries, 1);
    expect(service.grants, 1);
  });

  testWidgets(
      'confirmed projection sync uses recovery instead of another grant',
      (tester) async {
    final service = FakeConsentService()..projectionStatus = 'PENDING';
    await mount(tester, service);
    await selectDoctor(tester);
    await tester.tap(find.text('Grant Access'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm grant'));
    await tester.pumpAndSettle();
    service.recoveryResult = {
      'status': 'GRANTED',
      'txId': 'fictional-grant-proof',
      'projectionStatus': 'SYNCED'
    };
    await tester.tap(find.text('Sync access update'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm sync'));
    await tester.pumpAndSettle();
    expect(service.recoveries, 1);
    expect(service.grants, 1);
    expect(service.revocations, 0);
    expect(find.text('Revoke Access'), findsOneWidget);
    expect(find.text('Sync access update'), findsNothing);
  });

  testWidgets('desktop shows polished sections without automatic ledger calls',
      (tester) async {
    final service = FakeConsentService();
    await mount(tester, service);
    expect(find.text('Doctor Access & Consent'), findsOneWidget);
    expect(find.text('Direct Care'), findsOneWidget);
    expect(find.text('Select a doctor to check their access.'), findsOneWidget);
    expect(find.text('Your care team'), findsOneWidget);
    expect(find.text('Transaction proof'), findsOneWidget);
    expect(find.text('Transaction ID'), findsNothing);
    expect(service.checks, 0);
    expect(service.grants + service.revocations, 0);
  });

  testWidgets('doctor selection loads status and grant requires confirmation',
      (tester) async {
    final service = FakeConsentService();
    await mount(tester, service);
    await selectDoctor(tester);
    expect(service.checkedDoctorId, doctor.uid);
    expect(find.text('Hematology'), findsOneWidget);
    expect(find.text('Demonstration Hospital'), findsOneWidget);
    expect(find.text('No Consent'), findsOneWidget);
    expect(find.text('Not Found'), findsOneWidget);
    expect(find.text('NOT_FOUND'), findsNothing);
    expect(find.text('Ledger status'), findsNothing);
    expect(find.text('Direct Care'), findsNWidgets(2));
    expect(
        find.text(
            'You will be asked to confirm before any access change is requested.'),
        findsNothing);
    expect(find.text('Grant Access'), findsOneWidget);
    expect(find.text('Revoke Access'), findsNothing);
    await tester.ensureVisible(find.text('Grant Access'));
    await tester.tap(find.text('Grant Access'));
    await tester.pumpAndSettle();
    expect(service.grants, 0);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(service.grants, 0);
    await tester.tap(find.text('Grant Access'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm grant'));
    await tester.pumpAndSettle();
    expect(service.grants, 1);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('fictional-grant-proof'), findsOneWidget);
    expect(find.text('Revoke Access'), findsOneWidget);
  });

  testWidgets('active ledger proof and confirmed revocation are displayed',
      (tester) async {
    final service = FakeConsentService()
      ..result = {
        'active': true,
        'status': 'GRANTED',
        'txId': 'fictional-ledger-proof',
        'scope': 'DIRECT_CARE',
        'timestamp': '2026-10-21T10:00:00Z',
      };
    await mount(tester, service);
    await selectDoctor(tester);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('fictional-ledger-proof'), findsOneWidget);
    expect(find.text('Grant Access'), findsNothing);
    await tester.ensureVisible(find.text('Revoke Access'));
    await tester.tap(find.text('Revoke Access'));
    await tester.pumpAndSettle();
    expect(service.revocations, 0);
    await tester.tap(find.text('Confirm revocation'));
    await tester.pumpAndSettle();
    expect(service.revocations, 1);
    expect(find.text('Revoked'), findsWidgets);
    expect(find.text('fictional-revocation-proof'), findsOneWidget);
    expect(find.text('Grant Access'), findsOneWidget);
  });

  testWidgets(
      'disabled mutation shows unavailable without false success or proof',
      (tester) async {
    final service = FakeConsentService()
      ..mutationError = const FabricGatewayException(
          code: 'FEATURE_DISABLED',
          message: 'FEATURE_DISABLED',
          statusCode: 403);
    await mount(tester, service);
    await selectDoctor(tester);
    await tester.ensureVisible(find.text('Grant Access'));
    await tester.tap(find.text('Grant Access'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm grant'));
    await tester.pumpAndSettle();
    expect(find.text('Unavailable'), findsOneWidget);
    expect(find.textContaining('Access changes are currently disabled'),
        findsOneWidget);
    expect(find.text('Active'), findsNothing);
    expect(find.text('Transaction ID'), findsNothing);
    expect(find.text('Grant Access'), findsNothing);
  });

  testWidgets('checking and failed lookup cannot grant access', (tester) async {
    final service = FakeConsentService()..pending = Completer();
    await mount(tester, service);
    await selectDoctor(tester);
    expect(find.text('Checking'), findsOneWidget);
    expect(find.text('Grant Access'), findsNothing);
    service.pending!.completeError(Exception('offline'));
    await tester.pumpAndSettle();
    expect(find.text('Unavailable'), findsOneWidget);
    expect(find.text('No Consent'), findsNothing);
    expect(find.text('Grant Access'), findsNothing);
    expect(service.grants, 0);
  });

  for (final size in [const Size(360, 800), const Size(1366, 768)]) {
    testWidgets('responsive layout at ${size.width} with long proof',
        (tester) async {
      final service = FakeConsentService()
        ..result = {
          'active': true,
          'status': 'GRANTED',
          'txId': 'a' * 64,
        };
      await mount(tester, service, size: size);
      await selectDoctor(tester);
      await tester.ensureVisible(find.text('Transaction proof'));
      await tester.pumpAndSettle();
      expect(find.text('a' * 64), findsOneWidget);
    });
  }

  testWidgets('loading, empty, and doctor stream errors are explicit',
      (tester) async {
    final controller = StreamController<List<DoctorModel>>();
    addTearDown(controller.close);
    await mount(tester, FakeConsentService(), doctors: controller.stream);
    expect(find.text('Loading registered doctors...'), findsOneWidget);
    controller.add([]);
    await tester.pumpAndSettle();
    expect(find.text('No doctors available'), findsOneWidget);
    controller.addError(Exception('unavailable'));
    await tester.pumpAndSettle();
    expect(find.text('Doctors unavailable'), findsOneWidget);
    expect(find.text('Grant Access'), findsNothing);
  });

  testWidgets('doctor removed from stream hides stale proof and actions',
      (tester) async {
    final controller = StreamController<List<DoctorModel>>();
    addTearDown(controller.close);
    final service = FakeConsentService()
      ..result = {
        'active': true,
        'status': 'GRANTED',
        'txId': 'fictional-old-proof',
      };
    await mount(tester, service, doctors: controller.stream);
    controller.add([doctor]);
    await tester.pumpAndSettle();
    await selectDoctor(tester);
    controller.add([]);
    await tester.pumpAndSettle();
    expect(find.text('Unavailable'), findsOneWidget);
    expect(find.text('fictional-old-proof'), findsNothing);
    expect(find.text('Revoke Access'), findsNothing);
  });
  testWidgets('silent doctor listener times out and recovers on retry',
      (tester) async {
    final controller = StreamController<List<DoctorModel>>.broadcast();
    addTearDown(controller.close);
    final service = FakeConsentService();
    await mount(tester, service, doctors: controller.stream);
    await tester.pump(const Duration(seconds: 16));
    expect(find.text('Doctor list timed out'), findsOneWidget);
    expect(find.text('Loading registered doctors...'), findsNothing);
    await tester.tap(find.text('Retry loading doctors'));
    await tester.pump();
    controller.add([doctor]);
    await tester.pumpAndSettle();
    expect(find.byType(ConsentDoctorDropdown), findsOneWidget);
    await selectDoctor(tester);
    expect(service.checkedDoctorId, doctor.uid);
    expect(find.text('No Consent'), findsOneWidget);
  });

  testWidgets('permission denied is distinct from empty doctors',
      (tester) async {
    final controller = StreamController<List<DoctorModel>>();
    addTearDown(controller.close);
    await mount(tester, FakeConsentService(), doctors: controller.stream);
    controller.addError(FirebaseException(
        plugin: 'cloud_firestore', code: 'permission-denied'));
    await tester.pumpAndSettle();
    expect(find.text('Doctor list access denied'), findsOneWidget);
    expect(find.text('No doctors available'), findsNothing);
    expect(find.text('Retry loading doctors'), findsOneWidget);
  });

  testWidgets('three registered doctors are selectable without filtering',
      (tester) async {
    final second = DoctorModel(
        uid: 'fictional-second',
        name: 'Dr. Demo Blake',
        email: 'blake@example.test',
        medicalId: 'DEMO-002',
        createdAt: DateTime(2026),
        isAvailable: false);
    final third = DoctorModel(
        uid: 'fictional-third',
        name: 'Dr. Demo Casey',
        email: 'casey@example.test',
        medicalId: 'DEMO-003',
        createdAt: DateTime(2026));
    final service = FakeConsentService();
    await mount(tester, service,
        doctors: Stream.value([doctor, second, third]));
    await tester.tap(find.byType(ConsentDoctorDropdown));
    await tester.pumpAndSettle();
    expect(find.text(second.name), findsWidgets);
    expect(find.text(third.name), findsWidgets);
    await tester.tap(find.text(second.name).last);
    await tester.pumpAndSettle();
    expect(service.checkedDoctorId, second.uid);
    expect(service.grants + service.revocations, 0);
  });

  testWidgets(
      'unresponsive consent lookup becomes unavailable, never no consent',
      (tester) async {
    final service = FakeConsentService()..pending = Completer();
    await mount(tester, service);
    await selectDoctor(tester);
    expect(find.text('Checking'), findsOneWidget);
    await tester.pump(const Duration(seconds: 13));
    await tester.pumpAndSettle();
    expect(find.text('Unavailable'), findsOneWidget);
    expect(find.text('No Consent'), findsNothing);
    expect(find.text('Grant Access'), findsNothing);
  });

  for (final entry in {'REVOKED': 'Revoked', 'EXPIRED': 'Expired'}.entries) {
    testWidgets('confirmed ${entry.value} allows only a grant', (tester) async {
      final service = FakeConsentService()
        ..result = {'active': false, 'status': entry.key};
      await mount(tester, service);
      await selectDoctor(tester);
      expect(find.text(entry.value), findsWidgets);
      expect(find.text('Grant Access'), findsOneWidget);
      expect(find.text('Revoke Access'), findsNothing);
      expect(find.text('Transaction ID'), findsNothing);
    });
  }

  testWidgets(
      'desktop prioritizes doctor selection and active action above fold',
      (tester) async {
    final service = FakeConsentService()
      ..result = {'active': true, 'status': 'GRANTED'};
    await mount(tester, service);
    await selectDoctor(tester);
    expect(tester.getBottomRight(find.byType(ConsentDoctorDropdown)).dy,
        lessThan(768));
    expect(tester.getBottomRight(find.text('Revoke Access')).dy, lessThan(768));
    expect(find.text('doctor?s'), findsNothing);
    expect(find.text('Loading registered doctors?'), findsNothing);
  });
  test('consent picker accepts the exact ISO date format written by signup',
      () {
    final signup = OVUser(
        uid: 'fictional-doctor',
        name: 'Dr. Demo Avery',
        email: 'demo@example.test',
        medicalId: 'DEMO-001',
        role: 'doctor',
        createdAt: DateTime.utc(2026, 10, 21));
    final data = signup.toMap();
    // Reproduce the old loader failure, then verify the consent-only correction.
    expect(() => DoctorModel.fromMap(data), throwsA(isA<TypeError>()));
    final parsed = consentDoctorFromDocument(signup.uid, data);
    expect(parsed.uid, signup.uid);
    expect(parsed.name, signup.name);
    expect(parsed.createdAt.toUtc(), signup.createdAt.toUtc());
    expect(data['createdAt'], isA<String>());
  });

  test('consent picker preserves Timestamp, DateTime, and epoch dates', () {
    final date = DateTime.utc(2026, 10, 21);
    for (final raw in [
      Timestamp.fromDate(date),
      date,
      date.millisecondsSinceEpoch
    ]) {
      expect(
          consentDoctorFromDocument('fictional', {
            'name': 'Dr. Demo',
            'createdAt': raw,
          }).createdAt.toUtc(),
          date);
    }
    expect(
        () => consentDoctorFromDocument('fictional', {'createdAt': 'invalid'}),
        throwsFormatException);
  });

  testWidgets('signup-shaped doctor snapshots populate the real picker path',
      (tester) async {
    final raw = StreamController<List<Map<String, dynamic>>>();
    addTearDown(raw.close);
    final source = raw.stream.map((docs) => docs
        .map((data) => consentDoctorFromDocument(data['uid'] as String, data))
        .toList());
    final service = FakeConsentService();
    await mount(tester, service, doctors: source);
    raw.add([
      {
        'uid': 'fictional-doctor',
        'name': doctor.name,
        'createdAt': '2026-10-21T00:00:00.000Z'
      }
    ]);
    await tester.pumpAndSettle();
    await selectDoctor(tester);
    expect(service.checkedDoctorId, 'fictional-doctor');
    expect(find.text('No Consent'), findsOneWidget);
  });

  testWidgets('slow snapshot can recover after timeout without retry',
      (tester) async {
    final controller = StreamController<List<DoctorModel>>();
    addTearDown(controller.close);
    await mount(tester, FakeConsentService(), doctors: controller.stream);
    await tester.pump(const Duration(seconds: 16));
    expect(find.text('Doctor list timed out'), findsOneWidget);
    controller.add([doctor]);
    await tester.pumpAndSettle();
    expect(find.byType(ConsentDoctorDropdown), findsOneWidget);
    expect(find.text('Doctor list timed out'), findsNothing);
  });

  testWidgets('Firebase service code and parsing errors are distinguishable',
      (tester) async {
    final controller = StreamController<List<DoctorModel>>();
    addTearDown(controller.close);
    await mount(tester, FakeConsentService(), doctors: controller.stream);
    controller.addError(FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
        message: 'sensitive-detail-must-not-be-rendered'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Service code: unavailable'), findsOneWidget);
    expect(find.textContaining('sensitive-detail'), findsNothing);
    controller.addError(
        const FormatException('sensitive-profile-must-not-be-rendered'));
    await tester.pumpAndSettle();
    expect(find.text('Doctor profile unavailable'), findsOneWidget);
    expect(find.textContaining('sensitive-profile'), findsNothing);
    expect(find.text('No doctors available'), findsNothing);
  });
  testWidgets('dropdown uses white compact menu and scrolls a larger list',
      (tester) async {
    final doctors = List.generate(
        25,
        (i) => DoctorModel(
            uid: 'demo-$i',
            name: i == 24
                ? 'Dr. Demo Last'
                : 'Dr. Demonstration Long Name ' * 4 + '$i',
            email: 'demo$i@example.test',
            medicalId: 'DEMO-$i',
            createdAt: DateTime(2026)));
    final service = FakeConsentService();
    await mount(tester, service,
        doctors: Stream.value(doctors), size: const Size(360, 800));
    await tester.tap(find.byType(ConsentDoctorDropdown));
    await tester.pumpAndSettle();
    final anchor = tester.widget<MenuAnchor>(find.byType(MenuAnchor));
    expect(anchor.style!.backgroundColor!.resolve({}), Colors.white);
    expect(
        anchor.style!.maximumSize!.resolve({})!.height, lessThanOrEqualTo(280));
    final menuScroll =
        tester.state<ScrollableState>(find.byType(Scrollable).last);
    expect(menuScroll.position.maxScrollExtent, greaterThan(0));
    menuScroll.position.jumpTo(menuScroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dr. Demo Last').hitTestable());
    await tester.pumpAndSettle();
    expect(service.checkedDoctorId, 'demo-24');
  });

  testWidgets(
      'proof distinguishes unselected, confirmed empty history, and failed history',
      (tester) async {
    final service = FakeConsentService();
    await mount(tester, service);
    expect(find.textContaining('Choose a doctor to review blockchain'),
        findsOneWidget);
    await selectDoctor(tester);
    expect(find.text('No consent transactions recorded yet.'), findsOneWidget);
    service.historyError = Exception('offline');
    await tester.ensureVisible(find.text('Check status again'));
    await tester.tap(find.text('Check status again'));
    await tester.pumpAndSettle();
    expect(find.text('No Consent'), findsOneWidget);
    expect(find.text('Blockchain consent history is currently unavailable.'),
        findsOneWidget);
    expect(find.textContaining('No consent transactions recorded yet.'),
        findsNothing);
  });

  testWidgets('revoked consent keeps genuine immutable history',
      (tester) async {
    final service = FakeConsentService()
      ..result = {
        'active': false,
        'status': 'REVOKED',
        'revokedAt': '2026-10-21T12:00:00Z'
      }
      ..history = [
        {
          'txId': 'fictional-revoke-history',
          'timestamp': '2026-10-21T12:00:00Z',
          'value': {'status': 'REVOKED'}
        }
      ];
    await mount(tester, service);
    await selectDoctor(tester);
    await tester.ensureVisible(find.text('History (1)'));
    await tester.tap(find.text('History (1)'));
    await tester.pumpAndSettle();
    expect(find.text('fictional-revoke-history'), findsOneWidget);
    expect(find.text('Copy transaction ID'), findsOneWidget);
    expect(find.text('No consent transactions recorded yet.'), findsNothing);
  });

  for (final code in [401, 403]) {
    testWidgets(
        'HTTP $code leaves consent unavailable with no authorization actions',
        (tester) async {
      final service = FakeConsentService()
        ..lookupError = FabricGatewayException(
            code: code == 401 ? 'UNAUTHENTICATED' : 'FORBIDDEN',
            message: 'fictional',
            statusCode: code);
      await mount(tester, service);
      await selectDoctor(tester);
      expect(find.text('Unavailable'), findsOneWidget);
      expect(find.text('Grant Access'), findsNothing);
      expect(find.text('Revoke Access'), findsNothing);
      expect(find.text('Blockchain consent history is currently unavailable.'),
          findsOneWidget);
    });
  }
  testWidgets(
      'dropdown accepts keyboard selection through native menu semantics',
      (tester) async {
    final service = FakeConsentService();
    await mount(tester, service);
    await tester.tap(find.byType(ConsentDoctorDropdown));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(service.checkedDoctorId, doctor.uid);
  });
  for (final size in [const Size(360, 800), const Size(1366, 768)]) {
    testWidgets('popup is below and matches the visible field at ${size.width}',
        (tester) async {
      await mount(tester, FakeConsentService(), size: size);
      final field = find.byType(ConsentDoctorDropdown);
      final rect = tester.getRect(field);
      await tester.tap(field);
      await tester.pumpAndSettle();
      final itemRect = tester.getRect(
          find.byKey(const ValueKey('consent-doctor-option-fictional-doctor')));
      expect(itemRect.top, greaterThanOrEqualTo(rect.bottom + 4));
      expect(itemRect.left, closeTo(rect.left, 2));
      expect(itemRect.width, closeTo(rect.width, 2));
      expect(field.hitTestable(), findsOneWidget);
      await tester.tapAt(const Offset(5, 100));
      await tester.pumpAndSettle();
      expect(find.byType(MenuItemButton), findsNothing);
    });
  }

  testWidgets('successful retry clears previous unavailable status',
      (tester) async {
    final service = FakeConsentService()..lookupError = Exception('offline');
    await mount(tester, service);
    await selectDoctor(tester);
    expect(find.text('Unavailable'), findsOneWidget);
    service.lookupError = null;
    await tester.ensureVisible(find.text('Check status again'));
    await tester.tap(find.text('Check status again'));
    await tester.pumpAndSettle();
    expect(find.text('No Consent'), findsOneWidget);
    expect(find.text('Unavailable'), findsNothing);
  });
  testWidgets('short viewport opens above without covering the field',
      (tester) async {
    await mount(tester, FakeConsentService(), size: const Size(1366, 420));
    final field = find.byType(ConsentDoctorDropdown);
    final rect = tester.getRect(field);
    await tester.tap(field);
    await tester.pumpAndSettle();
    final item = tester.getRect(
        find.byKey(const ValueKey('consent-doctor-option-fictional-doctor')));
    expect(item.bottom, lessThanOrEqualTo(rect.top - 4));
    expect(field.hitTestable(), findsOneWidget);
  });

  testWidgets(
      'popup closes on page scrolling rather than detaching from its anchor',
      (tester) async {
    await mount(tester, FakeConsentService(), size: const Size(360, 800));
    final field = find.byType(ConsentDoctorDropdown);
    await tester.tap(field);
    await tester.pumpAndSettle();
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
    scroll.position.jumpTo(30);
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsNothing);
  });
  for (final code in [404, 500]) {
    testWidgets('HTTP $code stays unavailable without inventing ledger state',
        (tester) async {
      final service = FakeConsentService()
        ..lookupError = FabricGatewayException(
            code: code == 404 ? 'NOT_FOUND' : 'INTERNAL_ERROR',
            message: 'fictional',
            statusCode: code);
      await mount(tester, service);
      await selectDoctor(tester);
      expect(find.text('Unavailable'), findsOneWidget);
      expect(find.text('No Consent'), findsNothing);
      expect(find.text('Grant Access'), findsNothing);
    });
  }

  testWidgets('malformed gateway result is distinguished from no consent',
      (tester) async {
    final service = FakeConsentService()
      ..lookupError = const FabricGatewayException(
          code: 'INVALID_GATEWAY_RESPONSE',
          message: 'fictional',
          statusCode: 502);
    await mount(tester, service);
    await selectDoctor(tester);
    expect(find.textContaining('unreadable consent response'), findsOneWidget);
    expect(find.text('No Consent'), findsNothing);
  });

  testWidgets('resizing closes the popup and preserves its field',
      (tester) async {
    await mount(tester, FakeConsentService());
    await tester.tap(find.byType(ConsentDoctorDropdown));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(1100, 700);
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsNothing);
    expect(find.byType(ConsentDoctorDropdown), findsOneWidget);
  });
  testWidgets('repeated activation opens only one consent confirmation dialog',
      (tester) async {
    final service = FakeConsentService();
    await mount(tester, service);
    await selectDoctor(tester);
    final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Grant Access'));
    button.onPressed!();
    button.onPressed!();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(service.grants + service.revocations, 0);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(service.grants + service.revocations, 0);
    expect(find.text('Grant Access'), findsOneWidget);
  });
}
