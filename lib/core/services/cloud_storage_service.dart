import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// CloudStorageService
/// Handles all Firebase Storage operations for OncoVault.
///
/// Storage path structure:
///   reports/{uid}/{timestamp}_{filename}
///
/// SRS Reference:
///   FR6.1 – Store medical records in secure cloud storage
///   FR6.2 – Low-latency retrieval (returns direct download URL)
///   FR6.4 – Firebase Storage enforces TLS 1.2+ in transit automatically
///
/// Depends on:
///   - firebase_options.dart  → already initialised in main.dart
///   - auth_service.dart      → uses FirebaseAuth.instance.currentUser.uid
///     (no direct import needed — reads uid from FirebaseAuth.instance)
class CloudStorageService {
  // ─── Singleton ────────────────────────────────────────────────
  CloudStorageService._internal();
  static final CloudStorageService instance = CloudStorageService._internal();

  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // ─── Helpers ──────────────────────────────────────────────────

  /// Returns the UID of the currently signed-in user.
  /// Throws [CloudStorageException] if no user is logged in.
  String get _uid {
    final user = _auth.currentUser;
    if (user == null) {
      throw CloudStorageException('No authenticated user found. Please sign in first.');
    }
    return user.uid;
  }

  /// Builds a unique storage path using uid + timestamp + original filename.
  /// Example: reports/abc123/1718000000000_cbc_report.pdf
  String _buildPath(String fileName) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return 'reports/$_uid/${timestamp}_$fileName';
  }

  // ─── Public API ───────────────────────────────────────────────

  /// Uploads [file] to Firebase Storage.
  ///
  /// Returns a [CloudUploadResult] containing:
  ///   - downloadUrl  → permanent HTTPS link to store in Firestore
  ///   - storagePath  → path in bucket (needed for deletion later)
  ///
  /// Usage:
  ///   final result = await CloudStorageService.instance.uploadReport(
  ///     file: pickedFile,
  ///     fileName: 'cbc_report.pdf',
  ///     onProgress: (percent) => setState(() => _progress = percent),
  ///   );
  ///   print(result.downloadUrl);
  Future<CloudUploadResult> uploadReport({
    required File file,
    required String fileName,
    void Function(double percent)? onProgress,
  }) async {
    try {
      final path = _buildPath(fileName);
      final ref = _storage.ref().child(path);

      final uploadTask = ref.putFile(
        file,
        SettableMetadata(
          contentType: _inferContentType(fileName),
          customMetadata: {
            'uploadedBy': _uid,
            'uploadedAt': DateTime.now().toIso8601String(),
          },
        ),
      );

      // Stream upload progress if caller wants it
      if (onProgress != null) {
        uploadTask.snapshotEvents.listen((snapshot) {
          if (snapshot.totalBytes > 0) {
            final percent = snapshot.bytesTransferred / snapshot.totalBytes * 100;
            onProgress(percent);
          }
        });
      }

      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      return CloudUploadResult(
        downloadUrl: downloadUrl,
        storagePath: path,
      );
    } on FirebaseException catch (e) {
      throw CloudStorageException('Upload failed [${e.code}]: ${e.message}');
    } catch (e) {
      throw CloudStorageException('Unexpected upload error: $e');
    }
  }

  /// Downloads a file from [downloadUrl] into a local temp file.
  /// Used by EhrRepository.verifyIntegrity() to re-hash the remote file.
  ///
  /// Usage:
  ///   final tempFile = await CloudStorageService.instance.downloadToTemp(
  ///     downloadUrl: record.reportUrl,
  ///     fileName: 'verify_check.pdf',
  ///   );
  ///   final freshHash = await HashingService.instance.hashFile(tempFile);
  Future<File> downloadToTemp({
    required String downloadUrl,
    required String fileName,
  }) async {
    try {
      final ref = _storage.refFromURL(downloadUrl);
      final tempDir = Directory.systemTemp;
      final tempFile = File('${tempDir.path}/$fileName');

      await ref.writeToFile(tempFile);
      return tempFile;
    } on FirebaseException catch (e) {
      throw CloudStorageException('Download failed [${e.code}]: ${e.message}');
    } catch (e) {
      throw CloudStorageException('Unexpected download error: $e');
    }
  }

  /// Deletes a file from Firebase Storage using its [storagePath].
  /// Call this when a record is deleted from Firestore too.
  ///
  /// Usage:
  ///   await CloudStorageService.instance.deleteReport(
  ///     storagePath: record.storagePath,
  ///   );
  Future<void> deleteReport({required String storagePath}) async {
    try {
      await _storage.ref().child(storagePath).delete();
    } on FirebaseException catch (e) {
      throw CloudStorageException('Delete failed [${e.code}]: ${e.message}');
    }
  }

  // ─── Private Helpers ──────────────────────────────────────────

  /// Infers MIME type from file extension for proper Firebase metadata.
  String _inferContentType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':  return 'application/pdf';
      case 'png':  return 'image/png';
      case 'jpg':
      case 'jpeg': return 'image/jpeg';
      default:     return 'application/octet-stream';
    }
  }
}

// ─── Result Model ─────────────────────────────────────────────

/// Returned by [uploadReport]. Carries both pieces of data
/// that EhrRepository needs to persist in Firestore.
class CloudUploadResult {
  final String downloadUrl;   // store as reportUrl in ehr_record_model
  final String storagePath;   // store as storagePath for future deletion

  const CloudUploadResult({
    required this.downloadUrl,
    required this.storagePath,
  });
}

// ─── Custom Exception ─────────────────────────────────────────

class CloudStorageException implements Exception {
  final String message;
  const CloudStorageException(this.message);

  @override
  String toString() => 'CloudStorageException: $message';
}