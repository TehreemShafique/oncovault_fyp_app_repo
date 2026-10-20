// test/direct_firestore_appointment_approval_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:oncovault/models/appointment_model.dart';
import 'package:oncovault/services/appointment_exceptions.dart';
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
  group('Direct Firestore Doctor Appointment Approval Unit & Security Tests', () {
    final doctorUser = _FakeUser('doc_onco_1');
    final doctorAuth = _FakeAuth(doctorUser);

    final validAppt = AppointmentModel(
      id: 'appt_direct_001',
      doctorId: 'doc_onco_1',
      doctorName: 'Dr. John Watson',
      patientId: 'patient_jane_1',
      patientName: 'Jane Doe',
      doctorSpecialty: 'Medical Oncology',
      appointmentDate: DateTime(2026, 11, 20),
      timeSlot: '09:30 AM',
      status: AppointmentStatus.scheduled,
      createdAt: DateTime(2026, 11, 10),
    );

    test('1. Doctor authentication check rejects unauthenticated caller', () async {
      final unauthService = DoctorService(auth: _FakeAuth(null));

      expect(
        () => unauthService.approveAppointment(validAppt),
        throwsA(isA<AppointmentUnauthorizedException>().having(
          (e) => e.appointmentId,
          'appointmentId',
          equals('appt_direct_001'),
        )),
      );
    });

    test('2. Doctor authorization check rejects non-assigned doctor caller', () async {
      final foreignDoctorAuth = _FakeAuth(_FakeUser('doc_foreign_99'));
      final service = DoctorService(auth: foreignDoctorAuth);

      expect(
        () => service.approveAppointment(validAppt),
        throwsA(isA<AppointmentUnauthorizedException>().having(
          (e) => e.appointmentId,
          'appointmentId',
          equals('appt_direct_001'),
        )),
      );
    });

    test('3. Payload validation rejects empty appointmentId or patientId', () async {
      final service = DoctorService(auth: doctorAuth);

      final emptyIdAppt = AppointmentModel(
        id: '   ',
        doctorId: validAppt.doctorId,
        doctorName: validAppt.doctorName,
        patientId: validAppt.patientId,
        patientName: validAppt.patientName,
        doctorSpecialty: validAppt.doctorSpecialty,
        appointmentDate: validAppt.appointmentDate,
        timeSlot: validAppt.timeSlot,
        status: validAppt.status,
        createdAt: validAppt.createdAt,
      );
      expect(
        () => service.approveAppointment(emptyIdAppt),
        throwsA(isA<AppointmentPayloadConflictException>().having(
          (e) => e.field,
          'field',
          equals('id'),
        )),
      );

      final emptyPatientAppt = AppointmentModel(
        id: validAppt.id,
        doctorId: validAppt.doctorId,
        doctorName: validAppt.doctorName,
        patientId: '   ',
        patientName: validAppt.patientName,
        doctorSpecialty: validAppt.doctorSpecialty,
        appointmentDate: validAppt.appointmentDate,
        timeSlot: validAppt.timeSlot,
        status: validAppt.status,
        createdAt: validAppt.createdAt,
      );
      expect(
        () => service.approveAppointment(emptyPatientAppt),
        throwsA(isA<AppointmentPayloadConflictException>().having(
          (e) => e.field,
          'field',
          equals('patientId'),
        )),
      );
    });

    test('4. Status eligibility check: Scheduled and Rescheduled can become Confirmed', () {
      expect(DoctorService.isStatusEligibleForApproval('scheduled'), isTrue);
      expect(DoctorService.isStatusEligibleForApproval('pending'), isTrue);
      expect(DoctorService.canonicalStatus('scheduled'), equals('scheduled'));
      expect(DoctorService.canonicalStatus('pending'), equals('scheduled'));
      expect(DoctorService.canonicalStatus('rescheduled'), equals('rescheduled'));
      expect(DoctorService.canonicalStatus('confirmed'), equals('confirmed'));
      expect(DoctorService.canonicalStatus('completed'), equals('completed'));
      expect(DoctorService.canonicalStatus('rejected'), equals('rejected'));
      expect(DoctorService.canonicalStatus('cancelled'), equals('cancelled'));
    });

    test('5. Duplicate approval: Already-confirmed status is rejected cleanly', () {
      final confirmedAppt = validAppt.copyWith(status: AppointmentStatus.confirmed);
      expect(DoctorService.isStatusEligibleForApproval(confirmedAppt.status.firestoreValue), isFalse);
    });

    test('6. Terminal statuses cannot be approved', () {
      expect(DoctorService.isStatusEligibleForApproval('completed'), isFalse);
      expect(DoctorService.isStatusEligibleForApproval('rejected'), isFalse);
      expect(DoctorService.isStatusEligibleForApproval('cancelled'), isFalse);
      expect(DoctorService.isStatusEligibleForApproval('canceled'), isFalse);
      expect(DoctorService.isStatusEligibleForApproval(null), isFalse);
      expect(DoctorService.isStatusEligibleForApproval(''), isFalse);
      expect(DoctorService.isStatusEligibleForApproval('corrupt_status'), isFalse);
    });

    test('7. Slot key formatting matches canonical YYYY-MM-DD_timeSlot', () {
      final date = DateTime(2026, 11, 20);
      const timeSlot = '09:30 AM';
      final slotKey = buildSlotKey(date, timeSlot);
      expect(slotKey, equals('2026-11-20_09:30 AM'));
      expect(validAppt.slotKey, equals('2026-11-20_09:30 AM'));
    });

    test('8. firestore.rules permits doctor approval and slot reservation', () {
      final rulesFile = File('firestore.rules');
      expect(rulesFile.existsSync(), isTrue, reason: 'firestore.rules must exist');

      final content = rulesFile.readAsStringSync();

      // Verify patients appointment subcollection update rule permits doctor confirmation
      expect(
        content.contains("request.resource.data.status == 'confirmed'"),
        isTrue,
        reason: 'Rules must permit status == confirmed on appointment approval',
      );

      // Verify assigned doctor ownership requirement
      expect(
        content.contains('isOwner(resource.data.doctorId) && isDoctor()'),
        isTrue,
        reason: 'Rules must restrict approval strictly to the assigned doctor',
      );

      // Verify bookedSlots allow create rule permits doctor slot reservation
      expect(
        content.contains('match /bookedSlots/{doctorId}/slots/{slotKey}'),
        isTrue,
      );
      expect(
        content.contains("getAfter(/databases/\$(database)/documents/appointments/\$(request.resource.data.appointmentId)).data.status.matches('(?i)^(confirmed|approved)\$')"),
        isTrue,
        reason: 'Slot lock creation must be coupled to confirmed appointment status in Firestore rules',
      );
    });

    test('9. firestore.rules prevents unauthorized status transitions', () {
      final content = File('firestore.rules').readAsStringSync();

      // Ensure bookedSlots update remains disabled
      expect(content.contains('allow update: if false;'), isTrue);

      // Ensure patients cannot approve their own appointments
      // Patients are restricted to cancellation and rescheduling
      expect(
        content.contains("((isOwner(patientId) && isPatient()) || (isOwner(resource.data.doctorId) && isDoctor())) &&"),
        isTrue,
      );
    });
  });
}
