// lib/screens/doctor/full_medical_history_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../models/doctor_model.dart';
import '../../models/medical_record_model.dart';
import '../../services/doctor_service.dart';
import 'doctor_widgets.dart';
import 'add_diagnosis_screen.dart';

class FullMedicalHistoryScreen extends StatefulWidget {
  final String patientId, doctorId, patientName;
  const FullMedicalHistoryScreen({super.key, required this.patientId,
    required this.doctorId, required this.patientName});
  @override
  State<FullMedicalHistoryScreen> createState() => _FullMedicalHistoryScreenState();
}

class _FullMedicalHistoryScreenState extends State<FullMedicalHistoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  final _service = DoctorService();

  @override
  void initState() { super.initState(); _tab = TabController(length: 4, vsync: this); }
  @override
  void dispose() { _tab.dispose(); super.dispose(); }

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
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('EHR — ${widget.patientName}', style: GoogleFonts.manrope(
                    fontSize: 16, fontWeight: FontWeight.w700, color: OV.onSurface)),
                const BlockchainBadge(),
              ])),
              GestureDetector(onTap: () {},
                  child: Container(padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: OV.outlineVariant.withOpacity(0.5))),
                      child: Icon(Icons.print_outlined, size: 16, color: OV.primary))),
            ])),

        // ── Tabs ─────────────────────────────────────────────────
        Padding(padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(height: 42, padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: OV.outlineVariant.withOpacity(0.5))),
                child: TabBar(controller: _tab,
                    indicator: BoxDecoration(color: OV.slateDark, borderRadius: BorderRadius.circular(9)),
                    labelStyle: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700),
                    unselectedLabelStyle: GoogleFonts.inter(fontSize: 11),
                    labelColor: Colors.white, unselectedLabelColor: OV.onSurfaceVariant,
                    dividerColor: Colors.transparent,
                    tabs: const [Tab(text: 'History'), Tab(text: 'Reports'),
                      Tab(text: 'Prescriptions'), Tab(text: 'Labs')]))),

        const SizedBox(height: 12),

        Expanded(child: TabBarView(controller: _tab, children: [
          // History Tab
          _DiagnosisHistoryTab(patientId: widget.patientId, service: _service),
          // Reports Tab
          _RecordsTab(patientId: widget.patientId, service: _service, type: RecordType.report),
          // Prescriptions Tab
          _RecordsTab(patientId: widget.patientId, service: _service, type: RecordType.prescription),
          // Labs Tab
          _LabsTab(patientId: widget.patientId, service: _service),
        ])),
      ])),
      floatingActionButton: FloatingActionButton(
          onPressed: () => Navigator.push(context, dSlide(AddDiagnosisScreen(
              patientId: widget.patientId, patientName: widget.patientName,
              doctorId: widget.doctorId, doctorName: 'Doctor'))),
          backgroundColor: OV.slateDark, foregroundColor: Colors.white,
          child: const Icon(Icons.add_rounded)),
    );
  }
}

// ── Diagnosis History Tab ─────────────────────────────────────────────────────
class _DiagnosisHistoryTab extends StatelessWidget {
  final String patientId; final DoctorService service;
  const _DiagnosisHistoryTab({required this.patientId, required this.service});

  @override
  Widget build(BuildContext context) => StreamBuilder<List<DiagnosisEntry>>(
      stream: service.watchPatientDiagnoses(patientId),
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: OV.primary));
        }
        final entries = snap.data ?? [];
        if (entries.isEmpty) {
          return _Empty(icon: Icons.history_rounded, msg: 'No diagnosis history yet');
        }
        return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: entries.length,
            itemBuilder: (_, i) => _HistoryTimelineCard(entry: entries[i], isLast: i == entries.length - 1));
      });
}

class _HistoryTimelineCard extends StatelessWidget {
  final DiagnosisEntry entry; final bool isLast;
  const _HistoryTimelineCard({required this.entry, required this.isLast});

  Color get _statusColor {
    switch (entry.status.toLowerCase()) {
      case 'critical':   return OV.error;
      case 'follow-up':  return const Color(0xFF8B5000);
      case 'monitoring': return OV.primary;
      default:           return OV.tertiary;
    }
  }

