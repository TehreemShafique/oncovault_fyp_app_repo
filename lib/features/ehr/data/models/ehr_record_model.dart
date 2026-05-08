// lib/features/ehr/data/models/ehr_record_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

// ─── Integrity Status ─────────────────────────────────────────
/// Represents the hash-verification state of a single EHR record.
/// Used by IntegrityStatusBadge widget to show Verified / Tampered / Pending.
enum IntegrityStatus {
  verified,  // fresh hash == storedHash  → green badge
  tampered,  // fresh hash != storedHash  → red badge
  pending,   // not yet verified this session → grey badge
}

extension IntegrityStatusX on IntegrityStatus {
  String get label {
    switch (this) {
      case IntegrityStatus.verified: return 'Verified';
      case IntegrityStatus.tampered: return 'Tampered';
      case IntegrityStatus.pending:  return 'Unverified';
    }
  }
}

// ─── EhrRecordModel ───────────────────────────────────────────
/// Stored in Firestore under:
///   ehr_records/{recordId}
///
/// Relationship to MedicalRecordModel:
///   - MedicalRecordModel  → general records (prescriptions, history, etc.)
///   - EhrRecordModel      → CBC-specific records with hash integrity layer
///
/// Both use the same patientId (PatientProfile.uid) as the foreign key.
///
/// SRS Reference:
///   FR6.1  – stores reportUrl (Firebase Storage link)
///   FR5.x  – storedHash enables tamper-proof verification (EHR/blockchain layer)
class EhrRecordModel {
  final String id;           // Firestore document ID (auto-generated)
  final String patientId;    // PatientProfile.uid  ←→  AuthService.currentUser.uid
  final String patientName;  // Denormalized for quick display (no extra Firestore read)
  final String medicalId;    // PatientProfile.medicalId  e.g. "OV-PA-AB12CD"

  // CBC Report fields (SRS: only standard CBC — no bone marrow / genetic)
  final CbcData cbcData;

  // Cloud Storage
  final String reportUrl;    // Firebase Storage download URL
  final String storagePath;  // e.g. "reports/{uid}/{timestamp}_cbc.pdf" — needed for deletion
  final String fileType;     // 'pdf' | 'jpg' | 'png'

  // Integrity (hash layer — replaces blockchain for 30% submission)
  final String storedHash;   // SHA-256 of file at upload time — the "truth"
  IntegrityStatus integrityStatus; // runtime only — NOT stored in Firestore

  // Meta
  final String facility;     // Hospital / lab name
  final String doctorName;   // Ordering doctor
  final String notes;        // Optional clinical notes (voice placeholder)
  final DateTime reportDate; // Date on the physical report
  final DateTime uploadedAt; // When it was uploaded to OncoVault
  final bool isArchived;

  EhrRecordModel({
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.medicalId,
    required this.cbcData,
    required this.reportUrl,
    required this.storagePath,
    this.fileType = 'pdf',
    required this.storedHash,
    this.integrityStatus = IntegrityStatus.pending,
    this.facility = '',
    this.doctorName = '',
    this.notes = '',
    required this.reportDate,
    required this.uploadedAt,
    this.isArchived = false,
  });

  // ─── Firestore Serialization ─────────────────────────────────

  Map<String, dynamic> toMap() => {
    'id':           id,
    'patientId':    patientId,
    'patientName':  patientName,
    'medicalId':    medicalId,
    'cbcData':      cbcData.toMap(),
    'reportUrl':    reportUrl,
    'storagePath':  storagePath,
    'fileType':     fileType,
    'storedHash':   storedHash,
    // integrityStatus is NOT persisted — recomputed at runtime
    'facility':     facility,
    'doctorName':   doctorName,
    'notes':        notes,
    'reportDate':   Timestamp.fromDate(reportDate),
    'uploadedAt':   Timestamp.fromDate(uploadedAt),
    'isArchived':   isArchived,
  };

