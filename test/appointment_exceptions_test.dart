// test/appointment_exceptions_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:oncovault/models/appointment_model.dart';
import 'package:oncovault/services/appointment_exceptions.dart';
import 'package:oncovault/services/doctor_service.dart';

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
  });
}
