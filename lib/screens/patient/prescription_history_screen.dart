// lib/screens/patient/prescription_history_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../models/medical_record_model.dart';
import '../../services/appointment_service.dart';
import '../../services/fabric_gateway_service.dart';
import '../doctor/doctor_widgets.dart';
import 'report_viewer_screen.dart';

class PrescriptionHistoryScreen extends StatelessWidget {
  final String patientId;
  final Stream<List<MedicalRecordModel>>? recordsStream;

  const PrescriptionHistoryScreen({
    super.key,
    required this.patientId,
    this.recordsStream,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OV.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── App Bar ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: OV.outlineVariant.withOpacity(0.5)),
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 16,
                        color: OV.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Prescription History',
                    style: GoogleFonts.manrope(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: OV.onSurface,
                    ),
                  ),
                ],
              ),
            ),

            // ── Header ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Prescriptions',
                    style: GoogleFonts.manrope(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: OV.onSurface,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'A complete chronological record of your oncology medications and digital prescriptions.',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: OV.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── Prescriptions List ────────────────────────────────────
            Expanded(
              child: StreamBuilder<List<MedicalRecordModel>>(
                stream: recordsStream ?? MedicalRecordService().watchRecords(patientId),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(color: OV.primary),
                    );
                  }

                  final allRecords = snapshot.data ?? [];
                  final prescriptions = allRecords
                      .where((r) => r.type == RecordType.prescription)
                      .toList()
                    ..sort((a, b) => b.date.compareTo(a.date));

                  if (prescriptions.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.medication_outlined,
                            size: 48,
                            color: OV.outlineVariant,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No prescriptions found',
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              color: OV.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: prescriptions.length,
                    itemBuilder: (context, index) {
                      final record = prescriptions[index];
                      return _PrescriptionHistoryCard(record: record);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrescriptionHistoryCard extends StatelessWidget {
  final MedicalRecordModel record;
  const _PrescriptionHistoryCard({required this.record});

  @override
  Widget build(BuildContext context) {
    final isAnchored = record.fabricTxId != null && record.fabricTxId!.isNotEmpty;
    final status = isAnchored
        ? FabricVerificationStatus.pending
        : FabricVerificationStatus.notAnchored;

    final drugs = record.prescribedDrugs;
    final primaryDrug = drugs.isNotEmpty ? drugs.first : null;
    final drugName = primaryDrug != null ? (primaryDrug['name']?.toString() ?? '') : '';
    final dosage = primaryDrug != null ? (primaryDrug['dosage']?.toString() ?? '') : '';
    final frequency = primaryDrug != null ? (primaryDrug['frequency']?.toString() ?? '') : '';
    final duration = primaryDrug != null ? (primaryDrug['duration']?.toString() ?? '') : '';
    final route = primaryDrug != null ? (primaryDrug['route']?.toString() ?? '') : '';
    final instructions = primaryDrug != null ? (primaryDrug['instructions']?.toString() ?? '') : '';

    final displayTitle = drugName.isNotEmpty
        ? (dosage.isNotEmpty ? '$drugName $dosage' : drugName)
        : (record.title.isNotEmpty ? record.title : 'Digital Prescription');

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ReportViewerScreen(record: record)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Date and Subtype tag
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      DateFormat('MMMM d, yyyy').format(record.date),
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: OV.outline,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: OV.primaryContainer,
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        record.subtype.isNotEmpty ? record.subtype : 'Prescription',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: OV.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Drug icon + Drug name / Dosage
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: isAnchored
                            ? OV.primary.withOpacity(0.12)
                            : OV.outlineVariant.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.medication_rounded,
                        size: 20,
                        color: isAnchored ? OV.primary : OV.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayTitle,
                            style: GoogleFonts.manrope(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: OV.onSurface,
                            ),
                          ),
                          if (record.doctorName.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              record.doctorName,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: OV.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),

                // Medication metadata chips
                if (frequency.isNotEmpty || duration.isNotEmpty || route.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      if (frequency.isNotEmpty)
                        _metaChip(Icons.schedule_rounded, frequency),
                      if (duration.isNotEmpty)
                        _metaChip(Icons.date_range_rounded, duration),
                      if (route.isNotEmpty)
                        _metaChip(Icons.directions_rounded, route),
                    ],
                  ),
                ],

                if (instructions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Instructions: $instructions',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: OV.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],

                const SizedBox(height: 14),
                Container(height: 1, color: OV.outlineVariant.withOpacity(0.3)),
                const SizedBox(height: 12),

                // Truthful Blockchain verification badge + Inspect action
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    BlockchainBadge(
                      status: status,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => ReportViewerScreen(record: record)),
                      ),
                    ),
                    Row(
                      children: [
                        Text(
                          'Inspect',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: OV.primary,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.chevron_right_rounded,
                          size: 16,
                          color: OV.primary,
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _metaChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: OV.surfaceLow,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: OV.outlineVariant.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: OV.outline),
          const SizedBox(width: 4),
          Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: OV.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
