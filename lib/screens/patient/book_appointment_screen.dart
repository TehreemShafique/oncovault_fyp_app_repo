// lib/screens/patient/book_appointment_screen.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../theme/app_theme.dart';
import '../../services/appointment_service.dart';
import '../../models/doctor_availability_model.dart';
import '../../utils/slot_generator.dart';

class BookAppointmentScreen extends StatefulWidget {
  final String patientId, patientName;
  const BookAppointmentScreen({
    super.key,
    required this.patientId,
    required this.patientName,
  });

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

  // Real-time booked slots subscription and cache
  StreamSubscription<Set<String>>? _bookedSlotsSub;
  Set<String> _bookedSlotKeys = {};

  List<DateTime> get _calendarDays {
    final first = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final start = first.subtract(Duration(days: first.weekday % 7));
    return List.generate(
      42,
      (i) => DateTime(start.year, start.month, start.day + i),
    );
  }

  String _formatDateKey(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  bool _isDateAvailable(DateTime day) {
    if (_selectedDoctor == null) return true;
    final avail = _selectedDoctor!.availability;
    if (!_selectedDoctor!.isAvailable) return false;
    final dateKey = _formatDateKey(day);
    if (avail.blockedDates.contains(dateKey)) return false;

    if (avail.state == DoctorAvailabilityState.legacy) {
      const legacyMap = {
        DateTime.monday: 'Mon',
        DateTime.tuesday: 'Tue',
        DateTime.wednesday: 'Wed',
        DateTime.thursday: 'Thu',
        DateTime.friday: 'Fri',
        DateTime.saturday: 'Sat',
        DateTime.sunday: 'Sun',
      };
      final abbr = legacyMap[day.weekday];
      return abbr != null && avail.legacyDays.contains(abbr);
    } else if (avail.state == DoctorAvailabilityState.structured) {
      final s = avail.weeklySchedule.getDay(day.weekday);
      return s.enabled;
    } else {
      // Standard Mon-Fri clinic working days
      return day.weekday != DateTime.saturday && day.weekday != DateTime.sunday;
    }
  }

  List<String> get _currentDaySlots {
    if (_selectedDoctor == null || _selectedDate == null) return const [];
    final avail = _selectedDoctor!.availability;
    if (!_selectedDoctor!.isAvailable) return const [];
    final dateKey = _formatDateKey(_selectedDate!);
    if (avail.blockedDates.contains(dateKey)) return const [];

    List<String> rawSlots;
    if (avail.state == DoctorAvailabilityState.structured) {
      final daySchedule = avail.weeklySchedule.getDay(_selectedDate!.weekday);
      if (!daySchedule.enabled) return const [];
      rawSlots = SlotGenerator.generateSlots(
        daySchedule,
        avail.slotDurationMinutes,
      );
    } else {
      rawSlots = avail.legacySlots.isNotEmpty
          ? avail.legacySlots
          : const [
              '08:00 AM',
              '09:30 AM',
              '11:00 AM',
              '01:30 PM',
              '03:00 PM',
              '04:30 PM',
            ];
    }

    return rawSlots.where((slot) {
      return SlotGenerator.isSlotValid(
        date: _selectedDate!,
        timeSlot: slot,
        availability: avail.state == DoctorAvailabilityState.structured
            ? avail
            : DoctorAvailability.legacy(
                legacyDays: avail.legacyDays.isNotEmpty
                    ? avail.legacyDays
                    : const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'],
                legacySlots: rawSlots,
              ),
        isDoctorAvailable: _selectedDoctor!.isAvailable,
      );
    }).toList();
  }

  List<String> get _morningSlots => _currentDaySlots.where((slot) {
        final m = SlotGenerator.parse12Hour(slot);
        return m != null && m < 720;
      }).toList();

  List<String> get _afternoonSlots => _currentDaySlots.where((slot) {
        final m = SlotGenerator.parse12Hour(slot);
        return m != null && m >= 720;
      }).toList();

  bool _isSlotBooked(String slot) {
    if (_selectedDate == null || _selectedDoctor == null) return false;
    final dateKey = _formatDateKey(_selectedDate!);
    final slotKey = '${dateKey}_$slot';

    if (_bookedSlotKeys.contains(slotKey)) return true;
    if (_selectedDoctor!.availability.blockedSlots.contains(slotKey)) return true;

    final candidateInterval = AppointmentInterval.fromSlot(
      dateKey,
      slot,
      _selectedDoctor!.availability.slotDurationMinutes,
    );
    if (candidateInterval == null) return true;

    for (final bookedKey in _bookedSlotKeys) {
      if (bookedKey.startsWith('${dateKey}_')) {
        final bookedTime = bookedKey.substring(dateKey.length + 1);
        final bookedInterval = AppointmentInterval.fromSlot(
          dateKey,
          bookedTime,
          _selectedDoctor!.availability.slotDurationMinutes,
        );
        if (bookedInterval != null && candidateInterval.overlaps(bookedInterval)) {
          return true;
        }
      }
    }

    return false;
  }

  void _selectDoctor(_RealDoctor doc) {
    if (_selectedDoctor?.id == doc.id) return;
    _bookedSlotsSub?.cancel();
    setState(() {
      _selectedDoctor = doc;
      _selectedSlot = null;
      _bookedSlotKeys = {};
    });

    _bookedSlotsSub = _service.watchBookedSlots(doc.id).listen((keys) {
      if (mounted && !setEquals(_bookedSlotKeys, keys)) {
        setState(() => _bookedSlotKeys = keys);
      }
    });
  }

  void _showWarning(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500)),
      backgroundColor: OV.error,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  Future<void> _handleConfirmPressed() async {
    if (_selectedDoctor == null) {
      _showWarning('Please select a doctor.');
      return;
    }
    if (_selectedDate == null) {
      _showWarning('Please select an appointment date.');
      return;
    }
    if (_selectedSlot == null) {
      _showWarning('Please select an available time slot.');
      return;
    }

    if (_isSlotBooked(_selectedSlot!)) {
      _showWarning('This time slot is no longer available. Please choose another.');
      setState(() => _selectedSlot = null);
      return;
    }

    _showBookingSummary();
  }

