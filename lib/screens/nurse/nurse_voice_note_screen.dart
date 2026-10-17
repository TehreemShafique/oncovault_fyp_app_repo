// lib/screens/nurse/nurse_voice_note_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../config/api_config.dart';
import '../../models/clinical_note_model.dart';
import '../../services/audio_recorder_service.dart';
import '../../services/nlp_service.dart';
import 'nurse_note_review_screen.dart';

class NurseVoiceNoteScreen extends StatefulWidget {
  final String patientId;
  final String patientName;
  final String? doctorId;
  final String? doctorName;
  final ClinicalNoteType initialNoteType;
  final ClinicalNoteModel? draftNote;
  final String? amendmentOf;

  const NurseVoiceNoteScreen({
    super.key,
    required this.patientId,
    required this.patientName,
    this.doctorId,
    this.doctorName,
    this.initialNoteType = ClinicalNoteType.progressNote,
    this.draftNote,
    this.amendmentOf,
  });

  @override
  State<NurseVoiceNoteScreen> createState() => _NurseVoiceNoteScreenState();
}

class _NurseVoiceNoteScreenState extends State<NurseVoiceNoteScreen>
    with SingleTickerProviderStateMixin {
  final _recorderService = AudioRecorderService();
  final _nlpService = NlpService();
  final _transcriptCtrl = TextEditingController();

  late ClinicalNoteType _selectedNoteType;
  bool _isRecording = false;
  bool _isTranscribing = false;
  bool _isAnalyzing = false;
  int _recordSeconds = 0;
  Timer? _recordTimer;
  String _statusMessage = 'Tap the microphone and begin dictating clinical observations.';
  late AnimationController _pulseController;

  final List<Map<String, String>> _sampleDictations = [
    {
      'title': 'Morning Shift Intake',
      'text':
          'Morning oncology intake. Patient reports mild persistent weakness and nausea following last chemo cycle. Denies fever or chills. Oral mucosa intact, skin free of rash.',
    },
    {
      'title': 'Blood Transfusion Progress',
      'text':
          'Patient receiving packed red blood cells. Complains of mild shortness of breath and fatigue. Denies bone pain or dizziness. Pre-transfusion vitals stable.',
    },
    {
      'title': 'Neutropenic Vigilance',
      'text':
          'Patient in profound neutropenia. Reports sudden shivering and persistent fever. Complains of bone pain. Denies headache or visual blurring. Attending physician alerted.',
    },
  ];

  @override
  void initState() {
    super.initState();
    _selectedNoteType = widget.draftNote?.noteType ?? widget.initialNoteType;
    if (widget.draftNote != null) {
      _transcriptCtrl.text = widget.draftNote!.nurseReviewedTranscript.isNotEmpty
          ? widget.draftNote!.nurseReviewedTranscript
          : widget.draftNote!.rawTranscription;
    }

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _pulseController.dispose();
    _recorderService.cancelRecording();
    _transcriptCtrl.dispose();
    super.dispose();
  }

  String _formatTimer(int totalSecs) {
    final m = (totalSecs ~/ 60).toString().padLeft(2, '0');
    final s = (totalSecs % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _toggleRecording() async {
    if (_isTranscribing || _isAnalyzing) return;

    if (_isRecording) {
      _recordTimer?.cancel();
      _pulseController.stop();
      _pulseController.reset();
      setState(() {
        _isRecording = false;
        _isTranscribing = true;
        _statusMessage = 'Processing speech with Whisper speech-to-text...';
      });

      String? tempFilePath;
      try {
        final recordedResult = await _recorderService.stopRecording();
        if (recordedResult == null) {
          if (mounted) {
            setState(() {
              _isTranscribing = false;
              _statusMessage = 'Recording was empty. Please speak clearly.';
            });
          }
          return;
        }

        tempFilePath = recordedResult.filePath;

        final transcript = await _nlpService.transcribeAudio(
          filePath: recordedResult.filePath,
          audioBytes: recordedResult.bytes,
          fileName: recordedResult.fileName,
          patientId: widget.patientId,
        );

        if (mounted) {
          setState(() {
            final clean = transcript.trim();
            if (clean.isEmpty) {
              _statusMessage = 'No clear speech detected. Please speak into the microphone.';
            } else {
              final previous = _transcriptCtrl.text.trim();
              _transcriptCtrl.text = previous.isEmpty ? clean : '$previous $clean';
              _statusMessage = 'Transcription complete ✓ Please review and correct any errors below.';
            }
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _statusMessage = 'Transcription service unavailable: $e';
          });
          _showServiceErrorDialog(e.toString());
        }
      } finally {
        // Guarantee cleanup of client-side temporary recording file
        if (tempFilePath != null) {
          await _recorderService.deleteAudioFile(tempFilePath);
        }
        if (mounted) setState(() => _isTranscribing = false);
      }
    } else {
      final started = await _recorderService.startRecording();
      if (!started) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Microphone permission is required. Please enable microphone access in device settings or type directly.',
                style: GoogleFonts.inter(fontSize: 13),
              ),
              backgroundColor: OV.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      _pulseController.repeat(reverse: true);
      setState(() {
        _isRecording = true;
        _recordSeconds = 0;
        _statusMessage = 'Recording in progress... Speak patient observations clearly.';
      });

      _recordTimer?.cancel();
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (mounted && _isRecording) {
          setState(() => _recordSeconds++);
        }
      });
    }
  }

  Future<void> _proceedToNlpReview() async {
    final text = _transcriptCtrl.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please record voice dictation or enter clinical notes before analyzing.',
            style: GoogleFonts.inter(fontSize: 13),
          ),
          backgroundColor: OV.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (_isRecording) {
      _recordTimer?.cancel();
      await _recorderService.cancelRecording();
      setState(() => _isRecording = false);
    }

    setState(() => _isAnalyzing = true);

    try {
      final response = await _nlpService.extractClinicalInformation(
        text,
        patientId: widget.patientId,
      );

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => NurseNoteReviewScreen(
              patientId: widget.patientId,
              patientName: widget.patientName,
              doctorId: widget.doctorId,
              doctorName: widget.doctorName,
              noteType: _selectedNoteType,
              rawTranscription: text,
              reviewedTranscript: text,
              extraction: response,
              draftNote: widget.draftNote,
              amendmentOf: widget.amendmentOf,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _showServiceErrorDialog(e.toString());
      }
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  void _showServiceErrorDialog(String errorMsg) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.cloud_off_rounded, color: OV.error, size: 24),
            const SizedBox(width: 10),
            Text('Clinical Voice Service', style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(errorMsg, style: GoogleFonts.inter(fontSize: 13, height: 1.5, color: OV.onSurface)),
            const SizedBox(height: 14),
            Text('Server endpoint: ${ApiConfig.nlpBaseUrl}', style: GoogleFonts.inter(fontSize: 12, color: OV.onSurfaceVariant)),
            const SizedBox(height: 8),
            Text('You can continue documenting by typing directly in the text field below.',
                style: GoogleFonts.inter(fontSize: 12, color: OV.primary, fontWeight: FontWeight.w500)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Continue Manual Entry', style: GoogleFonts.manrope(fontWeight: FontWeight.w700, color: OV.primary)),
          ),
        ],
      ),
    );
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
          'Nurse Voice Documentation',
          style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700, color: OV.onSurface),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Patient Banner
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
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: OV.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.person_rounded, color: OV.primary, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.patientName,
                            style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700, color: OV.onSurface),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Patient ID: ${widget.patientId}',
                            style: GoogleFonts.inter(fontSize: 11, color: OV.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: OV.primaryContainer,
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        'Assigned',
                        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: OV.primary),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Note Type Selector
              Text(
                'DOCUMENTATION TYPE',
                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: OV.outline),
              ),
              const SizedBox(height: 8),
              Row(
                children: ClinicalNoteType.values.map((type) {
                  final isSelected = _selectedNoteType == type;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Center(
                          child: Text(
                            type.label,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                              color: isSelected ? Colors.white : OV.onSurface,
                            ),
                          ),
                        ),
                        selected: isSelected,
                        selectedColor: OV.slateDark,
                        backgroundColor: Colors.white,
                        onSelected: (val) {
                          if (val) setState(() => _selectedNoteType = type);
                        },
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 20),

              // Voice Recording Card
              Container(
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: OV.outlineVariant.withOpacity(0.5)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.02),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    if (_isRecording) ...[
                      Text(
                        _formatTimer(_recordSeconds),
                        style: GoogleFonts.manrope(fontSize: 32, fontWeight: FontWeight.w700, color: OV.error),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Recording in progress • Tap button to finish dictation',
                        style: GoogleFonts.inter(fontSize: 12, color: OV.error, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 18),
                    ] else ...[
                      Text(
                        _isTranscribing
                            ? 'Transcribing audio...'
                            : _isAnalyzing
                            ? 'Analyzing concepts...'
                            : 'Voice Dictation',
                        style: GoogleFonts.manrope(fontSize: 17, fontWeight: FontWeight.w700, color: OV.onSurface),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _statusMessage,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(fontSize: 12, color: OV.onSurfaceVariant, height: 1.4),
                      ),
                      const SizedBox(height: 18),
                    ],

                    // Microphone Action Button
                    Center(
                      child: AnimatedBuilder(
                        animation: _pulseController,
                        builder: (_, child) => Transform.scale(
                          scale: _isRecording ? (1.0 + _pulseController.value * 0.12) : 1.0,
                          child: child,
                        ),
                        child: GestureDetector(
                          onTap: _toggleRecording,
                          child: Container(
                            width: 84,
                            height: 84,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _isRecording ? OV.error : OV.slateDark,
                              boxShadow: [
                                BoxShadow(
                                  color: (_isRecording ? OV.error : OV.slateDark).withOpacity(0.3),
                                  blurRadius: 20,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: _isTranscribing
                                ? const Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                                : Icon(
                                    _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                                    color: Colors.white,
                                    size: 40,
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Sample Clinical Dictations Chips
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(
                  'Sample Clinical Dictations',
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: OV.primary),
                ),
                children: _sampleDictations.map((sample) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: OV.primaryContainer.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: OV.primary.withOpacity(0.2)),
                    ),
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _transcriptCtrl.text = sample['text']!;
                          _statusMessage = 'Sample loaded ✓ Review and proceed to clinical analysis.';
                        });
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                sample['title']!,
                                style: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w700, color: OV.primary),
                              ),
                              Text('Tap to Insert', style: GoogleFonts.inter(fontSize: 10, color: OV.primary)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            sample['text']!,
                            style: GoogleFonts.inter(fontSize: 11, color: OV.onSurfaceVariant, height: 1.3),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 12),

              // Transcription & Human-in-the-Loop Review
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'TRANSCRIPTION / CLINICAL OBSERVATIONS',
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: OV.outline),
                  ),
                  if (_transcriptCtrl.text.isNotEmpty)
                    TextButton(
                      onPressed: () => setState(() => _transcriptCtrl.clear()),
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                      child: Text('Clear', style: GoogleFonts.inter(fontSize: 11, color: OV.error)),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: OV.outlineVariant.withOpacity(0.6)),
                ),
                child: TextField(
                  controller: _transcriptCtrl,
                  maxLines: 6,
                  style: GoogleFonts.inter(fontSize: 13, height: 1.5, color: OV.onSurface),
                  decoration: InputDecoration(
                    hintText:
                        'Transcription will appear here. You can edit any unrecognized medical terms, dosage details, or type notes manually.',
                    hintStyle: GoogleFonts.inter(fontSize: 13, color: OV.outline),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(14),
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // Human Review Notice
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, color: Color(0xFF92400E), size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'SDS Protocol: Review and verify transcription accuracy before clinical entity extraction.',
                        style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF92400E)),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Action Button: Proceed to Step 2 NLP Review
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _isAnalyzing || _isTranscribing ? null : _proceedToNlpReview,
                  icon: _isAnalyzing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome_rounded, size: 18),
                  label: Text(
                    _isAnalyzing ? 'Extracting Clinical Concepts...' : 'Analyze & Review Clinical Concepts',
                    style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: OV.slateDark,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
}
