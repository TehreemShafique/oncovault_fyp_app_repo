// lib/screens/doctor/patient_list_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../models/patient_profile_model.dart';
import '../../services/doctor_service.dart';
import 'doctor_widgets.dart';
import 'patient_detail_screen.dart';

class PatientListScreen extends StatefulWidget {
  final String doctorId;
  const PatientListScreen({super.key, required this.doctorId});
  @override
  State<PatientListScreen> createState() => _PatientListScreenState();
}

class _PatientListScreenState extends State<PatientListScreen> {
  final _service = DoctorService();
  final _searchCtrl = TextEditingController();
  String _query = '';
  String _filter = 'All';
  final _filters = ['All', 'Stable', 'Monitoring', 'Critical', 'Follow-Up'];

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  List<PatientProfile> _applyFilter(List<PatientProfile> patients) {
    var list = patients;
    if (_query.isNotEmpty) {
      list = list.where((p) =>
      p.name.toLowerCase().contains(_query.toLowerCase()) ||
          p.medicalId.toLowerCase().contains(_query.toLowerCase())).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: OV.background,
        body: SafeArea(child: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('Patients', style: GoogleFonts.manrope(
                    fontSize: 26, fontWeight: FontWeight.w700, color: OV.onSurface, letterSpacing: -0.4)),
                StreamBuilder<List<PatientProfile>>(
                    stream: _service.watchDoctorPatients(widget.doctorId),
                    builder: (_, snap) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(color: OV.primaryContainer, borderRadius: BorderRadius.circular(100)),
                        child: Text('${snap.data?.length ?? 0} total',
                            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: OV.primary)))),
              ])),
          const SizedBox(height: 14),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: OV.outlineVariant.withOpacity(0.5))),
                  child: TextField(
                      controller: _searchCtrl,
                      onChanged: (v) => setState(() => _query = v),
                      style: GoogleFonts.inter(fontSize: 14, color: OV.onSurface),
                      decoration: InputDecoration(
                          hintText: 'Search by name or patient ID...',
                          hintStyle: GoogleFonts.inter(fontSize: 14, color: OV.outline),
                          prefixIcon: Icon(Icons.search_rounded, color: OV.outline, size: 20),
                          suffixIcon: _query.isNotEmpty
                              ? GestureDetector(onTap: () => setState(() { _query = ''; _searchCtrl.clear(); }),
                              child: Icon(Icons.close_rounded, color: OV.outline, size: 18)) : null,
                          filled: true, fillColor: Colors.white,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4))))),
          const SizedBox(height: 12),
          SizedBox(height: 36, child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              itemCount: _filters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final f = _filters[i]; final sel = _filter == f;
                return GestureDetector(
                    onTap: () => setState(() => _filter = f),
                    child: AnimatedContainer(duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                            color: sel ? OV.slateDark : Colors.white,
                            borderRadius: BorderRadius.circular(100),
                            border: Border.all(color: sel ? OV.slateDark : OV.outlineVariant.withOpacity(0.5))),
                        child: Text(f, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600,
                            color: sel ? Colors.white : OV.onSurfaceVariant))));
              })),
          const SizedBox(height: 14),
          Expanded(child: StreamBuilder<List<PatientProfile>>(
              stream: _service.watchDoctorPatients(widget.doctorId),
              builder: (_, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: OV.primary));
                }
                final patients = _applyFilter(snap.data ?? []);
                if (patients.isEmpty) {
                  return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.people_alt_outlined, size: 48, color: OV.outlineVariant),
                    const SizedBox(height: 12),
                    Text(_query.isNotEmpty ? 'No results for "$_query"' : 'No patients yet',
                        style: GoogleFonts.inter(fontSize: 14, color: OV.onSurfaceVariant)),
                  ]));
                }
                return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: patients.length,
                    itemBuilder: (_, i) => _PatientCard(
                        patient: patients[i],
                        onTap: () => Navigator.push(context, dSlide(PatientDetailScreen(
                            patientId: patients[i].uid, doctorId: widget.doctorId)))));
              })),
        ])));
  }
}

class _PatientCard extends StatelessWidget {
  final PatientProfile patient; final VoidCallback onTap;
  const _PatientCard({required this.patient, required this.onTap});

  String get _initials {
    final parts = patient.name.split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return patient.name.isNotEmpty ? patient.name[0].toUpperCase() : 'P';
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: onTap,
      child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 3))]),
          child: Row(children: [
            Container(width: 48, height: 48,
                decoration: BoxDecoration(color: OV.primaryContainer, borderRadius: BorderRadius.circular(14)),
                child: Center(child: Text(_initials,
                    style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w800, color: OV.primary)))),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(patient.name, style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700, color: OV.onSurface)),
              Text('ID: ${patient.medicalId}', style: GoogleFonts.inter(fontSize: 11, color: OV.onSurfaceVariant)),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              PatientStatusChip(status: patient.activeDiagnosis.isNotEmpty ? 'Stable' : 'New'),
              if (patient.activeDiagnosis.isNotEmpty) ...[
                const SizedBox(height: 4),
                SizedBox(width: 90, child: Text(patient.activeDiagnosis,
                    style: GoogleFonts.inter(fontSize: 10, color: OV.onSurfaceVariant),
                    maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right)),
              ],
            ]),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded, color: OV.outlineVariant, size: 20),
          ])));
}