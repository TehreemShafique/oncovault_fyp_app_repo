// test/appointment_approval_ui_resilience_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
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
  group('Appointment Approval UI Resilience & Network Failure Tests', () {
    final fakeAuth = _FakeAuth(_FakeUser('doc_test_1'));

    final sampleAppt = AppointmentModel(
      id: 'appt_test_001',
      doctorId: 'doc_test_1',
      doctorName: 'Dr. Test Doctor',
      patientId: 'patient_test_1',
      patientName: 'Jane Doe',
      doctorSpecialty: 'Hematology/Oncology',
      appointmentDate: DateTime(2026, 10, 20),
      timeSlot: '10:00 AM',
      status: AppointmentStatus.scheduled,
      createdAt: DateTime(2026, 10, 15),
    );

    test('1. DoctorService maps FirebaseFunctionsException "internal" (CORS preflight failure) to AppointmentNetworkException', () async {
      final service = DoctorService(
        auth: fakeAuth,
        approveCallable: ({required String appointmentId}) async {
          throw FirebaseFunctionsException(
            message: 'internal',
            code: 'internal',
          );
        },
      );

      try {
        await service.approveAppointment(sampleAppt);
        fail('Should have thrown AppointmentNetworkException');
      } catch (e) {
        expect(e, isA<AppointmentNetworkException>());
        final netEx = e as AppointmentNetworkException;
        expect(netEx.appointmentId, equals('appt_test_001'));
        expect(netEx.originalCode, equals('internal'));
        expect(netEx.message, contains('unreachable'));
        expect(netEx.message, contains('Cloud Function may not be deployed'));
        // Verify backward-compatibility as an AppointmentStateConflictException
        expect(e, isA<AppointmentStateConflictException>());
      }
    });

    test('2. DoctorService maps FirebaseFunctionsException "unavailable" to AppointmentNetworkException', () async {
      final service = DoctorService(
        auth: fakeAuth,
        approveCallable: ({required String appointmentId}) async {
          throw FirebaseFunctionsException(
            message: 'The service is temporarily unavailable.',
            code: 'unavailable',
          );
        },
      );

      expect(
        () => service.approveAppointment(sampleAppt),
        throwsA(isA<AppointmentNetworkException>().having(
          (e) => e.originalCode,
          'originalCode',
          equals('unavailable'),
        )),
      );
    });

    test('3. DoctorService rethrows AppointmentException without wrapping', () async {
      final service = DoctorService(
        auth: fakeAuth,
        approveCallable: ({required String appointmentId}) async {
          throw const SlotAlreadyBookedException(
            'Slot is occupied.',
            slotKey: '2026-10-20_10:00 AM',
          );
        },
      );

      expect(
        () => service.approveAppointment(sampleAppt),
        throwsA(isA<SlotAlreadyBookedException>()),
      );
    });

    test('4. DoctorService wraps arbitrary transport errors into AppointmentNetworkException', () async {
      final service = DoctorService(
        auth: fakeAuth,
        approveCallable: ({required String appointmentId}) async {
          throw Exception('Connection closed by peer');
        },
      );

      try {
        await service.approveAppointment(sampleAppt);
        fail('Should have thrown AppointmentNetworkException');
      } catch (e) {
        expect(e, isA<AppointmentNetworkException>());
        expect(e.toString(), contains('Server approval failed'));
        expect(e.toString(), contains('Connection closed by peer'));
      }
    });

    test('5. AppointmentNetworkException provides clear actionable message without infinite loop', () {
      const ex = AppointmentNetworkException(
        'Server approval endpoint unreachable. The Cloud Function may not be deployed or accessible from this origin.',
        appointmentId: 'appt_123',
        originalCode: 'internal',
      );

      expect(ex.message, contains('unreachable'));
      expect(ex.appointmentId, equals('appt_123'));
      expect(ex.originalCode, equals('internal'));
      expect(ex.currentStatus, equals('scheduled'));
      expect(ex.requiredStatus, equals('scheduled'));
    });
  });
}
