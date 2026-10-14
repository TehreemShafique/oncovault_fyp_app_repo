// test/appointment_exceptions_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:oncovault/models/appointment_model.dart';
import 'package:oncovault/services/appointment_exceptions.dart';
import 'package:oncovault/services/appointment_service.dart';
import 'package:oncovault/services/doctor_service.dart';

class _FakeUser extends Fake implements User {
  @override
  final String uid;
  _FakeUser(this.uid);
}

class _FakeAuth extends Fake implements FirebaseAuth {
  @override
  final User? currentUser;
  _FakeAuth(this.currentUser);
}

void main() {
  group('Appointment Domain Concurrency Exceptions (Step 2B.1) Tests', () {
    test('1. SlotAlreadyBookedException accurately captures conflict context',
        () {
      final date = DateTime(2026, 10, 15);
      const slot = '09:30 AM';
      final slotKey = buildSlotKey(date, slot);

      const ex = SlotAlreadyBookedException(
        'Slot is already occupied.',
        slotKey: '2026-10-15_09:30 AM',
        conflictingAppointmentId: 'appt_existing_99',
      );

      expect(ex, isA<AppointmentException>());
      expect(ex, isA<Exception>());
      expect(ex.slotKey, equals(slotKey));
      expect(ex.conflictingAppointmentId, equals('appt_existing_99'));
      expect(ex.message, equals('Slot is already occupied.'));
      expect(ex.toString(), equals('Slot is already occupied.'));
    });

    test(
        '2. AppointmentStateConflictException accurately captures state mismatch',
        () {
      const ex = AppointmentStateConflictException(
        'Cannot approve appointment appt_123: status is cancelled.',
        appointmentId: 'appt_123',
        currentStatus: 'cancelled',
        requiredStatus: 'scheduled',
      );

      expect(ex, isA<AppointmentException>());
      expect(ex.appointmentId, equals('appt_123'));
      expect(ex.currentStatus, equals('cancelled'));
      expect(ex.requiredStatus, equals('scheduled'));
      expect(ex.message, contains('appt_123'));
      expect(ex.toString(), equals(ex.message));
    });

    test('3. AppointmentNotFoundException represents missing document', () {
      const ex = AppointmentNotFoundException(
        'Appointment appt_missing_404 not found in Firestore.',
        appointmentId: 'appt_missing_404',
      );

      expect(ex, isA<AppointmentException>());
      expect(ex.appointmentId, equals('appt_missing_404'));
      expect(ex.toString(), contains('appt_missing_404'));
    });

    test('4. AppointmentUnauthorizedException represents mismatched doctor',
        () {
      const ex = AppointmentUnauthorizedException(
        'Doctor dr_eve is not authorized to approve appointment appt_1.',
        appointmentId: 'appt_1',
      );

      expect(ex, isA<AppointmentException>());
      expect(ex.appointmentId, equals('appt_1'));
      expect(ex.toString(), contains('dr_eve'));
    });

    test(
        '5. Canonical buildSlotKey generates matching key for SlotAlreadyBookedException',
        () {
      final apptDate = DateTime(2026, 4, 9);
      const timeSlot = '02:00 PM';
      final derivedKey = buildSlotKey(apptDate, timeSlot);

      final exception = SlotAlreadyBookedException(
        'Slot collision detected',
        slotKey: derivedKey,
        conflictingAppointmentId: 'appt_other',
      );

      expect(exception.slotKey, equals('2026-04-09_02:00 PM'));
    });

    test(
        '6. AppointmentMirrorInconsistentException captures mirror mismatch context',
        () {
      const ex = AppointmentMirrorInconsistentException(
        'Patient appointment mirror missing at /patients/p_1/appointments/appt_1.',
        appointmentId: 'appt_1',
        patientId: 'p_1',
        reason: 'Mirror document does not exist.',
      );

      expect(ex, isA<AppointmentException>());
      expect(ex.appointmentId, equals('appt_1'));
      expect(ex.patientId, equals('p_1'));
      expect(ex.reason, equals('Mirror document does not exist.'));
      expect(ex.toString(), contains('appt_1'));
    });

    test('7. SlotLockCorruptException captures corrupt slot key', () {
      const ex = SlotLockCorruptException(
        'Slot document 2026-10-15_09:30 AM has invalid or empty appointmentId.',
        slotKey: '2026-10-15_09:30 AM',
      );

      expect(ex, isA<AppointmentException>());
      expect(ex.slotKey, equals('2026-10-15_09:30 AM'));
      expect(ex.toString(), contains('2026-10-15_09:30 AM'));
    });

    test(
        '8. DoctorService.approveAppointment fails closed when unauthenticated',
        () async {
      final service = DoctorService();
      final appt = AppointmentModel(
        id: 'appt_test_auth',
        patientId: 'p_1',
        patientName: 'Patient 1',
        doctorId: 'dr_1',
        doctorName: 'Dr. One',
        doctorSpecialty: 'Oncology',
        appointmentDate: DateTime(2026, 10, 15),
        timeSlot: '09:30 AM',
        status: AppointmentStatus.scheduled,
        createdAt: DateTime.now(),
      );

      expect(
        () => service.approveAppointment(appt),
        throwsA(isA<AppointmentUnauthorizedException>().having(
          (e) => e.appointmentId,
          'appointmentId',
          equals('appt_test_auth'),
        )),
      );
    });

    test(
        '9. AppointmentPayloadConflictException captures payload conflict metadata',
        () {
      const ex = AppointmentPayloadConflictException(
        'Caller appointment date conflicts with authoritative date.',
        appointmentId: 'appt_date_mismatch',
        field: 'appointmentDate',
        expectedValue: '15/10/2026',
        actualValue: '16/10/2026',
      );

      expect(ex, isA<AppointmentException>());
      expect(ex.appointmentId, equals('appt_date_mismatch'));
      expect(ex.field, equals('appointmentDate'));
      expect(ex.expectedValue, equals('15/10/2026'));
      expect(ex.actualValue, equals('16/10/2026'));
      expect(ex.toString(), contains('conflicts with authoritative date'));
    });

    test(
        '10. DoctorService.approveAppointment rejects empty doctorId on payload',
        () async {
      final service = DoctorService();
      final appt = AppointmentModel(
        id: 'appt_empty_dr',
        patientId: 'p_1',
        patientName: 'Patient 1',
        doctorId: '   ',
        doctorName: 'Dr. None',
        doctorSpecialty: 'Oncology',
        appointmentDate: DateTime(2026, 10, 15),
        timeSlot: '09:30 AM',
        status: AppointmentStatus.scheduled,
        createdAt: DateTime.now(),
      );

      expect(
        () => service.approveAppointment(appt),
        throwsA(isA<AppointmentUnauthorizedException>().having(
          (e) => e.appointmentId,
          'appointmentId',
          equals('appt_empty_dr'),
        )),
      );
    });

    test(
        '11. SlotLockCorruptException captures date and bookedAt corruption scenarios',
        () {
      const exMissingDate = SlotLockCorruptException(
        'Slot lock for appointment appt_1 is missing or has invalid date.',
        slotKey: '2026-10-15_09:30 AM',
      );
      expect(exMissingDate, isA<AppointmentException>());
      expect(exMissingDate.slotKey, equals('2026-10-15_09:30 AM'));
      expect(exMissingDate.message, contains('missing or has invalid date'));

      const exMissingBookedAt = SlotLockCorruptException(
        'Slot lock for appointment appt_1 is missing or has invalid bookedAt timestamp.',
        slotKey: '2026-10-15_09:30 AM',
      );
      expect(exMissingBookedAt, isA<AppointmentException>());
      expect(exMissingBookedAt.slotKey, equals('2026-10-15_09:30 AM'));
      expect(exMissingBookedAt.message, contains('invalid bookedAt timestamp'));
    });

    test(
        '12. AppointmentStateConflictException accurately captures missing, empty, and unrecognized raw statuses',
        () {
      const exMissing = AppointmentStateConflictException(
        'Appointment document appt_1 status is missing or empty, cannot be confirmed.',
        appointmentId: 'appt_1',
        currentStatus: '',
        requiredStatus: 'scheduled',
      );
      expect(exMissing.appointmentId, equals('appt_1'));
      expect(exMissing.currentStatus, equals(''));
      expect(exMissing.requiredStatus, equals('scheduled'));
      expect(exMissing.message, contains('missing or empty'));

      const exUnrecognized = AppointmentStateConflictException(
        'Appointment is in unrecognized status "corrupted_val" status, cannot be confirmed.',
        appointmentId: 'appt_1',
        currentStatus: 'corrupted_val',
        requiredStatus: 'scheduled',
      );
      expect(exUnrecognized.currentStatus, equals('corrupted_val'));
      expect(exUnrecognized.message, contains('unrecognized status'));
    });

    test(
        '13. DoctorService.isStatusEligibleForApproval accepts scheduled and legacy pending case-insensitively with trimming',
        () {
      expect(DoctorService.isStatusEligibleForApproval('scheduled'), isTrue);
      expect(DoctorService.isStatusEligibleForApproval('pending'), isTrue);
      expect(DoctorService.isStatusEligibleForApproval('SCHEDULED'), isTrue);
      expect(DoctorService.isStatusEligibleForApproval('PENDING'), isTrue);
      expect(
          DoctorService.isStatusEligibleForApproval('  scheduled  '), isTrue);
      expect(DoctorService.isStatusEligibleForApproval('  pending  '), isTrue);
      expect(DoctorService.isStatusEligibleForApproval('Scheduled'), isTrue);
      expect(DoctorService.isStatusEligibleForApproval('Pending'), isTrue);
    });

    test(
        '14. DoctorService.isStatusEligibleForApproval rejects null, empty, whitespace, unrecognized, and non-scheduled statuses',
        () {
      // Null, empty, and whitespace
      expect(DoctorService.isStatusEligibleForApproval(null), isFalse);
      expect(DoctorService.isStatusEligibleForApproval(''), isFalse);
      expect(DoctorService.isStatusEligibleForApproval('   '), isFalse);

      // Known non-scheduled statuses (must not be eligible for approval)
      expect(DoctorService.isStatusEligibleForApproval('confirmed'), isFalse);
      expect(DoctorService.isStatusEligibleForApproval('approved'), isFalse);
      expect(DoctorService.isStatusEligibleForApproval('rescheduled'), isFalse);
      expect(DoctorService.isStatusEligibleForApproval('cancelled'), isFalse);
      expect(DoctorService.isStatusEligibleForApproval('canceled'), isFalse);
      expect(DoctorService.isStatusEligibleForApproval('completed'), isFalse);
      expect(DoctorService.isStatusEligibleForApproval('rejected'), isFalse);
      expect(DoctorService.isStatusEligibleForApproval('APPROVED'), isFalse);
      expect(DoctorService.isStatusEligibleForApproval('CONFIRMED'), isFalse);

      // Unrecognized / corrupt values
      expect(DoctorService.isStatusEligibleForApproval('unknown'), isFalse);
      expect(
          DoctorService.isStatusEligibleForApproval('corrupt_status'), isFalse);
      expect(DoctorService.isStatusEligibleForApproval('pending_approval'),
          isFalse);
    });

    test(
        '15. AppointmentService.isStatusEligibleForCancellation accepts scheduled, pending, confirmed, approved, and rescheduled',
        () {
      // Canonical & legacy scheduled
      expect(AppointmentService.isStatusEligibleForCancellation('scheduled'),
          isTrue);
      expect(AppointmentService.isStatusEligibleForCancellation('pending'),
          isTrue);
      expect(AppointmentService.isStatusEligibleForCancellation('SCHEDULED'),
          isTrue);
      expect(AppointmentService.isStatusEligibleForCancellation('PENDING'),
          isTrue);
      expect(
          AppointmentService.isStatusEligibleForCancellation('  scheduled  '),
          isTrue);
      expect(AppointmentService.isStatusEligibleForCancellation('  pending  '),
          isTrue);

      // Canonical & legacy confirmed
      expect(AppointmentService.isStatusEligibleForCancellation('confirmed'),
          isTrue);
      expect(AppointmentService.isStatusEligibleForCancellation('approved'),
          isTrue);
      expect(AppointmentService.isStatusEligibleForCancellation('CONFIRMED'),
          isTrue);
      expect(AppointmentService.isStatusEligibleForCancellation('APPROVED'),
          isTrue);
      expect(
          AppointmentService.isStatusEligibleForCancellation('  confirmed  '),
          isTrue);
      expect(AppointmentService.isStatusEligibleForCancellation('  approved  '),
          isTrue);

      // Rescheduled
      expect(AppointmentService.isStatusEligibleForCancellation('rescheduled'),
          isTrue);
      expect(AppointmentService.isStatusEligibleForCancellation('RESCHEDULED'),
          isTrue);
      expect(
          AppointmentService.isStatusEligibleForCancellation('  rescheduled  '),
          isTrue);
    });

    test(
        '16. AppointmentService.isStatusEligibleForCancellation rejects null, empty, whitespace, unrecognized, and terminal statuses',
        () {
      // Null, empty, and whitespace
      expect(AppointmentService.isStatusEligibleForCancellation(null), isFalse);
      expect(AppointmentService.isStatusEligibleForCancellation(''), isFalse);
      expect(
          AppointmentService.isStatusEligibleForCancellation('   '), isFalse);

      // Terminal / ineligible statuses
      expect(AppointmentService.isStatusEligibleForCancellation('cancelled'),
          isFalse);
      expect(AppointmentService.isStatusEligibleForCancellation('canceled'),
          isFalse);
      expect(AppointmentService.isStatusEligibleForCancellation('completed'),
          isFalse);
      expect(AppointmentService.isStatusEligibleForCancellation('rejected'),
          isFalse);
      expect(AppointmentService.isStatusEligibleForCancellation('CANCELLED'),
          isFalse);
      expect(AppointmentService.isStatusEligibleForCancellation('CANCELED'),
          isFalse);
      expect(AppointmentService.isStatusEligibleForCancellation('COMPLETED'),
          isFalse);
      expect(AppointmentService.isStatusEligibleForCancellation('REJECTED'),
          isFalse);

      // Unrecognized / corrupt values
      expect(AppointmentService.isStatusEligibleForCancellation('unknown'),
          isFalse);
      expect(
          AppointmentService.isStatusEligibleForCancellation('corrupt_status'),
          isFalse);
      expect(AppointmentService.isStatusEligibleForCancellation('active'),
          isFalse);
    });

    test(
        '17. AppointmentService.cancelAppointment rejects empty appointmentId or patientId',
        () async {
      final service = AppointmentService();

      // Empty appointmentId
      expect(
        () => service.cancelAppointment('', 'p_1'),
        throwsA(isA<AppointmentPayloadConflictException>().having(
          (e) => e.field,
          'field',
          equals('appointmentId'),
        )),
      );

      // Whitespace-only patientId
      expect(
        () => service.cancelAppointment('appt_1', '   '),
        throwsA(isA<AppointmentPayloadConflictException>().having(
          (e) => e.field,
          'field',
          equals('patientId'),
        )),
      );
    });

    test(
        '18. AppointmentService.cancelAppointment fails closed when unauthenticated',
        () async {
      final service = AppointmentService();

      expect(
        () => service.cancelAppointment('appt_test_auth', 'p_unauthenticated'),
        throwsA(isA<AppointmentUnauthorizedException>().having(
          (e) => e.appointmentId,
          'appointmentId',
          equals('appt_test_auth'),
        )),
      );
    });

    test(
        '19. AppointmentService.cancelAppointment rejects mismatched authenticated UID and supplied patient ID before Firestore interaction',
        () async {
      final fakeAuth = _FakeAuth(_FakeUser('patient_A'));
      // Construct service with fakeAuth but without Firestore; if the guard runs
      // prior to Firestore access, it throws AppointmentUnauthorizedException.
      final service = AppointmentService(auth: fakeAuth);

      expect(
        () => service.cancelAppointment('appt_1', 'patient_B'),
        throwsA(isA<AppointmentUnauthorizedException>()
            .having(
              (e) => e.appointmentId,
              'appointmentId',
              equals('appt_1'),
            )
            .having(
              (e) => e.message,
              'message',
              contains('Authenticated user UID does not match the patient ID.'),
            )),
      );
    });

    test(
        '20. AppointmentService.isStatusEligibleForRescheduling accepts scheduled, pending, confirmed, approved, and rescheduled',
        () {
      // Canonical & legacy scheduled
      expect(AppointmentService.isStatusEligibleForRescheduling('scheduled'),
          isTrue);
      expect(AppointmentService.isStatusEligibleForRescheduling('pending'),
          isTrue);
      expect(AppointmentService.isStatusEligibleForRescheduling('SCHEDULED'),
          isTrue);
      expect(AppointmentService.isStatusEligibleForRescheduling('PENDING'),
          isTrue);
      expect(
          AppointmentService.isStatusEligibleForRescheduling('  scheduled  '),
          isTrue);
      expect(AppointmentService.isStatusEligibleForRescheduling('  pending  '),
          isTrue);

      // Canonical & legacy confirmed
      expect(AppointmentService.isStatusEligibleForRescheduling('confirmed'),
          isTrue);
      expect(AppointmentService.isStatusEligibleForRescheduling('approved'),
          isTrue);
      expect(AppointmentService.isStatusEligibleForRescheduling('CONFIRMED'),
          isTrue);
      expect(AppointmentService.isStatusEligibleForRescheduling('APPROVED'),
          isTrue);
      expect(
          AppointmentService.isStatusEligibleForRescheduling('  confirmed  '),
          isTrue);
      expect(AppointmentService.isStatusEligibleForRescheduling('  approved  '),
          isTrue);

      // Rescheduled
      expect(AppointmentService.isStatusEligibleForRescheduling('rescheduled'),
          isTrue);
      expect(AppointmentService.isStatusEligibleForRescheduling('RESCHEDULED'),
          isTrue);
      expect(
          AppointmentService.isStatusEligibleForRescheduling('  rescheduled  '),
          isTrue);
    });

    test(
        '21. AppointmentService.isStatusEligibleForRescheduling rejects null, empty, whitespace, unrecognized, and terminal statuses',
        () {
      // Null, empty, and whitespace
      expect(AppointmentService.isStatusEligibleForRescheduling(null), isFalse);
      expect(AppointmentService.isStatusEligibleForRescheduling(''), isFalse);
      expect(
          AppointmentService.isStatusEligibleForRescheduling('   '), isFalse);

      // Terminal / ineligible statuses
      expect(AppointmentService.isStatusEligibleForRescheduling('cancelled'),
          isFalse);
      expect(AppointmentService.isStatusEligibleForRescheduling('canceled'),
          isFalse);
      expect(AppointmentService.isStatusEligibleForRescheduling('completed'),
          isFalse);
      expect(AppointmentService.isStatusEligibleForRescheduling('rejected'),
          isFalse);
      expect(AppointmentService.isStatusEligibleForRescheduling('CANCELLED'),
          isFalse);
      expect(AppointmentService.isStatusEligibleForRescheduling('CANCELED'),
          isFalse);
      expect(AppointmentService.isStatusEligibleForRescheduling('COMPLETED'),
          isFalse);
      expect(AppointmentService.isStatusEligibleForRescheduling('REJECTED'),
          isFalse);

      // Unrecognized / corrupt values
      expect(AppointmentService.isStatusEligibleForRescheduling('unknown'),
          isFalse);
      expect(
          AppointmentService.isStatusEligibleForRescheduling('corrupt_status'),
          isFalse);
      expect(AppointmentService.isStatusEligibleForRescheduling('active'),
          isFalse);
    });

    test(
        '22. AppointmentService.rescheduleAppointment rejects empty appointmentId, patientId, or newTimeSlot',
        () async {
      final service = AppointmentService();
      final testDate = DateTime(2026, 11, 20);

      // Empty appointmentId
      expect(
        () => service.rescheduleAppointment(
          appointmentId: '',
          patientId: 'p_1',
          newDate: testDate,
          newTimeSlot: '09:30 AM',
        ),
        throwsA(isA<AppointmentPayloadConflictException>().having(
          (e) => e.field,
          'field',
          equals('appointmentId'),
        )),
      );

      // Whitespace-only patientId
      expect(
        () => service.rescheduleAppointment(
          appointmentId: 'appt_1',
          patientId: '   ',
          newDate: testDate,
          newTimeSlot: '09:30 AM',
        ),
        throwsA(isA<AppointmentPayloadConflictException>().having(
          (e) => e.field,
          'field',
          equals('patientId'),
        )),
      );

      // Empty newTimeSlot
      expect(
        () => service.rescheduleAppointment(
          appointmentId: 'appt_1',
          patientId: 'p_1',
          newDate: testDate,
          newTimeSlot: '   ',
        ),
        throwsA(isA<AppointmentPayloadConflictException>().having(
          (e) => e.field,
          'field',
          equals('newTimeSlot'),
        )),
      );
    });

    test(
        '23. AppointmentService.rescheduleAppointment fails closed when unauthenticated',
        () async {
      final service = AppointmentService();

      expect(
        () => service.rescheduleAppointment(
          appointmentId: 'appt_test_auth',
          patientId: 'p_unauthenticated',
          newDate: DateTime(2026, 11, 20),
          newTimeSlot: '10:00 AM',
        ),
        throwsA(isA<AppointmentUnauthorizedException>().having(
          (e) => e.appointmentId,
          'appointmentId',
          equals('appt_test_auth'),
        )),
      );
    });

    test(
        '24. AppointmentService.rescheduleAppointment rejects mismatched authenticated UID and supplied patient ID before Firestore interaction',
        () async {
      final fakeAuth = _FakeAuth(_FakeUser('patient_A'));
      final service = AppointmentService(auth: fakeAuth);

      expect(
        () => service.rescheduleAppointment(
          appointmentId: 'appt_resched_1',
          patientId: 'patient_B',
          newDate: DateTime(2026, 11, 20),
          newTimeSlot: '11:00 AM',
        ),
        throwsA(isA<AppointmentUnauthorizedException>()
            .having(
              (e) => e.appointmentId,
              'appointmentId',
              equals('appt_resched_1'),
            )
            .having(
              (e) => e.message,
              'message',
              contains('Authenticated user UID does not match the patient ID.'),
            )),
      );
    });

    test(
        '25. AppointmentService.rescheduleAppointment and validateAppointmentDate reject yesterday before Firestore interaction',
        () async {
      final now = DateTime.now();
      final yesterday =
          DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1));

      // 1. Isolated helper test
      expect(
        () => AppointmentService.validateAppointmentDate(
          yesterday,
          appointmentId: 'appt_past_test',
        ),
        throwsA(isA<AppointmentPayloadConflictException>()
            .having((e) => e.appointmentId, 'appointmentId', equals('appt_past_test'))
            .having((e) => e.field, 'field', equals('newDate'))
            .having((e) => e.expectedValue, 'expectedValue', equals('date on or after today'))
            .having((e) => e.message, 'message', contains('Appointment date cannot be in the past.'))),
      );

      // 2. Service-level pre-transaction test: rejects before Firestore interaction
      final service = AppointmentService();
      expect(
        () => service.rescheduleAppointment(
          appointmentId: 'appt_past_test',
          patientId: 'patient_A',
          newDate: yesterday,
          newTimeSlot: '10:00 AM',
        ),
        throwsA(isA<AppointmentPayloadConflictException>()
            .having((e) => e.appointmentId, 'appointmentId', equals('appt_past_test'))
            .having((e) => e.field, 'field', equals('newDate'))),
      );

      // 3. Isolated test with fixed reference time across midnight boundary
      final fixedRefNow = DateTime(2026, 10, 14, 15, 30);
      final fixedYesterday = DateTime(2026, 10, 13, 23, 59);
      expect(
        () => AppointmentService.validateAppointmentDate(
          fixedYesterday,
          appointmentId: 'fixed_past',
          referenceNow: fixedRefNow,
        ),
        throwsA(isA<AppointmentPayloadConflictException>()),
      );
    });

    test(
        '26. AppointmentService.validateAppointmentDate accepts today (regardless of hour) and tomorrow',
        () {
      final now = DateTime.now();
      final todayMidnight = DateTime(now.year, now.month, now.day);
      final todayEarly = DateTime(now.year, now.month, now.day, 0, 1);
      final todayLate = DateTime(now.year, now.month, now.day, 23, 59);
      final tomorrow = todayMidnight.add(const Duration(days: 1));
      final nextWeek = todayMidnight.add(const Duration(days: 7));

      // None of these should throw
      expect(() => AppointmentService.validateAppointmentDate(todayMidnight),
          returnsNormally);
      expect(() => AppointmentService.validateAppointmentDate(todayEarly),
          returnsNormally);
      expect(() => AppointmentService.validateAppointmentDate(todayLate),
          returnsNormally);
      expect(() => AppointmentService.validateAppointmentDate(tomorrow),
          returnsNormally);
      expect(() => AppointmentService.validateAppointmentDate(nextWeek),
          returnsNormally);

      // With fixed reference time to prove hour-independence
      final fixedRef = DateTime(2026, 10, 14, 23, 45); // late at night
      final sameDayMorning = DateTime(2026, 10, 14, 8, 30); // earlier that day
      final fixedTomorrow = DateTime(2026, 10, 15, 9, 0);

      expect(
        () => AppointmentService.validateAppointmentDate(
          sameDayMorning,
          referenceNow: fixedRef,
        ),
        returnsNormally,
      );
      expect(
        () => AppointmentService.validateAppointmentDate(
          fixedTomorrow,
          referenceNow: fixedRef,
        ),
        returnsNormally,
      );
    });

    test(
        '27. DoctorService.isStatusEligibleForRescheduling accepts scheduled, pending, confirmed, approved, and rescheduled',
        () {
      // Canonical & legacy scheduled
      expect(DoctorService.isStatusEligibleForRescheduling('scheduled'), isTrue);
      expect(DoctorService.isStatusEligibleForRescheduling('pending'), isTrue);
      expect(DoctorService.isStatusEligibleForRescheduling('SCHEDULED'), isTrue);
      expect(DoctorService.isStatusEligibleForRescheduling('PENDING'), isTrue);
      expect(DoctorService.isStatusEligibleForRescheduling('  scheduled  '), isTrue);
      expect(DoctorService.isStatusEligibleForRescheduling('  pending  '), isTrue);

      // Canonical & legacy confirmed
      expect(DoctorService.isStatusEligibleForRescheduling('confirmed'), isTrue);
      expect(DoctorService.isStatusEligibleForRescheduling('approved'), isTrue);
      expect(DoctorService.isStatusEligibleForRescheduling('CONFIRMED'), isTrue);
      expect(DoctorService.isStatusEligibleForRescheduling('APPROVED'), isTrue);
      expect(DoctorService.isStatusEligibleForRescheduling('  confirmed  '), isTrue);
      expect(DoctorService.isStatusEligibleForRescheduling('  approved  '), isTrue);

      // Rescheduled
      expect(DoctorService.isStatusEligibleForRescheduling('rescheduled'), isTrue);
      expect(DoctorService.isStatusEligibleForRescheduling('RESCHEDULED'), isTrue);
      expect(DoctorService.isStatusEligibleForRescheduling('  rescheduled  '), isTrue);
    });

    test(
        '28. DoctorService.isStatusEligibleForRescheduling rejects null, empty, whitespace, unrecognized, and terminal statuses',
        () {
      // Null, empty, and whitespace
      expect(DoctorService.isStatusEligibleForRescheduling(null), isFalse);
      expect(DoctorService.isStatusEligibleForRescheduling(''), isFalse);
      expect(DoctorService.isStatusEligibleForRescheduling('   '), isFalse);

      // Terminal / ineligible statuses
      expect(DoctorService.isStatusEligibleForRescheduling('cancelled'), isFalse);
      expect(DoctorService.isStatusEligibleForRescheduling('canceled'), isFalse);
      expect(DoctorService.isStatusEligibleForRescheduling('completed'), isFalse);
      expect(DoctorService.isStatusEligibleForRescheduling('rejected'), isFalse);
      expect(DoctorService.isStatusEligibleForRescheduling('CANCELLED'), isFalse);
      expect(DoctorService.isStatusEligibleForRescheduling('CANCELED'), isFalse);
      expect(DoctorService.isStatusEligibleForRescheduling('COMPLETED'), isFalse);
      expect(DoctorService.isStatusEligibleForRescheduling('REJECTED'), isFalse);

      // Unrecognized / corrupt values
      expect(DoctorService.isStatusEligibleForRescheduling('unknown'), isFalse);
      expect(DoctorService.isStatusEligibleForRescheduling('corrupt_status'), isFalse);
      expect(DoctorService.isStatusEligibleForRescheduling('active'), isFalse);
    });

    test(
        '29. DoctorService.doctorReschedule rejects empty appointment id, doctorId, patientId, or newSlot',
        () async {
      final service = DoctorService();
      final futureDate = DateTime(2026, 11, 20);

      AppointmentModel makeAppt({
        String id = 'appt_1',
        String doctorId = 'doctor_1',
        String patientId = 'patient_1',
      }) =>
          AppointmentModel(
            id: id,
            patientId: patientId,
            patientName: 'Patient 1',
            doctorId: doctorId,
            doctorName: 'Dr. One',
            doctorSpecialty: 'Oncology',
            appointmentDate: futureDate,
            timeSlot: '09:30 AM',
            status: AppointmentStatus.scheduled,
            createdAt: DateTime.now(),
          );

      // Empty appointmentId
      expect(
        () => service.doctorReschedule(
          appt: makeAppt(id: ''),
          newDate: futureDate,
          newSlot: '10:00 AM',
        ),
        throwsA(isA<AppointmentPayloadConflictException>().having(
          (e) => e.field,
          'field',
          equals('id'),
        )),
      );

      // Empty doctorId
      expect(
        () => service.doctorReschedule(
          appt: makeAppt(doctorId: '   '),
          newDate: futureDate,
          newSlot: '10:00 AM',
        ),
        throwsA(isA<AppointmentPayloadConflictException>().having(
          (e) => e.field,
          'field',
          equals('doctorId'),
        )),
      );

      // Empty patientId
      expect(
        () => service.doctorReschedule(
          appt: makeAppt(patientId: '   '),
          newDate: futureDate,
          newSlot: '10:00 AM',
        ),
        throwsA(isA<AppointmentPayloadConflictException>().having(
          (e) => e.field,
          'field',
          equals('patientId'),
        )),
      );

      // Empty newSlot
      expect(
        () => service.doctorReschedule(
          appt: makeAppt(),
          newDate: futureDate,
          newSlot: '   ',
        ),
        throwsA(isA<AppointmentPayloadConflictException>().having(
          (e) => e.field,
          'field',
          equals('newSlot'),
        )),
      );
    });

    test(
        '30. DoctorService.doctorReschedule fails closed when unauthenticated',
        () async {
      final service = DoctorService();
      final futureDate = DateTime(2026, 11, 20);
      final appt = AppointmentModel(
        id: 'appt_auth_test',
        patientId: 'patient_1',
        patientName: 'Patient 1',
        doctorId: 'doctor_1',
        doctorName: 'Dr. One',
        doctorSpecialty: 'Oncology',
        appointmentDate: futureDate,
        timeSlot: '09:30 AM',
        status: AppointmentStatus.scheduled,
        createdAt: DateTime.now(),
      );

      expect(
        () => service.doctorReschedule(
          appt: appt,
          newDate: futureDate,
          newSlot: '10:00 AM',
        ),
        throwsA(isA<AppointmentUnauthorizedException>().having(
          (e) => e.appointmentId,
          'appointmentId',
          equals('appt_auth_test'),
        )),
      );
    });

    test(
        '31. DoctorService.doctorReschedule rejects authenticated doctor UID mismatch before database interaction',
        () async {
      final fakeAuth = _FakeAuth(_FakeUser('doctor_A'));
      final service = DoctorService(auth: fakeAuth);
      final futureDate = DateTime(2026, 11, 20);
      final appt = AppointmentModel(
        id: 'appt_mismatch_test',
        patientId: 'patient_1',
        patientName: 'Patient 1',
        doctorId: 'doctor_B',
        doctorName: 'Dr. One',
        doctorSpecialty: 'Oncology',
        appointmentDate: futureDate,
        timeSlot: '09:30 AM',
        status: AppointmentStatus.scheduled,
        createdAt: DateTime.now(),
      );

      expect(
        () => service.doctorReschedule(
          appt: appt,
          newDate: futureDate,
          newSlot: '10:00 AM',
        ),
        throwsA(isA<AppointmentUnauthorizedException>()
            .having(
              (e) => e.appointmentId,
              'appointmentId',
              equals('appt_mismatch_test'),
            )
            .having(
              (e) => e.message,
              'message',
              contains('Authenticated doctor UID does not match the appointment doctor ID.'),
            )),
      );
    });

    test(
        '32. DoctorService.doctorReschedule rejects past dates and accepts today and tomorrow before database interaction',
        () async {
      final now = DateTime.now();
      final yesterday =
          DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1));
      final today = DateTime(now.year, now.month, now.day);
      final tomorrow = today.add(const Duration(days: 1));

      final appt = AppointmentModel(
        id: 'appt_date_test',
        patientId: 'patient_1',
        patientName: 'Patient 1',
        doctorId: 'doctor_1',
        doctorName: 'Dr. One',
        doctorSpecialty: 'Oncology',
        appointmentDate: today,
        timeSlot: '09:30 AM',
        status: AppointmentStatus.scheduled,
        createdAt: DateTime.now(),
      );

      final service = DoctorService();

      // Yesterday is rejected before DB interaction
      expect(
        () => service.doctorReschedule(
          appt: appt,
          newDate: yesterday,
          newSlot: '11:00 AM',
        ),
        throwsA(isA<AppointmentPayloadConflictException>()
            .having((e) => e.appointmentId, 'appointmentId', equals('appt_date_test'))
            .having((e) => e.field, 'field', equals('newDate'))
            .having((e) => e.expectedValue, 'expectedValue', equals('date on or after today'))
            .having((e) => e.message, 'message', contains('Appointment date cannot be in the past.'))),
      );

      // Today and tomorrow pass the date validation guard
      expect(
        () => AppointmentService.validateAppointmentDate(today),
        returnsNormally,
      );
      expect(
        () => AppointmentService.validateAppointmentDate(tomorrow),
        returnsNormally,
      );
    });
  });
}
