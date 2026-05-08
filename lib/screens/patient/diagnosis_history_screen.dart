// lib/screens/patient/diagnosis_history_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../models/medical_record_model.dart';
import '../../services/appointment_service.dart';

class DiagnosisHistoryScreen extends StatelessWidget {
  final String patientId;
  const DiagnosisHistoryScreen({super.key, required this.patientId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OV.background,
      body: SafeArea(child: Column(children: [

        // ── App Bar ──────────────────────────────────────────────
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              GestureDetector(onTap: () => Navigator.pop(context),
                  child: Container(padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: OV.outlineVariant.withOpacity(0.5))),
                      child: const Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: OV.onSurface))),
              const SizedBox(width: 12),
              Text('Diagnosis History', style: GoogleFonts.manrope(
                  fontSize: 17, fontWeight: FontWeight.w700, color: OV.onSurface)),
            ])),

        // ── Header ───────────────────────────────────────────────
        Padding(padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Medical Timeline', style: GoogleFonts.manrope(
                  fontSize: 26, fontWeight: FontWeight.w700, color: OV.onSurface, letterSpacing: -0.3)),
              const SizedBox(height: 4),
              Text('A chronological view of your diagnoses, treatments, and clinical notes.',
                  style: GoogleFonts.inter(fontSize: 13, color: OV.onSurfaceVariant, height: 1.5)),
            ])),

        const SizedBox(height: 20),

        // ── Timeline ─────────────────────────────────────────────
        Expanded(child: StreamBuilder<List<MedicalRecordModel>>(
            stream: MedicalRecordService().watchRecords(patientId),
            builder: (_, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: OV.primary));
              }
              final records = snap.data ?? [];
              if (records.isEmpty) {
                return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.timeline_rounded, size: 48, color: OV.outlineVariant),
                  const SizedBox(height: 12),
                  Text('No history yet', style: GoogleFonts.inter(fontSize: 15, color: OV.onSurfaceVariant)),
                ]));
              }

              // Group by year
              final grouped = <int, List<MedicalRecordModel>>{};
              for (final r in records) {
                grouped.putIfAbsent(r.date.year, () => []).add(r);
              }
              final years = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

              return ListView(padding: const EdgeInsets.symmetric(horizontal: 20), children: [
                ...years.expand((year) => [
                  // Year header
                  Padding(padding: const EdgeInsets.only(top: 8, bottom: 12),
                      child: Row(children: [
                        Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(color: OV.slateDark, borderRadius: BorderRadius.circular(100)),
                            child: Text('$year', style: GoogleFonts.manrope(
                                fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white))),
                        const SizedBox(width: 12),
                        Expanded(child: Container(height: 1, color: OV.outlineVariant.withOpacity(0.5))),
                      ])),
                  // Records for this year
                  ...grouped[year]!.asMap().entries.map((e) {
                    final isLast = e.key == grouped[year]!.length - 1 && year == years.last;
                    return _TimelineItem(record: e.value, isLast: isLast);
                  }),
                ]),
                const SizedBox(height: 24),
              ]);
            })),
      ])),
    );
  }
}

class _TimelineItem extends StatelessWidget {
  final MedicalRecordModel record;
  final bool isLast;
  const _TimelineItem({required this.record, required this.isLast});

  Color get _dotColor {
    switch (record.type) {
      case RecordType.medicalHistory: return OV.primary;
      case RecordType.report:         return OV.secondary;
      case RecordType.prescription:   return OV.tertiary;
      default:                        return OV.outline;
    }
  }

  IconData get _icon {
    switch (record.type) {
      case RecordType.medicalHistory: return Icons.medical_services_outlined;
      case RecordType.report:         return Icons.description_outlined;
      case RecordType.prescription:   return Icons.medication_outlined;
      default:                        return Icons.folder_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Timeline spine
        SizedBox(width: 32, child: Column(children: [
          Container(width: 16, height: 16,
              decoration: BoxDecoration(color: _dotColor, shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.5),
                  boxShadow: [BoxShadow(color: _dotColor.withOpacity(0.3), blurRadius: 6)])),
          if (!isLast) Expanded(child: Center(
              child: Container(width: 2, color: OV.outlineVariant.withOpacity(0.4)))),
        ])),

        // Card
        Expanded(child: Padding(
            padding: const EdgeInsets.only(left: 12, bottom: 20),
            child: Container(padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04),
                        blurRadius: 10, offset: const Offset(0, 3))]),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // Date badge
                  Text(DateFormat('MMM d, yyyy').format(record.date),
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700,
                          letterSpacing: 0.5, color: OV.outline)),
                  const SizedBox(height: 8),
                  Row(children: [
                    Container(width: 36, height: 36,
                        decoration: BoxDecoration(
                            color: _dotColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10)),
                        child: Icon(_icon, size: 18, color: _dotColor)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(record.title, style: GoogleFonts.manrope(
                        fontSize: 14, fontWeight: FontWeight.w700, color: OV.onSurface))),
                    if (record.subtype.isNotEmpty)
                      Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                              color: _dotColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(100)),
                          child: Text(record.subtype, style: GoogleFonts.inter(
                              fontSize: 10, fontWeight: FontWeight.w700, color: _dotColor))),
                  ]),
                  if (record.facility.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(record.facility, style: GoogleFonts.inter(
                        fontSize: 12, color: OV.onSurfaceVariant)),
                  ],
                  if (record.doctorName.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(children: [
                      Icon(Icons.person_outline_rounded, size: 12, color: OV.outline),
                      const SizedBox(width: 4),
                      Text(record.doctorName, style: GoogleFonts.inter(
                          fontSize: 12, color: OV.onSurfaceVariant)),
                    ]),
                  ],
                  if (record.summary.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(height: 1, color: OV.outlineVariant.withOpacity(0.3)),
                    const SizedBox(height: 10),
                    Text(record.summary, style: GoogleFonts.inter(
                        fontSize: 12, color: OV.onSurfaceVariant, height: 1.5)),
                  ],
                ])))),
      ]),
    );
  }
}