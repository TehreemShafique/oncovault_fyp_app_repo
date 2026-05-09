// lib/screens/doctor/ai_diagnosis_screen.dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import 'doctor_widgets.dart';

class AiDiagnosisScreen extends StatefulWidget {
  final String patientId, patientName;
  const AiDiagnosisScreen({super.key, required this.patientId, required this.patientName});
  @override
  State<AiDiagnosisScreen> createState() => _AiDiagnosisScreenState();
}

class _AiDiagnosisScreenState extends State<AiDiagnosisScreen>
    with SingleTickerProviderStateMixin {
  final _symptomsCtrl = TextEditingController();
  bool _analyzing     = false;
  bool _hasResult     = false;
  late AnimationController _progressCtrl;
  late Animation<double>   _progressAnim;

  @override
  void initState() {
    super.initState();
    _progressCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
    _progressAnim = Tween<double>(begin: 0, end: 0.88)
        .animate(CurvedAnimation(parent: _progressCtrl, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() { _symptomsCtrl.dispose(); _progressCtrl.dispose(); super.dispose(); }

  Future<void> _analyze() async {
    if (_symptomsCtrl.text.trim().isEmpty) return;
    setState(() { _analyzing = true; _hasResult = false; });
    _progressCtrl.forward(from: 0);
    await Future.delayed(const Duration(seconds: 3));
    if (!mounted) return;
    setState(() { _analyzing = false; _hasResult = true; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OV.background,
      body: SafeArea(child: Column(children: [
        DoctorAppBar(title: 'AI Diagnostic Assistant', showBack: true),

        Expanded(child: SingleChildScrollView(padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Header
              Text('AI Diagnostic\nAssistant', style: GoogleFonts.manrope(
                  fontSize: 28, fontWeight: FontWeight.w700, color: OV.onSurface,
                  height: 1.2, letterSpacing: -0.4)),
              const SizedBox(height: 6),
              Text('Analyze patient symptoms and biometric data using our advanced oncology-trained neural network for rapid clinical insight.',
                  style: GoogleFonts.inter(fontSize: 13, color: OV.onSurfaceVariant, height: 1.5)),
              const SizedBox(height: 16),

              // AI Engine badge
              DCard(child: Row(children: [
                Container(width: 40, height: 40,
                    decoration: BoxDecoration(color: OV.primaryContainer, borderRadius: BorderRadius.circular(12)),
                    child: Icon(Icons.psychology_rounded, color: OV.primary, size: 22)),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text('AI ENGINE ACTIVE', style: GoogleFonts.inter(
                        fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1, color: OV.tertiary)),
                    const SizedBox(width: 6),
                    Container(width: 6, height: 6, decoration: const BoxDecoration(
                        color: OV.tertiary, shape: BoxShape.circle)),
                  ]),
                  Text('V4.2 Oncology Core', style: GoogleFonts.manrope(
                      fontSize: 13, fontWeight: FontWeight.w700, color: OV.onSurface)),
                ]),
                const Spacer(),
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: const Color(0xFFFFF3E0), borderRadius: BorderRadius.circular(100)),
                    child: Text('COMING SOON', style: GoogleFonts.inter(
                        fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.5,
                        color: const Color(0xFF8B5000)))),
              ])),
              const SizedBox(height: 20),

              // Input form
              DCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Analyze Symptoms', style: GoogleFonts.manrope(
                    fontSize: 16, fontWeight: FontWeight.w700, color: OV.onSurface)),
                const SizedBox(height: 14),
                Text('SYMPTOM DESCRIPTION', style: GoogleFonts.inter(
                    fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: OV.outline)),
                const SizedBox(height: 8),
                TextField(
                    controller: _symptomsCtrl, maxLines: 5,
                    style: GoogleFonts.inter(fontSize: 13, color: OV.onSurface),
                    decoration: InputDecoration(
                        hintText: 'Describe clinical observations, patient discomfort, or radiological findings...',
                        hintStyle: GoogleFonts.inter(fontSize: 12, color: OV.outline),
                        filled: true, fillColor: OV.surfaceLow,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: OV.outlineVariant.withOpacity(0.6))),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: OV.outlineVariant.withOpacity(0.6))),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: OV.primary, width: 1.5)),
                        contentPadding: const EdgeInsets.all(14))),
                const SizedBox(height: 14),
                // Upload / Camera row
                Row(children: [
                  Expanded(child: _AttachButton(icon: Icons.upload_file_rounded, label: 'Upload Lab Results', action: 'Browse')),
                  const SizedBox(width: 10),
                  Expanded(child: _AttachButton(icon: Icons.camera_alt_outlined, label: 'Attach Scan Image', action: 'Camera')),
                ]),
                const SizedBox(height: 16),
                SizedBox(width: double.infinity, height: 50,
                    child: ElevatedButton.icon(
                        onPressed: _analyzing ? null : _analyze,
                        icon: _analyzing
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.auto_awesome_rounded, size: 18),
                        label: Text(_analyzing ? 'Analyzing...' : 'Analyze Clinical Data',
                            style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w700)),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: OV.primary, foregroundColor: Colors.white, elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))))),
              ])),

              if (_analyzing) ...[
                const SizedBox(height: 20),
                _AnalyzingLoader(animation: _progressAnim),
              ],

              if (_hasResult) ...[
                const SizedBox(height: 20),
                _ResultSection(),
                const SizedBox(height: 16),
                _ConfidenceCircle(),
                const SizedBox(height: 16),
                _NextStepsCard(),
              ],

              const SizedBox(height: 30),
            ]))),
      ])),
      floatingActionButton: FloatingActionButton(
          onPressed: () {},
          backgroundColor: OV.slateDark, foregroundColor: Colors.white,
          child: const Icon(Icons.picture_as_pdf_outlined)),
    );
  }
}

