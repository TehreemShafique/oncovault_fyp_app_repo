// lib/services/fabric_gateway_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

/// Enumerates the verification status of a record on the Hyperledger Fabric ledger.
enum FabricVerificationStatus {
  verified,
  tamperedOrMismatch,
  notAnchored,
  pending,
  verificationUnavailable,
}

extension FabricVerificationStatusX on FabricVerificationStatus {
  String get label {
    switch (this) {
      case FabricVerificationStatus.verified:
        return 'VERIFIED';
      case FabricVerificationStatus.tamperedOrMismatch:
        return 'TAMPERED_OR_MISMATCH';
      case FabricVerificationStatus.notAnchored:
        return 'NOT_ANCHORED';
      case FabricVerificationStatus.pending:
        return 'PENDING';
      case FabricVerificationStatus.verificationUnavailable:
        return 'VERIFICATION_UNAVAILABLE';
    }
  }

  static FabricVerificationStatus fromString(String? s) {
    switch (s?.toUpperCase()) {
      case 'VERIFIED':
        return FabricVerificationStatus.verified;
      case 'TAMPERED_OR_MISMATCH':
        return FabricVerificationStatus.tamperedOrMismatch;
      case 'NOT_ANCHORED':
        return FabricVerificationStatus.notAnchored;
      case 'PENDING':
        return FabricVerificationStatus.pending;
      default:
        return FabricVerificationStatus.verificationUnavailable;
    }
  }
}

/// Represents immutable blockchain proof metadata evaluated from the Fabric ledger.
class FabricProofInfo {
  final String recordId;
  final String sha256Hash;
  final int version;
  final String txId;
  final String timestamp;
  final String status;
  final String? opaqueRecordKey;
  final Map<String, dynamic>? metadata;

  const FabricProofInfo({
    required this.recordId,
    required this.sha256Hash,
    required this.version,
    required this.txId,
    required this.timestamp,
    required this.status,
    this.opaqueRecordKey,
    this.metadata,
  });

