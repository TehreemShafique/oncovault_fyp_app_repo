// lib/screens/doctor/appointment_requests_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../models/appointment_model.dart';
import '../../services/doctor_service.dart';
import 'doctor_widgets.dart';
import 'appointment_detail_doctor_screen.dart';

class AppointmentRequestsScreen extends StatefulWidget {
  final String doctorId, doctorName;
  const AppointmentRequestsScreen({super.key, required this.doctorId, required this.doctorName});
  @override
  State<AppointmentRequestsScreen> createState() => _AppointmentRequestsScreenState();
}

class _AppointmentRequestsScreenState extends State<AppointmentRequestsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  final _service = DoctorService();

  @override
  void initState() { super.initState(); _tab = TabController(length: 3, vsync: this); }
  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: OV.background,
        body: SafeArea(child: Column(children: [
          DoctorAppBar(title: 'Appointments', showBack: false,
              actions: [
                StreamBuilder<List<AppointmentModel>>(
                    stream: _service.watchPendingAppointments(widget.doctorId),
                    builder: (_, snap) {
                      final count = snap.data?.length ?? 0;
                      return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(color: count > 0 ? const Color(0xFFFFF3E0) : OV.surfaceLow,
                              borderRadius: BorderRadius.circular(100)),
                          child: Text('$count pending', style: GoogleFonts.inter(
                              fontSize: 11, fontWeight: FontWeight.w700,
                              color: count > 0 ? const Color(0xFF8B5000) : OV.outline)));
                    }),
              ]),

          Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Container(height: 46, padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: OV.outlineVariant.withOpacity(0.5))),
                  child: TabBar(controller: _tab,
                      indicator: BoxDecoration(color: OV.slateDark, borderRadius: BorderRadius.circular(8)),
                      labelStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700),
                      unselectedLabelStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500),
                      labelColor: Colors.white, unselectedLabelColor: OV.onSurfaceVariant,
                      dividerColor: Colors.transparent,
                      tabs: const [Tab(text: 'Pending'), Tab(text: 'Upcoming'), Tab(text: 'Past')]))),

          const SizedBox(height: 12),

          Expanded(child: StreamBuilder<List<AppointmentModel>>(
              stream: _service.watchDoctorAppointments(widget.doctorId),
              builder: (_, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: OV.primary));
                }
                final all = snap.data ?? [];
                final now = DateTime.now();
                final pending   = all.where((a) => a.status == AppointmentStatus.pending).toList();
                final upcoming  = all.where((a) =>
                a.appointmentDate.isAfter(now) &&
                    (a.status == AppointmentStatus.approved || a.status == AppointmentStatus.rescheduled)).toList();
                final past      = all.where((a) =>
                a.status == AppointmentStatus.completed ||
                    a.status == AppointmentStatus.cancelled ||
                    a.status == AppointmentStatus.rejected ||
                    a.appointmentDate.isBefore(now)).toList();

                return TabBarView(controller: _tab, children: [
                  _ApptList(appts: pending, service: _service, doctorName: widget.doctorName,
                      showActions: true, emptyMsg: 'No pending requests'),
                  _ApptList(appts: upcoming, service: _service, doctorName: widget.doctorName,
                      emptyMsg: 'No upcoming appointments'),
                  _ApptList(appts: past, service: _service, doctorName: widget.doctorName,
                      emptyMsg: 'No past appointments', isPast: true),
                ]);
              })),
        ])));
  }
}

class _ApptList extends StatelessWidget {
  final List<AppointmentModel> appts;
  final DoctorService service;
  final String doctorName, emptyMsg;
  final bool showActions, isPast;
  const _ApptList({required this.appts, required this.service,
    required this.doctorName, required this.emptyMsg,
    this.showActions = false, this.isPast = false});

  @override
  Widget build(BuildContext context) {
    if (appts.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.calendar_today_rounded, size: 44, color: OV.outlineVariant),
        const SizedBox(height: 12),
        Text(emptyMsg, style: GoogleFonts.inter(fontSize: 14, color: OV.onSurfaceVariant)),
      ]));
    }
    return ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: appts.length,
        itemBuilder: (_, i) => _ApptRequestCard(
            appt: appts[i], service: service, showActions: showActions, isPast: isPast));
  }
}

class _ApptRequestCard extends StatefulWidget {
  final AppointmentModel appt;
  final DoctorService service;
  final bool showActions, isPast;
  const _ApptRequestCard({required this.appt, required this.service,
    required this.showActions, required this.isPast});
  @override
  State<_ApptRequestCard> createState() => _ApptRequestCardState();
}

