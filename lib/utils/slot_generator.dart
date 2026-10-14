// lib/utils/slot_generator.dart
import '../models/doctor_availability_model.dart';

class SlotGenerator {
  /// Converts minutes from midnight (0–1439) into a strict canonical 12-hour string: "hh:mm AM/PM".
  /// Examples:
  /// - 0    -> "12:00 AM"
  /// - 540  -> "09:00 AM"
  /// - 720  -> "12:00 PM"
  /// - 810  -> "01:30 PM"
  static String format12Hour(int minutes) {
    assert(minutes >= 0 && minutes < 1440, 'Minutes must be in 0..1439 range');
    final h24 = minutes ~/ 60;
    final m = minutes % 60;
    final period = h24 >= 12 ? 'PM' : 'AM';
    var h12 = h24 % 12;
    if (h12 == 0) h12 = 12;
    final hStr = h12.toString().padLeft(2, '0');
    final mStr = m.toString().padLeft(2, '0');
    return '$hStr:$mStr $period';
  }

  /// Parses a 12-hour string ("09:30 AM") into total minutes from midnight (0–1439).
  /// Returns null if [timeStr] does not strictly match canonical 12-hour time syntax.
  static int? parse12Hour(String? timeStr) {
    return DoctorAvailability.tryParse12HourToMinutes(timeStr);
  }

  /// Generates a deterministic sequence of non-overlapping slot start times.
  /// Each slot must completely fit within the day's [startTime, endTime] window.
  /// Returns an empty list if the day is disabled, invalid, or window is smaller than duration.
  static List<String> generateSlots(DaySchedule day, int durationMinutes) {
    if (!day.enabled || !day.isValid(minDurationMinutes: durationMinutes)) {
      return const [];
    }
    if (durationMinutes <= 0) return const [];

    final slots = <String>[];
    int current = day.startMinutes;
    final end = day.endMinutes;

    while (current + durationMinutes <= end) {
      slots.add(format12Hour(current));
      current += durationMinutes;
    }

    return List.unmodifiable(slots);
  }

  /// Evaluates whether a requested date and timeSlot are valid for consultation.
  ///
  /// Criteria evaluated:
  /// 1. Availability state must be structured or legacy.
  /// 2. [isDoctorAvailable] must be true (temporarily unavailable doctors offer 0 slots).
  /// 3. Weekday must be enabled in the schedule.
  /// 4. Selected calendar date must not be blocked.
  /// 5. Start time must belong to the doctor's active slot grid (or legacy slot allowlist).
  /// 6. Consultation interval must fit within working hours.
  /// 7. Individual slotKey must not be in blockedSlots.
  /// 8. Date and slot start time must not be expired relative to [referenceNow].
  static bool isSlotValid({
    required DateTime date,
    required String timeSlot,
    required DoctorAvailability availability,
    bool isDoctorAvailable = true,
    DateTime? referenceNow,
  }) {
    // 1. Doctor temporary availability check
    if (!isDoctorAvailable) return false;

    // 2. Schedule state check (fail-closed on unconfigured or invalid)
    if (availability.state == DoctorAvailabilityState.unconfigured ||
        availability.state == DoctorAvailabilityState.invalid) {
      return false;
    }

    final trimmedSlot = timeSlot.trim();
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    final dateKey = '$y-$m-$d';

    // 3. Blocked date check
    if (availability.blockedDates.contains(dateKey)) {
      return false;
    }

    // 4. Blocked slot check
    final slotKey = '${dateKey}_$trimmedSlot';
    if (availability.blockedSlots.contains(slotKey)) {
      return false;
    }

    // 5. State-specific slot evaluation
    if (availability.state == DoctorAvailabilityState.legacy) {
      // Legacy weekday mapping
      const legacyMap = {
        DateTime.monday: 'Mon',
        DateTime.tuesday: 'Tue',
        DateTime.wednesday: 'Wed',
        DateTime.thursday: 'Thu',
        DateTime.friday: 'Fri',
        DateTime.saturday: 'Sat',
        DateTime.sunday: 'Sun',
      };
      final dayAbbr = legacyMap[date.weekday];
      if (dayAbbr == null || !availability.legacyDays.contains(dayAbbr)) {
        return false;
      }
      if (!availability.legacySlots.contains(trimmedSlot)) {
        return false;
      }
    } else {
      // Structured availability
      final daySchedule = availability.weeklySchedule.getDay(date.weekday);
      if (!daySchedule.enabled) return false;

      final grid = generateSlots(daySchedule, availability.slotDurationMinutes);
      if (!grid.contains(trimmedSlot)) return false;

      final slotMinutes = parse12Hour(trimmedSlot);
      if (slotMinutes == null) return false;

      // Verify boundary containment
      if (slotMinutes + availability.slotDurationMinutes > daySchedule.endMinutes) {
        return false;
      }
    }

    // 6. Clock expiration check
    final now = referenceNow ?? DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);
    final targetMidnight = DateTime(date.year, date.month, date.day);

    if (targetMidnight.isBefore(todayMidnight)) {
      return false; // Past date
    }

    if (targetMidnight == todayMidnight) {
      final slotMinutes = parse12Hour(trimmedSlot);
      if (slotMinutes == null) return false;
      final nowMinutes = now.hour * 60 + now.minute;
      if (slotMinutes <= nowMinutes) {
        return false; // Slot has already started or passed today
      }
    }

    return true;
  }
}
