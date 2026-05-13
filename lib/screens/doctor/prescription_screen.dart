// lib/screens/doctor/prescription_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../models/patient_profile_model.dart';
import '../../models/medical_record_model.dart';
import '../../services/doctor_service.dart';
import 'doctor_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Prescription model
// ─────────────────────────────────────────────────────────────────────────────
class PrescriptionModel {
  final String id;
  final String patientId;
  final String patientName;
  final String doctorId;
  final String doctorName;
  final String doctorSpecialty;
  final List<PrescriptionDrug> drugs;
  final String additionalNotes;
  final String followUpInstructions;
  final DateTime issuedAt;
  final DateTime validUntil;
  final bool isSigned;

  PrescriptionModel({
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.doctorId,
    required this.doctorName,
    required this.doctorSpecialty,
    required this.drugs,
    this.additionalNotes = '',
    this.followUpInstructions = '',
    required this.issuedAt,
    required this.validUntil,
    this.isSigned = true,
  });

  Map<String, dynamic> toMap() => {
    'id':                   id,
    'patientId':            patientId,
    'patientName':          patientName,
    'doctorId':             doctorId,
    'doctorName':           doctorName,
    'doctorSpecialty':      doctorSpecialty,
    'drugs':                drugs.map((d) => d.toMap()).toList(),
    'additionalNotes':      additionalNotes,
    'followUpInstructions': followUpInstructions,
    'issuedAt':             Timestamp.fromDate(issuedAt),
    'validUntil':           Timestamp.fromDate(validUntil),
    'isSigned':             isSigned,
  };
}

class PrescriptionDrug {
  String name;
  String dosage;
  String frequency;
  String duration;
  String route;
  String instructions;

  PrescriptionDrug({
    this.name = '',
    this.dosage = '',
    this.frequency = '',
    this.duration = '',
    this.route = 'Oral',
    this.instructions = '',
  });

  Map<String, dynamic> toMap() => {
    'name': name, 'dosage': dosage, 'frequency': frequency,
    'duration': duration, 'route': route, 'instructions': instructions,
  };

  bool get isValid => name.trim().isNotEmpty && dosage.trim().isNotEmpty;
}

// ─── Small helpers ────────────────────────────────────────────────────────────
class _SimpleField extends StatefulWidget {
  final String label, hint, value;
  final ValueChanged<String> onChange;

  const _SimpleField({
    required this.label,
    required this.hint,
    required this.value,
    required this.onChange,
  });

  @override
  State<_SimpleField> createState() => _SimpleFieldState();
}

class _SimpleFieldState extends State<_SimpleField> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value);
    // Place cursor at the end on first build
    _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
  }

  @override
  void didUpdateWidget(_SimpleField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only sync when the value was changed externally (not by the user typing)
    if (widget.value != _ctrl.text) {
      _ctrl.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      onChanged: widget.onChange,
      style: GoogleFonts.inter(fontSize: 13, color: OV.onSurface),
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        labelStyle: GoogleFonts.inter(fontSize: 11, color: OV.outline),
        hintStyle: GoogleFonts.inter(fontSize: 12, color: OV.outline),
        filled: true,
        fillColor: OV.surfaceLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: OV.outlineVariant.withOpacity(0.6)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: OV.outlineVariant.withOpacity(0.6)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: OV.primary, width: 1.5),
        ),
        contentPadding:
        const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Prescription Screen
// ─────────────────────────────────────────────────────────────────────────────
class PrescriptionScreen extends StatefulWidget {
  final String doctorId;
  final String doctorName;
  final String doctorSpecialty;
  /// Pre-fill if opened from a patient's detail page
  final String? patientId;
  final String? patientName;

  const PrescriptionScreen({
    super.key,
    required this.doctorId,
    required this.doctorName,
    required this.doctorSpecialty,
    this.patientId,
    this.patientName,
  });

  @override
  State<PrescriptionScreen> createState() => _PrescriptionScreenState();
}

class _PrescriptionScreenState extends State<PrescriptionScreen> {
  final _db      = FirebaseFirestore.instance;
  final _service = DoctorService();

  // Patient selection
  String? _selectedPatientId;
  String? _selectedPatientName;
  List<PatientProfile> _patients = [];
  bool _loadingPatients = true;

  // Drugs list
  final List<PrescriptionDrug> _drugs = [PrescriptionDrug()];

  // Other fields
  final _notesCtrl   = TextEditingController();
  final _followUpCtrl = TextEditingController();
  int _validDays_ = 30;
  bool _isSaving = false;

