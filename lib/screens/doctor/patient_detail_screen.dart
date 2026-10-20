// lib/screens/doctor/patient_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../models/patient_profile_model.dart';
import '../../models/doctor_model.dart';
import '../../services/doctor_service.dart';
import '../../services/nurse_service.dart';
import '../../models/vital_sign_model.dart';
import '../../models/clinical_note_model.dart';
import '../../models/treatment_plan_model.dart';
import '../../services/treatment_tracking_service.dart';
import '../../services/fabric_gateway_service.dart';
import '../nurse/patient_vitals_history_screen.dart';
import '../nurse/patient_notes_history_screen.dart';
import 'doctor_widgets.dart';
import 'full_medical_history_screen.dart';
import 'add_diagnosis_screen.dart';
import 'prescription_screen.dart';
import 'blood_cancer_ehr_screen.dart';
import 'doctor_treatment_plan_screen.dart';
import 'create_treatment_plan_screen.dart';

class PatientDetailScreen extends StatefulWidget {
  final String patientId, doctorId;
  final TreatmentTrackingService? treatmentService;
  const PatientDetailScreen({
    super.key,
    required this.patientId,
    required this.doctorId,
    this.treatmentService,
  });
  @override
  State<PatientDetailScreen> createState() => _PatientDetailScreenState();
}

