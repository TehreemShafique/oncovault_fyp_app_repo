// lib/screens/patient/appointment_list_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../models/appointment_model.dart';
import '../../services/appointment_service.dart';
import 'appointment_detail_screen.dart';
import 'book_appointment_screen.dart';

class AppointmentListScreen extends StatefulWidget {
  final String patientId, patientName;
  const AppointmentListScreen({super.key, required this.patientId, required this.patientName});
  @override
  State<AppointmentListScreen> createState() => _AppointmentListScreenState();
}

class _AppointmentListScreenState extends State<AppointmentListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  final _service = AppointmentService();

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OV.background,
      body: SafeArea(child: Column(children: [
        // Header
        Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Appointments', style: GoogleFonts.manrope(
                  fontSize: 28, fontWeight: FontWeight.w700, color: OV.onSurface, letterSpacing: -0.4)),
              Text('Manage your medical consultations and history.',
                  style: GoogleFonts.inter(fontSize: 13, color: OV.onSurfaceVariant, height: 1.5)),
            ])),

        const SizedBox(height: 20),

        // Tab bar
        Padding(padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(height: 48, padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: OV.outlineVariant.withOpacity(0.5))),
                child: TabBar(
                    controller: _tab,
                    indicator: BoxDecoration(color: OV.slateDark, borderRadius: BorderRadius.circular(10)),
                    labelStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
                    unselectedLabelStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
                    labelColor: Colors.white, unselectedLabelColor: OV.onSurfaceVariant,
                    dividerColor: Colors.transparent,
                    tabs: const [Tab(text: 'Upcoming'), Tab(text: 'Past')]))),

        const SizedBox(height: 16),

        Expanded(child: StreamBuilder<List<AppointmentModel>>(
          stream: _service.watchPatientAppointments(widget.patientId),
          builder: (_, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: OV.primary));
            }
            final all = snap.data ?? [];
            final now = DateTime.now();
            // Upcoming: status-based (not date-based) so pending stays visible
            final upcoming = all.where((a) =>
            a.status == AppointmentStatus.pending ||
                a.status == AppointmentStatus.approved ||
                a.status == AppointmentStatus.rescheduled).toList();
            final past = all.where((a) =>
            a.status == AppointmentStatus.completed ||
                a.status == AppointmentStatus.cancelled ||
                a.status == AppointmentStatus.rejected).toList();

            return TabBarView(controller: _tab, children: [
              _AppointmentList(
                  appointments: upcoming, patientId: widget.patientId,
                  patientName: widget.patientName, service: _service, isEmpty: upcoming.isEmpty,
                  emptyMessage: 'No upcoming appointments'),
              _AppointmentList(
                  appointments: past, patientId: widget.patientId,
                  patientName: widget.patientName, service: _service, isEmpty: past.isEmpty,
                  emptyMessage: 'No past appointments', isPast: true),
            ]);
          },
        )),
      ])),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: () => Navigator.push(context, _slide(
              BookAppointmentScreen(patientId: widget.patientId, patientName: widget.patientName))),
          backgroundColor: OV.primary, foregroundColor: Colors.white,
          icon: const Icon(Icons.add_rounded),
          label: Text('Book', style: GoogleFonts.manrope(fontWeight: FontWeight.w700))),
    );
  }
}

class _AppointmentList extends StatelessWidget {
  final List<AppointmentModel> appointments;
  final String patientId, patientName;
  final AppointmentService service;
  final bool isEmpty, isPast;
  final String emptyMessage;

  const _AppointmentList({
    required this.appointments, required this.patientId, required this.patientName,
    required this.service, required this.isEmpty, required this.emptyMessage,
    this.isPast = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isEmpty) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.calendar_today_rounded, size: 48, color: OV.outlineVariant),
      const SizedBox(height: 12),
      Text(emptyMessage, style: GoogleFonts.inter(fontSize: 15, color: OV.onSurfaceVariant)),
    ]));

    return ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: appointments.length,
        itemBuilder: (_, i) => _AppointmentCard(
            appointment: appointments[i],
            patientId: patientId, patientName: patientName,
            service: service, isPast: isPast));
  }
}