class _ApptRequestCardState extends State<_ApptRequestCard> {
  bool _loading = false;

  Future<void> _approve() async {
    setState(() => _loading = true);
    await widget.service.approveAppointment(widget.appt);
    if (mounted) setState(() => _loading = false);
    if (mounted) _snack('Appointment approved ✓', OV.tertiary);
  }

  Future<void> _reject() async {
    final reason = await _showRejectDialog();
    if (reason == null) return;
    setState(() => _loading = true);
    await widget.service.rejectAppointment(widget.appt, reason: reason);
    if (mounted) setState(() => _loading = false);
    if (mounted) _snack('Appointment rejected', OV.error);
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg, style: GoogleFonts.inter(fontSize: 13)),
        backgroundColor: color, behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
  }

  Future<String?> _showRejectDialog() async {
    final ctrl = TextEditingController();
    return showDialog<String>(context: context, builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Reject Appointment', style: GoogleFonts.manrope(fontSize: 17, fontWeight: FontWeight.w700)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Provide a reason (optional):', style: GoogleFonts.inter(fontSize: 13, color: OV.onSurfaceVariant)),
          const SizedBox(height: 12),
          TextField(controller: ctrl, decoration: InputDecoration(
              hintText: 'e.g. Not available on this date',
              hintStyle: GoogleFonts.inter(fontSize: 13, color: OV.outline),
              filled: true, fillColor: OV.surfaceLow,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: OV.outlineVariant.withOpacity(0.6))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: OV.outlineVariant.withOpacity(0.6))))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: GoogleFonts.inter(color: OV.onSurfaceVariant, fontWeight: FontWeight.w600))),
          ElevatedButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              style: ElevatedButton.styleFrom(backgroundColor: OV.error, elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: Text('Reject', style: GoogleFonts.manrope(fontWeight: FontWeight.w700, color: Colors.white))),
        ]));
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.appt;
    return GestureDetector(
        onTap: () => Navigator.push(context, dSlide(AppointmentDetailDoctorScreen(appointment: a, service: widget.service))),
        child: Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 3))]),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 46, height: 46,
                    decoration: BoxDecoration(color: OV.primaryContainer, borderRadius: BorderRadius.circular(12)),
                    child: Center(child: Text(a.patientName.isNotEmpty ? a.patientName[0].toUpperCase() : 'P',
                        style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w700, color: OV.primary)))),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a.patientName, style: GoogleFonts.manrope(
                      fontSize: 15, fontWeight: FontWeight.w700, color: OV.onSurface)),
                  Text(a.doctorSpecialty, style: GoogleFonts.inter(fontSize: 12, color: OV.onSurfaceVariant)),
                ])),
                DStatusBadge(status: a.status),
              ]),
              const SizedBox(height: 12),
              Container(height: 1, color: OV.outlineVariant.withOpacity(0.3)),
              const SizedBox(height: 10),
              Row(children: [
                Icon(Icons.calendar_today_rounded, size: 13, color: OV.primary),
                const SizedBox(width: 5),
                Text(DateFormat('MMM d, yyyy').format(a.appointmentDate),
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: OV.onSurface)),
                const SizedBox(width: 16),
                Icon(Icons.access_time_rounded, size: 13, color: OV.primary),
                const SizedBox(width: 5),
                Text(a.timeSlot, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: OV.onSurface)),
              ]),
              if (a.notes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(a.notes, style: GoogleFonts.inter(fontSize: 12, color: OV.onSurfaceVariant),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
              if (widget.showActions && !widget.isPast) ...[
                const SizedBox(height: 14),
                _loading
                    ? const Center(child: SizedBox(width: 24, height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2, color: OV.primary)))
                    : Row(children: [
                  Expanded(child: GestureDetector(onTap: _reject,
                      child: Container(height: 40,
                          decoration: BoxDecoration(
                              color: OV.errorContainer,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: OV.error.withOpacity(0.2))),
                          child: Center(child: Text('Reject',
                              style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700, color: OV.error)))))),
                  const SizedBox(width: 10),
                  Expanded(flex: 2, child: GestureDetector(onTap: _approve,
                      child: Container(height: 40,
                          decoration: BoxDecoration(
                              color: OV.slateDark,
                              borderRadius: BorderRadius.circular(10)),
                          child: Center(child: Text('Approve',
                              style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)))))),
                ]),
              ],
            ])));
  }
}