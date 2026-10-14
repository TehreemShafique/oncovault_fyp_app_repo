// lib/services/appointment_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/appointment_model.dart';
import '../models/medical_record_model.dart';
import 'appointment_exceptions.dart';

class AppointmentService {
  final FirebaseFirestore? _customDb;
  final FirebaseAuth? _customAuth;

  AppointmentService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _customDb = firestore,
        _customAuth = auth;

  FirebaseFirestore get _db => _customDb ?? FirebaseFirestore.instance;
  FirebaseAuth? get _safeAuth {
    if (_customAuth != null) return _customAuth;
    try {
      return FirebaseAuth.instance;
    } catch (_) {
      return null;
    }
  }

  // ── Collections ───────────────────────────────────────────────
  // /appointments/{id}                        — all appointments (doctor module reads this)
  // /patients/{uid}/appointments/{id}         — subcollection for fast patient queries
  // /notifications/{patientId}/items/{id}
  // /bookedSlots/{doctorId}/slots/{slotKey}   — approved/booked slots per doctor
  //   slotKey format: "yyyy-MM-dd_HH:mm AM/PM"  e.g. "2025-06-15_09:30 AM"

  CollectionReference get _appointments => _db.collection('appointments');
  CollectionReference _patientAppts(String uid) =>
      _db.collection('patients').doc(uid).collection('appointments');
  CollectionReference _notifications(String uid) =>
      _db.collection('notifications').doc(uid).collection('items');

  // bookedSlots/{doctorId}/slots/{slotKey}
  CollectionReference _bookedSlots(String doctorId) =>
      _db.collection('bookedSlots').doc(doctorId).collection('slots');

  /// Pure eligibility check for appointment cancellation:
  /// Accepts 'scheduled', 'pending', 'confirmed', 'approved', and 'rescheduled' (case-insensitively, trimmed).
  /// Rejects null, empty, whitespace-only, unrecognized, and terminal statuses ('cancelled', 'canceled', 'completed', 'rejected').
  static bool isStatusEligibleForCancellation(String? rawStatus) {
    if (rawStatus == null) return false;
    final trimmed = rawStatus.trim().toLowerCase();
    if (trimmed.isEmpty) return false;
    return trimmed == 'scheduled' ||
        trimmed == 'pending' ||
        trimmed == 'confirmed' ||
        trimmed == 'approved' ||
        trimmed == 'rescheduled';
  }

  /// Pure eligibility check for appointment rescheduling:
  /// Follows the same approved state eligibility rules as cancellation.
  static bool isStatusEligibleForRescheduling(String? rawStatus) =>
      isStatusEligibleForCancellation(rawStatus);

  /// Validates that [date] is on or after today's calendar date in local time.
  ///
  /// Compares year, month, and day in local time so that today remains valid
  /// regardless of the current hour. Throws [AppointmentPayloadConflictException]
  /// if [date] is before today.
  static void validateAppointmentDate(
    DateTime date, {
    String appointmentId = '',
    DateTime? referenceNow,
  }) {
    final now = referenceNow ?? DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);
    final targetMidnight = DateTime(date.year, date.month, date.day);

