// lib/screens/patient/book_appointment_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../theme/app_theme.dart';
import '../../services/appointment_service.dart';

class BookAppointmentScreen extends StatefulWidget {
  final String patientId, patientName;
  const BookAppointmentScreen({super.key, required this.patientId, required this.patientName});
  @override
  State<BookAppointmentScreen> createState() => _BookAppointmentScreenState();
}

class _BookAppointmentScreenState extends State<BookAppointmentScreen> {
  final _service = AppointmentService();
  List<_RealDoctor> _doctors = [];
  bool _loadingDoctors = true;

  _RealDoctor? _selectedDoctor;
  DateTime _focusedMonth = DateTime.now();
  DateTime? _selectedDate;
  String? _selectedSlot;
  final _notesCtrl = TextEditingController();
  bool _isLoading = false;

  // Booked slot keys stream — updates whenever the doctor's slots change.
  // Key format: "yyyy-MM-dd_HH:mm AM/PM"
  Set<String> _bookedSlotKeys = {};

  List<DateTime> get _calendarDays {
    final first = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final last  = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0);
    final start = first.subtract(Duration(days: first.weekday % 7));
    return List.generate(42, (i) => start.add(Duration(days: i)));
  }

  List<String> get _morningSlots   => ['08:00 AM', '09:30 AM', '11:00 AM'];
  List<String> get _afternoonSlots => ['01:30 PM', '03:00 PM', '04:30 PM'];

  List<String> get _availableSlots => _selectedDoctor?.availableSlots ?? [];

  // Returns true if this slot on the selected date is already taken.
  bool _isSlotBooked(String slot) {
    if (_selectedDate == null || _selectedDoctor == null) return false;
    final y = _selectedDate!.year.toString().padLeft(4, '0');
    final m = _selectedDate!.month.toString().padLeft(2, '0');
    final d = _selectedDate!.day.toString().padLeft(2, '0');
    final key = '${y}-${m}-${d}_$slot';
    return _bookedSlotKeys.contains(key);
  }

  // ── Doctor selection ──────────────────────────────────────────
  void _selectDoctor(_RealDoctor doc) {
    if (_selectedDoctor?.id == doc.id) return;
    setState(() {
      _selectedDoctor = doc;
      _selectedSlot   = null;   // clear stale slot selection
      _bookedSlotKeys = {};     // reset until new stream arrives
    });
  }

  // ── Confirm booking ───────────────────────────────────────────
  Future<void> _confirmBooking() async {
    if (_selectedDoctor == null || _selectedDate == null || _selectedSlot == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Please select a doctor, date, and time slot',
              style: GoogleFonts.inter(fontSize: 13)),
          backgroundColor: OV.error, behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
      return;
    }

    // Guard: re-check the slot is still free at booking time.
    if (_isSlotBooked(_selectedSlot!)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('That slot was just taken. Please select another time.',
              style: GoogleFonts.inter(fontSize: 13)),
          backgroundColor: OV.error, behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
      setState(() => _selectedSlot = null);
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _service.bookAppointment(
        patientId:       widget.patientId,
        patientName:     widget.patientName,
        doctorId:        _selectedDoctor?.id ?? '',
        doctorName:      _selectedDoctor?.name ?? '',
        doctorSpecialty: _selectedDoctor?.specialty ?? '',
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
              Text('Your appointment with ${_selectedDoctor?.name ?? 'your doctor'} on ${DateFormat('MMM d, yyyy').format(_selectedDate!)} at ${_selectedSlot ?? ''} has been submitted and is pending doctor approval.',
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
  void initState() {
    super.initState();
    _loadDoctors();
  }

  Future<void> _loadDoctors() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('doctors').get();
      final docs = snap.docs
          .where((d) => (d.data()['isAvailable'] ?? true) == true)
          .map((d) {
        final data = d.data();
        return _RealDoctor(
          id:              d.id,
          name:            data['name'] ?? 'Doctor',
          specialty:       data['specialty'] ?? 'Specialist',
          experienceYears: data['experienceYears'] ?? 0,
          badge:           data['subSpecialty'] ?? '',
          availableSlots:  List<String>.from(data['availableSlots'] ?? [
            '08:00 AM', '09:30 AM', '11:00 AM',
            '01:30 PM', '03:00 PM', '04:30 PM',
          ]),
        );
      }).toList();
      if (mounted) setState(() { _doctors = docs; _loadingDoctors = false; });
    } catch (e) {
      if (mounted) setState(() => _loadingDoctors = false);
    }
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
              Text('Schedule Appointment', style: GoogleFonts.manrope(fontSize: 17, fontWeight: FontWeight.w700, color: OV.onSurface)),
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
            if (_loadingDoctors)
              const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: CircularProgressIndicator(color: OV.primary)))
            else if (_doctors.isEmpty)
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: Text(
                      'No doctors available. Please check back later.',
                      style: GoogleFonts.inter(fontSize: 13, color: OV.onSurfaceVariant),
                      textAlign: TextAlign.center)))
            else
            // Stream booked slots whenever the selected doctor changes.
              ..._doctors.map((doc) {
                if (doc.id == _selectedDoctor?.id) {
                  // Wrap selected doctor card in a StreamBuilder so slot
                  // availability updates in real-time.
                  return StreamBuilder<Set<String>>(
                    stream: _service.watchBookedSlots(doc.id),
                    builder: (_, snap) {
                      if (snap.hasData) {
                        // Update local set without calling setState to avoid
                        // full rebuild; the slot section rebuilds via its own
                        // parent setState when the date/slot changes anyway.
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted && _bookedSlotKeys != snap.data!) {
                            setState(() => _bookedSlotKeys = snap.data!);
                          }
                        });
                      }
                      return _DoctorCard(
                        doctor: doc,
                        isSelected: true,
                        onTap: () => _selectDoctor(doc),
                      );
                    },
                  );
                }
                return _DoctorCard(
                  doctor: doc,
                  isSelected: false,
                  onTap: () => _selectDoctor(doc),
                );
              }),

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
              const SizedBox(height: 4),
              // Legend
              Row(children: [
                _LegendDot(color: OV.slateDark),
                const SizedBox(width: 4),
                Text('Selected', style: GoogleFonts.inter(fontSize: 11, color: OV.onSurfaceVariant)),
                const SizedBox(width: 14),
                _LegendDot(color: OV.errorContainer, border: OV.error.withOpacity(0.4)),
                const SizedBox(width: 4),
                Text('Not Available', style: GoogleFonts.inter(fontSize: 11, color: OV.onSurfaceVariant)),
              ]),
              const SizedBox(height: 12),
              _SlotSection(
                  label: 'Morning Sessions',
                  slots: _morningSlots.where((s) => _availableSlots.contains(s) || _selectedDoctor == null).toList(),
                  selectedSlot: _selectedSlot,
                  bookedChecker: _isSlotBooked,
                  onSelect: (s) {
                    if (_isSlotBooked(s)) return; // ignore taps on booked slots
                    setState(() => _selectedSlot = s);
                  }),
              const SizedBox(height: 16),
              _SlotSection(
                  label: 'Afternoon Sessions',
                  slots: _afternoonSlots.where((s) => _availableSlots.contains(s) || _selectedDoctor == null).toList(),
                  selectedSlot: _selectedSlot,
                  bookedChecker: _isSlotBooked,
                  onSelect: (s) {
                    if (_isSlotBooked(s)) return;
                    setState(() => _selectedSlot = s);
                  }),
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

