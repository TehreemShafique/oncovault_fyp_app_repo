// lib/screens/patient/report_viewer_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../models/medical_record_model.dart';

class ReportViewerScreen extends StatelessWidget {
  final MedicalRecordModel record;
  const ReportViewerScreen({super.key, required this.record});

  IconData get _typeIcon {
    switch (record.subtype.toLowerCase()) {
      case 'imaging':       return Icons.image_outlined;
      case 'pathology':     return Icons.biotech_outlined;
      case 'clinical notes':return Icons.notes_rounded;
      case 'treatment':     return Icons.medical_services_outlined;
      default:              return Icons.description_outlined;
    }
  }

  Color get _typeBg {
    switch (record.subtype.toLowerCase()) {
      case 'imaging':       return OV.secondaryContainer;
      case 'pathology':     return OV.primaryContainer;
      case 'clinical notes':return OV.tertiaryContainer;
      default:              return OV.surfaceContainer;
    }
  }

  Color get _typeColor {
    switch (record.subtype.toLowerCase()) {
      case 'imaging':       return OV.secondary;
      case 'pathology':     return OV.primary;
      case 'clinical notes':return OV.tertiary;
      default:              return OV.onSurfaceVariant;
    }
  }

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
              const Spacer(),
              Text('Report Viewer', style: GoogleFonts.manrope(
                  fontSize: 17, fontWeight: FontWeight.w700, color: OV.onSurface)),
              const Spacer(),
              GestureDetector(onTap: () {},
                  child: Container(padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: OV.outlineVariant.withOpacity(0.5))),
                      child: Icon(Icons.share_outlined, size: 16, color: OV.primary))),
            ])),

        Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [

          // ── Report Header Card ──────────────────────────────────
          Container(padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05),
                      blurRadius: 16, offset: const Offset(0, 4))]),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(width: 56, height: 56,
                      decoration: BoxDecoration(color: _typeBg, borderRadius: BorderRadius.circular(14)),
                      child: Icon(_typeIcon, color: _typeColor, size: 28)),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(record.title, style: GoogleFonts.manrope(
                        fontSize: 17, fontWeight: FontWeight.w700, color: OV.onSurface, height: 1.2)),
                    const SizedBox(height: 4),
                    if (record.subtype.isNotEmpty)
                      Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: _typeBg, borderRadius: BorderRadius.circular(100)),
                          child: Text(record.subtype, style: GoogleFonts.inter(
                              fontSize: 11, fontWeight: FontWeight.w700, color: _typeColor))),
                  ])),
                ]),
                const SizedBox(height: 18),
                Container(height: 1, color: OV.outlineVariant.withOpacity(0.3)),
                const SizedBox(height: 16),
                _MetaRow(icon: Icons.local_hospital_outlined, label: 'Facility', value: record.facility),
                if (record.doctorName.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _MetaRow(icon: Icons.person_outline_rounded, label: 'Doctor', value: record.doctorName),
                ],
                const SizedBox(height: 10),
                _MetaRow(icon: Icons.calendar_today_rounded, label: 'Date',
                    value: DateFormat('MMMM d, yyyy').format(record.date)),
                const SizedBox(height: 10),
                _MetaRow(icon: Icons.upload_outlined, label: 'Uploaded',
                    value: DateFormat('MMM d, yyyy').format(record.uploadedAt)),
              ])),

          const SizedBox(height: 16),

          // ── Preview Area ──────────────────────────────────────
          Container(
              width: double.infinity,
              height: 280,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04),
                      blurRadius: 12, offset: const Offset(0, 3))]),
              child: record.fileUrl.isNotEmpty
                  ? ClipRRect(borderRadius: BorderRadius.circular(20),
                  child: Image.network(record.fileUrl, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _PreviewPlaceholder(record: record)))
                  : _PreviewPlaceholder(record: record)),

          const SizedBox(height: 16),

          // ── Summary / Notes ───────────────────────────────────
          if (record.summary.isNotEmpty)
            Container(padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04),
                        blurRadius: 12, offset: const Offset(0, 3))]),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.summarize_outlined, size: 18, color: OV.primary),
                    const SizedBox(width: 8),
                    Text('Clinical Summary', style: GoogleFonts.manrope(
                        fontSize: 15, fontWeight: FontWeight.w700, color: OV.onSurface)),
                  ]),
                  const SizedBox(height: 12),
                  Container(height: 1, color: OV.outlineVariant.withOpacity(0.3)),
                  const SizedBox(height: 12),
                  Text(record.summary, style: GoogleFonts.inter(
                      fontSize: 14, color: OV.onSurface, height: 1.7)),
                ])),

          const SizedBox(height: 16),

          // ── Security Badge ────────────────────────────────────
          Container(padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: OV.tertiaryContainer.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: OV.tertiary.withOpacity(0.2))),
              child: Row(children: [
                Icon(Icons.verified_user_outlined, size: 18, color: OV.tertiary),
                const SizedBox(width: 10),
                Expanded(child: Text('This record is end-to-end encrypted and HIPAA-compliant.',
                    style: GoogleFonts.inter(fontSize: 12, color: OV.tertiary, height: 1.4))),
              ])),

          const SizedBox(height: 24),
        ]))),

        // ── Bottom Actions ────────────────────────────────────────
        Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            decoration: BoxDecoration(color: Colors.white,
                border: Border(top: BorderSide(color: OV.outlineVariant.withOpacity(0.4)))),
            child: Row(children: [
              Expanded(child: OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.print_outlined, size: 16),
                  label: Text('Print', style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(foregroundColor: OV.onSurface,
                      side: BorderSide(color: OV.outlineVariant),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14)))),
              const SizedBox(width: 12),
              Expanded(flex: 2, child: ElevatedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.download_rounded, size: 16),
                  label: Text('Download PDF', style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: OV.slateDark, foregroundColor: Colors.white,
                      elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14)))),
            ])),
      ])),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final IconData icon; final String label, value;
  const _MetaRow({required this.icon, required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Icon(icon, size: 15, color: OV.outline),
    const SizedBox(width: 8),
    Text('$label: ', style: GoogleFonts.inter(fontSize: 13, color: OV.outline, fontWeight: FontWeight.w500)),
    Expanded(child: Text(value, style: GoogleFonts.inter(
        fontSize: 13, fontWeight: FontWeight.w600, color: OV.onSurface))),
  ]);
}

