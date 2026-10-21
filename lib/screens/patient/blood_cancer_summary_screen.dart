// lib/screens/patient/blood_cancer_summary_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../models/blood_cancer_ehr_model.dart';
import '../../models/vital_sign_model.dart';
import '../../services/doctor_service.dart';
import '../../services/nurse_service.dart';
import '../../models/medical_record_model.dart';
import '../../services/appointment_service.dart';
import '../../services/fabric_gateway_service.dart';
import '../doctor/doctor_widgets.dart';
import 'report_viewer_screen.dart';
import 'prescription_history_screen.dart';

class BloodCancerSummaryScreen extends StatefulWidget {
  final String patientId;
  final DoctorService? doctorService;
  final MedicalRecordService? recordService;
  final NurseService? nurseService;
  const BloodCancerSummaryScreen(
      {super.key,
      required this.patientId,
      this.doctorService,
      this.recordService,
      this.nurseService});

  @override
  State<BloodCancerSummaryScreen> createState() =>
      _BloodCancerSummaryScreenState();
}

class _BloodCancerSummaryScreenState extends State<BloodCancerSummaryScreen> {
  late final _service = widget.doctorService ?? DoctorService();
  String? _selectedRecordId;
  FabricVerificationStatus _ehrVerificationStatus =
      FabricVerificationStatus.pending;
  FabricVerificationResult? _ehrVerificationResult;

