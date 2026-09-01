// lib/screens/patient/blood_cancer_summary_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../models/blood_cancer_ehr_model.dart';
import '../../services/doctor_service.dart';

class BloodCancerSummaryScreen extends StatefulWidget {
  final String patientId;
  const BloodCancerSummaryScreen({super.key, required this.patientId});

  @override
  State<BloodCancerSummaryScreen> createState() => _BloodCancerSummaryScreenState();
}

class _BloodCancerSummaryScreenState extends State<BloodCancerSummaryScreen> {
  final _service = DoctorService();
  String? _selectedRecordId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OV.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: OV.onSurface),
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
            return const Center(child: CircularProgressIndicator(color: OV.primary));
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
                      child: const Icon(Icons.medical_information_outlined, size: 36, color: OV.primary),
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
  Widget _buildTimelineSelector(List<BloodCancerEhrModel> records, BloodCancerEhrModel current) {
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
            style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700, color: OV.onSurface),
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
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected ? OV.slateDark : OV.surfaceLow,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected ? OV.slateDark : OV.outlineVariant.withOpacity(0.4),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '${DateFormat('MMM d, yyyy').format(r.createdAt)}${index == 0 ? ' (Latest)' : ''}',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected ? Colors.white : OV.onSurfaceVariant,
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
              if (record.diagnosisStatus?.isNotEmpty == true)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
          ),
          const SizedBox(height: 14),
          Text(
            record.diagnosisSubtype?.isNotEmpty == true
                ? record.diagnosisSubtype!
                : (record.diseaseType?.isNotEmpty == true ? record.diseaseType! : 'Hematologic Evaluation'),
            style: GoogleFonts.manrope(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: OV.onSurface,
              letterSpacing: -0.4,
            ),
          ),
          if (record.diseaseType?.isNotEmpty == true && record.diagnosisSubtype?.isNotEmpty == true) ...[
            const SizedBox(height: 4),
            Text(
              'Classification: ${record.diseaseType!}',
              style: GoogleFonts.inter(fontSize: 13, color: OV.onSurfaceVariant),
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
              child: Row(
                children: [
                  const Icon(Icons.layers_outlined, size: 16, color: OV.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Stage / Risk Stratification: ',
                    style: GoogleFonts.inter(fontSize: 12, color: OV.onSurfaceVariant),
                  ),
                  Text(
                    record.stage!,
                    style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700, color: OV.onSurface),
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (cbc.rdwSd != null)
                  Text('RDW-SD: ${cbc.rdwSd} fL', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: OV.onSurface)),
                if (cbc.rdwCv != null)
                  Text('RDW-CV: ${cbc.rdwCv}%', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: OV.onSurface)),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Blast Cell Percentage', style: GoogleFonts.inter(fontSize: 13, color: OV.onSurfaceVariant)),
              Text(
                record.blastCellPercentage != null ? '${record.blastCellPercentage}%' : 'Not recorded',
                style: GoogleFonts.manrope(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: record.blastCellPercentage != null && record.blastCellPercentage! > 5.0
                      ? OV.error
                      : OV.onSurface,
                ),
              ),
            ],
          ),
          if (record.boneMarrowBiopsy?.isNotEmpty == true) ...[
            const SizedBox(height: 12),
            Text('Biopsy / Cytogenetic Summary:', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: OV.outline)),
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
                style: GoogleFonts.inter(fontSize: 13, color: OV.onSurface, height: 1.4),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Chemotherapy Regimen', style: GoogleFonts.inter(fontSize: 13, color: OV.onSurfaceVariant)),
              Flexible(
                child: Text(
                  record.chemotherapy?.isNotEmpty == true ? record.chemotherapy! : 'None active',
                  style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700, color: OV.onSurface),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          if (record.medications.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Active Medications:', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: OV.outline)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: record.medications.map((m) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: OV.primaryContainer,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  m,
                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: OV.primary),
                ),
              )).toList(),
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
    if (symptoms.frequentInfections == true) reported.add('Frequent Infections');
    if (symptoms.itchySkinOrRash == true) reported.add('Itchy Skin / Rash');
    if (symptoms.lossOfAppetiteOrNausea == true) reported.add('Loss of Appetite');
    if (symptoms.persistentWeaknessAndFatigue == true) reported.add('Persistent Fatigue');
    if (symptoms.swollenPainlessLymphNodes == true) reported.add('Swollen Lymph Nodes');
    if (symptoms.significantBruisingOrBleeding == true) reported.add('Bruising / Bleeding');
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
              children: reported.map((s) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: OV.surfaceLow,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: OV.outlineVariant.withOpacity(0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle_outline_rounded, size: 14, color: OV.primary),
                    const SizedBox(width: 6),
                    Text(s, style: GoogleFonts.inter(fontSize: 12, color: OV.onSurface)),
                  ],
                ),
              )).toList(),
            )
          : Text(
              'No acute symptoms documented at intake.',
              style: GoogleFonts.inter(fontSize: 13, color: OV.onSurfaceVariant),
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
        style: GoogleFonts.inter(fontSize: 13, color: OV.onSurface, height: 1.5),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Attending Physician', style: GoogleFonts.inter(fontSize: 12, color: OV.outline)),
              Text(
                record.doctorName.isNotEmpty ? record.doctorName : 'Medical Staff',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: OV.onSurface),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Record ID', style: GoogleFonts.inter(fontSize: 12, color: OV.outline)),
              Text(
                record.recordId.length > 12 ? record.recordId.substring(0, 12).toUpperCase() : record.recordId,
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: OV.onSurface),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Last Updated', style: GoogleFonts.inter(fontSize: 12, color: OV.outline)),
              Text(
                DateFormat('MMM d, yyyy • hh:mm a').format(record.updatedAt ?? record.createdAt),
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: OV.onSurface),
              ),
            ],
          ),
        ],
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
        crossAxisAlignment: CrossAxisAlignment.start,
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
                  style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700, color: OV.onSurface),
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

  Widget _cbcRow(String name, double? val, String unit, String normalRange) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: OV.onSurface)),
            Text('Ref: $normalRange $unit', style: GoogleFonts.inter(fontSize: 10, color: OV.outline)),
          ],
        ),
        Text(
          val != null ? '$val $unit' : '—',
          style: GoogleFonts.manrope(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: val != null ? OV.onSurface : OV.outline,
          ),
        ),
      ],
    );
  }

  Widget _diffRow(String name, DifferentialCount? diff) {
    final abs = diff?.absolute;
    final pct = diff?.percentage;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(name, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: OV.onSurface)),
        Text(
          '${abs != null ? "$abs k/µL" : "—"}  (${pct != null ? "$pct%" : "—"})',
          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: OV.onSurface),
        ),
      ],
    );
  }
}
