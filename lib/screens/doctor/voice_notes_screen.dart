// lib/screens/doctor/voice_notes_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import 'doctor_widgets.dart';

class VoiceNotesScreen extends StatefulWidget {
  final String patientId, patientName;
  final ValueChanged<String> onNoteAdded;
  const VoiceNotesScreen({super.key, required this.patientId,
    required this.patientName, required this.onNoteAdded});
  @override
  State<VoiceNotesScreen> createState() => _VoiceNotesScreenState();
}

class _VoiceNotesScreenState extends State<VoiceNotesScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  bool _isListening = false;
  bool _hasResult   = false;
  String _transcription = '';
  final _manualCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.25)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _pulseCtrl.dispose(); _manualCtrl.dispose(); super.dispose(); }

  void _toggleListening() {
    setState(() { _isListening = !_isListening; _hasResult = false; });
    if (_isListening) {
      _pulseCtrl.repeat(reverse: true);
      // TODO: Integrate speech_to_text package here
      // speech.listen(onResult: (result) { setState(() { _transcription = result.recognizedWords; }); });
      Future.delayed(const Duration(seconds: 4), () {
        if (!mounted || !_isListening) return;
        setState(() {
          _isListening = false;
          _hasResult   = true;
          _transcription = 'Patient reports mild nausea following last chemo session. Appetite reduced by approximately 40%. Recommend anti-emetic before next cycle.';
          _manualCtrl.text = _transcription;
        });
        _pulseCtrl.stop();
        _pulseCtrl.reset();
      });
    } else {
      _pulseCtrl.stop();
      _pulseCtrl.reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: OV.background,
        body: SafeArea(child: Column(children: [

          // ── App Bar ──────────────────────────────────────────────
          DoctorAppBar(title: 'Voice Clinical Notes', showBack: true),
          const SizedBox(height: 8),

          // ── Patient tag ───────────────────────────────────────────
          Padding(padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: OV.primaryContainer, borderRadius: BorderRadius.circular(12)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.person_outline_rounded, size: 14, color: OV.primary),
                    const SizedBox(width: 6),
                    Text('Patient: ${widget.patientName}',
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: OV.primary)),
                  ]))),

          const SizedBox(height: 8),

          Expanded(child: SingleChildScrollView(padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(children: [

                // ── AI Engine badge ───────────────────────────────────
                DCard(child: Row(children: [
                  Container(width: 40, height: 40,
                      decoration: BoxDecoration(color: OV.primaryContainer, borderRadius: BorderRadius.circular(12)),
                      child: Icon(Icons.record_voice_over_rounded, color: OV.primary, size: 20)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text('AI ENGINE ACTIVE', style: GoogleFonts.inter(
                          fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1, color: OV.tertiary)),
                      const SizedBox(width: 6),
                      Container(width: 6, height: 6, decoration: const BoxDecoration(
                          color: OV.tertiary, shape: BoxShape.circle)),
                    ]),
                    Text('V4.2 Oncology NLP Core', style: GoogleFonts.manrope(
                        fontSize: 13, fontWeight: FontWeight.w700, color: OV.onSurface)),
                  ])),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                          color: const Color(0xFFFFF3E0), borderRadius: BorderRadius.circular(100)),
                      child: Text('COMING SOON', style: GoogleFonts.inter(
                          fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.5,
                          color: const Color(0xFF8B5000)))),
                ])),

                const SizedBox(height: 24),

                // ── Mic Button ────────────────────────────────────────
                Center(child: Column(children: [
                  AnimatedBuilder(
                      animation: _pulseAnim,
                      builder: (_, child) => Transform.scale(
                          scale: _isListening ? _pulseAnim.value : 1.0, child: child),
                      child: GestureDetector(
                          onTap: _toggleListening,
                          child: Container(width: 120, height: 120,
                              decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _isListening ? OV.error : OV.slateDark,
                                  boxShadow: [BoxShadow(
                                      color: (_isListening ? OV.error : OV.primary).withOpacity(0.35),
                                      blurRadius: 30, spreadRadius: 4)]),
                              child: Icon(_isListening ? Icons.stop_rounded : Icons.mic_rounded,
                                  color: Colors.white, size: 52)))),
                  const SizedBox(height: 16),
                  Text(
                      _isListening ? 'Listening… tap to stop'
                          : _hasResult ? 'Tap to record again'
                          : 'Tap microphone to begin',
                      style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600,
                          color: _isListening ? OV.error : OV.onSurfaceVariant)),
                ])),

                const SizedBox(height: 28),

                // ── Live waveform visual ──────────────────────────────
                if (_isListening)
                  _WaveformVisual(),

                // ── Transcription ─────────────────────────────────────
                if (_hasResult || _transcription.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Container(padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: OV.primaryContainer.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: OV.primary.withOpacity(0.2))),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Icon(Icons.auto_awesome_rounded, size: 14, color: OV.primary),
                          const SizedBox(width: 6),
                          Text('Transcription', style: GoogleFonts.manrope(
                              fontSize: 13, fontWeight: FontWeight.w700, color: OV.primary)),
                        ]),
                        const SizedBox(height: 8),
                        Text(_transcription, style: GoogleFonts.inter(
                            fontSize: 13, color: OV.onSurface, height: 1.6)),
                      ])),
                  const SizedBox(height: 16),
                ],

                // ── Manual edit area ──────────────────────────────────
                Container(padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: OV.outlineVariant.withOpacity(0.5))),
                    child: TextField(
                        controller: _manualCtrl,
                        maxLines: 6, minLines: 4,
                        style: GoogleFonts.inter(fontSize: 14, color: OV.onSurface),
                        decoration: InputDecoration(
                            hintText: _isListening
                                ? 'Transcription will appear here...'
                                : 'Type or dictate clinical notes...',
                            hintStyle: GoogleFonts.inter(fontSize: 13, color: OV.outline),
                            filled: true, fillColor: Colors.white,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                            contentPadding: const EdgeInsets.all(14)))),

                const SizedBox(height: 16),

                // Quick phrase chips
                Text('Quick Phrases', style: GoogleFonts.inter(
                    fontSize: 12, fontWeight: FontWeight.w600, color: OV.onSurfaceVariant)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  'Patient tolerating well', 'No adverse effects', 'Nausea reported',
                  'Follow-up in 2 weeks', 'CBC ordered', 'Referral made',
                ].map((phrase) => GestureDetector(
                    onTap: () => setState(() =>
                    _manualCtrl.text += (_manualCtrl.text.isEmpty ? '' : ' ') + phrase + '.'),
                    child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(100),
                            border: Border.all(color: OV.outlineVariant.withOpacity(0.6))),
                        child: Text(phrase, style: GoogleFonts.inter(
                            fontSize: 11, fontWeight: FontWeight.w500, color: OV.onSurface))))).toList()),

                const SizedBox(height: 24),
              ]))),

          // ── Bottom Action ─────────────────────────────────────────
          Container(padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              decoration: BoxDecoration(color: Colors.white,
                  border: Border(top: BorderSide(color: OV.outlineVariant.withOpacity(0.4)))),
              child: Row(children: [
                OutlinedButton(
                    onPressed: () => setState(() { _manualCtrl.clear(); _transcription = ''; _hasResult = false; }),
                    style: OutlinedButton.styleFrom(foregroundColor: OV.onSurface,
                        side: BorderSide(color: OV.outlineVariant),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16)),
                    child: Text('Clear', style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700))),
                const SizedBox(width: 12),
                Expanded(child: ElevatedButton.icon(
                    onPressed: _manualCtrl.text.trim().isEmpty ? null : () {
                      widget.onNoteAdded(_manualCtrl.text.trim());
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: Text('Add to Record', style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(backgroundColor: OV.slateDark, foregroundColor: Colors.white,
                        elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14)))),
              ])),
        ])));
  }
}

class _WaveformVisual extends StatefulWidget {
  @override
  State<_WaveformVisual> createState() => _WaveformVisualState();
}

class _WaveformVisualState extends State<_WaveformVisual> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _ctrl.repeat(reverse: true);
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Row(mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(20, (i) {
            final h = (20 + (i % 5 == 0 ? 30 : i % 3 == 0 ? 20 : 10) * _ctrl.value).clamp(8.0, 50.0);
            return Container(width: 4, height: h, margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(color: OV.primary.withOpacity(0.7 + 0.3 * _ctrl.value),
                    borderRadius: BorderRadius.circular(2)));
          })));
}