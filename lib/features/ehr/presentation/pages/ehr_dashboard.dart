// lib/features/ehr/presentation/pages/ehr_dashboard.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'dart:io';

import '../../../../models/medical_record_model.dart';
import '../../../../models/patient_profile_model.dart';
import '../../../../features/ehr/data/repositories/ehr_repository_impl.dart';
import '../../../../services/doctor_service.dart';
import '../../../../theme/app_theme.dart';
import '../widgets/integrity_status_badge.dart';
import '../widgets/voice_input_placeholder.dart';

class EhrDashboard extends StatefulWidget {
  final String  patientId;
  final String? doctorId;

  const EhrDashboard({
    super.key,
    required this.patientId,
    this.doctorId,
  });

  @override
  State<EhrDashboard> createState() => _EhrDashboardState();
}

class _EhrDashboardState extends State<EhrDashboard> {
  final _repo    = EhrRepositoryImpl.instance;
  final _service = DoctorService();

  PatientProfile?          _profile;
  List<MedicalRecordModel> _records    = [];
  Map<String, dynamic>     _vitals     = {};
  bool                     _loading    = true;
  bool                     _uploading  = false;
  bool                     _hasConsent = false;
  String?                  _error;

  bool get _isDoctor => widget.doctorId != null;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() { _loading = true; _error = null; });
    try {
      // Check consent first if doctor
      if (_isDoctor) {
        _hasConsent = await _service.hasConsent(
            widget.doctorId!, widget.patientId);
      }

      final profile = await _repo.fetchPatientProfile(widget.patientId);
      final records = await _repo.fetchRecords(widget.patientId);
      final vitals  = await _service.fetchEhrVitals(widget.patientId);

      setState(() {
        _profile    = profile;
        _records    = records;
        _vitals     = vitals;
        _loading    = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  // ── Upload CBC Report (doctor only) ──────────────────────────
  Future<void> _uploadReport() async {
    if (!_isDoctor || !_hasConsent) return;

    final result = await FilePicker.platform.pickFiles(
      type             : FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
    );
    if (result == null || result.files.single.path == null) return;

    final file     = File(result.files.single.path!);
    final ext      = result.files.single.name.split('.').last.toLowerCase();
    final fileType = ext == 'pdf' ? 'pdf' : 'image';
    final title    = await _showTitleDialog(result.files.single.name);
    if (title == null || title.trim().isEmpty) return;

    setState(() => _uploading = true);
    try {
      await _repo.uploadAndSaveRecord(
        patientId : widget.patientId,
        file      : file,
        title     : title.trim(),
        facility  : 'OncoVault Medical',
        doctorName: widget.doctorId ?? '',
        fileType  : fileType,
        subtype   : 'CBC',
        summary   : 'Uploaded by doctor via OncoVault EHR',
      );
      await _loadAll();
      if (mounted) _showSnack('✅ Report uploaded & hashed', success: true);
    } catch (e) {
      if (mounted) _showSnack('Upload failed: $e', success: false);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  // ── Save Vitals ───────────────────────────────────────────────
  Future<void> _saveVitals(Map<String, dynamic> vitals) async {
    await _service.saveEhrVitals(
        patientId: widget.patientId, vitals: vitals);
    await _loadAll();
    if (mounted) _showSnack('✅ Vitals saved', success: true);
  }

  void _showSnack(String msg, {required bool success}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content        : Text(msg, style: GoogleFonts.inter(fontSize: 13)),
      backgroundColor: success ? const Color(0xFF1B6B3A) : OV.error,
      behavior       : SnackBarBehavior.floating,
      shape          : RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10)),
    ));
  }

  Future<String?> _showTitleDialog(String defaultName) async {
    final ctrl = TextEditingController(text: defaultName);
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape          : RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title  : Text('Name this Report',
            style: GoogleFonts.manrope(fontWeight: FontWeight.w700,
                fontSize: 17, color: OV.onSurface)),
        content: TextField(
          controller: ctrl, autofocus: true,
          style     : GoogleFonts.inter(fontSize: 14, color: OV.onSurface),
          decoration: InputDecoration(
            hintText     : 'e.g. CBC Report May 2025',
            hintStyle    : GoogleFonts.inter(color: OV.outline),
            filled       : true, fillColor: OV.surfaceLow,
            border       : OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide  : BorderSide(color: OV.outlineVariant)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide  : const BorderSide(
                    color: OV.primary, width: 1.5)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child    : Text('Cancel',
                  style: GoogleFonts.inter(color: OV.outline))),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, ctrl.text),
              style    : ElevatedButton.styleFrom(
                  backgroundColor: OV.slateDark,
                  foregroundColor: Colors.white,
                  elevation      : 0,
                  shape          : RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              child: Text('Upload',
                  style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OV.background,
      body: _loading
          ? const Center(
          child: CircularProgressIndicator(color: OV.primary))
          : _error != null
          ? _ErrorView(error: _error!, onRetry: _loadAll)
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    // Doctor without consent sees blocked screen
    if (_isDoctor && !_hasConsent) {
      return _NoConsentView(
        patientName: _profile?.name ?? 'Patient',
        onBack     : () => Navigator.pop(context),
      );
    }

    return SafeArea(child: CustomScrollView(slivers: [

      SliverToBoxAdapter(child: _buildAppBar()),
      SliverToBoxAdapter(child: _buildRoleBanner()),

      // ── SECTION 1: Patient Biodata ────────────────────────────
      if (_profile != null)
        SliverToBoxAdapter(child: _buildBiodataCard()),

      // ── SECTION 2: Blockchain Consent (patient only) ──────────
      if (!_isDoctor)
        SliverToBoxAdapter(child: _buildConsentCard()),

      // ── SECTION 3: Vitals ────────────────────────────────────
      SliverToBoxAdapter(child: _buildVitalsCard()),

      // ── SECTION 4: Voice Input Placeholder ───────────────────
      if (_isDoctor)
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child  : const VoiceInputPlaceholder(),
        )),

      // ── SECTION 5: CBC Report Upload + Records ────────────────
      SliverToBoxAdapter(child: _buildCbcSection()),

      // ── SECTION 6: AI Diagnostic Placeholder ─────────────────
      SliverToBoxAdapter(child: _buildAiPlaceholder()),

      const SliverToBoxAdapter(child: SizedBox(height: 100)),
    ]));
  }

  // ─────────────────────────────────────────────────────────────
  // APP BAR
  // ─────────────────────────────────────────────────────────────
  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                  padding   : const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: OV.outlineVariant.withOpacity(0.5))),
                  child: const Icon(Icons.arrow_back_ios_new_rounded,
                      size: 16, color: OV.onSurface)),
            ),
            Column(children: [
              Text('Electronic Health Record',
                  style: GoogleFonts.manrope(fontSize: 15,
                      fontWeight: FontWeight.w700, color: OV.onSurface)),
              Text('Blockchain-secured patient data',
                  style: GoogleFonts.inter(
                      fontSize: 11, color: OV.outline)),
            ]),
            _isDoctor && _hasConsent
                ? GestureDetector(
                onTap: _uploading ? null : _uploadReport,
                child: Container(
                  padding   : const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: OV.primary,
                      borderRadius: BorderRadius.circular(10)),
                  child: _uploading
                      ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.upload_rounded,
                      size: 16, color: Colors.white),
                ))
                : Container(
                padding   : const EdgeInsets.all(8),
                decoration: BoxDecoration(color: OV.surfaceLow,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: OV.outlineVariant.withOpacity(0.5))),
                child: Icon(
                    _isDoctor
                        ? Icons.lock_outline_rounded
                        : Icons.lock_outline_rounded,
                    size: 16, color: OV.outline)),
          ]),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // ROLE BANNER
  // ─────────────────────────────────────────────────────────────
  Widget _buildRoleBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        padding   : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color       : _isDoctor ? OV.primaryContainer : OV.surfaceLow,
          borderRadius: BorderRadius.circular(12),
          border      : Border.all(
              color: _isDoctor
                  ? OV.primary.withOpacity(0.3)
                  : OV.outlineVariant.withOpacity(0.4)),
        ),
        child: Row(children: [
          Icon(
            _isDoctor
                ? Icons.edit_note_rounded
                : Icons.visibility_outlined,
            size : 16,
            color: _isDoctor ? OV.primary : OV.outline,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(
            _isDoctor
                ? 'Doctor View — Full EHR access granted by patient'
                : 'Patient View — Read only. Use Share Access to grant doctor access.',
            style: GoogleFonts.inter(fontSize: 12,
                fontWeight: FontWeight.w500,
                color     : _isDoctor ? OV.primary : OV.outline),
          )),
        ]),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // SECTION 1: PATIENT BIODATA CARD
  // ─────────────────────────────────────────────────────────────
  Widget _buildBiodataCard() {
    final p = _profile!;
    return _Section(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Header row
        Row(children: [
          Container(width: 56, height: 56,
              decoration: BoxDecoration(
                  color: OV.primaryContainer,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: OV.primary.withOpacity(0.3), width: 2)),
              child: Center(child: Text(
                  p.name.isNotEmpty ? p.name[0].toUpperCase() : 'P',
                  style: GoogleFonts.manrope(fontSize: 22,
                      fontWeight: FontWeight.w700, color: OV.primary)))),
          const SizedBox(width: 14),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.name, style: GoogleFonts.manrope(fontSize: 18,
                fontWeight: FontWeight.w700, color: OV.onSurface)),
            const SizedBox(height: 4),
            Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 3),
                decoration: BoxDecoration(color: OV.primaryContainer,
                    borderRadius: BorderRadius.circular(100)),
                child: Text('PT-${p.medicalId}',
                    style: GoogleFonts.inter(fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5, color: OV.primary))),
          ])),
          // Blockchain badge
          Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color       : OV.slateDark,
                  borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                const Icon(Icons.shield_rounded,
                    size: 10, color: Colors.white),
                const SizedBox(width: 4),
                Text('Secured', style: GoogleFonts.inter(
                    fontSize: 9, fontWeight: FontWeight.w700,
                    color   : Colors.white)),
              ])),
        ]),

        const SizedBox(height: 16),
        _divider(),

        // Biodata grid
        const SizedBox(height: 12),
        _BiodataGrid(fields: [
          _BioField(label: 'Age',
              value: p.age != null ? '${p.age} years' : 'N/A',
              icon : Icons.cake_outlined),
          _BioField(label: 'Gender',
              value: p.gender.isNotEmpty ? p.gender : 'N/A',
              icon : Icons.person_outline_rounded),
          _BioField(label: 'DOB',
              value: p.dateOfBirth != null
                  ? DateFormat('yyyy-MM-dd').format(p.dateOfBirth!)
                  : 'N/A',
              icon : Icons.calendar_today_outlined),
          _BioField(label: 'Blood Group',
              value: p.bloodType.isNotEmpty ? p.bloodType : 'N/A',
              icon : Icons.water_drop_outlined),
          _BioField(label: 'Contact',
              value: p.phone.isNotEmpty ? p.phone : 'N/A',
              icon : Icons.phone_outlined),
          _BioField(label: 'Email',
              value: p.email.isNotEmpty ? p.email : 'N/A',
              icon : Icons.email_outlined),
        ]),

        if (p.allergies.isNotEmpty) ...[
          const SizedBox(height: 12),
          _divider(),
          const SizedBox(height: 12),
          Text('Allergies', style: GoogleFonts.inter(fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6, color: OV.outline)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6,
              children: p.allergies.map((a) => Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color       : OV.errorContainer,
                      borderRadius: BorderRadius.circular(100)),
                  child: Text(a, style: GoogleFonts.inter(
                      fontSize: 11, color: OV.error,
                      fontWeight: FontWeight.w500)))).toList()),
        ],

        if (p.activeDiagnosis.isNotEmpty) ...[
          const SizedBox(height: 12),
          _divider(),
          const SizedBox(height: 12),
          Text('Active Diagnosis', style: GoogleFonts.inter(
              fontSize: 11, fontWeight: FontWeight.w700,
              letterSpacing: 0.6, color: OV.outline)),
          const SizedBox(height: 6),
          Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color       : OV.primaryContainer,
                  borderRadius: BorderRadius.circular(10)),
              child: Text(p.activeDiagnosis,
                  style: GoogleFonts.manrope(fontSize: 14,
                      fontWeight: FontWeight.w700, color: OV.primary))),
        ],
      ]),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // SECTION 2: BLOCKCHAIN CONSENT (patient only)
  // ─────────────────────────────────────────────────────────────
  Widget _buildConsentCard() {
    return _Section(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.shield_outlined, size: 18, color: OV.primary),
          const SizedBox(width: 8),
          Text('Access Control', style: GoogleFonts.manrope(
              fontSize: 15, fontWeight: FontWeight.w700,
              color: OV.onSurface)),
        ]),
        const SizedBox(height: 8),
        Text('Control which doctors can access your EHR. '
            'Blockchain consent is simulated for demo.',
            style: GoogleFonts.inter(
                fontSize: 12, color: OV.outline, height: 1.4)),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, height: 44,
            child: ElevatedButton.icon(
              onPressed: () => _showConsentDialog(),
              icon : const Icon(Icons.share_rounded, size: 16),
              label: Text('Share Access with Doctor',
                  style: GoogleFonts.manrope(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: OV.slateDark,
                  foregroundColor: Colors.white,
                  elevation      : 0,
                  shape          : RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
            )),
      ]),
    );
  }

  void _showConsentDialog() {
    showModalBottomSheet(
      context         : context,
      backgroundColor : Colors.white,
      shape           : const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child  : Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: OV.outlineVariant,
                  borderRadius: BorderRadius.circular(100))),
          const SizedBox(height: 20),
          Icon(Icons.shield_outlined, size: 48, color: OV.primary),
          const SizedBox(height: 12),
          Text('Blockchain Consent', style: GoogleFonts.manrope(
              fontSize: 18, fontWeight: FontWeight.w700,
              color: OV.onSurface)),
          const SizedBox(height: 8),
          Text('Enter your doctor\'s Medical ID to grant them '
              'access to your EHR records. This simulates '
              'blockchain-based consent management.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  fontSize: 13, color: OV.outline, height: 1.5)),
          const SizedBox(height: 20),
          Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color       : OV.primaryContainer,
                  borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                Icon(Icons.info_outline_rounded,
                    size: 16, color: OV.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(
                    'In production, this will use blockchain '
                        'smart contracts for immutable consent records.',
                    style: GoogleFonts.inter(fontSize: 11,
                        color: OV.primary, height: 1.4))),
              ])),
          const SizedBox(height: 20),
          SizedBox(width: double.infinity, height: 48,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style    : ElevatedButton.styleFrom(
                    backgroundColor: OV.slateDark,
                    foregroundColor: Colors.white,
                    elevation      : 0,
                    shape          : RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14))),
                child: Text('Got it',
                    style: GoogleFonts.manrope(
                        fontWeight: FontWeight.w600)),
              )),
        ]),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // SECTION 3: VITALS CARD
  // ─────────────────────────────────────────────────────────────
  Widget _buildVitalsCard() {
    return _Section(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            Icon(Icons.monitor_heart_outlined,
                size: 18, color: OV.primary),
            const SizedBox(width: 8),
            Text('Vitals', style: GoogleFonts.manrope(
                fontSize: 15, fontWeight: FontWeight.w700,
                color: OV.onSurface)),
          ]),
          if (_isDoctor)
            GestureDetector(
              onTap: () => _showVitalsEditDialog(),
              child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                      color       : OV.primaryContainer,
                      borderRadius: BorderRadius.circular(100)),
                  child: Row(children: [
                    Icon(Icons.edit_rounded,
                        size: 12, color: OV.primary),
                    const SizedBox(width: 4),
                    Text('Edit', style: GoogleFonts.inter(
                        fontSize: 11, fontWeight: FontWeight.w600,
                        color   : OV.primary)),
                  ])),
            ),
        ]),
        const SizedBox(height: 14),
        _VitalsGrid(vitals: _vitals),
      ]),
    );
  }

  void _showVitalsEditDialog() {
    final weightCtrl = TextEditingController(
        text: _vitals['weight']?.toString() ?? '');
    final bpCtrl = TextEditingController(
        text: _vitals['bloodPressure']?.toString() ?? '');
    final tempCtrl = TextEditingController(
        text: _vitals['temperature']?.toString() ?? '');
    final hrCtrl = TextEditingController(
        text: _vitals['heartRate']?.toString() ?? '');
    final o2Ctrl = TextEditingController(
        text: _vitals['oxygenSaturation']?.toString() ?? '');
    final rrCtrl = TextEditingController(
        text: _vitals['respiratoryRate']?.toString() ?? '');

    showModalBottomSheet(
      context         : context,
      isScrollControlled: true,
      backgroundColor : Colors.white,
      shape           : const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(
            24, 24, 24,
            MediaQuery.of(context).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: OV.outlineVariant,
                  borderRadius: BorderRadius.circular(100))),
          const SizedBox(height: 16),
          Text('Edit Vitals', style: GoogleFonts.manrope(
              fontSize: 18, fontWeight: FontWeight.w700,
              color: OV.onSurface)),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: _VitalField(
                ctrl : weightCtrl,
                label: 'Weight (kg)')),
            const SizedBox(width: 12),
            Expanded(child: _VitalField(
                ctrl : bpCtrl,
                label: 'Blood Pressure')),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _VitalField(
                ctrl : tempCtrl,
                label: 'Temperature (°C)')),
            const SizedBox(width: 12),
            Expanded(child: _VitalField(
                ctrl : hrCtrl,
                label: 'Heart Rate (bpm)')),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _VitalField(
                ctrl : o2Ctrl,
                label: 'O2 Saturation (%)')),
            const SizedBox(width: 12),
            Expanded(child: _VitalField(
                ctrl : rrCtrl,
                label: 'Resp. Rate (/min)')),
          ]),
          const SizedBox(height: 20),
          SizedBox(width: double.infinity, height: 50,
              child: ElevatedButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await _saveVitals({
                    'weight'           : weightCtrl.text,
                    'bloodPressure'    : bpCtrl.text,
                    'temperature'      : tempCtrl.text,
                    'heartRate'        : hrCtrl.text,
                    'oxygenSaturation' : o2Ctrl.text,
                    'respiratoryRate'  : rrCtrl.text,
                  });
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: OV.slateDark,
                    foregroundColor: Colors.white,
                    elevation      : 0,
                    shape          : RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14))),
                child: Text('Save Vitals',
                    style: GoogleFonts.manrope(
                        fontSize: 15, fontWeight: FontWeight.w600)),
              )),
        ]),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // SECTION 5: CBC REPORT + RECORDS
  // ─────────────────────────────────────────────────────────────
  Widget _buildCbcSection() {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('CBC Reports', style: GoogleFonts.manrope(
                  fontSize: 17, fontWeight: FontWeight.w700,
                  color: OV.onSurface)),
              Text('${_records.length} total',
                  style: GoogleFonts.inter(
                      fontSize: 13, color: OV.outline)),
            ]),
      ),
      if (_isDoctor && _hasConsent)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child  : GestureDetector(
            onTap: _uploading ? null : _uploadReport,
            child: Container(
              padding   : const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color       : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border      : Border.all(
                      color: OV.primary.withOpacity(0.3),
                      width: 1.5,
                      style: BorderStyle.solid),
                  boxShadow   : [BoxShadow(
                      color     : OV.primary.withOpacity(0.06),
                      blurRadius: 8,
                      offset    : const Offset(0, 2))]),
              child: Row(children: [
                Container(width: 44, height: 44,
                    decoration: BoxDecoration(
                        color : OV.primaryContainer,
                        shape : BoxShape.circle),
                    child: const Icon(Icons.upload_file_rounded,
                        color: OV.primary, size: 20)),
                const SizedBox(width: 14),
                Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Upload CBC Report',
                          style: GoogleFonts.manrope(fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color     : OV.onSurface)),
                      Text('PDF or Image — hash generated automatically',
                          style: GoogleFonts.inter(
                              fontSize: 12, color: OV.outline)),
                    ])),
                Icon(Icons.arrow_forward_ios_rounded,
                    size: 14, color: OV.primary),
              ]),
            ),
          ),
        ),
      _records.isEmpty
          ? _EmptyRecords(isDoctor: _isDoctor)
          : Column(
          children: _records
              .map((r) => _RecordCard(record: r))
              .toList()),
    ]);
  }

  // ─────────────────────────────────────────────────────────────
  // SECTION 6: AI DIAGNOSTIC PLACEHOLDER
  // ─────────────────────────────────────────────────────────────
  Widget _buildAiPlaceholder() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        padding   : const EdgeInsets.all(18),
        decoration: BoxDecoration(
            gradient    : LinearGradient(
                colors: [OV.primary.withOpacity(0.08),
                  OV.primaryContainer.withOpacity(0.5)],
                begin: Alignment.topLeft,
                end  : Alignment.bottomRight),
            borderRadius: BorderRadius.circular(16),
            border      : Border.all(
                color: OV.primary.withOpacity(0.2))),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(children: [
                  Icon(Icons.auto_awesome_rounded,
                      size: 16, color: OV.primary),
                  const SizedBox(width: 6),
                  Text('AI Diagnostic Engine',
                      style: GoogleFonts.manrope(fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color     : OV.primary)),
                ]),
                Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color       : OV.slateDark,
                        borderRadius: BorderRadius.circular(100)),
                    child: Text('COMING SOON',
                        style: GoogleFonts.inter(
                            fontSize: 9, fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color   : Colors.white))),
              ]),
          const SizedBox(height: 10),
          Text('Upload a CBC report above and the AI model will '
              'automatically analyze blood values, detect cancer '
              'indicators, and provide diagnostic predictions.',
              style: GoogleFonts.inter(fontSize: 12,
                  color: OV.onSurfaceVariant, height: 1.5)),
          const SizedBox(height: 14),
          SizedBox(width: double.infinity, height: 44,
              child: ElevatedButton.icon(
                onPressed: () {}, // placeholder — no logic
                icon : const Icon(Icons.science_rounded, size: 16),
                label: Text('Run AI Diagnosis',
                    style: GoogleFonts.manrope(fontSize: 13,
                        fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                    backgroundColor: OV.primary.withOpacity(0.15),
                    foregroundColor: OV.primary,
                    elevation      : 0,
                    shape          : RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
              )),
          const SizedBox(height: 8),
          Center(child: Text('AI model training — 70% presentation',
              style: GoogleFonts.inter(fontSize: 11,
                  color: OV.outline,
                  fontStyle: FontStyle.italic))),
        ]),
      ),
    );
  }

  Widget _divider() => Container(height: 1,
      color: OV.outlineVariant.withOpacity(0.4));
}