  Future<void> _verifyBloodCancerRecord(BloodCancerEhrModel record) async {
    if (record.blockchainTxId == null || record.blockchainTxId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'This clinical intake evaluation is not anchored on Hyperledger Fabric yet.'),
          backgroundColor: OV.slateDark,
        ),
      );
      return;
    }

    try {
      final res = await FabricGatewayService.instance.verifyRecord(
        recordId: record.recordId,
        patientId: record.patientId,
      );
      if (mounted) {
        setState(() {
          _ehrVerificationResult = res;
          _ehrVerificationStatus = res.status;
        });
        if (res.status == FabricVerificationStatus.verified) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                  'Live blockchain integrity verified ✓ Record matches ledger proof.'),
              backgroundColor: const Color(0xFF1B6B3A),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          );
        } else if (res.status == FabricVerificationStatus.tamperedOrMismatch) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                  'Integrity mismatch detected! Record content differs from ledger proof.'),
              backgroundColor: OV.error,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _ehrVerificationStatus =
              FabricVerificationStatus.verificationUnavailable;
        });
      }
    }
  }

  Widget _proofRow(String label, String value, {bool canCopy = false}) =>
      ClinicalProofRow(label: label, value: value, canCopy: canCopy);

  void _showEhrProofDetailsSheet(BloodCancerEhrModel record) {
    final proof = _ehrVerificationResult?.proof;
    final txId = proof?.txId ?? record.blockchainTxId ?? 'N/A';
    final hash = proof?.sha256Hash ?? record.storedHash ?? 'N/A';
    final version = proof?.version ?? 1;
    final timestamp = proof?.timestamp ??
        DateFormat('yyyy-MM-dd HH:mm:ss')
            .format(record.updatedAt ?? record.createdAt);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: OV.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.shield_outlined,
                    color: Color(0xFF1B6B3A), size: 24),
                const SizedBox(width: 10),
                Text(
                  'Hyperledger Fabric Proof',
                  style: GoogleFonts.manrope(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: OV.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Channel: oncovault-channel  •  Contract: oncovault  •  Document: BLOOD_CANCER_EHR',
              style: GoogleFonts.inter(fontSize: 11, color: OV.outline),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: OV.surfaceLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: OV.outlineVariant.withOpacity(0.5)),
              ),
              child: Column(
                children: [
                  _proofRow('Fabric TxID', txId, canCopy: true),
                  const Divider(height: 16),
                  _proofRow('Anchored Hash', hash, canCopy: true),
                  const Divider(height: 16),
                  _proofRow('Ledger Version', 'v$version'),
                  const Divider(height: 16),
                  _proofRow('Committed At', timestamp),
                  const Divider(height: 16),
                  _proofRow('Endorsing MSPs',
                      'Hospital1MSP, Hospital2MSP (Dual Endorsement)'),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Cryptographic proof committed to Hyperledger Fabric confirms patient record authenticity, chronological finalization, and tamper-resistance.',
              style: GoogleFonts.inter(
                  fontSize: 11, color: OV.outline, height: 1.4),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text('Close',
                    style: GoogleFonts.manrope(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OV.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded,
                    size: 18, color: OV.onSurface),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        title: Text(
          'Electronic Health Record',
          style: GoogleFonts.manrope(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: OV.onSurface,
          ),
        ),
        centerTitle: false,
      ),
      body: StreamBuilder<List<BloodCancerEhrModel>>(
        stream: _service.watchBloodCancerEhrs(widget.patientId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: OV.primary));
          }

          final records = snapshot.data ?? [];

          if (records.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: OV.primaryContainer,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(Icons.medical_information_outlined,
                          size: 36, color: OV.primary),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'No Clinical Records Yet',
                      style: GoogleFonts.manrope(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: OV.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your electronic health record will appear here after your clinical intake and evaluation.',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: OV.onSurfaceVariant,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          BloodCancerEhrModel currentRecord;
          if (_selectedRecordId != null) {
            currentRecord = records.firstWhere(
              (r) => r.recordId == _selectedRecordId,
              orElse: () => records.first,
            );
          } else {
            currentRecord = records.first;
          }

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            children: [
              // ── Record History Timeline ─────────────────────────
              if (records.length > 1)
                _buildTimelineSelector(records, currentRecord),

              if (records.length > 1) const SizedBox(height: 16),

              // ── Active Clinical Status Card ─────────────────────
              _buildDiagnosisCard(currentRecord),

              const SizedBox(height: 16),

              // ── Recent Vital Signs Observation ──────────────────
              _buildVitalsCard(widget.patientId),

              const SizedBox(height: 16),

              // ── Complete Blood Count (CBC) Panel ────────────────
              _buildCbcCard(currentRecord.cbc),

              const SizedBox(height: 16),

              // ── WBC Differential Counts ─────────────────────────
              _buildDifferentialsCard(currentRecord.cbc),

              const SizedBox(height: 16),

              // ── Bone Marrow & Blast Cells ───────────────────────
              _buildBoneMarrowCard(currentRecord),

              const SizedBox(height: 16),

              // ── Chemotherapy & Medications ──────────────────────
              _buildTreatmentCard(currentRecord),

              const SizedBox(height: 16),

              // ── Prescriptions ───────────────────────────────────
              _buildPrescriptionsSection(widget.patientId),

              const SizedBox(height: 16),

              // ── Reported Symptoms ───────────────────────────────
              _buildSymptomsCard(currentRecord.symptoms),

              const SizedBox(height: 16),

              // ── Clinical Notes ──────────────────────────────────
              if (currentRecord.clinicalNotes?.isNotEmpty == true) ...[
                _buildClinicalNotesCard(currentRecord),
                const SizedBox(height: 16),
              ],

              // ── Footer Metadata ─────────────────────────────────
              _buildRecordFooter(currentRecord),

              const SizedBox(height: 40),
            ],
          );
        },
      ),
    );
  }

  // ── Timeline Selector ─────────────────────────────────────────
  Widget _buildTimelineSelector(
      List<BloodCancerEhrModel> records, BloodCancerEhrModel current) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Record Timeline',
            style: GoogleFonts.manrope(
                fontSize: 13, fontWeight: FontWeight.w700, color: OV.onSurface),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: records.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final r = records[index];
                final isSelected = r.recordId == current.recordId;
                return GestureDetector(
                  onTap: () => setState(() => _selectedRecordId = r.recordId),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected ? OV.slateDark : OV.surfaceLow,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected
                            ? OV.slateDark
                            : OV.outlineVariant.withOpacity(0.4),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '${DateFormat('MMM d, yyyy').format(r.createdAt)}${index == 0 ? ' (Latest)' : ''}',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w500,
                          color:
                              isSelected ? Colors.white : OV.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Diagnosis & Staging Card ──────────────────────────────────
  Widget _buildDiagnosisCard(BloodCancerEhrModel record) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: OV.primaryContainer,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      'Clinical Diagnosis',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: OV.primary,
                      ),
                    ),
                  ),
                  if (record.diagnosisStatus?.isNotEmpty == true) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: OV.tertiaryContainer,
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        record.diagnosisStatus!,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: OV.tertiary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              BlockchainBadge(
                status: (record.blockchainTxId != null &&
                        record.blockchainTxId!.isNotEmpty)
                    ? _ehrVerificationStatus
                    : FabricVerificationStatus.notAnchored,
                onTap: () {
                  if (_ehrVerificationStatus ==
                      FabricVerificationStatus.verified) {
                    _showEhrProofDetailsSheet(record);
                  } else {
                    _verifyBloodCancerRecord(record);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            record.diagnosisSubtype?.isNotEmpty == true
                ? record.diagnosisSubtype!
                : (record.diseaseType?.isNotEmpty == true
                    ? record.diseaseType!
                    : 'Hematologic Evaluation'),
            style: GoogleFonts.manrope(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: OV.onSurface,
              letterSpacing: -0.4,
            ),
          ),
          if (record.diseaseType?.isNotEmpty == true &&
              record.diagnosisSubtype?.isNotEmpty == true) ...[
            const SizedBox(height: 4),
            Text(
              'Classification: ${record.diseaseType!}',
              style:
                  GoogleFonts.inter(fontSize: 13, color: OV.onSurfaceVariant),
            ),
          ],
          if (record.stage?.isNotEmpty == true) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: OV.surfaceLow,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  const Icon(Icons.layers_outlined,
                      size: 16, color: OV.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Stage / Risk Stratification: ',
                    style: GoogleFonts.inter(
                        fontSize: 12, color: OV.onSurfaceVariant),
                  ),
                  Text(
                    record.stage!,
                    style: GoogleFonts.manrope(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: OV.onSurface),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── CBC Card ──────────────────────────────────────────────────
  Widget _buildCbcCard(BloodCancerCbc cbc) {
    return _buildCard(
      title: 'Complete Blood Count (CBC)',
      icon: Icons.bloodtype_rounded,
      child: Column(
        children: [
          _cbcRow('WBC Count', cbc.wbc, '×10³/µL', '4.5 - 11.0'),
          const Divider(height: 14),
          _cbcRow('RBC Count', cbc.rbc, '×10⁶/µL', '4.2 - 5.8'),
          const Divider(height: 14),
          _cbcRow('Hemoglobin', cbc.hemoglobin, 'g/dL', '13.5 - 17.5'),
          const Divider(height: 14),
          _cbcRow('Hematocrit', cbc.hematocrit, '%', '38.8 - 50.0'),
          const Divider(height: 14),
          _cbcRow('Platelet Count', cbc.platelets, '×10³/µL', '150 - 450'),
        ],
      ),
    );
  }

  // ── Differentials Card ────────────────────────────────────────
  Widget _buildDifferentialsCard(BloodCancerCbc cbc) {
    return _buildCard(
      title: 'White Blood Cell Differentials',
      icon: Icons.science_outlined,
      child: Column(
        children: [
          _diffRow('Neutrophils', cbc.neutrophils),
          const Divider(height: 14),
          _diffRow('Lymphocytes', cbc.lymphocytes),
          const Divider(height: 14),
          _diffRow('Monocytes', cbc.monocytes),
          const Divider(height: 14),
          _diffRow('Eosinophils', cbc.eosinophils),
          const Divider(height: 14),
          _diffRow('Basophils', cbc.basophils),
          if (cbc.rdwSd != null || cbc.rdwCv != null) ...[
            const Divider(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                if (cbc.rdwSd != null)
                  Text('RDW-SD: ${cbc.rdwSd} fL',
                      style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: OV.onSurface)),
                if (cbc.rdwCv != null)
                  Text('RDW-CV: ${cbc.rdwCv}%',
                      style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: OV.onSurface)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── Bone Marrow Card ──────────────────────────────────────────
  Widget _buildBoneMarrowCard(BloodCancerEhrModel record) {
    return _buildCard(
      title: 'Bone Marrow & Blast Cells',
      icon: Icons.analytics_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              Text('Blast Cell Percentage',
                  style: GoogleFonts.inter(
                      fontSize: 13, color: OV.onSurfaceVariant)),
              Text(
                record.blastCellPercentage != null
                    ? '${record.blastCellPercentage}%'
                    : 'Not recorded',
                style: GoogleFonts.manrope(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: record.blastCellPercentage != null &&
                          record.blastCellPercentage! > 5.0
                      ? OV.error
                      : OV.onSurface,
                ),
              ),
            ],
          ),
          if (record.boneMarrowBiopsy?.isNotEmpty == true) ...[
            const SizedBox(height: 12),
            Text('Biopsy / Cytogenetic Summary:',
                style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: OV.outline)),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: OV.surfaceLow,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                record.boneMarrowBiopsy!,
                style: GoogleFonts.inter(
                    fontSize: 13, color: OV.onSurface, height: 1.4),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Treatment Card ────────────────────────────────────────────
  Widget _buildTreatmentCard(BloodCancerEhrModel record) {
    return _buildCard(
      title: 'Treatment & Chemotherapy',
      icon: Icons.medication_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              Text('Chemotherapy Regimen',
                  style: GoogleFonts.inter(
                      fontSize: 13, color: OV.onSurfaceVariant)),
              Text(
                record.chemotherapy?.isNotEmpty == true
                    ? record.chemotherapy!
                    : 'None active',
                style: GoogleFonts.manrope(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: OV.onSurface),
                textAlign: TextAlign.right,
              ),
            ],
          ),
          if (record.medications.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Active Medications:',
                style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: OV.outline)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: record.medications
                  .map((m) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: OV.primaryContainer,
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text(
                          m,
                          style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: OV.primary),
                        ),
                      ))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  // ── Symptoms Card ─────────────────────────────────────────────
  Widget _buildSymptomsCard(BloodCancerSymptoms symptoms) {
    final reported = <String>[];
    if (symptoms.shortnessOfBreath == true) reported.add('Shortness of Breath');
    if (symptoms.bonePain == true) reported.add('Bone / Joint Pain');
    if (symptoms.fever == true) reported.add('Persistent Fever');
    if (symptoms.familyHistory == true) reported.add('Family History');
    if (symptoms.frequentInfections == true)
      reported.add('Frequent Infections');
    if (symptoms.itchySkinOrRash == true) reported.add('Itchy Skin / Rash');
    if (symptoms.lossOfAppetiteOrNausea == true)
      reported.add('Loss of Appetite');
    if (symptoms.persistentWeaknessAndFatigue == true)
      reported.add('Persistent Fatigue');
    if (symptoms.swollenPainlessLymphNodes == true)
      reported.add('Swollen Lymph Nodes');
    if (symptoms.significantBruisingOrBleeding == true)
      reported.add('Bruising / Bleeding');
    if (symptoms.enlargedLiver == true) reported.add('Hepatomegaly');
    if (symptoms.oralCavityChanges == true) reported.add('Oral Cavity Changes');
    if (symptoms.visionBlurring == true) reported.add('Vision Blurring');
    if (symptoms.jaundice == true) reported.add('Jaundice');
    if (symptoms.nightSweats == true) reported.add('Night Sweats');
    if (symptoms.smokes == true) reported.add('Smoking History');

    return _buildCard(
      title: 'Reported Symptoms',
      icon: Icons.checklist_rounded,
      child: reported.isNotEmpty
          ? Wrap(
              spacing: 8,
              runSpacing: 8,
              children: reported
                  .map((s) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: OV.surfaceLow,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: OV.outlineVariant.withOpacity(0.5)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check_circle_outline_rounded,
                                size: 14, color: OV.primary),
                            const SizedBox(width: 6),
                            Flexible(
                                child: Text(s,
                                    style: GoogleFonts.inter(
                                        fontSize: 12, color: OV.onSurface))),
                          ],
                        ),
                      ))
                  .toList(),
            )
          : Text(
              'No acute symptoms documented at intake.',
              style:
                  GoogleFonts.inter(fontSize: 13, color: OV.onSurfaceVariant),
            ),
    );
  }

  // ── Clinical Notes Card ───────────────────────────────────────
  Widget _buildClinicalNotesCard(BloodCancerEhrModel record) {
    return _buildCard(
      title: "Doctor's Clinical Notes",
      icon: Icons.notes_rounded,
      child: Text(
        record.clinicalNotes!,
        style:
            GoogleFonts.inter(fontSize: 13, color: OV.onSurface, height: 1.5),
      ),
    );
  }

  // ── Record Footer ─────────────────────────────────────────────
  Widget _buildRecordFooter(BloodCancerEhrModel record) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              Text('Attending Physician',
                  style: GoogleFonts.inter(fontSize: 12, color: OV.outline)),
              Text(
                record.doctorName.isNotEmpty
                    ? record.doctorName
                    : 'Medical Staff',
                style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: OV.onSurface),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              Text('Record ID',
                  style: GoogleFonts.inter(fontSize: 12, color: OV.outline)),
              Text(
                record.recordId.length > 12
                    ? record.recordId.substring(0, 12).toUpperCase()
                    : record.recordId,
                style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: OV.onSurface),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              Text('Blockchain Ledger',
                  style: GoogleFonts.inter(fontSize: 12, color: OV.outline)),
              if (record.blockchainTxId != null &&
                  record.blockchainTxId!.isNotEmpty)
                InkWell(
                  onTap: () {
                    if (_ehrVerificationStatus ==
                        FabricVerificationStatus.verified) {
                      _showEhrProofDetailsSheet(record);
                    } else {
                      _verifyBloodCancerRecord(record);
                    }
                  },
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      Text(
                        _ehrVerificationStatus ==
                                FabricVerificationStatus.verified
                            ? 'Verified ✓ (View Proof)'
                            : 'Anchored (Check Integrity)',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _ehrVerificationStatus ==
                                  FabricVerificationStatus.verified
                              ? const Color(0xFF1B6B3A)
                              : OV.primary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.shield_outlined,
                        size: 14,
                        color: _ehrVerificationStatus ==
                                FabricVerificationStatus.verified
                            ? const Color(0xFF1B6B3A)
                            : OV.primary,
                      ),
                    ],
                  ),
                )
              else
                Text(
                  'Not Yet Anchored',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: OV.outline,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              Text('Last Updated',
                  style: GoogleFonts.inter(fontSize: 12, color: OV.outline)),
              Text(
                DateFormat('MMM d, yyyy • hh:mm a')
                    .format(record.updatedAt ?? record.createdAt),
                style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: OV.onSurface),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Prescriptions Section ─────────────────────────────────────
  Widget _buildPrescriptionsSection(String patientId) {
    return _buildCard(
      title: 'Prescriptions',
      icon: Icons.medication_rounded,
      child: StreamBuilder<List<MedicalRecordModel>>(
        stream: (widget.recordService ?? MedicalRecordService())
            .watchRecords(patientId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: OV.primary),
                ),
              ),
            );
          }
          final allRecords = snapshot.data ?? [];
          final allPrescriptions = allRecords
              .where((r) => r.type == RecordType.prescription)
              .toList();

          if (allPrescriptions.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No active prescriptions found.',
                style:
                    GoogleFonts.inter(fontSize: 13, color: OV.onSurfaceVariant),
              ),
            );
          }

          // Show anchored prescription in preview; complete history is accessible below
          final previewPrescriptions = allPrescriptions
              .where((r) => r.fabricTxId?.isNotEmpty == true)
              .toList();

          final displayList = previewPrescriptions.isNotEmpty
              ? previewPrescriptions
              : [allPrescriptions.first];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...displayList.map((r) => PatientPrescriptionPreview(record: r)),
              if (allPrescriptions.length > displayList.length) ...[
                const SizedBox(height: 4),
                Center(
                  child: TextButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PrescriptionHistoryScreen(
                          patientId: patientId,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.history_rounded, size: 16),
                    label: Text(
                      'View All Prescriptions (${allPrescriptions.length})',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: OV.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  // ── Helper Card ───────────────────────────────────────────────
  Widget _buildCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: OV.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: OV.primary, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.manrope(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: OV.onSurface),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _cbcRow(String name, double? val, String unit, String normalRange) =>
      ResponsiveDetailRow(
          label:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name,
                style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: OV.onSurface)),
            Text('Ref: $normalRange $unit',
                style: GoogleFonts.inter(fontSize: 10, color: OV.outline))
          ]),
          value: Text(val != null ? '$val $unit' : '\u2014',
              style: GoogleFonts.manrope(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: val != null ? OV.onSurface : OV.outline)));

  Widget _diffRow(String name, DifferentialCount? diff) => ResponsiveDetailRow(
      label: Text(name,
          style: GoogleFonts.inter(
              fontSize: 13, fontWeight: FontWeight.w600, color: OV.onSurface)),
      value: Text(
          '${diff?.absolute != null ? "${diff!.absolute} k/\u00b5L" : "\u2014"}  (${diff?.percentage != null ? "${diff!.percentage}%" : "\u2014"})',
          style: GoogleFonts.inter(
              fontSize: 12, fontWeight: FontWeight.w600, color: OV.onSurface)));

  Widget _buildVitalsCard(String patientId) {
    return StreamBuilder<VitalSignModel?>(
      stream: (widget.nurseService ?? NurseService())
          .watchLatestPatientVitals(patientId),
      builder: (context, snapshot) {
        final vitals = snapshot.data;
        if (vitals == null) return const SizedBox.shrink();

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: OV.outlineVariant.withOpacity(0.5)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 16,
                runSpacing: 12,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: OV.primary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.monitor_heart_rounded,
                            color: OV.primary, size: 16),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Recent Vital Signs',
                        style: GoogleFonts.manrope(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: OV.onSurface,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    DateFormat('MMM d, h:mm a').format(vitals.recordedAt),
                    style: GoogleFonts.inter(
                        fontSize: 11, color: OV.onSurfaceVariant),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 12,
                children: [
                  _vitalMetric('Blood Pressure',
                      '${vitals.systolicBp}/${vitals.diastolicBp}', 'mmHg'),
                  _vitalMetric('Pulse Rate', '${vitals.pulseRate}', 'bpm'),
                  _vitalMetric(
                      'Temperature',
                      '${vitals.temperatureCelsius.toStringAsFixed(1)}°C',
                      '(${vitals.temperatureFahrenheit.toStringAsFixed(1)}°F)'),
                  _vitalMetric('SpO2', '${vitals.oxygenSaturation}%', ''),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Recorded by Nurse ${vitals.nurseName}',
                style:
                    GoogleFonts.inter(fontSize: 11, color: OV.onSurfaceVariant),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _vitalMetric(String label, String value, String unit) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.inter(
                fontSize: 10, color: OV.outline, fontWeight: FontWeight.w500)),
        const SizedBox(height: 2),
        Text(value,
            style: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: OV.onSurface)),
        if (unit.isNotEmpty)
          Text(unit,
              style:
                  GoogleFonts.inter(fontSize: 9, color: OV.onSurfaceVariant)),
      ],
    );
  }
}