  void _showBookingSummary() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: OV.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.event_available_rounded, color: OV.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Text(
                'Confirm Consultation',
                style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w700, color: OV.onSurface),
              ),
            ]),
            const SizedBox(height: 18),
            _SummaryRow(
              icon: Icons.person_outline_rounded,
              label: 'Doctor',
              value: '${_selectedDoctor!.name} (${_selectedDoctor!.specialty})',
            ),
            const SizedBox(height: 10),
            _SummaryRow(
              icon: Icons.calendar_today_outlined,
              label: 'Date',
              value: DateFormat('EEEE, MMMM d, yyyy').format(_selectedDate!),
            ),
            const SizedBox(height: 10),
            _SummaryRow(
              icon: Icons.access_time_rounded,
              label: 'Time Slot',
              value: _selectedSlot!,
            ),
            if (_notesCtrl.text.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              _SummaryRow(
                icon: Icons.notes_rounded,
                label: 'Notes',
                value: _notesCtrl.text.trim(),
              ),
            ],
            const SizedBox(height: 24),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('Back', style: GoogleFonts.manrope(fontWeight: FontWeight.w600, color: OV.onSurfaceVariant)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _executeBooking();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: OV.slateDark,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('Confirm Booking', style: GoogleFonts.manrope(fontWeight: FontWeight.w600)),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Future<void> _executeBooking() async {
    setState(() => _isLoading = true);
    try {
      await _service.bookAppointment(
        patientId: widget.patientId,
        patientName: widget.patientName,
        doctorId: _selectedDoctor!.id,
        doctorName: _selectedDoctor!.name,
        doctorSpecialty: _selectedDoctor!.specialty,
        appointmentDate: _selectedDate!,
        timeSlot: _selectedSlot!,
        notes: _notesCtrl.text.trim(),
      );
      if (!mounted) return;
      _showSuccess();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Booking failed: $e', style: GoogleFonts.inter(fontSize: 13)),
        backgroundColor: OV.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSuccess() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(color: OV.tertiaryContainer, shape: BoxShape.circle),
              child: const Icon(Icons.check_circle_outline_rounded, color: OV.tertiary, size: 34),
            ),
            const SizedBox(height: 16),
            Text(
              'Appointment Requested!',
              style: GoogleFonts.manrope(fontSize: 20, fontWeight: FontWeight.w700, color: OV.onSurface),
            ),
            const SizedBox(height: 8),
            Text(
              'Your appointment with ${_selectedDoctor?.name ?? 'your doctor'} on ${DateFormat('MMM d, yyyy').format(_selectedDate!)} at ${_selectedSlot ?? ''} has been submitted and is pending doctor approval.',
              style: GoogleFonts.inter(fontSize: 13, color: OV.onSurfaceVariant, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: OV.slateDark,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text('Back to Dashboard', style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
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
        DoctorAvailability avail;
        if (data.containsKey('availability')) {
          avail = DoctorAvailability.fromDoctorData(data);
          if (avail.state == DoctorAvailabilityState.invalid ||
              avail.state == DoctorAvailabilityState.unconfigured) {
            avail = DoctorAvailability.legacy(
              legacyDays: const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'],
              legacySlots: const [
                '08:00 AM',
                '09:30 AM',
                '11:00 AM',
                '01:30 PM',
                '03:00 PM',
                '04:30 PM',
              ],
            );
          }
        } else if (data['availableSlots'] is List &&
            (data['availableSlots'] as List).isNotEmpty) {
          avail = DoctorAvailability.fromDoctorData(data);
          if (avail.state == DoctorAvailabilityState.invalid ||
              avail.state == DoctorAvailabilityState.unconfigured) {
            avail = DoctorAvailability.legacy(
              legacyDays: const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'],
              legacySlots: const [
                '08:00 AM',
                '09:30 AM',
                '11:00 AM',
                '01:30 PM',
                '03:00 PM',
                '04:30 PM',
              ],
            );
          }
        } else {
          avail = DoctorAvailability.legacy(
            legacyDays: const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'],
            legacySlots: const [
              '08:00 AM',
              '09:30 AM',
              '11:00 AM',
              '01:30 PM',
              '03:00 PM',
              '04:30 PM',
            ],
          );
        }

        return _RealDoctor(
          id: d.id,
          name: (data['name'] ?? 'Doctor').toString(),
          specialty: (data['specialty'] ?? 'Specialist').toString(),
          experienceYears: data['experienceYears'] is int
              ? data['experienceYears'] as int
              : int.tryParse(data['experienceYears']?.toString() ?? '0') ?? 0,
          badge: (data['subSpecialty'] ?? '').toString(),
          availability: avail,
          isAvailable: (data['isAvailable'] ?? true) == true,
        );
      }).toList();

      if (mounted) {
        setState(() {
          _doctors = docs;
          _loadingDoctors = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingDoctors = false);
    }
  }

  @override
  void dispose() {
    _bookedSlotsSub?.cancel();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OV.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(children: [
              // App Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: OV.outlineVariant.withOpacity(0.5)),
                      ),
                      child: const Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: OV.onSurface),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Schedule Appointment',
                    style: GoogleFonts.manrope(fontSize: 17, fontWeight: FontWeight.w700, color: OV.onSurface),
                  ),
                ]),
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      'Schedule Your\nConsultation',
                      style: GoogleFonts.manrope(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: OV.onSurface,
                        height: 1.2,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Select a specialist and find a time that works for you.',
                      style: GoogleFonts.inter(fontSize: 14, color: OV.onSurfaceVariant, height: 1.5),
                    ),
                    const SizedBox(height: 24),

                    // ── Doctor Selection ────────────────────────────────
                    Text(
                      '1. Select Doctor',
                      style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700, color: OV.onSurface),
                    ),
                    const SizedBox(height: 12),
                    if (_loadingDoctors)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Center(child: CircularProgressIndicator(color: OV.primary)),
                      )
                    else if (_doctors.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: OV.outlineVariant.withOpacity(0.5)),
                        ),
                        child: Center(
                          child: Text(
                            'No doctors currently available. Please check back later.',
                            style: GoogleFonts.inter(fontSize: 13, color: OV.onSurfaceVariant),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    else
                      ..._doctors.map((doc) => _DoctorCard(
                            doctor: doc,
                            isSelected: doc.id == _selectedDoctor?.id,
                            onTap: () => _selectDoctor(doc),
                          )),

                    const SizedBox(height: 24),

                    // ── Calendar Date Picker ────────────────────────────
                    Text(
                      '2. Select Appointment Date',
                      style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700, color: OV.onSurface),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 3)),
                            ],
                          ),
                          child: Column(children: [
                            // Month Header & Navigation
                            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                              Text(
                                DateFormat('MMMM yyyy').format(_focusedMonth),
                                style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700, color: OV.onSurface),
                              ),
                              Row(children: [
                                IconButton(
                                  icon: const Icon(Icons.chevron_left_rounded, color: OV.onSurface, size: 22),
                                  onPressed: () => setState(() {
                                    _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1);
                                  }),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: const Icon(Icons.chevron_right_rounded, color: OV.onSurface, size: 22),
                                  onPressed: () => setState(() {
                                    _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1);
                                  }),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                ),
                              ]),
                            ]),
                            const SizedBox(height: 12),

                            // Day of week headers
                            Row(
                              children: ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'].map((d) {
                                return Expanded(
                                  child: Center(
                                    child: Text(
                                      d,
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: const Color(0xFF555555),
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 10),

                            // Calendar Dates Grid
                            GridView.count(
                              crossAxisCount: 7,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              mainAxisSpacing: 6,
                              crossAxisSpacing: 4,
                              childAspectRatio: 1.1,
                              children: _calendarDays.map((day) {
                                final isCurrentMonth = day.month == _focusedMonth.month;
                                final isSelected = _selectedDate != null &&
                                    day.year == _selectedDate!.year &&
                                    day.month == _selectedDate!.month &&
                                    day.day == _selectedDate!.day;
                                final now = DateTime.now();
                                final todayMidnight = DateTime(now.year, now.month, now.day);
                                final dayMidnight = DateTime(day.year, day.month, day.day);
                                final isToday = dayMidnight == todayMidnight;
                                final isPast = dayMidnight.isBefore(todayMidnight);
                                final isDateAvail = _isDateAvailable(day);
                                final isTappable = !isPast && isCurrentMonth && isDateAvail;

                                return GestureDetector(
                                  onTap: !isTappable
                                      ? null
                                      : () {
                                          setState(() {
                                            _selectedDate = day;
                                            _selectedSlot = null;
                                          });
                                        },
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? OV.slateDark
                                          : isToday
                                              ? OV.primaryContainer.withOpacity(0.5)
                                              : Colors.transparent,
                                      shape: BoxShape.circle,
                                      border: isToday && !isSelected
                                          ? Border.all(color: OV.primary, width: 1.5)
                                          : null,
                                      boxShadow: isSelected
                                          ? [
                                              BoxShadow(
                                                color: OV.slateDark.withOpacity(0.25),
                                                blurRadius: 6,
                                                offset: const Offset(0, 2),
                                              )
                                            ]
                                          : null,
                                    ),
                                    child: Center(
                                      child: Text(
                                        '${day.day}',
                                        style: GoogleFonts.inter(
                                          fontSize: 13,
                                          fontWeight: isSelected
                                              ? FontWeight.w700
                                              : (isToday || isTappable)
                                                  ? FontWeight.w600
                                                  : FontWeight.w400,
                                          color: isSelected
                                              ? Colors.white
                                              : !isCurrentMonth
                                                  ? const Color(0xFFC4C4C4)
                                                  : isPast
                                                      ? const Color(0xFF9E9E9E)
                                                      : !isDateAvail
                                                          ? const Color(0xFFB0BEC5)
                                                          : OV.onSurface,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ]),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ── Time Slots Section ──────────────────────────────
                    Text(
                      '3. Select Time Slot',
                      style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700, color: OV.onSurface),
                    ),
                    const SizedBox(height: 10),

                    if (_selectedDoctor == null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: OV.outlineVariant.withOpacity(0.4)),
                        ),
                        child: Row(children: [
                          const Icon(Icons.info_outline_rounded, color: OV.outline, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Please select a doctor above to view available slots.',
                              style: GoogleFonts.inter(fontSize: 13, color: OV.onSurfaceVariant),
                            ),
                          ),
                        ]),
                      )
                    else if (_selectedDate == null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: OV.outlineVariant.withOpacity(0.4)),
                        ),
                        child: Row(children: [
                          const Icon(Icons.calendar_month_outlined, color: OV.outline, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Please select a date from the calendar to view available consultation slots.',
                              style: GoogleFonts.inter(fontSize: 13, color: OV.onSurfaceVariant),
                            ),
                          ),
                        ]),
                      )
                    else if (!_isDateAvailable(_selectedDate!))
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: OV.outlineVariant.withOpacity(0.4)),
                        ),
                        child: Text(
                          '${_selectedDoctor?.name ?? 'The doctor'} is unavailable on ${DateFormat('EEEE, MMM d').format(_selectedDate!)}. Please select another date.',
                          style: GoogleFonts.inter(fontSize: 13, color: OV.onSurfaceVariant, fontStyle: FontStyle.italic),
                        ),
                      )
                    else if (_currentDaySlots.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: OV.outlineVariant.withOpacity(0.4)),
                        ),
                        child: Row(children: [
                          const Icon(Icons.event_busy_rounded, color: OV.outline, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'No available appointment slots for this doctor on the selected date.',
                              style: GoogleFonts.inter(fontSize: 13, color: OV.onSurfaceVariant),
                            ),
                          ),
                        ]),
                      )
                    else ...[
                      // Legend
                      Row(children: [
                        const _LegendDot(color: OV.slateDark),
                        const SizedBox(width: 4),
                        Text('Selected', style: GoogleFonts.inter(fontSize: 11, color: OV.onSurfaceVariant)),
                        const SizedBox(width: 14),
                        _LegendDot(color: OV.errorContainer, border: OV.error.withOpacity(0.4)),
                        const SizedBox(width: 4),
                        Text('Not Available', style: GoogleFonts.inter(fontSize: 11, color: OV.onSurfaceVariant)),
                      ]),
                      const SizedBox(height: 14),

                      if (_morningSlots.isNotEmpty) ...[
                        _SlotSection(
                          label: 'Morning Sessions',
                          slots: _morningSlots,
                          selectedSlot: _selectedSlot,
                          bookedChecker: _isSlotBooked,
                          onSelect: (s) {
                            if (_isSlotBooked(s)) return;
                            setState(() => _selectedSlot = s);
                          },
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (_afternoonSlots.isNotEmpty) ...[
                        _SlotSection(
                          label: 'Afternoon & Evening Sessions',
                          slots: _afternoonSlots,
                          selectedSlot: _selectedSlot,
                          bookedChecker: _isSlotBooked,
                          onSelect: (s) {
                            if (_isSlotBooked(s)) return;
                            setState(() => _selectedSlot = s);
                          },
                        ),
                        const SizedBox(height: 16),
                      ],
                      Row(children: [
                        const Icon(Icons.timer_outlined, size: 14, color: OV.outline),
                        const SizedBox(width: 6),
                        Text('Session Duration:', style: GoogleFonts.inter(fontSize: 13, color: OV.onSurfaceVariant)),
                        const SizedBox(width: 6),
                        Text(
                          '${_selectedDoctor?.availability.slotDurationMinutes ?? 45} Minutes Consultation',
                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: OV.onSurface),
                        ),
                      ]),
                    ],

                    const SizedBox(height: 24),

                    // ── Notes ───────────────────────────────────────────
                    Text(
                      'Notes (Optional)',
                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: OV.onSurface),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _notesCtrl,
                      maxLines: 3,
                      style: GoogleFonts.inter(fontSize: 14, color: OV.onSurface),
                      decoration: InputDecoration(
                        hintText: 'Describe your symptoms or reason for visit...',
                        hintStyle: GoogleFonts.inter(fontSize: 13, color: OV.outline),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: OV.outlineVariant.withOpacity(0.6)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: OV.outlineVariant.withOpacity(0.6)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: OV.primary, width: 1.5),
                        ),
                        contentPadding: const EdgeInsets.all(14),
                      ),
                    ),

                    const SizedBox(height: 24),
                  ]),
                ),
              ),

              // Confirm Button Footer
              Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: OV.outlineVariant.withOpacity(0.4))),
                ),
                child: Column(children: [
                  if (_selectedSlot != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(children: [
                        const Icon(Icons.timer_outlined, size: 14, color: OV.outline),
                        const SizedBox(width: 6),
                        Text(
                          'Cancellation possible up to 24 hours before the appointment.',
                          style: GoogleFonts.inter(fontSize: 11, color: OV.onSurfaceVariant),
                        ),
                      ]),
                    ),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _handleConfirmPressed,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: OV.slateDark,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Text(
                                'Book Appointment',
                                style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.arrow_forward_rounded, size: 18),
                            ]),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
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
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: border != null ? Border.all(color: border!, width: 1) : null,
        ),
      );
}

