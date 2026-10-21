// lib/screens/doctor/voice_transcription_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../config/api_config.dart';
import '../../services/audio_recorder_service.dart';
import '../../services/nlp_service.dart';
import '../../models/blood_cancer_ehr_model.dart';
import 'nlp_review_screen.dart';

/// Formats the title for display without changing the stored name.
String formatAttendingDoctorName(String name) {
  final untitled = name
      .trim()
      .replaceFirst(
          RegExp(r'^(?:dr(?:\s*[.,]+\s*|\s+|$))+', caseSensitive: false), '')
      .trim();
  return untitled.isEmpty ? 'Not recorded' : 'Dr. $untitled';
}

class VoiceTranscriptionScreen extends StatefulWidget {
  final String patientId;
  final String patientName;
  final String doctorId;
  final String doctorName;
  final BloodCancerEhrModel? currentEhr;

  const VoiceTranscriptionScreen({
    super.key,
    required this.patientId,
    required this.patientName,
    required this.doctorId,
    required this.doctorName,
    this.currentEhr,
  });

  @override
  State<VoiceTranscriptionScreen> createState() =>
      _VoiceTranscriptionScreenState();
}

class _VoiceTranscriptionScreenState extends State<VoiceTranscriptionScreen>
    with SingleTickerProviderStateMixin {
  final _recorderService = AudioRecorderService();
  final _nlpService = NlpService();
  final _transcriptCtrl = TextEditingController();

  bool _isRecording = false;
  bool _isTranscribing = false;
  bool _isAnalyzing = false;
  int _recordSeconds = 0;
  Timer? _recordTimer;
  String _statusMessage =
      'Tap the microphone and begin speaking clinical findings.';
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
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
      // ── Stop Recording & Transcribe with Whisper ──────────
      _recordTimer?.cancel();
      setState(() {
        _isRecording = false;
        _isTranscribing = true;
        _statusMessage = 'Processing clinical voice note...';
      });

      try {
        final recordedResult = await _recorderService.stopRecording();
        if (recordedResult == null) {
          if (mounted) {
            setState(() {
              _isTranscribing = false;
              _statusMessage =
                  'Recording was empty. Please try speaking again.';
            });
          }
          return;
        }

        final transcript = await _nlpService.transcribeAudio(
          filePath: recordedResult.filePath,
          audioBytes: recordedResult.bytes,
          fileName: recordedResult.fileName,
        );

        if (mounted) {
          setState(() {
            final cleanTranscript = transcript.trim();
            if (cleanTranscript.isEmpty) {
              _statusMessage =
                  'No clear speech detected in recording. Please try speaking again.';
            } else {
              final previous = _transcriptCtrl.text.trim();
              if (previous.isEmpty) {
                _transcriptCtrl.text = cleanTranscript;
              } else {
                _transcriptCtrl.text = '$previous $cleanTranscript';
              }
              _statusMessage =
                  'Transcription complete ✓ You can review or edit before analysis.';
            }
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _statusMessage = 'Transcription error: $e';
          });
          _showServiceErrorDialog(e.toString());
        }
      } finally {
        if (mounted) setState(() => _isTranscribing = false);
      }
    } else {
      // ── Start Recording ──────────────────────────────────
      final started = await _recorderService.startRecording();
      if (!started) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Microphone access is unavailable. Please check microphone permissions or type directly.',
                style: GoogleFonts.inter(fontSize: 13),
              ),
              backgroundColor: OV.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      setState(() {
        _isRecording = true;
        _recordSeconds = 0;
        _statusMessage =
            'Recording in progress... Speak clinical notes clearly.';
      });

      _recordTimer?.cancel();
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (mounted && _isRecording) {
          setState(() => _recordSeconds++);
        }
      });
    }
  }

  Future<void> _analyzeTranscript() async {
    final text = _transcriptCtrl.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Please record or type clinical documentation before analyzing.',
              style: GoogleFonts.inter(fontSize: 13)),
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
      final response = await _nlpService.extractClinicalInformation(text);

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => NlpReviewScreen(
              patientId: widget.patientId,
              patientName: widget.patientName,
              doctorId: widget.doctorId,
              doctorName: widget.doctorName,
              currentEhr: widget.currentEhr,
              extraction: response,
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
            Text('Clinical Service',
                style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w700, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(errorMsg,
                style: GoogleFonts.inter(
                    fontSize: 13, height: 1.5, color: OV.onSurface)),
            const SizedBox(height: 14),
            Text('Current server address: ${ApiConfig.nlpBaseUrl}',
                style: GoogleFonts.inter(
                    fontSize: 12, color: OV.onSurfaceVariant)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showServerSettingsDialog();
            },
            child: Text('Configure Server',
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600, color: OV.primary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: OV.slateDark,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('OK',
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600, color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showServerSettingsDialog() {
    final ctrl = TextEditingController(text: ApiConfig.nlpBaseUrl);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Clinical Server Connection',
            style:
                GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'Set local or remote address for the clinical documentation server:',
                style: GoogleFonts.inter(
                    fontSize: 13, color: OV.onSurfaceVariant)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              decoration: InputDecoration(
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                hintText:
                    'e.g. http://10.0.2.2:8000 or http://192.168.1.5:8000',
              ),
              style: GoogleFonts.inter(fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              ApiConfig.resetBaseUrl();
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Reset to default: ${ApiConfig.nlpBaseUrl}')));
            },
            child: Text('Reset Default',
                style: GoogleFonts.inter(fontSize: 12, color: OV.outline)),
          ),
          ElevatedButton(
            onPressed: () {
              if (ctrl.text.trim().isNotEmpty) {
                ApiConfig.setBaseUrl(ctrl.text.trim());
              }
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Updated to: ${ApiConfig.nlpBaseUrl}')));
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: OV.slateDark,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Save',
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600, color: Colors.white)),
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
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              size: 18, color: OV.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Voice Clinical Documentation',
          style: GoogleFonts.manrope(
              fontSize: 16, fontWeight: FontWeight.w700, color: OV.onSurface),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined,
                size: 20, color: OV.outline),
            tooltip: 'Server Settings',
            onPressed: _showServerSettingsDialog,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          // ── Patient Badge ──────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: OV.outlineVariant.withOpacity(0.4)),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: OV.primaryContainer.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.person_outline_rounded,
                      color: OV.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.patientName,
                          style: GoogleFonts.manrope(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: OV.onSurface)),
                      const SizedBox(height: 2),
                      Text(
                          'ID: ${widget.patientId} • Attending: ${formatAttendingDoctorName(widget.doctorName)}',
                          style: GoogleFonts.inter(
                              fontSize: 11, color: OV.outline)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Mic Button & Voice State ───────────────────────────
          Center(
            child: Column(
              children: [
                GestureDetector(
                  onTap: _toggleRecording,
                  child: AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      final scale = _isRecording
                          ? 1.0 + (_pulseController.value * 0.1)
                          : 1.0;
                      return Transform.scale(
                        scale: scale,
                        child: Container(
                          width: 84,
                          height: 84,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isRecording
                                ? OV.error
                                : _isTranscribing
                                    ? Colors.amber.shade700
                                    : OV.primary,
                            boxShadow: [
                              BoxShadow(
                                color: (_isRecording
                                        ? OV.error
                                        : _isTranscribing
                                            ? Colors.amber.shade700
                                            : OV.primary)
                                    .withOpacity(0.3),
                                blurRadius: _isRecording ? 20 : 12,
                                spreadRadius: _isRecording ? 4 : 1,
                              ),
                            ],
                          ),
                          child: _isTranscribing
                              ? const Center(
                                  child: SizedBox(
                                    width: 32,
                                    height: 32,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 3,
                                      color: Colors.white,
                                    ),
                                  ),
                                )
                              : Icon(
                                  _isRecording
                                      ? Icons.stop_rounded
                                      : Icons.mic_rounded,
                                  color: Colors.white,
                                  size: 40,
                                ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                if (_isRecording) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: OV.error,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Recording ${_formatTimer(_recordSeconds)}',
                        style: GoogleFonts.manrope(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: OV.error,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tap to stop recording',
                    style: GoogleFonts.inter(
                        fontSize: 12, color: OV.onSurfaceVariant),
                  ),
                ] else if (_isTranscribing) ...[
                  Text(
                    'Processing Audio...',
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.amber.shade800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Converting voice to clinical transcript...',
                    style: GoogleFonts.inter(
                        fontSize: 12, color: OV.onSurfaceVariant),
                  ),
                ] else ...[
                  Text(
                    'Tap to Record Clinical Voice Note',
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: OV.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _statusMessage,
                    style: GoogleFonts.inter(
                        fontSize: 12, color: OV.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Editable Transcript Section ────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: OV.outlineVariant.withOpacity(0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                        child: Text(
                      'Clinical Voice Note Transcript',
                      style: GoogleFonts.manrope(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: OV.onSurface),
                    )),
                    if (_transcriptCtrl.text.isNotEmpty)
                      GestureDetector(
                        onTap: () => setState(() => _transcriptCtrl.clear()),
                        child: Text(
                          'Clear',
                          style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: OV.outline),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _transcriptCtrl,
                  maxLines: 6,
                  style: GoogleFonts.inter(
                      fontSize: 14, height: 1.5, color: OV.onSurface),
                  decoration: InputDecoration(
                    hintText:
                        'Voice transcription will appear here. You can edit text, correct numbers, or type clinical details directly...',
                    hintStyle: GoogleFonts.inter(
                        fontSize: 13, color: OV.outlineVariant),
                    border: InputBorder.none,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Process Button ─────────────────────────────────────
          ElevatedButton.icon(
            onPressed: (_isAnalyzing || _isTranscribing || _isRecording)
                ? null
                : _analyzeTranscript,
            icon: _isAnalyzing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.analytics_outlined, size: 20),
            label: Text(
              _isAnalyzing
                  ? 'Extracting Clinical Concepts...'
                  : 'Extract Clinical Information',
              style: GoogleFonts.manrope(
                  fontSize: 14, fontWeight: FontWeight.w700),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: OV.slateDark,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
          ),

          const SizedBox(height: 30),
        ],
      ),
    );
  }
}
