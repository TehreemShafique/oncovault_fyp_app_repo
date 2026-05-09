// lib/screens/doctor/add_diagnosis_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../models/doctor_model.dart';
import '../../services/doctor_service.dart';
import 'doctor_widgets.dart';
import 'voice_notes_screen.dart';

class AddDiagnosisScreen extends StatefulWidget {
  final String patientId, patientName, doctorId, doctorName;
  const AddDiagnosisScreen({super.key, required this.patientId,
    required this.patientName, required this.doctorId, required this.doctorName});
  @override
  State<AddDiagnosisScreen> createState() => _AddDiagnosisScreenState();
}

class _AddDiagnosisScreenState extends State<AddDiagnosisScreen> {
  final _service = DoctorService();
  final _formKey = GlobalKey<FormState>();

  final _diagnosisTitleCtrl = TextEditingController();
  final _diagnosisDetailCtrl = TextEditingController();
  final _prescriptionCtrl    = TextEditingController();
  final _clinicalNotesCtrl   = TextEditingController();
  final _recommendCtrl       = TextEditingController();
  final _cancerTypeCtrl      = TextEditingController();

  String _selectedStatus = 'stable';
  String _selectedStage  = '';
  bool _isLoading = false;

  final _statuses = ['stable', 'monitoring', 'follow-up', 'critical'];
  final _stages   = ['', 'Stage I', 'Stage II', 'Stage III', 'Stage IV', 'Remission', 'Post-Op'];

