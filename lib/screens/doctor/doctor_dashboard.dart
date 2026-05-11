// lib/screens/doctor/doctor_dashboard.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../profile_selection_screen.dart';
import '../../models/appointment_model.dart';
import '../../models/doctor_model.dart';
import '../../services/doctor_service.dart';
import 'doctor_widgets.dart';
import '../../models/patient_profile_model.dart';
import 'full_medical_history_screen.dart';
import 'appointment_requests_screen.dart';
import 'patient_list_screen.dart';
import 'critical_alerts_screen.dart';
import 'doctor_notifications_screen.dart';
import 'doctor_profile_screen.dart';
import 'prescription_screen.dart';

class DoctorDashboard extends StatefulWidget {
  final String doctorId;
  final String doctorName;
  const DoctorDashboard({super.key, required this.doctorId, required this.doctorName});
  @override
  State<DoctorDashboard> createState() => _DoctorDashboardState();
}

class _DoctorDashboardState extends State<DoctorDashboard> {
  int _tab = 0;
  final _service = DoctorService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OV.background,
      body: IndexedStack(index: _tab, children: [
        _DashboardHome(doctorId: widget.doctorId, doctorName: widget.doctorName, service: _service),
        PatientListScreen(doctorId: widget.doctorId),
        AppointmentRequestsScreen(doctorId: widget.doctorId, doctorName: widget.doctorName),
        _DoctorArchiveTab(doctorId: widget.doctorId),
      ]),
      bottomNavigationBar: _BottomNav(current: _tab, onTap: (i) => setState(() => _tab = i)),
    );
  }
}