class _AttachButton extends StatelessWidget {
  final IconData icon; final String label, action;
  const _AttachButton({required this.icon, required this.label, required this.action});
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
      decoration: BoxDecoration(color: OV.surfaceLow, borderRadius: BorderRadius.circular(10),
          border: Border.all(color: OV.outlineVariant.withOpacity(0.5))),
      child: Row(children: [
        Icon(icon, size: 14, color: OV.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(child: Text(label, style: GoogleFonts.inter(fontSize: 10, color: OV.onSurface),
            maxLines: 1, overflow: TextOverflow.ellipsis)),
        Text(action, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: OV.primary)),
      ]));
}

class _AnalyzingLoader extends StatelessWidget {
  final Animation<double> animation;
  const _AnalyzingLoader({required this.animation});
  @override
  Widget build(BuildContext context) => DCard(child: Column(children: [
    Row(children: [
      const SizedBox(width: 8, height: 8, child: CircularProgressIndicator(strokeWidth: 2, color: OV.primary)),
      const SizedBox(width: 10),
      Text('AI is analyzing patient data...', style: GoogleFonts.inter(fontSize: 13, color: OV.primary, fontWeight: FontWeight.w600)),
    ]),
    const SizedBox(height: 12),
    AnimatedBuilder(animation: animation, builder: (_, __) =>
        ClipRRect(borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: animation.value, minHeight: 6,
                backgroundColor: OV.outlineVariant.withOpacity(0.3),
                valueColor: const AlwaysStoppedAnimation(OV.primary)))),
    const SizedBox(height: 8),
    Text('Cross-referencing 1.2M oncology cases...', style: GoogleFonts.inter(fontSize: 11, color: OV.onSurfaceVariant)),
  ]));
}

