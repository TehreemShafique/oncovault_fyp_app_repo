// lib/models/doctor_availability_model.dart

/// Configuration state for a doctor's availability.
enum DoctorAvailabilityState {
  /// The doctor has an explicitly configured availability map that passes complete validation.
  structured,

  /// No structured availability exists, but valid existing `availableDays` and
  /// `availableSlots` data can be preserved and interpreted using legacy compatibility rules.
  legacy,

  /// No usable schedule has been configured.
  unconfigured,

  /// A structured availability map exists but is malformed, internally inconsistent,
  /// or violates validation rules. An invalid structured schedule must never silently
  /// become an active default schedule.
  invalid,
}

/// Represents a single calendar day's working window.
class DaySchedule {
  final bool enabled;
  final String startTime; // "HH:mm" (24-hour)
  final String endTime;   // "HH:mm" (24-hour)

  static const defaultStart = '09:00';
  static const defaultEnd = '17:00';

  static const DaySchedule defaultEnabled =
      DaySchedule(enabled: true, startTime: defaultStart, endTime: defaultEnd);
  static const DaySchedule defaultDisabled =
      DaySchedule(enabled: false, startTime: defaultStart, endTime: defaultEnd);

  static final RegExp timeSyntax = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$');

  const DaySchedule({
    required this.enabled,
    required this.startTime,
    required this.endTime,
  });

  /// Safely parses an "HH:mm" string into total minutes from midnight (0–1439).
  /// Returns null if [hhmm] does not strictly match 24-hour time syntax.
  static int? tryParseMinutes(String? hhmm) {
    if (hhmm == null) return null;
    final match = timeSyntax.firstMatch(hhmm.trim());
    if (match == null) return null;
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return hour * 60 + minute;
  }

  int get startMinutes => tryParseMinutes(startTime) ?? 0;
  int get endMinutes => tryParseMinutes(endTime) ?? 0;

  /// Validates syntax and intra-day chronological ordering.
  /// If [minDurationMinutes] > 0 and [enabled] is true, checks that the working
  /// window can fit at least one full consultation slot.
  bool isValid({int minDurationMinutes = 0}) {
    final start = tryParseMinutes(startTime);
    final end = tryParseMinutes(endTime);
    if (start == null || end == null) return false;

    if (enabled) {
      if (start >= end) return false;
      if (minDurationMinutes > 0 && (end - start) < minDurationMinutes) {
        return false;
      }
    }
    return true;
  }

  Map<String, dynamic> toMap() => {
    'enabled': enabled,
    'startTime': startTime,
    'endTime': endTime,
  };

  /// Parses a DaySchedule from raw map data.
  /// Returns null if the raw data is missing, non-map, or contains invalid syntax.
  static DaySchedule? fromMap(dynamic raw, {int minDurationMinutes = 0}) {
    if (raw == null || raw is! Map) return null;
    final enabledRaw = raw['enabled'];
    final startRaw = raw['startTime'];
    final endRaw = raw['endTime'];

    if (enabledRaw is! bool) return null;
    if (startRaw is! String || endRaw is! String) return null;

    final schedule = DaySchedule(
      enabled: enabledRaw,
      startTime: startRaw,
      endTime: endRaw,
    );

    if (!schedule.isValid(minDurationMinutes: minDurationMinutes)) {
      return null;
    }
    return schedule;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DaySchedule &&
          runtimeType == other.runtimeType &&
          enabled == other.enabled &&
          startTime == other.startTime &&
          endTime == other.endTime;

  @override
  int get hashCode => enabled.hashCode ^ startTime.hashCode ^ endTime.hashCode;
}

/// Represents the seven calendar weekdays.
class WeeklySchedule {
  final Map<String, DaySchedule> days;

  static const canonicalWeekdays = [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  ];

  const WeeklySchedule(this.days);

  /// Suggested configuration template (Mon–Fri 09:00–17:00 enabled, Sat–Sun disabled).
  /// This is an explicit template only; never silently applied to corrupt persisted data.
  factory WeeklySchedule.template() {
    final map = <String, DaySchedule>{};
    for (final day in canonicalWeekdays) {
      map[day] = (day == 'saturday' || day == 'sunday')
          ? DaySchedule.defaultDisabled
          : DaySchedule.defaultEnabled;
    }
    return WeeklySchedule(map);
  }

