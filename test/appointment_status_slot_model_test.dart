// test/appointment_status_slot_model_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:oncovault/models/appointment_model.dart';

void main() {
  group('AppointmentStatus & Slot Model (Step 2A.1) Tests', () {
    test('1. Canonical status serialization returns exact expected firestoreValue', () {
      expect(AppointmentStatus.scheduled.firestoreValue, equals('scheduled'));
      expect(AppointmentStatus.confirmed.firestoreValue, equals('confirmed'));
      expect(AppointmentStatus.rescheduled.firestoreValue, equals('rescheduled'));
      expect(AppointmentStatus.cancelled.firestoreValue, equals('cancelled'));
      expect(AppointmentStatus.completed.firestoreValue, equals('completed'));
      expect(AppointmentStatus.rejected.firestoreValue, equals('rejected'));
    });

    test('2. Backward-compatible status deserialization handles legacy, canonical, and fallback inputs', () {
      // Legacy Firestore status values
      expect(statusFromString('pending'), equals(AppointmentStatus.scheduled));
      expect(statusFromString('approved'), equals(AppointmentStatus.confirmed));

      // Canonical Phase 2 values
      expect(statusFromString('scheduled'), equals(AppointmentStatus.scheduled));
      expect(statusFromString('confirmed'), equals(AppointmentStatus.confirmed));
      expect(statusFromString('rescheduled'), equals(AppointmentStatus.rescheduled));
      expect(statusFromString('cancelled'), equals(AppointmentStatus.cancelled));
      expect(statusFromString('canceled'), equals(AppointmentStatus.cancelled));
      expect(statusFromString('completed'), equals(AppointmentStatus.completed));
      expect(statusFromString('rejected'), equals(AppointmentStatus.rejected));

      // Null, empty, and unknown values safely fallback to scheduled without throwing
      expect(statusFromString(null), equals(AppointmentStatus.scheduled));
      expect(statusFromString(''), equals(AppointmentStatus.scheduled));
      expect(statusFromString('unknown_status'), equals(AppointmentStatus.scheduled));
      expect(statusFromString('  APPROVED  '), equals(AppointmentStatus.confirmed));
    });

    test('3. Display labels return human-readable Title Case strings', () {
      expect(AppointmentStatus.scheduled.label, equals('Scheduled'));
      expect(AppointmentStatus.confirmed.label, equals('Confirmed'));
      expect(AppointmentStatus.rescheduled.label, equals('Rescheduled'));
      expect(AppointmentStatus.cancelled.label, equals('Cancelled'));
      expect(AppointmentStatus.completed.label, equals('Completed'));
      expect(AppointmentStatus.rejected.label, equals('Rejected'));
    });

    test('4. Canonical buildSlotKey generates YYYY-MM-DD_timeSlot with zero-padding and trimming', () {
      // Zero-padded month and day
      expect(
        buildSlotKey(DateTime(2026, 3, 5), '09:30 AM'),
        equals('2026-03-05_09:30 AM'),
      );

      // Leap year
      expect(
        buildSlotKey(DateTime(2028, 2, 29), '03:00 PM'),
        equals('2028-02-29_03:00 PM'),
      );

      // Surrounding whitespace trimming on timeSlot
      expect(
        buildSlotKey(DateTime(2026, 10, 15), ' 09:30 AM '),
        equals('2026-10-15_09:30 AM'),
      );
    });

    test('5. AppointmentModel slot-key behavior computes on demand or uses explicit persisted value', () {
      final apptDate = DateTime(2026, 10, 15);
      const slot = '09:30 AM';

      // Without explicit slot key -> computed from appointmentDate + timeSlot
      final dynamicAppt = AppointmentModel(
        id: 'appt_dyn_1',
        patientId: 'pt_1',
        patientName: 'Jane Doe',
        doctorId: 'dr_1',
        doctorName: 'Dr. Thorne',
        doctorSpecialty: 'Oncology',
        appointmentDate: apptDate,
        timeSlot: slot,
        status: AppointmentStatus.scheduled,
        createdAt: DateTime.now(),
      );
      expect(dynamicAppt.explicitSlotKey, isNull);
      expect(dynamicAppt.slotKey, equals('2026-10-15_09:30 AM'));

      // With explicit slot key -> persisted value returned directly
      final explicitAppt = AppointmentModel(
        id: 'appt_exp_1',
        patientId: 'pt_1',
        patientName: 'Jane Doe',
        doctorId: 'dr_1',
        doctorName: 'Dr. Thorne',
        doctorSpecialty: 'Oncology',
        appointmentDate: apptDate,
        timeSlot: slot,
        status: AppointmentStatus.confirmed,
        createdAt: DateTime.now(),
        explicitSlotKey: '2026-10-15_09:30 AM_PERSISTED',
      );
      expect(explicitAppt.explicitSlotKey, equals('2026-10-15_09:30 AM_PERSISTED'));
      expect(explicitAppt.slotKey, equals('2026-10-15_09:30 AM_PERSISTED'));
    });

    test('6. Legacy Firestore map without slotKey and with approved/pending deserializes properly', () {
      final now = DateTime.now();
      final apptDate = DateTime(2026, 6, 20);

      // Legacy map with 'approved' and no slotKey
      final legacyApprovedMap = <String, dynamic>{
        'id': 'legacy_appt_1',
        'patientId': 'pt_leg_1',
        'patientName': 'Legacy Patient',
        'doctorId': 'dr_leg_1',
        'doctorName': 'Dr. Vance',
        'doctorSpecialty': 'Radiation Oncology',
        'appointmentDate': Timestamp.fromDate(apptDate),
        'timeSlot': '11:00 AM',
        'durationMinutes': 45,
        'status': 'approved',
        'notes': 'Follow up scan',
        'createdAt': Timestamp.fromDate(now),
        // slotKey intentionally omitted
      };

      final apptApproved = AppointmentModel.fromMap(legacyApprovedMap);
      expect(apptApproved.status, equals(AppointmentStatus.confirmed));
      expect(apptApproved.explicitSlotKey, isNull);
      expect(apptApproved.slotKey, equals('2026-06-20_11:00 AM'));

      // Legacy map with 'pending' and no slotKey
      final legacyPendingMap = <String, dynamic>{
        'id': 'legacy_appt_2',
        'patientId': 'pt_leg_2',
        'patientName': 'Pending Patient',
        'doctorId': 'dr_leg_1',
        'doctorName': 'Dr. Vance',
        'doctorSpecialty': 'Radiation Oncology',
        'appointmentDate': Timestamp.fromDate(apptDate),
        'timeSlot': '01:30 PM',
        'durationMinutes': 45,
        'status': 'pending',
        'createdAt': Timestamp.fromDate(now),
      };

      final apptPending = AppointmentModel.fromMap(legacyPendingMap);
      expect(apptPending.status, equals(AppointmentStatus.scheduled));
      expect(apptPending.slotKey, equals('2026-06-20_01:30 PM'));
    });

    test('7. New Firestore map with canonical status and persisted slotKey deserializes properly', () {
      final now = DateTime.now();
      final apptDate = DateTime(2026, 10, 15);

      final newDocMap = <String, dynamic>{
        'id': 'new_appt_1',
        'patientId': 'pt_new_1',
        'patientName': 'New Patient',
        'doctorId': 'dr_1',
        'doctorName': 'Dr. Thorne',
        'doctorSpecialty': 'Medical Oncology',
        'appointmentDate': Timestamp.fromDate(apptDate),
        'timeSlot': '09:30 AM',
        'slotKey': '2026-10-15_09:30 AM',
        'durationMinutes': 45,
        'status': 'confirmed',
        'createdAt': Timestamp.fromDate(now),
      };

      final appt = AppointmentModel.fromMap(newDocMap);
      expect(appt.status, equals(AppointmentStatus.confirmed));
      expect(appt.explicitSlotKey, equals('2026-10-15_09:30 AM'));
      expect(appt.slotKey, equals('2026-10-15_09:30 AM'));
    });

    test('8. Serialization round-trip preserves canonical status, slotKey, and all core fields', () {
      final apptDate = DateTime(2026, 10, 15);
      final createdAt = DateTime(2026, 10, 1, 12, 0, 0);

      final original = AppointmentModel(
        id: 'appt_rt_1',
        patientId: 'pt_rt_1',
        patientName: 'Roundtrip Patient',
        doctorId: 'dr_rt_1',
        doctorName: 'Dr. Jenkins',
        doctorSpecialty: 'Surgical Oncology',
        appointmentDate: apptDate,
        timeSlot: '04:30 PM',
        durationMinutes: 45,
        status: AppointmentStatus.confirmed,
        notes: 'Pre-surgery consultation',
        doctorNotes: 'Cleared for lab work',
        createdAt: createdAt,
        explicitSlotKey: '2026-10-15_04:30 PM',
      );

      final map = original.toMap();
      expect(map['status'], equals('confirmed'));
      expect(map['slotKey'], equals('2026-10-15_04:30 PM'));

      final restored = AppointmentModel.fromMap(map);
      expect(restored.id, equals(original.id));
      expect(restored.patientId, equals(original.patientId));
      expect(restored.patientName, equals(original.patientName));
      expect(restored.doctorId, equals(original.doctorId));
      expect(restored.doctorName, equals(original.doctorName));
      expect(restored.doctorSpecialty, equals(original.doctorSpecialty));
      expect(restored.appointmentDate, equals(original.appointmentDate));
      expect(restored.timeSlot, equals(original.timeSlot));
      expect(restored.slotKey, equals(original.slotKey));
      expect(restored.status, equals(AppointmentStatus.confirmed));
      expect(restored.notes, equals(original.notes));
      expect(restored.doctorNotes, equals(original.doctorNotes));
    });
  });
}
