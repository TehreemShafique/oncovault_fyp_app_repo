import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import 'fabric_gateway_service.dart';

class ConsentService {
  final FabricGatewayService _gateway;

  ConsentService({FabricGatewayService? gateway})
      : _gateway = gateway ?? FabricGatewayService.instance;

  // Bind a logical action to the last confirmed ledger revision. A timeout retains
  // its key; a screen reload derives the same key from the read-only status check.
  final Map<String, String> _revisions = {};
  final Map<String, String> _requestKeys = {};

  String _requestKey(String doctorId, String action) =>
      _requestKeys.putIfAbsent(
          '$doctorId:$action',
          () => sha256
              .convert(utf8.encode(jsonEncode([
                'consent-v1',
                doctorId,
                scope,
                action,
                _revisions[doctorId] ?? 'initial'
              ])))
              .toString());

  Map<String, dynamic> _confirmedMutation(
      String doctorId, String action, Map<String, dynamic> response) {
    final consent = _consentRecord(response);
    _revisions[doctorId] = consent['txId'] as String;
    _requestKeys.remove('$doctorId:${action == 'grant' ? 'revoke' : 'grant'}');
    return consent;
  }

  static const scope = 'DIRECT_CARE';

  // Mutations use the patient identity from the authenticated gateway token.
  Future<Map<String, dynamic>> grantConsent({required String doctorId}) =>
      _mutate(doctorId, true);

  Future<Map<String, dynamic>> revokeConsent({required String doctorId}) =>
      _mutate(doctorId, false);

  Future<Map<String, dynamic>> _mutate(String doctorId, bool grant) async {
    final action = grant ? 'grant' : 'revoke';
    final key = _requestKey(doctorId, action);
    try {
      final response = grant
          ? await _gateway.grantConsent(
              providerId: doctorId,
              scope: scope,
              expirationTimestamp: 'NEVER',
              idempotencyKey: key)
          : await _gateway.revokeConsent(
              providerId: doctorId, scope: scope, idempotencyKey: key);
      return _confirmedMutation(doctorId, action, response);
    } on FabricGatewayException catch (error) {
      if (error.code == 'CONSENT_REJECTED') {
        // A definitive rejection closes this request. Only a subsequent explicit
        // patient confirmation may send a NEW request. Uncertainty retains its key.
        _requestKeys['$doctorId:$action'] = const Uuid().v4();
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> reconcileConsent(
      {required String doctorId}) async {
    final response =
        await _gateway.reconcileConsent(providerId: doctorId, scope: scope);
    if (response['operationStatus'] == 'NONE') return response;
    final record = _consentRecord(response);
    if (record['status'] == 'GRANTED' || record['status'] == 'REVOKED') {
      // Only a confirmed receipt advances the revision and retires the opposite
      // action's old key, just as a normally completed mutation does.
      return _confirmedMutation(doctorId,
          record['status'] == 'GRANTED' ? 'grant' : 'revoke', response);
    }
    _revisions[doctorId] = record['txId'] as String;
    return record;
  }

  Future<Map<String, dynamic>> checkConsent({
    required String patientId,
    required String doctorId,
  }) async {
    final response = await _gateway.checkConsent(
      patientId: patientId,
      providerId: doctorId,
      scope: scope,
    );
    if (response['active'] is! bool || response['status'] is! String) {
      throw const FormatException(
          'Gateway returned an invalid consent status.');
    }
    final txId = response['txId'];
    if (txId is String && txId.isNotEmpty) _revisions[doctorId] = txId;
    return response;
  }

  Future<List<Map<String, dynamic>>> getHistory({
    required String patientId,
    required String doctorId,
  }) =>
      _gateway.getConsentHistory(
          patientId: patientId, providerId: doctorId, scope: scope);

  Map<String, dynamic> _consentRecord(Map<String, dynamic> response) {
    final consent = response['consent'];
    if (consent is! Map<String, dynamic> ||
        consent['status'] is! String ||
        consent['txId'] is! String ||
        (consent['txId'] as String).isEmpty) {
      throw const FormatException(
        'Gateway response did not include a consent transaction proof. '
        'Check ledger status before retrying.',
      );
    }
    return {
      ...consent,
      if (response['projectionStatus'] != null)
        'projectionStatus': response['projectionStatus'],
    };
  }
}