// ─────────────────────────────────────────────────────────────────
// NO CONSENT VIEW
// ─────────────────────────────────────────────────────────────────
class _NoConsentView extends StatelessWidget {
  final String patientName;
  final VoidCallback onBack;
  const _NoConsentView({required this.patientName, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OV.background,
      body: SafeArea(child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child  : GestureDetector(
            onTap: onBack,
            child: Container(padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: OV.outlineVariant.withOpacity(0.5))),
                child: const Icon(Icons.arrow_back_ios_new_rounded,
                    size: 16, color: OV.onSurface)),
          ),
        ),
        Expanded(child: Center(child: Padding(
          padding: const EdgeInsets.all(32),
          child  : Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 80, height: 80,
                decoration: BoxDecoration(
                    color       : OV.errorContainer,
                    shape       : BoxShape.circle),
                child: Icon(Icons.lock_rounded,
                    size: 36, color: OV.error)),
            const SizedBox(height: 20),
            Text('Access Restricted', style: GoogleFonts.manrope(
                fontSize: 20, fontWeight: FontWeight.w700,
                color: OV.onSurface)),
            const SizedBox(height: 10),
            Text(
              '$patientName has not granted you access to their EHR.\n\n'
                  'Per SRS FR-M2.2 and FR-M8.2, blockchain consent '
                  'verification is required before accessing patient records.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 13,
                  color: OV.outline, height: 1.6),
            ),
            const SizedBox(height: 24),
            Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color       : OV.primaryContainer,
                    borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  Icon(Icons.info_outline_rounded,
                      size: 16, color: OV.primary),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                      'Ask the patient to tap "Share Access with Doctor" '
                          'in their EHR and enter your Medical ID.',
                      style: GoogleFonts.inter(fontSize: 12,
                          color: OV.primary, height: 1.4))),
                ])),
          ]),
        ))),
      ])),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// RECORD CARD
