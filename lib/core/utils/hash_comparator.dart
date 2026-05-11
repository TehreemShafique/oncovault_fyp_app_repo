// lib/core/utils/hash_comparator.dart

import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../services/hashing_service.dart';

/// Result of a hash verification check
enum IntegrityStatus {
  verified,   // hashes match — file is untampered
  tampered,   // hashes do NOT match — file was modified
  unverified, // no stored hash exists yet
  error,      // something went wrong during check
}

class IntegrityResult {
  final IntegrityStatus status;
  final String storedHash;
  final String computedHash;
  final String? errorMessage;

  const IntegrityResult({
    required this.status,
    this.storedHash  = '',
    this.computedHash = '',
    this.errorMessage,
  });

  /// Convenience getters for UI badge
  bool get isVerified  => status == IntegrityStatus.verified;
  bool get isTampered  => status == IntegrityStatus.tampered;
  bool get isUnverified => status == IntegrityStatus.unverified;
}

class HashComparator {
  final HashingService _hashingService;

  HashComparator({HashingService? hashingService})
      : _hashingService = hashingService ?? HashingService();

  // ── Verify a LOCAL file against stored hash ──────────
  Future<IntegrityResult> verifyLocalFile({
    required File file,
    required String storedHash,
  }) async {
    // No stored hash means record was saved before hashing was added
    if (storedHash.isEmpty) {
      return const IntegrityResult(status: IntegrityStatus.unverified);
    }

    try {
      final computedHash = await _hashingService.hashFile(file);
      final match = computedHash == storedHash;

      return IntegrityResult(
        status:       match ? IntegrityStatus.verified : IntegrityStatus.tampered,
        storedHash:   storedHash,
        computedHash: computedHash,
      );
    } catch (e) {
      return IntegrityResult(
        status:       IntegrityStatus.error,
        storedHash:   storedHash,
        errorMessage: e.toString(),
      );
    }
  }

  // ── Verify a REMOTE file (Firebase URL) against stored hash ──
  Future<IntegrityResult> verifyRemoteFile({
    required String fileUrl,
    required String storedHash,
  }) async {
    if (storedHash.isEmpty) {
      return const IntegrityResult(status: IntegrityStatus.unverified);
    }

    try {
      // Download file bytes from Firebase Storage URL
      final response = await http.get(Uri.parse(fileUrl));
      if (response.statusCode != 200) {
        return IntegrityResult(
          status:       IntegrityStatus.error,
          storedHash:   storedHash,
          errorMessage: 'Failed to download file: HTTP ${response.statusCode}',
        );
      }

      final Uint8List bytes = response.bodyBytes;
      final computedHash    = _hashingService.hashBytes(bytes);
      final match           = computedHash == storedHash;

      return IntegrityResult(
        status:       match ? IntegrityStatus.verified : IntegrityStatus.tampered,
        storedHash:   storedHash,
        computedHash: computedHash,
      );
    } catch (e) {
      return IntegrityResult(
        status:       IntegrityStatus.error,
        storedHash:   storedHash,
        errorMessage: e.toString(),
      );
    }
  }

  // ── Quick string-only compare (no file download needed) ──
  // Use this if you already have the computed hash from elsewhere
  IntegrityResult compareHashes({
    required String storedHash,
    required String computedHash,
  }) {
    if (storedHash.isEmpty) {
      return const IntegrityResult(status: IntegrityStatus.unverified);
    }

    final match = storedHash == computedHash;
    return IntegrityResult(
      status:       match ? IntegrityStatus.verified : IntegrityStatus.tampered,
      storedHash:   storedHash,
      computedHash: computedHash,
    );
  }
}