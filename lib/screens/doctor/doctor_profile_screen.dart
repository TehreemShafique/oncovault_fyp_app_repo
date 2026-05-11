// lib/screens/doctor/doctor_profile_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../models/doctor_model.dart';
import '../../services/doctor_service.dart';
import '../../services/auth_service.dart';
import 'doctor_widgets.dart';
import '../profile_selection_screen.dart';

class DoctorProfileScreen extends StatefulWidget {
  final String doctorId;
  const DoctorProfileScreen({super.key, required this.doctorId});
  @override
  State<DoctorProfileScreen> createState() => _DoctorProfileScreenState();
}

class _DoctorProfileScreenState extends State<DoctorProfileScreen> {
  final _service = DoctorService();
  DoctorModel? _doctor;
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final d = await _service.fetchDoctor(widget.doctorId);
    if (d != null) {
      // If profile came from users fallback, it may be missing specialty etc.
      // Re-save so next load is from doctors collection with full data
      if (d.specialty.isEmpty && d.name.isNotEmpty) {
        await _service.updateDoctorProfile(d);
      }
    }
    setState(() { _doctor = d; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(backgroundColor: OV.background,
          body: Center(child: CircularProgressIndicator(color: OV.primary)));
    }
    final d = _doctor;
    if (d == null) {
      // Show retry screen instead of blank "not found"
      return Scaffold(backgroundColor: OV.background,
          body: SafeArea(child: Center(child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.error_outline_rounded, size: 48, color: OV.outlineVariant),
                const SizedBox(height: 16),
                Text('Could not load profile', style: GoogleFonts.manrope(
                    fontSize: 18, fontWeight: FontWeight.w700, color: OV.onSurface)),
                const SizedBox(height: 8),
                Text('Please check your connection and try again.',
                    style: GoogleFonts.inter(fontSize: 13, color: OV.onSurfaceVariant),
                    textAlign: TextAlign.center),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                    onPressed: () { setState(() => _loading = true); _load(); },
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text('Retry', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(backgroundColor: OV.slateDark,
                        foregroundColor: Colors.white, elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
              ])))));
    }

    return Scaffold(
        backgroundColor: OV.background,
        body: SafeArea(child: CustomScrollView(slivers: [
          SliverToBoxAdapter(child: _buildAppBar(context, d)),
          SliverToBoxAdapter(child: _buildHeroCard(d)),
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
          SliverToBoxAdapter(child: _buildStatsRow(d)),
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
          SliverToBoxAdapter(child: _buildInfoCard(d)),
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
          SliverToBoxAdapter(child: _buildSettingsSection()),
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
          SliverToBoxAdapter(child: _buildSignOutButton(context)),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ])));
  }

  Widget _buildAppBar(BuildContext context, DoctorModel d) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        GestureDetector(onTap: () => Navigator.pop(context),
            child: Container(padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: OV.outlineVariant.withOpacity(0.5))),
                child: const Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: OV.onSurface))),
        const SizedBox(width: 12),
        Text('Doctor Profile', style: GoogleFonts.manrope(
            fontSize: 17, fontWeight: FontWeight.w700, color: OV.onSurface)),
        const Spacer(),
        GestureDetector(onTap: () => _showEditSheet(context, d),
            child: Container(padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: OV.outlineVariant.withOpacity(0.5))),
                child: Icon(Icons.edit_outlined, size: 16, color: OV.primary))),
      ]));

  Widget _buildHeroCard(DoctorModel d) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: DCard(radius: 22, child: Column(children: [
        Stack(children: [
          Container(width: 90, height: 90,
              decoration: BoxDecoration(shape: BoxShape.circle, color: OV.primaryContainer,
                  border: Border.all(color: OV.primary.withOpacity(0.3), width: 3)),
              child: Center(child: Text(
                  d.name.isNotEmpty ? d.name[0].toUpperCase() : 'D',
                  style: GoogleFonts.manrope(fontSize: 36, fontWeight: FontWeight.w700, color: OV.primary)))),
          Positioned(bottom: 0, right: 0, child: Container(width: 28, height: 28,
              decoration: BoxDecoration(color: OV.slateDark, shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2)),
              child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 13))),
        ]),
        const SizedBox(height: 12),
        Text(d.name, style: GoogleFonts.manrope(
            fontSize: 22, fontWeight: FontWeight.w700, color: OV.onSurface)),
        const SizedBox(height: 4),
        if (d.specialty.isNotEmpty)
          Text(d.specialty, style: GoogleFonts.inter(
              fontSize: 14, color: OV.primary, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 6, children: [
          _Chip(d.medicalId, OV.primaryContainer, OV.primary),
          if (d.experienceYears > 0)
            _Chip('${d.experienceYears} Yrs Exp.', OV.secondaryContainer, OV.secondary),
          if (d.hospital.isNotEmpty)
            _Chip(d.hospital, OV.tertiaryContainer, OV.tertiary),
        ]),
        if (d.specialty.isEmpty) ...[
          const SizedBox(height: 12),
          GestureDetector(
              onTap: () => _showEditSheet(context, d),
              child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                      color: const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(color: const Color(0xFF8B5000).withOpacity(0.3))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.edit_rounded, size: 12, color: Color(0xFF8B5000)),
                    const SizedBox(width: 6),
                    Text('Tap Edit to complete your profile',
                        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600,
                            color: const Color(0xFF8B5000))),
                  ]))),
        ],
      ])));

  Widget _buildStatsRow(DoctorModel d) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(children: [
        _StatBlock(label: 'Specialty',
            value: d.specialty.isNotEmpty ? d.specialty : '—'),
        const SizedBox(width: 8),
        _StatBlock(label: 'Experience',
            value: d.experienceYears > 0 ? '${d.experienceYears} Yrs' : '—'),
        const SizedBox(width: 8),
        _StatBlock(label: 'Department',
            value: d.department.isNotEmpty ? d.department : '—'),
      ]));

  Widget _buildInfoCard(DoctorModel d) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: DCard(child: Column(children: [
        _InfoRow(icon: Icons.email_outlined, label: 'EMAIL', value: d.email),
        DividerLine(),
        _InfoRow(icon: Icons.phone_outlined, label: 'PHONE',
            value: d.phone.isNotEmpty ? d.phone : 'Tap Edit to add'),
        DividerLine(),
        _InfoRow(icon: Icons.badge_outlined, label: 'LICENSE NO.',
            value: d.licenseNumber.isNotEmpty ? d.licenseNumber : 'Tap Edit to add'),
        if (d.qualifications.isNotEmpty) ...[
          DividerLine(),
          _InfoRow(icon: Icons.school_outlined, label: 'QUALIFICATIONS',
              value: d.qualifications.join(', ')),
        ],
      ])));

  Widget _buildSettingsSection() => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Settings', style: GoogleFonts.manrope(
            fontSize: 16, fontWeight: FontWeight.w700, color: OV.onSurface)),
        const SizedBox(height: 10),
        DCard(child: Column(children: [
          _SettingsTile(icon: Icons.notifications_outlined,
              label: 'Notification Preferences', onTap: () {}),
          DividerLine(),
          _SettingsTile(icon: Icons.lock_outline_rounded,
              label: 'Change Password', onTap: () {}),
          DividerLine(),
          _SettingsTile(icon: Icons.shield_outlined,
              label: 'Privacy and Security', onTap: () {}),
          DividerLine(),
          _SettingsTile(icon: Icons.help_outline_rounded,
              label: 'Help and Support', onTap: () {}),
          DividerLine(),
          _SettingsTile(icon: Icons.info_outline_rounded,
              label: 'About OncoVault v4.0.2', onTap: () {}),
        ])),
      ]));

  Widget _buildSignOutButton(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SizedBox(width: double.infinity, height: 52,
          child: OutlinedButton.icon(
              onPressed: () async {
                await AuthService().signOut();
                if (context.mounted) {
                  Navigator.pushAndRemoveUntil(context,
                      MaterialPageRoute(builder: (_) => const ProfileSelectionScreen()),
                          (r) => false);
                }
              },
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: Text('Sign Out',
                  style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700)),
              style: OutlinedButton.styleFrom(foregroundColor: OV.error,
                  side: BorderSide(color: OV.error.withOpacity(0.4)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))))));

  void _showEditSheet(BuildContext context, DoctorModel d) {
    final specialtyCtrl = TextEditingController(text: d.specialty);
    final hospitalCtrl  = TextEditingController(text: d.hospital);
    final deptCtrl      = TextEditingController(text: d.department);
    final phoneCtrl     = TextEditingController(text: d.phone);
    final licenseCtrl   = TextEditingController(text: d.licenseNumber);
    final expCtrl       = TextEditingController(
        text: d.experienceYears > 0 ? d.experienceYears.toString() : '');

    showModalBottomSheet(
        context: context, isScrollControlled: true, backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (ctx) => Padding(
            padding: EdgeInsets.fromLTRB(24, 24, 24,
                MediaQuery.of(context).viewInsets.bottom + 24),
            child: SingleChildScrollView(child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Edit Profile', style: GoogleFonts.manrope(
                  fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 20),
              _EditField(ctrl: specialtyCtrl, label: 'Specialty',
                  icon: Icons.medical_services_outlined),
              const SizedBox(height: 10),
              _EditField(ctrl: hospitalCtrl, label: 'Hospital',
                  icon: Icons.local_hospital_outlined),
              const SizedBox(height: 10),
              _EditField(ctrl: deptCtrl, label: 'Department',
                  icon: Icons.business_outlined),
              const SizedBox(height: 10),
              _EditField(ctrl: phoneCtrl, label: 'Phone',
                  icon: Icons.phone_outlined),
              const SizedBox(height: 10),
              _EditField(ctrl: licenseCtrl, label: 'License Number',
                  icon: Icons.badge_outlined),
              const SizedBox(height: 10),
              _EditField(ctrl: expCtrl, label: 'Years of Experience',
                  icon: Icons.work_history_outlined,
                  keyboardType: TextInputType.number),
              const SizedBox(height: 24),
              SizedBox(width: double.infinity, height: 50,
                  child: ElevatedButton(
                      onPressed: () async {
                        final updated = d.copyWith(
                          specialty:       specialtyCtrl.text.trim(),
                          hospital:        hospitalCtrl.text.trim(),
                          department:      deptCtrl.text.trim(),
                          phone:           phoneCtrl.text.trim(),
                          licenseNumber:   licenseCtrl.text.trim(),
                          experienceYears: int.tryParse(expCtrl.text.trim()) ?? d.experienceYears,
                        );
                        await _service.updateDoctorProfile(updated);
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          _load();
                        }
                      },
                      style: ElevatedButton.styleFrom(
                          backgroundColor: OV.slateDark, foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                      child: Text('Save Changes',
                          style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w600)))),
            ]))));
  }
}