class _PatientDetailScreenState extends State<PatientDetailScreen> {
  final _service = DoctorService();
  final _nurseService = NurseService();
  PatientProfile? _profile;
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final p = await _service.fetchPatient(widget.patientId);
    setState(() { _profile = p; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(backgroundColor: OV.background,
        body: Center(child: CircularProgressIndicator(color: OV.primary)));
    final p = _profile;
    if (p == null) return Scaffold(body: Center(child: Text('Patient not found',
        style: GoogleFonts.inter(fontSize: 15))));

    return Scaffold(
      backgroundColor: OV.background,
      body: SafeArea(child: CustomScrollView(slivers: [

        // ── App Bar ──────────────────────────────────────────────
        SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              GestureDetector(onTap: () => Navigator.pop(context),
                  child: Container(padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: OV.outlineVariant.withOpacity(0.5))),
                      child: const Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: OV.onSurface))),
              Column(children: [
                Text('PATIENT RECORD #${p.medicalId}',
                    style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700,
                        letterSpacing: 0.8, color: OV.outline)),
                Text(p.name, style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700, color: OV.onSurface)),
              ]),
              Container(width: 36, height: 36,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: OV.primaryContainer,
                      border: Border.all(color: OV.primary.withOpacity(0.3), width: 1.5)),
                  child: Center(child: Text(p.name.isNotEmpty ? p.name[0].toUpperCase() : 'P',
                      style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w700, color: OV.primary)))),
            ]))),

        // ── Patient Header Card ───────────────────────────────────
        SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: DCard(radius: 20, child: Column(children: [
              // Avatar + basic info
              Row(children: [
                Container(width: 70, height: 70, decoration: BoxDecoration(
                    color: OV.primaryContainer, borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: OV.primary.withOpacity(0.2), width: 2)),
                    child: Center(child: Text(p.name.isNotEmpty ? p.name[0].toUpperCase() : 'P',
                        style: GoogleFonts.manrope(fontSize: 28, fontWeight: FontWeight.w700, color: OV.primary)))),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.name, style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w700, color: OV.onSurface)),
                  const SizedBox(height: 6),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: OV.primaryContainer, borderRadius: BorderRadius.circular(100)),
                      child: Text('PATIENT ID: ${p.medicalId}',
                          style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800,
                              letterSpacing: 0.8, color: OV.primary))),
                ])),
              ]),
              const SizedBox(height: 16),
              // Info row
              Row(children: [
                _InfoChip(label: p.age != null ? '${p.age} years old' : 'Age N/A', icon: Icons.cake_outlined),
                const SizedBox(width: 8),
                if (p.activeDiagnosis.isNotEmpty)
                  _InfoChip(label: p.activeDiagnosis, icon: Icons.medical_services_outlined),
                const SizedBox(width: 8),
                if (p.address.isNotEmpty)
                  _InfoChip(label: p.address.split(',').last.trim(), icon: Icons.location_on_outlined),
              ]),
              const SizedBox(height: 14),
              // Medical metadata
              Row(children: [
                Expanded(child: _MetaBlock(label: 'BLOOD TYPE',
                    value: p.bloodType.isNotEmpty ? p.bloodType : 'N/A')),
                Container(width: 1, height: 36, color: OV.outlineVariant.withOpacity(0.4)),
                Expanded(child: _MetaBlock(label: 'LAST VISIT',
                    value: DateFormat('MMM d, yyyy').format(DateTime.now().subtract(const Duration(days: 7))))),
              ]),
              const SizedBox(height: 14),
              // Status
              Row(children: [
                Container(width: 8, height: 8, decoration: const BoxDecoration(
                    color: OV.tertiary, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text('STATUS', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700,
                    letterSpacing: 0.8, color: OV.outline)),
                const SizedBox(width: 8),
                Text('Stable', style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w700, color: OV.tertiary)),
              ]),
            ])))),

        const SliverToBoxAdapter(child: SizedBox(height: 14)),

        // ── Electronic Health Record (EHR) Action Card ─────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: GestureDetector(
              onTap: () => Navigator.push(
                context,
                dSlide(BloodCancerEhrScreen(
                  patientId: widget.patientId,
                  patientName: p.name,
                  doctorId: widget.doctorId,
                  doctorName: widget.doctorId,
                )),
              ),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: OV.slateDark,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.medical_information_rounded, color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Open Patient EHR',
                            style: GoogleFonts.manrope(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'View & update complete clinical records, CBC, and treatment',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: Colors.white.withOpacity(0.75),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 16),
                  ],
                ),
              ),
            ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 14)),

        // ── Patient Vital Signs Summary Card ──────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _DoctorVitalsCard(
              patientId: widget.patientId,
              patientName: p.name,
              nurseService: _nurseService,
            ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 14)),

        // ── Nursing Clinical Notes Summary Card ────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _DoctorClinicalNotesCard(
              patientId: widget.patientId,
              patientName: p.name,
              doctorService: _service,
            ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 14)),

        // ── Doctor Treatment Plan & Progress Card (Phase 3D.4) ──────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _DoctorTreatmentPlanCard(
              patientId: widget.patientId,
              patientName: p.name,
              doctorId: widget.doctorId,
              treatmentService: widget.treatmentService,
            ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 14)),

        // ── AI Insights placeholder ───────────────────────────────
        SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    gradient: LinearGradient(
                        colors: [OV.primary.withOpacity(0.08), OV.primaryContainer.withOpacity(0.5)],
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
                        decoration: BoxDecoration(color: OV.tertiaryContainer, borderRadius: BorderRadius.circular(100)),
                        child: Text('REAL-TIME', style: GoogleFonts.inter(
                            fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: OV.tertiary))),
                  ]),
                  const SizedBox(height: 12),
                  _InsightRow(title: 'Treatment Response',
                      body: 'Marker CA 19-9 decreased by 14% since the last cycle. Positive response to current regimen.'),
                  const SizedBox(height: 8),
                  _InsightRow(title: 'Risk Alert',
                      body: 'Elevated white blood cell count detected (11.2k). Monitor for possible secondary infection.',
                      isAlert: true),
                  const SizedBox(height: 8),
                  _InsightRow(title: 'Next Suggestion',
                      body: 'Recommend baseline echocardiogram before starting Cycle 4 per updated protocol.'),
                ])))),



        const SliverToBoxAdapter(child: SizedBox(height: 20)),

        // ── Clinical Journey ──────────────────────────────────────
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
                            style: GoogleFonts.inter(fontSize: 13, color: OV.onSurfaceVariant))))));
              }
              return Padding(padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(children: diagnoses.map((d) => _ClinicalEntry(entry: d)).toList()));
            })),

        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ])),
      floatingActionButton: Column(mainAxisSize: MainAxisSize.min, children: [
        FloatingActionButton(
            heroTag: 'prescription',
            onPressed: () => Navigator.push(context, dSlide(PrescriptionScreen(
                doctorId: widget.doctorId,
                doctorName: widget.doctorId,
                doctorSpecialty: '',
                patientId: widget.patientId,
                patientName: p.name))),
            backgroundColor: OV.primary, foregroundColor: Colors.white,
            child: const Icon(Icons.medication_rounded)),
        const SizedBox(height: 12),
        FloatingActionButton.extended(
            heroTag: 'diagnosis',
            onPressed: () => Navigator.push(context, dSlide(AddDiagnosisScreen(
                patientId: widget.patientId, patientName: p.name, doctorId: widget.doctorId,
                doctorName: widget.doctorId))),
            backgroundColor: OV.slateDark, foregroundColor: Colors.white,
            icon: const Icon(Icons.add_rounded),
            label: Text('Add Diagnosis', style: GoogleFonts.manrope(fontWeight: FontWeight.w700))),
      ]),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label; final IconData icon;
  const _InfoChip({required this.label, required this.icon});
  @override
  Widget build(BuildContext context) => Flexible(child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: OV.surfaceLow, borderRadius: BorderRadius.circular(100),
          border: Border.all(color: OV.outlineVariant.withOpacity(0.5))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: OV.outline),
        const SizedBox(width: 4),
        Flexible(child: Text(label, style: GoogleFonts.inter(fontSize: 10, color: OV.onSurface),
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
        Text(value, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: OV.onSurface)),
      ]));
}

