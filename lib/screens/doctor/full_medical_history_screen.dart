// lib/screens/doctor/full_medical_history_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../models/doctor_model.dart';
import '../../models/medical_record_model.dart';
import '../../services/doctor_service.dart';
import '../../services/nurse_service.dart';
import '../../models/vital_sign_model.dart';
import '../../models/clinical_note_model.dart';
import '../../services/fabric_gateway_service.dart';
import '../patient/report_viewer_screen.dart';
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
  void initState() { super.initState(); _tab = TabController(length: 6, vsync: this); }
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
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    indicator: BoxDecoration(color: OV.slateDark, borderRadius: BorderRadius.circular(9)),
                    labelStyle: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700),
                    unselectedLabelStyle: GoogleFonts.inter(fontSize: 11),
                    labelColor: Colors.white, unselectedLabelColor: OV.onSurfaceVariant,
                    dividerColor: Colors.transparent,
                    tabs: const [
                      Tab(text: 'History'),
                      Tab(text: 'Vitals'),
                      Tab(text: 'Notes'),
                      Tab(text: 'Reports'),
                      Tab(text: 'Prescriptions'),
                      Tab(text: 'Labs'),
                    ]))),

        const SizedBox(height: 12),

        Expanded(child: TabBarView(controller: _tab, children: [
          // History Tab
          _DiagnosisHistoryTab(patientId: widget.patientId, service: _service),
          // Vitals Tab
          _VitalsHistoryTab(patientId: widget.patientId),
          // Nursing Notes Tab
          _NotesHistoryTab(patientId: widget.patientId, service: _service),
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
                const BlockchainBadge(
                  status: FabricVerificationStatus.notAnchored,
                ),
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

  FabricVerificationStatus get _status {
    if (record.fabricTxId == null || record.fabricTxId!.isEmpty) {
      return FabricVerificationStatus.notAnchored;
    }
    // The record has an on-chain Fabric proof, but current content has not yet been
    // freshly verified against the ledger on this view. Show neutral 'Check Integrity'
    // until verified in ReportViewerScreen. Never assume green without fresh verification.
    return FabricVerificationStatus.pending;
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: () => Navigator.push(context, dSlide(ReportViewerScreen(record: record))),
      child: Container(
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
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                BlockchainBadge(status: _status),
                Row(children: [
                  Text('Inspect Ledger',
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: OV.primary)),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right_rounded, size: 14, color: OV.primary),
                ]),
              ],
            ),
          ])));
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

class _VitalsHistoryTab extends StatelessWidget {
  final String patientId;
  const _VitalsHistoryTab({required this.patientId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<VitalSignModel>>(
      stream: NurseService().watchPatientVitalsHistory(patientId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: OV.primary));
        }
        final observations = snapshot.data ?? [];
        if (observations.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.monitor_heart_outlined, size: 48, color: OV.outlineVariant),
                  const SizedBox(height: 12),
                  Text(
                    'No vital observations recorded',
                    style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700, color: OV.onSurface),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Vital sign entries by clinical nursing staff will appear here.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(fontSize: 12, color: OV.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          itemCount: observations.length,
          itemBuilder: (context, index) {
            final obs = observations[index];
            final dateFormat = DateFormat('MMM d, yyyy • h:mm a');
            final formattedDate = dateFormat.format(obs.recordedAt);
            final isCrit = obs.isCritical;
            final hasWarn = obs.warningFlags.isNotEmpty;

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isCrit
                      ? OV.error.withOpacity(0.4)
                      : hasWarn
                          ? const Color(0xFFF59E0B).withOpacity(0.4)
                          : OV.outlineVariant.withOpacity(0.4),
                  width: (isCrit || hasWarn) ? 1.5 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        formattedDate,
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: OV.onSurface),
                      ),
                      if (isCrit)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: const Color(0xFFFDE8E8), borderRadius: BorderRadius.circular(4)),
                          child: Text('CRITICAL', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w800, color: OV.error)),
                        )
                      else if (hasWarn)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(4)),
                          child: Text('WARNING', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w800, color: const Color(0xFFB45309))),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: OV.tertiaryContainer, borderRadius: BorderRadius.circular(4)),
                          child: Text('Normal', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w700, color: OV.tertiary)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('Nurse: ${obs.nurseName}', style: GoogleFonts.inter(fontSize: 11, color: OV.onSurfaceVariant)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _miniVital('BP', '${obs.systolicBp}/${obs.diastolicBp} mmHg'),
                      _miniVital('Pulse', '${obs.pulseRate} bpm'),
                      _miniVital('Temp', '${obs.temperatureCelsius.toStringAsFixed(1)} °C'),
                      _miniVital('SpO2', '${obs.oxygenSaturation}%'),
                      _miniVital('Resp', '${obs.respiratoryRate}/m'),
                    ],
                  ),
                  if (obs.warningFlags.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      obs.warningFlags.join(' • '),
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: isCrit ? OV.error : const Color(0xFF92400E)),
                    ),
                  ],
                  if (obs.notes != null && obs.notes!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Notes: ${obs.notes}',
                      style: GoogleFonts.inter(fontSize: 11, fontStyle: FontStyle.italic, color: OV.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _miniVital(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 9, color: OV.outline, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(value, style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w700, color: OV.onSurface)),
        ],
      ),
    );
  }
}