// ── Small legend dot ──────────────────────────────────────────────────────────
class _LegendDot extends StatelessWidget {
  final Color color;
  final Color? border;
  const _LegendDot({required this.color, this.border});
  @override
  Widget build(BuildContext context) => Container(
      width: 12, height: 12,
      decoration: BoxDecoration(
          color: color, shape: BoxShape.circle,
          border: border != null ? Border.all(color: border!, width: 1) : null));
}

// Real doctor data fetched from Firestore
class _RealDoctor {
  final String id, name, specialty, badge;
  final int experienceYears;
  final List<String> availableSlots;
  _RealDoctor({
    required this.id, required this.name, required this.specialty,
    required this.badge, required this.experienceYears,
    required this.availableSlots,
  });
}

class _DoctorCard extends StatelessWidget {
  final _RealDoctor doctor; final bool isSelected; final VoidCallback onTap;
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

// ── Slot section with booked-state support ────────────────────────────────────
class _SlotSection extends StatelessWidget {
  final String label;
  final List<String> slots;
  final String? selectedSlot;
  final bool Function(String slot) bookedChecker;
  final ValueChanged<String> onSelect;

  const _SlotSection({
    required this.label,
    required this.slots,
    required this.selectedSlot,
    required this.bookedChecker,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: OV.onSurfaceVariant)),
    const SizedBox(height: 10),
    Wrap(spacing: 10, runSpacing: 10, children: slots.map((slot) {
      final isSelected = selectedSlot == slot;
      final isBooked   = bookedChecker(slot);

      return GestureDetector(
          onTap: isBooked ? null : () => onSelect(slot),
          child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                // Booked → muted red; Selected → dark; Default → white
                  color: isBooked
                      ? OV.errorContainer
                      : isSelected
                      ? OV.slateDark
                      : Colors.white,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                      color: isBooked
                          ? OV.error.withOpacity(0.35)
                          : isSelected
                          ? OV.slateDark
                          : OV.outlineVariant.withOpacity(0.6)),
                  boxShadow: isSelected
                      ? [BoxShadow(color: OV.slateDark.withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 3))]
                      : null),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (isBooked) ...[
                  Icon(Icons.block_rounded, size: 12, color: OV.error.withOpacity(0.7)),
                  const SizedBox(width: 5),
                ],
                Text(
                    isBooked ? '$slot · Not Available' : slot,
                    style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isBooked
                            ? OV.error.withOpacity(0.8)
                            : isSelected
                            ? Colors.white
                            : OV.onSurface)),
              ])));
    }).toList()),
  ]);
}