// ── Dashboard Home ────────────────────────────────────────────────────────────
class _DashboardHome extends StatelessWidget {
  final String doctorId, doctorName;
  final DoctorService service;
  const _DashboardHome({required this.doctorId, required this.doctorName, required this.service});

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(child: CustomScrollView(slivers: [

      // ── Top Bar ──────────────────────────────────────────────
      SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Row(children: [
              Container(padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: OV.primary.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
                  child: Icon(Icons.grid_view_rounded, color: OV.primary, size: 16)),
              const SizedBox(width: 8),
              Text('OncoVault', style: GoogleFonts.manrope(
                  fontSize: 16, fontWeight: FontWeight.w700, color: OV.primary)),
            ]),
            Row(children: [
              // Search
              GestureDetector(
                  onTap: () => Navigator.push(context, dSlide(PatientListScreen(doctorId: doctorId))),
                  child: Container(padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: OV.outlineVariant.withOpacity(0.5))),
                      child: Icon(Icons.search_rounded, size: 18, color: OV.onSurfaceVariant))),
              const SizedBox(width: 8),
              // Notifications
              StreamBuilder<List>(
                  stream: service.watchDoctorNotifications(doctorId)
                      .map((l) => l.where((n) => !n.isRead).toList()),
                  builder: (_, snap) {
                    final unread = snap.data?.length ?? 0;
                    return GestureDetector(
                        onTap: () => Navigator.push(context, dSlide(DoctorNotificationsScreen(doctorId: doctorId))),
                        child: Stack(children: [
                          Container(padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: OV.outlineVariant.withOpacity(0.5))),
                              child: Icon(Icons.notifications_outlined, size: 18, color: OV.onSurfaceVariant)),
                          if (unread > 0) Positioned(top: 4, right: 4, child: Container(
                              width: 8, height: 8,
                              decoration: const BoxDecoration(color: OV.error, shape: BoxShape.circle))),
                        ]));
                  }),
              const SizedBox(width: 8),
              // Logout button
              GestureDetector(
                  onTap: () async {
                    final ctx = context;
                    final confirm = await showDialog<bool>(context: ctx,
                        builder: (_) => AlertDialog(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            title: Text('Sign Out', style: GoogleFonts.manrope(fontSize: 17, fontWeight: FontWeight.w700)),
                            content: Text('Are you sure you want to sign out?',
                                style: GoogleFonts.inter(fontSize: 14, color: OV.onSurfaceVariant)),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false),
                                  child: Text('Cancel', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: OV.onSurfaceVariant))),
                              ElevatedButton(onPressed: () => Navigator.pop(ctx, true),
                                  style: ElevatedButton.styleFrom(backgroundColor: OV.error, elevation: 0,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                                  child: Text('Sign Out', style: GoogleFonts.manrope(fontWeight: FontWeight.w700, color: Colors.white))),
                            ]));
                    if (confirm == true && ctx.mounted) {
                      await AuthService().signOut();
                      if (ctx.mounted) Navigator.pushAndRemoveUntil(ctx,
                          MaterialPageRoute(builder: (_) => const ProfileSelectionScreen()), (r) => false);
                    }
                  },
                  child: Container(padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: OV.outlineVariant.withOpacity(0.5))),
                      child: Icon(Icons.logout_rounded, size: 16, color: OV.error))),
              const SizedBox(width: 8),
              GestureDetector(
                  onTap: () => Navigator.push(context, dSlide(DoctorProfileScreen(doctorId: doctorId))),
                  child: Container(width: 36, height: 36,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: OV.primaryContainer,
                          border: Border.all(color: OV.primary.withOpacity(0.3), width: 2)),
                      child: Center(child: Text(doctorName[0].toUpperCase(),
                          style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w700, color: OV.primary))))),
            ]),
          ]))),

      // ── Critical Alert Banner (if any) ────────────────────────
      SliverToBoxAdapter(child: StreamBuilder<List<dynamic>>(
          stream: service.watchAlerts(doctorId),
          builder: (_, snap) {
            final alerts = snap.data ?? [];
            final highAlerts = alerts.where((a) => a.severity == 'high' && !a.isResolved).toList();
            if (highAlerts.isEmpty) return const SizedBox.shrink();
            final a = highAlerts.first;
            return GestureDetector(
                onTap: () => Navigator.push(context, dSlide(CriticalAlertsScreen(doctorId: doctorId))),
                child: Container(
                    margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                        color: OV.errorContainer,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: OV.error.withOpacity(0.3))),
                    child: Row(children: [
                      Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(color: OV.error, borderRadius: BorderRadius.circular(100)),
                          child: Text('Urgent Review', style: GoogleFonts.inter(
                              fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white))),
                      const SizedBox(width: 8),
                      Text('ID: #${a.patientId.substring(0, 6).toUpperCase()}',
                          style: GoogleFonts.inter(fontSize: 11, color: OV.error)),
                      const Spacer(),
                      Icon(Icons.arrow_forward_rounded, size: 16, color: OV.error),
                    ])));
          })),

      const SliverToBoxAdapter(child: SizedBox(height: 20)),

      // ── Analytics Cards ───────────────────────────────────────
      SliverToBoxAdapter(child: FutureBuilder<Map<String, int>>(
          future: service.fetchDashboardStats(doctorId),
          builder: (_, snap) {
            final stats = snap.data ?? {};
            return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(children: [
                  Expanded(child: _StatCard(
                    label: 'Patients',
                    value: '${stats['totalPatients'] ?? 0}',
                    icon: Icons.people_alt_rounded,
                    color: OV.primary,
                    onTap: () => Navigator.push(context, dSlide(PatientListScreen(doctorId: doctorId))),
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: _StatCard(
                    label: 'Pending',
                    value: '${stats['pendingRequests'] ?? 0}',
                    icon: Icons.pending_actions_rounded,
                    color: const Color(0xFF8B5000),
                    bg: const Color(0xFFFFF3E0),
                    onTap: () => Navigator.push(context, dSlide(
                        AppointmentRequestsScreen(doctorId: doctorId, doctorName: doctorName))),
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: _StatCard(
                    label: 'Alerts',
                    value: '${stats['criticalAlerts'] ?? 0}',
                    icon: Icons.warning_amber_rounded,
                    color: OV.error,
                    bg: OV.errorContainer,
                    onTap: () => Navigator.push(context, dSlide(CriticalAlertsScreen(doctorId: doctorId))),
                  )),
                ]));
          })),

      const SliverToBoxAdapter(child: SizedBox(height: 20)),

      // ── Recent Patients ───────────────────────────────────────
      SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SectionHeader(
            title: 'Recent Patients',
            action: 'See all',
            onAction: () => Navigator.push(context, dSlide(PatientListScreen(doctorId: doctorId))),
          ))),
      const SliverToBoxAdapter(child: SizedBox(height: 12)),
      SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: DCard(
              padding: const EdgeInsets.all(8),
              child: StreamBuilder<List>(
                  stream: service.watchDoctorPatients(doctorId),
                  builder: (_, snap) {
                    final patients = (snap.data ?? []).take(3).toList();
                    if (patients.isEmpty) {
                      return Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text('No patients yet', style: GoogleFonts.inter(
                              fontSize: 13, color: OV.onSurfaceVariant)));
                    }
                    return Column(children: patients.map((p) =>
                        _RecentPatientRow(
                            patient: p,
                            onTap: () {})).toList());
                  })))),

      const SliverToBoxAdapter(child: SizedBox(height: 16)),

      // ── Issue Prescription quick button ───────────────────────
      SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: GestureDetector(
              onTap: () => Navigator.push(context, dSlide(PrescriptionScreen(
                  doctorId: doctorId, doctorName: doctorName, doctorSpecialty: ''))),
              child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: OV.primaryContainer.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: OV.primary.withOpacity(0.25))),
                  child: Row(children: [
                    Container(width: 44, height: 44,
                        decoration: BoxDecoration(color: OV.primary, borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.medication_rounded, color: Colors.white, size: 22)),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Issue Digital Prescription', style: GoogleFonts.manrope(
                          fontSize: 14, fontWeight: FontWeight.w700, color: OV.primary)),
                      Text('Generate and send prescriptions to patients',
                          style: GoogleFonts.inter(fontSize: 11, color: OV.onSurfaceVariant)),
                    ])),
                    Icon(Icons.arrow_forward_ios_rounded, size: 14, color: OV.primary),
                  ]))))),

      const SliverToBoxAdapter(child: SizedBox(height: 20)),

      // ── Daily Schedule (Real Firestore data) ──────────────────
      SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Daily Schedule', style: GoogleFonts.manrope(
                  fontSize: 17, fontWeight: FontWeight.w700, color: OV.onSurface)),
              Text(DateFormat('EEEE, MMM d').format(DateTime.now()),
                  style: GoogleFonts.inter(fontSize: 12, color: OV.onSurfaceVariant)),
            ]),
            GestureDetector(
                onTap: () => Navigator.push(context, dSlide(
                    AppointmentRequestsScreen(doctorId: doctorId, doctorName: doctorName))),
                child: Container(padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: OV.surfaceLow, borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: OV.outlineVariant.withOpacity(0.5))),
                    child: Icon(Icons.calendar_month_rounded, size: 16, color: OV.primary))),
          ]))),
      const SliverToBoxAdapter(child: SizedBox(height: 12)),
      SliverToBoxAdapter(child: StreamBuilder<List<AppointmentModel>>(
          stream: service.watchDoctorAppointments(doctorId),
          builder: (_, snap) {
            final now = DateTime.now();
            final todayAppts = (snap.data ?? []).where((a) {
              final d = a.appointmentDate;
              return d.year == now.year && d.month == now.month && d.day == now.day
                  && a.status != AppointmentStatus.cancelled
                  && a.status != AppointmentStatus.rejected;
            }).toList()
              ..sort((a, b) => a.appointmentDate.compareTo(b.appointmentDate));

            if (snap.connectionState == ConnectionState.waiting) {
              return const Padding(padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Center(child: SizedBox(height: 40, width: 40,
                      child: CircularProgressIndicator(strokeWidth: 2, color: OV.primary))));
            }

            if (todayAppts.isEmpty) {
              return Padding(padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 3))]),
                      child: Row(children: [
                        Icon(Icons.event_available_rounded, color: OV.outlineVariant, size: 28),
                        const SizedBox(width: 14),
                        Text('No appointments scheduled for today',
                            style: GoogleFonts.inter(fontSize: 13, color: OV.onSurfaceVariant)),
                      ])));
            }

            return Padding(padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(children: todayAppts.map((a) =>
                    _AppointmentScheduleItem(appt: a)).toList()));
          })),


      const SliverToBoxAdapter(child: SizedBox(height: 24)),

    ]));
  }
}

