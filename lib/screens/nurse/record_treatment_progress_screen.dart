// lib/screens/nurse/record_treatment_progress_screen.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../services/treatment_tracking_service.dart';

class RecordTreatmentProgressScreen extends StatefulWidget {
  final String patientId;
  final String patientName;
  final String planId;
  final String planTitle;
  final TreatmentTrackingService? service;

  const RecordTreatmentProgressScreen({
    super.key,
    required this.patientId,
    required this.patientName,
    required this.planId,
    required this.planTitle,
    this.service,
  });

  @override
  State<RecordTreatmentProgressScreen> createState() =>
      _RecordTreatmentProgressScreenState();
}

class _RecordTreatmentProgressScreenState
    extends State<RecordTreatmentProgressScreen> {
  final _formKey = GlobalKey<FormState>();
  final _summaryController = TextEditingController();
  final _observationsController = TextEditingController();
  String? _selectedTolerance;
  bool _isSubmitting = false;

  final List<Map<String, String>> _toleranceOptions = [
    {
      'value': 'well_tolerated',
      'label': 'Well Tolerated',
      'desc': 'No significant adverse reactions or distress',
    },
    {
      'value': 'mild_adverse',
      'label': 'Mild Adverse Reaction',
      'desc': 'Mild nausea, fatigue, or localized discomfort',
    },
    {
      'value': 'moderate_adverse',
      'label': 'Moderate Adverse Reaction',
      'desc': 'Noticeable distress requiring supportive interventions',
    },
    {
      'value': 'severe_toxicity',
      'label': 'Severe Toxicity Alert',
      'desc': 'Critical reaction or febrile emergency; attending alerted',
    },
  ];

  @override
  void dispose() {
    _summaryController.dispose();
    _observationsController.dispose();
    super.dispose();
  }

  Future<void> _submitProgressUpdate() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final service = widget.service ?? TreatmentTrackingService.instance;
      await service.recordTreatmentProgressUpdate(
        patientId: widget.patientId,
        planId: widget.planId,
        clinicalSummary: _summaryController.text.trim(),
        patientTolerance: _selectedTolerance,
        factualObservations: _observationsController.text.trim().isNotEmpty
            ? _observationsController.text.trim()
            : null,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Treatment progress update recorded successfully.',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
          ),
          backgroundColor: OV.tertiary,
          behavior: SnackBarBehavior.floating,
        ),
      );

      setState(() => _isSubmitting = false);
      if (Navigator.canPop(context)) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);

      String errorMessage = 'Failed to record progress update.';
      if (e is TreatmentPlanException) {
        errorMessage = e.message;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMessage,
            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
          ),
          backgroundColor: OV.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OV.background,
      appBar: AppBar(
        backgroundColor: OV.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: OV.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Record Progress Update',
              style: GoogleFonts.manrope(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: OV.onSurface,
              ),
            ),
            Text(
              widget.patientName,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: OV.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Plan Context Banner ──────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: OV.tertiaryContainer.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: OV.tertiary.withOpacity(0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: OV.tertiary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.assignment_turned_in_rounded,
                          color: OV.tertiary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Target Treatment Plan',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: OV.tertiary,
                              ),
                            ),
                            Text(
                              widget.planTitle,
                              style: GoogleFonts.manrope(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: OV.onSurface,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ── Clinical Progress Summary (Required) ─────────────────
                Text(
                  'Clinical Progress Summary *',
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: OV.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Concise factual summary of patient response and current condition.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: OV.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  key: const Key('progressSummaryField'),
                  controller: _summaryController,
                  maxLines: 4,
                  maxLength: 2000,
                  decoration: InputDecoration(
                    hintText:
                        'e.g. Patient tolerated second antiemetic dose well. Blood pressure stabilized at 120/78 mmHg. Afebrile.',
                    hintStyle: GoogleFonts.inter(
                      fontSize: 13,
                      color: OV.outline,
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: OV.outlineVariant),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: OV.outlineVariant),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: OV.primary, width: 2),
                    ),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Please enter a clinical progress summary.';
                    }
                    if (val.trim().length < 5) {
                      return 'Summary must be at least 5 characters.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // ── Patient Tolerance Enum (Optional) ────────────────────
                Text(
                  'Observed Patient Tolerance',
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: OV.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Standardized hematologic therapy tolerance classification.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: OV.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  key: const Key('patientToleranceDropdown'),
                  initialValue: _selectedTolerance,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: OV.outlineVariant),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: OV.outlineVariant),
                    ),
                  ),
                  hint: Text(
                    'Select tolerance rating (optional)',
                    style: GoogleFonts.inter(fontSize: 13, color: OV.outline),
                  ),
                  isExpanded: true,
                  items: _toleranceOptions.map((opt) {
                    return DropdownMenuItem<String>(
                      value: opt['value'],
                      child: Text(
                        opt['label']!,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: OV.onSurface,
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: (val) => setState(() => _selectedTolerance = val),
                ),
                const SizedBox(height: 20),

                // ── Factual Observations (Optional) ──────────────────────
                Text(
                  'Factual Observations (Optional)',
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: OV.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Bedside findings, hydration status, oral mucosa inspection, or infusion rate checks.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: OV.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  key: const Key('factualObservationsField'),
                  controller: _observationsController,
                  maxLines: 3,
                  maxLength: 1000,
                  decoration: InputDecoration(
                    hintText:
                        'e.g. Oral mucosa intact without mucositis. Peripheral IV site clean and patent.',
                    hintStyle: GoogleFonts.inter(
                      fontSize: 13,
                      color: OV.outline,
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: OV.outlineVariant),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: OV.outlineVariant),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: OV.primary, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // ── Clinical Safety Notice ───────────────────────────────
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: OV.primaryContainer.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        size: 16,
                        color: OV.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Clinical Safety Policy: Treatment progress records are immutable and attributable to your authenticated identity. Treatment protocol modification or medication prescription requires attending physician authorization.',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            height: 1.4,
                            color: OV.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // ── Submit Button ────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    key: const Key('submitProgressButton'),
                    onPressed: _isSubmitting ? null : _submitProgressUpdate,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: OV.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            'Submit Progress Update',
                            style: GoogleFonts.manrope(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