  // Common drug suggestions
  final _drugSuggestions = [
    'Gemcitabine', 'Paclitaxel', 'Carboplatin', 'Cisplatin',
    'Ondansetron', 'Dexamethasone', 'Metoclopramide', 'Omeprazole',
    'Tamoxifen', 'Letrozole', 'Trastuzumab', 'Bevacizumab',
    'Metformin', 'Ibuprofen', 'Paracetamol', 'Amoxicillin',
  ];

  final _frequencies = [
    'Once daily', 'Twice daily', 'Three times daily', 'Four times daily',
    'Every 8 hours', 'Every 12 hours', 'Weekly', 'As needed (PRN)',
    'Before meals', 'After meals', 'At bedtime',
  ];

  final _routes = [
    'Oral', 'Intravenous (IV)', 'Intramuscular (IM)',
    'Subcutaneous', 'Topical', 'Inhalation', 'Sublingual',
  ];

  final _durations = [
    '3 days', '5 days', '7 days', '10 days', '14 days',
    '21 days', '1 month', '3 months', '6 months', 'Ongoing',
  ];

  @override
  void initState() {
    super.initState();
    // Pre-fill patient if provided
    if (widget.patientId != null) {
      _selectedPatientId   = widget.patientId;
      _selectedPatientName = widget.patientName;
    }
    _loadPatients();
  }

  Future<void> _loadPatients() async {
    _service.watchDoctorPatients(widget.doctorId).listen((list) {
      if (mounted) setState(() { _patients = list; _loadingPatients = false; });
    });
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    _followUpCtrl.dispose();
    super.dispose();
  }