// ── Stat Card ─────────────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final String label, value; final IconData icon;
  final Color color; final Color? bg; final VoidCallback? onTap;
  const _StatCard({required this.label, required this.value,
    required this.icon, required this.color, this.bg, this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: onTap,
      child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: bg ?? OV.primaryContainer.withOpacity(0.4),
              borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 10),
            Text(value, style: GoogleFonts.manrope(fontSize: 26, fontWeight: FontWeight.w800, color: color)),
            Text(label, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: color.withOpacity(0.7))),
          ])));
}

// ── Recent Patient Row ────────────────────────────────────────────────────────
class _RecentPatientRow extends StatelessWidget {
  final dynamic patient; final VoidCallback onTap;
  const _RecentPatientRow({required this.patient, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: onTap,
      child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          child: Row(children: [
            Container(width: 40, height: 40,
                decoration: BoxDecoration(color: OV.primaryContainer, borderRadius: BorderRadius.circular(12)),
                child: Center(child: Text(
                    (patient.name?.isNotEmpty == true ? patient.name[0] : 'P').toUpperCase(),
                    style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700, color: OV.primary)))),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(patient.name ?? '', style: GoogleFonts.manrope(
                  fontSize: 14, fontWeight: FontWeight.w700, color: OV.onSurface)),
              Text('Last visit: Recently', style: GoogleFonts.inter(
                  fontSize: 11, color: OV.onSurfaceVariant)),
            ])),
            if (patient.activeDiagnosis?.isNotEmpty == true)
              PatientStatusChip(status: 'Stable'),
            if (patient.activeDiagnosis?.isNotEmpty == true) const SizedBox(width: 6),
            Text(patient.activeDiagnosis ?? '',
                style: GoogleFonts.inter(fontSize: 10, color: OV.onSurfaceVariant),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ])));
}