// ─────────────────────────────────────────────────────────────────
class _RecordCard extends StatelessWidget {
  final MedicalRecordModel record;
  const _RecordCard({required this.record});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        padding   : const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow   : [BoxShadow(
                color     : Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset    : const Offset(0, 3))]),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(record.title,
                    style: GoogleFonts.manrope(fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color     : OV.onSurface),
                    overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 8),
                AsyncIntegrityBadge(
                    fileUrl   : record.fileUrl,
                    storedHash: record.fileHash),
              ]),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 4, children: [
            _MetaChip(icon: Icons.local_hospital_outlined,
                label: record.facility),
            _MetaChip(icon: Icons.calendar_today_outlined,
                label: _fmt(record.uploadedAt)),
            _MetaChip(icon: Icons.insert_drive_file_outlined,
                label: record.fileType.toUpperCase()),
          ]),
          if (record.summary.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(record.summary, style: GoogleFonts.inter(
                fontSize: 12, color: OV.outline, height: 1.5),
                maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
          if (record.fileHash.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding   : const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: OV.surfaceLow,
                  borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                Icon(Icons.fingerprint_rounded,
                    size: 13, color: OV.outline),
                const SizedBox(width: 6),
                Expanded(child: Text(
                    'SHA-256: ${record.fileHash.substring(0, 20)}...',
                    style: GoogleFonts.inter(
                        fontSize: 11, color: OV.outline))),
              ]),
            ),
          ],
        ]),
      ),
    );
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
          '${d.month.toString().padLeft(2, '0')}/${d.year}';
}

