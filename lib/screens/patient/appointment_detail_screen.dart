// lib/screens/patient/appointment_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../models/appointment_model.dart';
import '../../services/appointment_service.dart';

class AppointmentDetailScreen extends StatefulWidget {
  final AppointmentModel appointment;
  final String patientId, patientName;
  final bool openReschedule;
  const AppointmentDetailScreen({
    super.key, required this.appointment, required this.patientId,
    required this.patientName, this.openReschedule = false});
  @override
  State<AppointmentDetailScreen> createState() => _AppointmentDetailScreenState();
}

class _AppointmentDetailScreenState extends State<AppointmentDetailScreen> {
  late AppointmentModel _appt;
  final _service = AppointmentService();
  bool _isCancelling = false;

  @override
  void initState() {
    super.initState();
    _appt = widget.appointment;
    if (widget.openReschedule) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showReschedule());
    }
  }

  bool get _canModify =>
      _appt.status != AppointmentStatus.cancelled &&
          _appt.status != AppointmentStatus.rejected &&
          _appt.status != AppointmentStatus.completed &&
          _appt.appointmentDate.isAfter(DateTime.now());

  Future<void> _cancelAppointment() async {
    final confirm = await showDialog<bool>(
        context: context, barrierDismissible: false,
        builder: (_) => _ConfirmDialog(
            title: 'Cancel Appointment',
            body: 'Are you sure you want to cancel your appointment with ${_appt.doctorName}? This action cannot be undone.',
            confirmLabel: 'Yes, Cancel', confirmColor: OV.error));
    if (confirm != true) return;

    setState(() => _isCancelling = true);
    await _service.cancelAppointment(_appt.id, widget.patientId);
    if (!mounted) return;
    setState(() {
      _appt = _appt.copyWith(status: AppointmentStatus.cancelled);
      _isCancelling = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Appointment cancelled.', style: GoogleFonts.inter(fontSize: 13)),
        backgroundColor: OV.tertiary, behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
  }

  void _showReschedule() {
    DateTime? newDate;
    String? newSlot;
    DateTime focusedMonth = DateTime.now();

    showModalBottomSheet(
        context: context, isScrollControlled: true, backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (ctx) => StatefulBuilder(builder: (ctx, setModal) {
          final calDays = () {
            final first = DateTime(focusedMonth.year, focusedMonth.month, 1);
            final start = first.subtract(Duration(days: first.weekday % 7));
            return List.generate(42, (i) => start.add(Duration(days: i)));
          }();
          return DraggableScrollableSheet(
              initialChildSize: 0.85, maxChildSize: 0.95, minChildSize: 0.5, expand: false,
              builder: (_, sc) => SingleChildScrollView(controller: sc,
                  child: Padding(padding: const EdgeInsets.all(24), child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Center(child: Container(width: 40, height: 4,
                        decoration: BoxDecoration(color: OV.outlineVariant, borderRadius: BorderRadius.circular(2)))),
                    const SizedBox(height: 20),
                    Text('Reschedule Appointment', style: GoogleFonts.manrope(
                        fontSize: 20, fontWeight: FontWeight.w700, color: OV.onSurface)),
                    const SizedBox(height: 6),
                    Text('Select a new date and time for your consultation.',
                        style: GoogleFonts.inter(fontSize: 13, color: OV.onSurfaceVariant)),
                    const SizedBox(height: 20),

                    // Month nav
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text(DateFormat('MMMM yyyy').format(focusedMonth),
                          style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700)),
                      Row(children: [
                        GestureDetector(onTap: () => setModal(() =>
                        focusedMonth = DateTime(focusedMonth.year, focusedMonth.month - 1)),
                            child: const Icon(Icons.chevron_left_rounded)),
                        GestureDetector(onTap: () => setModal(() =>
                        focusedMonth = DateTime(focusedMonth.year, focusedMonth.month + 1)),
                            child: const Icon(Icons.chevron_right_rounded)),
                      ]),
                    ]),
                    const SizedBox(height: 12),

                    Row(children: ['S','M','T','W','T','F','S'].map((d) =>
                        Expanded(child: Center(child: Text(d,
                            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700,
                                color: OV.outline))))).toList()),
                    const SizedBox(height: 8),
                    GridView.count(crossAxisCount: 7, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 4, childAspectRatio: 1,
                        children: calDays.map((day) {
                          final isCurMonth = day.month == focusedMonth.month;
                          final isSel = newDate != null && day.year == newDate!.year &&
                              day.month == newDate!.month && day.day == newDate!.day;
                          final isPast = day.isBefore(DateTime.now().subtract(const Duration(days: 1)));
                          return GestureDetector(
                              onTap: isPast || !isCurMonth ? null : () => setModal(() { newDate = day; newSlot = null; }),
                              child: Container(margin: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                      color: isSel ? OV.slateDark : Colors.transparent,
                                      shape: BoxShape.circle),
                                  child: Center(child: Text('${day.day}',
                                      style: GoogleFonts.inter(fontSize: 12,
                                          fontWeight: isSel ? FontWeight.w700 : FontWeight.w400,
                                          color: isSel ? Colors.white
                                              : !isCurMonth || isPast ? OV.outlineVariant
                                              : OV.onSurface)))));
                        }).toList()),

                    if (newDate != null) ...[
                      const SizedBox(height: 16),
                      Text('Select Time', style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 10),
                      Wrap(spacing: 10, runSpacing: 10,
                          children: ['08:00 AM','09:30 AM','11:00 AM','01:30 PM','03:00 PM','04:30 PM']
                              .map((slot) {
                            final sel = newSlot == slot;
                            return GestureDetector(
                                onTap: () => setModal(() => newSlot = slot),
                                child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    decoration: BoxDecoration(
                                        color: sel ? OV.slateDark : Colors.white,
                                        borderRadius: BorderRadius.circular(100),
                                        border: Border.all(color: sel ? OV.slateDark : OV.outlineVariant.withOpacity(0.6))),
                                    child: Text(slot, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600,
                                        color: sel ? Colors.white : OV.onSurface))));
                          }).toList()),
                    ],

                    const SizedBox(height: 24),
                    SizedBox(width: double.infinity, height: 50,
                        child: ElevatedButton(
                            onPressed: (newDate == null || newSlot == null) ? null : () async {
                              await _service.rescheduleAppointment(
                                  appointmentId: _appt.id, patientId: widget.patientId,
                                  newDate: newDate!, newTimeSlot: newSlot!);
                              if (!mounted) return;
                              setState(() => _appt = _appt.copyWith(
                                  status: AppointmentStatus.rescheduled,
                                  appointmentDate: newDate, timeSlot: newSlot));
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  content: Text('Appointment rescheduled!', style: GoogleFonts.inter(fontSize: 13)),
                                  backgroundColor: OV.tertiary, behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
                            },
                            style: ElevatedButton.styleFrom(backgroundColor: OV.slateDark, foregroundColor: Colors.white,
                                elevation: 0, disabledBackgroundColor: OV.outlineVariant,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                            child: Text('Confirm Reschedule', style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w600)))),
                  ]))));
        }));
  }

  @override
  Widget build(BuildContext context) {
    final a = _appt;
    return Scaffold(
      backgroundColor: OV.background,
      body: SafeArea(child: Column(children: [
        // App bar
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              GestureDetector(onTap: () => Navigator.pop(context),
                  child: Container(padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: OV.outlineVariant.withOpacity(0.5))),
                      child: const Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: OV.onSurface))),
              Text('Appointment Details', style: GoogleFonts.manrope(fontSize: 17, fontWeight: FontWeight.w700, color: OV.onSurface)),
              _StatusBadge(status: a.status),
            ])),

        Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Doctor card
          Container(padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 16, offset: const Offset(0, 4))]),
              child: Row(children: [
                Container(width: 60, height: 60,
                    decoration: BoxDecoration(color: OV.primaryContainer, borderRadius: BorderRadius.circular(16)),
                    child: Center(child: Text(a.doctorName.split(' ').last[0],
                        style: GoogleFonts.manrope(fontSize: 24, fontWeight: FontWeight.w700, color: OV.primary)))),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a.doctorName, style: GoogleFonts.manrope(fontSize: 17, fontWeight: FontWeight.w700, color: OV.onSurface)),
                  Text(a.doctorSpecialty, style: GoogleFonts.inter(fontSize: 13, color: OV.onSurfaceVariant)),
                ])),
              ])),

          const SizedBox(height: 16),

          // Date/time/duration
          Container(padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 3))]),
              child: Column(children: [
                _DetailRow(icon: Icons.calendar_today_rounded, label: 'Date',
                    value: DateFormat('EEEE, MMMM d, yyyy').format(a.appointmentDate)),
                _Divider(),
                _DetailRow(icon: Icons.access_time_rounded, label: 'Time', value: a.timeSlot),
                _Divider(),
                _DetailRow(icon: Icons.timer_outlined, label: 'Duration', value: '${a.durationMinutes} Minutes'),
                _Divider(),
                _DetailRow(icon: Icons.info_outline_rounded, label: 'Status', value: a.status.label),
              ])),

          if (a.notes.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 3))]),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Your Notes', style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700, color: OV.onSurface)),
                  const SizedBox(height: 8),
                  Text(a.notes, style: GoogleFonts.inter(fontSize: 13, color: OV.onSurfaceVariant, height: 1.5)),
                ])),
          ],

          if (a.doctorNotes.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: OV.primaryContainer.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: OV.primary.withOpacity(0.2))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.medical_information_outlined, size: 16, color: OV.primary),
                    const SizedBox(width: 8),
                    Text("Doctor's Notes", style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700, color: OV.primary)),
                  ]),
                  const SizedBox(height: 8),
                  Text(a.doctorNotes, style: GoogleFonts.inter(fontSize: 13, color: OV.onSurface, height: 1.5)),
                ])),
          ],

          // Status info card
          if (a.status == AppointmentStatus.pending) ...[
            const SizedBox(height: 16),
            Container(padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF8B5000).withOpacity(0.2))),
                child: Row(children: [
                  const Icon(Icons.access_time_rounded, color: Color(0xFF8B5000), size: 18),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Your appointment is awaiting doctor confirmation. You will be notified once approved.',
                      style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF8B5000), height: 1.4))),
                ])),
          ],
        ]))),

        // Bottom action buttons
        if (_canModify) Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            decoration: BoxDecoration(color: Colors.white,
                border: Border(top: BorderSide(color: OV.outlineVariant.withOpacity(0.4)))),
            child: Row(children: [
              Expanded(child: OutlinedButton(
                  onPressed: _isCancelling ? null : _cancelAppointment,
                  style: OutlinedButton.styleFrom(
                      foregroundColor: OV.error, side: BorderSide(color: OV.error.withOpacity(0.5)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: _isCancelling
                      ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: OV.error))
                      : Text('Cancel', style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600)))),
              const SizedBox(width: 12),
              Expanded(child: ElevatedButton(
                  onPressed: _showReschedule,
                  style: ElevatedButton.styleFrom(backgroundColor: OV.slateDark, foregroundColor: Colors.white,
                      elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: Text('Reschedule', style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600)))),
            ])),
      ])),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon; final String label, value;
  const _DetailRow({required this.icon, required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 36, height: 36,
        decoration: BoxDecoration(color: OV.surfaceLow, borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, size: 16, color: OV.primary)),
    const SizedBox(width: 12),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: GoogleFonts.inter(fontSize: 11, color: OV.outline, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
      Text(value, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: OV.onSurface)),
    ])),
  ]);
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(margin: const EdgeInsets.symmetric(vertical: 12),
      height: 1, color: OV.outlineVariant.withOpacity(0.3));
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

class _ConfirmDialog extends StatelessWidget {
  final String title, body, confirmLabel; final Color confirmColor;
  const _ConfirmDialog({required this.title, required this.body,
    required this.confirmLabel, required this.confirmColor});
  @override
  Widget build(BuildContext context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(title, style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w700)),
      content: Text(body, style: GoogleFonts.inter(fontSize: 14, color: OV.onSurfaceVariant, height: 1.5)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false),
            child: Text('Keep it', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: OV.onSurfaceVariant))),
        ElevatedButton(onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: confirmColor, elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: Text(confirmLabel, style: GoogleFonts.manrope(fontWeight: FontWeight.w700, color: Colors.white))),
      ]);
}