  /// Look up DaySchedule using Dart's weekday numbering (DateTime.monday = 1, DateTime.sunday = 7).
  DaySchedule getDay(int weekday) {
    if (weekday < 1 || weekday > 7) return DaySchedule.defaultDisabled;
    final key = canonicalWeekdays[weekday - 1];
    return days[key] ?? DaySchedule.defaultDisabled;
  }

  Map<String, dynamic> toMap() {
    final result = <String, dynamic>{};
    for (final day in canonicalWeekdays) {
      if (days.containsKey(day)) {
        result[day] = days[day]!.toMap();
      }
    }
    return result;
  }

  /// Parses a WeeklySchedule from raw map data.
  /// Requires all seven canonical weekday entries. Rejects missing, extra,
  /// or malformed entries by returning null.
  static WeeklySchedule? fromMap(dynamic raw, {int minDurationMinutes = 0}) {
    if (raw == null || raw is! Map) return null;

    // Check for unexpected extra keys
    for (final k in raw.keys) {
      if (k is! String || !canonicalWeekdays.contains(k)) {
        return null;
      }
    }

    final result = <String, DaySchedule>{};
    for (final day in canonicalWeekdays) {
      if (!raw.containsKey(day)) return null;
      final parsedDay =
          DaySchedule.fromMap(raw[day], minDurationMinutes: minDurationMinutes);
      if (parsedDay == null) return null;
      result[day] = parsedDay;
    }
    return WeeklySchedule(result);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! WeeklySchedule) return false;
    for (final day in canonicalWeekdays) {
      if (days[day] != other.days[day]) return false;
    }
    return true;
  }

  @override
  int get hashCode => days.hashCode;
}

/// Represents a discrete intra-day consultation time interval: [start, end).
class AppointmentInterval {
  final String date; // "YYYY-MM-DD"
  final int startMinutes; // Minutes from midnight (0–1439)
  final int durationMinutes;

  int get endMinutes => startMinutes + durationMinutes;

  const AppointmentInterval({
    required this.date,
    required this.startMinutes,
    required this.durationMinutes,
  });

  /// Validates interval semantics. Must be within the intra-day boundary (0–1440).
  bool isValid() {
    if (!DoctorAvailability.isValidIsoDate(date)) return false;
    if (durationMinutes <= 0) return false;
    if (startMinutes < 0) return false;
    if (endMinutes > 1440) return false;
    return true;
  }

  /// Creates an interval from a canonical date and 12-hour slot string ("09:30 AM").
  /// Returns null if date or time slot cannot be parsed.
  static AppointmentInterval? fromSlot(
      String date, String timeSlot, int durationMinutes) {
    if (!DoctorAvailability.isValidIsoDate(date)) return null;
    final start = DoctorAvailability.tryParse12HourToMinutes(timeSlot);
    if (start == null) return null;
    final interval = AppointmentInterval(
      date: date,
      startMinutes: start,
      durationMinutes: durationMinutes,
    );
    return interval.isValid() ? interval : null;
  }

  /// Two intervals overlap if and only if they are on the same calendar date
  /// and their half-open minute ranges intersect: a.start < b.end && b.start < a.end.
  bool overlaps(AppointmentInterval other) {
    if (!isValid() || !other.isValid()) return false;
    if (date != other.date) return false; // Different calendar dates never overlap
    return startMinutes < other.endMinutes && other.startMinutes < endMinutes;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppointmentInterval &&
          runtimeType == other.runtimeType &&
          date == other.date &&
          startMinutes == other.startMinutes &&
          durationMinutes == other.durationMinutes;

  @override
  int get hashCode =>
      date.hashCode ^ startMinutes.hashCode ^ durationMinutes.hashCode;

  @override
  String toString() =>
      'AppointmentInterval($date: $startMinutes..$endMinutes, ${durationMinutes}m)';
}

/// Root aggregate model for doctor availability.
class DoctorAvailability {
  final int slotDurationMinutes;
  final WeeklySchedule weeklySchedule;
  final Set<String> blockedDates; // "YYYY-MM-DD"
  final Set<String> blockedSlots; // "YYYY-MM-DD_hh:mm AM/PM"
  final DoctorAvailabilityState state;
  final List<String> legacyDays;  // e.g. ['Mon', 'Tue', 'Wed', 'Thu', 'Fri']
  final List<String> legacySlots; // e.g. ['08:00 AM', '09:30 AM']
  final DateTime? updatedAt;