// ─────────────────────────────────────────────────────────────────
// VITALS GRID WIDGET
// ─────────────────────────────────────────────────────────────────
class _VitalsGrid extends StatelessWidget {
  final Map<String, dynamic> vitals;
  const _VitalsGrid({required this.vitals});

  @override
  Widget build(BuildContext context) {
    final items = [
      _VitalItem(label: 'Weight',       value: vitals['weight'],
          unit: 'kg',   icon: Icons.monitor_weight_outlined),
      _VitalItem(label: 'Blood Pressure', value: vitals['bloodPressure'],
          unit: 'mmHg', icon: Icons.favorite_outline_rounded),
      _VitalItem(label: 'Temperature',  value: vitals['temperature'],
          unit: '°C',   icon: Icons.thermostat_rounded),
      _VitalItem(label: 'Heart Rate',   value: vitals['heartRate'],
          unit: 'bpm',  icon: Icons.monitor_heart_outlined),
      _VitalItem(label: 'O2 Sat',       value: vitals['oxygenSaturation'],
          unit: '%',    icon: Icons.air_rounded),
      _VitalItem(label: 'Resp. Rate',   value: vitals['respiratoryRate'],
          unit: '/min', icon: Icons.air_outlined),
    ];

    return GridView.count(
      crossAxisCount : 3,
      shrinkWrap     : true,
      physics        : const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing : 10,
      childAspectRatio: 1.2,
      children       : items.map((item) => _VitalTile(item: item)).toList(),
    );
  }
}

