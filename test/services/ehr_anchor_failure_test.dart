import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oncovault/services/fabric_gateway_service.dart';

void main() {
  test('EHR endorsement HTTP 500 throws without returning an anchored proof',
      () async {
    var requests = 0;
    final service = FabricGatewayService.createForTesting(
      baseUrl: 'http://127.0.0.1:5001',
      tokenProvider: () async => 'fictional-test-token',
      client: MockClient((request) async {
        requests++;
        expect(request.url.path, '/api/v1/records/anchor');
        return http.Response(
          jsonEncode({
            'success': false,
            'error': {
              'code': 'INTERNAL_ERROR',
              'message': '10 ABORTED: failed to endorse transaction',
            },
          }),
          500,
        );
      }),
    );

    await expectLater(
      service.anchorRecord(
        recordId: 'fictional-ehr',
        patientId: 'fictional-patient',
        metadata: {'documentType': 'BLOOD_CANCER_EHR'},
      ),
      throwsA(isA<FabricGatewayException>()
          .having((error) => error.statusCode, 'HTTP status', 500)
          .having((error) => error.code, 'code', 'INTERNAL_ERROR')),
    );
    expect(requests, 1); // No automatic retry after endorsement failure.
  });
}