  Future<void> _savePrescription() async {
    if (_selectedPatientId == null) {
      _snack('Please select a patient', OV.error); return;
    }
    final validDrugs = _drugs.where((d) => d.isValid).toList();
    if (validDrugs.isEmpty) {
      _snack('Add at least one medication with name and dosage', OV.error); return;
    }

    setState(() => _isSaving = true);
    try {
      final ref = _db.collection('prescriptions').doc();
      final now = DateTime.now();
      final prescription = PrescriptionModel(
        id:                   ref.id,
        patientId:            _selectedPatientId!,
        patientName:          _selectedPatientName ?? '',
        doctorId:             widget.doctorId,
        doctorName:           widget.doctorName,
        doctorSpecialty:      widget.doctorSpecialty,
        drugs:                validDrugs,
        additionalNotes:      _notesCtrl.text.trim(),
        followUpInstructions: _followUpCtrl.text.trim(),
        issuedAt:             now,
        validUntil:           now.add(Duration(days: _validDays_)),
      );

      final data = prescription.toMap();

      // Write to global /prescriptions
      await ref.set(data);

      // Write to patient's medicalRecords subcollection as a Prescription record
      final recRef = _db.collection('patients')
          .doc(_selectedPatientId!).collection('medicalRecords').doc();
      await recRef.set({
        'id':         recRef.id,
        'patientId':  _selectedPatientId,
        'title':      'Prescription — ${DateFormat('MMM d, yyyy').format(now)}',
        'type':       'prescription',
        'subtype':    'Digital Prescription',
        'facility':   'OncoVault Medical Center',
        'doctorName': widget.doctorName,
        'date':       Timestamp.fromDate(now),
        'fileUrl':    '',
        'fileType':   'prescription',
        'summary':    validDrugs.map((d) => '${d.name} ${d.dosage} — ${d.frequency}').join('; '),
        'uploadedAt': Timestamp.fromDate(now),
        'isArchived': false,
        'prescriptionData': data,
      });

      // Notify patient
      final notifRef = _db.collection('notifications')
          .doc(_selectedPatientId!).collection('items').doc();
      await notifRef.set({
        'id':          notifRef.id,
        'patientId':   _selectedPatientId,
        'title':       'New Prescription Issued',
        'body':        '${widget.doctorName} has issued a new prescription with ${validDrugs.length} medication(s).',
        'type':        'report',
        'isRead':      false,
        'createdAt':   Timestamp.fromDate(now),
        'referenceId': ref.id,
      });

      if (!mounted) return;
      _showSuccess(prescription);
    } catch (e) {
      if (!mounted) return;
      _snack('Failed to save: $e', OV.error);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSuccess(PrescriptionModel rx) {
    showModalBottomSheet(
        context: context, isDismissible: false,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (_) => Padding(padding: const EdgeInsets.all(28), child: Column(
            mainAxisSize: MainAxisSize.min, children: [
          Container(width: 64, height: 64,
              decoration: BoxDecoration(color: OV.tertiaryContainer, shape: BoxShape.circle),
              child: const Icon(Icons.medication_rounded, color: OV.tertiary, size: 32)),
          const SizedBox(height: 16),
          Text('Prescription Issued!', style: GoogleFonts.manrope(
              fontSize: 20, fontWeight: FontWeight.w700, color: OV.onSurface)),
          const SizedBox(height: 8),
          Text('The prescription for ${rx.patientName} has been saved to their medical record and they have been notified.',
              style: GoogleFonts.inter(fontSize: 13, color: OV.onSurfaceVariant, height: 1.5),
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Container(padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: OV.surfaceLow, borderRadius: BorderRadius.circular(12)),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _PrescStat('${rx.drugs.length}', 'Medications'),
                Container(width: 1, height: 30, color: OV.outlineVariant),
                _PrescStat('$_validDays_ d', 'Valid for'),
                Container(width: 1, height: 30, color: OV.outlineVariant),
                _PrescStat('✓', 'Signed'),
              ])),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(child: OutlinedButton(
                onPressed: () {
                  Navigator.pop(context);
                  // Reset for new prescription
                  setState(() {
                    _drugs.clear(); _drugs.add(PrescriptionDrug());
                    _notesCtrl.clear(); _followUpCtrl.clear();
                    if (widget.patientId == null) {
                      _selectedPatientId = null; _selectedPatientName = null;
                    }
                  });
                },
                style: OutlinedButton.styleFrom(foregroundColor: OV.onSurface,
                    side: BorderSide(color: OV.outlineVariant),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                child: Text('New Prescription',
                    style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700)))),
            const SizedBox(width: 12),
            Expanded(child: ElevatedButton(
                onPressed: () { Navigator.pop(context); Navigator.pop(context); },
                style: ElevatedButton.styleFrom(backgroundColor: OV.slateDark,
                    foregroundColor: Colors.white, elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                child: Text('Done',
                    style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700)))),
          ]),
        ])));
  }



  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg, style: GoogleFonts.inter(fontSize: 13)),
        backgroundColor: color, behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: OV.background,
        body: SafeArea(child: Column(children: [
          // ── App Bar ──────────────────────────────────────────────
          DoctorAppBar(title: 'Digital Prescription', showBack: true,
              actions: [
                Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: OV.tertiaryContainer, borderRadius: BorderRadius.circular(100)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.verified_rounded, size: 12, color: OV.tertiary),
                      const SizedBox(width: 4),
                      Text('Digitally Signed', style: GoogleFonts.inter(
                          fontSize: 10, fontWeight: FontWeight.w700, color: OV.tertiary)),
                    ])),
              ]),

          Expanded(child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                // ── Doctor Header ─────────────────────────────────────
                DCard(child: Row(children: [
                  Container(width: 48, height: 48,
                      decoration: BoxDecoration(color: OV.primaryContainer, borderRadius: BorderRadius.circular(14)),
                      child: Center(child: Text(
                          widget.doctorName.isNotEmpty ? widget.doctorName[0].toUpperCase() : 'D',
                          style: GoogleFonts.manrope(fontSize: 20, fontWeight: FontWeight.w700, color: OV.primary)))),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(widget.doctorName, style: GoogleFonts.manrope(
                        fontSize: 15, fontWeight: FontWeight.w700, color: OV.onSurface)),
                    Text(widget.doctorSpecialty.isNotEmpty ? widget.doctorSpecialty : 'Doctor',
                        style: GoogleFonts.inter(fontSize: 12, color: OV.onSurfaceVariant)),
                  ])),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('DATE ISSUED', style: GoogleFonts.inter(
                        fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: OV.outline)),
                    Text(DateFormat('MMM d, yyyy').format(DateTime.now()),
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: OV.onSurface)),
                  ]),
                ])),

                const SizedBox(height: 16),

                // ── Patient Selection ─────────────────────────────────
                _Label('Patient'),
                const SizedBox(height: 8),
                widget.patientId != null
                    ? _PatientTag(name: widget.patientName ?? '', onClear: null)
                    : _loadingPatients
                    ? const Center(child: SizedBox(height: 30, width: 30,
                    child: CircularProgressIndicator(strokeWidth: 2, color: OV.primary)))
                    : GestureDetector(
                    onTap: () => _showPatientPicker(),
                    child: _selectedPatientId != null
                        ? _PatientTag(
                        name: _selectedPatientName ?? '',
                        onClear: () => setState(() {
                          _selectedPatientId = null; _selectedPatientName = null; }))
                        : Container(padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: OV.outlineVariant.withOpacity(0.6))),
                        child: Row(children: [
                          Icon(Icons.person_search_rounded, color: OV.outline, size: 20),
                          const SizedBox(width: 10),
                          Text('Select patient...', style: GoogleFonts.inter(
                              fontSize: 14, color: OV.outline)),
                          const Spacer(),
                          Icon(Icons.chevron_right_rounded, color: OV.outline),
                        ]))),

                const SizedBox(height: 20),

                // ── Medications ───────────────────────────────────────
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  _Label('Medications'),
                  GestureDetector(
                      onTap: () => setState(() => _drugs.add(PrescriptionDrug())),
                      child: Row(children: [
                        Icon(Icons.add_circle_outline_rounded, size: 16, color: OV.primary),
                        const SizedBox(width: 4),
                        Text('Add Drug', style: GoogleFonts.inter(
                            fontSize: 12, fontWeight: FontWeight.w700, color: OV.primary)),
                      ])),
                ]),
                const SizedBox(height: 10),

                ..._drugs.asMap().entries.map((e) => _DrugCard(
                  index: e.key,
                  drug: e.value,
                  canRemove: _drugs.length > 1,
                  drugSuggestions: _drugSuggestions,
                  frequencies: _frequencies,
                  routes: _routes,
                  durations: _durations,
                  onRemove: () => setState(() => _drugs.removeAt(e.key)),
                  onChanged: () => setState(() {}),
                )),

                const SizedBox(height: 20),

                // ── Validity ──────────────────────────────────────────
                _Label('Prescription Validity'),
                const SizedBox(height: 10),
                DCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Valid for: $_validDays_ days  '
                      '(until ${DateFormat('MMM d, yyyy').format(DateTime.now().add(Duration(days: _validDays_)))})',
                      style: GoogleFonts.inter(fontSize: 13, color: OV.onSurface, fontWeight: FontWeight.w500)),
                  Slider(
                      value: _validDays_.toDouble(),
                      min: 7, max: 180, divisions: 17,
                      activeColor: OV.primary,
                      onChanged: (v) => setState(() => _validDays_ = v.round())),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('7 days', style: GoogleFonts.inter(fontSize: 10, color: OV.outline)),
                    Text('180 days', style: GoogleFonts.inter(fontSize: 10, color: OV.outline)),
                  ]),
                ])),

                const SizedBox(height: 20),

                // ── Additional Notes ──────────────────────────────────
                _Label('Additional Notes (Optional)'),
                const SizedBox(height: 8),
                _TextArea(ctrl: _notesCtrl,
                    hint: 'e.g. Take with food, avoid alcohol, monitor blood pressure...'),

                const SizedBox(height: 16),

                _Label('Follow-Up Instructions (Optional)'),
                const SizedBox(height: 8),
                _TextArea(ctrl: _followUpCtrl,
                    hint: 'e.g. Return in 2 weeks for blood test. Stop medication if rash develops.'),

                const SizedBox(height: 16),

                // ── Digital signature notice ──────────────────────────
                Container(padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: OV.tertiaryContainer.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: OV.tertiary.withOpacity(0.2))),
                    child: Row(children: [
                      Icon(Icons.verified_user_outlined, size: 16, color: OV.tertiary),
                      const SizedBox(width: 8),
                      Expanded(child: Text(
                          'This prescription is digitally signed by ${widget.doctorName} and stored securely in the patient\'s vault.',
                          style: GoogleFonts.inter(fontSize: 11, color: OV.tertiary, height: 1.4))),
                    ])),

                const SizedBox(height: 24),
              ]))),

          // ── Issue Button ──────────────────────────────────────────
          Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              decoration: BoxDecoration(color: Colors.white,
                  border: Border(top: BorderSide(color: OV.outlineVariant.withOpacity(0.4)))),
              child: SizedBox(width: double.infinity, height: 52,
                  child: ElevatedButton.icon(
                      onPressed: _isSaving ? null : _savePrescription,
                      icon: _isSaving
                          ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.medication_rounded, size: 18),
                      label: Text('Issue Prescription',
                          style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700)),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: OV.slateDark, foregroundColor: Colors.white,
                          elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)))))),
        ])));
  }

  void _showPatientPicker() {
    showModalBottomSheet(context: context, backgroundColor: Colors.white,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (_) {
          String q = '';
          return StatefulBuilder(builder: (ctx, setM) => DraggableScrollableSheet(
              initialChildSize: 0.6, maxChildSize: 0.9, minChildSize: 0.4, expand: false,
              builder: (_, sc) => Column(children: [
                const SizedBox(height: 12),
                Container(width: 40, height: 4,
                    decoration: BoxDecoration(color: OV.outlineVariant, borderRadius: BorderRadius.circular(2))),
                Padding(padding: const EdgeInsets.all(16),
                    child: TextField(
                        autofocus: true,
                        onChanged: (v) => setM(() => q = v),
                        style: GoogleFonts.inter(fontSize: 14, color: OV.onSurface),
                        decoration: InputDecoration(
                            hintText: 'Search patients...',
                            hintStyle: GoogleFonts.inter(fontSize: 14, color: OV.outline),
                            prefixIcon: Icon(Icons.search_rounded, color: OV.outline, size: 18),
                            filled: true, fillColor: OV.surfaceLow,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                            contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4)))),
                Expanded(child: ListView(controller: sc, children:
                _patients.where((p) =>
                q.isEmpty || p.name.toLowerCase().contains(q.toLowerCase()) ||
                    p.medicalId.toLowerCase().contains(q.toLowerCase()))
                    .map((p) => ListTile(
                    leading: CircleAvatar(backgroundColor: OV.primaryContainer,
                        child: Text(p.name.isNotEmpty ? p.name[0].toUpperCase() : 'P',
                            style: GoogleFonts.manrope(fontWeight: FontWeight.w700, color: OV.primary))),
                    title: Text(p.name, style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600)),
                    subtitle: Text(p.medicalId, style: GoogleFonts.inter(fontSize: 11, color: OV.onSurfaceVariant)),
                    onTap: () {
                      setState(() { _selectedPatientId = p.uid; _selectedPatientName = p.name; });
                      Navigator.pop(ctx);
                    })).toList())),
              ])));
        });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Drug entry card