// ── Quick Action Tile ─────────────────────────────────────────────────────────
// ── Appointment Schedule Item (real Firestore data) ──────────────────────────
class _AppointmentScheduleItem extends StatelessWidget {
  final AppointmentModel appt;
  const _AppointmentScheduleItem({required this.appt});

  Color get _lineColor {
    switch (appt.status) {
      case AppointmentStatus.approved:    return OV.tertiary;
      case AppointmentStatus.pending:     return const Color(0xFF8B5000);
      case AppointmentStatus.rescheduled: return OV.primary;
      default:                            return OV.outline;
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: IntrinsicHeight(child: Row(children: [
        SizedBox(width: 64, child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(appt.timeSlot, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700,
              color: OV.onSurface, letterSpacing: 0.2)),
          Text('${appt.durationMinutes}m', style: GoogleFonts.inter(fontSize: 10, color: OV.outline)),
        ])),
        const SizedBox(width: 12),
        Column(children: [
          Container(width: 10, height: 10,
              decoration: BoxDecoration(color: _lineColor, shape: BoxShape.circle)),
          Expanded(child: Container(width: 2, color: _lineColor.withOpacity(0.2))),
        ]),
        const SizedBox(width: 12),
        Expanded(child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(12),
                border: Border(left: BorderSide(color: _lineColor, width: 3)),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04),
                    blurRadius: 8, offset: const Offset(0, 2))]),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(appt.patientName, style: GoogleFonts.manrope(
                    fontSize: 13, fontWeight: FontWeight.w700, color: OV.onSurface))),
                DStatusBadge(status: appt.status),
              ]),
              const SizedBox(height: 2),
              Text(appt.doctorSpecialty.isNotEmpty ? appt.doctorSpecialty : 'Consultation',
                  style: GoogleFonts.inter(fontSize: 11, color: OV.onSurfaceVariant)),
              if (appt.notes.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(appt.notes, style: GoogleFonts.inter(fontSize: 10, color: OV.outline),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ]))),
      ])));
}

// ── Bottom Navigation ─────────────────────────────────────────────────────────
class _BottomNav extends StatelessWidget {
  final int current; final ValueChanged<int> onTap;
  const _BottomNav({required this.current, required this.onTap});

