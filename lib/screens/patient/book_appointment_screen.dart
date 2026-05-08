// lib/screens/patient/book_appointment_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../models/patient_profile_model.dart';
import '../../services/appointment_service.dart';

class BookAppointmentScreen extends StatefulWidget {
  final String patientId, patientName;
  const BookAppointmentScreen({super.key, required this.patientId, required this.patientName});
  @override
  State<BookAppointmentScreen> createState() => _BookAppointmentScreenState();
}

class _BookAppointmentScreenState extends State<BookAppointmentScreen> {
  final _service = AppointmentService();
  final _doctors  = DoctorInfo.mockDoctors;

  DoctorInfo? _selectedDoctor;
  DateTime _focusedMonth = DateTime.now();
  DateTime? _selectedDate;
  String? _selectedSlot;
  final _notesCtrl = TextEditingController();
  bool _isLoading = false;

  List<DateTime> get _calendarDays {
    final first = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final last  = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0);
    final start = first.subtract(Duration(days: first.weekday % 7));
    return List.generate(42, (i) => start.add(Duration(days: i)));
  }

  List<String> get _morningSlots => ['08:00 AM', '09:30 AM', '11:00 AM'];
  List<String> get _afternoonSlots => ['01:30 PM', '03:00 PM', '04:30 PM'];

  List<String> get _availableSlots {
    if (_selectedDoctor == null) return [];
    return _selectedDoctor!.availableSlots;
  }

  Future<void> _confirmBooking() async {
    if (_selectedDoctor == null || _selectedDate == null || _selectedSlot == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Please select a doctor, date, and time slot',
              style: GoogleFonts.inter(fontSize: 13)),
          backgroundColor: OV.error, behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
      return;
    }
    setState(() => _isLoading = true);
    try {
      await _service.bookAppointment(
        patientId:       widget.patientId,
        patientName:     widget.patientName,
        doctorId:        _selectedDoctor!.id,
        doctorName:      _selectedDoctor!.name,
        doctorSpecialty: _selectedDoctor!.specialty,
        appointmentDate: _selectedDate!,
        timeSlot:        _selectedSlot!,
        notes:           _notesCtrl.text.trim(),
      );
      if (!mounted) return;
      _showSuccess();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Booking failed: $e', style: GoogleFonts.inter(fontSize: 13)),
          backgroundColor: OV.error, behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSuccess() {
    showModalBottomSheet(context: context, isScrollControlled: true, isDismissible: false,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (_) => Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 64, height: 64,
                  decoration: BoxDecoration(color: OV.tertiaryContainer, shape: BoxShape.circle),
                  child: const Icon(Icons.check_circle_outline_rounded, color: OV.tertiary, size: 34)),
              const SizedBox(height: 16),
              Text('Appointment Requested!', style: GoogleFonts.manrope(fontSize: 20, fontWeight: FontWeight.w700, color: OV.onSurface)),
              const SizedBox(height: 8),
              Text('Your appointment with ${_selectedDoctor!.name} on ${DateFormat('MMM d, yyyy').format(_selectedDate!)} at $_selectedSlot has been submitted and is pending doctor approval.',
                  style: GoogleFonts.inter(fontSize: 13, color: OV.onSurfaceVariant, height: 1.5),
                  textAlign: TextAlign.center),
              const SizedBox(height: 24),
              SizedBox(width: double.infinity, height: 50,
                  child: ElevatedButton(
                      onPressed: () { Navigator.pop(context); Navigator.pop(context); },
                      style: ElevatedButton.styleFrom(backgroundColor: OV.slateDark, foregroundColor: Colors.white,
                          elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                      child: Text('Back to Dashboard', style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w600)))),
            ])));
  }

  @override
  void dispose() { _notesCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OV.background,
      body: SafeArea(child: Column(children: [
        // App bar
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              GestureDetector(onTap: () => Navigator.pop(context),
                  child: Container(padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: OV.outlineVariant.withOpacity(0.5))),
                      child: const Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: OV.onSurface))),
              const SizedBox(width: 12),
              Text('Access Permissions', style: GoogleFonts.manrope(fontSize: 17, fontWeight: FontWeight.w700, color: OV.onSurface)),
            ])),

        Expanded(child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Schedule Your\nConsultation', style: GoogleFonts.manrope(
                fontSize: 28, fontWeight: FontWeight.w700, color: OV.onSurface, height: 1.2, letterSpacing: -0.4)),
            const SizedBox(height: 6),
            Text('Select a specialist and find a time that works for you.',
                style: GoogleFonts.inter(fontSize: 14, color: OV.onSurfaceVariant, height: 1.5)),
            const SizedBox(height: 24),

            // ── Doctor Selection ──────────────────────────────────
            ..._doctors.map((doc) => _DoctorCard(
              doctor: doc,
              isSelected: _selectedDoctor?.id == doc.id,
              onTap: () => setState(() => _selectedDoctor = doc),
            )),

            const SizedBox(height: 24),

            // ── Calendar ─────────────────────────────────────────
            Container(padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 3))]),
                child: Column(children: [
                  // Month nav
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(DateFormat('MMMM yyyy').format(_focusedMonth),
                        style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700, color: OV.onSurface)),
                    Row(children: [
                      GestureDetector(onTap: () => setState(() =>
                      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1)),
                          child: Container(padding: const EdgeInsets.all(4),
                              child: Icon(Icons.chevron_left_rounded, color: OV.onSurface))),
                      GestureDetector(onTap: () => setState(() =>
                      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1)),
                          child: Container(padding: const EdgeInsets.all(4),
                              child: Icon(Icons.chevron_right_rounded, color: OV.onSurface))),
                    ]),
                  ]),
                  const SizedBox(height: 12),
                  // Day headers
                  Row(children: ['SUN','MON','TUE','WED','THU','FRI','SAT'].map((d) =>
                      Expanded(child: Center(child: Text(d,
                          style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700,
                              color: OV.outline, letterSpacing: 0.5))))).toList()),
                  const SizedBox(height: 8),
                  // Days grid
                  GridView.count(
                      crossAxisCount: 7, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 4, crossAxisSpacing: 0,
                      childAspectRatio: 1,
                      children: _calendarDays.map((day) {
                        final isCurrentMonth = day.month == _focusedMonth.month;
                        final isSelected = _selectedDate != null &&
                            day.year == _selectedDate!.year &&
                            day.month == _selectedDate!.month &&
                            day.day == _selectedDate!.day;
                        final isToday = day.year == DateTime.now().year &&
                            day.month == DateTime.now().month && day.day == DateTime.now().day;
                        final isPast = day.isBefore(DateTime.now().subtract(const Duration(days: 1)));
                        return GestureDetector(
                            onTap: isPast || !isCurrentMonth ? null : () =>
                                setState(() { _selectedDate = day; _selectedSlot = null; }),
                            child: Container(
                                margin: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                    color: isSelected ? OV.slateDark : isToday ? OV.primaryContainer : Colors.transparent,
                                    shape: BoxShape.circle),
                                child: Center(child: Text('${day.day}',
                                    style: GoogleFonts.inter(
                                        fontSize: 13,
                                        fontWeight: isSelected || isToday ? FontWeight.w700 : FontWeight.w400,
                                        color: isSelected ? Colors.white
                                            : isToday ? OV.primary
                                            : !isCurrentMonth || isPast ? OV.outlineVariant
                                            : OV.onSurface)))));
                      }).toList()),
                ])),

            const SizedBox(height: 20),

            // ── Time Slots ────────────────────────────────────────
            if (_selectedDate != null) ...[
              Text('Available Time Slots', style: GoogleFonts.manrope(
                  fontSize: 16, fontWeight: FontWeight.w700, color: OV.onSurface)),
              const SizedBox(height: 12),
              _SlotSection(
                  label: 'Morning Sessions',
                  slots: _morningSlots.where((s) => _availableSlots.contains(s) || _selectedDoctor == null).toList(),
                  selectedSlot: _selectedSlot,
                  onSelect: (s) => setState(() => _selectedSlot = s)),
              const SizedBox(height: 16),
              _SlotSection(
                  label: 'Afternoon Sessions',
                  slots: _afternoonSlots.where((s) => _availableSlots.contains(s) || _selectedDoctor == null).toList(),
                  selectedSlot: _selectedSlot,
                  onSelect: (s) => setState(() => _selectedSlot = s)),
              const SizedBox(height: 16),
              Row(children: [
                Icon(Icons.timer_outlined, size: 14, color: OV.outline),
                const SizedBox(width: 6),
                Text('Session Duration', style: GoogleFonts.inter(fontSize: 13, color: OV.onSurfaceVariant)),
                const SizedBox(width: 8),
                Text('45 Minutes Consultation', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: OV.onSurface)),
              ]),
              const SizedBox(height: 20),
            ],

            // ── Notes ─────────────────────────────────────────────
            Text('Notes (Optional)', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: OV.onSurface)),
            const SizedBox(height: 8),
            TextField(
                controller: _notesCtrl,
                maxLines: 3,
                style: GoogleFonts.inter(fontSize: 14, color: OV.onSurface),
                decoration: InputDecoration(
                    hintText: 'Describe your symptoms or reason for visit...',
                    hintStyle: GoogleFonts.inter(fontSize: 13, color: OV.outline),
                    filled: true, fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: OV.outlineVariant.withOpacity(0.6))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: OV.outlineVariant.withOpacity(0.6))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: OV.primary, width: 1.5)),
                    contentPadding: const EdgeInsets.all(14))),

            const SizedBox(height: 24),
          ]),
        )),

        // Confirm button
        Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            decoration: BoxDecoration(color: Colors.white,
                border: Border(top: BorderSide(color: OV.outlineVariant.withOpacity(0.4)))),
            child: Column(children: [
              if (_selectedSlot != null) Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    Icon(Icons.timer_outlined, size: 14, color: OV.outline),
                    const SizedBox(width: 6),
                    Text('Cancellation possible up to 24 hours before the appointment.',
                        style: GoogleFonts.inter(fontSize: 11, color: OV.onSurfaceVariant)),
                  ])),
              SizedBox(width: double.infinity, height: 52,
                  child: ElevatedButton(
                      onPressed: _isLoading ? null : _confirmBooking,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: OV.slateDark, foregroundColor: Colors.white,
                          elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                      child: _isLoading
                          ? const SizedBox(width: 22, height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text('Confirm Booking', style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward_rounded, size: 18),
                      ]))),
            ])),
      ])),
    );
  }
}

