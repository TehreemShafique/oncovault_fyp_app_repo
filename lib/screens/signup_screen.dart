import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import '../services/appointment_service.dart';
import 'login_screen.dart';

class SignupScreen extends StatefulWidget {
  final String selectedRole;
  const SignupScreen({super.key, required this.selectedRole});
  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> with SingleTickerProviderStateMixin {
  final _nameCtrl     = TextEditingController();
  final _emailCtrl    = TextEditingController();
  final _passCtrl     = TextEditingController();
  final _confirmCtrl  = TextEditingController();
  final _formKey      = GlobalKey<FormState>();
  final _auth         = AuthService();

  bool _obscurePass    = true;
  bool _obscureConfirm = true;
  bool _isLoading      = false;

  late AnimationController _cardCtrl;
  late Animation<double> _cardOpacity;
  late Animation<Offset> _cardSlide;

  // role display helpers
  String get _roleLabel {
    switch (widget.selectedRole) {
      case 'doctor': return 'Doctor';
      case 'nurse':  return 'Nurse / HO';
      case 'admin':  return 'Admin';
      default:       return 'Patient';
    }
  }
  Color get _roleColor {
    switch (widget.selectedRole) {
      case 'doctor': return const Color(0xFF50616B);
      case 'nurse':  return const Color(0xFF52625C);
      case 'admin':  return const Color(0xFFBA1A1A);
      default:       return OV.primary;
    }
  }
  Color get _roleBg {
    switch (widget.selectedRole) {
      case 'doctor': return const Color(0xFFD3E5F1);
      case 'nurse':  return const Color(0xFFDFF0E8);
      case 'admin':  return const Color(0xFFFFDAD6);
      default:       return const Color(0xFFEDE8F5);
    }
  }

  @override
  void initState() {
    super.initState();
    _cardCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _cardOpacity = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _cardCtrl, curve: Curves.easeOut));
    _cardSlide   = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(CurvedAnimation(parent: _cardCtrl, curve: Curves.easeOutCubic));
    Future.delayed(const Duration(milliseconds: 100), () { if (mounted) _cardCtrl.forward(); });
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _emailCtrl.dispose();
    _passCtrl.dispose(); _confirmCtrl.dispose();
    _cardCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleSignup() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final user = await _auth.signUp(
        name: _nameCtrl.text,
        email: _emailCtrl.text,
        password: _passCtrl.text,
        role: widget.selectedRole,
      );
      if (!mounted) return;
      // Seed sample medical records for new patients
      if (widget.selectedRole == 'patient' && user != null) {
        await MedicalRecordService().seedSampleRecords(user.uid, user.name);
      }
      // Show generated Medical ID then go to login
      await showDialog(context: context, barrierDismissible: false, builder: (_) =>
          _MedicalIdDialog(medicalId: user?.medicalId ?? ''));
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
              (r) => false);
    } catch (e) {
      if (!mounted) return;
      _showError(e.toString().replaceAll('Exception: ', '').replaceAll('[firebase_auth/', '').replaceAll(']', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.inter(fontSize: 13)),
      backgroundColor: OV.error,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: OV.splashGrad),
        child: SafeArea(child: Column(children: [
          // Back bar
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(children: [
                GestureDetector(onTap: () => Navigator.pop(context),
                    child: Container(padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.8),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: OV.outlineVariant.withOpacity(0.5))),
                        child: const Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: OV.onSurface))),
                const SizedBox(width: 12),
                Text('Create Account', style: GoogleFonts.manrope(
                    fontSize: 18, fontWeight: FontWeight.w700, color: OV.onSurface)),
              ])),

          Expanded(child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: AnimatedBuilder(
              animation: _cardCtrl,
              builder: (_, child) => Opacity(opacity: _cardOpacity.value,
                  child: SlideTransition(position: _cardSlide, child: child)),
              child: Form(key: _formKey, child: Column(children: [
                // Role badge
                Container(margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(color: _roleBg,
                        borderRadius: BorderRadius.circular(100),
                        border: Border.all(color: _roleColor.withOpacity(0.3))),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 8, height: 8,
                          decoration: BoxDecoration(color: _roleColor, shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Text('Signing up as $_roleLabel',
                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: _roleColor)),
                    ])),

                // Card
                Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(color: OV.primary.withOpacity(0.08), blurRadius: 32, offset: const Offset(0, 12)),
                          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2)),
                        ]),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Center(child: Column(children: [
                        Text('Join OncoVault', style: GoogleFonts.manrope(
                            fontSize: 26, fontWeight: FontWeight.w700, color: OV.onSurface, letterSpacing: -0.4)),
                        const SizedBox(height: 6),
                        Text('Your Medical ID will be auto-generated\nafter successful registration.',
                            style: GoogleFonts.inter(fontSize: 13, color: OV.onSurfaceVariant, height: 1.5),
                            textAlign: TextAlign.center),
                      ])),
                      const SizedBox(height: 28),

                      _Label('Full Name'),
                      const SizedBox(height: 8),
                      _Field(controller: _nameCtrl, hint: 'Enter your full name', icon: Icons.person_outline_rounded,
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter your full name' : null),

                      const SizedBox(height: 16),
                      _Label('Email Address'),
                      const SizedBox(height: 8),
                      _Field(controller: _emailCtrl, hint: 'your@hospital.com', icon: Icons.email_outlined,
                          keyboardType: TextInputType.emailAddress,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'Please enter your email';
                            if (!v.contains('@') || !v.contains('.')) return 'Enter a valid email address';
                            return null;
                          }),

                      const SizedBox(height: 16),
                      _Label('Password'),
                      const SizedBox(height: 8),
                      _Field(controller: _passCtrl, hint: 'Min. 8 characters', icon: Icons.lock_outline_rounded,
                          obscureText: _obscurePass,
                          suffix: GestureDetector(
                              onTap: () => setState(() => _obscurePass = !_obscurePass),
                              child: Icon(_obscurePass ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                  color: OV.outline, size: 20)),
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'Please enter a password';
                            if (v.length < 8) return 'Password must be at least 8 characters';
                            return null;
                          }),

                      const SizedBox(height: 16),
                      _Label('Confirm Password'),
                      const SizedBox(height: 8),
                      _Field(controller: _confirmCtrl, hint: 'Re-enter password', icon: Icons.lock_outline_rounded,
                          obscureText: _obscureConfirm,
                          suffix: GestureDetector(
                              onTap: () => setState(() => _obscureConfirm = !_obscureConfirm),
                              child: Icon(_obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                  color: OV.outline, size: 20)),
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'Please confirm your password';
                            if (v != _passCtrl.text) return 'Passwords do not match';
                            return null;
                          }),

                      const SizedBox(height: 28),

                      // Sign Up button
                      SizedBox(width: double.infinity, height: 54,
                          child: ElevatedButton(
                              onPressed: _isLoading ? null : _handleSignup,
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: OV.slateDark, foregroundColor: Colors.white, elevation: 0,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                              child: _isLoading
                                  ? const SizedBox(width: 22, height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                Text('Create Account', style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w600)),
                                const SizedBox(width: 8),
                                const Icon(Icons.arrow_forward_rounded, size: 18),
                              ]))),

                      const SizedBox(height: 20),
                      Center(child: GestureDetector(
                          onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen())),
                          child: RichText(text: TextSpan(
                              style: GoogleFonts.inter(fontSize: 13, color: OV.onSurfaceVariant),
                              children: [
                                const TextSpan(text: 'Already registered? '),
                                TextSpan(text: 'Sign In', style: GoogleFonts.inter(
                                    fontSize: 13, fontWeight: FontWeight.w700, color: OV.primary)),
                              ])))),
                    ])),
              ])),
            ),
          )),
        ])),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: OV.onSurface));
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  const _Field({required this.controller, required this.hint, required this.icon,
    this.obscureText = false, this.suffix, this.keyboardType, this.validator});

  @override
  Widget build(BuildContext context) => TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      style: GoogleFonts.inter(fontSize: 15, color: OV.onSurface),
      decoration: InputDecoration(
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
        contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
      ));
}

