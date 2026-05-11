// lib/screens/doctor/patient_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../models/patient_profile_model.dart';
import '../../models/doctor_model.dart';
import '../../services/doctor_service.dart';
import 'doctor_widgets.dart';
import 'full_medical_history_screen.dart';
import 'add_diagnosis_screen.dart';
import '../../features/ehr/presentation/pages/ehr_dashboard.dart'; // ← NEW

class PatientDetailScreen extends StatefulWidget {
  final String patientId, doctorId;
  const PatientDetailScreen({
    super.key,
    required this.patientId,
    required this.doctorId,
  });
  @override
  State<PatientDetailScreen> createState() => _PatientDetailScreenState();
}

class _PatientDetailScreenState extends State<PatientDetailScreen> {
  final _service = DoctorService();
  PatientProfile? _profile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await _service.fetchPatient(widget.patientId);
    setState(() { _profile = p; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(
        backgroundColor: OV.background,
        body: Center(child: CircularProgressIndicator(color: OV.primary)));
    final p = _profile;
    if (p == null) return Scaffold(
        body: Center(child: Text('Patient not found',
            style: GoogleFonts.inter(fontSize: 15))));

    return Scaffold(
      backgroundColor: OV.background,
      body: SafeArea(child: CustomScrollView(slivers: [

        // ── App Bar ─────────────────────────────────────────────
        SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: OV.outlineVariant.withOpacity(0.5))),
                      child: const Icon(Icons.arrow_back_ios_new_rounded,
                          size: 16, color: OV.onSurface))),
              Column(children: [
                Text('PATIENT RECORD #${p.medicalId}',
                    style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700,
                        letterSpacing: 0.8, color: OV.outline)),
                Text(p.name, style: GoogleFonts.manrope(
                    fontSize: 15, fontWeight: FontWeight.w700, color: OV.onSurface)),
              ]),
              Container(width: 36, height: 36,
                  decoration: BoxDecoration(shape: BoxShape.circle,
                      color: OV.primaryContainer,
                      border: Border.all(color: OV.primary.withOpacity(0.3), width: 1.5)),
                  child: Center(child: Text(
                      p.name.isNotEmpty ? p.name[0].toUpperCase() : 'P',
                      style: GoogleFonts.manrope(fontSize: 14,
                          fontWeight: FontWeight.w700, color: OV.primary)))),
            ]))),

        // ── Patient Header Card ──────────────────────────────────
        SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: DCard(radius: 20, child: Column(children: [
              Row(children: [
                Container(width: 70, height: 70,
                    decoration: BoxDecoration(
                        color: OV.primaryContainer,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: OV.primary.withOpacity(0.2), width: 2)),
                    child: Center(child: Text(
                        p.name.isNotEmpty ? p.name[0].toUpperCase() : 'P',
                        style: GoogleFonts.manrope(fontSize: 28,
                            fontWeight: FontWeight.w700, color: OV.primary)))),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.name, style: GoogleFonts.manrope(
                      fontSize: 18, fontWeight: FontWeight.w700, color: OV.onSurface)),
                  const SizedBox(height: 6),
                  Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: OV.primaryContainer,
                          borderRadius: BorderRadius.circular(100)),
                      child: Text('PATIENT ID: ${p.medicalId}',
                          style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800,
                              letterSpacing: 0.8, color: OV.primary))),
                ])),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                _InfoChip(label: p.age != null ? '${p.age} years old' : 'Age N/A',
                    icon: Icons.cake_outlined),
                const SizedBox(width: 8),
                if (p.activeDiagnosis.isNotEmpty)
                  _InfoChip(label: p.activeDiagnosis,
                      icon: Icons.medical_services_outlined),
                const SizedBox(width: 8),
                if (p.address.isNotEmpty)
                  _InfoChip(label: p.address.split(',').last.trim(),
                      icon: Icons.location_on_outlined),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: _MetaBlock(label: 'BLOOD TYPE',
                    value: p.bloodType.isNotEmpty ? p.bloodType : 'N/A')),
                Container(width: 1, height: 36,
                    color: OV.outlineVariant.withOpacity(0.4)),
                Expanded(child: _MetaBlock(label: 'LAST VISIT',
                    value: DateFormat('MMM d, yyyy').format(
                        DateTime.now().subtract(const Duration(days: 7))))),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                Container(width: 8, height: 8,
                    decoration: const BoxDecoration(
                        color: OV.tertiary, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text('STATUS', style: GoogleFonts.inter(fontSize: 10,
                    fontWeight: FontWeight.w700, letterSpacing: 0.8, color: OV.outline)),
                const SizedBox(width: 8),
                Text('Stable', style: GoogleFonts.manrope(fontSize: 14,
                    fontWeight: FontWeight.w700, color: OV.tertiary)),
              ]),
            ])))),

        const SliverToBoxAdapter(child: SizedBox(height: 14)),

        // ── Action Buttons ───────────────────────────────────────
        SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(children: [

              // Row 1: Telehealth + Export
              Row(children: [
                Expanded(child: OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.video_call_rounded, size: 16),
                    label: Text('Telehealth', style: GoogleFonts.manrope(
                        fontSize: 13, fontWeight: FontWeight.w700)),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: OV.primary,
                        side: BorderSide(color: OV.primary.withOpacity(0.4)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12)))),
                const SizedBox(width: 10),
                Expanded(child: OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.print_outlined, size: 16),
                    label: Text('Export', style: GoogleFonts.manrope(
                        fontSize: 13, fontWeight: FontWeight.w700)),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: OV.onSurface,
                        side: BorderSide(color: OV.outlineVariant),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12)))),
              ]),

              const SizedBox(height: 10),

              // ── EHR VAULT BUTTON ← NEW ───────────────────────
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.push(context, dSlide(
                      EhrDashboard(
                        patientId : widget.patientId,
                        doctorId  : widget.doctorId,   // ← passes doctorId
                      ))),
                  icon: const Icon(Icons.folder_shared_rounded, size: 18),
                  label: Text('Open EHR Vault',
                      style: GoogleFonts.manrope(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: OV.slateDark,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ]))),

        const SliverToBoxAdapter(child: SizedBox(height: 20)),

        // ── AI Insights placeholder ──────────────────────────────
        SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    gradient: LinearGradient(
                        colors: [OV.primary.withOpacity(0.08),
                          OV.primaryContainer.withOpacity(0.5)],
                        begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: OV.primary.withOpacity(0.2))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Row(children: [
                      Icon(Icons.auto_awesome_rounded, size: 16, color: OV.primary),
                      const SizedBox(width: 6),
                      Text('AI Insights', style: GoogleFonts.manrope(
                          fontSize: 14, fontWeight: FontWeight.w700, color: OV.primary)),
                    ]),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: OV.tertiaryContainer,
                            borderRadius: BorderRadius.circular(100)),
                        child: Text('REAL-TIME', style: GoogleFonts.inter(
                            fontSize: 9, fontWeight: FontWeight.w800,
                            letterSpacing: 0.8, color: OV.tertiary))),
                  ]),
                  const SizedBox(height: 12),
                  _InsightRow(title: 'Treatment Response',
                      body: 'Marker CA 19-9 decreased by 14% since last cycle. Positive response to current regimen.'),
                  const SizedBox(height: 8),
                  _InsightRow(title: 'Risk Alert',
                      body: 'Elevated WBC count detected (11.2k). Monitor for possible secondary infection.',
                      isAlert: true),
                  const SizedBox(height: 8),
                  _InsightRow(title: 'Next Suggestion',
                      body: 'Recommend baseline echocardiogram before starting Cycle 4 per updated protocol.'),
                ])))),

        const SliverToBoxAdapter(child: SizedBox(height: 20)),

        // ── Recent Labs ──────────────────────────────────────────
        SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SectionHeader(
                title: 'Recent Labs & Biomarkers',
                action: 'View Full Report',
                onAction: () => Navigator.push(context, dSlide(
                    FullMedicalHistoryScreen(
                        patientId  : widget.patientId,
                        doctorId   : widget.doctorId,
                        patientName: p.name)))))),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
        SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: DCard(child: Column(children: [
              _LabRow(name: 'Hemoglobin', value: '12.4', unit: 'g/dL',
                  status: 'WITHIN RANGE', statusColor: OV.tertiary,
                  bars: [0.7, 0.8, 0.75, 0.82]),
              DividerLine(),
              _LabRow(name: 'Creatinine', value: '0.9', unit: 'mg/dL',
                  status: 'STABLE TREND', statusColor: OV.secondary,
                  bars: [0.6, 0.65, 0.62, 0.63]),
              DividerLine(),
              _LabRow(name: 'CA 19-9', value: '42', unit: 'U/mL',
                  status: 'DECREASING ▾', statusColor: OV.tertiary,
                  bars: [0.9, 0.85, 0.75, 0.65], isDecreasing: true),
            ])))),

        const SliverToBoxAdapter(child: SizedBox(height: 20)),

        // ── Clinical Journey ─────────────────────────────────────
        SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SectionHeader(title: 'Clinical Journey'))),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
        SliverToBoxAdapter(child: StreamBuilder<List<DiagnosisEntry>>(
            stream: _service.watchPatientDiagnoses(widget.patientId),
            builder: (_, snap) {
              final diagnoses = snap.data ?? [];
              if (diagnoses.isEmpty) {
                return Padding(padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: DCard(child: Center(child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text('No clinical entries yet.',
                            style: GoogleFonts.inter(
                                fontSize: 13, color: OV.onSurfaceVariant))))));
              }
              return Padding(padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(children: diagnoses
                      .map((d) => _ClinicalEntry(entry: d)).toList()));
            })),

        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ])),

      floatingActionButton: FloatingActionButton.extended(
          onPressed: () => Navigator.push(context, dSlide(AddDiagnosisScreen(
              patientId  : widget.patientId,
              patientName: p.name,
              doctorId   : widget.doctorId,
              doctorName : 'Dr. ${_profile?.name ?? 'Doctor'}'))),
          backgroundColor: OV.slateDark,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add_rounded),
          label: Text('Add Diagnosis Note',
              style: GoogleFonts.manrope(fontWeight: FontWeight.w700))),
    );
  }
}

