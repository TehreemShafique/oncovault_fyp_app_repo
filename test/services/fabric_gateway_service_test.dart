// test/services/fabric_gateway_service_test.dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oncovault/services/fabric_gateway_service.dart';

void main() {
  group('FabricGatewayService Unit Tests', () {
    const testBaseUrl = 'http://127.0.0.1:5001';
    const testToken = 'mock_firebase_id_token_12345';

    test('1. isGatewayAvailable returns true on 200 health check', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, equals('/health'));
        return http.Response(
          jsonEncode({
            'status': 'OK',
            'fabric': {'connected': true, 'channel': 'oncovault-channel'},
          }),
          200,
        );
      });

      final service = FabricGatewayService.createForTesting(
        client: mockClient,
        baseUrl: testBaseUrl,
        tokenProvider: () async => testToken,
      );

      final available = await service.isGatewayAvailable();
      expect(available, isTrue);
    });

    test('2. isGatewayAvailable returns false on HTTP 503 or network failure', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Service Unavailable', 503);
      });

      final service = FabricGatewayService.createForTesting(
        client: mockClient,
        baseUrl: testBaseUrl,
        tokenProvider: () async => testToken,
      );

      final available = await service.isGatewayAvailable();
      expect(available, isFalse);
    });

    test('3. anchorRecord successfully parses COMMITTED response with proof', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, equals('/api/v1/records/anchor'));
        expect(request.headers['Authorization'], equals('Bearer $testToken'));
        expect(request.headers['Content-Type'], contains('application/json'));

        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['recordId'], equals('rec_001'));
        expect(body['patientId'], equals('patient_42'));

        return http.Response(
          jsonEncode({
            'success': true,
            'status': 'COMMITTED',
            'operationId': 'op_123',
            'proof': {
              'recordId': 'rec_001',
              'sha256Hash': 'a'*64,
              'patientPseudonym': '0xABCDEF',
              'txId': 'fab_tx_9999',
              'version': 1,
              'timestamp': '2026-10-16T12:00:00Z',
              'status': 'COMMITTED',
              'opaqueRecordKey': 'key_abc_123',
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = FabricGatewayService.createForTesting(
        client: mockClient,
        baseUrl: testBaseUrl,
        tokenProvider: () async => testToken,
      );

      final proof = await service.anchorRecord(
        recordId: 'rec_001',
        patientId: 'patient_42',
        metadata: {'type': 'LAB_REPORT'},
      );

      expect(proof.recordId, equals('rec_001'));
      expect(proof.status, equals('COMMITTED'));
      expect(proof.txId, equals('fab_tx_9999'));
      expect(proof.version, equals(1));
      expect(proof.opaqueRecordKey, equals('key_abc_123'));
    });

    test('4. verifyRecord returns verified when SHA-256 matches on-chain hash', () async {
      final targetHash = 'b'*64;
      final mockClient = MockClient((request) async {
        expect(request.url.path, equals('/api/v1/records/verify'));
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['expectedHash'], equals(targetHash));

        return http.Response(
          jsonEncode({
            'success': true,
            'verified': true,
            'status': 'VERIFIED',
            'recordId': 'rec_002',
            'proof': {
              'recordId': 'rec_002',
              'sha256Hash': targetHash,
              'patientPseudonym': '0xABC',
              'txId': 'tx_verified_01',
              'version': 1,
              'timestamp': '2026-10-16T12:00:00Z',
              'status': 'COMMITTED',
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = FabricGatewayService.createForTesting(
        client: mockClient,
        baseUrl: testBaseUrl,
        tokenProvider: () async => testToken,
      );

      final res = await service.verifyRecord(
        recordId: 'rec_002',
        expectedSha256: targetHash,
      );

      expect(res.verified, isTrue);
      expect(res.status, equals(FabricVerificationStatus.verified));
      expect(res.proof?.txId, equals('tx_verified_01'));
    });

    test('5. verifyRecord detects tampered record when hash does not match', () async {
      final tamperedHash = 'c'*64;
      final onChainHash = 'd'*64;

      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': true,
            'verified': false,
            'status': 'TAMPERED_OR_MISMATCH',
            'recordId': 'rec_003',
            'expectedHash': tamperedHash,
            'ledgerHash': onChainHash,
            'proof': {
              'recordId': 'rec_003',
              'sha256Hash': onChainHash,
              'patientPseudonym': '0xABC',
              'txId': 'tx_anchor_orig',
              'version': 1,
              'timestamp': '2026-10-16T12:00:00Z',
              'status': 'COMMITTED',
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = FabricGatewayService.createForTesting(
        client: mockClient,
        baseUrl: testBaseUrl,
        tokenProvider: () async => testToken,
      );

      final res = await service.verifyRecord(
        recordId: 'rec_003',
        expectedSha256: tamperedHash,
      );

      expect(res.verified, isFalse);
      expect(res.status, equals(FabricVerificationStatus.tamperedOrMismatch));
      expect(res.proof?.sha256Hash, equals(onChainHash));
    });

    test('6. verifyRecord returns notAnchored on RECORD_NOT_ANCHORED response', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': false,
            'verified': false,
            'status': 'NOT_ANCHORED',
            'recordId': 'rec_unanchored',
            'message': 'Record not found on blockchain ledger',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = FabricGatewayService.createForTesting(
        client: mockClient,
        baseUrl: testBaseUrl,
        tokenProvider: () async => testToken,
      );

      final res = await service.verifyRecord(
        recordId: 'rec_unanchored',
      );

      expect(res.verified, isFalse);
      expect(res.status, equals(FabricVerificationStatus.notAnchored));
    });

    test('7. checkConsent parses active consent response correctly', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, equals('/api/v1/consent/check'));
        expect(request.url.queryParameters['patientId'], equals('pat_10'));
        expect(request.url.queryParameters['providerId'], equals('doc_20'));
        expect(request.url.queryParameters['scope'], equals('BLOOD_CANCER_RESEARCH'));

        return http.Response(
          jsonEncode({
            'success': true,
            'hasConsent': true,
            'patientId': 'pat_10',
            'providerId': 'doc_20',
            'scope': 'BLOOD_CANCER_RESEARCH',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = FabricGatewayService.createForTesting(
        client: mockClient,
        baseUrl: testBaseUrl,
        tokenProvider: () async => testToken,
      );

      final resp = await service.checkConsent(
        patientId: 'pat_10',
        providerId: 'doc_20',
        scope: 'BLOOD_CANCER_RESEARCH',
      );

      expect(resp['hasConsent'], isTrue);
      expect(resp['success'], isTrue);
    });

    test('8. grantConsent throws FabricGatewayException on HTTP 503 gated endpoint', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': false,
            'error': 'GATEWAY_CONSENT_MUTATION_DISABLED',
            'message': 'Direct consent mutation via gateway is disabled',
          }),
          503,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = FabricGatewayService.createForTesting(
        client: mockClient,
        baseUrl: testBaseUrl,
        tokenProvider: () async => testToken,
      );

      expect(
        () => service.grantConsent(
          providerId: 'doc_1',
          scope: 'BLOOD_CANCER_RESEARCH',
          expirationTimestamp: '2027-10-16T12:00:00Z',
        ),
        throwsA(isA<FabricGatewayException>().having((e) => e.statusCode, 'statusCode', 503)),
      );
    });

    test('9. FabricGatewayException formats message and statusCode cleanly', () {
      final ex = FabricGatewayException(
        message: 'Unauthorized caller',
        statusCode: 401,
        code: 'UNAUTHORIZED',
      );

      expect(ex.statusCode, equals(401));
      expect(ex.code, equals('UNAUTHORIZED'));
      expect(ex.toString(), contains('FabricGatewayException [UNAUTHORIZED - HTTP 401]'));
    });
  });
}