// ─────────────────────────────────────────────────────────────────────────────
class _DrugCard extends StatelessWidget {
  final int index;
  final PrescriptionDrug drug;
  final bool canRemove;
  final List<String> drugSuggestions, frequencies, routes, durations;
  final VoidCallback onRemove, onChanged;

  const _DrugCard({
    required this.index, required this.drug, required this.canRemove,
    required this.drugSuggestions, required this.frequencies,
    required this.routes, required this.durations,
    required this.onRemove, required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
            border: Border.all(color: OV.outlineVariant.withOpacity(0.5)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))]),
        child: Column(children: [
          // Card header
          Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                  color: OV.primaryContainer.withOpacity(0.4),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16))),
              child: Row(children: [
                Icon(Icons.medication_outlined, size: 16, color: OV.primary),
                const SizedBox(width: 8),
                Text('Medication ${index + 1}', style: GoogleFonts.manrope(
                    fontSize: 13, fontWeight: FontWeight.w700, color: OV.primary)),
                const Spacer(),
                if (canRemove) GestureDetector(onTap: onRemove,
                    child: Icon(Icons.remove_circle_outline_rounded, size: 18, color: OV.error)),
              ])),
          Padding(padding: const EdgeInsets.all(14), child: Column(children: [
            // Drug name with suggestions
            Autocomplete<String>(
                optionsBuilder: (v) => v.text.isEmpty ? []
                    : drugSuggestions.where((s) => s.toLowerCase().contains(v.text.toLowerCase())),
                onSelected: (s) { drug.name = s; onChanged(); },
                fieldViewBuilder: (ctx, ctrl, fn, _) {
                  if (drug.name.isNotEmpty && ctrl.text.isEmpty) ctrl.text = drug.name;
                  return TextField(
                      controller: ctrl, focusNode: fn,
                      onChanged: (v) { drug.name = v; onChanged(); },
                      style: GoogleFonts.inter(fontSize: 14, color: OV.onSurface),
                      decoration: _dec('Drug Name *', Icons.medication_outlined));
                }),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _SimpleField(label: 'Dosage *', hint: 'e.g. 500mg',
                  value: drug.dosage, onChange: (v) { drug.dosage = v; onChanged(); })),
              const SizedBox(width: 10),
              Expanded(child: _Dropdown(label: 'Route',
                  value: drug.route.isNotEmpty ? drug.route : 'Oral',
                  items: routes,
                  onChanged: (v) { drug.route = v ?? 'Oral'; onChanged(); })),
            ]),
            const SizedBox(height: 10),
            _Dropdown(label: 'Frequency',
                value: drug.frequency.isNotEmpty ? drug.frequency : null,
                hint: 'Select frequency',
                items: frequencies,
                onChanged: (v) { drug.frequency = v ?? ''; onChanged(); }),
            const SizedBox(height: 10),
            _Dropdown(label: 'Duration',
                value: drug.duration.isNotEmpty ? drug.duration : null,
                hint: 'Select duration',
                items: durations,
                onChanged: (v) { drug.duration = v ?? ''; onChanged(); }),
            const SizedBox(height: 10),
            _SimpleField(label: 'Special Instructions', hint: 'e.g. Take with food',
                value: drug.instructions, onChange: (v) { drug.instructions = v; onChanged(); }),
          ])),
        ]));
  }

  InputDecoration _dec(String label, IconData icon) => InputDecoration(
      labelText: label, labelStyle: GoogleFonts.inter(fontSize: 12, color: OV.outline),
      prefixIcon: Icon(icon, color: OV.outline, size: 16),
      filled: true, fillColor: OV.surfaceLow,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: OV.outlineVariant.withOpacity(0.6))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: OV.outlineVariant.withOpacity(0.6))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: OV.primary, width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4));
}

