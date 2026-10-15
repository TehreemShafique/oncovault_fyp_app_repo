// lib/screens/doctor/doctor_availability_sheet.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../models/doctor_model.dart';
import '../../models/doctor_availability_model.dart';
import '../../utils/slot_generator.dart';
import '../../services/doctor_service.dart';

class DoctorAvailabilitySheet extends StatefulWidget {
  final DoctorModel doctor;
  final VoidCallback onSaved;

  const DoctorAvailabilitySheet({
    super.key,
    required this.doctor,
    required this.onSaved,
  });

  @override
  State<DoctorAvailabilitySheet> createState() =>
      _DoctorAvailabilitySheetState();
}

class _DoctorAvailabilitySheetState extends State<DoctorAvailabilitySheet> {
  final _service = DoctorService();
  bool _saving = false;
  String? _errorMessage;

  late int _slotDurationMinutes;
  late bool _isAvailable;
  late Map<String, DaySchedule> _scheduleDays;
  late Set<String> _blockedDates;
  late Set<String> _blockedSlots;

  static const _canonicalWeekdays = [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  ];

  static const _weekdayLabels = {
    'monday': 'Monday',
    'tuesday': 'Tuesday',
    'wednesday': 'Wednesday',
    'thursday': 'Thursday',
    'friday': 'Friday',
    'saturday': 'Saturday',
    'sunday': 'Sunday',
  };

  @override
  void initState() {
    super.initState();
    final avail = widget.doctor.availability;
    _slotDurationMinutes = avail.slotDurationMinutes;
    _isAvailable = widget.doctor.isAvailable;
    _blockedDates = Set<String>.from(avail.blockedDates);
    _blockedSlots = Set<String>.from(avail.blockedSlots);

    // Deep copy schedule days
    _scheduleDays = {};
    for (final day in _canonicalWeekdays) {
      final existing = avail.weeklySchedule.days[day];
      if (existing != null) {
        _scheduleDays[day] = DaySchedule(
          enabled: existing.enabled,
          startTime: existing.startTime,
          endTime: existing.endTime,
        );
      } else {
        final isWeekend = day == 'saturday' || day == 'sunday';
        _scheduleDays[day] = DaySchedule(
          enabled: !isWeekend,
          startTime: DaySchedule.defaultStart,
          endTime: DaySchedule.defaultEnd,
        );
      }
    }
  }

  Future<void> _pickTime(String day, bool isStart) async {
    final schedule = _scheduleDays[day]!;
    final initialStr = isStart ? schedule.startTime : schedule.endTime;
    final parts = initialStr.split(':');
    final initialTime = TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 9,
      minute: int.tryParse(parts[1]) ?? 0,
    );

