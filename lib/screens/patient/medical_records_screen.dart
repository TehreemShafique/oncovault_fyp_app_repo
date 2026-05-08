// lib/screens/patient/medical_records_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../models/medical_record_model.dart';
import '../../services/appointment_service.dart';
import 'report_viewer_screen.dart';
import 'diagnosis_history_screen.dart';

class MedicalRecordsScreen extends StatefulWidget {
  final String patientId;
  const MedicalRecordsScreen({super.key, required this.patientId});
  @override
  State<MedicalRecordsScreen> createState() => _MedicalRecordsScreenState();
}

class _MedicalRecordsScreenState extends State<MedicalRecordsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  final _service = MedicalRecordService();
  String? _activeFilter;

  final _filters = ['Bloodwork', 'MRI/CT Scans', 'Biopsies', 'Genetic Reports'];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OV.background,
      body: SafeArea(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── App Bar ──────────────────────────────────────────────
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              GestureDetector(onTap: () => Navigator.pop(context),
                  child: Container(padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: OV.outlineVariant.withOpacity(0.5))),
                      child: const Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: OV.onSurface))),
              const SizedBox(width: 8),
              Text('Account', style: GoogleFonts.inter(fontSize: 15, color: OV.onSurfaceVariant)),
              const SizedBox(width: 6),
              Text('OncoVault', style: GoogleFonts.manrope(
                  fontSize: 15, fontWeight: FontWeight.w700, color: OV.primary)),
            ])),

        // ── Header ───────────────────────────────────────────────
        Padding(padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Vault Records', style: GoogleFonts.manrope(
                  fontSize: 30, fontWeight: FontWeight.w700, color: OV.onSurface, letterSpacing: -0.4)),
              const SizedBox(height: 6),
              Text('Access your secure clinical documents, imaging reports, and historical treatment data with clinical-grade precision.',
                  style: GoogleFonts.inter(fontSize: 13, color: OV.onSurfaceVariant, height: 1.5)),
            ])),

        const SizedBox(height: 20),

        // ── Tabs ─────────────────────────────────────────────────
        Padding(padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SingleChildScrollView(scrollDirection: Axis.horizontal,
                child: Row(children: [
                  _TabChip(label: 'Medical History', selected: _tab.index == 0,
                      onTap: () => setState(() => _tab.animateTo(0))),
                  const SizedBox(width: 8),
                  _TabChip(label: 'Reports', selected: _tab.index == 1,
                      onTap: () => setState(() => _tab.animateTo(1))),
                  const SizedBox(width: 8),
                  _TabChip(label: 'Prescriptions', selected: _tab.index == 2,
                      onTap: () => setState(() => _tab.animateTo(2))),
                ]))),

        const SizedBox(height: 16),

        Expanded(child: TabBarView(controller: _tab, children: [
          // Medical History Tab
          _RecordsTab(
              patientId: widget.patientId, service: _service,
              type: RecordType.medicalHistory, filter: _activeFilter,
              onRecordTap: (r) => Navigator.push(context, _slide(DiagnosisHistoryScreen(patientId: widget.patientId))),
              extraBottom: _buildStorageCard()),

          // Reports Tab
          _RecordsTab(
              patientId: widget.patientId, service: _service,
              type: RecordType.report, filter: _activeFilter,
              onRecordTap: (r) => Navigator.push(context, _slide(ReportViewerScreen(record: r))),
              header: _buildSortHeader(),
              extraBottom: _buildFiltersCard()),

          // Prescriptions Tab
          _RecordsTab(
              patientId: widget.patientId, service: _service,
              type: RecordType.prescription, filter: _activeFilter,
              onRecordTap: (r) => Navigator.push(context, _slide(ReportViewerScreen(record: r)))),
        ])),
      ])),
    );
  }

  Widget _buildSortHeader() => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('Recent Reports', style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700, color: OV.onSurface)),
        Text('SORT BY DATE', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700,
            letterSpacing: 1, color: OV.outline)),
      ]));

  Widget _buildStorageCard() => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: OV.slateDark, borderRadius: BorderRadius.circular(20)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Storage Secure', style: GoogleFonts.manrope(
                fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
            const SizedBox(height: 8),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('82%', style: GoogleFonts.manrope(
                  fontSize: 36, fontWeight: FontWeight.w800, color: Colors.white)),
              const SizedBox(width: 10),
              Padding(padding: const EdgeInsets.only(bottom: 6),
                  child: Text('END-TO-END\nENCRYPTED', style: GoogleFonts.inter(
                      fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white60, letterSpacing: 0.5))),
            ]),
            const SizedBox(height: 12),
            ClipRRect(borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: 0.82, minHeight: 6,
                    backgroundColor: Colors.white24,
                    valueColor: const AlwaysStoppedAnimation(Colors.white))),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, height: 44,
                child: OutlinedButton(
                    onPressed: () {},
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white38),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: Text('Request Archive Access',
                        style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)))),
          ])));

  Widget _buildFiltersCard() => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
              border: Border.all(color: OV.outlineVariant.withOpacity(0.5))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('QUICK FILTERS', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700,
                letterSpacing: 1.2, color: OV.outline)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: _filters.map((f) {
              final sel = _activeFilter == f;
              return GestureDetector(
                  onTap: () => setState(() => _activeFilter = sel ? null : f),
                  child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                          color: sel ? OV.primary : OV.surfaceLow,
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(color: sel ? OV.primary : OV.outlineVariant.withOpacity(0.5))),
                      child: Text(f, style: GoogleFonts.inter(
                          fontSize: 12, fontWeight: FontWeight.w500,
                          color: sel ? Colors.white : OV.onSurface))));
            }).toList()),
            const SizedBox(height: 12),
            Row(children: [
              Icon(Icons.info_outline_rounded, size: 12, color: OV.outline),
              const SizedBox(width: 6),
              Expanded(child: Text(
                  'Looking for older records? If they are not visible in your digital vault, please contact our HIPAA-compliant records officer for manual retrieval.',
                  style: GoogleFonts.inter(fontSize: 11, color: OV.onSurfaceVariant, height: 1.4))),
            ]),
          ])));
}