  @override
  void dispose() {
    _diagnosisTitleCtrl.dispose(); _diagnosisDetailCtrl.dispose();
    _prescriptionCtrl.dispose(); _clinicalNotesCtrl.dispose();
    _recommendCtrl.dispose(); _cancerTypeCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final entry = DiagnosisEntry(
        id: '',
        patientId:        widget.patientId,
        patientName:      widget.patientName,
        doctorId:         widget.doctorId,
        doctorName:       widget.doctorName,
        diagnosisTitle:   _diagnosisTitleCtrl.text.trim(),
        diagnosisDetails: _diagnosisDetailCtrl.text.trim(),
        prescription:     _prescriptionCtrl.text.trim(),
        clinicalNotes:    _clinicalNotesCtrl.text.trim(),
        recommendations:  _recommendCtrl.text.trim(),
        cancerType:       _cancerTypeCtrl.text.trim(),
        stage:            _selectedStage,
        status:           _selectedStatus,
        blockchainVerified: true,
        createdAt:        DateTime.now(),
      );
      await _service.addDiagnosis(entry);
      if (!mounted) return;
      _showSuccess();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e', style: GoogleFonts.inter(fontSize: 13)),
          backgroundColor: OV.error, behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSuccess() {
    showModalBottomSheet(context: context, isDismissible: false,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (_) => Padding(padding: const EdgeInsets.all(28), child: Column(
            mainAxisSize: MainAxisSize.min, children: [
          Container(width: 64, height: 64,
              decoration: BoxDecoration(color: OV.tertiaryContainer, shape: BoxShape.circle),
              child: const Icon(Icons.check_circle_outline_rounded, color: OV.tertiary, size: 34)),
          const SizedBox(height: 16),
          Text('Record Saved!', style: GoogleFonts.manrope(fontSize: 20, fontWeight: FontWeight.w700, color: OV.onSurface)),
          const SizedBox(height: 8),
          Text('The diagnosis has been added to ${widget.patientName}\'s medical record and verified on the blockchain.',
              style: GoogleFonts.inter(fontSize: 13, color: OV.onSurfaceVariant, height: 1.5), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          const BlockchainBadge(),
          const SizedBox(height: 24),
          SizedBox(width: double.infinity, height: 50,
              child: ElevatedButton(
                  onPressed: () { Navigator.pop(context); Navigator.pop(context); },
                  style: ElevatedButton.styleFrom(backgroundColor: OV.slateDark, foregroundColor: Colors.white,
                      elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                  child: Text('Back to Patient', style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w600)))),
        ])));
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
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Add Diagnosis Note', style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700, color: OV.onSurface)),
                  Text('Patient: ${widget.patientName}', style: GoogleFonts.inter(fontSize: 11, color: OV.onSurfaceVariant)),
                ])),
                // Voice notes shortcut
                GestureDetector(
                    onTap: () => Navigator.push(context, dSlide(VoiceNotesScreen(
                        patientId: widget.patientId, patientName: widget.patientName,
                        onNoteAdded: (text) => setState(() =>
                        _clinicalNotesCtrl.text += ((_clinicalNotesCtrl.text.isEmpty ? '' : '\n') + text))))),
                    child: Container(padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: OV.primaryContainer, borderRadius: BorderRadius.circular(10)),
                        child: Icon(Icons.mic_rounded, size: 18, color: OV.primary))),
              ])),

          Expanded(child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(key: _formKey, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                // ── Diagnosis ─────────────────────────────────────────
                _SectionLabel('Diagnosis'),
                const SizedBox(height: 8),
                _FormField(ctrl: _diagnosisTitleCtrl, hint: 'e.g. Stage III Adenocarcinoma',
                    label: 'Diagnosis Title', icon: Icons.medical_services_outlined,
                    validator: (v) => v == null || v.isEmpty ? 'Required' : null),
                const SizedBox(height: 10),
                _FormField(ctrl: _diagnosisDetailCtrl, hint: 'Describe the diagnosis in detail...',
                    label: 'Diagnosis Details', icon: Icons.notes_rounded, maxLines: 3),
                const SizedBox(height: 10),
                _FormField(ctrl: _cancerTypeCtrl, hint: 'e.g. Adenocarcinoma, Lymphoma',
                    label: 'Cancer Type (if applicable)', icon: Icons.category_outlined),
                const SizedBox(height: 14),

                // ── Stage & Status row ────────────────────────────────
                Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _SectionLabel('Stage'),
                    const SizedBox(height: 8),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: OV.outlineVariant.withOpacity(0.6))),
                        child: DropdownButtonHideUnderline(child: DropdownButton<String>(
                            value: _selectedStage,
                            isExpanded: true,
                            style: GoogleFonts.inter(fontSize: 13, color: OV.onSurface),
                            items: _stages.map((s) => DropdownMenuItem(
                                value: s, child: Text(s.isEmpty ? 'Select stage' : s,
                                style: GoogleFonts.inter(fontSize: 13,
                                    color: s.isEmpty ? OV.outline : OV.onSurface)))).toList(),
                            onChanged: (v) => setState(() => _selectedStage = v ?? '')))),
                  ])),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _SectionLabel('Status'),
                    const SizedBox(height: 8),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: OV.outlineVariant.withOpacity(0.6))),
                        child: DropdownButtonHideUnderline(child: DropdownButton<String>(
                            value: _selectedStatus,
                            isExpanded: true,
                            style: GoogleFonts.inter(fontSize: 13, color: OV.onSurface),
                            items: _statuses.map((s) => DropdownMenuItem(
                                value: s, child: Text(s[0].toUpperCase() + s.substring(1),
                                style: GoogleFonts.inter(fontSize: 13, color: OV.onSurface)))).toList(),
                            onChanged: (v) => setState(() => _selectedStatus = v ?? 'stable')))),
                  ])),
                ]),

                const SizedBox(height: 20),

                // ── Prescription ──────────────────────────────────────
                _SectionLabel('Prescription'),
                const SizedBox(height: 8),
                _FormField(ctrl: _prescriptionCtrl,
                    hint: 'e.g. Gemcitabine 1000mg/m² IV + Nab-paclitaxel 125mg/m², Day 1, 8, 15 of 28-day cycle',
                    label: 'Prescription Details', icon: Icons.medication_outlined, maxLines: 3),

                const SizedBox(height: 20),

                // ── Clinical Notes ────────────────────────────────────
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  _SectionLabel('Clinical Notes'),
                  GestureDetector(
                      onTap: () => Navigator.push(context, dSlide(VoiceNotesScreen(
                          patientId: widget.patientId, patientName: widget.patientName,
                          onNoteAdded: (text) => setState(() =>
                          _clinicalNotesCtrl.text += ((_clinicalNotesCtrl.text.isEmpty ? '' : '\n') + text))))),
                      child: Row(children: [
                        Icon(Icons.mic_rounded, size: 14, color: OV.primary),
                        const SizedBox(width: 4),
                        Text('Voice Input', style: GoogleFonts.inter(
                            fontSize: 12, fontWeight: FontWeight.w600, color: OV.primary)),
                      ])),
                ]),
                const SizedBox(height: 8),
                _FormField(ctrl: _clinicalNotesCtrl, hint: 'Clinical observations and notes...',
                    label: 'Clinical Notes', icon: Icons.edit_note_rounded, maxLines: 4),

                const SizedBox(height: 20),

                // ── Recommendations ───────────────────────────────────
                _SectionLabel('Clinical Recommendations'),
                const SizedBox(height: 8),
                _FormField(ctrl: _recommendCtrl, hint: 'Next steps, follow-up tests, referrals...',
                    label: 'Recommendations', icon: Icons.lightbulb_outline_rounded, maxLines: 3),

                const SizedBox(height: 20),

                // ── Upload Reports placeholder ────────────────────────
                GestureDetector(onTap: () {},
                    child: Container(padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: OV.outlineVariant.withOpacity(0.5),
                                style: BorderStyle.solid)),
                        child: Row(children: [
                          Container(width: 40, height: 40,
                              decoration: BoxDecoration(color: OV.primaryContainer, borderRadius: BorderRadius.circular(10)),
                              child: Icon(Icons.upload_file_rounded, color: OV.primary, size: 20)),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Upload Lab Results / Reports', style: GoogleFonts.manrope(
                                fontSize: 13, fontWeight: FontWeight.w700, color: OV.onSurface)),
                            Text('PDF, images, DICOM files supported', style: GoogleFonts.inter(
                                fontSize: 11, color: OV.onSurfaceVariant)),
                          ])),
                          Text('Browse', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: OV.primary)),
                        ]))),

                const SizedBox(height: 16),

                // ── Blockchain notice ─────────────────────────────────
                Container(padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: OV.tertiaryContainer.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: OV.tertiary.withOpacity(0.2))),
                    child: Row(children: [
                      Icon(Icons.verified_rounded, size: 16, color: OV.tertiary),
                      const SizedBox(width: 8),
                      Expanded(child: Text(
                          'This record will be cryptographically signed and stored on the blockchain for immutable verification.',
                          style: GoogleFonts.inter(fontSize: 11, color: OV.tertiary, height: 1.4))),
                    ])),

                const SizedBox(height: 24),
              ])))),

          // ── Save Button ───────────────────────────────────────────
          Container(padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              decoration: BoxDecoration(color: Colors.white,
                  border: Border(top: BorderSide(color: OV.outlineVariant.withOpacity(0.4)))),
              child: SizedBox(width: double.infinity, height: 52,
                  child: ElevatedButton(
                      onPressed: _isLoading ? null : _save,
                      style: ElevatedButton.styleFrom(backgroundColor: OV.slateDark, foregroundColor: Colors.white,
                          elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                      child: _isLoading
                          ? const SizedBox(width: 22, height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Icon(Icons.save_rounded, size: 18),
                        const SizedBox(width: 8),
                        Text('Save Medical Record', style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w600)),
                      ])))),
        ])));
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text, style: GoogleFonts.manrope(
      fontSize: 14, fontWeight: FontWeight.w700, color: OV.onSurface));
}

