// lib/screens/nurse/nurse_note_review_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../models/clinical_note_model.dart';
import '../../models/nlp_extraction_model.dart';
import '../../services/nurse_service.dart';

class NurseNoteReviewScreen extends StatefulWidget {
  final String patientId;
  final String patientName;
  final String? doctorId;
  final String? doctorName;
  final ClinicalNoteType noteType;
  final String rawTranscription;
  final String reviewedTranscript;
  final NlpExtractionResponse extraction;
  final ClinicalNoteModel? draftNote;
  final String? amendmentOf;

  const NurseNoteReviewScreen({
    super.key,
    required this.patientId,
    required this.patientName,
    this.doctorId,
    this.doctorName,
    required this.noteType,
    required this.rawTranscription,
    required this.reviewedTranscript,
    required this.extraction,
    this.draftNote,
    this.amendmentOf,
  });

  @override
  State<NurseNoteReviewScreen> createState() => _NurseNoteReviewScreenState();
}

class _NurseNoteReviewScreenState extends State<NurseNoteReviewScreen> {
  final _nurseService = NurseService();
  bool _saving = false;
  bool _isConfirmed = false;

  late TextEditingController _transcriptCtrl;
  late TextEditingController _summaryCtrl;
  late TextEditingController _observationsCtrl;
  late TextEditingController _interventionsCtrl;
  late TextEditingController _responseCtrl;

  // Editable Symptoms State: map of symptomKey -> bool? (true: present, false: negated, null: unstated)
  late Map<String, bool?> _symptomsState;
  late Map<String, String?> _symptomsTrace;

  final Map<String, String> _symptomLabels = {
    'shortnessOfBreath': 'Shortness of Breath',
    'bonePain': 'Bone / Joint Pain',
    'fever': 'Persistent Fever',
    'familyHistory': 'Family History',
    'frequentInfections': 'Frequent Infections',
    'itchySkinOrRash': 'Itchy Skin / Rash',
    'lossOfAppetiteOrNausea': 'Loss of Appetite / Nausea',
    'persistentWeaknessAndFatigue': 'Weakness & Fatigue',
    'swollenPainlessLymphNodes': 'Swollen Lymph Nodes',
    'significantBruisingOrBleeding': 'Bruising / Bleeding',
    'enlargedLiver': 'Enlarged Liver / Spleen',
    'oralCavityChanges': 'Oral Sores / Mucosa Changes',
    'visionBlurring': 'Vision Blurring',
    'jaundice': 'Jaundice / Scleral Icterus',
    'nightSweats': 'Night Sweats',
    'smokes': 'History of Smoking',
  };

  @override
  void initState() {
    super.initState();
    _transcriptCtrl = TextEditingController(text: widget.reviewedTranscript);
    _observationsCtrl = TextEditingController(
      text: widget.draftNote?.narrativeObservations ?? '',
    );
    _interventionsCtrl = TextEditingController(
      text: widget.draftNote?.careInterventions ?? '',
    );
    _responseCtrl = TextEditingController(
      text: widget.draftNote?.treatmentResponseNarrative ?? '',
    );

    // Initialize 16 symptoms from extraction response or draft
    _symptomsState = {};
    _symptomsTrace = {};

    _symptomLabels.forEach((k, _) {
      if (widget.extraction.symptoms.containsKey(k)) {
        final item = widget.extraction.symptoms[k]!;
        _symptomsState[k] = item.value;
        _symptomsTrace[k] = item.sourceText;
      } else if (widget.draftNote?.supportedExtractedSymptoms.containsKey(k) == true) {
        final raw = widget.draftNote!.supportedExtractedSymptoms[k];
        if (raw is Map) {
          _symptomsState[k] = raw['value'] as bool?;
          _symptomsTrace[k] = raw['sourceText'] as String?;
        } else if (raw is bool) {
          _symptomsState[k] = raw;
        }
      } else {
        _symptomsState[k] = null;
        _symptomsTrace[k] = null;
      }
    });

    // Auto-generate clinical summary if not already present
    final initialSummary = widget.draftNote?.clinicalSummary.isNotEmpty == true
        ? widget.draftNote!.clinicalSummary
        : _buildDefaultSummary();
    _summaryCtrl = TextEditingController(text: initialSummary);
  }

  @override
  void dispose() {
    _transcriptCtrl.dispose();
    _summaryCtrl.dispose();
    _observationsCtrl.dispose();
    _interventionsCtrl.dispose();
    _responseCtrl.dispose();
    super.dispose();
  }

  String _buildDefaultSummary() {
    final present = _symptomsState.entries
        .where((e) => e.value == true)
        .map((e) => _symptomLabels[e.key] ?? e.key)
        .toList();
    final negated = _symptomsState.entries
        .where((e) => e.value == false)
        .map((e) => _symptomLabels[e.key] ?? e.key)
        .toList();

    final parts = <String>[];
    if (present.isNotEmpty) parts.add('Present symptoms: ${present.join(', ')}.');
    if (negated.isNotEmpty) parts.add('Denies: ${negated.join(', ')}.');
    if (parts.isEmpty) return widget.reviewedTranscript;
    return parts.join(' ');
  }

