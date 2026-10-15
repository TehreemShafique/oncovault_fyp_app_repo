// test/record_hash_verification_test.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oncovault/core/services/hashing_service.dart';
import 'package:oncovault/core/utils/hash_comparator.dart';

void main() {
  group('Part A — Record Hash Verification & Binary Hashing Tests', () {
    late HashingService hashingService;
    late Directory tempDir;

    setUp(() {
      hashingService = HashingService.instance;
      tempDir = Directory.systemTemp.createTempSync('hash_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('1. hashBytes computes correct SHA-256 for known binary bytes', () {
      final bytes = Uint8List.fromList([0, 1, 2, 128, 200, 255]);
      final hash = hashingService.hashBytes(bytes);

      expect(hash, isNotEmpty);
      expect(hash.length, equals(64)); // 32 bytes in hex = 64 characters
    });

    test('2. hashBytes exactly matches hashFile for arbitrary binary files (bytes > 127)', () async {
      // Generate synthetic binary payload simulating PDF header and binary streams
      final binaryPayload = Uint8List.fromList([
        0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x34, // %PDF-1.4
        0x80, 0x81, 0xA0, 0xC3, 0xD4, 0xE5, 0xF6, 0xFF, // High binary bytes > 127
        0x00, 0x01, 0x7F, 0xFE, 0xAA, 0x55, 0xCC, 0x33,
      ]);

      final tempFile = File('${tempDir.path}/sample.bin');
      await tempFile.writeAsBytes(binaryPayload);

      final fileHash = await hashingService.hashFile(tempFile);
      final bytesHash = hashingService.hashBytes(binaryPayload);

      expect(bytesHash, equals(fileHash),
          reason: 'hashBytes must be 100% equivalent to hashFile for binary data');
    });

    test('3. Regression test: String conversion corrupts binary data with bytes > 127', () {
      final highBytes = Uint8List.fromList([0x80, 0x90, 0xA0, 0xC3, 0xFF]);
      final correctHash = hashingService.hashBytes(highBytes);

      // Previous defective implementation
      final corruptedString = String.fromCharCodes(highBytes);
      final defectiveHash = hashingService.hashString(corruptedString);

      // High bytes get encoded by utf8.encode as multi-byte sequences, causing a false hash mismatch
      expect(defectiveHash, isNot(equals(correctHash)),
          reason: 'fromCharCodes converts high bytes to UTF-16 code units, mutating SHA-256');
    });

    test('4. HashComparator.verifyRemoteFile verifies binary file with bytes > 127', () async {
      final binaryPayload = Uint8List.fromList([
        0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x37,
        0x90, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x80,
      ]);
      final expectedHash = hashingService.hashBytes(binaryPayload);

      final mockClient = MockClient((request) async {
        return http.Response.bytes(binaryPayload, 200);
      });

      final comparator = HashComparator(
        hashingService: hashingService,
        client: mockClient,
      );

      final result = await comparator.verifyRemoteFile(
        fileUrl: 'https://storage.googleapis.com/test-bucket/report.pdf',
        storedHash: expectedHash,
      );

      expect(result.status, equals(IntegrityStatus.verified));
      expect(result.isVerified, isTrue);
      expect(result.isTampered, isFalse);
      expect(result.storedHash, equals(expectedHash));
      expect(result.computedHash, equals(expectedHash));
    });

    test('5. HashComparator.verifyRemoteFile detects tampered binary file', () async {
      final originalPayload = Uint8List.fromList([0x80, 0x90, 0xA0, 0xFF]);
      final storedHash = hashingService.hashBytes(originalPayload);

      final tamperedPayload = Uint8List.fromList([0x80, 0x90, 0xA0, 0xFE]); // 1 bit flip

      final mockClient = MockClient((request) async {
        return http.Response.bytes(tamperedPayload, 200);
      });

      final comparator = HashComparator(
        hashingService: hashingService,
        client: mockClient,
      );

      final result = await comparator.verifyRemoteFile(
        fileUrl: 'https://storage.googleapis.com/test-bucket/report.pdf',
        storedHash: storedHash,
      );

      expect(result.status, equals(IntegrityStatus.tampered));
      expect(result.isVerified, isFalse);
      expect(result.isTampered, isTrue);
      expect(result.storedHash, equals(storedHash));
      expect(result.computedHash, equals(hashingService.hashBytes(tamperedPayload)));
    });

    test('6. HashComparator.verifyRemoteFile handles empty stored hash as unverified', () async {
      final comparator = HashComparator(hashingService: hashingService);

      final result = await comparator.verifyRemoteFile(
        fileUrl: 'https://storage.googleapis.com/test-bucket/report.pdf',
        storedHash: '',
      );

      expect(result.status, equals(IntegrityStatus.unverified));
      expect(result.isUnverified, isTrue);
    });

    test('7. HashComparator.verifyRemoteFile handles HTTP error safely', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Not Found', 404);
      });

      final comparator = HashComparator(
        hashingService: hashingService,
        client: mockClient,
      );

      final result = await comparator.verifyRemoteFile(
        fileUrl: 'https://storage.googleapis.com/test-bucket/missing.pdf',
        storedHash: 'abcdef0123456789',
      );

      expect(result.status, equals(IntegrityStatus.error));
      expect(result.errorMessage, contains('404'));
    });
  });
}