    if (targetMidnight.isBefore(todayMidnight)) {
      throw AppointmentPayloadConflictException(
        'Appointment date cannot be in the past.',
        appointmentId: appointmentId,
        field: 'newDate',
        expectedValue: 'date on or after today',
        actualValue: date.toIso8601String(),
      );
    }
  }

  // ── Check if a slot is booked ─────────────────────────────────
  /// Returns true when the slot is already taken (approved appointment exists).
  Future<bool> isSlotBooked(
      String doctorId, DateTime date, String timeSlot) async {
    final key = buildSlotKey(date, timeSlot);
    final doc = await _bookedSlots(doctorId).doc(key).get();
    return doc.exists;
  }

  /// Stream of all booked slot keys for a doctor so the UI can react in real-time.
  Stream<Set<String>> watchBookedSlots(String doctorId) =>
      _bookedSlots(doctorId).snapshots().map(
            (s) => s.docs.map((d) => d.id).toSet(),
          );

  // ── Book Appointment ──────────────────────────────────────────
  Future<AppointmentModel> bookAppointment({
    required String patientId,
    required String patientName,
    required String doctorId,
    required String doctorName,
    required String doctorSpecialty,
    required DateTime appointmentDate,
    required String timeSlot,
    String notes = '',
    int durationMinutes = 45,
  }) async {
    final ref = _appointments.doc();
    final appt = AppointmentModel(
      id: ref.id,
      patientId: patientId,
      patientName: patientName,
      doctorId: doctorId,
      doctorName: doctorName,
      doctorSpecialty: doctorSpecialty,
      appointmentDate: appointmentDate,
      timeSlot: timeSlot,
      durationMinutes: durationMinutes,
      status: AppointmentStatus.scheduled,
      notes: notes,
      createdAt: DateTime.now(),
    );

    final batch = _db.batch();
    // Write to global /appointments (doctor module will listen here)
    batch.set(ref, appt.toMap());
    // Write to patient's subcollection for fast queries
    batch.set(_patientAppts(patientId).doc(ref.id), appt.toMap());
    await batch.commit();

    // Create notification
    await _createNotification(
      patientId: patientId,
      title: 'Appointment Requested',
      body:
          'Your appointment with $doctorName on ${_fmtDate(appointmentDate)} at $timeSlot is pending approval.',
      type: 'appointment',
      referenceId: ref.id,
    );

    return appt;
  }

  // ── Cancel Appointment ────────────────────────────────────────
  Future<void> cancelAppointment(String appointmentId, String patientId) async {
    final trimmedApptId = appointmentId.trim();
    final trimmedPatientId = patientId.trim();

    if (trimmedApptId.isEmpty || trimmedPatientId.isEmpty) {
      throw AppointmentPayloadConflictException(
        'Appointment cancellation requires non-empty appointmentId and patientId.',
        appointmentId: trimmedApptId,
        field: trimmedApptId.isEmpty ? 'appointmentId' : 'patientId',
        expectedValue: 'non-empty string',
        actualValue: trimmedApptId.isEmpty ? appointmentId : patientId,
      );
    }

    // 1. Fail-closed authentication check
    final auth = _safeAuth;
    final currentUserId = auth?.currentUser?.uid;
    if (auth == null || currentUserId == null || currentUserId.trim().isEmpty) {
      throw AppointmentUnauthorizedException(
        'Patient cancellation requires an authenticated session.',
        appointmentId: trimmedApptId,
      );
    }

    if (currentUserId != trimmedPatientId) {
      throw AppointmentUnauthorizedException(
        'Authenticated user UID does not match the patient ID.',
        appointmentId: trimmedApptId,
      );
    }

    final apptRef = _appointments.doc(trimmedApptId);
    final patientApptRef = _patientAppts(trimmedPatientId).doc(trimmedApptId);

    await _db.runTransaction((tx) async {
      // ── PHASE 1: ALL READS MUST PRECEDE ALL WRITES ──
      // 1. Read authoritative global appointment document
      final apptSnap = await tx.get(apptRef);
      if (!apptSnap.exists) {
        throw AppointmentNotFoundException(
          'Appointment document $trimmedApptId not found in Firestore.',
          appointmentId: trimmedApptId,
        );
      }

      final apptData = apptSnap.data() as Map<String, dynamic>;
      final rawStatus = apptData['status']?.toString();

      if (rawStatus == null || rawStatus.trim().isEmpty) {
        throw AppointmentStateConflictException(
          'Appointment document $trimmedApptId status is missing or empty, cannot be cancelled.',
          appointmentId: trimmedApptId,
          currentStatus: rawStatus?.trim() ?? '',
          requiredStatus: 'eligible (scheduled, confirmed, or rescheduled)',
        );
      }

      if (!isStatusEligibleForCancellation(rawStatus)) {
        final trimmed = rawStatus.trim();
        const knownTerminalStatuses = {
          'cancelled',
          'canceled',
          'completed',
          'rejected',
        };
        final description =
            knownTerminalStatuses.contains(trimmed.toLowerCase())
                ? trimmed
                : 'unrecognized status "$trimmed"';
        throw AppointmentStateConflictException(
          'Appointment $trimmedApptId is in $description status, cannot be cancelled.',
          appointmentId: trimmedApptId,
          currentStatus: trimmed,
          requiredStatus: 'eligible (scheduled, confirmed, or rescheduled)',
        );
      }

      final serverPatientId = apptData['patientId']?.toString() ?? '';
      if (serverPatientId.isEmpty || serverPatientId != currentUserId) {
        throw AppointmentUnauthorizedException(
          'Server record patientId ($serverPatientId) does not match authenticated user ($currentUserId).',
          appointmentId: trimmedApptId,
        );
      }

      final serverDoctorId = apptData['doctorId']?.toString().trim() ?? '';
      if (serverDoctorId.isEmpty) {
        throw AppointmentPayloadConflictException(
          'Authoritative appointment doctorId is missing or empty in document $trimmedApptId.',
          appointmentId: trimmedApptId,
          field: 'doctorId',
          expectedValue: 'non-empty doctorId',
          actualValue: '',
        );
      }

      final rawServerDate = apptData['appointmentDate'];
      if (rawServerDate == null || rawServerDate is! Timestamp) {
        throw AppointmentPayloadConflictException(
          'Authoritative appointment date is missing or invalid in document $trimmedApptId.',
          appointmentId: trimmedApptId,
          field: 'appointmentDate',
          expectedValue: 'valid Timestamp',
          actualValue: rawServerDate.toString(),
        );
      }
      final serverAppointmentDate = rawServerDate.toDate();
      final serverDateOnly = DateTime(serverAppointmentDate.year,
          serverAppointmentDate.month, serverAppointmentDate.day);

      final serverTimeSlot = apptData['timeSlot']?.toString().trim() ?? '';
      if (serverTimeSlot.isEmpty) {
        throw AppointmentPayloadConflictException(
          'Authoritative appointment timeSlot is missing or empty in document $trimmedApptId.',
          appointmentId: trimmedApptId,
          field: 'timeSlot',
          expectedValue: 'non-empty timeSlot',
          actualValue: '',
        );
      }

      // 2. Read patient mirror document
      final patientApptSnap = await tx.get(patientApptRef);
      if (!patientApptSnap.exists) {
        throw AppointmentMirrorInconsistentException(
          'Patient appointment mirror does not exist at /patients/$trimmedPatientId/appointments/$trimmedApptId.',
          appointmentId: trimmedApptId,
          patientId: trimmedPatientId,
          reason: 'Mirror document does not exist',
        );
      }

      final patientData = patientApptSnap.data() as Map<String, dynamic>;
      final mirrorDoctorId = patientData['doctorId']?.toString().trim() ?? '';
      final mirrorPatientId = patientData['patientId']?.toString().trim() ?? '';
      final mirrorRawStatus = patientData['status']?.toString();

      if (mirrorDoctorId != serverDoctorId ||
          mirrorPatientId != serverPatientId) {
        throw AppointmentMirrorInconsistentException(
          'Patient appointment mirror contains mismatched identity fields.',
          appointmentId: trimmedApptId,
          patientId: serverPatientId,
          reason: 'Mirror identity fields mismatch global record',
        );
      }

      if (!isStatusEligibleForCancellation(mirrorRawStatus)) {
        throw AppointmentMirrorInconsistentException(
          'Patient appointment mirror status ($mirrorRawStatus) is not eligible for cancellation.',
          appointmentId: trimmedApptId,
          patientId: serverPatientId,
          reason: 'Mirror status is not eligible for cancellation',
        );
      }

      final rawMirrorDate = patientData['appointmentDate'];
      if (rawMirrorDate == null || rawMirrorDate is! Timestamp) {
        throw AppointmentMirrorInconsistentException(
          'Patient appointment mirror missing or invalid appointmentDate.',
          appointmentId: trimmedApptId,
          patientId: serverPatientId,
          reason: 'Mirror appointmentDate is missing or invalid',
        );
      }
      final mirrorDateOnly = DateTime(rawMirrorDate.toDate().year,
          rawMirrorDate.toDate().month, rawMirrorDate.toDate().day);
      if (mirrorDateOnly != serverDateOnly) {
        throw AppointmentMirrorInconsistentException(
          'Patient appointment mirror date conflicts with authoritative date.',
          appointmentId: trimmedApptId,
          patientId: serverPatientId,
          reason: 'Mirror appointment date mismatch',
        );
      }

      final mirrorTimeSlot = patientData['timeSlot']?.toString().trim() ?? '';
      if (mirrorTimeSlot != serverTimeSlot) {
        throw AppointmentMirrorInconsistentException(
          'Patient appointment mirror timeSlot ($mirrorTimeSlot) conflicts with authoritative timeSlot ($serverTimeSlot).',
          appointmentId: trimmedApptId,
          patientId: serverPatientId,
          reason: 'Mirror timeSlot mismatch',
        );
      }

      // 3. Derive canonical slotKey and check slot lock if appointment was confirmed/approved
      final authoritativeSlotKey =
          buildSlotKey(serverAppointmentDate, serverTimeSlot);
      final slotRef = _bookedSlots(serverDoctorId).doc(authoritativeSlotKey);

      final normalizedRawStatus = rawStatus.trim().toLowerCase();
      final isConfirmed = normalizedRawStatus == 'confirmed' ||
          normalizedRawStatus == 'approved';

      DocumentSnapshot? slotSnap;
      bool shouldDeleteSlotLock = false;

      if (isConfirmed) {
        slotSnap = await tx.get(slotRef);

        if (!slotSnap.exists) {
          throw SlotLockCorruptException(
            'Confirmed appointment $trimmedApptId is missing its expected slot lock at $authoritativeSlotKey.',
            slotKey: authoritativeSlotKey,
          );
        }

        final slotData = slotSnap.data() as Map<String, dynamic>? ?? {};
        final existingApptId =
            slotData['appointmentId']?.toString().trim() ?? '';
        final existingPatientId =
            slotData['patientId']?.toString().trim() ?? '';
        final existingTimeSlot = slotData['timeSlot']?.toString().trim() ?? '';

        if (existingApptId.isEmpty ||
            existingPatientId.isEmpty ||
            existingTimeSlot.isEmpty) {
          throw SlotLockCorruptException(
            'Slot lock $authoritativeSlotKey contains missing or empty required fields.',
            slotKey: authoritativeSlotKey,
          );
        }

        if (existingApptId != trimmedApptId) {
          throw SlotAlreadyBookedException(
            'Slot $authoritativeSlotKey belongs to appointment $existingApptId, not $trimmedApptId.',
            slotKey: authoritativeSlotKey,
            conflictingAppointmentId: existingApptId,
          );
        }

        if (existingPatientId != serverPatientId ||
            existingTimeSlot != serverTimeSlot) {
          throw SlotLockCorruptException(
            'Slot lock for appointment $trimmedApptId has inconsistent patientId or timeSlot.',
            slotKey: authoritativeSlotKey,
          );
        }

        final rawLockDate = slotData['date'];
        if (rawLockDate == null || rawLockDate is! Timestamp) {
          throw SlotLockCorruptException(
            'Slot lock for appointment $trimmedApptId is missing or has invalid date.',
            slotKey: authoritativeSlotKey,
          );
        }
        final lockDateOnly = DateTime(rawLockDate.toDate().year,
            rawLockDate.toDate().month, rawLockDate.toDate().day);
        if (lockDateOnly != serverDateOnly) {
          throw SlotLockCorruptException(
            'Slot lock for appointment $trimmedApptId date conflicts with authoritative date.',
            slotKey: authoritativeSlotKey,
          );
        }

        final rawBookedAt = slotData['bookedAt'];
        if (rawBookedAt == null || rawBookedAt is! Timestamp) {
          throw SlotLockCorruptException(
            'Slot lock for appointment $trimmedApptId is missing or has invalid bookedAt timestamp.',
            slotKey: authoritativeSlotKey,
          );
        }

        shouldDeleteSlotLock = true;
      }

      // ── PHASE 2: ATOMIC WRITES ──
      final now = Timestamp.now();
      final updateData = {
        'status': AppointmentStatus.cancelled.firestoreValue,
        'updatedAt': now,
      };

      tx.update(apptRef, updateData);
      tx.update(patientApptRef, updateData);

      if (shouldDeleteSlotLock) {
        tx.delete(slotRef);
      }
    });

    // ── Notification: executed strictly outside and after successful transaction commit ──
    await _createNotification(
      patientId: trimmedPatientId,
      title: 'Appointment Cancelled',
      body: 'Your appointment has been successfully cancelled.',
      type: 'appointment',
      referenceId: trimmedApptId,
    );
  }

  // ── Reschedule Appointment (by Patient) ───────────────────────
  // Transactional patient rescheduling: resets status to 'scheduled' awaiting
  // doctor re-approval. If previously confirmed, safely releases the verified old lock.
  Future<void> rescheduleAppointment({
    required String appointmentId,
    required String patientId,
    required DateTime newDate,
    required String newTimeSlot,
    // Optional caller parameters preserved for 100% signature backward compatibility.
    String doctorId = '',
    DateTime? oldDate,
    String oldTimeSlot = '',
    AppointmentStatus oldStatus = AppointmentStatus.scheduled,
  }) async {
    final trimmedApptId = appointmentId.trim();
    final trimmedPatientId = patientId.trim();
    final trimmedNewSlot = newTimeSlot.trim();

    if (trimmedApptId.isEmpty ||
        trimmedPatientId.isEmpty ||
        trimmedNewSlot.isEmpty) {
      final field = trimmedApptId.isEmpty
          ? 'appointmentId'
          : trimmedPatientId.isEmpty
              ? 'patientId'
              : 'newTimeSlot';
      final actual = trimmedApptId.isEmpty
          ? appointmentId
          : trimmedPatientId.isEmpty
              ? patientId
              : newTimeSlot;
      throw AppointmentPayloadConflictException(
        'Appointment rescheduling requires non-empty appointmentId, patientId, and newTimeSlot.',
        appointmentId: trimmedApptId,
        field: field,
        expectedValue: 'non-empty string',
        actualValue: actual,
      );
    }

    validateAppointmentDate(newDate, appointmentId: trimmedApptId);

    // 1. Fail-closed authentication check
    final auth = _safeAuth;
    final currentUserId = auth?.currentUser?.uid;
    if (auth == null || currentUserId == null || currentUserId.trim().isEmpty) {
      throw AppointmentUnauthorizedException(
        'Patient rescheduling requires an authenticated session.',
        appointmentId: trimmedApptId,
      );
    }

    if (currentUserId != trimmedPatientId) {
      throw AppointmentUnauthorizedException(
        'Authenticated user UID does not match the patient ID.',
        appointmentId: trimmedApptId,
      );
    }

    final apptRef = _appointments.doc(trimmedApptId);
    final patientApptRef = _patientAppts(trimmedPatientId).doc(trimmedApptId);

    await _db.runTransaction((tx) async {
      // ── PHASE 1: ALL READS MUST PRECEDE ALL WRITES ──
      // 1. Read authoritative global appointment document
      final apptSnap = await tx.get(apptRef);
      if (!apptSnap.exists) {
        throw AppointmentNotFoundException(
          'Appointment document $trimmedApptId not found in Firestore.',
          appointmentId: trimmedApptId,
        );
      }

      final apptData = apptSnap.data() as Map<String, dynamic>;
      final rawStatus = apptData['status']?.toString();

      if (rawStatus == null || rawStatus.trim().isEmpty) {
        throw AppointmentStateConflictException(
          'Appointment document $trimmedApptId status is missing or empty, cannot be rescheduled.',
          appointmentId: trimmedApptId,
          currentStatus: rawStatus?.trim() ?? '',
          requiredStatus: 'eligible (scheduled, confirmed, or rescheduled)',
        );
      }

      if (!isStatusEligibleForRescheduling(rawStatus)) {
        final trimmed = rawStatus.trim();
        const knownTerminalStatuses = {
          'cancelled',
          'canceled',
          'completed',
          'rejected',
        };
        final description =
            knownTerminalStatuses.contains(trimmed.toLowerCase())
                ? trimmed
                : 'unrecognized status "$trimmed"';
        throw AppointmentStateConflictException(
          'Appointment $trimmedApptId is in $description status, cannot be rescheduled.',
          appointmentId: trimmedApptId,
          currentStatus: trimmed,
          requiredStatus: 'eligible (scheduled, confirmed, or rescheduled)',
        );
      }

      final serverPatientId = apptData['patientId']?.toString() ?? '';
      if (serverPatientId.isEmpty || serverPatientId != currentUserId) {
        throw AppointmentUnauthorizedException(
          'Server record patientId ($serverPatientId) does not match authenticated user ($currentUserId).',
          appointmentId: trimmedApptId,
        );
      }

      final serverDoctorId = apptData['doctorId']?.toString().trim() ?? '';
      if (serverDoctorId.isEmpty) {
        throw AppointmentPayloadConflictException(
          'Authoritative appointment doctorId is missing or empty in document $trimmedApptId.',
          appointmentId: trimmedApptId,
          field: 'doctorId',
          expectedValue: 'non-empty doctorId',
          actualValue: '',
        );
      }

      final rawServerDate = apptData['appointmentDate'];
      if (rawServerDate == null || rawServerDate is! Timestamp) {
        throw AppointmentPayloadConflictException(
          'Authoritative appointment date is missing or invalid in document $trimmedApptId.',
          appointmentId: trimmedApptId,
          field: 'appointmentDate',
          expectedValue: 'valid Timestamp',
          actualValue: rawServerDate.toString(),
        );
      }
      final serverAppointmentDate = rawServerDate.toDate();
      final serverDateOnly = DateTime(serverAppointmentDate.year,
          serverAppointmentDate.month, serverAppointmentDate.day);

      final serverTimeSlot = apptData['timeSlot']?.toString().trim() ?? '';
      if (serverTimeSlot.isEmpty) {
        throw AppointmentPayloadConflictException(
          'Authoritative appointment timeSlot is missing or empty in document $trimmedApptId.',
          appointmentId: trimmedApptId,
          field: 'timeSlot',
          expectedValue: 'non-empty timeSlot',
          actualValue: '',
        );
      }

      // 2. Read patient mirror document
      final patientApptSnap = await tx.get(patientApptRef);
      if (!patientApptSnap.exists) {
        throw AppointmentMirrorInconsistentException(
          'Patient appointment mirror does not exist at /patients/$trimmedPatientId/appointments/$trimmedApptId.',
          appointmentId: trimmedApptId,
          patientId: trimmedPatientId,
          reason: 'Mirror document does not exist',
        );
      }

      final patientData = patientApptSnap.data() as Map<String, dynamic>;
      final mirrorDoctorId = patientData['doctorId']?.toString().trim() ?? '';
      final mirrorPatientId = patientData['patientId']?.toString().trim() ?? '';
      final mirrorRawStatus = patientData['status']?.toString();

      if (mirrorDoctorId != serverDoctorId ||
          mirrorPatientId != serverPatientId) {
        throw AppointmentMirrorInconsistentException(
          'Patient appointment mirror contains mismatched identity fields.',
          appointmentId: trimmedApptId,
          patientId: serverPatientId,
          reason: 'Mirror identity fields mismatch global record',
        );
      }

      if (!isStatusEligibleForRescheduling(mirrorRawStatus)) {
        throw AppointmentMirrorInconsistentException(
          'Patient appointment mirror status ($mirrorRawStatus) is not eligible for rescheduling.',
          appointmentId: trimmedApptId,
          patientId: serverPatientId,
          reason: 'Mirror status is not eligible for rescheduling',
        );
      }

      final rawMirrorDate = patientData['appointmentDate'];
      if (rawMirrorDate == null || rawMirrorDate is! Timestamp) {
        throw AppointmentMirrorInconsistentException(
          'Patient appointment mirror missing or invalid appointmentDate.',
          appointmentId: trimmedApptId,
          patientId: serverPatientId,
          reason: 'Mirror appointmentDate is missing or invalid',
        );
      }
      final mirrorDateOnly = DateTime(rawMirrorDate.toDate().year,
          rawMirrorDate.toDate().month, rawMirrorDate.toDate().day);
      if (mirrorDateOnly != serverDateOnly) {
        throw AppointmentMirrorInconsistentException(
          'Patient appointment mirror date conflicts with authoritative date.',
          appointmentId: trimmedApptId,
          patientId: serverPatientId,
          reason: 'Mirror appointment date mismatch',
        );
      }

      final mirrorTimeSlot = patientData['timeSlot']?.toString().trim() ?? '';
      if (mirrorTimeSlot != serverTimeSlot) {
        throw AppointmentMirrorInconsistentException(
          'Patient appointment mirror timeSlot ($mirrorTimeSlot) conflicts with authoritative timeSlot ($serverTimeSlot).',
          appointmentId: trimmedApptId,
          patientId: serverPatientId,
          reason: 'Mirror timeSlot mismatch',
        );
      }

      // 3. Derive canonical old slotKey and check slot lock if appointment was confirmed/approved
      final authoritativeOldSlotKey =
          buildSlotKey(serverAppointmentDate, serverTimeSlot);
      final oldSlotRef =
          _bookedSlots(serverDoctorId).doc(authoritativeOldSlotKey);

      final normalizedRawStatus = rawStatus.trim().toLowerCase();
      final isConfirmed = normalizedRawStatus == 'confirmed' ||
          normalizedRawStatus == 'approved';

      DocumentSnapshot? oldSlotSnap;
      bool shouldDeleteSlotLock = false;

      if (isConfirmed) {
        oldSlotSnap = await tx.get(oldSlotRef);

        if (!oldSlotSnap.exists) {
          throw SlotLockCorruptException(
            'Confirmed appointment $trimmedApptId is missing its expected slot lock at $authoritativeOldSlotKey.',
            slotKey: authoritativeOldSlotKey,
          );
        }

        final slotData = oldSlotSnap.data() as Map<String, dynamic>? ?? {};
        final existingApptId =
            slotData['appointmentId']?.toString().trim() ?? '';
        final existingPatientId =
            slotData['patientId']?.toString().trim() ?? '';
        final existingTimeSlot = slotData['timeSlot']?.toString().trim() ?? '';

        if (existingApptId.isEmpty ||
            existingPatientId.isEmpty ||
            existingTimeSlot.isEmpty) {
          throw SlotLockCorruptException(
            'Slot lock $authoritativeOldSlotKey contains missing or empty required fields.',
            slotKey: authoritativeOldSlotKey,
          );
        }

        if (existingApptId != trimmedApptId) {
          throw SlotAlreadyBookedException(
            'Slot $authoritativeOldSlotKey belongs to appointment $existingApptId, not $trimmedApptId.',
            slotKey: authoritativeOldSlotKey,
            conflictingAppointmentId: existingApptId,
          );
        }

        if (existingPatientId != serverPatientId ||
            existingTimeSlot != serverTimeSlot) {
          throw SlotLockCorruptException(
            'Slot lock for appointment $trimmedApptId has inconsistent patientId or timeSlot.',
            slotKey: authoritativeOldSlotKey,
          );
        }

        final rawLockDate = slotData['date'];
        if (rawLockDate == null || rawLockDate is! Timestamp) {
          throw SlotLockCorruptException(
            'Slot lock for appointment $trimmedApptId is missing or has invalid date.',
            slotKey: authoritativeOldSlotKey,
          );
        }
        final lockDateOnly = DateTime(rawLockDate.toDate().year,
            rawLockDate.toDate().month, rawLockDate.toDate().day);
        if (lockDateOnly != serverDateOnly) {
          throw SlotLockCorruptException(
            'Slot lock for appointment $trimmedApptId date conflicts with authoritative date.',
            slotKey: authoritativeOldSlotKey,
          );
        }

        final rawBookedAt = slotData['bookedAt'];
        if (rawBookedAt == null || rawBookedAt is! Timestamp) {
          throw SlotLockCorruptException(
            'Slot lock for appointment $trimmedApptId is missing or has invalid bookedAt timestamp.',
            slotKey: authoritativeOldSlotKey,
          );
        }

        shouldDeleteSlotLock = true;
      }

      // ── PHASE 2: ATOMIC WRITES ──
      final now = Timestamp.now();
      final newSlotKey = buildSlotKey(newDate, trimmedNewSlot);
      final updateData = {
        'appointmentDate': Timestamp.fromDate(newDate),
        'timeSlot': trimmedNewSlot,
        'slotKey': newSlotKey,
        'status': AppointmentStatus.scheduled.firestoreValue,
        'updatedAt': now,
      };

      tx.update(apptRef, updateData);
      tx.update(patientApptRef, updateData);

      if (shouldDeleteSlotLock) {
        tx.delete(oldSlotRef);
      }
    });

    // ── Notification: executed strictly outside and after successful transaction commit ──
    await _createNotification(
      patientId: trimmedPatientId,
      title: 'Appointment Rescheduled — Awaiting Approval',
      body:
          'Your appointment has been rescheduled to ${_fmtDate(newDate)} at $trimmedNewSlot. The doctor must approve the new time.',
      type: 'appointment',
      referenceId: trimmedApptId,
    );
  }

  // ── Fetch Patient Appointments ────────────────────────────────
  Stream<List<AppointmentModel>> watchPatientAppointments(String patientId) =>
      _patientAppts(patientId).snapshots().map((s) {
        final list = s.docs
            .map((d) =>
                AppointmentModel.fromMap(d.data() as Map<String, dynamic>))
            .toList();
        list.sort((a, b) => a.appointmentDate.compareTo(b.appointmentDate));
        return list;
      });

  Future<List<AppointmentModel>> getPatientAppointments(
      String patientId) async {
    final snap = await _patientAppts(patientId)
        .orderBy('appointmentDate', descending: false)
        .get();
    return snap.docs
        .map((d) => AppointmentModel.fromMap(d.data() as Map<String, dynamic>))
        .toList();
  }

  Future<AppointmentModel?> getAppointment(String id) async {
    final doc = await _appointments.doc(id).get();
    if (!doc.exists) return null;
    return AppointmentModel.fromMap(doc.data() as Map<String, dynamic>);
  }

  // ── Notifications ─────────────────────────────────────────────
  Stream<List<NotificationModel>> watchNotifications(String patientId) =>
      _notifications(patientId)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .snapshots()
          .map((s) => s.docs
              .map((d) =>
                  NotificationModel.fromMap(d.data() as Map<String, dynamic>))
              .toList());

  Future<void> markNotificationRead(String patientId, String notifId) async {
    await _notifications(patientId).doc(notifId).update({'isRead': true});
  }

  Future<void> markAllRead(String patientId) async {
    final snap =
        await _notifications(patientId).where('isRead', isEqualTo: false).get();
    final batch = _db.batch();
    for (final doc in snap.docs) batch.update(doc.reference, {'isRead': true});
    await batch.commit();
  }

  Future<void> _createNotification({
    required String patientId,
    required String title,
    required String body,
    required String type,
    String? referenceId,
  }) async {
    final ref = _notifications(patientId).doc();
    final notif = NotificationModel(
      id: ref.id,
      patientId: patientId,
      title: title,
      body: body,
      type: type,
      createdAt: DateTime.now(),
      referenceId: referenceId,
    );
    await ref.set(notif.toMap());
  }

  String _fmtDate(DateTime d) => '${d.day}/${d.month}/${d.year}';
}