  @override
  Widget build(BuildContext context) => IntrinsicHeight(child: Row(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
    // Timeline spine
    SizedBox(width: 32, child: Column(children: [
      Container(width: 14, height: 14, decoration: BoxDecoration(
          color: _statusColor, shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.5),
          boxShadow: [BoxShadow(color: _statusColor.withOpacity(0.3), blurRadius: 6)])),
      if (!isLast) Expanded(child: Center(
          child: Container(width: 2, color: OV.outlineVariant.withOpacity(0.4)))),
    ])),
    // Card
    Expanded(child: Padding(padding: const EdgeInsets.only(left: 10, bottom: 16),
        child: Container(padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04),
                    blurRadius: 10, offset: const Offset(0, 3))]),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(DateFormat('MMM d, yyyy').format(entry.createdAt).toUpperCase(),
                  style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w700,
                      letterSpacing: 0.8, color: OV.outline)),
              const SizedBox(height: 6),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Expanded(child: Text(entry.diagnosisTitle, style: GoogleFonts.manrope(
                    fontSize: 14, fontWeight: FontWeight.w700, color: OV.onSurface))),
                PatientStatusChip(status: entry.status),
              ]),
              if (entry.diagnosisDetails.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(entry.diagnosisDetails, style: GoogleFonts.inter(
                    fontSize: 12, color: OV.onSurfaceVariant, height: 1.5)),
              ],
              if (entry.prescription.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: OV.primaryContainer.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(10)),
                    child: Row(children: [
                      Icon(Icons.medication_outlined, size: 14, color: OV.primary),
                      const SizedBox(width: 6),
                      Expanded(child: Text(entry.prescription,
                          style: GoogleFonts.inter(fontSize: 11, color: OV.primary, height: 1.3))),
                    ])),
              ],
              if (entry.clinicalNotes.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('Notes: ${entry.clinicalNotes}', style: GoogleFonts.inter(
                    fontSize: 11, color: OV.onSurfaceVariant, fontStyle: FontStyle.italic)),
              ],
              const SizedBox(height: 10),
              Row(children: [
                Text('By ${entry.doctorName}', style: GoogleFonts.inter(
                    fontSize: 10, color: OV.outline, fontWeight: FontWeight.w500)),
                const Spacer(),
                if (entry.blockchainVerified) const BlockchainBadge(),
              ]),
            ])))),
  ]));
}

// ── Records Tab ───────────────────────────────────────────────────────────────
class _RecordsTab extends StatelessWidget {
  final String patientId; final DoctorService service; final RecordType type;
  const _RecordsTab({required this.patientId, required this.service, required this.type});

  @override
  Widget build(BuildContext context) => StreamBuilder<List<MedicalRecordModel>>(
      stream: service.watchPatientRecords(patientId),
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: OV.primary));
        }
        final records = (snap.data ?? []).where((r) => r.type == type).toList();
        if (records.isEmpty) return _Empty(icon: Icons.folder_outlined, msg: 'No records found');
        return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: records.length,
            itemBuilder: (_, i) => _RecordCard(record: records[i]));
      });
}

class _RecordCard extends StatelessWidget {
  final MedicalRecordModel record;
  const _RecordCard({required this.record});
  @override
  Widget build(BuildContext context) => Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 42, height: 42, decoration: BoxDecoration(
              color: OV.secondaryContainer, borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.description_outlined, color: OV.secondary, size: 20)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(record.title, style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w700, color: OV.onSurface)),
            Text('${record.facility} · ${DateFormat('MMM d, yyyy').format(record.date)}',
                style: GoogleFonts.inter(fontSize: 11, color: OV.onSurfaceVariant)),
          ])),
          if (record.subtype.isNotEmpty)
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: OV.primaryContainer, borderRadius: BorderRadius.circular(100)),
                child: Text(record.subtype, style: GoogleFonts.inter(
                    fontSize: 10, fontWeight: FontWeight.w700, color: OV.primary))),
        ]),
        if (record.summary.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(record.summary, style: GoogleFonts.inter(
              fontSize: 12, color: OV.onSurfaceVariant, height: 1.4)),
        ],
      ]));
}

// ── Labs Tab ──────────────────────────────────────────────────────────────────
class _LabsTab extends StatelessWidget {
  final String patientId; final DoctorService service;
  const _LabsTab({required this.patientId, required this.service});

