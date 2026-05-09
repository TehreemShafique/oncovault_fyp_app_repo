import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';

/// HashingService
/// Generates a SHA-256 fingerprint for a file or a raw string.
/// Used by EhrRepository to stamp every uploaded report before
/// storing it in Firestore, and again at verification time to
/// compare against the stored hash.
///
/// SRS Reference: FR6.1 (secure storage), EHR integrity check (Module 5)
class HashingService {
  // ─── Singleton ────────────────────────────────────────────────
  HashingService._internal();
  static final HashingService instance = HashingService._internal();

  // ─── Public API ───────────────────────────────────────────────

  /// Returns the SHA-256 hex string of the given [file].
  ///
  /// Usage:
  ///   final hash = await HashingService.instance.hashFile(pickedFile);
  ///   // "e3b0c44298fc1c149afb..."
  Future<String> hashFile(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final digest = sha256.convert(bytes);
      return digest.toString();
    } catch (e) {
      throw HashingException('Failed to hash file: ${file.path}\n$e');
    }
  }

  /// Returns the SHA-256 hex string of a plain [text] string.
  /// Useful for hashing JSON payloads (CBC structured data).
  ///
  /// Usage:
  ///   final hash = HashingService.instance.hashString(jsonEncode(cbcModel));
  String hashString(String text) {
    final bytes = utf8.encode(text);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Compares a freshly computed hash against the stored one.
  /// Returns true  → record is VERIFIED (untampered).
  /// Returns false → record is TAMPERED (mismatch detected).
  ///
  /// Usage (in EhrRepository.verifyIntegrity):
  ///   final fresh = await hashFile(downloadedFile);
  ///   final ok    = verifyHash(fresh, record.storedHash);
  bool verifyHash(String freshHash, String storedHash) {
    return freshHash == storedHash;
  }
}

// ─── Custom Exception ─────────────────────────────────────────
class HashingException implements Exception {
  final String message;
  const HashingException(this.message);

  @override
  String toString() => 'HashingException: $message';
}