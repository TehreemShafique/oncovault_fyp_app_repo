// test/doctor_availability_model_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:oncovault/models/doctor_availability_model.dart';
import 'package:oncovault/models/doctor_model.dart';
import 'package:oncovault/utils/slot_generator.dart';

void main() {
  group('A. DaySchedule Unit Tests', () {
    test('Valid 24-hour time formats are accepted and parsed', () {
      const schedule = DaySchedule(enabled: true, startTime: '09:00', endTime: '17:30');
      expect(schedule.isValid(), isTrue);
      expect(schedule.startMinutes, equals(540));
      expect(schedule.endMinutes, equals(1050));
    });

    test('Invalid 24-hour formats are rejected', () {
      const invalidFormats = ['9:00', '24:00', '12:60', '09:00 AM', '', '  ', 'abc'];
      for (final invalid in invalidFormats) {
        final sched1 = DaySchedule(enabled: true, startTime: invalid, endTime: '17:00');
        final sched2 = DaySchedule(enabled: true, startTime: '09:00', endTime: invalid);
        expect(sched1.isValid(), isFalse, reason: 'Failed to reject invalid startTime: $invalid');
        expect(sched2.isValid(), isFalse, reason: 'Failed to reject invalid endTime: $invalid');
      }
    });

    test('Start equal to or after end is rejected when enabled', () {
      const equalTime = DaySchedule(enabled: true, startTime: '12:00', endTime: '12:00');
      const reversedTime = DaySchedule(enabled: true, startTime: '17:00', endTime: '09:00');
      expect(equalTime.isValid(), isFalse);
      expect(reversedTime.isValid(), isFalse);
    });

    test('Overnight working windows are rejected', () {
      const overnight = DaySchedule(enabled: true, startTime: '22:00', endTime: '06:00');
      expect(overnight.isValid(), isFalse);
    });

    test('Disabled days are valid if time syntax is valid, even if start >= end', () {
      const disabled = DaySchedule(enabled: false, startTime: '17:00', endTime: '09:00');
      expect(disabled.isValid(), isTrue);
    });

    test('Disabled days with invalid time syntax are rejected', () {
      const disabledCorrupt = DaySchedule(enabled: false, startTime: 'invalid', endTime: '17:00');
      expect(disabledCorrupt.isValid(), isFalse);
    });

    test('Working window shorter than minDurationMinutes is rejected', () {
      const shortWindow = DaySchedule(enabled: true, startTime: '09:00', endTime: '09:30');
      expect(shortWindow.isValid(minDurationMinutes: 45), isFalse);
      expect(shortWindow.isValid(minDurationMinutes: 30), isTrue);
    });
  });

  group('B. WeeklySchedule Unit Tests', () {
    test('All seven weekdays map correctly', () {
      final schedule = WeeklySchedule.template();
      expect(schedule.getDay(DateTime.monday).enabled, isTrue);
      expect(schedule.getDay(DateTime.tuesday).enabled, isTrue);
      expect(schedule.getDay(DateTime.wednesday).enabled, isTrue);
      expect(schedule.getDay(DateTime.thursday).enabled, isTrue);
      expect(schedule.getDay(DateTime.friday).enabled, isTrue);
      expect(schedule.getDay(DateTime.saturday).enabled, isFalse);
      expect(schedule.getDay(DateTime.sunday).enabled, isFalse);
    });

    test('Missing weekday in map fails parsing by returning null', () {
      final map = WeeklySchedule.template().toMap();
      map.remove('friday');
      expect(WeeklySchedule.fromMap(map), isNull);
    });

    test('Unexpected weekday key in map fails parsing by returning null', () {
      final map = WeeklySchedule.template().toMap();
      map['funday'] = const DaySchedule(enabled: true, startTime: '09:00', endTime: '17:00').toMap();
      expect(WeeklySchedule.fromMap(map), isNull);
    });

    test('Malformed weekday entry fails parsing by returning null', () {
      final map = WeeklySchedule.template().toMap();
      map['monday'] = {'enabled': true, 'startTime': 'invalid', 'endTime': '17:00'};
      expect(WeeklySchedule.fromMap(map), isNull);
    });
  });

  group('C. Consultation Duration Unit Tests', () {
    test('All supported durations (15, 20, 30, 45, 60) are accepted', () {
      for (final duration in [15, 20, 30, 45, 60]) {
        final data = {
          'availability': {
            'slotDurationMinutes': duration,
            'weeklySchedule': WeeklySchedule.template().toMap(),
            'blockedDates': <String>[],
            'blockedSlots': <String>[],
          }
        };
        final avail = DoctorAvailability.fromDoctorData(data);
        expect(avail.state, equals(DoctorAvailabilityState.structured));
        expect(avail.slotDurationMinutes, equals(duration));
      }
    });

    test('Unsupported durations, zero, negative, and wrong types are rejected as invalid', () {
      final unsupported = [0, -15, 10, 25, 40, 50, 90, 120, '45', null];
      for (final duration in unsupported) {
        final data = {
          'availability': {
            'slotDurationMinutes': duration,
            'weeklySchedule': WeeklySchedule.template().toMap(),
            'blockedDates': <String>[],
            'blockedSlots': <String>[],
          }
        };
        final avail = DoctorAvailability.fromDoctorData(data);
        expect(avail.state, equals(DoctorAvailabilityState.invalid),
            reason: 'Failed to mark invalid duration: $duration');
      }
    });
  });

  group('D. Blocked Dates and Slots Unit Tests', () {
    test('Valid Gregorian calendar dates and leap years are accepted', () {
      expect(DoctorAvailability.isValidIsoDate('2026-02-28'), isTrue);
      expect(DoctorAvailability.isValidIsoDate('2024-02-29'), isTrue); // Leap year 2024
      expect(DoctorAvailability.isValidIsoDate('2026-12-31'), isTrue);
    });

    test('Invalid calendar dates are rejected', () {
      expect(DoctorAvailability.isValidIsoDate('2026-02-29'), isFalse); // Not leap year
      expect(DoctorAvailability.isValidIsoDate('2026-02-30'), isFalse);
      expect(DoctorAvailability.isValidIsoDate('2026-04-31'), isFalse); // April has 30 days
      expect(DoctorAvailability.isValidIsoDate('2026-13-01'), isFalse); // Month 13
      expect(DoctorAvailability.isValidIsoDate('invalid-date'), isFalse);
      expect(DoctorAvailability.isValidIsoDate(null), isFalse);
    });

    test('Canonical slot keys are validated correctly', () {
      expect(DoctorAvailability.isValidSlotKey('2026-10-20_09:00 AM'), isTrue);
      expect(DoctorAvailability.isValidSlotKey('2026-10-20_01:30 PM'), isTrue);
      expect(DoctorAvailability.isValidSlotKey('2026-02-30_09:00 AM'), isFalse); // Invalid date
      expect(DoctorAvailability.isValidSlotKey('2026-10-20_25:00 PM'), isFalse); // Invalid hour
      expect(DoctorAvailability.isValidSlotKey('2026-10-20_9:00 AM'), isFalse);  // Missing leading zero
      expect(DoctorAvailability.isValidSlotKey('random_slot'), isFalse);
    });

    test('Duplicate blocked dates or slots in persisted structured data mark state invalid', () {
      final duplicateDates = {
        'availability': {
          'slotDurationMinutes': 45,
          'weeklySchedule': WeeklySchedule.template().toMap(),
          'blockedDates': ['2026-10-20', '2026-10-20'],
          'blockedSlots': <String>[],
        }
      };
      expect(DoctorAvailability.fromDoctorData(duplicateDates).state,
          equals(DoctorAvailabilityState.invalid));

      final duplicateSlots = {
        'availability': {
          'slotDurationMinutes': 45,
          'weeklySchedule': WeeklySchedule.template().toMap(),
          'blockedDates': <String>[],
          'blockedSlots': ['2026-10-20_09:00 AM', '2026-10-20_09:00 AM'],
        }
      };
      expect(DoctorAvailability.fromDoctorData(duplicateSlots).state,
          equals(DoctorAvailabilityState.invalid));
    });

    test('Exceeding collection limits (365 dates, 500 slots) marks state invalid', () {
      final tooManyDates = {
        'availability': {
          'slotDurationMinutes': 45,
          'weeklySchedule': WeeklySchedule.template().toMap(),
          'blockedDates': List.generate(366, (i) => '2026-01-01'),
          'blockedSlots': <String>[],
        }
      };
      expect(DoctorAvailability.fromDoctorData(tooManyDates).state,
          equals(DoctorAvailabilityState.invalid));
    });

    test('Serialization produces deterministically sorted lists', () {
      final avail = DoctorAvailability(
        weeklySchedule: WeeklySchedule.template(),
        blockedDates: {'2026-12-25', '2026-01-01', '2026-07-04'},
        blockedSlots: {'2026-10-20_03:00 PM', '2026-10-20_09:00 AM'},
        state: DoctorAvailabilityState.structured,
      );
      final map = avail.toMap();
      expect(map['blockedDates'], equals(['2026-01-01', '2026-07-04', '2026-12-25']));
      expect(map['blockedSlots'], equals(['2026-10-20_03:00 PM', '2026-10-20_09:00 AM']));
    });
  });

  group('E. Legacy Compatibility Unit Tests', () {
    test('Actual legacy working days and slots are preserved without synthetic grid', () {
      final docData = {
        'availableDays': ['Mon', 'Wed', 'Fri'],
        'availableSlots': ['08:00 AM', '09:30 AM', '11:00 AM'],
        'isAvailable': true,
      };
      final avail = DoctorAvailability.fromDoctorData(docData);
      expect(avail.state, equals(DoctorAvailabilityState.legacy));
      expect(avail.legacyDays, equals(['Mon', 'Wed', 'Fri']));
      expect(avail.legacySlots, equals(['08:00 AM', '09:30 AM', '11:00 AM']));
    });

    test('Malformed legacy day name marks state invalid', () {
      final docData = {
        'availableDays': ['Mon', 'Funday'],
        'availableSlots': ['08:00 AM'],
        'isAvailable': true,
      };
      expect(DoctorAvailability.fromDoctorData(docData).state,
          equals(DoctorAvailabilityState.invalid));
    });

    test('Duplicate legacy slot marks state invalid', () {
      final docData = {
        'availableDays': ['Mon'],
        'availableSlots': ['08:00 AM', '08:00 AM'],
        'isAvailable': true,
      };
      expect(DoctorAvailability.fromDoctorData(docData).state,
          equals(DoctorAvailabilityState.invalid));
    });

    test('Empty legacy collections are treated as unconfigured', () {
      final docData = {
        'availableDays': <String>[],
        'availableSlots': <String>[],
        'isAvailable': true,
      };
      expect(DoctorAvailability.fromDoctorData(docData).state,
          equals(DoctorAvailabilityState.unconfigured));
    });

    test('Legacy isAvailable == false maintains legacy state but rejects slot validity', () {
      final docData = {
        'availableDays': ['Mon'],
        'availableSlots': ['09:00 AM'],
        'isAvailable': false,
      };
      final avail = DoctorAvailability.fromDoctorData(docData);
      expect(avail.state, equals(DoctorAvailabilityState.legacy));

      // Test slot validity
      final validMonday = DateTime(2026, 10, 19); // 2026-10-19 is Monday
      final isSlotValid = SlotGenerator.isSlotValid(
        date: validMonday,
        timeSlot: '09:00 AM',
        availability: avail,
        isDoctorAvailable: false, // passed from doctor.isAvailable
        referenceNow: DateTime(2026, 10, 18),
      );
      expect(isSlotValid, isFalse);
    });
  });

  group('F. SlotGenerator Unit Tests', () {
    test('30-minute grid generation from 09:00 to 11:00', () {
      const day = DaySchedule(enabled: true, startTime: '09:00', endTime: '11:00');
      final slots = SlotGenerator.generateSlots(day, 30);
      expect(slots, equals(['09:00 AM', '09:30 AM', '10:00 AM', '10:30 AM']));
    });

    test('45-minute grid generation from 09:00 to 12:00', () {
      const day = DaySchedule(enabled: true, startTime: '09:00', endTime: '12:00');
      final slots = SlotGenerator.generateSlots(day, 45);
      expect(slots, equals(['09:00 AM', '09:45 AM', '10:30 AM', '11:15 AM']));
    });

    test('60-minute grid generation from 09:00 to 12:00', () {
      const day = DaySchedule(enabled: true, startTime: '09:00', endTime: '12:00');
      final slots = SlotGenerator.generateSlots(day, 60);
      expect(slots, equals(['09:00 AM', '10:00 AM', '11:00 AM']));
    });

    test('No slot extends beyond end time', () {
      const day = DaySchedule(enabled: true, startTime: '09:00', endTime: '10:00');
      // 45 min slot starting at 09:00 ends at 09:45. Next would start at 09:45 and end at 10:30 (exceeds 10:00)
      final slots = SlotGenerator.generateSlots(day, 45);
      expect(slots, equals(['09:00 AM']));
    });

    test('Disabled day generates zero slots', () {
      const day = DaySchedule(enabled: false, startTime: '09:00', endTime: '17:00');
      expect(SlotGenerator.generateSlots(day, 45), isEmpty);
    });

    test('isSlotValid accepts future on-grid slot and rejects off-grid or expired slots', () {
      final avail = DoctorAvailability(
        slotDurationMinutes: 45,
        weeklySchedule: WeeklySchedule.template(),
        blockedDates: {'2026-10-21'},
        blockedSlots: {'2026-10-20_09:45 AM'},
        state: DoctorAvailabilityState.structured,
      );

      final tuesday = DateTime(2026, 10, 20); // Tuesday
      final wednesday = DateTime(2026, 10, 21); // Wednesday (blocked)

      // Fixed reference clock: 2026-10-20 at 09:15 AM
      final refNow = DateTime(2026, 10, 20, 9, 15);

      // On-grid future slot for today
      expect(
        SlotGenerator.isSlotValid(
          date: tuesday,
          timeSlot: '10:30 AM',
          availability: avail,
          referenceNow: refNow,
        ),
        isTrue,
      );

      // Today slot that already passed (09:00 AM at 09:15 AM referenceNow)
      expect(
        SlotGenerator.isSlotValid(
          date: tuesday,
          timeSlot: '09:00 AM',
          availability: avail,
          referenceNow: refNow,
        ),
        isFalse,
      );

      // Blocked slot
      expect(
        SlotGenerator.isSlotValid(
          date: tuesday,
          timeSlot: '09:45 AM',
          availability: avail,
          referenceNow: refNow,
        ),
        isFalse,
      );

      // Blocked date
      expect(
        SlotGenerator.isSlotValid(
          date: wednesday,
          timeSlot: '10:30 AM',
          availability: avail,
          referenceNow: refNow,
        ),
        isFalse,
      );

      // Off-grid slot (09:20 AM not on 45m grid)
      expect(
        SlotGenerator.isSlotValid(
          date: tuesday,
          timeSlot: '09:20 AM',
          availability: avail,
          referenceNow: refNow,
        ),
        isFalse,
      );

      // Past date
      expect(
        SlotGenerator.isSlotValid(
          date: DateTime(2026, 10, 19),
          timeSlot: '10:30 AM',
          availability: avail,
          referenceNow: refNow,
        ),
        isFalse,
      );
    });
  });

  group('G. Interval Overlap Unit Tests (Cases A–E)', () {
    test('Case A: 09:00–09:45 and 09:30–10:00 partially overlap -> Overlap', () {
      final a = AppointmentInterval.fromSlot('2026-10-20', '09:00 AM', 45)!; // 540..585
      final b = AppointmentInterval.fromSlot('2026-10-20', '09:30 AM', 30)!; // 570..600
      expect(a.overlaps(b), isTrue);
      expect(b.overlaps(a), isTrue);
    });

    test('Case B: 09:00–09:45 and 09:45–10:30 adjacent intervals -> No overlap', () {
      final a = AppointmentInterval.fromSlot('2026-10-20', '09:00 AM', 45)!; // 540..585
      final b = AppointmentInterval.fromSlot('2026-10-20', '09:45 AM', 45)!; // 585..630
      expect(a.overlaps(b), isFalse);
      expect(b.overlaps(a), isFalse);
    });

    test('Case C: 09:45–10:30 and 10:00–10:30 contained overlap -> Overlap', () {
      final a = AppointmentInterval.fromSlot('2026-10-20', '09:45 AM', 45)!; // 585..630
      final b = AppointmentInterval.fromSlot('2026-10-20', '10:00 AM', 30)!; // 600..630
      expect(a.overlaps(b), isTrue);
      expect(b.overlaps(a), isTrue);
    });

    test('Case D: Same hours on two different calendar dates -> No overlap', () {
      final a = AppointmentInterval.fromSlot('2026-10-20', '09:00 AM', 45)!;
      final b = AppointmentInterval.fromSlot('2026-10-21', '09:00 AM', 45)!;
      expect(a.overlaps(b), isFalse);
    });

    test('Case E: Invalid or zero-length intervals are rejected', () {
      expect(AppointmentInterval.fromSlot('invalid-date', '09:00 AM', 45), isNull);
      expect(AppointmentInterval.fromSlot('2026-10-20', 'invalid-time', 45), isNull);
      expect(AppointmentInterval.fromSlot('2026-10-20', '09:00 AM', 0), isNull);
      expect(AppointmentInterval.fromSlot('2026-10-20', '09:00 AM', -15), isNull);
    });
  });

  group('H. Serialization & DoctorModel Backward Compatibility Unit Tests', () {
    test('Structured DoctorAvailability round-trips through toMap and fromDoctorData', () {
      final avail = DoctorAvailability(
        slotDurationMinutes: 30,
        weeklySchedule: WeeklySchedule.template(),
        blockedDates: {'2026-11-20', '2026-12-25'},
        blockedSlots: {'2026-11-15_11:15 AM'},
        state: DoctorAvailabilityState.structured,
        updatedAt: DateTime(2026, 10, 15, 10, 0),
      );

      final map = {'availability': avail.toMap()};
      final restored = DoctorAvailability.fromDoctorData(map);

      expect(restored.state, equals(DoctorAvailabilityState.structured));
      expect(restored.slotDurationMinutes, equals(30));
      expect(restored.blockedDates, equals({'2026-11-20', '2026-12-25'}));
      expect(restored.blockedSlots, equals({'2026-11-15_11:15 AM'}));
      expect(restored.weeklySchedule, equals(avail.weeklySchedule));
    });

    test('Legacy-only DoctorModel serializes without writing an availability map', () {
      final doctor = DoctorModel(
        uid: 'doc_123',
        name: 'Dr. Gregory House',
        email: 'house@princeton.edu',
        medicalId: 'MED-1234',
        availableDays: ['Mon', 'Tue', 'Thu'],
        availableSlots: ['08:00 AM', '10:00 AM'],
        isAvailable: true,
        createdAt: DateTime(2026, 1, 1),
      );

      final map = doctor.toMap();
      expect(map.containsKey('availability'), isFalse,
          reason: 'Legacy doctor must not silently serialize a synthetic structured availability map');
      expect(doctor.availability.state, equals(DoctorAvailabilityState.legacy));
      expect(doctor.availability.legacyDays, equals(['Mon', 'Tue', 'Thu']));
      expect(doctor.availability.legacySlots, equals(['08:00 AM', '10:00 AM']));
    });

    test('DoctorModel with structured availability serializes availability map cleanly', () {
      final structuredAvail = DoctorAvailability(
        slotDurationMinutes: 45,
        weeklySchedule: WeeklySchedule.template(),
        blockedDates: {'2026-11-20'},
        blockedSlots: {'2026-11-15_11:15 AM'},
        state: DoctorAvailabilityState.structured,
      );

      final doctor = DoctorModel(
        uid: 'doc_456',
        name: 'Dr. Lisa Cuddy',
        email: 'cuddy@princeton.edu',
        medicalId: 'MED-5678',
        availability: structuredAvail,
        createdAt: DateTime(2026, 1, 1),
      );

      final map = doctor.toMap();
      expect(map.containsKey('availability'), isTrue);
      expect(map['availability']['slotDurationMinutes'], equals(45));

      final restored = DoctorModel.fromMap(map);
      expect(restored.availability.state, equals(DoctorAvailabilityState.structured));
      expect(restored.availability.slotDurationMinutes, equals(45));
    });

    test('DoctorModel copyWith preserves availability and legacy fields correctly', () {
      final doctor = DoctorModel(
        uid: 'doc_789',
        name: 'Dr. James Wilson',
        email: 'wilson@princeton.edu',
        medicalId: 'MED-9999',
        createdAt: DateTime(2026, 1, 1),
      );

      final updated = doctor.copyWith(specialty: 'Oncology');
      expect(updated.specialty, equals('Oncology'));
      expect(updated.name, equals('Dr. James Wilson'));
      expect(updated.availability.state, equals(DoctorAvailabilityState.legacy));
    });
  });
}
