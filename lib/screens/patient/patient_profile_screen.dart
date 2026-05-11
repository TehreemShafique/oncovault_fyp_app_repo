// lib/screens/patient/patient_profile_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../theme/app_theme.dart';
import '../../models/patient_profile_model.dart';

class PatientProfileScreen extends StatefulWidget {
  final String patientId;
  const PatientProfileScreen({super.key, required this.patientId});
  @override
  State<PatientProfileScreen> createState() => _PatientProfileScreenState();
}

class _PatientProfileScreenState extends State<PatientProfileScreen> {
  PatientProfile? _profile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final doc = await FirebaseFirestore.instance
        .collection('patients').doc(widget.patientId).get();
    if (!doc.exists) {
      final usersDoc = await FirebaseFirestore.instance
          .collection('users').doc(widget.patientId).get();
      if (usersDoc.exists) {
        final data = usersDoc.data()!;
        setState(() {
          _profile = PatientProfile(uid: widget.patientId,
              name: data['name'] ?? '', email: data['email'] ?? '',
              medicalId: data['medicalId'] ?? '');
          _loading = false;
        });
        return;
      }
    } else {
      setState(() {
        _profile = PatientProfile.fromMap(doc.data()!);
        _loading = false;
      });
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OV.background,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: OV.primary))
          : _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final p = _profile;
    if (p == null) return const Center(child: Text('Profile not found'));
    return SafeArea(child: CustomScrollView(slivers: [
    // App Bar
    SliverToBoxAdapter(child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            GestureDetector(onTap: () => Navigator.pop(context),
    child: Container(padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
    border: Border.all(color: OV.outlineVariant.withOpacity(0.5))),
    child: const Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: OV.onSurface))),
    Text('Account', style: GoogleFonts.manrope(fontSize: 17, fontWeight: FontWeight.w700, color: OV.onSurface)),
    Container(padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
    border: Border.all(color: OV.outlineVariant.withOpacity(0.5))),
    )]),
    )),

    // Avatar + Name
    SliverToBoxAdapter(child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Container(padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24),
    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 16, offset: const Offset(0, 4))]),
    child: Column(children: [
    Stack(children: [
    Container(width: 100, height: 100,
    decoration: BoxDecoration(shape: BoxShape.circle,
    color: OV.primaryContainer,
    border: Border.all(color: OV.primary.withOpacity(0.3), width: 3)),
    child: Center(child: Text(p.name.isNotEmpty ? p.name[0].toUpperCase() : 'P',
    style: GoogleFonts.manrope(fontSize: 40, fontWeight: FontWeight.w700, color: OV.primary)))),
    Positioned(bottom: 0, right: 0, child: Container(width: 30, height: 30,
    decoration: BoxDecoration(color: OV.slateDark, shape: BoxShape.circle,
    border: Border.all(color: Colors.white, width: 2)),
    child: const Icon(Icons.edit_rounded, color: Colors.white, size: 14))),
    ]),
    const SizedBox(height: 14),
    Text(p.name, style: GoogleFonts.manrope(fontSize: 22, fontWeight: FontWeight.w700, color: OV.onSurface)),
    const SizedBox(height: 8),
    Wrap(spacing: 8, children: [
    if (p.age != null) _Chip('${p.age} Years Old', OV.primaryContainer, OV.primary),
    if (p.gender.isNotEmpty) _Chip(p.gender, OV.secondaryContainer, OV.secondary),
    _Chip('Patient ID: ${p.medicalId}', OV.tertiaryContainer, OV.tertiary),
    ]),
    ]),
    ),
    )),

    const SliverToBoxAdapter(child: SizedBox(height: 24)),

    // Personal Info
    SliverToBoxAdapter(child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
    Text('Personal Info', style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w700, color: OV.onSurface)),
    GestureDetector(
    onTap: () => _showEditDialog(context, p),
    child: Row(children: [
    Icon(Icons.edit_outlined, size: 14, color: OV.primary),
    const SizedBox(width: 4),
    Text('Edit Info', style: GoogleFonts.inter(fontSize: 13, color: OV.primary, fontWeight: FontWeight.w500)),
    ])),
    ]),
    )),
    const SliverToBoxAdapter(child: SizedBox(height: 12)),

    SliverToBoxAdapter(child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Container(padding: const EdgeInsets.all(20), decoration: _cardDec,
    child: Column(children: [
    _InfoRow(icon: Icons.email_outlined, label: 'EMAIL ADDRESS', value: p.email),
    _Divider(),
    _InfoRow(icon: Icons.phone_outlined, label: 'PHONE NUMBER',
    value: p.phone.isNotEmpty ? p.phone : 'Not provided'),
    _Divider(),
    _InfoRow(icon: Icons.location_on_outlined, label: 'RESIDENTIAL ADDRESS',
    value: p.address.isNotEmpty ? p.address : 'Not provided'),
    ]),
    ),
    )),

    const SliverToBoxAdapter(child: SizedBox(height: 24)),

    // Medical Info
    SliverToBoxAdapter(child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Text('Medical Info', style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w700, color: OV.onSurface)),
    )),
    const SliverToBoxAdapter(child: SizedBox(height: 12)),

    SliverToBoxAdapter(child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Column(children: [
    _MedicalInfoCard(
    icon: Icons.water_drop_outlined,
    iconBg: OV.errorContainer,
    iconColor: OV.error,
    label: 'BLOOD TYPE',
    value: p.bloodType.isNotEmpty ? p.bloodType : 'Not set',
    leftBorder: OV.error,
    ),
    const SizedBox(height: 12),
    _MedicalInfoCard(
    icon: Icons.warning_amber_rounded,
    iconBg: const Color(0xFFFFF3E0),
    iconColor: const Color(0xFF8B5000),
    label: 'ALLERGIES',
    value: p.allergies.isNotEmpty ? p.allergies.join(', ') : 'None recorded',
    ),
    ]),
    )),

    const SliverToBoxAdapter(child: SizedBox(height: 24)),

    // Vault Security
    SliverToBoxAdapter(child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Container(padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(color: OV.slateDark, borderRadius: BorderRadius.circular(20)),
    child: Row(children: [
    Container(width: 44, height: 44,
    decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), shape: BoxShape.circle),
    child: const Icon(Icons.shield_outlined, color: Colors.white, size: 22)),
    const SizedBox(width: 14),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text('Vault Security', style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
    Text('Your medical records are encrypted with AES-256.',
    style: GoogleFonts.inter(fontSize: 12, color: Colors.white.withOpacity(0.7), height: 1.4)),
    ])),
    ]),
    ),
    )),
    const SliverToBoxAdapter(child: SizedBox(height: 12)),
    SliverToBoxAdapter(child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: SizedBox(width: double.infinity, height: 48,
    child: ElevatedButton(
    onPressed: () {},
    style: ElevatedButton.styleFrom(backgroundColor: OV.slateDark, foregroundColor: Colors.white,
    elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
    child: Text('Manage Access', style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600)))),
    )),

    const SliverToBoxAdapter(child: SizedBox(height: 32)),
    ]));
  }

  BoxDecoration get _cardDec => BoxDecoration(
      color: Colors.white, borderRadius: BorderRadius.circular(20),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 3))]);

  void _showEditDialog(BuildContext context, PatientProfile p) {
    final phoneCtrl   = TextEditingController(text: p.phone);
    final addressCtrl = TextEditingController(text: p.address);
    final allergyCtrl = TextEditingController(text: p.allergies.join(', '));
    String selectedGender   = p.gender;
    String selectedBlood    = p.bloodType;
    DateTime? selectedDOB   = p.dateOfBirth;

    final genders    = ['Male', 'Female', 'Other', 'Prefer not to say'];
    final bloodTypes = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];

    showModalBottomSheet(
        context: context, isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (ctx) => StatefulBuilder(builder: (ctx, setModal) => DraggableScrollableSheet(
            initialChildSize: 0.85, maxChildSize: 0.95, minChildSize: 0.5, expand: false,
            builder: (_, sc) => SingleChildScrollView(controller: sc, child: Padding(
                padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Center(child: Container(width: 40, height: 4,
                      decoration: BoxDecoration(color: OV.outlineVariant, borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 16),
                  Text('Edit Profile', style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 20),

                  _SectionLabel('Personal Information'),
                  const SizedBox(height: 10),
                  _EditField(ctrl: phoneCtrl, label: 'Phone Number', icon: Icons.phone_outlined),
                  const SizedBox(height: 10),
                  _EditField(ctrl: addressCtrl, label: 'Residential Address', icon: Icons.location_on_outlined),
                  const SizedBox(height: 10),

                  Text('Gender', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: OV.outline)),
                  const SizedBox(height: 6),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(color: OV.surfaceLow, borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: OV.outlineVariant.withOpacity(0.6))),
                      child: DropdownButtonHideUnderline(child: DropdownButton<String>(
                          value: selectedGender.isNotEmpty ? selectedGender : null,
                          hint: Text('Select gender', style: GoogleFonts.inter(fontSize: 14, color: OV.outline)),
                          isExpanded: true,
                          style: GoogleFonts.inter(fontSize: 14, color: OV.onSurface),
                          items: genders.map((g) => DropdownMenuItem(value: g,
                              child: Text(g, style: GoogleFonts.inter(fontSize: 14, color: OV.onSurface)))).toList(),
                          onChanged: (v) => setModal(() => selectedGender = v ?? '')))),
                  const SizedBox(height: 10),

                  Text('Date of Birth', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: OV.outline)),
                  const SizedBox(height: 6),
                  GestureDetector(
                      onTap: () async {
                        final picked = await showDatePicker(context: ctx,
                            initialDate: selectedDOB ?? DateTime(1990),
                            firstDate: DateTime(1920), lastDate: DateTime.now(),
                            builder: (c, child) => Theme(data: Theme.of(c).copyWith(
                                colorScheme: const ColorScheme.light(primary: OV.primary)), child: child!));
                        if (picked != null) setModal(() => selectedDOB = picked);
                      },
                      child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                          decoration: BoxDecoration(color: OV.surfaceLow, borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: OV.outlineVariant.withOpacity(0.6))),
                          child: Row(children: [
                            Icon(Icons.cake_outlined, color: OV.outline, size: 18),
                            const SizedBox(width: 10),
                            Text(selectedDOB != null
                                ? '\${selectedDOB!.day}/\${selectedDOB!.month}/\${selectedDOB!.year}'
                                : 'Select date of birth',
                                style: GoogleFonts.inter(fontSize: 14,
                                    color: selectedDOB != null ? OV.onSurface : OV.outline)),
                          ]))),

                  const SizedBox(height: 20),
                  _SectionLabel('Medical Information'),
                  const SizedBox(height: 10),

                  Text('Blood Type', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: OV.outline)),
                  const SizedBox(height: 6),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(color: OV.surfaceLow, borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: OV.outlineVariant.withOpacity(0.6))),
                      child: DropdownButtonHideUnderline(child: DropdownButton<String>(
                          value: selectedBlood.isNotEmpty ? selectedBlood : null,
                          hint: Text('Select blood type', style: GoogleFonts.inter(fontSize: 14, color: OV.outline)),
                          isExpanded: true,
                          style: GoogleFonts.inter(fontSize: 14, color: OV.onSurface),
                          items: bloodTypes.map((bt) => DropdownMenuItem(value: bt,
                              child: Text(bt, style: GoogleFonts.inter(fontSize: 14, color: OV.onSurface)))).toList(),
                          onChanged: (v) => setModal(() => selectedBlood = v ?? '')))),
                  const SizedBox(height: 10),

                  _EditField(ctrl: allergyCtrl, label: 'Allergies (comma separated)', icon: Icons.warning_amber_rounded),
                  const SizedBox(height: 4),
                  Text('e.g. Penicillin, Shellfish, Latex',
                      style: GoogleFonts.inter(fontSize: 11, color: OV.outline, fontStyle: FontStyle.italic)),

                  const SizedBox(height: 24),
                  SizedBox(width: double.infinity, height: 50,
                      child: ElevatedButton(
                          onPressed: () async {
                            final allergiesList = allergyCtrl.text.trim().isEmpty
                                ? <String>[]
                                : allergyCtrl.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
                            final updated = p.copyWith(
                              phone: phoneCtrl.text.trim(), address: addressCtrl.text.trim(),
                              gender: selectedGender, dateOfBirth: selectedDOB,
                              bloodType: selectedBlood, allergies: allergiesList,
                            );
                            await FirebaseFirestore.instance.collection('patients').doc(p.uid).set(updated.toMap());
                            await FirebaseFirestore.instance.collection('users').doc(p.uid)
                                .update({'phone': phoneCtrl.text.trim(), 'address': addressCtrl.text.trim()});
                            if (ctx.mounted) { Navigator.pop(ctx); _load(); }
                          },
                          style: ElevatedButton.styleFrom(backgroundColor: OV.slateDark, foregroundColor: Colors.white,
                              elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                          child: Text('Save Changes', style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w600)))),
                ]))))));
  }
}