class _ResultSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: OV.primaryContainer, borderRadius: BorderRadius.circular(100)),
        child: Text('MOST LIKELY MATCH', style: GoogleFonts.inter(
            fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1, color: OV.primary))),
    const SizedBox(height: 10),
    Text('Stage II Adenocarcinoma', style: GoogleFonts.manrope(
        fontSize: 22, fontWeight: FontWeight.w700, color: OV.onSurface, letterSpacing: -0.3)),
    const SizedBox(height: 6),
    Text('Symptoms align with secondary progression patterns observed in 82% of similar histological profiles.',
        style: GoogleFonts.inter(fontSize: 13, color: OV.onSurfaceVariant, height: 1.5)),
    const SizedBox(height: 8),
    GestureDetector(onTap: () {},
        child: Row(children: [
          Text('View Deep Insight', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: OV.primary)),
          const SizedBox(width: 4),
          Icon(Icons.arrow_forward_rounded, size: 14, color: OV.primary),
        ])),
    const SizedBox(height: 16),
    Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: OV.secondaryContainer, borderRadius: BorderRadius.circular(100)),
        child: Text('COMPARATIVE DATA', style: GoogleFonts.inter(
            fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1, color: OV.secondary))),
    const SizedBox(height: 10),
    Text('Cohort Analysis', style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w700, color: OV.onSurface)),
    const SizedBox(height: 4),
    Text('Patient profiles within this demographic respond 15% better to targeted immunotherapy combinations.',
        style: GoogleFonts.inter(fontSize: 13, color: OV.onSurfaceVariant, height: 1.5)),
    const SizedBox(height: 6),
    GestureDetector(onTap: () {},
        child: Row(children: [
          Text('View Cohort Map', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: OV.primary)),
          const SizedBox(width: 4),
          Icon(Icons.grid_view_rounded, size: 14, color: OV.primary),
        ])),
  ]);
}

class _ConfidenceCircle extends StatelessWidget {
  @override
  Widget build(BuildContext context) => DCard(child: Column(children: [
    Text('CONFIDENCE SCORE', style: GoogleFonts.inter(
        fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1, color: OV.outline)),
    const SizedBox(height: 16),
    SizedBox(width: 140, height: 140, child: Stack(alignment: Alignment.center, children: [
      CustomPaint(size: const Size(140, 140), painter: _CirclePainter(progress: 0.88)),
      Column(mainAxisSize: MainAxisSize.min, children: [
        Text('88%', style: GoogleFonts.manrope(fontSize: 32, fontWeight: FontWeight.w800, color: OV.primary)),
        Text('HIGH PRECISION', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w800,
            letterSpacing: 0.5, color: OV.onSurfaceVariant)),
      ]),
    ])),
    const SizedBox(height: 12),
    Text('Based on 1.2M historical oncology cases\nand current patient biomarkers.',
        style: GoogleFonts.inter(fontSize: 12, color: OV.onSurfaceVariant, height: 1.4),
        textAlign: TextAlign.center),
  ]));
}

class _CirclePainter extends CustomPainter {
  final double progress;
  const _CirclePainter({required this.progress});
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;
    final bgPaint = Paint()..color = OV.outlineVariant.withOpacity(0.2)
      ..strokeWidth = 12 ..style = PaintingStyle.stroke ..strokeCap = StrokeCap.round;
    final fgPaint = Paint()..color = OV.primary ..strokeWidth = 12
      ..style = PaintingStyle.stroke ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, bgPaint);
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius),
        -pi / 2, 2 * pi * progress, false, fgPaint);
  }
  @override
  bool shouldRepaint(_) => false;
}

class _NextStepsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) => DCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text('Next Steps', style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700, color: OV.onSurface)),
    const SizedBox(height: 14),
    ...[
      {'num': '01', 'title': 'Verify with PET/CT', 'sub': 'Recommended for metabolic activity mapping in localized thoracic regions.'},
      {'num': '02', 'title': 'Consult Pathologist', 'sub': 'Share generated AI report with Dr. Aris Thorne for histological validation.'},
      {'num': '03', 'title': 'Schedule Biopsy', 'sub': 'Liquid biopsy suggested to monitor cell-free DNA fragments.'},
    ].map((step) => Padding(padding: const EdgeInsets.only(bottom: 14), child: Row(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: 28, height: 28,
          decoration: BoxDecoration(color: OV.primaryContainer, borderRadius: BorderRadius.circular(8)),
          child: Center(child: Text(step['num']!, style: GoogleFonts.manrope(
              fontSize: 11, fontWeight: FontWeight.w800, color: OV.primary)))),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(step['title']!, style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700, color: OV.onSurface)),
        const SizedBox(height: 2),
        Text(step['sub']!, style: GoogleFonts.inter(fontSize: 11, color: OV.onSurfaceVariant, height: 1.4)),
      ])),
    ]))),
    DividerLine(),
    const SizedBox(height: 10),
    GestureDetector(onTap: () {},
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.picture_as_pdf_outlined, size: 14, color: OV.primary),
          const SizedBox(width: 6),
          Text('Generate PDF Report', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: OV.primary)),
        ])),
  ]));
}