class _Chip extends StatelessWidget {
  final String label; final Color bg, fg;
  const _Chip(this.label, this.bg, this.fg);
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(100)),
      child: Text(label,
          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: fg)));
}

class _StatBlock extends StatelessWidget {
  final String label, value;
  const _StatBlock({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Expanded(child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04),
              blurRadius: 8, offset: const Offset(0, 2))]),
      child: Column(children: [
        Text(label, style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w700,
            letterSpacing: 0.5, color: OV.outline)),
        const SizedBox(height: 4),
        Text(value, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700,
            color: OV.onSurface),
            textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
      ])));
}

class _InfoRow extends StatelessWidget {
  final IconData icon; final String label, value;
  const _InfoRow({required this.icon, required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Icon(icon, size: 16, color: OV.outline),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w700,
              letterSpacing: 0.8, color: OV.outline)),
          const SizedBox(height: 2),
          Text(value, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600,
              color: OV.onSurface)),
        ])),
      ]));
}

class _SettingsTile extends StatelessWidget {
  final IconData icon; final String label; final VoidCallback onTap;
  const _SettingsTile({required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(onTap: onTap,
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(children: [
            Container(width: 36, height: 36,
                decoration: BoxDecoration(color: OV.surfaceLow, borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, size: 18, color: OV.onSurfaceVariant)),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: GoogleFonts.inter(
                fontSize: 14, fontWeight: FontWeight.w500, color: OV.onSurface))),
            Icon(Icons.chevron_right_rounded, color: OV.outlineVariant, size: 20),
          ])));
}

class _EditField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  const _EditField({required this.ctrl, required this.label,
    required this.icon, this.keyboardType});
  @override
  Widget build(BuildContext context) => TextField(
      controller: ctrl, keyboardType: keyboardType,
      style: GoogleFonts.inter(fontSize: 14, color: OV.onSurface),
      decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.inter(fontSize: 13, color: OV.outline),
          prefixIcon: Icon(icon, color: OV.outline, size: 18),
          filled: true, fillColor: OV.surfaceLow,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: OV.outlineVariant.withOpacity(0.6))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: OV.outlineVariant.withOpacity(0.6))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: OV.primary, width: 1.5))));
}