class _Chip extends StatelessWidget {
  final String label; final Color bg, fg;
  const _Chip(this.label, this.bg, this.fg);
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(100)),
      child: Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: fg)));
}

class _InfoRow extends StatelessWidget {
  final IconData icon; final String label, value;
  const _InfoRow({required this.icon, required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Icon(icon, size: 18, color: OV.outline),
    const SizedBox(width: 12),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700,
          letterSpacing: 0.8, color: OV.outline)),
      const SizedBox(height: 4),
      Text(value, style: GoogleFonts.inter(fontSize: 14, color: OV.onSurface, height: 1.4)),
    ])),
  ]);
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
      margin: const EdgeInsets.symmetric(vertical: 14),
      height: 1, color: OV.outlineVariant.withOpacity(0.4));
}

class _MedicalInfoCard extends StatelessWidget {
  final IconData icon; final Color iconBg, iconColor;
  final String label, value; final Color? leftBorder;
  const _MedicalInfoCard({required this.icon, required this.iconBg, required this.iconColor,
    required this.label, required this.value, this.leftBorder});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
        border: leftBorder != null ? Border(left: BorderSide(color: leftBorder!, width: 3)) : null,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))]),
    child: Row(children: [
      Container(width: 44, height: 44, decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: iconColor, size: 22)),
      const SizedBox(width: 14),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: OV.outline)),
        const SizedBox(height: 4),
        Text(value, style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w700, color: OV.onSurface)),
      ]),
    ]),
  );
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: GoogleFonts.manrope(
      fontSize: 15,
      fontWeight: FontWeight.w700,
      color: OV.onSurface,
    ),
  );
}

class _EditField extends StatelessWidget {
  final TextEditingController ctrl; final String label; final IconData icon;
  const _EditField({required this.ctrl, required this.label, required this.icon});
  @override
  Widget build(BuildContext context) => TextField(
      controller: ctrl,
      style: GoogleFonts.inter(fontSize: 14, color: OV.onSurface),
      decoration: InputDecoration(
        labelText: label, labelStyle: GoogleFonts.inter(fontSize: 13, color: OV.outline),
        prefixIcon: Icon(icon, color: OV.outline, size: 18),
        filled: true, fillColor: OV.surfaceLow,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: OV.outlineVariant.withOpacity(0.6))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: OV.outlineVariant.withOpacity(0.6))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: OV.primary, width: 1.5)),
      ));
}