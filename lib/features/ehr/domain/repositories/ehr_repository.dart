// lib/features/ehr/data/repositories/ehr_repository.dart

import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../../../../models/medical_record_model.dart';
import '../../../../models/patient_profile_model.dart';
import '../../../../core/services/hashing_service.dart';
import '../../../../core/services/cloud_storage_service.dart';
import '../../../../core/utils/hash_comparator.dart';

/// EhrRepository
/// Single source of truth for all EHR operations:
///   1. Upload CBC report file → get URL
///   2. Hash the file → stamp the record
///   3. Save to Firestore (medical_records collection)
///   4. Verify integrity on demand (re-hash + compare)
///
/// SRS Reference: Module 5 (EHR System), Module 6 (Cloud Storage)
/// FR6.1 – secure storage, FR5.x – integrity verification
class EhrRepository {
  // ─── Dependencies ─────────────────────────────────────────────
  final FirebaseFirestore      _db             = FirebaseFirestore.instance;
  final HashingService         _hashingService = HashingService.instance;
  final CloudStorageService    _cloudStorage   = CloudStorageService.instance;
  final HashComparator         _comparator     = HashComparator();
  final Uuid                   _uuid           = const Uuid();

  // ─── Singleton ────────────────────────────────────────────────
  EhrRepository._internal();
  static final EhrRepository instance = EhrRepository._internal();

  // ─── Firestore collection reference ───────────────────────────
  CollectionReference get _records =>
      _db.collection('medical_records');

  // ════════════════════════════════════════════════════════════════
  // 1. UPLOAD + HASH + SAVE  (main flow)
  // ════════════════════════════════════════════════════════════════

  /// Uploads [file], hashes it, builds a [MedicalRecordModel],
  /// and saves everything to Firestore in one atomic call.
  ///
  /// Returns the saved [MedicalRecordModel] with fileUrl + fileHash filled.
  ///
  /// Usage:
  ///   final record = await EhrRepository.instance.uploadAndSaveRecord(
  ///     patientId : currentUser.uid,
  ///     file      : pickedFile,
  ///     title     : 'CBC Report – May 2025',
  ///     facility  : 'PIMS Hospital',
  ///     doctorName: 'Dr. Aris Thorne',
  ///     summary   : 'Routine CBC — WBC elevated',
  ///   );
  Future<MedicalRecordModel> uploadAndSaveRecord({
    required String patientId,
    required File   file,
    required String title,
    required String facility,
    String          doctorName  = '',
    String          summary     = '',
    String          fileType    = 'pdf',     // 'pdf' | 'image'
    RecordType      recordType  = RecordType.report,
    String          subtype     = 'CBC',
  }) async {
    // ── Step 1: Hash the file BEFORE upload ──────────────────────
    // We hash locally so we have a "pure" fingerprint of the
    // original file. If the file is ever modified in storage,
    // the re-computed hash will no longer match this value.
    final String fileHash = await _hashingService.hashFile(file);

    // ── Step 2: Upload to Firebase Cloud Storage ─────────────────
    final String recordId = _uuid.v4();
    final String storagePath = 'ehr/$patientId/$recordId.$fileType';
    final String fileUrl = await _cloudStorage.uploadFile(
      file        : file,
      storagePath : storagePath,
    );

    // ── Step 3: Build the record model ───────────────────────────
    final now = DateTime.now();
    final MedicalRecordModel record = MedicalRecordModel(
      id          : recordId,
      patientId   : patientId,
      title       : title,
      type        : recordType,
      subtype     : subtype,
      facility    : facility,
      doctorName  : doctorName,
      date        : now,
      fileUrl     : fileUrl,
      fileType    : fileType,
      summary     : summary,
      uploadedAt  : now,
      isArchived  : false,
      fileHash    : fileHash,    // ← stored as "truth" in Firestore
    );

    // ── Step 4: Save to Firestore ─────────────────────────────────
    await _records.doc(recordId).set(record.toMap());

    return record;
  }

  // ════════════════════════════════════════════════════════════════
  // 2. FETCH RECORDS
  // ════════════════════════════════════════════════════════════════

  /// Fetch all non-archived CBC records for [patientId],
  /// ordered by most recent first.
  Future<List<MedicalRecordModel>> fetchRecords(String patientId) async {
    final snap = await _records
        .where('patientId',  isEqualTo: patientId)
        .where('isArchived', isEqualTo: false)
        .orderBy('uploadedAt', descending: true)
        .get();

    return snap.docs
        .map((doc) => MedicalRecordModel.fromMap(doc.data() as Map<String, dynamic>))
        .toList();
  }

  /// Fetch a single record by its [recordId].
  Future<MedicalRecordModel?> fetchRecord(String recordId) async {
    final doc = await _records.doc(recordId).get();
    if (!doc.exists) return null;
    return MedicalRecordModel.fromMap(doc.data() as Map<String, dynamic>);
  }

  // ════════════════════════════════════════════════════════════════
  // 3. VERIFY INTEGRITY
  // ════════════════════════════════════════════════════════════════

  /// Re-downloads the file from [record.fileUrl], re-hashes it,
  /// and compares against [record.fileHash] stored in Firestore.
  ///
  /// Returns [IntegrityResult] with status: verified / tampered / unverified
  ///
  /// Usage (in EHR dashboard, when user taps the badge):
  ///   final result = await EhrRepository.instance.verifyIntegrity(record);
  ///   if (result.isVerified) { show green badge }
  ///   else                   { show red  badge }
  Future<IntegrityResult> verifyIntegrity(MedicalRecordModel record) async {
    // Guard: no hash stored (old record uploaded before hashing was added)
    if (record.fileHash.isEmpty) {
      return const IntegrityResult(status: IntegrityStatus.unverified);
    }

    // Re-download + re-hash from Firebase URL, compare to stored hash
    return await _comparator.verifyRemoteFile(
      fileUrl    : record.fileUrl,
      storedHash : record.fileHash,
    );
  }

  // ════════════════════════════════════════════════════════════════
  // 4. FETCH PATIENT PROFILE (helper used by EHR dashboard)
  // ════════════════════════════════════════════════════════════════

  /// Loads [PatientProfile] from Firestore for the given [patientId].
  /// Tries 'patients' collection first, falls back to 'users'.
  Future<PatientProfile?> fetchPatientProfile(String patientId) async {
    final doc = await _db.collection('patients').doc(patientId).get();
    if (doc.exists) {
      return PatientProfile.fromMap(doc.data()!);
    }
    // Fallback to users collection (matches auth_service.dart logic)
    final userDoc = await _db.collection('users').doc(patientId).get();
    if (userDoc.exists) {
      final d = userDoc.data()!;
      return PatientProfile(
        uid       : patientId,
        name      : d['name']      ?? '',
        email     : d['email']     ?? '',
        medicalId : d['medicalId'] ?? '',
      );
    }
    return null;
  }

  // ════════════════════════════════════════════════════════════════
  // 5. ARCHIVE A RECORD
  // ════════════════════════════════════════════════════════════════

  /// Soft-deletes a record by marking it archived.
  /// Archived records are excluded from fetchRecords().
  Future<void> archiveRecord(String recordId) async {
    await _records.doc(recordId).update({'isArchived': true});
  }
}