class _VitalItem {
  final String   label;
  final dynamic  value;
  final String   unit;
  final IconData icon;
  const _VitalItem({required this.label, required this.value,
    required this.unit, required this.icon});
}

class _VitalTile extends StatelessWidget {
  final _VitalItem item;
  const _VitalTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final hasValue = item.value != null &&
        item.value.toString().isNotEmpty;
    return Container(
      padding   : const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color       : hasValue ? OV.primaryContainer : OV.surfaceLow,
          borderRadius: BorderRadius.circular(12),
          border      : Border.all(
              color: hasValue
                  ? OV.primary.withOpacity(0.2)
                  : OV.outlineVariant.withOpacity(0.3))),
      child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(item.icon, size: 18,
                color: hasValue ? OV.primary : OV.outlineVariant),
            const SizedBox(height: 4),
            Text(
              hasValue ? '${item.value} ${item.unit}' : '—',
              style: GoogleFonts.manrope(
                  fontSize  : 11,
                  fontWeight: FontWeight.w700,
                  color     : hasValue ? OV.onSurface : OV.outlineVariant),
              textAlign: TextAlign.center,
            ),
            Text(item.label, style: GoogleFonts.inter(
                fontSize: 9, color: OV.outline),
                textAlign: TextAlign.center),
          ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// BIODATA GRID
// ─────────────────────────────────────────────────────────────────
class _BioField {
  final String label, value;
  final IconData icon;
  const _BioField(
      {required this.label, required this.value, required this.icon});
}

class _BiodataGrid extends StatelessWidget {
  final List<_BioField> fields;
  const _BiodataGrid({required this.fields});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        (fields.length / 2).ceil(),
            (i) {
          final left  = fields[i * 2];
          final right = i * 2 + 1 < fields.length
              ? fields[i * 2 + 1] : null;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child  : Row(children: [
              Expanded(child: _BioTile(field: left)),
              const SizedBox(width: 10),
              Expanded(child: right != null
                  ? _BioTile(field: right)
                  : const SizedBox()),
            ]),
          );
        },
      ),
    );
  }
}

