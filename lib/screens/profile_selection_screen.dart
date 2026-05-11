import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import 'signup_screen.dart';
import 'login_screen.dart';

class ProfileSelectionScreen extends StatefulWidget {
  const ProfileSelectionScreen({super.key});
  @override
  State<ProfileSelectionScreen> createState() => _ProfileSelectionScreenState();
}

class _ProfileSelectionScreenState extends State<ProfileSelectionScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _listCtrl;
  int? _selectedIndex;

  final List<_ProfileData> _profiles = const [
    _ProfileData(title: 'Patient',   roleKey: 'patient',
        desc: 'Access your medical records, treatment plans, and appointment schedule.',
        icon: Icons.person_outline_rounded,
        iconBg: Color(0xFFEDE8F5), iconColor: Color(0xFF635B6E)),
    _ProfileData(title: 'Doctor',    roleKey: 'doctor',
        desc: 'Manage patient diagnostics, prescribe treatments, and review clinical trials.',
        icon: Icons.medical_services_outlined,
        iconBg: Color(0xFFD3E5F1), iconColor: Color(0xFF50616B),
        badgeIcon: Icons.star_rounded, badgeColor: Color(0xFF4A4456)),
    _ProfileData(title: 'Nurse / HO', roleKey: 'nurse',
        desc: 'Monitor daily patient vitals, medication delivery, and ward logistics.',
        icon: Icons.add_box_outlined,
        iconBg: Color(0xFFDFF0E8), iconColor: Color(0xFF52625C)),
    _ProfileData(title: 'Admin',     roleKey: 'admin',
        desc: 'Manage hospital resources, user access levels, and security protocols.',
        icon: Icons.shield_outlined,
        iconBg: Color(0xFFFFDAD6), iconColor: Color(0xFFBA1A1A)),
  ];

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent, statusBarIconBrightness: Brightness.dark));
    _listCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));
    Future.delayed(const Duration(milliseconds: 100), () { if (mounted) _listCtrl.forward(); });
  }

  @override
  void dispose() { _listCtrl.dispose(); super.dispose(); }

  void _goNext(bool isNew) {
    final role = _profiles[_selectedIndex!].roleKey;
    Navigator.push(context, PageRouteBuilder(
      pageBuilder: (_, a, __) => isNew ? SignupScreen(selectedRole: role) : const LoginScreen(),
      transitionDuration: const Duration(milliseconds: 450),
      transitionsBuilder: (_, a, __, child) {
        final tween = Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
            .chain(CurveTween(curve: Curves.easeOutCubic));
        return SlideTransition(position: a.drive(tween), child: child);
      },
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OV.background,
      body: SafeArea(child: Column(children: [
        // ── Top Bar ─────────────────────────────────────────────
        Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Row(children: [
                Container(padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: OV.primary.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
                    child: Icon(Icons.grid_view_rounded, color: OV.primary, size: 16)),
                const SizedBox(width: 8),
                Text('OncoVault', style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700, color: OV.primary)),
              ]),
              Container(width: 38, height: 38,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: OV.surfaceContainer,
                      border: Border.all(color: OV.outlineVariant, width: 1.5)),
                  child: const Icon(Icons.person_rounded, size: 20, color: OV.onSurfaceVariant)),
            ])),

        // ── Scrollable cards ────────────────────────────────────
        Expanded(child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(children: [
            const SizedBox(height: 8),
            Text('Select Your\nProfile', style: GoogleFonts.manrope(
                fontSize: 36, fontWeight: FontWeight.w700, color: OV.onSurface, height: 1.2, letterSpacing: -0.5),
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('Welcome to OncoVault. Please select your role to access your personalized medical workspace.',
                    style: GoogleFonts.inter(fontSize: 14, color: OV.onSurfaceVariant, height: 1.6),
                    textAlign: TextAlign.center)),
            const SizedBox(height: 28),

            ..._profiles.asMap().entries.map((e) {
              final i = e.key; final delay = i * 0.15;
              return AnimatedBuilder(
                  animation: _listCtrl,
                  builder: (_, child) {
                    final v = Curves.easeOutCubic.transform(
                        ((_listCtrl.value - delay) / (1.0 - delay)).clamp(0.0, 1.0));
                    return Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 30 * (1 - v)), child: child));
                  },
                  child: Padding(padding: const EdgeInsets.only(bottom: 14),
                      child: _ProfileCard(
                          profile: e.value,
                          isSelected: _selectedIndex == i,
                          onTap: () { setState(() => _selectedIndex = i); HapticFeedback.lightImpact(); })));
            }),


          ]),
        )),

        // ── Bottom CTA ──────────────────────────────────────────
        AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            height: _selectedIndex != null ? 120 : 0,
            child: _selectedIndex != null ? Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: OV.outlineVariant.withOpacity(0.5)))),
              child: Column(children: [
                SizedBox(width: double.infinity, height: 50,
                    child: ElevatedButton(
                        onPressed: () => _goNext(true),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: OV.primary, foregroundColor: Colors.white, elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Text('Create Account as ${_profiles[_selectedIndex!].title}',
                              style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600)),
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward_rounded, size: 16),
                        ]))),
              ]),
            ) : const SizedBox.shrink()),
      ])),
    );
  }
}

class _ProfileData {
  final String title, roleKey, desc;
  final IconData icon;
  final Color iconBg, iconColor;
  final IconData? badgeIcon;
  final Color? badgeColor;
  const _ProfileData({required this.title, required this.roleKey, required this.desc,
    required this.icon, required this.iconBg, required this.iconColor,
    this.badgeIcon, this.badgeColor});
}

class _ProfileCard extends StatelessWidget {
  final _ProfileData profile;
  final bool isSelected;
  final VoidCallback onTap;
  const _ProfileCard({required this.profile, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
              color: isSelected ? OV.primaryContainer.withOpacity(0.35) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: isSelected ? OV.primary.withOpacity(0.45) : OV.outlineVariant.withOpacity(0.5),
                  width: isSelected ? 1.5 : 1),
              boxShadow: [BoxShadow(
                  color: isSelected ? OV.primary.withOpacity(0.08) : Colors.black.withOpacity(0.04),
                  blurRadius: isSelected ? 20 : 8, offset: const Offset(0, 4))]),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Stack(children: [
              Container(width: 54, height: 54,
                  decoration: BoxDecoration(color: profile.iconBg, borderRadius: BorderRadius.circular(14)),
                  child: Icon(profile.icon, color: profile.iconColor, size: 26)),
              if (profile.badgeIcon != null)
                Positioned(top: -3, right: -3, child: Container(width: 22, height: 22,
                    decoration: BoxDecoration(color: profile.badgeColor, shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2)),
                    child: Icon(profile.badgeIcon!, color: Colors.white, size: 10))),
            ]),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(profile.title, style: GoogleFonts.manrope(
                    fontSize: 16, fontWeight: FontWeight.w600, color: OV.onSurface, letterSpacing: -0.2)),
                if (isSelected) ...[
                  const Spacer(),
                  Container(width: 20, height: 20,
                      decoration: const BoxDecoration(color: OV.primary, shape: BoxShape.circle),
                      child: const Icon(Icons.check_rounded, color: Colors.white, size: 13)),
                ],
              ]),
              const SizedBox(height: 4),
              Text(profile.desc, style: GoogleFonts.inter(fontSize: 12, color: OV.onSurfaceVariant, height: 1.5)),
            ])),
          ])));
}