// ── All helper widgets unchanged ─────────────────────────────────
class _InfoChip extends StatelessWidget {
  final String label; final IconData icon;
  const _InfoChip({required this.label, required this.icon});
  @override
  Widget build(BuildContext context) => Flexible(child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: OV.surfaceLow,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: OV.outlineVariant.withOpacity(0.5))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: OV.outline),
        const SizedBox(width: 4),
        Flexible(child: Text(label,
            style: GoogleFonts.inter(fontSize: 10, color: OV.onSurface),
            maxLines: 1, overflow: TextOverflow.ellipsis)),
      ])));
}

class _MetaBlock extends StatelessWidget {
  final String label, value;
  const _MetaBlock({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w700,
            letterSpacing: 0.8, color: OV.outline)),
        const SizedBox(height: 2),
        Text(value, style: GoogleFonts.inter(fontSize: 13,
            fontWeight: FontWeight.w700, color: OV.onSurface)),
      ]));
}

class _InsightRow extends StatelessWidget {
  final String title, body; final bool isAlert;
  const _InsightRow({required this.title, required this.body, this.isAlert = false});
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: isAlert
              ? OV.errorContainer.withOpacity(0.5)
              : Colors.white.withOpacity(0.7),
          borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: GoogleFonts.manrope(fontSize: 12,
            fontWeight: FontWeight.w700,
            color: isAlert ? OV.error : OV.onSurface)),
        const SizedBox(height: 3),
        Text(body, style: GoogleFonts.inter(
            fontSize: 11, color: OV.onSurfaceVariant, height: 1.4)),
      ]));
}