class _TabChip extends StatelessWidget {
  final String label; final bool selected; final VoidCallback onTap;
  const _TabChip({required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
              color: selected ? OV.primaryContainer : Colors.white,
              borderRadius: BorderRadius.circular(100),
              border: Border.all(color: selected ? OV.primary.withOpacity(0.4) : OV.outlineVariant.withOpacity(0.5))),
          child: Text(label, style: GoogleFonts.inter(
              fontSize: 13, fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? OV.primary : OV.onSurfaceVariant))));
}

class _RecordsTab extends StatelessWidget {
  final String patientId;
  final MedicalRecordService service;
  final RecordType type;
  final String? filter;
  final ValueChanged<MedicalRecordModel> onRecordTap;
  final Widget? header, extraBottom;

  const _RecordsTab({
    required this.patientId, required this.service, required this.type,
    required this.onRecordTap, this.filter, this.header, this.extraBottom,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<MedicalRecordModel>>(
        stream: service.watchRecords(patientId, type: type),
        builder: (_, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: OV.primary));
          }
          final records = snap.data ?? [];
          return ListView(padding: const EdgeInsets.symmetric(horizontal: 20), children: [
            if (header != null) ...[header!, const SizedBox(height: 12)],
            if (records.isEmpty)
              Container(padding: const EdgeInsets.all(40),
                  child: Column(children: [
                    Icon(Icons.folder_outlined, size: 48, color: OV.outlineVariant),
                    const SizedBox(height: 12),
                    Text('No records found', style: GoogleFonts.inter(fontSize: 14, color: OV.onSurfaceVariant)),
                  ])),
            ...records.map((r) => _RecordCard(record: r, onTap: () => onRecordTap(r))),
            // Archive link
            GestureDetector(onTap: () {},
                child: Container(margin: const EdgeInsets.symmetric(vertical: 8),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                        color: Colors.transparent, borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: OV.outlineVariant.withOpacity(0.5),
                            style: BorderStyle.solid)),
                    child: Center(child: Text('View Archived Records (2022 and earlier)',
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: OV.onSurfaceVariant))))),
            if (extraBottom != null) ...[const SizedBox(height: 16), extraBottom!],
            const SizedBox(height: 24),
          ]);
        });
  }
}

class _RecordCard extends StatelessWidget {
  final MedicalRecordModel record; final VoidCallback onTap;
  const _RecordCard({required this.record, required this.onTap});

  IconData get _icon {
    switch (record.subtype.toLowerCase()) {
      case 'imaging':   return Icons.image_outlined;
      case 'pathology': return Icons.biotech_outlined;
      default:          return Icons.description_outlined;
    }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: onTap,
      child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 3))]),
          child: Column(children: [
            // Icon
            Container(width: 48, height: 48,
                decoration: BoxDecoration(color: OV.surfaceLow, borderRadius: BorderRadius.circular(12)),
                child: Icon(_icon, color: OV.onSurfaceVariant, size: 24)),
            const SizedBox(height: 12),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(record.title, style: GoogleFonts.manrope(
                    fontSize: 14, fontWeight: FontWeight.w700, color: OV.onSurface)),
                const SizedBox(height: 2),
                Text('${record.facility} • ${DateFormat('MMM d, yyyy').format(record.date)}',
                    style: GoogleFonts.inter(fontSize: 11, color: OV.onSurfaceVariant)),
              ])),
              if (record.subtype.isNotEmpty)
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: OV.primaryContainer, borderRadius: BorderRadius.circular(100)),
                    child: Text(record.subtype, style: GoogleFonts.inter(
                        fontSize: 10, fontWeight: FontWeight.w700, color: OV.primary))),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              GestureDetector(onTap: onTap, child: Row(children: [
                Icon(Icons.visibility_outlined, size: 14, color: OV.onSurfaceVariant),
                const SizedBox(width: 4),
                Text('View', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: OV.onSurface)),
              ])),
              const SizedBox(width: 20),
              GestureDetector(onTap: () {}, child: Row(children: [
                Icon(Icons.download_outlined, size: 14, color: OV.onSurfaceVariant),
                const SizedBox(width: 4),
                Text('Download', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: OV.onSurface)),
              ])),
            ]),
          ])));
}

PageRoute _slide(Widget page) => PageRouteBuilder(
    pageBuilder: (_, a, __) => page,
    transitionDuration: const Duration(milliseconds: 350),
    transitionsBuilder: (_, a, __, child) {
      final t = Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
          .chain(CurveTween(curve: Curves.easeOutCubic));
      return SlideTransition(position: a.drive(t), child: child);
    });