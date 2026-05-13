// lib/features/ehr/data/repositories/ehr_repository_impl.dart

import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../../../../models/medical_record_model.dart';
import '../../../../models/patient_profile_model.dart';
import '../../../../core/services/hashing_service.dart';
import '../../../../core/services/cloud_storage_service.dart';
import '../../../../core/utils/hash_comparator.dart';

class EhrRepositoryImpl {
  final FirebaseFirestore   _db             = FirebaseFirestore.instance;
  final HashingService      _hashingService = HashingService.instance;
  final CloudStorageService _cloudStorage   = CloudStorageService.instance;
  final HashComparator      _comparator     = HashComparator();
  final Uuid                _uuid           = const Uuid();

  EhrRepositoryImpl._internal();
  static final EhrRepositoryImpl instance = EhrRepositoryImpl._internal();

  CollectionReference get _records => _db.collection('medical_records');

  // ── Upload + Hash + Save ──────────────────────────────────────
  Future<MedicalRecordModel> uploadAndSaveRecord({
    required String patientId,
    required File   file,
    required String title,
    required String facility,
    String          doctorName = '',
    String          summary    = '',
    String          fileType   = 'pdf',
    RecordType      recordType = RecordType.report,
    String          subtype    = 'CBC',
  }) async {
    // Step 1: Hash file before upload
    final String fileHash = await _hashingService.hashFile(file);

    // Step 2: Upload using uploadReport() — matches your service
    final String fileName = '${_uuid.v4()}.$fileType';
    final CloudUploadResult uploadResult = await _cloudStorage.uploadReport(
      file     : file,
      fileName : fileName,
    );

    // Step 3: Build model
    final String recordId = _uuid.v4();
    final now = DateTime.now();
    final MedicalRecordModel record = MedicalRecordModel(
      id         : recordId,
      patientId  : patientId,
      title      : title,
      type       : recordType,
      subtype    : subtype,
      facility   : facility,
      doctorName : doctorName,
      date       : now,
      fileUrl    : uploadResult.downloadUrl,
      fileType   : fileType,
      summary    : summary,
      uploadedAt : now,
      isArchived : false,
      fileHash   : fileHash,
    );

    // Step 4: Save to Firestore
    await _records.doc(recordId).set(record.toMap());
    return record;
  }

  // ── Fetch all records ─────────────────────────────────────────
  Future<List<MedicalRecordModel>> fetchRecords(String patientId) async {
    final snap = await _records
        .where('patientId',  isEqualTo: patientId)
        .where('isArchived', isEqualTo: false)
        .orderBy('uploadedAt', descending: true)
        .get();

    return snap.docs
        .map((d) => MedicalRecordModel.fromMap(
        d.data() as Map<String, dynamic>))
        .toList();
  }

  // ── Verify integrity ──────────────────────────────────────────
  Future<IntegrityResult> verifyIntegrity(
      MedicalRecordModel record) async {
    if (record.fileHash.isEmpty) {
      return const IntegrityResult(status: IntegrityStatus.unverified);
    }
    return await _comparator.verifyRemoteFile(
      fileUrl    : record.fileUrl,
      storedHash : record.fileHash,
    );
  }

  // ── Fetch patient profile ─────────────────────────────────────
  Future<PatientProfile?> fetchPatientProfile(String patientId) async {
    final doc = await _db.collection('patients').doc(patientId).get();
    if (doc.exists) return PatientProfile.fromMap(doc.data()!);

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
  // ── Fetch prescriptions for a patient ────────────────────────────
  Future<List<Map<String, dynamic>>> fetchPrescriptions(String patientId) async {
    try {
      final snap = await _db
          .collection('prescriptions')
          .where('patientId', isEqualTo: patientId)
          .orderBy('issuedAt', descending: true)
          .get();
      return snap.docs.map((d) => d.data()).toList();
    } catch (e) {
      // Fallback without orderBy
      final snap = await _db
          .collection('prescriptions')
          .where('patientId', isEqualTo: patientId)
          .get();
      final list = snap.docs.map((d) => d.data()).toList();
      list.sort((a, b) {
        final at = (a['issuedAt'] as Timestamp).toDate();
        final bt = (b['issuedAt'] as Timestamp).toDate();
        return bt.compareTo(at);
      });
      return list;
    }
  }

  // ── Archive record ────────────────────────────────────────────
  Future<void> archiveRecord(String recordId) async {
    await _records.doc(recordId).update({'isArchived': true});
  }
}