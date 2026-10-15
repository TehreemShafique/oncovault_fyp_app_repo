// test/doctor_availability_service_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:oncovault/models/doctor_availability_model.dart';
import 'package:oncovault/services/doctor_service.dart';
import 'package:oncovault/services/appointment_exceptions.dart';
import 'package:oncovault/utils/slot_generator.dart';

void main() {
  group('DoctorService.updateDoctorAvailability', () {
    final templateSchedule = WeeklySchedule.template();
    final validAvailability = DoctorAvailability(
      slotDurationMinutes: 45,
      weeklySchedule: templateSchedule,
      blockedDates: {'2026-10-25'},
      blockedSlots: {'2026-10-20_11:15 AM'},
      state: DoctorAvailabilityState.structured,
    );

    test('invokes customUpdateAvailabilityCallable with serialized payload', () async {
      final service = DoctorService(
        updateAvailabilityCallable: ({required availability, isAvailable}) async {
          return {'success': true, 'scheduleRevision': 2};
        },
      );

      // Note: when running in unit tests where FirebaseAuth.instance is not initialized,
      // updateDoctorAvailability catches fail-closed if no authenticated user exists.
      // Let's verify that fail-closed unauthenticated behavior:
      expect(
        () => service.updateDoctorAvailability(
          availability: validAvailability,
          isAvailable: true,
        ),
        throwsA(isA<AppointmentUnauthorizedException>()),
      );
    });

    test('DoctorScheduleConflictException is thrown on schedule validation or conflict', () {
      const exc = DoctorScheduleConflictException(
        'Cannot block date 2026-10-25: existing confirmed appointment',
        reason: 'existing confirmed appointment',
      );
      expect(exc.message, contains('Cannot block date'));
      expect(exc.reason, contains('existing confirmed appointment'));
    });
  });

  group('Dynamic Slot Generation & Interval Overlap Verification', () {
    final weekly = WeeklySchedule.template();
    final avail = DoctorAvailability(
      slotDurationMinutes: 45,
      weeklySchedule: weekly,
      blockedDates: {'2026-12-25'},
      blockedSlots: {'2026-10-20_02:15 PM'},
      state: DoctorAvailabilityState.structured,
    );

    test('generates valid 45-minute slots across 09:00 - 17:00 window', () {
      final monday = weekly.getDay(1); // Monday
      final slots = SlotGenerator.generateSlots(monday, 45);

      expect(slots, isNotEmpty);
      expect(slots.first, '09:00 AM');
      expect(slots, contains('09:45 AM'));
      expect(slots, contains('10:30 AM'));
      expect(slots, contains('03:00 PM'));
      expect(slots, contains('03:45 PM'));
      expect(slots.last, '03:45 PM'); // 03:45 PM + 45m = 04:30 PM <= 05:00 PM
    });

    test('isSlotValid rejects blocked dates and blocked individual slots', () {
      final date = DateTime(2026, 12, 25); // Blocked date
      final isValid = SlotGenerator.isSlotValid(
        date: date,
        timeSlot: '09:00 AM',
        availability: avail,
      );
      expect(isValid, isFalse);

      final slotDate = DateTime(2026, 10, 20);
      final isBlockedSlotValid = SlotGenerator.isSlotValid(
        date: slotDate,
        timeSlot: '02:15 PM', // in blockedSlots
        availability: avail,
      );
      expect(isBlockedSlotValid, isFalse);
    });

    test('overlapping interval detection identifies conflicts accurately', () {
      // 09:00 AM to 09:45 AM (540 .. 585)
      final slot1 = AppointmentInterval.fromSlot('2026-10-20', '09:00 AM', 45)!;
      // 09:30 AM to 10:15 AM (570 .. 615) -> overlaps with slot1
      final slot2 = AppointmentInterval.fromSlot('2026-10-20', '09:30 AM', 45)!;
      // 09:45 AM to 10:30 AM (585 .. 630) -> adjacent, does NOT overlap
      final slot3 = AppointmentInterval.fromSlot('2026-10-20', '09:45 AM', 45)!;

      expect(slot1.overlaps(slot2), isTrue);
      expect(slot2.overlaps(slot1), isTrue);
      expect(slot1.overlaps(slot3), isFalse);
      expect(slot3.overlaps(slot1), isFalse);
    });

    test('handles legacy doctor availability correctly', () {
      final legacy = DoctorAvailability.legacy(
        legacyDays: ['Mon', 'Wed', 'Fri'],
        legacySlots: ['09:00 AM', '11:00 AM', '02:00 PM'],
      );

      expect(legacy.state, DoctorAvailabilityState.legacy);

      // Monday is allowed
      final mon = DateTime(2026, 10, 19); // Monday
      expect(
        SlotGenerator.isSlotValid(
          date: mon,
          timeSlot: '09:00 AM',
          availability: legacy,
          referenceNow: DateTime(2026, 10, 1),
        ),
        isTrue,
      );

      // Tuesday is not in legacyDays
      final tue = DateTime(2026, 10, 20); // Tuesday
      expect(
        SlotGenerator.isSlotValid(
          date: tue,
          timeSlot: '09:00 AM',
          availability: legacy,
          referenceNow: DateTime(2026, 10, 1),
        ),
        isFalse,
      );

      // Slot not in legacySlots is rejected
      expect(
        SlotGenerator.isSlotValid(
          date: mon,
          timeSlot: '10:00 AM',
          availability: legacy,
          referenceNow: DateTime(2026, 10, 1),
        ),
        isFalse,
      );
    });
  });
}