  factory FabricProofInfo.fromJson(Map<String, dynamic> json) {
    return FabricProofInfo(
      recordId: json['recordId']?.toString() ?? '',
      sha256Hash: json['sha256Hash']?.toString() ?? '',
      version: json['version'] is int
          ? json['version'] as int
          : int.tryParse(json['version']?.toString() ?? '1') ?? 1,
      txId: json['txId']?.toString() ?? '',
      timestamp: json['timestamp']?.toString() ?? '',
      status: json['status']?.toString() ?? 'ACTIVE',
      opaqueRecordKey: json['opaqueRecordKey']?.toString(),
      metadata: json['metadata'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(json['metadata'] as Map)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'recordId': recordId,
        'sha256Hash': sha256Hash,
        'version': version,
        'txId': txId,
        'timestamp': timestamp,
        'status': status,
        if (opaqueRecordKey != null) 'opaqueRecordKey': opaqueRecordKey,
        if (metadata != null) 'metadata': metadata,
      };
}

/// Represents the cryptographic outcome of verifying a medical record against Hyperledger Fabric.
class FabricVerificationResult {
  final bool verified;
  final FabricVerificationStatus status;
  final String recordId;
  final String targetHash;
  final FabricProofInfo? proof;
  final String message;

  const FabricVerificationResult({
    required this.verified,
    required this.status,
    required this.recordId,
    required this.targetHash,
    this.proof,
    required this.message,
  });

  factory FabricVerificationResult.fromJson(Map<String, dynamic> json) {
    final statusStr = json['status']?.toString();
    final proofJson = json['proof'];
    return FabricVerificationResult(
      verified: json['verified'] == true,
      status: FabricVerificationStatusX.fromString(statusStr),
      recordId: json['recordId']?.toString() ?? '',
      targetHash: json['targetHash']?.toString() ?? '',
      proof: proofJson is Map<String, dynamic>
          ? FabricProofInfo.fromJson(proofJson)
          : null,
      message: json['message']?.toString() ?? '',
    );
  }
}

/// Custom exception thrown on Fabric Gateway API failures.
class FabricGatewayException implements Exception {
  final String code;
  final String message;
  final int statusCode;
  final dynamic details;

  const FabricGatewayException({
    required this.code,
    required this.message,
    required this.statusCode,
    this.details,
  });

  @override
  String toString() =>
      'FabricGatewayException [$code - HTTP $statusCode]: $message';
}

/// Client service for communicating with the trusted OncoVault Fabric Gateway.
/// Bridges the Flutter mobile/desktop app to the real Hyperledger Fabric ledger.
class FabricGatewayService {
  FabricGatewayService._internal({http.Client? httpClient, FirebaseAuth? auth})
      : _client = httpClient ?? http.Client(),
        _auth = auth,
        _customTokenProvider = null;

  @visibleForTesting
  FabricGatewayService.createForTesting({
    http.Client? client,
    FirebaseAuth? auth,
    String? baseUrl,
    Future<String> Function()? tokenProvider,
  })  : _client = client ?? http.Client(),
        _auth = auth,
        _customBaseUrl = baseUrl,
        _customTokenProvider = tokenProvider;

  static FabricGatewayService instance = FabricGatewayService._internal();

  final http.Client _client;
  final FirebaseAuth? _auth;
  final Future<String> Function()? _customTokenProvider;
  final Uuid _uuid = const Uuid();

  String? _customBaseUrl;

  /// Sets an explicit custom base URL (e.g. for testing or staging).
  void setCustomBaseUrl(String? url) {
    _customBaseUrl = url;
  }

  /// Resolves the platform-specific default gateway base URL.
  /// Android Emulator accesses host loopback via 10.0.2.2.
  /// iOS simulator, Desktop (Windows/macOS/Linux), and Web use 127.0.0.1.
  String get baseUrl {
    if (_customBaseUrl != null && _customBaseUrl!.trim().isNotEmpty) {
      return _customBaseUrl!.trim().replaceAll(RegExp(r'/+$'), '');
    }
    const int gatewayPort = int.fromEnvironment('FABRIC_GATEWAY_PORT', defaultValue: 5001);
    if (!kIsWeb && Platform.isAndroid) {
      const bool useAdbReverse = bool.fromEnvironment('USE_ADB_REVERSE', defaultValue: true);
      const bool useEmulators = bool.fromEnvironment('USE_FIREBASE_EMULATORS', defaultValue: false);
      if (useAdbReverse || useEmulators) {
        return 'http://127.0.0.1:$gatewayPort';
      }
      return 'http://10.0.2.2:$gatewayPort';
    }
    return 'http://127.0.0.1:$gatewayPort';
  }

  // ── Authentication & Token Acquisition ─────────────────────────────

  /// Acquires a fresh Firebase ID token for the current authenticated user.
  Future<String> _getAuthToken({bool forceRefresh = false}) async {
    if (_customTokenProvider != null) {
      return _customTokenProvider!();
    }
    final auth = _auth ?? FirebaseAuth.instance;
    final user = auth.currentUser;
    if (user == null) {
      throw const FabricGatewayException(
        code: 'UNAUTHENTICATED',
        message: 'No authenticated Firebase user found. Please sign in.',
        statusCode: 401,
      );
    }
    final token = await user.getIdToken(forceRefresh);
    if (token == null || token.isEmpty) {
      throw const FabricGatewayException(
        code: 'UNAUTHENTICATED',
        message: 'Failed to acquire Firebase ID token.',
        statusCode: 401,
      );
    }
    return token;
  }

  /// Builds standard JSON request headers with Bearer authentication.
  Future<Map<String, String>> _headers({String? idempotencyKey}) async {
    final token = await _getAuthToken();
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (idempotencyKey != null && idempotencyKey.isNotEmpty)
        'X-Idempotency-Key': idempotencyKey,
    };
  }

  // ── Health & Availability ──────────────────────────────────────────

  /// Checks if the Fabric Gateway is online and reachable.
  Future<bool> isGatewayAvailable({Duration timeout = const Duration(seconds: 3)}) async {
    try {
      final res = await _client
          .get(Uri.parse('$baseUrl/health'))
          .timeout(timeout);
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Fetches gateway and dependency readiness status.
  Future<Map<String, dynamic>> checkReady({Duration timeout = const Duration(seconds: 5)}) async {
    try {
      final res = await _client
          .get(Uri.parse('$baseUrl/ready'))
          .timeout(timeout);
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      return {
        'status': 'UNAVAILABLE',
        'error': e.toString(),
      };
    }
  }

  // ── Record Anchoring & Verification ────────────────────────────────

  /// Anchors a medical record hash to the Hyperledger Fabric ledger.
  /// Server reads the authoritative file from storage, computes binary SHA-256,
  /// obtains dual peer endorsement, and commits the transaction.
  Future<FabricProofInfo> anchorRecord({
    required String recordId,
    String? patientId,
    Map<String, dynamic>? metadata,
    String? idempotencyKey,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final uri = Uri.parse('$baseUrl/api/v1/records/anchor');
    final key = idempotencyKey ?? _uuid.v4();
    final headers = await _headers(idempotencyKey: key);

    final payload = {
      'recordId': recordId,
      if (patientId != null) 'patientId': patientId,
      if (metadata != null) 'metadata': metadata,
    };

    try {
      final res = await _client
          .post(uri, headers: headers, body: jsonEncode(payload))
          .timeout(timeout);

      final data = _parseResponse(res);
      final proofJson = data['proof'];
      if (proofJson is! Map<String, dynamic>) {
        throw const FabricGatewayException(
          code: 'INVALID_GATEWAY_RESPONSE',
          message: 'Malformed gateway response: missing proof metadata.',
          statusCode: 502,
        );
      }
      return FabricProofInfo.fromJson(proofJson);
    } on TimeoutException {
      throw const FabricGatewayException(
        code: 'TIMEOUT',
        message: 'Anchoring request timed out waiting for Fabric ledger endorsement.',
        statusCode: 504,
      );
    }
  }

  /// Verifies a medical record's hash against the immutable ledger proof.
  Future<FabricVerificationResult> verifyRecord({
    required String recordId,
    String? patientId,
    String? expectedSha256,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final uri = Uri.parse('$baseUrl/api/v1/records/verify');
    final headers = await _headers();

    final payload = {
      'recordId': recordId,
      if (patientId != null) 'patientId': patientId,
      if (expectedSha256 != null && expectedSha256.isNotEmpty)
        'expectedHash': expectedSha256.toLowerCase(),
    };

    try {
      final res = await _client
          .post(uri, headers: headers, body: jsonEncode(payload))
          .timeout(timeout);

      final data = _parseResponse(res);
      return FabricVerificationResult.fromJson(data);
    } on TimeoutException {
      return FabricVerificationResult(
        verified: false,
        status: FabricVerificationStatus.verificationUnavailable,
        recordId: recordId,
        targetHash: expectedSha256 ?? '',
        message: 'Verification request timed out connecting to Fabric Gateway.',
      );
    } catch (e) {
      if (e is FabricGatewayException) {
        return FabricVerificationResult(
          verified: false,
          status: FabricVerificationStatus.verificationUnavailable,
          recordId: recordId,
          targetHash: expectedSha256 ?? '',
          message: e.message,
        );
      }
      return FabricVerificationResult(
        verified: false,
        status: FabricVerificationStatus.verificationUnavailable,
        recordId: recordId,
        targetHash: expectedSha256 ?? '',
        message: 'Gateway connection failed: $e',
      );
    }
  }

  /// Retrieves the current ledger proof directly from Fabric.
  Future<FabricProofInfo?> getRecordProof(
    String recordId, {
    String? patientId,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final queryParams = patientId != null ? '?patientId=$patientId' : '';
    final uri = Uri.parse('$baseUrl/api/v1/records/$recordId/proof$queryParams');
    final headers = await _headers();

    try {
      final res = await _client.get(uri, headers: headers).timeout(timeout);
      final data = _parseResponse(res);
      final proofJson = data['proof'];
      if (proofJson is Map<String, dynamic>) {
        return FabricProofInfo.fromJson(proofJson);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Retrieves the full immutable audit revision history of a record from Fabric.
  Future<List<Map<String, dynamic>>> getRecordHistory(
    String recordId, {
    String? patientId,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final queryParams = patientId != null ? '?patientId=$patientId' : '';
    final uri = Uri.parse('$baseUrl/api/v1/records/$recordId/history$queryParams');
    final headers = await _headers();

    try {
      final res = await _client.get(uri, headers: headers).timeout(timeout);
      final data = _parseResponse(res);
      final history = data['history'];
      if (history is List) {
        return history.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  // ── Consent Management ─────────────────────────────────────────────

  /// Grants consent from the authenticated patient to a provider.
  /// Gated by `ENABLE_LIVE_CONSENT_MUTATIONS` on the gateway backend.
  Future<Map<String, dynamic>> grantConsent({
    required String providerId,
    required String scope,
    required String expirationTimestamp,
    String? idempotencyKey,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final uri = Uri.parse('$baseUrl/api/v1/consent/grant');
    final key = idempotencyKey ?? _uuid.v4();
    final headers = await _headers(idempotencyKey: key);

    final payload = {
      'providerId': providerId,
      'scope': scope,
      'expirationTimestamp': expirationTimestamp,
    };

    final res = await _client
        .post(uri, headers: headers, body: jsonEncode(payload))
        .timeout(timeout);
    return _parseResponse(res);
  }

  /// Revokes consent previously granted by the authenticated patient.
  /// Gated by `ENABLE_LIVE_CONSENT_MUTATIONS` on the gateway backend.
  Future<Map<String, dynamic>> revokeConsent({
    required String providerId,
    required String scope,
    String? idempotencyKey,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final uri = Uri.parse('$baseUrl/api/v1/consent/revoke');
    final key = idempotencyKey ?? _uuid.v4();
    final headers = await _headers(idempotencyKey: key);

    final payload = {
      'providerId': providerId,
      'scope': scope,
    };

    final res = await _client
        .post(uri, headers: headers, body: jsonEncode(payload))
        .timeout(timeout);
    return _parseResponse(res);
  }

  /// Evaluates whether an active consent grant exists on the Fabric ledger.
  Future<Map<String, dynamic>> checkConsent({
    required String patientId,
    required String providerId,
    required String scope,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final uri = Uri.parse(
      '$baseUrl/api/v1/consent/check?patientId=$patientId&providerId=$providerId&scope=$scope',
    );
    final headers = await _headers();

    final res = await _client.get(uri, headers: headers).timeout(timeout);
    return _parseResponse(res);
  }

  /// Retrieves the immutable consent audit history from the Fabric ledger.
  Future<List<Map<String, dynamic>>> getConsentHistory({
    required String patientId,
    required String providerId,
    required String scope,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final uri = Uri.parse(
      '$baseUrl/api/v1/consent/history?patientId=$patientId&providerId=$providerId&scope=$scope',
    );
    final headers = await _headers();

    final res = await _client.get(uri, headers: headers).timeout(timeout);
    final data = _parseResponse(res);
    final history = data['history'];
    if (history is List) {
      return history.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  // ── Safe Response Parser ───────────────────────────────────────────

  Map<String, dynamic> _parseResponse(http.Response res) {
    Map<String, dynamic> body;
    try {
      body = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      throw FabricGatewayException(
        code: 'PARSE_ERROR',
        message: 'Invalid JSON received from Fabric Gateway: ${res.body}',
        statusCode: res.statusCode,
      );
    }

    if (res.statusCode >= 200 && res.statusCode < 300) {
      final data = body['data'];
      if (data is Map<String, dynamic>) {
        return data;
      }
      return body;
    }

    final errorObj = body['error'];
    final code = errorObj is Map ? errorObj['code']?.toString() ?? 'ERROR' : 'ERROR';
    final msg = errorObj is Map
        ? errorObj['message']?.toString() ?? 'Gateway error'
        : body['message']?.toString() ?? 'Gateway error';

    throw FabricGatewayException(
      code: code,
      message: msg,
      statusCode: res.statusCode,
      details: errorObj is Map ? errorObj['details'] : null,
    );
  }
}