// Dialog showing the auto-generated Medical ID
class _MedicalIdDialog extends StatelessWidget {
  final String medicalId;
  const _MedicalIdDialog({required this.medicalId});

  @override
  Widget build(BuildContext context) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 60, height: 60,
            decoration: BoxDecoration(color: OV.tertiaryContainer, shape: BoxShape.circle),
            child: const Icon(Icons.check_circle_outline_rounded, color: OV.tertiary, size: 32)),
        const SizedBox(height: 16),
        Text('Account Created!', style: GoogleFonts.manrope(fontSize: 22, fontWeight: FontWeight.w700, color: OV.onSurface)),
        const SizedBox(height: 8),
        Text('Your unique Medical ID has been generated. Save this — you will use it to log in.',
            style: GoogleFonts.inter(fontSize: 13, color: OV.onSurfaceVariant, height: 1.5),
            textAlign: TextAlign.center),
        const SizedBox(height: 20),
        Container(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(color: OV.primaryContainer,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: OV.primary.withOpacity(0.3))),
            child: Column(children: [
              Text('YOUR MEDICAL ID', style: GoogleFonts.inter(
                  fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: OV.onSurfaceVariant)),
              const SizedBox(height: 6),
              Text(medicalId, style: GoogleFonts.manrope(
                  fontSize: 24, fontWeight: FontWeight.w700, color: OV.primary, letterSpacing: 1.5)),
            ])),
        const SizedBox(height: 8),
        TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: medicalId));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Medical ID copied!'), duration: Duration(seconds: 1)));
            },
            icon: const Icon(Icons.copy_rounded, size: 14),
            label: Text('Copy to clipboard', style: GoogleFonts.inter(fontSize: 12)),
            style: TextButton.styleFrom(foregroundColor: OV.primary)),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, height: 48,
            child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                    backgroundColor: OV.slateDark, foregroundColor: Colors.white, elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: Text('Proceed to Sign In', style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600)))),
      ])));
}