// ── Nursing Notes Tab ─────────────────────────────────────────────────────────
class _NotesHistoryTab extends StatefulWidget {
  final String patientId;
  final DoctorService service;

  const _NotesHistoryTab({required this.patientId, required this.service});

  @override
  State<_NotesHistoryTab> createState() => _NotesHistoryTabState();
}

class _NotesHistoryTabState extends State<_NotesHistoryTab> {
  String? _signingNoteId;

  Future<void> _reviewNote(ClinicalNoteModel note) async {
    final notesCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Sign Off Clinical Note',
          style: GoogleFonts.manrope(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sign off on documentation authored by ${note.authorName} (${note.authorRole.toUpperCase()}).',
              style: GoogleFonts.inter(fontSize: 13, color: OV.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notesCtrl,
              maxLines: 3,
              style: GoogleFonts.inter(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Attending physician notes / sign-off remarks (optional)',
                hintStyle: GoogleFonts.inter(fontSize: 12, color: OV.onSurfaceVariant),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: OV.outlineVariant),
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: OV.onSurfaceVariant)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('Sign Off', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _signingNoteId = note.noteId);
      try {
        await widget.service.reviewClinicalNote(
          patientId: widget.patientId,
          noteId: note.noteId,
          reviewNotes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Clinical note signed off successfully.', style: GoogleFonts.manrope(fontWeight: FontWeight.w600)),
              backgroundColor: Colors.green.shade700,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to sign off: $e'), backgroundColor: OV.error),
          );
        }
      } finally {
        if (mounted) setState(() => _signingNoteId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ClinicalNoteModel>>(
      stream: widget.service.watchPatientClinicalNotes(widget.patientId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: OV.primary));
        }
        final notes = snapshot.data ?? [];
        if (notes.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.description_outlined, size: 48, color: OV.outlineVariant),
                  const SizedBox(height: 12),
                  Text(
                    'No clinical notes recorded',
                    style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700, color: OV.onSurface),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Voice notes recorded by nurses will appear here for attending physician review.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(fontSize: 12, color: OV.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          );
        }

        final df = DateFormat('MMM d, yyyy • h:mm a');

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          itemCount: notes.length,
          itemBuilder: (context, index) {
            final note = notes[index];
            final isBusy = _signingNoteId == note.noteId;

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: note.status == ClinicalNoteStatus.submitted
                      ? OV.primary.withOpacity(0.4)
                      : OV.outlineVariant.withOpacity(0.4),
                  width: note.status == ClinicalNoteStatus.submitted ? 1.5 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        note.createdAt != null ? df.format(note.createdAt!) : 'Recently',
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: OV.onSurface),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildStatusBadge(note.status),
                          if (note.status != ClinicalNoteStatus.draft) ...[
                            const SizedBox(width: 6),
                            _buildFabricBadge(note.fabricStatus),
                          ],
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'By ${note.authorName} (${note.authorRole.toUpperCase()})',
                    style: GoogleFonts.inter(fontSize: 11, color: OV.onSurfaceVariant),
                  ),
                  if (note.clinicalSummary.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      note.clinicalSummary,
                      style: GoogleFonts.manrope(fontSize: 13, color: OV.onSurface, height: 1.3),
                    ),
                  ],
                  if (note.supportedExtractedSymptoms.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: note.supportedExtractedSymptoms.entries.map((e) {
                        final isPresent = e.value == true;
                        return Chip(
                          label: Text(
                            '${e.key}: ${isPresent ? "Present" : "Denied"}',
                            style: GoogleFonts.manrope(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: isPresent ? Colors.green.shade800 : Colors.red.shade800,
                            ),
                          ),
                          backgroundColor: isPresent ? Colors.green.shade50 : Colors.red.shade50,
                          side: BorderSide(color: isPresent ? Colors.green.shade200 : Colors.red.shade200),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        );
                      }).toList(),
                    ),
                  ],
                  if (note.narrativeObservations.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('Observations: ${note.narrativeObservations}',
                        style: GoogleFonts.inter(fontSize: 12, color: OV.onSurfaceVariant)),
                  ],
                  if (note.careInterventions.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text('Interventions: ${note.careInterventions}',
                        style: GoogleFonts.inter(fontSize: 12, color: OV.onSurfaceVariant)),
                  ],
                  if (note.status == ClinicalNoteStatus.reviewed) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.verified, size: 14, color: Colors.green),
                              const SizedBox(width: 4),
                              Text(
                                'Signed off by ${note.reviewedByName ?? "Doctor"}',
                                style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.green.shade900),
                              ),
                            ],
                          ),
                          if (note.doctorReviewNotes != null && note.doctorReviewNotes!.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              note.doctorReviewNotes!,
                              style: GoogleFonts.inter(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.green.shade800),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  if (note.status == ClinicalNoteStatus.submitted) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton.icon(
                        onPressed: isBusy ? null : () => _reviewNote(note),
                        icon: isBusy
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.check_circle_outline, size: 15),
                        label: Text(
                          isBusy ? 'Signing Off...' : 'Review & Sign Off',
                          style: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade700,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStatusBadge(ClinicalNoteStatus status) {
    Color bg;
    Color fg;
    String label;

    switch (status) {
      case ClinicalNoteStatus.draft:
        bg = Colors.amber.shade100;
        fg = Colors.amber.shade900;
        label = 'DRAFT';
        break;
      case ClinicalNoteStatus.submitted:
        bg = Colors.blue.shade100;
        fg = Colors.blue.shade900;
        label = 'SUBMITTED';
        break;
      case ClinicalNoteStatus.reviewed:
        bg = Colors.green.shade100;
        fg = Colors.green.shade900;
        label = 'REVIEWED';
        break;
      case ClinicalNoteStatus.amended:
        bg = Colors.purple.shade100;
        fg = Colors.purple.shade900;
        label = 'AMENDED';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(
        label,
        style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w800, color: fg),
      ),
    );
  }

  Widget _buildFabricBadge(String? fabricStatus) {
    final status = (fabricStatus ?? 'PENDING').toUpperCase();
    Color bg;
    Color fg;
    IconData icon;
    String label;

    switch (status) {
      case 'COMMITTED':
        bg = const Color(0xFFE8F5E9);
        fg = const Color(0xFF2E7D32);
        icon = Icons.check_circle_outline;
        label = 'COMMITTED';
        break;
      case 'PROCESSING':
        bg = const Color(0xFFE3F2FD);
        fg = const Color(0xFF1565C0);
        icon = Icons.sync_rounded;
        label = 'PROCESSING';
        break;
      case 'FAILED_RETRYABLE':
        bg = const Color(0xFFFFF9C4);
        fg = const Color(0xFFF57F17);
        icon = Icons.warning_amber_rounded;
        label = 'RETRY PENDING';
        break;
      case 'FAILED_PERMANENT':
      case 'FAILED':
        bg = const Color(0xFFFFEBEE);
        fg = const Color(0xFFC62828);
        icon = Icons.error_outline;
        label = 'FAILED';
        break;
      case 'PENDING':
      default:
        bg = const Color(0xFFFFF3E0);
        fg = const Color(0xFFEF6C00);
        icon = Icons.schedule;
        label = 'PENDING';
        break;
    }

    return Container(
      key: Key('doctor_fabric_badge_${status.toLowerCase()}'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: fg.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}