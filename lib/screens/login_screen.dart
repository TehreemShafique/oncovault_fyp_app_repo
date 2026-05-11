import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import 'dashboard_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _medIdCtrl  = TextEditingController();
  final _passCtrl   = TextEditingController();
  final _formKey    = GlobalKey<FormState>();
  final _auth       = AuthService();

  bool _obscurePass = true;
  bool _isLoading   = false;

  late AnimationController _cardCtrl;
  late Animation<double> _cardOpacity;
  late Animation<Offset> _cardSlide;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent, statusBarIconBrightness: Brightness.dark));
    _cardCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 750));
    _cardOpacity = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _cardCtrl, curve: Curves.easeOut));
    _cardSlide   = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _cardCtrl, curve: Curves.easeOutCubic));
    Future.delayed(const Duration(milliseconds: 100), () { if (mounted) _cardCtrl.forward(); });
  }

  @override
  void dispose() { _medIdCtrl.dispose(); _passCtrl.dispose(); _cardCtrl.dispose(); super.dispose(); }

  Future<void> _showForgotPassword(BuildContext context) async {
    final emailCtrl = TextEditingController();
    await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text('Reset Password', style: GoogleFonts.manrope(fontSize: 17, fontWeight: FontWeight.w700)),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Enter your registered email address. We will send you a link to reset your password.',
                  style: GoogleFonts.inter(fontSize: 13, color: OV.onSurfaceVariant, height: 1.5)),
              const SizedBox(height: 16),
              TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  style: GoogleFonts.inter(fontSize: 14, color: OV.onSurface),
                  decoration: InputDecoration(
                      hintText: 'your@email.com',
                      hintStyle: GoogleFonts.inter(fontSize: 14, color: OV.outline),
                      prefixIcon: Icon(Icons.email_outlined, color: OV.outline, size: 18),
                      filled: true, fillColor: OV.surfaceLow,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: OV.outlineVariant.withOpacity(0.6))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: OV.outlineVariant.withOpacity(0.6))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: OV.primary, width: 1.5)),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4))),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx),
                  child: Text('Cancel', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: OV.onSurfaceVariant))),
              ElevatedButton(
                  onPressed: () async {
                    final email = emailCtrl.text.trim();
                    if (email.isEmpty || !email.contains('@')) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('Please enter a valid email address',
                              style: GoogleFonts.inter(fontSize: 13)),
                          backgroundColor: OV.error, behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
                      return;
                    }
                    Navigator.pop(ctx);
                    try {
                      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('Password reset email sent to $email',
                                style: GoogleFonts.inter(fontSize: 13)),
                            backgroundColor: OV.tertiary, behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('No account found with this email.',
                                style: GoogleFonts.inter(fontSize: 13)),
                            backgroundColor: OV.error, behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: OV.primary, elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  child: Text('Send Reset Link', style: GoogleFonts.manrope(fontWeight: FontWeight.w700, color: Colors.white))),
            ]));
  }

  Future<void> _handleSignIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final user = await _auth.signIn(
        medicalId: _medIdCtrl.text,
        password: _passCtrl.text,
      );
      if (!mounted) return;
      Navigator.pushReplacement(context,
          PageRouteBuilder(
              pageBuilder: (_, a, __) => DashboardScreen(user: user),
              transitionDuration: const Duration(milliseconds: 500),
              transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child)));
    } catch (e) {
      if (!mounted) return;
      String msg = 'Sign in failed. Please check your credentials.';
      final s = e.toString();
      if (s.contains('user-not-found') || s.contains('No account')) {
        msg = 'No account found for this Medical ID.';
      } else if (s.contains('wrong-password') || s.contains('invalid-credential')) {
        msg = 'Incorrect password. Please try again.';
      } else if (s.contains('network')) {
        msg = 'Network error. Please check your connection.';
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg, style: GoogleFonts.inter(fontSize: 13)),
          backgroundColor: OV.error, behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: OV.splashGrad),
        child: SafeArea(child: SingleChildScrollView(child: Column(children: [
          // Logo bar
          Padding(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: OV.primary.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
                    child: Icon(Icons.grid_view_rounded, color: OV.primary, size: 18)),
                const SizedBox(width: 8),
                Text('OncoVault', style: GoogleFonts.manrope(
                    fontSize: 18, fontWeight: FontWeight.w700, color: OV.primary, letterSpacing: -0.3)),
              ])),

          const SizedBox(height: 16),

          // Card
          AnimatedBuilder(
            animation: _cardCtrl,
            builder: (_, child) => Opacity(opacity: _cardOpacity.value,
                child: SlideTransition(position: _cardSlide, child: child)),
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Form(key: _formKey, child: Container(
                    padding: const EdgeInsets.all(26),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(26),
                        boxShadow: [
                          BoxShadow(color: OV.primary.withOpacity(0.08), blurRadius: 40, offset: const Offset(0, 16)),
                          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2)),
                        ]),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Center(child: Column(children: [
                        Text('Welcome Back', style: GoogleFonts.manrope(
                            fontSize: 28, fontWeight: FontWeight.w700, color: OV.onSurface, letterSpacing: -0.5)),
                        const SizedBox(height: 8),
                        Text('Access secure patient records and\nvault services.',
                            style: GoogleFonts.inter(fontSize: 14, color: OV.onSurfaceVariant, height: 1.5),
                            textAlign: TextAlign.center),
                      ])),
                      const SizedBox(height: 28),

                      _Label('Medical ID'),
                      const SizedBox(height: 8),
                      TextFormField(
                          controller: _medIdCtrl,
                          textCapitalization: TextCapitalization.characters,
                          style: GoogleFonts.inter(fontSize: 15, color: OV.onSurface),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter your Medical ID' : null,
                          decoration: _fieldDec('OV-PA-XXXXXX', Icons.badge_outlined)),

                      const SizedBox(height: 18),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        _Label('Password'),
                        GestureDetector(
                            onTap: () => _showForgotPassword(context),
                            child: Text('Forgot?', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: OV.primary))),
                      ]),
                      const SizedBox(height: 8),
                      TextFormField(
                          controller: _passCtrl,
                          obscureText: _obscurePass,
                          style: GoogleFonts.inter(fontSize: 15, color: OV.onSurface),
                          validator: (v) => (v == null || v.isEmpty) ? 'Please enter your password' : null,
                          decoration: _fieldDec('••••••••••', Icons.lock_outline_rounded,
                              suffix: GestureDetector(
                                  onTap: () => setState(() => _obscurePass = !_obscurePass),
                                  child: Icon(_obscurePass ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                      color: OV.outline, size: 20)))),

                      const SizedBox(height: 26),
                      SizedBox(width: double.infinity, height: 54,
                          child: ElevatedButton(
                              onPressed: _isLoading ? null : _handleSignIn,
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: OV.slateDark, foregroundColor: Colors.white, elevation: 0,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                              child: _isLoading
                                  ? const SizedBox(width: 22, height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                Text('Sign In', style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w600)),
                                const SizedBox(width: 8),
                                const Icon(Icons.arrow_forward_rounded, size: 18),
                              ]))),


                      const SizedBox(height: 22),

                      Center(child: RichText(textAlign: TextAlign.center, text: TextSpan(
                          style: GoogleFonts.inter(fontSize: 13, color: OV.onSurfaceVariant, height: 1.6),
                          children: [
                            const TextSpan(text: 'Authorized Medical Personnel only.\n'),
                            TextSpan(text: 'Request Access Terminal',
                                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: OV.primary)),
                          ]))),
                    ])))),
          ),

          const SizedBox(height: 24),
          // Status dots
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _StatusDot(color: OV.tertiary, label: 'Vault Encrypted'),
            const SizedBox(width: 20),
            _StatusDot(color: OV.tertiary, label: 'System Status: Stable'),
          ]),
          const SizedBox(height: 24),
        ]))),
      ),
    );
  }

  InputDecoration _fieldDec(String hint, IconData icon, {Widget? suffix}) => InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.inter(fontSize: 15, color: OV.outline),
      prefixIcon: Icon(icon, color: OV.outline, size: 20),
      suffixIcon: suffix != null ? Padding(padding: const EdgeInsets.only(right: 12), child: suffix) : null,
      suffixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      filled: true, fillColor: OV.surfaceLow,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: OV.outlineVariant.withOpacity(0.6))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: OV.outlineVariant.withOpacity(0.6))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: OV.primary, width: 1.5)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: OV.error)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: OV.error, width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4));

  Widget _divider(String label) => Row(children: [
    Expanded(child: Container(height: 1, color: OV.outlineVariant)),
    Padding(padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Text(label, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600,
            letterSpacing: 1.2, color: OV.outline))),
    Expanded(child: Container(height: 1, color: OV.outlineVariant)),
  ]);
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: OV.onSurface));
}

class _BiometricTile extends StatelessWidget {
  final IconData icon; final String label;
  const _BiometricTile({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(color: OV.surfaceLow, borderRadius: BorderRadius.circular(14),
          border: Border.all(color: OV.outlineVariant.withOpacity(0.6))),
      child: Column(children: [
        Icon(icon, color: OV.onSurfaceVariant, size: 26),
        const SizedBox(height: 6),
        Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: OV.onSurface)),
      ]));
}

class _StatusDot extends StatelessWidget {
  final Color color; final String label;
  const _StatusDot({required this.color, required this.label});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    const SizedBox(width: 6),
    Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: OV.onSurfaceVariant)),
  ]);
}