  // Mock lab data rows that would come from Firestore in production
  static const _labData = [
    {'test': 'Complete Blood Count (CBC)', 'doctor': 'Dr. Julian Marks', 'date': 'Sep 12, 2023',
      'status': 'NORMAL', 'results': [
      {'name': 'White Blood Cells', 'value': '6.2', 'unit': '10³/μL'},
      {'name': 'Red Blood Cells', 'value': '4.8', 'unit': '10⁶/μL'},
      {'name': 'Platelets', 'value': '210', 'unit': '10³/μL'},
    ], 'note': 'Results show counts within optimal therapeutic ranges for the current cycle.'},
    {'test': 'Liver Function Panel', 'doctor': 'Dr. Julian Marks', 'date': 'Sep 02, 2023',
      'status': 'REVIEW', 'results': [
      {'name': 'ALT (SGPT)', 'value': '58', 'unit': 'U/L', 'isHigh': true, 'ref': '7-52'},
      {'name': 'AST (SGOT)', 'value': '34', 'unit': 'U/L'},
      {'name': 'Albumin', 'value': '4.1', 'unit': 'g/dL'},
    ], 'note': 'Mild elevation in ALT noted. Recommend hydration and re-test in 7 days.'},
  ];

  @override
  Widget build(BuildContext context) => ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: _labData.length,
      itemBuilder: (_, i) => _LabCard(data: _labData[i]));
}

class _LabCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _LabCard({required this.data});

  Color get _statusColor => data['status'] == 'NORMAL' ? OV.tertiary
      : data['status'] == 'REVIEW' ? const Color(0xFF8B5000) : OV.error;
  Color get _statusBg => data['status'] == 'NORMAL' ? OV.tertiaryContainer
      : data['status'] == 'REVIEW' ? const Color(0xFFFFF3E0) : OV.errorContainer;

  @override
  Widget build(BuildContext context) => Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 3))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(children: [
              Container(width: 40, height: 40,
                  decoration: BoxDecoration(color: OV.secondaryContainer, borderRadius: BorderRadius.circular(12)),
                  child: Icon(Icons.science_outlined, color: OV.secondary, size: 20)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(data['test'] as String, style: GoogleFonts.manrope(
                    fontSize: 13, fontWeight: FontWeight.w700, color: OV.onSurface)),
                Text('Ordered by ${data['doctor']} · ${data['date']}',
                    style: GoogleFonts.inter(fontSize: 10, color: OV.onSurfaceVariant)),
              ])),
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: _statusBg, borderRadius: BorderRadius.circular(100)),
                  child: Text(data['status'] as String, style: GoogleFonts.inter(
                      fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: _statusColor))),
            ])),
        Container(height: 1, color: OV.outlineVariant.withOpacity(0.3)),
        Padding(padding: const EdgeInsets.all(16), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          ...(data['results'] as List).map((r) {
            final isHigh = r['isHigh'] == true;
            return Padding(padding: const EdgeInsets.only(bottom: 10), child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r['name'] as String, style: GoogleFonts.inter(
                  fontSize: 11, color: OV.onSurfaceVariant)),
              const SizedBox(height: 2),
              Row(children: [
                Text(r['value'] as String, style: GoogleFonts.manrope(
                    fontSize: 20, fontWeight: FontWeight.w700,
                    color: isHigh ? OV.error : OV.onSurface)),
                const SizedBox(width: 6),
                Text(r['unit'] as String, style: GoogleFonts.inter(fontSize: 11, color: OV.outline)),
                if (isHigh) ...[
                  const SizedBox(width: 8),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: OV.errorContainer, borderRadius: BorderRadius.circular(6)),
                      child: Text('High (Ref: ${r['ref']})', style: GoogleFonts.inter(
                          fontSize: 9, fontWeight: FontWeight.w700, color: OV.error))),
                ],
              ]),
            ]));
          }),
          if (data['note'] != null && (data['note'] as String).isNotEmpty) ...[
            Container(height: 1, color: OV.outlineVariant.withOpacity(0.3)),
            const SizedBox(height: 10),
            Row(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: Text('"${data['note']}"', style: GoogleFonts.inter(
                      fontSize: 11, color: OV.onSurfaceVariant, fontStyle: FontStyle.italic, height: 1.4))),
                  const SizedBox(width: 10),
                  GestureDetector(onTap: () {},
                      child: Row(children: [
                        Text('View\nFull', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: OV.primary)),
                        Icon(Icons.arrow_forward_rounded, size: 12, color: OV.primary),
                      ])),
                ]),
          ],
        ])),
      ]));
}

class _Empty extends StatelessWidget {
  final IconData icon; final String msg;
  const _Empty({required this.icon, required this.msg});
  @override
  Widget build(BuildContext context) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 48, color: OV.outlineVariant),
    const SizedBox(height: 12),
    Text(msg, style: GoogleFonts.inter(fontSize: 14, color: OV.onSurfaceVariant)),
  ]));
}