/// The same prescription and proof actions, responsive to its card's actual width.
class PatientPrescriptionPreview extends StatelessWidget {
  final MedicalRecordModel record;
  const PatientPrescriptionPreview({super.key, required this.record});
  @override
  Widget build(BuildContext context) {
    final anchored = record.fabricTxId?.isNotEmpty == true;
    void open() => Navigator.push(context,
        MaterialPageRoute(builder: (_) => ReportViewerScreen(record: record)));
    return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: OV.surfaceLow,
            borderRadius: BorderRadius.circular(12),
            border:
                Border.all(color: OV.outlineVariant.withValues(alpha: 0.4))),
        child: InkWell(
            onTap: open,
            child: ResponsiveActionRow(
                leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: anchored
                            ? OV.primary.withValues(alpha: 0.12)
                            : OV.outlineVariant.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.medication_rounded,
                        size: 20, color: OV.primary)),
                body: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(record.title,
                          style: GoogleFonts.manrope(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: OV.onSurface)),
                      const SizedBox(height: 2),
                      Text(
                          record.summary.isNotEmpty
                              ? record.summary
                              : '${record.subtype} - ${record.facility}',
                          style: GoogleFonts.inter(
                              fontSize: 11, color: OV.onSurfaceVariant))
                    ]),
                action: BlockchainBadge(
                    status: anchored
                        ? FabricVerificationStatus.pending
                        : FabricVerificationStatus.notAnchored,
                    onTap: open))));
  }
}