class _BioTile extends StatelessWidget {
  final _BioField field;
  const _BioTile({required this.field});

  @override
  Widget build(BuildContext context) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(field.icon, size: 14, color: OV.outline),
        const SizedBox(width: 6),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(field.label, style: GoogleFonts.inter(
              fontSize: 9, fontWeight: FontWeight.w700,
              letterSpacing: 0.6, color: OV.outline)),
          const SizedBox(height: 2),
          Text(field.value, style: GoogleFonts.inter(
              fontSize: 12, fontWeight: FontWeight.w600,
              color: OV.onSurface),
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ])),
      ]);
}

// ─────────────────────────────────────────────────────────────────
// HELPER WIDGETS
// ─────────────────────────────────────────────────────────────────
class _Section extends StatelessWidget {
  final Widget child;
  final EdgeInsets margin;
  const _Section({required this.child, required this.margin});

  @override
  Widget build(BuildContext context) => Padding(
      padding: margin,
      child  : Container(
        padding   : const EdgeInsets.all(18),
        decoration: BoxDecoration(
            color       : Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow   : [BoxShadow(
                color     : Colors.black.withOpacity(0.04),
                blurRadius: 12,
                offset    : const Offset(0, 3))]),
        child: child,
      ));
}

class _VitalField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  const _VitalField({required this.ctrl, required this.label});

  @override
  Widget build(BuildContext context) => TextField(
      controller: ctrl,
      keyboardType: TextInputType.text,
      style      : GoogleFonts.inter(fontSize: 13, color: OV.onSurface),
      decoration : InputDecoration(
        labelText   : label,
        labelStyle  : GoogleFonts.inter(fontSize: 11, color: OV.outline),
        filled      : true,
        fillColor   : OV.surfaceLow,
        border      : OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide  : BorderSide(color: OV.outlineVariant)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide  : const BorderSide(
                color: OV.primary, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 12, vertical: 10),
      ));
}