class _Dropdown extends StatelessWidget {
  final String label; final String? value, hint;
  final List<String> items; final ValueChanged<String?> onChanged;
  const _Dropdown({required this.label, required this.items,
    required this.onChanged, this.value, this.hint});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: OV.outline)),
    const SizedBox(height: 4),
    Container(padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(color: OV.surfaceLow, borderRadius: BorderRadius.circular(10),
            border: Border.all(color: OV.outlineVariant.withOpacity(0.6))),
        child: DropdownButtonHideUnderline(child: DropdownButton<String>(
            value: value, hint: Text(hint ?? label, style: GoogleFonts.inter(fontSize: 12, color: OV.outline)),
            isExpanded: true,
            style: GoogleFonts.inter(fontSize: 13, color: OV.onSurface),
            items: items.map((i) => DropdownMenuItem(value: i,
                child: Text(i, style: GoogleFonts.inter(fontSize: 13, color: OV.onSurface)))).toList(),
            onChanged: onChanged))),
  ]);
}

class _TextArea extends StatelessWidget {
  final TextEditingController ctrl; final String hint;
  const _TextArea({required this.ctrl, required this.hint});
  @override
  Widget build(BuildContext context) => TextField(
      controller: ctrl, maxLines: 3,
      style: GoogleFonts.inter(fontSize: 14, color: OV.onSurface),
      decoration: InputDecoration(hintText: hint,
          hintStyle: GoogleFonts.inter(fontSize: 13, color: OV.outline),
          filled: true, fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: OV.outlineVariant.withOpacity(0.6))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: OV.outlineVariant.withOpacity(0.6))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: OV.primary, width: 1.5)),
          contentPadding: const EdgeInsets.all(14)));
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(text, style: GoogleFonts.manrope(
      fontSize: 14, fontWeight: FontWeight.w700, color: OV.onSurface));
}

class _PatientTag extends StatelessWidget {
  final String name; final VoidCallback? onClear;
  const _PatientTag({required this.name, required this.onClear});
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: OV.primaryContainer.withOpacity(0.4),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: OV.primary.withOpacity(0.3))),
      child: Row(children: [
        Container(width: 32, height: 32, decoration: BoxDecoration(
            color: OV.primary, borderRadius: BorderRadius.circular(8)),
            child: Center(child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'P',
                style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)))),
        const SizedBox(width: 10),
        Expanded(child: Text(name, style: GoogleFonts.manrope(
            fontSize: 14, fontWeight: FontWeight.w700, color: OV.primary))),
        if (onClear != null) GestureDetector(onTap: onClear,
            child: Icon(Icons.close_rounded, color: OV.primary, size: 18)),
      ]));
}

class _PrescStat extends StatelessWidget {
  final String value, label;
  const _PrescStat(this.value, this.label);
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
    Text(value, style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w800, color: OV.primary)),
    Text(label, style: GoogleFonts.inter(fontSize: 10, color: OV.onSurfaceVariant)),
  ]);
}