class _FormField extends StatelessWidget {
  final TextEditingController ctrl;
  final String hint, label; final IconData icon;
  final int maxLines; final String? Function(String?)? validator;
  const _FormField({required this.ctrl, required this.hint, required this.label,
    required this.icon, this.maxLines = 1, this.validator});

  @override
  Widget build(BuildContext context) => TextFormField(
      controller: ctrl, maxLines: maxLines, validator: validator,
      style: GoogleFonts.inter(fontSize: 14, color: OV.onSurface),
      decoration: InputDecoration(
          hintText: hint, labelText: label,
          hintStyle: GoogleFonts.inter(fontSize: 13, color: OV.outline),
          labelStyle: GoogleFonts.inter(fontSize: 12, color: OV.outline),
          prefixIcon: Padding(
              padding: EdgeInsets.only(top: maxLines > 1 ? 8.0 : 0.0),
              child: Align(alignment: Alignment.topLeft,
                  child: Icon(icon, color: OV.outline, size: 18))),
          prefixIconConstraints: const BoxConstraints(minWidth: 44),
          filled: true, fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: OV.outlineVariant.withOpacity(0.6))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: OV.outlineVariant.withOpacity(0.6))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: OV.primary, width: 1.5)),
          errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: OV.error)),
          contentPadding: EdgeInsets.symmetric(
              vertical: maxLines > 1 ? 14.0 : 0.0, horizontal: 4)));
}