class _MetaChip extends StatelessWidget {
  final IconData icon; final String label;
  const _MetaChip({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) => Row(
      mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 12, color: OV.outline),
    const SizedBox(width: 4),
    Text(label, style: GoogleFonts.inter(
        fontSize: 11, color: OV.outline)),
  ]);
}

class _EmptyRecords extends StatelessWidget {
  final bool isDoctor;
  const _EmptyRecords({required this.isDoctor});
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 40),
      child: Column(children: [
        Icon(Icons.folder_open_rounded,
            size: 48, color: OV.outlineVariant),
        const SizedBox(height: 12),
        Text('No CBC reports yet', style: GoogleFonts.manrope(
            fontSize: 14, fontWeight: FontWeight.w600,
            color: OV.outline)),
        const SizedBox(height: 6),
        Text(
          isDoctor
              ? 'Tap the upload area above to add\nthe first CBC report.'
              : 'Your doctor has not uploaded\nany reports yet.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(fontSize: 12, color: OV.outline),
        ),
      ]));
}

class _ErrorView extends StatelessWidget {
  final String error; final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.cloud_off_rounded, size: 48, color: OV.error),
        const SizedBox(height: 14),
        Text('Something went wrong', style: GoogleFonts.manrope(
            fontSize: 16, fontWeight: FontWeight.w700,
            color: OV.onSurface)),
        const SizedBox(height: 8),
        Text(error, textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 12, color: OV.outline)),
        const SizedBox(height: 24),
        ElevatedButton(onPressed: onRetry,
            style: ElevatedButton.styleFrom(
                backgroundColor: OV.slateDark,
                foregroundColor: Colors.white,
                shape          : RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
            child: Text('Retry', style: GoogleFonts.manrope(
                fontWeight: FontWeight.w600))),
      ])));
}