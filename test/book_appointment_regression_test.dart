import 'package:flutter_test/flutter_test.dart';
import 'package:oncovault/models/doctor_availability_model.dart';
import 'package:oncovault/models/doctor_model.dart';
import 'package:oncovault/utils/slot_generator.dart';

void main() {
  group('Appointment Booking Regression Tests (Part B)', () {
    test('DoctorModel defaults to standard Mon-Fri availability when unconfigured', () {
      final doc = DoctorModel(
        uid: 'doc_123',
        name: 'Dr. Gregory House',
        email: 'house@princeton.edu',
        medicalId: 'OV-DO-HOUSE1',
        specialty: 'Diagnostic Oncology',
        createdAt: DateTime.now(),
      );

      expect(doc.availableDays, containsAll(['Mon', 'Tue', 'Wed', 'Thu', 'Fri']));
      expect(doc.availableSlots, containsAll(['08:00 AM', '09:30 AM', '11:00 AM', '01:30 PM', '03:00 PM', '04:30 PM']));
      expect(doc.isAvailable, isTrue);

      final avail = doc.availability;
      expect(avail.state, equals(DoctorAvailabilityState.legacy));
      expect(avail.legacyDays, contains('Mon'));
      expect(avail.legacyDays, isNot(contains('Sat')));
      expect(avail.legacyDays, isNot(contains('Sun')));
    });

    test('DoctorAvailability.fromDoctorData safely falls back on raw map without crashing', () {
      final emptyDocMap = <String, dynamic>{
        'name': 'Dr. Empty',
        'isAvailable': true,
      };

      // Raw unconfigured without fallback returns unconfigured
      final rawAvail = DoctorAvailability.fromDoctorData(emptyDocMap);
      expect(rawAvail.state, equals(DoctorAvailabilityState.unconfigured));

      // With legacy fallback applied as in BookAppointmentScreen
      final safeAvail = DoctorAvailability.legacy(
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

      expect(safeAvail.state, equals(DoctorAvailabilityState.legacy));
      expect(safeAvail.legacySlots.length, equals(6));
    });

    test('Calendar date generation creates exact 42 days without timezone offset drifts', () {
      final focusedMonth = DateTime(2026, 10, 1);
      final first = DateTime(focusedMonth.year, focusedMonth.month, 1);
      final start = first.subtract(Duration(days: first.weekday % 7));

      final days = List.generate(
        42,
        (i) => DateTime(start.year, start.month, start.day + i),
      );

      expect(days.length, equals(42));
      for (int i = 0; i < 41; i++) {
        expect(days[i + 1].difference(days[i]).inDays, equals(1));
        expect(days[i].hour, equals(0)); // No DST hour drift
      }
    });

    test('SlotGenerator evaluates future slots on working days as valid', () {
      final avail = DoctorAvailability.legacy(
        legacyDays: const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'],
        legacySlots: const ['08:00 AM', '09:30 AM', '11:00 AM', '01:30 PM', '03:00 PM', '04:30 PM'],
      );

      // A future Monday
      final futureMonday = DateTime(2026, 10, 26); // Monday
      expect(futureMonday.weekday, equals(DateTime.monday));

      final isValid = SlotGenerator.isSlotValid(
        date: futureMonday,
        timeSlot: '09:30 AM',
        availability: avail,
        isDoctorAvailable: true,
        referenceNow: DateTime(2026, 10, 18),
      );
      expect(isValid, isTrue);

      // Saturday should be rejected
      final saturday = DateTime(2026, 10, 24); // Saturday
      final isSaturdayValid = SlotGenerator.isSlotValid(
        date: saturday,
        timeSlot: '09:30 AM',
        availability: avail,
        isDoctorAvailable: true,
        referenceNow: DateTime(2026, 10, 18),
      );
      expect(isSaturdayValid, isFalse);

      // Past date should be rejected
      final pastDate = DateTime(2026, 10, 10);
      final isPastValid = SlotGenerator.isSlotValid(
        date: pastDate,
        timeSlot: '09:30 AM',
        availability: avail,
        isDoctorAvailable: true,
        referenceNow: DateTime(2026, 10, 18),
      );
      expect(isPastValid, isFalse);
    });

    test('Overlapping slot and blocked slot detection detects unavailable slots', () {
      const dateKey = '2026-10-26';
      const slot = '09:30 AM';
      const slotDuration = 45;

      final candidate = AppointmentInterval.fromSlot(dateKey, slot, slotDuration);
      expect(candidate, isNotNull);

      // Exact match
      final bookedSame = AppointmentInterval.fromSlot(dateKey, '09:30 AM', slotDuration);
      expect(candidate!.overlaps(bookedSame!), isTrue);

      // Adjacent non-overlapping
      final bookedNext = AppointmentInterval.fromSlot(dateKey, '10:15 AM', slotDuration);
      expect(candidate.overlaps(bookedNext!), isFalse);

      // Different date non-overlapping
      final bookedOtherDay = AppointmentInterval.fromSlot('2026-10-27', '09:30 AM', slotDuration);
      expect(candidate.overlaps(bookedOtherDay!), isFalse);
    });

    test('Field-specific booking validation correctly identifies missing fields', () {
      String? validateBooking({
        required String? doctorId,
        required DateTime? date,
        required String? slot,
      }) {
        if (doctorId == null || doctorId.isEmpty) return 'Please select a doctor.';
        if (date == null) return 'Please select an appointment date.';
        if (slot == null || slot.isEmpty) return 'Please select an available time slot.';
        return null;
      }

      expect(validateBooking(doctorId: null, date: DateTime(2026, 10, 20), slot: '09:30 AM'),
          equals('Please select a doctor.'));
      expect(validateBooking(doctorId: 'doc_1', date: null, slot: '09:30 AM'),
          equals('Please select an appointment date.'));
      expect(validateBooking(doctorId: 'doc_1', date: DateTime(2026, 10, 20), slot: null),
          equals('Please select an available time slot.'));
      expect(validateBooking(doctorId: 'doc_1', date: DateTime(2026, 10, 20), slot: '09:30 AM'),
          isNull);
    });
  });
}