class _DoctorCard extends StatelessWidget {
  final DoctorInfo doctor; final bool isSelected; final VoidCallback onTap;
  const _DoctorCard({required this.doctor, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isSelected ? OV.primary : OV.outlineVariant.withOpacity(0.5),
                  width: isSelected ? 2 : 1),
              boxShadow: [BoxShadow(color: isSelected ? OV.primary.withOpacity(0.1) : Colors.black.withOpacity(0.04),
                  blurRadius: isSelected ? 20 : 8, offset: const Offset(0, 4))]),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Doctor image placeholder
            ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                child: Container(height: 160, width: double.infinity,
                    color: OV.primaryContainer,
                    child: Stack(alignment: Alignment.center, children: [
                      Icon(Icons.person_rounded, size: 80, color: OV.primary.withOpacity(0.3)),
                      if (isSelected) Positioned(top: 12, right: 12,
                          child: Container(width: 28, height: 28,
                              decoration: BoxDecoration(color: OV.primary, shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2)),
                              child: const Icon(Icons.check_rounded, color: Colors.white, size: 16))),
                    ]))),
            Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(doctor.name, style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700, color: OV.onSurface)),
              Text('${doctor.specialty} • ${doctor.experienceYears} Yrs Exp.',
                  style: GoogleFonts.inter(fontSize: 12, color: OV.onSurfaceVariant)),
              if (doctor.badge.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(children: [
                  Icon(Icons.star_rounded, size: 12, color: const Color(0xFF8B5000)),
                  const SizedBox(width: 4),
                  Text(doctor.badge, style: GoogleFonts.inter(
                      fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF8B5000))),
                ]),
              ],
            ])),
          ])));
}

class _SlotSection extends StatelessWidget {
  final String label; final List<String> slots;
  final String? selectedSlot; final ValueChanged<String> onSelect;
  const _SlotSection({required this.label, required this.slots,
    required this.selectedSlot, required this.onSelect});

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: OV.onSurfaceVariant)),
    const SizedBox(height: 10),
    Wrap(spacing: 10, runSpacing: 10, children: slots.map((slot) {
      final sel = selectedSlot == slot;
      return GestureDetector(
          onTap: () => onSelect(slot),
          child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                  color: sel ? OV.slateDark : Colors.white,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: sel ? OV.slateDark : OV.outlineVariant.withOpacity(0.6)),
                  boxShadow: sel ? [BoxShadow(color: OV.slateDark.withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 3))] : null),
              child: Text(slot, style: GoogleFonts.inter(
                  fontSize: 13, fontWeight: FontWeight.w600,
                  color: sel ? Colors.white : OV.onSurface))));
    }).toList()),
  ]);
}