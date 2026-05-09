// lib/core/utils/hash_comparator.dart

import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../services/hashing_service.dart';

enum IntegrityStatus { verified, tampered, unverified, error }

class IntegrityResult {
  final IntegrityStatus status;
  final String storedHash;
  final String computedHash;
  final String? errorMessage;

  const IntegrityResult({
    required this.status,
    this.storedHash   = '',
    this.computedHash = '',
    this.errorMessage,
  });

  bool get isVerified   => status == IntegrityStatus.verified;
  bool get isTampered   => status == IntegrityStatus.tampered;
  bool get isUnverified => status == IntegrityStatus.unverified;
}

class HashComparator {
  // ── Use singleton, no constructor ────────────────────────────
  final HashingService _hashingService = HashingService.instance;

  // ── Verify remote file from Firebase URL ─────────────────────
  Future<IntegrityResult> verifyRemoteFile({
    required String fileUrl,
    required String storedHash,
  }) async {
    if (storedHash.isEmpty) {
      return const IntegrityResult(status: IntegrityStatus.unverified);
    }

    try {
      final response = await http.get(Uri.parse(fileUrl));

      if (response.statusCode != 200) {
        return IntegrityResult(
          status       : IntegrityStatus.error,
          storedHash   : storedHash,
          errorMessage : 'HTTP ${response.statusCode}',
        );
      }

      // Convert bytes to string then hash
      // Uses hashString() which your HashingService already has
      final Uint8List bytes        = response.bodyBytes;
      final String   bytesAsString = String.fromCharCodes(bytes);
      final String   computedHash  = _hashingService.hashString(bytesAsString);
      final bool     match         = computedHash == storedHash;

      return IntegrityResult(
        status       : match
            ? IntegrityStatus.verified
            : IntegrityStatus.tampered,
        storedHash   : storedHash,
        computedHash : computedHash,
      );
    } catch (e) {
      return IntegrityResult(
        status       : IntegrityStatus.error,
        storedHash   : storedHash,
        errorMessage : e.toString(),
      );
    }
  }

  // ── Quick compare (no download needed) ───────────────────────
  IntegrityResult compareHashes({
    required String storedHash,
    required String computedHash,
  }) {
    if (storedHash.isEmpty) {
      return const IntegrityResult(status: IntegrityStatus.unverified);
    }
    return IntegrityResult(
      status       : storedHash == computedHash
          ? IntegrityStatus.verified
          : IntegrityStatus.tampered,
      storedHash   : storedHash,
      computedHash : computedHash,
    );
  }
}