  static const supportedDurations = {15, 20, 30, 45, 60};
  static const defaultDuration = 45;
  static const maxBlockedDates = 365;
  static const maxBlockedSlots = 500;

  static const canonicalLegacyDays = {
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'
  };

  static final RegExp _slotKeyRegex =
      RegExp(r'^\d{4}-\d{2}-\d{2}_(0[1-9]|1[0-2]):[0-5]\d (AM|PM)$');

  static final RegExp _timeSlot12hRegex =
      RegExp(r'^(0[1-9]|1[0-2]):([0-5]\d)\s+(AM|PM)$');

  const DoctorAvailability({
    this.slotDurationMinutes = defaultDuration,
    required this.weeklySchedule,
    this.blockedDates = const {},
    this.blockedSlots = const {},
    required this.state,
    this.legacyDays = const [],
    this.legacySlots = const [],
    this.updatedAt,
  });

  /// Factory for an unconfigured doctor.
  factory DoctorAvailability.unconfigured() => DoctorAvailability(
        slotDurationMinutes: defaultDuration,
        weeklySchedule: WeeklySchedule.template(),
        state: DoctorAvailabilityState.unconfigured,
      );

  /// Factory for an invalid/corrupt doctor schedule.
  factory DoctorAvailability.invalid() => DoctorAvailability(
        slotDurationMinutes: defaultDuration,
        weeklySchedule: WeeklySchedule.template(),
        state: DoctorAvailabilityState.invalid,
      );

  /// Factory for legacy compatibility schedule.
  factory DoctorAvailability.legacy({
    required List<String> legacyDays,
    required List<String> legacySlots,
  }) =>
      DoctorAvailability(
        slotDurationMinutes: defaultDuration,
        weeklySchedule: WeeklySchedule.template(),
        legacyDays: List.unmodifiable(legacyDays),
        legacySlots: List.unmodifiable(legacySlots),
        state: DoctorAvailabilityState.legacy,
      );