class _PreviewPlaceholder extends StatelessWidget {
  final MedicalRecordModel record;
  const _PreviewPlaceholder({required this.record});

  @override
  Widget build(BuildContext context) => Column(
      mainAxisAlignment: MainAxisAlignment.center, children: [
    Container(width: 72, height: 72,
        decoration: BoxDecoration(color: OV.surfaceLow, borderRadius: BorderRadius.circular(16)),
        child: Icon(
            record.fileType == 'pdf' ? Icons.picture_as_pdf_outlined
                : record.fileType == 'image' ? Icons.image_outlined
                : Icons.article_outlined,
            size: 36, color: OV.onSurfaceVariant)),
    const SizedBox(height: 14),
    Text(record.fileType == 'pdf' ? 'PDF Document' : 'Medical Record',
        style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700, color: OV.onSurface)),
    const SizedBox(height: 6),
    Text('Tap Download to view the full file',
        style: GoogleFonts.inter(fontSize: 12, color: OV.onSurfaceVariant)),
    const SizedBox(height: 16),
    Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(color: OV.primaryContainer, borderRadius: BorderRadius.circular(100)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.lock_outline_rounded, size: 12, color: OV.primary),
          const SizedBox(width: 6),
          Text('AES-256 Encrypted', style: GoogleFonts.inter(
              fontSize: 11, fontWeight: FontWeight.w700, color: OV.primary)),
        ])),
  ]);
}