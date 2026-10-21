import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oncovault/models/blood_cancer_ehr_model.dart';
import 'package:oncovault/screens/doctor/blood_cancer_ehr_screen.dart';
import 'package:oncovault/services/doctor_service.dart';
import 'package:oncovault/services/fabric_gateway_service.dart';

const _hash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

class _Doctor extends Fake implements DoctorService {
  final records = Stream.value([
    BloodCancerEhrModel(
      recordId: 'demo-record',
      patientId: 'demo-patient',
      doctorId: 'demo-doctor',
      doctorName: 'Demo Doctor',
      diagnosisSubtype: 'Historical subtype retained',
      createdAt: DateTime(2026, 10, 20),
      blockchainTxId: 'historical-demo-transaction',
      storedHash: _hash,
    ),
  ]);

  @override
  Stream<List<BloodCancerEhrModel>> watchBloodCancerEhrs(String patientId) =>
      records;
}

void main() {
  Future<void> open(WidgetTester tester, FabricGatewayService gateway) async {
    tester.view.physicalSize = const Size(1366, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: BloodCancerEhrScreen(
      patientId: 'demo-patient',
      patientName: 'Demo Patient',
      doctorId: 'demo-doctor',
      doctorName: 'Demo Doctor',
      doctorService: _Doctor(),
      gateway: gateway,
    )));
    await tester.pumpAndSettle();
    expect(find.text('Diagnosis Subtype'), findsNothing);
    expect(find.text('Historical subtype retained'), findsNothing);
    expect(find.text('Disease Type'), findsOneWidget);
    expect(find.text('Stage / Risk Level'), findsOneWidget);
    expect(find.text('Diagnosis Status'), findsOneWidget);
  }

  Future<void> check(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Check Integrity').last);
    await tester.tap(find.text('Check Integrity').last);
    await tester.pumpAndSettle();
  }

  testWidgets(
      '403 clears fresh success, explains denied consent and preserves historical proof',
      (tester) async {
    var requests = 0;
    final gateway = FabricGatewayService.createForTesting(
      tokenProvider: () async => 'demo-token',
      client: MockClient((request) async {
        requests++;
        expect(request.url.path, '/api/v1/records/verify');
        if (requests == 1) {
          return http.Response(
              jsonEncode({
                'verified': true,
                'status': 'VERIFIED',
                'recordId': 'demo-record',
                'proof': {
                  'recordId': 'demo-record',
                  'sha256Hash': _hash,
                  'txId': 'historical-demo-transaction',
                  'version': 1,
                  'timestamp': '2026-10-20T12:00:00Z',
                  'status': 'ACTIVE',
                  'metadata': {'documentType': 'EHR'}
                },
              }),
              200);
        }
        return http.Response(
            jsonEncode({
              'error': {
                'code': 'ACCESS_DENIED',
                'message': 'Direct Care consent is revoked',
              }
            }),
            403);
      }),
    );
    await open(tester, gateway);
    await check(tester);
    expect(find.text('Blockchain Verified'), findsOneWidget);
    await check(tester);
    expect(find.text('Blockchain Verified'), findsNothing);
    expect(find.textContaining('Live blockchain integrity verified'),
        findsNothing);
    expect(find.text('Access Denied'), findsOneWidget);
    expect(find.text('Cannot Verify Right Now'), findsOneWidget);
    await tester.tap(find.text('View Proof'));
    await tester.pumpAndSettle();
    expect(find.text('historical-demo-transaction'), findsOneWidget);
    expect(find.text(_hash), findsOneWidget);
    expect(find.text('Clinical classification'), findsOneWidget);
    expect(find.text('BLOOD_CANCER_EHR'), findsOneWidget);
    expect(find.text('On-chain document type'), findsOneWidget);
    expect(find.text('EHR'), findsOneWidget);
    expect(find.text('Not available in this proof response'), findsOneWidget);
    expect(find.textContaining('Hospital1MSP'), findsNothing);
    expect(find.textContaining('Org1MSP'), findsNothing);
    expect(
        requests, 2); // Verification only; no retry, anchor or consent request.
    expect(tester.takeException(), isNull);
  });

  testWidgets('cached proof does not invent on-chain metadata or endorsers',
      (tester) async {
    var requests = 0;
    final gateway = FabricGatewayService.createForTesting(
      tokenProvider: () async => 'demo-token',
      client: MockClient((_) async {
        requests++;
        throw StateError('Opening cached proof must not submit or verify');
      }),
    );
    await open(tester, gateway);
    await tester.tap(find.text('View Proof'));
    await tester.pumpAndSettle();
    expect(find.text('BLOOD_CANCER_EHR'), findsOneWidget);
    expect(find.text('EHR'), findsNothing);
    expect(find.text('Unavailable'), findsNWidgets(2));
    expect(find.text('Not available in this proof response'), findsOneWidget);
    expect(find.textContaining('Hospital1MSP'), findsNothing);
    expect(find.textContaining('Org1MSP'), findsNothing);
    expect(find.text('historical-demo-transaction'), findsOneWidget);
    expect(find.text(_hash), findsOneWidget);
    expect(find.text('Committed At'), findsNothing);
    expect(find.text('Record timestamp'), findsOneWidget);
    final label = tester.getRect(find.text('Record timestamp'));
    final value = tester.getRect(find.text('2026-10-20 00:00:00'));
    expect(value.left - label.right, greaterThanOrEqualTo(16));
    expect(tester.takeException(), isNull);
    expect(requests, 0);
  });

  for (final failure in ['timeout', 'network', 'server']) {
    testWidgets(
        '$failure shows unavailable feedback without fresh verification',
        (tester) async {
      var requests = 0;
      final gateway = FabricGatewayService.createForTesting(
        tokenProvider: () async => 'demo-token',
        client: MockClient((request) async {
          requests++;
          expect(request.url.path, '/api/v1/records/verify');
          if (failure == 'timeout') throw TimeoutException('demo timeout');
          if (failure == 'network') throw http.ClientException('demo offline');
          return http.Response(
              jsonEncode({
                'error': {'code': 'INTERNAL_ERROR'}
              }),
              500);
        }),
      );
      await open(tester, gateway);
      await check(tester);
      expect(
          find.textContaining(failure == 'timeout'
              ? 'Verification timed out.'
              : 'Verification unavailable.'),
          findsOneWidget);
      expect(find.textContaining('Access Denied'), findsNothing);
      expect(find.text('Blockchain Verified'), findsNothing);
      expect(requests, 1);
      expect(tester.takeException(), isNull);
    });
  }

  test('verification retains actual 403 separately from integrity status',
      () async {
    final gateway = FabricGatewayService.createForTesting(
      tokenProvider: () async => 'demo-token',
      client: MockClient((_) async =>
          http.Response('{"error":{"code":"ACCESS_DENIED"}}', 403)),
    );
    final result = await gateway.verifyRecord(recordId: 'demo-record');
    expect(result.httpStatusCode, 403);
    expect(result.verified, isFalse);
    expect(result.status, FabricVerificationStatus.verificationUnavailable);
    expect(result.proof, isNull);
  });
}