  factory EhrRecordModel.fromMap(Map<String, dynamic> m) => EhrRecordModel(
    id:           m['id'] ?? '',
    patientId:    m['patientId'] ?? '',
    patientName:  m['patientName'] ?? '',
    medicalId:    m['medicalId'] ?? '',
    cbcData:      CbcData.fromMap(Map<String, dynamic>.from(m['cbcData'] ?? {})),
    reportUrl:    m['reportUrl'] ?? '',
    storagePath:  m['storagePath'] ?? '',
    fileType:     m['fileType'] ?? 'pdf',
    storedHash:   m['storedHash'] ?? '',
    // always starts as pending — EhrRepository.verifyIntegrity() updates this
    integrityStatus: IntegrityStatus.pending,
    facility:     m['facility'] ?? '',
    doctorName:   m['doctorName'] ?? '',
    notes:        m['notes'] ?? '',
    reportDate:   (m['reportDate'] as Timestamp).toDate(),
    uploadedAt:   (m['uploadedAt'] as Timestamp).toDate(),
    isArchived:   m['isArchived'] ?? false,
  );

  // ─── copyWith (used by Bloc to update integrityStatus) ───────
  EhrRecordModel copyWith({IntegrityStatus? integrityStatus}) => EhrRecordModel(
    id: id, patientId: patientId, patientName: patientName,
    medicalId: medicalId, cbcData: cbcData,
    reportUrl: reportUrl, storagePath: storagePath, fileType: fileType,
    storedHash: storedHash,
    integrityStatus: integrityStatus ?? this.integrityStatus,
    facility: facility, doctorName: doctorName, notes: notes,
    reportDate: reportDate, uploadedAt: uploadedAt, isArchived: isArchived,
  );
}

// ─── CbcData ──────────────────────────────────────────────────
/// Standard CBC panel fields only.
/// SRS constraint: NO bone marrow, NO genetic, NO flow cytometry.
/// All values are doubles — stored as numbers in Firestore.
/// null means the lab did not report that value.
class CbcData {
  // White Blood Cells
  final double? wbc;       // ×10³/µL   normal: 4.5–11.0

  // Red Blood Cells
  final double? rbc;       // ×10⁶/µL   normal: 4.5–5.9 (M), 4.1–5.1 (F)
  final double? hgb;       // g/dL       normal: 13.5–17.5 (M), 12.0–15.5 (F)
  final double? hct;       // %          normal: 41–53 (M), 36–46 (F)
  final double? mcv;       // fL         normal: 80–100
  final double? mch;       // pg         normal: 27–33
  final double? mchc;      // g/dL       normal: 32–36

  // Platelets
  final double? plt;       // ×10³/µL   normal: 150–400

  // Differential (optional — lab may not always report)
  final double? neutrophils;   // %
  final double? lymphocytes;   // %
  final double? monocytes;     // %
  final double? eosinophils;   // %
  final double? basophils;     // %

  const CbcData({
    this.wbc,
    this.rbc,
    this.hgb,
    this.hct,
    this.mcv,
    this.mch,
    this.mchc,
    this.plt,
    this.neutrophils,
    this.lymphocytes,
    this.monocytes,
    this.eosinophils,
    this.basophils,
  });

  Map<String, dynamic> toMap() => {
    'wbc':         wbc,
    'rbc':         rbc,
    'hgb':         hgb,
    'hct':         hct,
    'mcv':         mcv,
    'mch':         mch,
    'mchc':        mchc,
    'plt':         plt,
    'neutrophils': neutrophils,
    'lymphocytes': lymphocytes,
    'monocytes':   monocytes,
    'eosinophils': eosinophils,
    'basophils':   basophils,
  };

  factory CbcData.fromMap(Map<String, dynamic> m) => CbcData(
    wbc:         (m['wbc'] as num?)?.toDouble(),
    rbc:         (m['rbc'] as num?)?.toDouble(),
    hgb:         (m['hgb'] as num?)?.toDouble(),
    hct:         (m['hct'] as num?)?.toDouble(),
    mcv:         (m['mcv'] as num?)?.toDouble(),
    mch:         (m['mch'] as num?)?.toDouble(),
    mchc:        (m['mchc'] as num?)?.toDouble(),
    plt:         (m['plt'] as num?)?.toDouble(),
    neutrophils: (m['neutrophils'] as num?)?.toDouble(),
    lymphocytes: (m['lymphocytes'] as num?)?.toDouble(),
    monocytes:   (m['monocytes'] as num?)?.toDouble(),
    eosinophils: (m['eosinophils'] as num?)?.toDouble(),
    basophils:   (m['basophils'] as num?)?.toDouble(),
  );

  /// Returns true if at least the 4 core fields are filled.
  /// Used by the form to validate before allowing upload.
  bool get isMinimallyValid =>
      wbc != null && hgb != null && plt != null && rbc != null;
}