class MedicalRecordService {
  final _db = FirebaseFirestore.instance;

  CollectionReference _records(String uid) =>
      _db.collection('patients').doc(uid).collection('medicalRecords');

  Stream<List<MedicalRecordModel>> watchRecords(String patientId,
      {RecordType? type}) {
    Query q = _records(patientId).orderBy('date', descending: true);
    if (type != null) q = q.where('type', isEqualTo: type.firestoreValue);
    return q.snapshots().map((s) => s.docs
        .map(
            (d) => MedicalRecordModel.fromMap(d.data() as Map<String, dynamic>))
        .toList());
  }

  Future<void> addRecord(MedicalRecordModel record) async {
    final ref =
        _records(record.patientId).doc(record.id.isEmpty ? null : record.id);
    await ref.set(record.toMap());
  }

  Future<MedicalRecordModel?> getRecord(
      String patientId, String recordId) async {
    try {
      final doc = await _records(patientId).doc(recordId).get();
      if (!doc.exists) return null;
      return MedicalRecordModel.fromMap(doc.data() as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  // Seed sample records for a new patient (called after signup)
  Future<void> seedSampleRecords(String patientId, String patientName) async {
    final now = DateTime.now();
    final samples = [
      MedicalRecordModel(
        id: 'rec_001_$patientId',
        patientId: patientId,
        title: 'MRI Scan - Lumbar Spine',
        type: RecordType.report,
        subtype: 'Imaging',
        facility: 'Radiology Center East',
        doctorName: 'Dr. Aris Thorne',
        date: now.subtract(const Duration(days: 13)),
        fileType: 'pdf',
        summary: 'No acute abnormality detected.',
        uploadedAt: now.subtract(const Duration(days: 13)),
      ),
      MedicalRecordModel(
        id: 'rec_002_$patientId',
        patientId: patientId,
        title: 'Complete Blood Count (CBC)',
        type: RecordType.report,
        subtype: 'Pathology',
        facility: 'City Oncology Lab',
        doctorName: 'Dr. Elena Vance',
        date: now.subtract(const Duration(days: 25)),
        fileType: 'pdf',
        summary: 'WBC: Normal, RBC: Slightly low.',
        uploadedAt: now.subtract(const Duration(days: 25)),
      ),
      MedicalRecordModel(
        id: 'rec_003_$patientId',
        patientId: patientId,
        title: 'Oncology Consultation Summary',
        type: RecordType.report,
        subtype: 'Clinical Notes',
        facility: 'OncoVault Medical Center',
        doctorName: 'Dr. Sarah Jenkins',
        date: now.subtract(const Duration(days: 49)),
        fileType: 'pdf',
        summary: 'Patient responding well to current protocol.',
        uploadedAt: now.subtract(const Duration(days: 49)),
      ),
      MedicalRecordModel(
        id: 'rec_004_$patientId',
        patientId: patientId,
        title: 'Hormone Therapy - Phase 2',
        type: RecordType.medicalHistory,
        subtype: 'Treatment',
        facility: 'OncoVault Medical Center',
        doctorName: 'Dr. Aris Thorne',
        date: now.subtract(const Duration(days: 60)),
        fileType: 'text',
        summary:
            'Progressing according to treatment plan. Current cycle focuses on stabilization and long-term monitoring.',
        uploadedAt: now.subtract(const Duration(days: 60)),
      ),
    ];
    for (final r in samples) await addRecord(r);
  }
}