class _InsightRow extends StatelessWidget {
  final String title, body; final bool isAlert;
  const _InsightRow({required this.title, required this.body, this.isAlert = false});
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: isAlert ? OV.errorContainer.withOpacity(0.5) : Colors.white.withOpacity(0.7),
          borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w700,
            color: isAlert ? OV.error : OV.onSurface)),
        const SizedBox(height: 3),
        Text(body, style: GoogleFonts.inter(fontSize: 11, color: OV.onSurfaceVariant, height: 1.4)),
      ]));
}



class _ClinicalEntry extends StatelessWidget {
  final DiagnosisEntry entry;
  const _ClinicalEntry({required this.entry});
  @override
  Widget build(BuildContext context) => Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))]),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 10, height: 10, margin: const EdgeInsets.only(top: 4, right: 12),
            decoration: const BoxDecoration(color: OV.primary, shape: BoxShape.circle)),
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
          const SizedBox(height: 8),
          const BlockchainBadge(
            status: FabricVerificationStatus.notAnchored,
          ),
        ])),
      ]));
}

class _DoctorVitalsCard extends StatelessWidget {
  final String patientId;
  final String patientName;
  final NurseService nurseService;

  const _DoctorVitalsCard({
    required this.patientId,
    required this.patientName,
    required this.nurseService,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<VitalSignModel?>(
      stream: nurseService.watchLatestPatientVitals(patientId),
      builder: (context, snapshot) {
        final vitals = snapshot.data;
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: vitals?.isCritical == true
                  ? OV.error.withOpacity(0.5)
                  : vitals != null && vitals.warningFlags.isNotEmpty
                      ? const Color(0xFFF59E0B).withOpacity(0.5)
                      : OV.outlineVariant.withOpacity(0.5),
              width: (vitals != null && (vitals.isCritical || vitals.warningFlags.isNotEmpty)) ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: OV.primary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.monitor_heart_rounded, color: OV.primary, size: 16),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Latest Vital Signs',
                        style: GoogleFonts.manrope(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: OV.onSurface,
                        ),
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PatientVitalsHistoryScreen(
                            patientId: patientId,
                            patientName: patientName,
                          ),
                        ),
                      );
                    },
                    child: Text(
                      'History →',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: OV.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (vitals == null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'No vital observations recorded yet by nursing staff.',
                    style: GoogleFonts.inter(fontSize: 12, color: OV.onSurfaceVariant),
                  ),
                )
              else ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Recorded by Nurse ${vitals.nurseName} • ${DateFormat('MMM d, h:mm a').format(vitals.recordedAt)}',
                      style: GoogleFonts.inter(fontSize: 11, color: OV.onSurfaceVariant),
                    ),
                    if (vitals.isCritical)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFDE8E8),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'CRITICAL',
                          style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w800, color: OV.error),
                        ),
                      )
                    else if (vitals.warningFlags.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'WARNING',
                          style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w800, color: const Color(0xFFB45309)),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _vitalItem('BP', '${vitals.systolicBp}/${vitals.diastolicBp}', 'mmHg'),
                    _vitalItem('Pulse', '${vitals.pulseRate}', 'bpm'),
                    _vitalItem('Temp', '${vitals.temperatureCelsius.toStringAsFixed(1)}°C', '${vitals.temperatureFahrenheit.toStringAsFixed(1)}°F'),
                    _vitalItem('SpO2', '${vitals.oxygenSaturation}%', ''),
                    _vitalItem('Resp', '${vitals.respiratoryRate}', '/min'),
                  ],
                ),
                if (vitals.warningFlags.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: vitals.isCritical ? const Color(0xFFFDE8E8) : const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      vitals.warningFlags.join(' • '),
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: vitals.isCritical ? OV.error : const Color(0xFF92400E),
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _vitalItem(String label, String value, String unit) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 10, color: OV.outline, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(value, style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700, color: OV.onSurface)),
          if (unit.isNotEmpty)
            Text(unit, style: GoogleFonts.inter(fontSize: 9, color: OV.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _DoctorClinicalNotesCard extends StatefulWidget {
  final String patientId;
  final String patientName;
  final DoctorService doctorService;

  const _DoctorClinicalNotesCard({
    required this.patientId,
    required this.patientName,
    required this.doctorService,
  });

  @override
  State<_DoctorClinicalNotesCard> createState() => _DoctorClinicalNotesCardState();
}

class _DoctorClinicalNotesCardState extends State<_DoctorClinicalNotesCard> {
  bool _isSigning = false;

  Future<void> _showSignOffDialog(ClinicalNoteModel note) async {
    final notesCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Doctor Sign-Off',
          style: GoogleFonts.manrope(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sign off on clinical documentation by ${note.authorName} (${note.authorRole.toUpperCase()}) submitted for this patient.',
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
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: OV.onSurfaceVariant),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(
              'Sign Off',
              style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _isSigning = true);
      try {
        await widget.doctorService.reviewClinicalNote(
          patientId: widget.patientId,
          noteId: note.noteId,
          reviewNotes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Clinical note signed off successfully.',
                style: GoogleFonts.manrope(fontWeight: FontWeight.w600),
              ),
              backgroundColor: Colors.green.shade700,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to sign off: $e'),
              backgroundColor: OV.error,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _isSigning = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ClinicalNoteModel>>(
      stream: widget.doctorService.watchPatientClinicalNotes(widget.patientId),
      builder: (context, snapshot) {
        final notes = snapshot.data ?? [];
        final submittedNotes = notes.where((n) => n.status == ClinicalNoteStatus.submitted).toList();
        final latestNote = notes.isNotEmpty ? notes.first : null;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: submittedNotes.isNotEmpty
                  ? OV.primary.withOpacity(0.5)
                  : OV.outlineVariant.withOpacity(0.5),
              width: submittedNotes.isNotEmpty ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: OV.secondary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.description_rounded, color: OV.secondary, size: 16),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Nursing Clinical Notes',
                        style: GoogleFonts.manrope(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: OV.onSurface,
                        ),
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PatientNotesHistoryScreen(
                            patientId: widget.patientId,
                            patientName: widget.patientName,
                          ),
                        ),
                      );
                    },
                    child: Text(
                      'All Notes (${notes.length}) →',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: OV.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              if (notes.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'No nursing clinical notes recorded yet.',
                    style: GoogleFonts.inter(fontSize: 12, color: OV.onSurfaceVariant),
                  ),
                )
              else ...[
                if (submittedNotes.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: OV.primaryContainer.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: OV.primary.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.pending_actions, size: 16, color: OV.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${submittedNotes.length} note(s) awaiting attending review & sign-off.',
                            style: GoogleFonts.manrope(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: OV.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                if (latestNote != null) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'By ${latestNote.authorName} (${latestNote.authorRole}) • ${latestNote.createdAt != null ? DateFormat('MMM d, h:mm a').format(latestNote.createdAt!) : "Recently"}',
                        style: GoogleFonts.inter(fontSize: 11, color: OV.onSurfaceVariant),
                      ),
                      _buildMiniBadge(latestNote.status),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (latestNote.clinicalSummary.isNotEmpty)
                    Text(
                      latestNote.clinicalSummary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontSize: 13, color: OV.onSurface, height: 1.3),
                    ),
                  const SizedBox(height: 10),

                  if (latestNote.status == ClinicalNoteStatus.submitted)
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton.icon(
                        onPressed: _isSigning ? null : () => _showSignOffDialog(latestNote),
                        icon: _isSigning
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.check_circle_outline, size: 15),
                        label: Text(
                          _isSigning ? 'Signing Off...' : 'Review & Sign Off',
                          style: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildMiniBadge(ClinicalNoteStatus status) {
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
}

class _DoctorTreatmentPlanCard extends StatelessWidget {
  final String patientId;
  final String patientName;
  final String doctorId;
  final TreatmentTrackingService? treatmentService;

  const _DoctorTreatmentPlanCard({
    required this.patientId,
    required this.patientName,
    required this.doctorId,
    this.treatmentService,
  });

  TreatmentTrackingService get _service =>
      treatmentService ?? TreatmentTrackingService.instance;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<TreatmentPlanModel>>(
      stream: _service.watchPatientTreatmentPlans(patientId),
      builder: (context, snapshot) {
        final plans = snapshot.data ?? [];
        final activePlan = plans.where((p) => p.isActive).isNotEmpty
            ? plans.firstWhere((p) => p.isActive)
            : (plans.isNotEmpty ? plans.first : null);

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: OV.outlineVariant.withValues(alpha: 0.5)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: OV.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.assignment_turned_in_rounded,
                          size: 18,
                          color: OV.primary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Treatment Plan & Supervision',
                        style: GoogleFonts.manrope(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: OV.onSurface,
                        ),
                      ),
                    ],
                  ),
                  TextButton(
                    key: const Key('viewAllPlansButton'),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DoctorTreatmentPlanScreen(
                            patientId: patientId,
                            patientName: patientName,
                            doctorId: doctorId,
                            service: _service,
                          ),
                        ),
                      );
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      'Manage (${plans.length})',
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: OV.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              if (activePlan == null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: OV.surfaceContainer.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, size: 18, color: OV.outline),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'No treatment plans established yet.',
                          style: GoogleFonts.inter(fontSize: 12, color: OV.onSurfaceVariant),
                        ),
                      ),
                      OutlinedButton(
                        key: const Key('establishPlanButton'),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CreateTreatmentPlanScreen(
                                patientId: patientId,
                                patientName: patientName,
                                doctorId: doctorId,
                                service: _service,
                              ),
                            ),
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          side: const BorderSide(color: OV.primary),
                        ),
                        child: Text(
                          'Create Plan',
                          style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w700, color: OV.primary),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        activePlan.title,
                        style: GoogleFonts.manrope(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: OV.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: activePlan.isActive
                            ? OV.primaryContainer
                            : activePlan.isCompleted
                                ? OV.tertiaryContainer
                                : Colors.amber.shade100,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        activePlan.status.toUpperCase(),
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: activePlan.isActive
                              ? OV.primary
                              : activePlan.isCompleted
                                  ? OV.tertiary
                                  : Colors.amber.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Bedside Tasks Completed: ${activePlan.completedTasks}/${activePlan.totalTasks}',
                      style: GoogleFonts.inter(fontSize: 11, color: OV.onSurfaceVariant),
                    ),
                    Text(
                      '${activePlan.overallProgressPercentage}%',
                      style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w700, color: OV.primary),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: activePlan.totalTasks > 0
                        ? (activePlan.completedTasks / activePlan.totalTasks).clamp(0.0, 1.0)
                        : 0.0,
                    minHeight: 6,
                    backgroundColor: OV.surfaceContainer,
                    valueColor: const AlwaysStoppedAnimation<Color>(OV.primary),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}