  Map<String, dynamic> _buildSymptomsPayload() {
    final map = <String, dynamic>{};
    _symptomsState.forEach((k, val) {
      if (val != null) {
        map[k] = {
          'value': val,
          'status': val ? 'present' : 'negated',
          'sourceText': _symptomsTrace[k] ?? '',
        };
      }
    });
    return map;
  }

  Future<void> _saveDraft() async {
    setState(() => _saving = true);
    try {
      final payload = {
        if (widget.draftNote?.noteId != null) 'noteId': widget.draftNote!.noteId,
        'patientId': widget.patientId,
        'noteType': widget.noteType.firestoreValue,
        'rawTranscription': widget.rawTranscription,
        'nurseReviewedTranscript': _transcriptCtrl.text.trim(),
        'clinicalSummary': _summaryCtrl.text.trim(),
        'supportedExtractedSymptoms': _buildSymptomsPayload(),
        'narrativeObservations': _observationsCtrl.text.trim(),
        'careInterventions': _interventionsCtrl.text.trim(),
        'treatmentResponseNarrative': _responseCtrl.text.trim(),
        if (widget.amendmentOf != null) 'amendmentOf': widget.amendmentOf,
      };

      await _nurseService.saveClinicalNoteDraft(payload);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Note draft saved successfully ✓', style: GoogleFonts.inter(fontSize: 13)),
            backgroundColor: OV.slateDark,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context); // Pop review screen
        Navigator.pop(context); // Pop dictation screen back to dashboard
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save draft: $e', style: GoogleFonts.inter(fontSize: 13)),
            backgroundColor: OV.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmAndSubmit() async {
    if (!_isConfirmed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please verify clinical accuracy and check the confirmation box before submitting.',
            style: GoogleFonts.inter(fontSize: 13),
          ),
          backgroundColor: OV.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final payload = {
        if (widget.draftNote?.noteId != null) 'noteId': widget.draftNote!.noteId,
        'patientId': widget.patientId,
        'noteType': widget.noteType.firestoreValue,
        'rawTranscription': widget.rawTranscription,
        'nurseReviewedTranscript': _transcriptCtrl.text.trim(),
        'clinicalSummary': _summaryCtrl.text.trim(),
        'supportedExtractedSymptoms': _buildSymptomsPayload(),
        'narrativeObservations': _observationsCtrl.text.trim(),
        'careInterventions': _interventionsCtrl.text.trim(),
        'treatmentResponseNarrative': _responseCtrl.text.trim(),
        if (widget.amendmentOf != null) 'amendmentOf': widget.amendmentOf,
      };

      await _nurseService.submitClinicalNote(payload);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.amendmentOf != null
                  ? 'Clinical amendment committed to EHR successfully ✓'
                  : 'Clinical note committed to EHR successfully ✓',
              style: GoogleFonts.inter(fontSize: 13),
            ),
            backgroundColor: const Color(0xFF1B6B3A),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to commit note to EHR: $e', style: GoogleFonts.inter(fontSize: 13)),
            backgroundColor: OV.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OV.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: OV.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Review & Confirm Note',
          style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700, color: OV.onSurface),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: OV.outlineVariant.withOpacity(0.5)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: OV.tertiaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        widget.noteType.label,
                        style: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w700, color: OV.tertiary),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Patient: ${widget.patientName}',
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: OV.onSurface),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (widget.amendmentOf != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'AMENDMENT',
                          style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, color: const Color(0xFF92400E)),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // ── 1. Reviewed Transcription ──────────────────────────
              Text(
                '1. REVIEWED TRANSCRIPTION',
                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: OV.outline),
              ),
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: OV.outlineVariant.withOpacity(0.6)),
                ),
                child: TextField(
                  controller: _transcriptCtrl,
                  maxLines: 4,
                  style: GoogleFonts.inter(fontSize: 13, height: 1.4, color: OV.onSurface),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(12),
                  ),
                ),
              ),

              const SizedBox(height: 18),

              // ── 2. Extracted Symptoms Review ────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '2. EXTRACTED SYMPTOMS (TAP TO TOGGLE)',
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: OV.outline),
                  ),
                  Text(
                    'Green: Present • Red: Denied',
                    style: GoogleFonts.inter(fontSize: 10, color: OV.onSurfaceVariant),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _symptomLabels.entries.map((entry) {
                  final key = entry.key;
                  final label = entry.value;
                  final state = _symptomsState[key];

                  Color chipColor;
                  Color textColor;
                  Color borderColor;
                  IconData? icon;

                  if (state == true) {
                    chipColor = const Color(0xFFE8F5E9);
                    textColor = const Color(0xFF1B6B3A);
                    borderColor = const Color(0xFF1B6B3A).withOpacity(0.4);
                    icon = Icons.check_circle_rounded;
                  } else if (state == false) {
                    chipColor = const Color(0xFFFFEBEE);
                    textColor = const Color(0xFFC62828);
                    borderColor = const Color(0xFFC62828).withOpacity(0.4);
                    icon = Icons.cancel_rounded;
                  } else {
                    chipColor = Colors.white;
                    textColor = OV.onSurfaceVariant;
                    borderColor = OV.outlineVariant;
                    icon = null;
                  }

                  return InkWell(
                    onTap: () {
                      setState(() {
                        if (_symptomsState[key] == null) {
                          _symptomsState[key] = true;
                        } else if (_symptomsState[key] == true) {
                          _symptomsState[key] = false;
                        } else {
                          _symptomsState[key] = null;
                        }
                        _summaryCtrl.text = _buildDefaultSummary();
                      });
                    },
                    borderRadius: BorderRadius.circular(100),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: chipColor,
                        borderRadius: BorderRadius.circular(100),
                        border: Border.all(color: borderColor),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (icon != null) ...[
                            Icon(icon, size: 14, color: textColor),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            label,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: state != null ? FontWeight.w700 : FontWeight.w500,
                              color: textColor,
                              decoration: state == false ? TextDecoration.lineThrough : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 18),

              // ── 3. Clinical Observations & Physical Findings ────────
              Text(
                '3. CLINICAL FINDINGS & OBSERVATIONS',
                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: OV.outline),
              ),
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: OV.outlineVariant.withOpacity(0.6)),
                ),
                child: TextField(
                  controller: _observationsCtrl,
                  maxLines: 3,
                  style: GoogleFonts.inter(fontSize: 13, height: 1.4, color: OV.onSurface),
                  decoration: const InputDecoration(
                    hintText: 'e.g. Oral mucosa intact, IV peripheral line patent, no edema.',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(12),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ── 4. Nursing Care Interventions ──────────────────────
              Text(
                '4. NURSING CARE INTERVENTIONS',
                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: OV.outline),
              ),
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: OV.outlineVariant.withOpacity(0.6)),
                ),
                child: TextField(
                  controller: _interventionsCtrl,
                  maxLines: 3,
                  style: GoogleFonts.inter(fontSize: 13, height: 1.4, color: OV.onSurface),
                  decoration: const InputDecoration(
                    hintText: 'e.g. IV normal saline infusion at 75 mL/hr, ondansetron 4mg administered per doctor order.',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(12),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ── 5. Treatment Response Narrative ─────────────────────
              Text(
                '5. TREATMENT RESPONSE / PATIENT STATUS',
                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: OV.outline),
              ),
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: OV.outlineVariant.withOpacity(0.6)),
                ),
                child: TextField(
                  controller: _responseCtrl,
                  maxLines: 2,
                  style: GoogleFonts.inter(fontSize: 13, height: 1.4, color: OV.onSurface),
                  decoration: const InputDecoration(
                    hintText: 'e.g. Patient reports nausea subsided. Alert and resting comfortably.',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(12),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ── 6. Clinical Summary (Final Narrative) ───────────────
              Text(
                '6. CONSOLIDATED CLINICAL SUMMARY',
                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: OV.outline),
              ),
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: OV.outlineVariant.withOpacity(0.6)),
                ),
                child: TextField(
                  controller: _summaryCtrl,
                  maxLines: 3,
                  style: GoogleFonts.inter(fontSize: 13, height: 1.4, color: OV.onSurface),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(12),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Explicit Human Confirmation Checkbox
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _isConfirmed ? const Color(0xFF1B6B3A) : OV.outlineVariant,
                    width: _isConfirmed ? 1.5 : 1.0,
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _isConfirmed,
                    onChanged: (val) => setState(() => _isConfirmed = val ?? false),
                    title: Text(
                      'I have reviewed and confirmed the clinical accuracy of these observations.',
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: OV.onSurface),
                    ),
                    subtitle: Text(
                      'Submitting creates an immutable, timestamped EHR entry and initiates blockchain proof anchoring.',
                      style: GoogleFonts.inter(fontSize: 11, color: OV.onSurfaceVariant),
                    ),
                    activeColor: const Color(0xFF1B6B3A),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Actions: Save Draft vs Confirm & Submit
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton(
                        onPressed: _saving ? null : _saveDraft,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: OV.slateDark,
                          side: BorderSide(color: OV.slateDark.withOpacity(0.6)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(
                          'Save Draft',
                          style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: _saving ? null : _confirmAndSubmit,
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : const Icon(Icons.check_circle_rounded, size: 18),
                        label: Text(
                          _saving
                              ? 'Committing...'
                              : widget.amendmentOf != null
                              ? 'Commit Amendment'
                              : 'Confirm & Submit',
                          style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isConfirmed ? const Color(0xFF1B6B3A) : OV.slateDark,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