class _LabRow extends StatelessWidget {
  final String name, value, unit, status;
  final Color statusColor;
  final List<double> bars;
  final bool isDecreasing;
  const _LabRow({required this.name, required this.value,
    required this.unit, required this.status, required this.statusColor,
    required this.bars, this.isDecreasing = false});
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: GoogleFonts.inter(fontSize: 12, color: OV.onSurfaceVariant)),
          const SizedBox(height: 2),
          RichText(text: TextSpan(children: [
            TextSpan(text: value, style: GoogleFonts.manrope(
                fontSize: 20, fontWeight: FontWeight.w700, color: OV.onSurface)),
            TextSpan(text: '  $unit', style: GoogleFonts.inter(
                fontSize: 11, color: OV.outline)),
          ])),
          const SizedBox(height: 4),
          Row(children: [
            Icon(isDecreasing
                ? Icons.trending_down_rounded
                : Icons.trending_up_rounded,
                size: 10, color: statusColor),
            const SizedBox(width: 3),
            Text(status, style: GoogleFonts.inter(fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5, color: statusColor)),
          ]),
        ])),
        Row(children: bars.map((h) => Container(
            width: 10, height: h * 40,
            margin: const EdgeInsets.only(left: 3),
            decoration: BoxDecoration(
                color: isDecreasing && h == bars.last
                    ? OV.error
                    : h == bars.last ? OV.primary
                    : OV.outlineVariant.withOpacity(0.5),
                borderRadius: BorderRadius.circular(3)))).toList()),
      ]));
}

class _ClinicalEntry extends StatelessWidget {
  final DiagnosisEntry entry;
  const _ClinicalEntry({required this.entry});
  @override
  Widget build(BuildContext context) => Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04),
              blurRadius: 8, offset: const Offset(0, 2))]),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 10, height: 10,
            margin: const EdgeInsets.only(top: 4, right: 12),
            decoration: const BoxDecoration(
                color: OV.primary, shape: BoxShape.circle)),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(entry.diagnosisTitle, style: GoogleFonts.manrope(
              fontSize: 14, fontWeight: FontWeight.w700, color: OV.onSurface)),
          const SizedBox(height: 2),
          Text(DateFormat('MMM d, yyyy').format(entry.createdAt).toUpperCase(),
              style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w700,
                  letterSpacing: 0.8, color: OV.outline)),
          const SizedBox(height: 4),
          Text(entry.diagnosisDetails, style: GoogleFonts.inter(
              fontSize: 12, color: OV.onSurfaceVariant, height: 1.4)),
          if (entry.blockchainVerified) ...[
            const SizedBox(height: 8),
            const BlockchainBadge(),
          ],
        ])),
      ]));
}