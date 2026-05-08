import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import 'profile_selection_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _iconCtrl, _textCtrl, _bottomCtrl;
  late Animation<double> _iconScale, _iconOpacity, _textOpacity, _bottomOpacity;
  late Animation<Offset> _textSlide;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent, statusBarIconBrightness: Brightness.dark));

    _iconCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _iconScale   = Tween<double>(begin: 0.6, end: 1.0).animate(CurvedAnimation(parent: _iconCtrl, curve: Curves.elasticOut));
    _iconOpacity = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _iconCtrl, curve: const Interval(0.0, 0.4, curve: Curves.easeIn)));

    _textCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _textOpacity = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _textCtrl, curve: Curves.easeOut));
    _textSlide   = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(CurvedAnimation(parent: _textCtrl, curve: Curves.easeOut));

    _bottomCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _bottomOpacity = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _bottomCtrl, curve: Curves.easeOut));

    _run();
  }

  Future<void> _run() async {
    await Future.delayed(const Duration(milliseconds: 200));
    _iconCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 500));
    _textCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 400));
    _bottomCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 1800));
    if (mounted) {
      Navigator.of(context).pushReplacement(PageRouteBuilder(
        pageBuilder: (_, a, __) => const ProfileSelectionScreen(),
        transitionDuration: const Duration(milliseconds: 600),
        transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
      ));
    }
  }

  @override
  void dispose() { _iconCtrl.dispose(); _textCtrl.dispose(); _bottomCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: OV.splashGrad),
        child: SafeArea(child: Column(children: [
          const Spacer(flex: 3),
          AnimatedBuilder(animation: _iconCtrl, builder: (_, child) =>
              Opacity(opacity: _iconOpacity.value, child: Transform.scale(scale: _iconScale.value, child: child)),
              child: _AppIcon()),
          const SizedBox(height: 48),
          AnimatedBuilder(animation: _textCtrl, builder: (_, child) =>
              Opacity(opacity: _textOpacity.value, child: SlideTransition(position: _textSlide, child: child)),
              child: Column(children: [
                Text('OncoVault', style: GoogleFonts.manrope(fontSize: 42, fontWeight: FontWeight.w700, color: OV.onSurface, letterSpacing: -0.5)),
                const SizedBox(height: 12),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 48),
                    child: Text('Restorative care through immutable security\nand clinical precision.',
                        style: GoogleFonts.inter(fontSize: 15, color: OV.onSurfaceVariant, height: 1.6),
                        textAlign: TextAlign.center)),
              ])),
          const SizedBox(height: 40),
          AnimatedBuilder(animation: _textCtrl, builder: (_, __) =>
              Opacity(opacity: _textOpacity.value,
                  child: Container(width: 40, height: 4, decoration: BoxDecoration(color: OV.outlineVariant, borderRadius: BorderRadius.circular(2))))),
          const Spacer(flex: 2),
          AnimatedBuilder(animation: _bottomCtrl, builder: (_, child) =>
              Opacity(opacity: _bottomOpacity.value, child: child), child: _BottomBadge()),
          const SizedBox(height: 32),
        ])),
      ),
    );
  }
}

class _AppIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
      width: 120, height: 120,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(color: OV.primary.withOpacity(0.12), blurRadius: 40, offset: const Offset(0, 12)),
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 4)),
          ]),
      child: Stack(children: [
        Center(child: Container(width: 72, height: 72,
            decoration: BoxDecoration(color: OV.slateDark, borderRadius: BorderRadius.circular(20)),
            child: const Icon(Icons.person_outline_rounded, color: Colors.white, size: 36))),
        Positioned(top: 8, right: 8, child: Container(width: 28, height: 28,
            decoration: BoxDecoration(color: OV.tertiaryContainer, shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2)),
            child: const Icon(Icons.verified_rounded, color: Color(0xFF52625C), size: 16))),
      ]));
}

class _BottomBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Column(children: [
    Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.7), borderRadius: BorderRadius.circular(100),
            border: Border.all(color: OV.outlineVariant.withOpacity(0.5)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 16, offset: const Offset(0, 4))]),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.hub_rounded, size: 16, color: OV.onSurfaceVariant),
          const SizedBox(width: 8),
          Text('POWERED BY BLOCKCHAIN', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: OV.onSurfaceVariant)),
        ])),
    const SizedBox(height: 16),
    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text('v4.0.2-Stable', style: GoogleFonts.inter(fontSize: 12, color: OV.outline, fontWeight: FontWeight.w500)),
      Container(margin: const EdgeInsets.symmetric(horizontal: 12), width: 4, height: 4, decoration: const BoxDecoration(color: OV.outlineVariant, shape: BoxShape.circle)),
      Text('HIPAA Compliant', style: GoogleFonts.inter(fontSize: 12, color: OV.outline, fontWeight: FontWeight.w500)),
    ]),
  ]);
}