class _AppointmentCard extends StatelessWidget {
  final AppointmentModel appointment;
  final String patientId, patientName;
  final AppointmentService service;
  final bool isPast;
  const _AppointmentCard({required this.appointment, required this.patientId,
    required this.patientName, required this.service, required this.isPast});

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    return GestureDetector(
        onTap: () => Navigator.push(context, _slide(AppointmentDetailScreen(
            appointment: a, patientId: patientId, patientName: patientName))),
        child: Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 3))]),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Doctor avatar
              Container(width: 48, height: 48, decoration: BoxDecoration(
                  color: OV.primaryContainer, borderRadius: BorderRadius.circular(14)),
                  child: Center(child: Text(a.doctorName.split(' ').last[0],
                      style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w700, color: OV.primary)))),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a.doctorName, style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700, color: OV.onSurface)),
                Text(a.doctorSpecialty, style: GoogleFonts.inter(fontSize: 12, color: OV.onSurfaceVariant)),
              ])),
              _StatusBadge(status: a.status),
            ]),
            const SizedBox(height: 14),
            Container(height: 1, color: OV.outlineVariant.withOpacity(0.3)),
            const SizedBox(height: 12),
            Row(children: [
              Icon(Icons.calendar_today_rounded, size: 14, color: OV.primary),
              const SizedBox(width: 6),
              Text(DateFormat('MMM d, yyyy').format(a.appointmentDate),
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: OV.onSurface)),
              const SizedBox(width: 20),
              Icon(Icons.access_time_rounded, size: 14, color: OV.primary),
              const SizedBox(width: 6),
              Text(a.timeSlot, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: OV.onSurface)),
            ]),
            if (!isPast && a.status != AppointmentStatus.cancelled && a.status != AppointmentStatus.rejected) ...[
              const SizedBox(height: 14),
              Row(children: [
                // Cancel button
                Expanded(child: _CancelButton(
                    appointment: a,
                    patientId: patientId,
                    service: service)),
                const SizedBox(width: 10),
                // Reschedule button
                Expanded(flex: 2, child: GestureDetector(
                    onTap: () => Navigator.push(context, _slide(AppointmentDetailScreen(
                        appointment: a, patientId: patientId, patientName: patientName,
                        openReschedule: true))),
                    child: Container(height: 42,
                        decoration: BoxDecoration(color: OV.slateDark, borderRadius: BorderRadius.circular(12)),
                        child: Center(child: Text('Reschedule',
                            style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)))))),
              ]),
            ],
            if (isPast && a.status == AppointmentStatus.completed)
              Padding(padding: const EdgeInsets.only(top: 10),
                  child: Text('Completed', style: GoogleFonts.inter(
                      fontSize: 13, fontWeight: FontWeight.w600, color: OV.primary))),
          ]),
        ));
  }
}


// ── Inline cancel button with confirmation ────────────────────────────────────
class _CancelButton extends StatefulWidget {
  final AppointmentModel appointment;
  final String patientId;
  final AppointmentService service;
  const _CancelButton({required this.appointment, required this.patientId, required this.service});
  @override
  State<_CancelButton> createState() => _CancelButtonState();
}

class _CancelButtonState extends State<_CancelButton> {
  bool _cancelling = false;

  Future<void> _cancel() async {
    final confirm = await showDialog<bool>(context: context,
        builder: (_) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text('Cancel Appointment', style: GoogleFonts.manrope(fontSize: 17, fontWeight: FontWeight.w700)),
            content: Text('Are you sure you want to cancel your appointment with ${widget.appointment.doctorName}?',
                style: GoogleFonts.inter(fontSize: 14, color: OV.onSurfaceVariant, height: 1.5)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false),
                  child: Text('Keep it', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: OV.onSurfaceVariant))),
              ElevatedButton(onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(backgroundColor: OV.error, elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  child: Text('Yes, Cancel', style: GoogleFonts.manrope(fontWeight: FontWeight.w700, color: Colors.white))),
            ]));
    if (confirm != true || !mounted) return;
    setState(() => _cancelling = true);
    await widget.service.cancelAppointment(widget.appointment.id, widget.patientId);
    if (mounted) setState(() => _cancelling = false);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: _cancelling ? null : _cancel,
      child: Container(height: 42,
          decoration: BoxDecoration(
              color: OV.errorContainer,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: OV.error.withOpacity(0.2))),
          child: _cancelling
              ? const Center(child: SizedBox(width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: OV.error)))
              : Center(child: Text('Cancel',
              style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700, color: OV.error)))));
}

class _StatusBadge extends StatelessWidget {
  final AppointmentStatus status;
  const _StatusBadge({required this.status});
  Color get _bg {
    switch (status) {
      case AppointmentStatus.approved:    return OV.tertiaryContainer;
      case AppointmentStatus.pending:     return const Color(0xFFFFF3E0);
      case AppointmentStatus.cancelled:   return OV.errorContainer;
      case AppointmentStatus.rejected:    return OV.errorContainer;
      case AppointmentStatus.completed:   return OV.secondaryContainer;
      case AppointmentStatus.rescheduled: return OV.primaryContainer;
    }
  }
  Color get _fg {
    switch (status) {
      case AppointmentStatus.approved:    return OV.tertiary;
      case AppointmentStatus.pending:     return const Color(0xFF8B5000);
      case AppointmentStatus.cancelled:   return OV.error;
      case AppointmentStatus.rejected:    return OV.error;
      case AppointmentStatus.completed:   return OV.secondary;
      case AppointmentStatus.rescheduled: return OV.primary;
    }
  }
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(100)),
      child: Text(status.label, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: _fg)));
}

PageRoute _slide(Widget page) => PageRouteBuilder(
    pageBuilder: (_, a, __) => page,
    transitionDuration: const Duration(milliseconds: 350),
    transitionsBuilder: (_, a, __, child) {
      final t = Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
          .chain(CurveTween(curve: Curves.easeOutCubic));
      return SlideTransition(position: a.drive(t), child: child);
    });