  @override
  Widget build(BuildContext context) => Container(
      decoration: BoxDecoration(color: Colors.white,
          border: Border(top: BorderSide(color: OV.outlineVariant.withOpacity(0.5)))),
      child: SafeArea(child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _NavItem(icon: Icons.grid_view_rounded,    label: 'Dashboard', sel: current == 0, onTap: () => onTap(0)),
            _NavItem(icon: Icons.people_alt_rounded,   label: 'Patients',  sel: current == 1, onTap: () => onTap(1)),
            _NavItem(icon: Icons.calendar_month_rounded,label: 'Schedule', sel: current == 2, onTap: () => onTap(2)),
            _NavItem(icon: Icons.folder_outlined,      label: 'Archive',   sel: current == 3, onTap: () => onTap(3)),
          ]))));
}

class _NavItem extends StatelessWidget {
  final IconData icon; final String label; final bool sel; final VoidCallback onTap;
  const _NavItem({required this.icon, required this.label, required this.sel, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: onTap, behavior: HitTestBehavior.opaque,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 22, color: sel ? OV.primary : OV.outline),
        const SizedBox(height: 4),
        Text(label, style: GoogleFonts.inter(fontSize: 10,
            fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
            color: sel ? OV.primary : OV.outline)),
      ]));
}

class _DoctorArchiveTab extends StatelessWidget {
  final String doctorId;
  const _DoctorArchiveTab({required this.doctorId});

  @override
  Widget build(BuildContext context) {
    final service = DoctorService();
    return SafeArea(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Archive', style: GoogleFonts.manrope(
                fontSize: 26, fontWeight: FontWeight.w700, color: OV.onSurface, letterSpacing: -0.3)),
            Text('All patient EHR records and clinical history',
                style: GoogleFonts.inter(fontSize: 13, color: OV.onSurfaceVariant)),
          ])),
      const SizedBox(height: 16),
      Expanded(child: StreamBuilder<List<PatientProfile>>(
          stream: service.watchDoctorPatients(doctorId),
          builder: (_, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: OV.primary));
            }
            final patients = snap.data ?? [];
            if (patients.isEmpty) {
              return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.folder_outlined, size: 48, color: OV.outlineVariant),
                const SizedBox(height: 12),
                Text('No patient records yet',
                    style: GoogleFonts.inter(fontSize: 14, color: OV.onSurfaceVariant)),
              ]));
            }
            return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: patients.length,
                itemBuilder: (_, i) {
                  final p = patients[i];
                  return GestureDetector(
                      onTap: () => Navigator.push(context, dSlide(
                          FullMedicalHistoryScreen(
                              patientId: p.uid,
                              doctorId: doctorId,
                              patientName: p.name))),
                      child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 3))]),
                          child: Row(children: [
                            Container(width: 46, height: 46,
                                decoration: BoxDecoration(color: OV.primaryContainer, borderRadius: BorderRadius.circular(12)),
                                child: Center(child: Text(
                                    p.name.isNotEmpty ? p.name[0].toUpperCase() : 'P',
                                    style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w700, color: OV.primary)))),
                            const SizedBox(width: 14),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(p.name, style: GoogleFonts.manrope(
                                  fontSize: 15, fontWeight: FontWeight.w700, color: OV.onSurface)),
                              Text('ID: \${p.medicalId}',
                                  style: GoogleFonts.inter(fontSize: 11, color: OV.onSurfaceVariant)),
                              if (p.activeDiagnosis.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(p.activeDiagnosis,
                                    style: GoogleFonts.inter(fontSize: 11, color: OV.primary, fontWeight: FontWeight.w500),
                                    maxLines: 1, overflow: TextOverflow.ellipsis),
                              ],
                            ])),
                            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                              Icon(Icons.folder_open_rounded, color: OV.primary, size: 18),
                              const SizedBox(height: 4),
                              Text('View EHR', style: GoogleFonts.inter(
                                  fontSize: 10, fontWeight: FontWeight.w600, color: OV.primary)),
                            ]),
                          ])));
                });
          })),
    ]));
  }
}