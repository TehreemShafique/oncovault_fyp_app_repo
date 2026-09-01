// lib/screens/doctor/appointment_detail_doctor_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../models/appointment_model.dart';
import '../../services/doctor_service.dart';
import 'doctor_widgets.dart';
import 'blood_cancer_ehr_screen.dart';

class AppointmentDetailDoctorScreen extends StatefulWidget {
  final AppointmentModel appointment;
  final DoctorService service;
  const AppointmentDetailDoctorScreen({super.key, required this.appointment, required this.service});
  @override
  State<AppointmentDetailDoctorScreen> createState() => _AppointmentDetailDoctorScreenState();
}

class _AppointmentDetailDoctorScreenState extends State<AppointmentDetailDoctorScreen> {
  late AppointmentModel _appt;
  final _notesCtrl = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _appt = widget.appointment;
    _notesCtrl.text = _appt.doctorNotes;
  }

  @override
  void dispose() { _notesCtrl.dispose(); super.dispose(); }

  Future<void> _approve() async {
    setState(() => _isLoading = true);
    await widget.service.approveAppointment(_appt);
    if (!mounted) return;
    setState(() { _appt = _appt.copyWith(status: AppointmentStatus.approved); _isLoading = false; });
    _snack('Appointment approved ✓', OV.tertiary);
  }

  Future<void> _markComplete() async {
    setState(() => _isLoading = true);
    await widget.service.markAppointmentComplete(_appt);
    if (!mounted) return;
    setState(() { _appt = _appt.copyWith(status: AppointmentStatus.completed); _isLoading = false; });
    _snack('Marked as completed', OV.secondary);
  }

  void _showReschedule() {
    DateTime? newDate; String? newSlot;
    DateTime focusedMonth = DateTime.now();
    showModalBottomSheet(context: context, isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (ctx) => StatefulBuilder(builder: (ctx, setM) {
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
                        fontSize: 20, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 20),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text(DateFormat('MMMM yyyy').format(focusedMonth),
                          style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700)),
                      Row(children: [
                        GestureDetector(onTap: () => setM(() =>
                        focusedMonth = DateTime(focusedMonth.year, focusedMonth.month - 1)),
                            child: const Icon(Icons.chevron_left_rounded)),
                        GestureDetector(onTap: () => setM(() =>
                        focusedMonth = DateTime(focusedMonth.year, focusedMonth.month + 1)),
                            child: const Icon(Icons.chevron_right_rounded)),
                      ]),
                    ]),
                    const SizedBox(height: 10),
                    Row(children: ['S','M','T','W','T','F','S'].map((d) =>
                        Expanded(child: Center(child: Text(d, style: GoogleFonts.inter(
                            fontSize: 11, fontWeight: FontWeight.w700, color: OV.outline))))).toList()),
                    const SizedBox(height: 8),
                    GridView.count(crossAxisCount: 7, shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 4, childAspectRatio: 1,
                        children: calDays.map((day) {
                          final isCur = day.month == focusedMonth.month;
                          final isSel = newDate != null && day.year == newDate!.year &&
                              day.month == newDate!.month && day.day == newDate!.day;
                          final isPast = day.isBefore(DateTime.now().subtract(const Duration(days: 1)));
                          return GestureDetector(
                              onTap: isPast || !isCur ? null : () => setM(() { newDate = day; newSlot = null; }),
                              child: Container(margin: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                      color: isSel ? OV.slateDark : Colors.transparent, shape: BoxShape.circle),
                                  child: Center(child: Text('${day.day}',
                                      style: GoogleFonts.inter(fontSize: 12,
                                          fontWeight: isSel ? FontWeight.w700 : FontWeight.w400,
                                          color: isSel ? Colors.white
                                              : !isCur || isPast ? OV.outlineVariant : OV.onSurface)))));
                        }).toList()),
                    if (newDate != null) ...[
                      const SizedBox(height: 16),
                      Text('Select Time', style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 10),
                      Wrap(spacing: 10, runSpacing: 10,
                          children: ['08:00 AM','09:30 AM','11:00 AM','01:30 PM','03:00 PM','04:30 PM']
                              .map((slot) => GestureDetector(
                              onTap: () => setM(() => newSlot = slot),
                              child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                      color: newSlot == slot ? OV.slateDark : Colors.white,
                                      borderRadius: BorderRadius.circular(100),
                                      border: Border.all(color: newSlot == slot ? OV.slateDark : OV.outlineVariant.withOpacity(0.6))),
                                  child: Text(slot, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600,
                                      color: newSlot == slot ? Colors.white : OV.onSurface)))))
                              .toList()),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(width: double.infinity, height: 50,
                        child: ElevatedButton(
                            onPressed: (newDate == null || newSlot == null) ? null : () async {
                              await widget.service.doctorReschedule(
                                  appt: _appt, newDate: newDate!, newSlot: newSlot!);
                              if (!mounted) return;
                              setState(() => _appt = _appt.copyWith(
                                  status: AppointmentStatus.rescheduled,
                                  appointmentDate: newDate, timeSlot: newSlot));
                              Navigator.pop(ctx);
                              _snack('Appointment rescheduled', OV.primary);
                            },
                            style: ElevatedButton.styleFrom(backgroundColor: OV.slateDark, foregroundColor: Colors.white,
                                elevation: 0, disabledBackgroundColor: OV.outlineVariant,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                            child: Text('Confirm Reschedule', style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w600)))),
                  ]))));
        }));
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg, style: GoogleFonts.inter(fontSize: 13)),
        backgroundColor: color, behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
  }

  @override
  Widget build(BuildContext context) {
    final a = _appt;
    return Scaffold(
        backgroundColor: OV.background,
        body: SafeArea(child: Column(children: [
          DoctorAppBar(title: 'Appointment Details', showBack: true,
              actions: [DStatusBadge(status: a.status)]),

          Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [

            // Patient card
            DCard(child: Row(children: [
              Container(width: 60, height: 60,
                  decoration: BoxDecoration(color: OV.primaryContainer, borderRadius: BorderRadius.circular(16)),
                  child: Center(child: Text(
                      a.patientName.isNotEmpty ? a.patientName[0].toUpperCase() : 'P',
                      style: GoogleFonts.manrope(fontSize: 24, fontWeight: FontWeight.w700, color: OV.primary)))),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a.patientName, style: GoogleFonts.manrope(fontSize: 17, fontWeight: FontWeight.w700, color: OV.onSurface)),
                Text('Patient', style: GoogleFonts.inter(fontSize: 12, color: OV.onSurfaceVariant)),
              ])),
            ])),
            const SizedBox(height: 14),

            // Appointment details
            DCard(child: Column(children: [
              _Row(icon: Icons.calendar_today_rounded, label: 'Date',
                  value: DateFormat('EEEE, MMMM d, yyyy').format(a.appointmentDate)),
              DividerLine(),
              _Row(icon: Icons.access_time_rounded, label: 'Time', value: a.timeSlot),
              DividerLine(),
              _Row(icon: Icons.timer_outlined, label: 'Duration', value: '${a.durationMinutes} Minutes'),
              DividerLine(),
              _Row(icon: Icons.info_outline_rounded, label: 'Status', value: a.status.label),
              if (a.notes.isNotEmpty) ...[DividerLine(), _Row(icon: Icons.notes_rounded, label: 'Patient Notes', value: a.notes)],
            ])),
            const SizedBox(height: 14),

            // Doctor notes
            Text("Doctor's Notes", style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700, color: OV.onSurface)),
            const SizedBox(height: 8),
            Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
                border: Border.all(color: OV.outlineVariant.withOpacity(0.5))),
                child: TextField(controller: _notesCtrl, maxLines: 4,
                    style: GoogleFonts.inter(fontSize: 14, color: OV.onSurface),
                    decoration: InputDecoration(
                        hintText: 'Add clinical notes for this appointment...',
                        hintStyle: GoogleFonts.inter(fontSize: 13, color: OV.outline),
                        filled: true, fillColor: Colors.white,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.all(14)))),
          ]))),

          // Actions
          Container(padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              decoration: BoxDecoration(color: Colors.white,
                  border: Border(top: BorderSide(color: OV.outlineVariant.withOpacity(0.4)))),
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: OV.primary))
                  : Column(mainAxisSize: MainAxisSize.min, children: [
                if (a.status == AppointmentStatus.pending) Row(children: [
                  Expanded(child: OutlinedButton(
                      onPressed: _showReschedule,
                      style: OutlinedButton.styleFrom(foregroundColor: OV.primary,
                          side: BorderSide(color: OV.primary.withOpacity(0.4)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 14)),
                      child: Text('Reschedule', style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700)))),
                  const SizedBox(width: 10),
                  Expanded(flex: 2, child: ElevatedButton(
                      onPressed: _approve,
                      style: ElevatedButton.styleFrom(backgroundColor: OV.slateDark, foregroundColor: Colors.white,
                          elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 14)),
                      child: Text('Approve', style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700)))),
                ]),
                if (a.status == AppointmentStatus.approved) ...[
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        dSlide(BloodCancerEhrScreen(
                          patientId: a.patientId,
                          patientName: a.patientName,
                          doctorId: a.doctorId,
                          doctorName: a.doctorName,
                        )),
                      ),
                      icon: const Icon(Icons.medical_information_rounded, size: 18),
                      label: Text('Open Patient EHR', style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w700)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: OV.primary,
                        side: const BorderSide(color: OV.primary, width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _markComplete,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: OV.tertiary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text('Mark as Completed', style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
                if (a.status != AppointmentStatus.pending && a.status != AppointmentStatus.approved) ...[
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        dSlide(BloodCancerEhrScreen(
                          patientId: a.patientId,
                          patientName: a.patientName,
                          doctorId: a.doctorId,
                          doctorName: a.doctorName,
                        )),
                      ),
                      icon: const Icon(Icons.medical_information_rounded, size: 18),
                      label: Text('Open Patient EHR', style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w700)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: OV.primary,
                        side: BorderSide(color: OV.primary.withOpacity(0.5)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(child: Text('This appointment is ${a.status.label.toLowerCase()}.',
                      style: GoogleFonts.inter(fontSize: 13, color: OV.onSurfaceVariant))),
                ],
              ])),
        ])));
  }
}

class _Row extends StatelessWidget {
  final IconData icon; final String label, value;
  const _Row({required this.icon, required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Container(width: 34, height: 34,
            decoration: BoxDecoration(color: OV.surfaceLow, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 15, color: OV.primary)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: GoogleFonts.inter(fontSize: 10, color: OV.outline,
              fontWeight: FontWeight.w600, letterSpacing: 0.5)),
          Text(value, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: OV.onSurface)),
        ])),
      ]));
}