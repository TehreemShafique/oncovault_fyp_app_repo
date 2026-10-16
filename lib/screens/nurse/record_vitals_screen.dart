// lib/screens/nurse/record_vitals_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../models/vital_sign_model.dart';
import '../../utils/vital_validator.dart';
import '../../services/nurse_service.dart';
import 'patient_vitals_history_screen.dart';

class RecordVitalsScreen extends StatefulWidget {
  final String patientId;
  final String patientName;
  final String? doctorId;
  final String? doctorName;
  final String? appointmentId;

  const RecordVitalsScreen({
    super.key,
    required this.patientId,
    required this.patientName,
    this.doctorId,
    this.doctorName,
    this.appointmentId,
  });

  @override
  State<RecordVitalsScreen> createState() => _RecordVitalsScreenState();
}

class _RecordVitalsScreenState extends State<RecordVitalsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nurseService = NurseService();

  // Controllers
  final _systolicCtrl = TextEditingController();
  final _diastolicCtrl = TextEditingController();
  final _pulseCtrl = TextEditingController();
  final _tempCtrl = TextEditingController();
  final _respRateCtrl = TextEditingController();
  final _spo2Ctrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  bool _isFahrenheit = false;
  bool _isSubmitting = false;

  List<String> _liveWarnings = [];
  bool _liveIsCritical = false;

  @override
  void initState() {
    super.initState();
    _systolicCtrl.addListener(_updateLiveFeedback);
    _diastolicCtrl.addListener(_updateLiveFeedback);
    _pulseCtrl.addListener(_updateLiveFeedback);
    _tempCtrl.addListener(_updateLiveFeedback);
    _respRateCtrl.addListener(_updateLiveFeedback);
    _spo2Ctrl.addListener(_updateLiveFeedback);
  }

  @override
  void dispose() {
    _systolicCtrl.dispose();
    _diastolicCtrl.dispose();
    _pulseCtrl.dispose();
    _tempCtrl.dispose();
    _respRateCtrl.dispose();
    _spo2Ctrl.dispose();
    _weightCtrl.dispose();
    _heightCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _updateLiveFeedback() {
    final sys = double.tryParse(_systolicCtrl.text.trim()) ?? 120.0;
    final dia = double.tryParse(_diastolicCtrl.text.trim()) ?? 80.0;
    final pulse = double.tryParse(_pulseCtrl.text.trim()) ?? 75.0;
    final tempVal = double.tryParse(_tempCtrl.text.trim()) ?? 37.0;
    final tempC = _isFahrenheit ? VitalValidator.fahrenheitToCelsius(tempVal) : tempVal;
    final resp = double.tryParse(_respRateCtrl.text.trim()) ?? 16.0;
    final spo2 = double.tryParse(_spo2Ctrl.text.trim()) ?? 98.0;

    final hasAnyInput = _systolicCtrl.text.trim().isNotEmpty ||
        _diastolicCtrl.text.trim().isNotEmpty ||
        _pulseCtrl.text.trim().isNotEmpty ||
        _tempCtrl.text.trim().isNotEmpty ||
        _respRateCtrl.text.trim().isNotEmpty ||
        _spo2Ctrl.text.trim().isNotEmpty;

    if (!hasAnyInput) {
      setState(() {
        _liveWarnings = [];
        _liveIsCritical = false;
      });
      return;
    }

    final assessment = VitalValidator.assessVitals(
      systolicBp: sys,
      diastolicBp: dia,
      pulseRate: pulse,
      temperatureC: tempC,
      respiratoryRate: resp,
      oxygenSaturation: spo2,
    );

    setState(() {
      _liveWarnings = [...assessment.criticalReasons, ...assessment.warnings];
      _liveIsCritical = assessment.isCritical;
    });
  }

  Future<void> _handleSubmit() async {
    if (_isSubmitting) return;

    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final sys = int.parse(_systolicCtrl.text.trim());
      final dia = int.parse(_diastolicCtrl.text.trim());
      final pulse = int.parse(_pulseCtrl.text.trim());
      final rawTemp = double.parse(_tempCtrl.text.trim());
      final tempC = _isFahrenheit
          ? VitalValidator.fahrenheitToCelsius(rawTemp)
          : rawTemp;
      final resp = int.parse(_respRateCtrl.text.trim());
      final spo2 = int.parse(_spo2Ctrl.text.trim());
      final weight = _weightCtrl.text.trim().isNotEmpty
          ? double.tryParse(_weightCtrl.text.trim())
          : null;
      final height = _heightCtrl.text.trim().isNotEmpty
          ? double.tryParse(_heightCtrl.text.trim())
          : null;
      final notes = _notesCtrl.text.trim();

      final obs = await _nurseService.recordVitalObservation(
        patientId: widget.patientId,
        patientName: widget.patientName,
        systolicBp: sys,
        diastolicBp: dia,
        pulseRate: pulse,
        temperatureCelsius: tempC,
        respiratoryRate: resp,
        oxygenSaturation: spo2,
        weightKg: weight,
        heightCm: height,
        notes: notes.isNotEmpty ? notes : null,
        appointmentId: widget.appointmentId,
      );

      if (!mounted) return;

      _showSuccessDialog(obs);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceAll('Exception: ', ''),
            style: GoogleFonts.inter(color: Colors.white),
          ),
          backgroundColor: OV.error,
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _showSuccessDialog(VitalSignModel obs) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: OV.tertiaryContainer,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_rounded, color: OV.tertiary, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Vitals Recorded',
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    color: OV.onSurface,
                  ),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Clinical observation successfully saved and added to the patient\'s EHR history.',
                  style: GoogleFonts.inter(fontSize: 13, color: OV.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: OV.surfaceLow.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: OV.outlineVariant.withOpacity(0.5)),
                  ),
                  child: Column(
                    children: [
                      _summaryRow('Blood Pressure', '${obs.systolicBp}/${obs.diastolicBp} mmHg'),
                      const Divider(height: 12),
                      _summaryRow('Pulse Rate', '${obs.pulseRate} bpm'),
                      const Divider(height: 12),
                      _summaryRow('Temperature', '${obs.temperatureCelsius.toStringAsFixed(1)} °C (${obs.temperatureFahrenheit.toStringAsFixed(1)} °F)'),
                      const Divider(height: 12),
                      _summaryRow('Resp. Rate', '${obs.respiratoryRate} /min'),
                      const Divider(height: 12),
                      _summaryRow('SpO2', '${obs.oxygenSaturation}%'),
                      if (obs.weightKg != null) ...[
                        const Divider(height: 12),
                        _summaryRow('Weight', '${obs.weightKg} kg'),
                      ],
                      if (obs.bmi != null) ...[
                        const Divider(height: 12),
                        _summaryRow('BMI', '${obs.bmi!.toStringAsFixed(1)}'),
                      ],
                    ],
                  ),
                ),
                if (obs.warningFlags.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: obs.isCritical ? OV.errorContainer : const Color(0xFFFFF3CD),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 18,
                          color: obs.isCritical ? OV.error : const Color(0xFF856404),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            obs.warningFlags.join(' • '),
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: obs.isCritical ? OV.error : const Color(0xFF856404),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx); // Close dialog
                Navigator.pop(context); // Return to previous screen
              },
              child: Text(
                'Back to Dashboard',
                style: GoogleFonts.manrope(fontWeight: FontWeight.w600, color: OV.onSurfaceVariant),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx); // Close dialog
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PatientVitalsHistoryScreen(
                      patientId: widget.patientId,
                      patientName: widget.patientName,
                    ),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: OV.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(
                'View History',
                style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _summaryRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 12, color: OV.onSurfaceVariant)),
        Text(value, style: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w700, color: OV.onSurface)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OV.background,
      appBar: AppBar(
        title: Text(
          'Record Patient Vitals',
          style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w700, color: OV.onSurface),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: OV.onSurface),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            children: [
              // ── Patient Context Banner ──────────────────────────────
              _buildPatientContextCard(),
              const SizedBox(height: 16),

              // ── Live Warning Banner (Non-blocking) ─────────────────
              if (_liveWarnings.isNotEmpty) _buildLiveWarningBanner(),
              if (_liveWarnings.isNotEmpty) const SizedBox(height: 16),

              // ── Vital Signs Entry Form ──────────────────────────────
              _buildVitalsCard(),
              const SizedBox(height: 16),

              // ── Optional Anthropometrics & Notes ────────────────────
              _buildOptionalCard(),
              const SizedBox(height: 24),

              // ── Submit Button ───────────────────────────────────────
              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _isSubmitting ? null : _handleSubmit,
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2),
                        )
                      : const Icon(Icons.check_circle_outline_rounded, size: 20),
                  label: Text(
                    _isSubmitting ? 'Saving Observation...' : 'Save & Record Vitals',
                    style: GoogleFonts.manrope(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: OV.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: OV.primary.withOpacity(0.6),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPatientContextCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: OV.outlineVariant.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: OV.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                widget.patientName.isNotEmpty ? widget.patientName[0].toUpperCase() : 'P',
                style: GoogleFonts.manrope(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: OV.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.patientName,
                  style: GoogleFonts.manrope(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: OV.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Patient ID: ${widget.patientId}',
                  style: GoogleFonts.inter(fontSize: 12, color: OV.onSurfaceVariant),
                ),
                if (widget.doctorName != null && widget.doctorName!.isNotEmpty) ...[
                  Text(
                    'Attending Doctor: ${widget.doctorName}',
                    style: GoogleFonts.inter(fontSize: 12, color: OV.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveWarningBanner() {
    final isCrit = _liveIsCritical;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isCrit ? const Color(0xFFFDE8E8) : const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCrit ? OV.error.withOpacity(0.5) : const Color(0xFFF59E0B).withOpacity(0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isCrit ? Icons.error_outline_rounded : Icons.warning_amber_rounded,
                size: 20,
                color: isCrit ? OV.error : const Color(0xFFB45309),
              ),
              const SizedBox(width: 8),
              Text(
                isCrit ? 'CRITICAL CLINICAL READING' : 'Abnormal Vital Sign Warnings',
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isCrit ? OV.error : const Color(0xFFB45309),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ..._liveWarnings.map(
            (w) => Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '• ',
                    style: TextStyle(
                      color: isCrit ? OV.error : const Color(0xFFB45309),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      w,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isCrit ? OV.error : const Color(0xFF92400E),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVitalsCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: OV.outlineVariant.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Vital Signs',
                style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700, color: OV.onSurface),
              ),
              Text(
                'Required',
                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: OV.primary),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Blood Pressure (Systolic & Diastolic)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildInputField(
                  controller: _systolicCtrl,
                  label: 'Systolic BP',
                  hint: '120',
                  unit: 'mmHg',
                  keyboardType: TextInputType.number,
                  validator: (val) => VitalValidator.validateSystolic(val).errorMessage,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildInputField(
                  controller: _diastolicCtrl,
                  label: 'Diastolic BP',
                  hint: '80',
                  unit: 'mmHg',
                  keyboardType: TextInputType.number,
                  validator: (val) => VitalValidator.validateDiastolic(
                    val,
                    systolicVal: double.tryParse(_systolicCtrl.text.trim()),
                  ).errorMessage,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Pulse Rate & Respiratory Rate
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildInputField(
                  controller: _pulseCtrl,
                  label: 'Pulse Rate',
                  hint: '75',
                  unit: 'bpm',
                  keyboardType: TextInputType.number,
                  validator: (val) => VitalValidator.validatePulse(val).errorMessage,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildInputField(
                  controller: _respRateCtrl,
                  label: 'Resp. Rate',
                  hint: '16',
                  unit: '/min',
                  keyboardType: TextInputType.number,
                  validator: (val) => VitalValidator.validateRespiratory(val).errorMessage,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Body Temperature & SpO2
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Temperature',
                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: OV.onSurface),
                        ),
                        // Unit Switcher
                        GestureDetector(
                          onTap: () {
                            final current = double.tryParse(_tempCtrl.text.trim());
                            setState(() {
                              _isFahrenheit = !_isFahrenheit;
                              if (current != null) {
                                if (_isFahrenheit) {
                                  _tempCtrl.text = VitalValidator.celsiusToFahrenheit(current).toStringAsFixed(1);
                                } else {
                                  _tempCtrl.text = VitalValidator.fahrenheitToCelsius(current).toStringAsFixed(1);
                                }
                              }
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: OV.primaryContainer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _isFahrenheit ? 'Switch to °C' : 'Switch to °F',
                              style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: OV.primary),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _tempCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: GoogleFonts.inter(fontSize: 14, color: OV.onSurface),
                      decoration: InputDecoration(
                        hintText: _isFahrenheit ? '98.6' : '37.0',
                        hintStyle: GoogleFonts.inter(fontSize: 13, color: OV.outline),
                        suffixText: _isFahrenheit ? '°F' : '°C',
                        suffixStyle: GoogleFonts.inter(fontSize: 12, color: OV.onSurfaceVariant),
                        filled: true,
                        fillColor: OV.surfaceLow.withOpacity(0.3),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: OV.outlineVariant.withOpacity(0.5)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: OV.outlineVariant.withOpacity(0.5)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: OV.primary, width: 1.5),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      validator: (val) => VitalValidator.validateTemperature(
                        val,
                        unit: _isFahrenheit ? 'F' : 'C',
                      ).errorMessage,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildInputField(
                  controller: _spo2Ctrl,
                  label: 'Oxygen Sat. (SpO2)',
                  hint: '98',
                  unit: '%',
                  keyboardType: TextInputType.number,
                  validator: (val) => VitalValidator.validateOxygenSaturation(val).errorMessage,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOptionalCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: OV.outlineVariant.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Anthropometrics & Notes',
                style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700, color: OV.onSurface),
              ),
              Text(
                'Optional',
                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: OV.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildInputField(
                  controller: _weightCtrl,
                  label: 'Weight',
                  hint: '70.5',
                  unit: 'kg',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (val) => VitalValidator.validateWeight(val).errorMessage,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildInputField(
                  controller: _heightCtrl,
                  label: 'Height',
                  hint: '175',
                  unit: 'cm',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (val) => VitalValidator.validateHeight(val).errorMessage,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Clinical Observations / Notes',
            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: OV.onSurface),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _notesCtrl,
            maxLines: 2,
            style: GoogleFonts.inter(fontSize: 14, color: OV.onSurface),
            decoration: InputDecoration(
              hintText: 'e.g. Patient appeared flushed, resting seated for 10 min...',
              hintStyle: GoogleFonts.inter(fontSize: 13, color: OV.outline),
              filled: true,
              fillColor: OV.surfaceLow.withOpacity(0.3),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: OV.outlineVariant.withOpacity(0.5)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: OV.outlineVariant.withOpacity(0.5)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: OV.primary, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required String unit,
    required TextInputType keyboardType,
    required String? Function(String?) validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: OV.onSurface),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          style: GoogleFonts.inter(fontSize: 14, color: OV.onSurface),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.inter(fontSize: 13, color: OV.outline),
            suffixText: unit,
            suffixStyle: GoogleFonts.inter(fontSize: 12, color: OV.onSurfaceVariant),
            filled: true,
            fillColor: OV.surfaceLow.withOpacity(0.3),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: OV.outlineVariant.withOpacity(0.5)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: OV.outlineVariant.withOpacity(0.5)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: OV.primary, width: 1.5),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
          validator: validator,
        ),
      ],
    );
  }
}
