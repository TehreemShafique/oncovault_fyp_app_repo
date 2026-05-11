// lib/features/ehr/data/models/cbc_report_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class CbcReportModel {
  final String reportId;
  final String patientId;
  final DateTime testDate;

  // ── Core CBC Fields ONLY ──────────────────────────────
  final double wbc;         // White Blood Cells  (10^3/uL)
  final double rbc;         // Red Blood Cells    (10^6/uL)
  final double hemoglobin;  // HGB                (g/dL)
  final double hematocrit;  // HCT                (%)
  final double mcv;         // Mean Corpuscular Volume (fL)
  final double mch;         // Mean Corpuscular Hemoglobin (pg)
  final double mchc;        // MCHC               (g/dL)
  final double platelets;   // PLT                (10^3/uL)
  final double neutrophils; // Neutrophils        (%)
  final double lymphocytes; // Lymphocytes        (%)

  // ── File Info (filled AFTER upload) ──────────────────
  final String? reportFileUrl;   // Firebase Storage download URL
  final String? reportFileHash;  // SHA-256 hash stored as truth

  const CbcReportModel({
    required this.reportId,
    required this.patientId,
    required this.testDate,
    required this.wbc,
    required this.rbc,
    required this.hemoglobin,
    required this.hematocrit,
    required this.mcv,
    required this.mch,
    required this.mchc,
    required this.platelets,
    required this.neutrophils,
    required this.lymphocytes,
    this.reportFileUrl,
    this.reportFileHash,
  });

  // ── FROM Firestore ────────────────────────────────────
  factory CbcReportModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return CbcReportModel(
      reportId:       doc.id,
      patientId:      data['patientId']    ?? '',
      testDate:       (data['testDate'] as Timestamp).toDate(),
      wbc:            (data['wbc']         ?? 0.0).toDouble(),
      rbc:            (data['rbc']         ?? 0.0).toDouble(),
      hemoglobin:     (data['hemoglobin']  ?? 0.0).toDouble(),
      hematocrit:     (data['hematocrit']  ?? 0.0).toDouble(),
      mcv:            (data['mcv']         ?? 0.0).toDouble(),
      mch:            (data['mch']         ?? 0.0).toDouble(),
      mchc:           (data['mchc']        ?? 0.0).toDouble(),
      platelets:      (data['platelets']   ?? 0.0).toDouble(),
      neutrophils:    (data['neutrophils'] ?? 0.0).toDouble(),
      lymphocytes:    (data['lymphocytes'] ?? 0.0).toDouble(),
      reportFileUrl:  data['reportFileUrl'],
      reportFileHash: data['reportFileHash'],
    );
  }

  // ── TO Firestore ──────────────────────────────────────
  Map<String, dynamic> toFirestore() {
    return {
      'patientId':      patientId,
      'testDate':       Timestamp.fromDate(testDate),
      'wbc':            wbc,
      'rbc':            rbc,
      'hemoglobin':     hemoglobin,
      'hematocrit':     hematocrit,
      'mcv':            mcv,
      'mch':            mch,
      'mchc':           mchc,
      'platelets':      platelets,
      'neutrophils':    neutrophils,
      'lymphocytes':    lymphocytes,
      'reportFileUrl':  reportFileUrl,
      'reportFileHash': reportFileHash,
    };
  }

  // ── copyWith (update URL + hash after upload) ─────────
  CbcReportModel copyWith({
    String? reportFileUrl,
    String? reportFileHash,
  }) {
    return CbcReportModel(
      reportId:       reportId,
      patientId:      patientId,
      testDate:       testDate,
      wbc:            wbc,
      rbc:            rbc,
      hemoglobin:     hemoglobin,
      hematocrit:     hematocrit,
      mcv:            mcv,
      mch:            mch,
      mchc:           mchc,
      platelets:      platelets,
      neutrophils:    neutrophils,
      lymphocytes:    lymphocytes,
      reportFileUrl:  reportFileUrl  ?? this.reportFileUrl,
      reportFileHash: reportFileHash ?? this.reportFileHash,
    );
  }
}