    final picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child ?? const SizedBox(),
        );
      },
    );

    if (picked != null) {
      final formatted =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      setState(() {
        _scheduleDays[day] = DaySchedule(
          enabled: schedule.enabled,
          startTime: isStart ? formatted : schedule.startTime,
          endTime: isStart ? schedule.endTime : formatted,
        );
        _errorMessage = null;
      });
    }
  }

  Future<void> _addBlockedDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'Select Date to Block',
    );

    if (picked != null) {
      final y = picked.year.toString().padLeft(4, '0');
      final m = picked.month.toString().padLeft(2, '0');
      final d = picked.day.toString().padLeft(2, '0');
      final key = '$y-$m-$d';
      setState(() {
        _blockedDates.add(key);
        _errorMessage = null;
      });
    }
  }

  Future<void> _addBlockedSlot() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
      helpText: 'Select Date for Slot to Block',
    );

    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
      helpText: 'Select Slot Time',
    );

    if (pickedTime == null || !mounted) return;

    final y = pickedDate.year.toString().padLeft(4, '0');
    final m = pickedDate.month.toString().padLeft(2, '0');
    final d = pickedDate.day.toString().padLeft(2, '0');
    final dateKey = '$y-$m-$d';

    final minutes = pickedTime.hour * 60 + pickedTime.minute;
    final timeStr = SlotGenerator.format12Hour(minutes);
    final slotKey = '${dateKey}_$timeStr';

    setState(() {
      _blockedSlots.add(slotKey);
      _errorMessage = null;
    });
  }

  Future<void> _saveAvailability() async {
    // 1. Client-side pre-validation
    for (final day in _canonicalWeekdays) {
      final s = _scheduleDays[day]!;
      if (s.enabled) {
        if (!s.isValid(minDurationMinutes: _slotDurationMinutes)) {
          setState(() {
            _errorMessage =
                '${_weekdayLabels[day]} start time (${s.startTime}) must be at least $_slotDurationMinutes min before end time (${s.endTime}).';
          });
          return;
        }
      }
    }

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    try {
      final updatedAvailability = DoctorAvailability(
        slotDurationMinutes: _slotDurationMinutes,
        weeklySchedule: WeeklySchedule(_scheduleDays),
        blockedDates: _blockedDates,
        blockedSlots: _blockedSlots,
        state: DoctorAvailabilityState.structured,
        updatedAt: DateTime.now(),
      );

      await _service.updateDoctorAvailability(
        availability: updatedAvailability,
        isAvailable: _isAvailable,
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Doctor availability updated successfully.'),
            backgroundColor: OV.primary,
          ),
        );
        widget.onSaved();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag Handle
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: OV.outlineVariant.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Availability & Schedule',
                        style: GoogleFonts.manrope(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: OV.onSurface,
                        ),
                      ),
                      Text(
                        'Configure consultation hours & block dates',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: OV.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          const Divider(height: 20),

          // Scrollable Content
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              children: [
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: OV.errorContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: OV.error.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            color: OV.error, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: OV.error,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // 1. Overall Availability Toggle
                _buildAvailabilityToggle(),
                const SizedBox(height: 20),

                // 2. Consultation Duration Selection
                _buildDurationSelector(),
                const SizedBox(height: 24),

                // 3. Weekly Schedule (Days & Hours)
                _buildWeeklyScheduleSection(),
                const SizedBox(height: 24),

                // 4. Blocked Calendar Dates
                _buildBlockedDatesSection(),
                const SizedBox(height: 24),

                // 5. Blocked Individual Slots
                _buildBlockedSlotsSection(),
                const SizedBox(height: 32),
              ],
            ),
          ),

          // Save Footer
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _saving ? null : _saveAvailability,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: OV.slateDark,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'Save Availability',
                          style: GoogleFonts.manrope(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvailabilityToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _isAvailable
            ? OV.tertiaryContainer.withValues(alpha: 0.4)
            : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isAvailable
              ? OV.tertiary.withValues(alpha: 0.3)
              : OV.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          Icon(
            _isAvailable ? Icons.check_circle_rounded : Icons.pause_circle_rounded,
            color: _isAvailable ? OV.tertiary : OV.outlineVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isAvailable ? 'Status: Accepting Appointments' : 'Status: Paused',
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: OV.onSurface,
                  ),
                ),
                Text(
                  _isAvailable
                      ? 'Patients can request appointments in your active slots.'
                      : 'Slots will be hidden from patients until resumed.',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: OV.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _isAvailable,
            onChanged: (val) => setState(() => _isAvailable = val),
            activeThumbColor: OV.tertiary,
          ),
        ],
      ),
    );
  }

  Widget _buildDurationSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Consultation Duration',
          style: GoogleFonts.manrope(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: OV.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [15, 20, 30, 45, 60].map((duration) {
            final isSelected = _slotDurationMinutes == duration;
            return ChoiceChip(
              label: Text('$duration min'),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  setState(() => _slotDurationMinutes = duration);
                }
              },
              selectedColor: OV.primaryContainer,
              labelStyle: GoogleFonts.manrope(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? OV.primary : OV.onSurface,
              ),
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(
                  color: isSelected ? OV.primary : OV.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildWeeklyScheduleSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Working Weekdays & Hours',
          style: GoogleFonts.manrope(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: OV.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Enable consultation days and customize operating hours.',
          style: GoogleFonts.inter(
            fontSize: 11,
            color: OV.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        ..._canonicalWeekdays.map((day) {
          final schedule = _scheduleDays[day]!;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: schedule.enabled ? Colors.white : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: schedule.enabled
                    ? OV.outlineVariant.withValues(alpha: 0.6)
                    : OV.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 90,
                  child: Row(
                    children: [
                      Checkbox(
                        value: schedule.enabled,
                        onChanged: (val) {
                          setState(() {
                            _scheduleDays[day] = DaySchedule(
                              enabled: val ?? false,
                              startTime: schedule.startTime,
                              endTime: schedule.endTime,
                            );
                          });
                        },
                        activeColor: OV.primary,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      Text(
                        _weekdayLabels[day]!.substring(0, 3),
                        style: GoogleFonts.manrope(
                          fontSize: 13,
                          fontWeight: schedule.enabled
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: schedule.enabled
                              ? OV.onSurface
                              : OV.outlineVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (schedule.enabled) ...[
                  const Spacer(),
                  GestureDetector(
                    onTap: () => _pickTime(day, true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        schedule.startTime,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: OV.onSurface,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      'to',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: OV.onSurfaceVariant,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _pickTime(day, false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        schedule.endTime,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: OV.onSurface,
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  const Spacer(),
                  Text(
                    'Closed',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: OV.outlineVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildBlockedDatesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Blocked Specific Dates (${_blockedDates.length})',
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: OV.onSurface,
                  ),
                ),
                Text(
                  'Mark vacations, holidays, or out-of-office days',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: OV.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            TextButton.icon(
              onPressed: _addBlockedDate,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Add Date'),
              style: TextButton.styleFrom(
                foregroundColor: OV.primary,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_blockedDates.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              'No individual dates blocked.',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: OV.outlineVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: (_blockedDates.toList()..sort()).map((date) {
              return Chip(
                label: Text(date),
                labelStyle: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: OV.error,
                ),
                backgroundColor: OV.errorContainer.withValues(alpha: 0.4),
                deleteIcon: const Icon(Icons.close_rounded, size: 14),
                deleteIconColor: OV.error,
                onDeleted: () => setState(() => _blockedDates.remove(date)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: OV.error.withValues(alpha: 0.2)),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildBlockedSlotsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Blocked Specific Slots (${_blockedSlots.length})',
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: OV.onSurface,
                  ),
                ),
                Text(
                  'Block individual slots (e.g. 2026-10-20_11:15 AM)',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: OV.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            TextButton.icon(
              onPressed: _addBlockedSlot,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Add Slot'),
              style: TextButton.styleFrom(
                foregroundColor: OV.primary,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_blockedSlots.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              'No individual slots blocked.',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: OV.outlineVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: (_blockedSlots.toList()..sort()).map((slotKey) {
              return Chip(
                label: Text(slotKey),
                labelStyle: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: OV.secondary,
                ),
                backgroundColor: OV.secondaryContainer.withValues(alpha: 0.5),
                deleteIcon: const Icon(Icons.close_rounded, size: 14),
                deleteIconColor: OV.secondary,
                onDeleted: () => setState(() => _blockedSlots.remove(slotKey)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: OV.secondary.withValues(alpha: 0.3)),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }
}