  /// Validates exact "YYYY-MM-DD" calendar date with Gregorian calendar correctness (including leap years).
  static bool isValidIsoDate(String? s) {
    if (s == null) return false;
    final trimmed = s.trim();
    if (!RegExp(r'^\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$').hasMatch(trimmed)) {
      return false;
    }
    final parts = trimmed.split('-');
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return false;

    // Check Gregorian day count per month
    const daysInMonth = [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    var maxDays = daysInMonth[m];
    if (m == 2) {
      final isLeapYear = (y % 4 == 0 && y % 100 != 0) || (y % 400 == 0);
      if (isLeapYear) maxDays = 29;
    }
    return d >= 1 && d <= maxDays;
  }

  /// Validates a canonical slotKey: "YYYY-MM-DD_hh:mm AM/PM".
  static bool isValidSlotKey(String? key) {
    if (key == null) return false;
    final trimmed = key.trim();
    if (!_slotKeyRegex.hasMatch(trimmed)) return false;
    final underscoreIdx = trimmed.indexOf('_');
    final datePart = trimmed.substring(0, underscoreIdx);
    return isValidIsoDate(datePart);
  }

  /// Parses a 12-hour time slot ("09:30 AM") to minutes from midnight (0–1439).
  static int? tryParse12HourToMinutes(String? timeStr) {
    if (timeStr == null) return null;
    final match = _timeSlot12hRegex.firstMatch(timeStr.trim());
    if (match == null) return null;
    var hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    final period = match.group(3)!;
    if (period == 'PM' && hour != 12) hour += 12;
    if (period == 'AM' && hour == 12) hour = 0;
    return hour * 60 + minute;
  }

  /// Serializes to a deterministic Map. Outputs sorted lists for blocked collections.
  Map<String, dynamic> toMap() {
    final sortedDates = blockedDates.toList()..sort();
    final sortedSlots = blockedSlots.toList()..sort();
    return {
      'slotDurationMinutes': slotDurationMinutes,
      'weeklySchedule': weeklySchedule.toMap(),
      'blockedDates': sortedDates,
      'blockedSlots': sortedSlots,
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    };
  }

  /// Parses availability from raw doctor Firestore document data.
  /// Strictly distinguishes structured, legacy, unconfigured, and invalid states.
  factory DoctorAvailability.fromDoctorData(Map<String, dynamic>? docData) {
    if (docData == null || docData.isEmpty) {
      return DoctorAvailability.unconfigured();
    }

    // 1. Structured Availability Map present
    if (docData.containsKey('availability')) {
      final rawAvail = docData['availability'];
      if (rawAvail == null || rawAvail is! Map) {
        return DoctorAvailability.invalid();
      }

      // Duration validation
      final rawDuration = rawAvail['slotDurationMinutes'];
      if (rawDuration is! int || !supportedDurations.contains(rawDuration)) {
        return DoctorAvailability.invalid();
      }

      // WeeklySchedule validation
      final weekly = WeeklySchedule.fromMap(
        rawAvail['weeklySchedule'],
        minDurationMinutes: rawDuration,
      );
      if (weekly == null) {
        return DoctorAvailability.invalid();
      }

      // Blocked dates validation
      final rawDates = rawAvail['blockedDates'];
      if (rawDates is! List || rawDates.length > maxBlockedDates) {
        return DoctorAvailability.invalid();
      }
      final dateSet = <String>{};
      for (final d in rawDates) {
        if (d is! String || !isValidIsoDate(d)) {
          return DoctorAvailability.invalid();
        }
        if (dateSet.contains(d)) {
          return DoctorAvailability.invalid(); // Duplicates in persisted structured data are corrupt
        }
        dateSet.add(d);
      }

      // Blocked slots validation
      final rawSlots = rawAvail['blockedSlots'];
      if (rawSlots is! List || rawSlots.length > maxBlockedSlots) {
        return DoctorAvailability.invalid();
      }
      final slotSet = <String>{};
      for (final s in rawSlots) {
        if (s is! String || !isValidSlotKey(s)) {
          return DoctorAvailability.invalid();
        }
        if (slotSet.contains(s)) {
          return DoctorAvailability.invalid(); // Duplicates in persisted structured data are corrupt
        }
        slotSet.add(s);
      }

      // UpdatedAt validation (optional string)
      DateTime? updated;
      if (rawAvail.containsKey('updatedAt') && rawAvail['updatedAt'] != null) {
        final rawUp = rawAvail['updatedAt'];
        if (rawUp is! String) return DoctorAvailability.invalid();
        updated = DateTime.tryParse(rawUp);
        if (updated == null) return DoctorAvailability.invalid();
      }

      return DoctorAvailability(
        slotDurationMinutes: rawDuration,
        weeklySchedule: weekly,
        blockedDates: Set.unmodifiable(dateSet),
        blockedSlots: Set.unmodifiable(slotSet),
        state: DoctorAvailabilityState.structured,
        updatedAt: updated,
      );
    }

    // 2. Legacy fields present
    final rawLegacySlots = docData['availableSlots'];
    final rawLegacyDays = docData['availableDays'];

    if (rawLegacySlots is List || rawLegacyDays is List) {
      if (rawLegacySlots is! List || rawLegacyDays is! List) {
        return DoctorAvailability.invalid();
      }

      if (rawLegacySlots.isEmpty && rawLegacyDays.isEmpty) {
        return DoctorAvailability.unconfigured();
      }

      // Validate legacy days
      final cleanDays = <String>[];
      final seenDays = <String>{};
      for (final d in rawLegacyDays) {
        if (d is! String || !canonicalLegacyDays.contains(d)) {
          return DoctorAvailability.invalid();
        }
        if (seenDays.contains(d)) {
          return DoctorAvailability.invalid(); // Duplicate day
        }
        seenDays.add(d);
        cleanDays.add(d);
      }

      // Validate legacy slots
      final cleanSlots = <String>[];
      final seenSlots = <String>{};
      for (final s in rawLegacySlots) {
        if (s is! String || !_timeSlot12hRegex.hasMatch(s)) {
          return DoctorAvailability.invalid();
        }
        if (seenSlots.contains(s)) {
          return DoctorAvailability.invalid(); // Duplicate slot
        }
        seenSlots.add(s);
        cleanSlots.add(s);
      }

      if (cleanDays.isEmpty || cleanSlots.isEmpty) {
        return DoctorAvailability.unconfigured();
      }

      return DoctorAvailability.legacy(
        legacyDays: cleanDays,
        legacySlots: cleanSlots,
      );
    }

    // 3. Neither structured nor legacy data
    return DoctorAvailability.unconfigured();
  }
}
