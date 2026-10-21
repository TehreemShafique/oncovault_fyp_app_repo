import 'dart:convert';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oncovault/services/consent_service.dart';
import 'package:oncovault/services/fabric_gateway_service.dart';

ConsentService serviceFor(
    Future<http.Response> Function(http.Request) handler) {
  return ConsentService(
      gateway: FabricGatewayService.createForTesting(
    client: MockClient(handler),
    baseUrl: 'http://fictional-gateway.test',
    tokenProvider: () async => 'fictional-token',
  ));
}

void main() {
  test('confirmed revocation recovery retires the prior completed grant key',
      () async {
    final grantKeys = <String?>[];
    final service = serviceFor((request) async {
      if (request.url.path.endsWith('/revoke')) {
        throw TimeoutException('demo timeout');
      }
      final recovery = request.url.path.endsWith('/reconcile');
      if (!recovery) grantKeys.add(request.headers['X-Idempotency-Key']);
      return http.Response(
          jsonEncode({
            'data': {
              'operationStatus': 'COMMITTED',
              'projectionStatus': 'SYNCED',
              'consent': {
                'status': recovery ? 'REVOKED' : 'GRANTED',
                'txId': recovery
                    ? 'demo-revocation'
                    : 'demo-grant-${grantKeys.length}'
              }
            }
          }),
          200);
    });
    await service.grantConsent(doctorId: 'fictional-doctor');
    await expectLater(service.revokeConsent(doctorId: 'fictional-doctor'),
        throwsA(isA<TimeoutException>()));
    await service.reconcileConsent(doctorId: 'fictional-doctor');
    // This is a separate, explicit mocked action after confirmed revocation.
    await service.grantConsent(doctorId: 'fictional-doctor');
    expect(grantKeys, hasLength(2));
    expect(grantKeys[0], isNot(grantKeys[1]));
  });

  for (final action in ['grant', 'revoke']) {
    test('$action timeout and 409 recovery never resubmit a mutation',
        () async {
      final paths = <String>[];
      String? originalKey;
      var recoveryChecks = 0;
      final service = serviceFor((request) async {
        paths.add(request.url.path);
        if (request.url.path == '/api/v1/consent/$action') {
          originalKey = request.headers['X-Idempotency-Key'];
          throw TimeoutException('demo lost response');
        }
        expect(request.url.path, '/api/v1/consent/reconcile');
        expect(jsonDecode(request.body),
            {'providerId': 'fictional-doctor', 'scope': 'DIRECT_CARE'});
        if (recoveryChecks++ == 0) {
          return http.Response(
              '{"error":{"code":"CONSENT_PENDING","message":"Still processing"}}',
              409);
        }
        return http.Response(
            jsonEncode({
              'data': {
                'operationStatus': 'COMMITTED',
                'projectionStatus': 'SYNCED',
                'consent': {
                  'status': action == 'grant' ? 'GRANTED' : 'REVOKED',
                  'txId': 'demo-confirmed-receipt'
                }
              }
            }),
            200);
      });
      await expectLater(
          action == 'grant'
              ? service.grantConsent(doctorId: 'fictional-doctor')
              : service.revokeConsent(doctorId: 'fictional-doctor'),
          throwsA(isA<TimeoutException>()));
      await expectLater(
          service.reconcileConsent(doctorId: 'fictional-doctor'),
          throwsA(isA<FabricGatewayException>()
              .having((e) => e.code, 'code', 'CONSENT_PENDING')));
      final receipt =
          await service.reconcileConsent(doctorId: 'fictional-doctor');
      expect(receipt['status'], action == 'grant' ? 'GRANTED' : 'REVOKED');
      expect(receipt['txId'], 'demo-confirmed-receipt');
      expect(originalKey, isNotEmpty);
      expect(paths.where((p) => p == '/api/v1/consent/$action'), hasLength(1));
      expect(paths, hasLength(3));
    });
  }

  test(
      'existing-operation recovery uses its authenticated endpoint and never grants or revokes',
      () async {
    var requests = 0;
    final service = serviceFor((request) async {
      requests++;
      expect(request.url.path, '/api/v1/consent/reconcile');
      expect(request.headers['Authorization'], 'Bearer fictional-token');
      expect(jsonDecode(request.body),
          {'providerId': 'fictional-doctor', 'scope': 'DIRECT_CARE'});
      return http.Response(
          jsonEncode({
            'data': {'operationStatus': 'NONE'}
          }),
          200);
    });
    expect(
        (await service.reconcileConsent(
            doctorId: 'fictional-doctor'))['operationStatus'],
        'NONE');
    expect(requests, 1);
  });

  test(
      'definitive rejection permits a new explicit request but pending retains its key',
      () async {
    final keys = <String?>[];
    var call = 0;
    final service = serviceFor((request) async {
      keys.add(request.headers['X-Idempotency-Key']);
      final code = call++ == 0 ? 'CONSENT_REJECTED' : 'CONSENT_PENDING';
      return http.Response(
          jsonEncode({
            'error': {'code': code, 'message': code}
          }),
          code == 'CONSENT_REJECTED' ? 422 : 409);
    });
    for (var i = 0; i < 3; i++) {
      await expectLater(service.grantConsent(doctorId: 'fictional-doctor'),
          throwsA(isA<FabricGatewayException>()));
    }
    expect(keys[0], isNot(keys[1]));
    expect(keys[1], keys[2]);
  });

  test(
      'timeout retry and repeated completion retain the same logical request key',
      () async {
    final keys = <String?>[];
    var calls = 0;
    final service = serviceFor((request) async {
      keys.add(request.headers['X-Idempotency-Key']);
      if (calls++ == 0) throw TimeoutException('fictional timeout');
      return http.Response(
          jsonEncode({
            'data': {
              'consent': {'status': 'GRANTED', 'txId': 'fictional-real-proof'},
              'projectionStatus': 'PENDING'
            }
          }),
          200);
    });
    await expectLater(service.grantConsent(doctorId: 'fictional-doctor'),
        throwsA(isA<TimeoutException>()));
    final result = await service.grantConsent(doctorId: 'fictional-doctor');
    await service.grantConsent(doctorId: 'fictional-doctor');
    expect(keys.toSet().length, 1);
    expect(keys.first, isNotEmpty);
    expect(result['projectionStatus'], 'PENDING');
  });

  test(
      'screen reload derives the same key from the same confirmed ledger revision',
      () async {
    final keys = <String?>[];
    Future<http.Response> handler(http.Request request) async {
      if (request.method == 'GET') {
        return http.Response(
            jsonEncode({
              'data': {
                'active': false,
                'status': 'REVOKED',
                'txId': 'fictional-revocation'
              }
            }),
            200);
      }
      keys.add(request.headers['X-Idempotency-Key']);
      throw TimeoutException('fictional lost response');
    }

    for (var i = 0; i < 2; i++) {
      final service = serviceFor(handler);
      await service.checkConsent(
          patientId: 'fictional-patient', doctorId: 'fictional-doctor');
      await expectLater(service.grantConsent(doctorId: 'fictional-doctor'),
          throwsA(isA<TimeoutException>()));
    }
    expect(keys[0], keys[1]);
  });

  test('grant uses public gateway authentication and nested ledger proof',
      () async {
    final service = serviceFor((request) async {
      expect(request.url.path, '/api/v1/consent/grant');
      expect(request.headers['Authorization'], 'Bearer fictional-token');
      expect(jsonDecode(request.body), {
        'providerId': 'fictional-doctor',
        'scope': 'DIRECT_CARE',
        'expirationTimestamp': 'NEVER',
      });
      return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'consent': {'status': 'GRANTED', 'txId': 'fictional-grant-proof'}
            }
          }),
          200);
    });
    final result = await service.grantConsent(doctorId: 'fictional-doctor');
    expect(result['status'], 'GRANTED');
    expect(result['txId'], 'fictional-grant-proof');
  });

  test('revoke preserves the returned revocation proof', () async {
    final service = serviceFor((request) async {
      expect(request.url.path, '/api/v1/consent/revoke');
      expect(jsonDecode(request.body), {
        'providerId': 'fictional-doctor',
        'scope': 'DIRECT_CARE',
      });
      return http.Response(
          jsonEncode({
            'data': {
              'consent': {'status': 'REVOKED', 'txId': 'fictional-revoke-proof'}
            }
          }),
          200);
    });
    final result = await service.revokeConsent(doctorId: 'fictional-doctor');
    expect(result['status'], 'REVOKED');
    expect(result['txId'], 'fictional-revoke-proof');
  });

  test('check is read-only and unwraps genuine active status', () async {
    final service = serviceFor((request) async {
      expect(request.method, 'GET');
      expect(request.url.queryParameters, {
        'patientId': 'fictional-patient',
        'providerId': 'fictional-doctor',
        'scope': 'DIRECT_CARE',
      });
      return http.Response(
          jsonEncode({
            'data': {
              'active': true,
              'status': 'GRANTED',
              'txId': 'fictional-proof'
            }
          }),
          200);
    });
    final result = await service.checkConsent(
        patientId: 'fictional-patient', doctorId: 'fictional-doctor');
    expect(result['active'], true);
    expect(result['txId'], 'fictional-proof');
  });

  test('disabled grants and revocations propagate errors, never success',
      () async {
    final service = serviceFor((_) async => http.Response(
        jsonEncode({
          'error': {
            'code': 'FEATURE_DISABLED',
            'message': 'Consent mutations disabled'
          }
        }),
        403));
    final disabled = isA<FabricGatewayException>()
        .having((e) => e.code, 'code', 'FEATURE_DISABLED');
    await expectLater(
        service.grantConsent(doctorId: 'fictional-doctor'), throwsA(disabled));
    await expectLater(
        service.revokeConsent(doctorId: 'fictional-doctor'), throwsA(disabled));
  });

  test('missing proof and unavailable lookups cannot fabricate consent',
      () async {
    final service = serviceFor((_) async => http.Response('{}', 200));
    await expectLater(service.grantConsent(doctorId: 'fictional-doctor'),
        throwsFormatException);
    await expectLater(
        service.checkConsent(
            patientId: 'fictional-patient', doctorId: 'fictional-doctor'),
        throwsFormatException);
    final offline =
        serviceFor((_) async => throw http.ClientException('offline'));
    await expectLater(
        offline.checkConsent(
            patientId: 'fictional-patient', doctorId: 'fictional-doctor'),
        throwsA(isA<http.ClientException>()));
  });
  for (final status in ['NOT_FOUND', 'GRANTED', 'REVOKED', 'EXPIRED']) {
    test('parses wrapped Fabric $status without inventing proof', () async {
      final service = serviceFor((request) async => http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'active': status == 'GRANTED',
              'status': status,
              'scope': 'DIRECT_CARE'
            },
          }),
          200));
      final response = await service.checkConsent(
          patientId: 'fictional-patient', doctorId: 'fictional-doctor');
      expect(response['status'], status);
      expect(response['txId'], isNull);
    });
  }

  test(
      'history uses existing authenticated endpoint and rejects missing history',
      () async {
    final service = serviceFor((request) async {
      expect(request.url.path, '/api/v1/consent/history');
      expect(request.url.queryParameters['scope'], 'DIRECT_CARE');
      expect(request.headers['Authorization'], 'Bearer fictional-token');
      return http.Response(
          jsonEncode({
            'data': {'history': []}
          }),
          200);
    });
    expect(
        await service.getHistory(
            patientId: 'fictional-patient', doctorId: 'fictional-doctor'),
        isEmpty);
    final malformed =
        serviceFor((_) async => http.Response('{"data":{}}', 200));
    await expectLater(
        malformed.getHistory(
            patientId: 'fictional-patient', doctorId: 'fictional-doctor'),
        throwsA(isA<FabricGatewayException>()));
  });
}