// Real doctor data fetched from Firestore
class _RealDoctor {
  final String id, name, specialty, badge;
  final int experienceYears;
  final DoctorAvailability availability;
  final bool isAvailable;
  _RealDoctor({
    required this.id,
    required this.name,
    required this.specialty,
    required this.badge,
    required this.experienceYears,
    required this.availability,
    required this.isAvailable,
  });
}

class _DoctorCard extends StatelessWidget {
  final _RealDoctor doctor;
  final bool isSelected;
  final VoidCallback onTap;
  const _DoctorCard({
    required this.doctor,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isSelected ? OV.primaryContainer.withOpacity(0.35) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? OV.primary : OV.outlineVariant.withOpacity(0.5),
              width: isSelected ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: isSelected ? OV.primary.withOpacity(0.08) : Colors.black.withOpacity(0.03),
                blurRadius: isSelected ? 12 : 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: OV.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.person_rounded, size: 28, color: OV.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    doctor.name,
                    style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700, color: OV.onSurface),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${doctor.specialty} • ${doctor.experienceYears} Yrs Exp.',
                    style: GoogleFonts.inter(fontSize: 12, color: OV.onSurfaceVariant),
                  ),
                  if (doctor.badge.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(children: [
                      const Icon(Icons.star_rounded, size: 12, color: Color(0xFF8B5000)),
                      const SizedBox(width: 4),
                      Text(
                        doctor.badge,
                        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF8B5000)),
                      ),
                    ]),
                  ],
                ],
              ),
            ),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: isSelected ? OV.primary : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? OV.primary : OV.outlineVariant,
                  width: 1.5,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
                  : null,
            ),
          ]),
        ),
      );
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
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: OV.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: slots.map((slot) {
              final isSelected = selectedSlot == slot;
              final isBooked = bookedChecker(slot);

              return GestureDetector(
                onTap: isBooked ? null : () => onSelect(slot),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
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
                              : OV.outlineVariant.withOpacity(0.6),
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: OV.slateDark.withOpacity(0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            )
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isBooked) ...[
                        Icon(Icons.block_rounded, size: 12, color: OV.error.withOpacity(0.7)),
                        const SizedBox(width: 5),
                      ],
                      Text(
                        isBooked ? '$slot · Not Available' : slot,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isBooked
                              ? OV.error.withOpacity(0.8)
                              : isSelected
                                  ? Colors.white
                                  : OV.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      );
}

class _SummaryRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _SummaryRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: OV.primary),
          const SizedBox(width: 10),
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: GoogleFonts.inter(fontSize: 13, color: OV.onSurfaceVariant, fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.inter(fontSize: 13, color: OV.onSurface, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      );
}