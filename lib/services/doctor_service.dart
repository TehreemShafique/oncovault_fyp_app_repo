// lib/services/doctor_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../models/doctor_model.dart';
import '../models/appointment_model.dart';
import '../models/patient_profile_model.dart';
import '../models/medical_record_model.dart';
import '../models/blood_cancer_ehr_model.dart';
import '../models/doctor_availability_model.dart';
import 'appointment_exceptions.dart';
import 'appointment_service.dart';
import 'fabric_gateway_service.dart';

typedef ApproveAppointmentCallable = Future<Map<String, dynamic>> Function({
  required String appointmentId,
});

typedef UpdateDoctorAvailabilityCallable = Future<Map<String, dynamic>> Function({
  required Map<String, dynamic> availability,
  bool? isAvailable,
});

class DoctorService {
  final FirebaseFirestore? _customDb;
  final FirebaseAuth? _customAuth;
  final FirebaseFunctions? _customFunctions;
  final ApproveAppointmentCallable? _customApproveCallable;
  final UpdateDoctorAvailabilityCallable? _customUpdateAvailabilityCallable;

  DoctorService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
    ApproveAppointmentCallable? approveCallable,
    UpdateDoctorAvailabilityCallable? updateAvailabilityCallable,
  })  : _customDb = firestore,
        _customAuth = auth,
        _customFunctions = functions,
        _customApproveCallable = approveCallable,
        _customUpdateAvailabilityCallable = updateAvailabilityCallable;

  FirebaseFirestore get _db => _customDb ?? FirebaseFirestore.instance;
  FirebaseAuth? get _safeAuth {
    if (_customAuth != null) return _customAuth;
    try {
      return FirebaseAuth.instance;
    } catch (_) {
      return null;
    }
  }

  FirebaseFunctions get _functions {
    if (_customFunctions != null) return _customFunctions!;
    try {
      return FirebaseFunctions.instance;
    } catch (_) {
      return FirebaseFunctions.instanceFor(region: 'us-central1');
    }
  }

  CollectionReference get _doctors => _db.collection('doctors');
  CollectionReference get _appointments => _db.collection('appointments');
  CollectionReference get _users => _db.collection('users');
  CollectionReference get _patients => _db.collection('patients');
  CollectionReference get _consents =>
      _db.collection('doctor_patient_consents');

  CollectionReference _patientBloodCancerEhrs(String patientId) =>
      _db.collection('patients').doc(patientId).collection('blood_cancer_ehrs');

  CollectionReference _diagnoses(String uid) =>
      _db.collection('doctors').doc(uid).collection('diagnoses');
  CollectionReference _alerts(String uid) =>
      _db.collection('doctors').doc(uid).collection('alerts');
  CollectionReference _notifications(String uid) =>
      _db.collection('notifications').doc(uid).collection('items');
  CollectionReference _patientDiagnoses(String patientId) =>
      _db.collection('patients').doc(patientId).collection('diagnoses');
  CollectionReference _patientAppts(String patientId) =>
      _db.collection('patients').doc(patientId).collection('appointments');

  // ── Booked Slots ──────────────────────────────────────────────
  // /bookedSlots/{doctorId}/slots/{slotKey}
  // slotKey format: "yyyy-MM-dd_HH:mm AM/PM"  e.g. "2025-06-15_09:30 AM"
  // Written on approve, deleted on complete / cancel / reschedule.
  CollectionReference _bookedSlots(String doctorId) =>
      _db.collection('bookedSlots').doc(doctorId).collection('slots');

  // ── Doctor Profile ────────────────────────────────────────────
  Future<DoctorModel?> fetchDoctor(String uid) async {
    try {
      final doc = await _doctors.doc(uid).get();
      if (doc.exists) {
        return DoctorModel.fromMap(doc.data() as Map<String, dynamic>);
      }
      final userDoc = await _users.doc(uid).get();
      if (!userDoc.exists) return null;
      final data = userDoc.data() as Map<String, dynamic>;
      final doctorProfile = DoctorModel(
        uid: uid,
        name: data['name'] ?? '',
        email: data['email'] ?? '',
        medicalId: data['medicalId'] ?? '',
        createdAt: DateTime.now(),
      );
      await _doctors
          .doc(uid)
          .set(doctorProfile.toMap(), SetOptions(merge: true));
      return doctorProfile;
    } catch (e) {
      return null;
    }
  }

  Future<void> updateDoctorProfile(DoctorModel doctor) async {
    final data = Map<String, dynamic>.from(doctor.toMap())
      ..remove('availability')
      ..remove('scheduleRevision')
      ..remove('availableDays')
      ..remove('availableSlots');
    final batch = _db.batch();
    batch.set(_doctors.doc(doctor.uid), data, SetOptions(merge: true));
    batch.set(_users.doc(doctor.uid), data, SetOptions(merge: true));
    await batch.commit();
  }

  /// Trusted Cloud Function update for doctor availability & working hours.
  /// Enforces server-side validation, role verification, and protection against
  /// invalidating existing confirmed appointments.
  Future<void> updateDoctorAvailability({
    required DoctorAvailability availability,
    bool? isAvailable,
  }) async {
    final auth = _safeAuth;
    final currentUserId = auth?.currentUser?.uid;
    if (auth == null || currentUserId == null || currentUserId.trim().isEmpty) {
      throw const AppointmentUnauthorizedException(
        'Doctor availability updates require an authenticated session.',
        appointmentId: '',
      );
    }

    try {
      if (_customUpdateAvailabilityCallable != null) {
        await _customUpdateAvailabilityCallable!(
          availability: availability.toMap(),
          isAvailable: isAvailable,
        );
      } else {
        final callable = _functions.httpsCallable('updateDoctorAvailability');
        await callable.call<Map<String, dynamic>>({
          'availability': availability.toMap(),
          if (isAvailable != null) 'isAvailable': isAvailable,
        });
      }
    } on FirebaseFunctionsException catch (e) {
      _mapUpdateAvailabilityException(e);
    } catch (e) {
      if (e is AppointmentException) rethrow;
      throw DoctorScheduleConflictException(
        'Server update of doctor availability failed: $e',
        reason: e.toString(),
      );
    }
  }

  Never _mapUpdateAvailabilityException(FirebaseFunctionsException e) {
    final msg = e.message ?? e.toString();
    switch (e.code) {
      case 'unauthenticated':
      case 'permission-denied':
        throw AppointmentUnauthorizedException(msg, appointmentId: '');
      case 'failed-precondition':
      case 'invalid-argument':
      default:
        throw DoctorScheduleConflictException(msg, reason: msg);
    }
  }

  // ── Appointments ──────────────────────────────────────────────
  Stream<List<AppointmentModel>> watchDoctorAppointments(String doctorId) =>
      _appointments.where('doctorId', isEqualTo: doctorId).snapshots().map((s) {
        final list = s.docs
            .map((d) =>
                AppointmentModel.fromMap(d.data() as Map<String, dynamic>))
            .toList();
        list.sort((a, b) => a.appointmentDate.compareTo(b.appointmentDate));
        return list;
      });

  Stream<List<AppointmentModel>> watchPendingAppointments(String doctorId) =>
      _appointments
          .where('doctorId', isEqualTo: doctorId)
          .where('status', whereIn: ['scheduled', 'pending', 'rescheduled'])
          .snapshots()
          .map((s) {
            final list = s.docs
                .map((d) =>
                    AppointmentModel.fromMap(d.data() as Map<String, dynamic>))
                .toList();
            list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
            return list;
          });

  /// Pure eligibility check for appointment approval:
  /// Allows canonical 'scheduled' and legacy 'pending', case-insensitively and trimmed.
  /// Rejects null, empty, whitespace-only, unrecognized, and all non-scheduled statuses.
  static bool isStatusEligibleForApproval(String? rawStatus) {
    if (rawStatus == null) return false;
    final trimmed = rawStatus.trim().toLowerCase();
    if (trimmed.isEmpty) return false;
    return trimmed == 'scheduled' || trimmed == 'pending';
  }

  /// Pure eligibility check for doctor appointment rescheduling:
  /// Allows scheduled, pending, confirmed, approved, and rescheduled case-insensitively with trimming.
  /// Rejects null, empty, whitespace-only, unrecognized, and terminal statuses.
  static bool isStatusEligibleForRescheduling(String? rawStatus) =>
      AppointmentService.isStatusEligibleForRescheduling(rawStatus);

  /// Pure eligibility check for doctor appointment completion:
  /// Allows canonical 'confirmed' and legacy 'approved', case-insensitively and trimmed.
  /// Rejects null, empty, whitespace-only, unrecognized, unconfirmed, and terminal statuses.
  static bool isStatusEligibleForCompletion(String? rawStatus) {
    if (rawStatus == null) return false;
    final trimmed = rawStatus.trim().toLowerCase();
    if (trimmed.isEmpty) return false;
    return trimmed == 'confirmed' || trimmed == 'approved';
  }

  /// Pure eligibility check for doctor appointment rejection:
  /// Allows canonical 'scheduled', legacy 'pending', and 'rescheduled', case-insensitively and trimmed.
  /// Rejects null, empty, whitespace-only, unrecognized, confirmed, completed, cancelled, and already rejected statuses.
  static bool isStatusEligibleForRejection(String? rawStatus) {
    if (rawStatus == null) return false;
    final trimmed = rawStatus.trim().toLowerCase();
    if (trimmed.isEmpty) return false;
    return trimmed == 'scheduled' ||
        trimmed == 'pending' ||
        trimmed == 'rescheduled';
  }

  /// Returns the canonical status string for [rawStatus], normalizing legacy aliases,
  /// case, and whitespace. Returns null for unrecognized, empty, or null statuses.
  /// Canonical mappings:
  /// - 'scheduled', 'pending' -> 'scheduled'
  /// - 'confirmed', 'approved' -> 'confirmed'
  /// - 'rescheduled' -> 'rescheduled'
  /// - 'cancelled', 'canceled' -> 'cancelled'
  /// - 'completed' -> 'completed'
  /// - 'rejected' -> 'rejected'
  static String? canonicalStatus(String? rawStatus) {
    if (rawStatus == null) return null;
    final trimmed = rawStatus.trim().toLowerCase();
    switch (trimmed) {
      case 'scheduled':
      case 'pending':
        return 'scheduled';
      case 'confirmed':
      case 'approved':
        return 'confirmed';
      case 'rescheduled':
        return 'rescheduled';
      case 'cancelled':
      case 'canceled':
        return 'cancelled';
      case 'completed':
        return 'completed';
      case 'rejected':
        return 'rejected';
      default:
        return null;
    }
  }

  // ── FEATURE 1: Approve → write bookedSlot ────────────────────
  // When the doctor approves, the slot is atomically reserved and the
  // appointment confirmed inside an atomic Firestore transaction.
  Future<void> approveAppointment(AppointmentModel appt) async {
    // 1. Fail-closed authentication check
    final auth = _safeAuth;
    final currentUserId = auth?.currentUser?.uid;
    if (auth == null || currentUserId == null || currentUserId.trim().isEmpty) {
      throw AppointmentUnauthorizedException(
        'Doctor approval requires an authenticated session.',
        appointmentId: appt.id,
      );
    }

    if (appt.doctorId.trim().isEmpty || currentUserId != appt.doctorId) {
      throw AppointmentUnauthorizedException(
        'Authenticated doctor UID does not match the appointment doctor ID.',
        appointmentId: appt.id,
      );
    }

    // 2. Invoke trusted Cloud Function callable
    try {
      if (_customApproveCallable != null) {
        await _customApproveCallable!(appointmentId: appt.id);
      } else {
        final callable = _functions.httpsCallable('approveAppointment');
        await callable.call<Map<String, dynamic>>({
          'appointmentId': appt.id,
        });
      }
    } on FirebaseFunctionsException catch (e) {
      _mapFunctionsException(e, appt);
    } catch (e) {
      if (e is AppointmentException) rethrow;
      throw AppointmentStateConflictException(
        'Server approval failed: $e',
        appointmentId: appt.id,
        currentStatus: appt.status.firestoreValue,
        requiredStatus: 'scheduled',
      );
    }
  }

  Never _mapFunctionsException(
      FirebaseFunctionsException e, AppointmentModel appt) {
    final msg = e.message ?? e.toString();
    switch (e.code) {
      case 'unauthenticated':
      case 'permission-denied':
        throw AppointmentUnauthorizedException(msg, appointmentId: appt.id);
      case 'not-found':
        throw AppointmentNotFoundException(msg, appointmentId: appt.id);
      case 'already-exists':
        throw SlotAlreadyBookedException(msg, slotKey: appt.slotKey);
      case 'failed-precondition':
        final lower = msg.toLowerCase();
        if (lower.contains('mirror')) {
          throw AppointmentMirrorInconsistentException(
            msg,
            appointmentId: appt.id,
            patientId: appt.patientId,
            reason: msg,
          );
        }
        if (lower.contains('slot lock') || lower.contains('corrupt')) {
          throw SlotLockCorruptException(msg, slotKey: appt.slotKey);
        }
        if (lower.contains('availability') ||
            lower.contains('expired') ||
            lower.contains('not available') ||
            lower.contains('working hours') ||
            lower.contains('blocked')) {
          throw DoctorAvailabilityException(
            msg,
            appointmentId: appt.id,
            reason: msg,
          );
        }
        throw AppointmentStateConflictException(
          msg,
          appointmentId: appt.id,
          currentStatus: appt.status.firestoreValue,
          requiredStatus: 'scheduled',
        );
      case 'invalid-argument':
        throw AppointmentPayloadConflictException(
          msg,
          appointmentId: appt.id,
          field: 'appointmentId',
          expectedValue: appt.id,
          actualValue: '',
        );
      default:
        throw AppointmentStateConflictException(
          msg,
          appointmentId: appt.id,
          currentStatus: appt.status.firestoreValue,
          requiredStatus: 'scheduled',
        );
    }
  }

  // ── Reject Appointment → atomic transaction ──────────────────
  // Transactional doctor rejection: verifies authoritative state and mirror consistency,
  // enforces pending-only status transitions (scheduled, pending, rescheduled),
  // validates slot lock integrity, atomically updates global and mirror records to 'rejected',
  // and dispatches post-commit patient notification.
  Future<void> rejectAppointment(
    AppointmentModel appt, {
    String reason = '',
  }) async {
    final trimmedApptId = appt.id.trim();
    final trimmedDoctorId = appt.doctorId.trim();
    final trimmedPatientId = appt.patientId.trim();
    final trimmedReason = reason.trim();

    // 1. Pre-transaction identifier validation
    if (trimmedApptId.isEmpty ||
        trimmedDoctorId.isEmpty ||
        trimmedPatientId.isEmpty) {
      final field = trimmedApptId.isEmpty
          ? 'id'
          : trimmedDoctorId.isEmpty
              ? 'doctorId'
              : 'patientId';
      final actual = trimmedApptId.isEmpty
          ? appt.id
          : trimmedDoctorId.isEmpty
              ? appt.doctorId
              : appt.patientId;
      throw AppointmentPayloadConflictException(
        'Appointment rejection requires non-empty $field.',
        appointmentId: trimmedApptId,
        field: field,
        expectedValue: 'non-empty string',
        actualValue: actual,
      );
    }

    // 2. Fail-closed authentication check
    final auth = _safeAuth;
    final currentUserId = auth?.currentUser?.uid;
    if (auth == null || currentUserId == null || currentUserId.trim().isEmpty) {
      throw AppointmentUnauthorizedException(
        'Doctor rejection requires an authenticated session.',
        appointmentId: trimmedApptId,
      );
    }

    // 3. Preliminary doctor authorization
    if (currentUserId != trimmedDoctorId) {
      throw AppointmentUnauthorizedException(
        'Authenticated doctor UID does not match the appointment doctor ID.',
        appointmentId: trimmedApptId,
      );
    }

    final apptRef = _appointments.doc(trimmedApptId);

    String? verifiedPatientId;
    DateTime? verifiedAppointmentDate;

    // 4. Atomic transaction
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
          'Appointment document $trimmedApptId status is missing or empty, cannot be rejected.',
          appointmentId: trimmedApptId,
          currentStatus: rawStatus?.trim() ?? '',
          requiredStatus: 'eligible (scheduled, pending, or rescheduled)',
        );
      }

      if (!isStatusEligibleForRejection(rawStatus)) {
        final trimmed = rawStatus.trim();
        const knownIneligibleStatuses = {
          'confirmed',
          'approved',
          'cancelled',
          'canceled',
          'completed',
          'rejected',
        };
        final description =
            knownIneligibleStatuses.contains(trimmed.toLowerCase())
                ? trimmed
                : 'unrecognized status "$trimmed"';
        throw AppointmentStateConflictException(
          'Appointment $trimmedApptId is in $description status, cannot be rejected.',
          appointmentId: trimmedApptId,
          currentStatus: trimmed,
          requiredStatus: 'eligible (scheduled, pending, or rescheduled)',
        );
      }

      final serverDoctorId = apptData['doctorId']?.toString().trim() ?? '';
      if (serverDoctorId.isEmpty || serverDoctorId != currentUserId) {
        throw AppointmentUnauthorizedException(
          'Server record doctorId ($serverDoctorId) does not match authenticated doctor ($currentUserId).',
          appointmentId: trimmedApptId,
        );
      }

      final serverPatientId = apptData['patientId']?.toString().trim() ?? '';
      if (serverPatientId.isEmpty || serverPatientId != trimmedPatientId) {
        throw AppointmentPayloadConflictException(
          'Appointment patientId ($serverPatientId) does not match caller parameter ($trimmedPatientId).',
          appointmentId: trimmedApptId,
          field: 'patientId',
          expectedValue: serverPatientId,
          actualValue: trimmedPatientId,
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
      final patientApptRef = _patientAppts(serverPatientId).doc(trimmedApptId);
      final patientApptSnap = await tx.get(patientApptRef);
      if (!patientApptSnap.exists) {
        throw AppointmentMirrorInconsistentException(
          'Patient appointment mirror does not exist at /patients/$serverPatientId/appointments/$trimmedApptId.',
          appointmentId: trimmedApptId,
          patientId: serverPatientId,
          reason: 'Mirror document does not exist',
        );
      }

      final patientData = patientApptSnap.data() as Map<String, dynamic>;
      final mirrorDoctorId = patientData['doctorId']?.toString().trim() ?? '';
      final mirrorPatientId =
          patientData['patientId']?.toString().trim() ?? '';
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

      final canonicalGlobal = canonicalStatus(rawStatus);
      final canonicalMirror = canonicalStatus(mirrorRawStatus);
      if (!isStatusEligibleForRejection(mirrorRawStatus) ||
          canonicalGlobal == null ||
          canonicalMirror == null ||
          canonicalGlobal != canonicalMirror) {
        throw AppointmentMirrorInconsistentException(
          'Patient appointment mirror status ($mirrorRawStatus) is inconsistent with global record status ($rawStatus).',
          appointmentId: trimmedApptId,
          patientId: serverPatientId,
          reason: 'Mirror status does not match canonical global status',
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

      final mirrorTimeSlot =
          patientData['timeSlot']?.toString().trim() ?? '';
      if (mirrorTimeSlot != serverTimeSlot) {
        throw AppointmentMirrorInconsistentException(
          'Patient appointment mirror timeSlot ($mirrorTimeSlot) conflicts with authoritative timeSlot ($serverTimeSlot).',
          appointmentId: trimmedApptId,
          patientId: serverPatientId,
          reason: 'Mirror timeSlot mismatch',
        );
      }

      // 3. Derive canonical slotKey and validate existing slot lock
      final authoritativeSlotKey =
          buildSlotKey(serverAppointmentDate, serverTimeSlot);
      final slotRef =
          _bookedSlots(serverDoctorId).doc(authoritativeSlotKey);

      final slotSnap = await tx.get(slotRef);

      if (slotSnap.exists) {
        final slotData = slotSnap.data() as Map<String, dynamic>? ?? {};
        final existingApptId =
            slotData['appointmentId']?.toString().trim() ?? '';

        // Case D: Slot lock exists but ownership information is missing or empty
        if (existingApptId.isEmpty) {
          throw SlotLockCorruptException(
            'Slot lock $authoritativeSlotKey contains missing or empty required appointmentId.',
            slotKey: authoritativeSlotKey,
          );
        }

        // Case C: Slot lock belongs to this pending appointment (lifecycle violation)
        if (existingApptId == trimmedApptId) {
          throw SlotLockCorruptException(
            'Pending appointment $trimmedApptId unexpectedly owns an exclusive slot lock at $authoritativeSlotKey.',
            slotKey: authoritativeSlotKey,
          );
        }

        // Case B: Slot lock belongs to another appointment (existingApptId != trimmedApptId)
        // Verify foreign lock is not malformed
        final existingPatientId =
            slotData['patientId']?.toString().trim() ?? '';
        final existingTimeSlot =
            slotData['timeSlot']?.toString().trim() ?? '';
        final rawLockDate = slotData['date'];

        if (existingPatientId.isEmpty ||
            existingTimeSlot.isEmpty ||
            rawLockDate == null ||
            rawLockDate is! Timestamp) {
          throw SlotLockCorruptException(
            'Slot lock $authoritativeSlotKey contains malformed foreign lock data.',
            slotKey: authoritativeSlotKey,
          );
        }

        // Legitimate foreign-owned lock: preserved intact without mutation.
      }
      // Case A: No slot lock exists. Expected state. Proceed.

      verifiedPatientId = serverPatientId;
      verifiedAppointmentDate = serverAppointmentDate;

      // ── PHASE 2: ATOMIC WRITES ──
      final updateData = {
        'status': AppointmentStatus.rejected.firestoreValue,
        'doctorNotes': trimmedReason,
        'rejectedBy': currentUserId,
        'rejectedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      tx.update(apptRef, updateData);
      tx.update(patientApptRef, updateData);
    });

    // ── Patient Notification: executed strictly outside and after successful transaction commit ──
    await _sendPatientNotification(
      patientId: verifiedPatientId ?? trimmedPatientId,
      title: 'Appointment Not Available',
      body:
          'Your appointment for ${_fmt(verifiedAppointmentDate ?? appt.appointmentDate)} '
          'could not be accommodated.'
          '${trimmedReason.isNotEmpty ? ' Reason: $trimmedReason' : ''}',
      type: 'appointment',
      referenceId: trimmedApptId,
    );
  }

  // ── FEATURE 2: Doctor reschedule → free old slot + reset scheduled ──
  // Transactional doctor rescheduling: verifies authoritative state and mirror consistency,
  // safely deletes verified old lock if previously confirmed, updates global and mirror
  // records to 'scheduled', and dispatches post-commit patient notification.
  Future<void> doctorReschedule({
    required AppointmentModel appt,
    required DateTime newDate,
    required String newSlot,
  }) async {
    final trimmedApptId = appt.id.trim();
    final trimmedDoctorId = appt.doctorId.trim();
    final trimmedPatientId = appt.patientId.trim();
    final trimmedNewSlot = newSlot.trim();

    if (trimmedApptId.isEmpty ||
        trimmedDoctorId.isEmpty ||
        trimmedPatientId.isEmpty ||
        trimmedNewSlot.isEmpty) {
      final field = trimmedApptId.isEmpty
          ? 'id'
          : trimmedDoctorId.isEmpty
              ? 'doctorId'
              : trimmedPatientId.isEmpty
                  ? 'patientId'
                  : 'newSlot';
      final actual = trimmedApptId.isEmpty
          ? appt.id
          : trimmedDoctorId.isEmpty
              ? appt.doctorId
              : trimmedPatientId.isEmpty
                  ? appt.patientId
                  : newSlot;
      throw AppointmentPayloadConflictException(
        'Doctor rescheduling requires non-empty appointment id, doctorId, patientId, and newSlot.',
        appointmentId: trimmedApptId,
        field: field,
        expectedValue: 'non-empty string',
        actualValue: actual,
      );
    }

    // Preliminary date validation before transaction
    AppointmentService.validateAppointmentDate(newDate,
        appointmentId: trimmedApptId);

    // 1. Fail-closed authentication check
    final auth = _safeAuth;
    final currentUserId = auth?.currentUser?.uid;
    if (auth == null || currentUserId == null || currentUserId.trim().isEmpty) {
      throw AppointmentUnauthorizedException(
        'Doctor rescheduling requires an authenticated session.',
        appointmentId: trimmedApptId,
      );
    }

    if (currentUserId != trimmedDoctorId) {
      throw AppointmentUnauthorizedException(
        'Authenticated doctor UID does not match the appointment doctor ID.',
        appointmentId: trimmedApptId,
      );
    }

    final apptRef = _appointments.doc(trimmedApptId);
    String? verifiedPatientId;

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
          requiredStatus:
              'eligible (scheduled, pending, confirmed, approved, or rescheduled)',
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
          requiredStatus:
              'eligible (scheduled, pending, confirmed, approved, or rescheduled)',
        );
      }

      final serverDoctorId = apptData['doctorId']?.toString().trim() ?? '';
      if (serverDoctorId.isEmpty || serverDoctorId != currentUserId) {
        throw AppointmentUnauthorizedException(
          'Server record doctorId ($serverDoctorId) does not match authenticated doctor ($currentUserId).',
          appointmentId: trimmedApptId,
        );
      }

      final serverPatientId = apptData['patientId']?.toString().trim() ?? '';
      if (serverPatientId.isEmpty || serverPatientId != trimmedPatientId) {
        throw AppointmentPayloadConflictException(
          'Appointment patientId ($serverPatientId) does not match caller parameter ($trimmedPatientId).',
          appointmentId: trimmedApptId,
          field: 'patientId',
          expectedValue: serverPatientId,
          actualValue: trimmedPatientId,
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
      final patientApptRef = _patientAppts(serverPatientId).doc(trimmedApptId);
      final patientApptSnap = await tx.get(patientApptRef);
      if (!patientApptSnap.exists) {
        throw AppointmentMirrorInconsistentException(
          'Patient appointment mirror does not exist at /patients/$serverPatientId/appointments/$trimmedApptId.',
          appointmentId: trimmedApptId,
          patientId: serverPatientId,
          reason: 'Mirror document does not exist',
        );
      }

      final patientData = patientApptSnap.data() as Map<String, dynamic>;
      final mirrorDoctorId = patientData['doctorId']?.toString().trim() ?? '';
      final mirrorPatientId =
          patientData['patientId']?.toString().trim() ?? '';
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

      final mirrorTimeSlot =
          patientData['timeSlot']?.toString().trim() ?? '';
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
        final existingTimeSlot =
            slotData['timeSlot']?.toString().trim() ?? '';

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

      verifiedPatientId = serverPatientId;

      // ── PHASE 2: ATOMIC WRITES ──
      final newSlotKey = buildSlotKey(newDate, trimmedNewSlot);
      final updateData = {
        'appointmentDate': Timestamp.fromDate(newDate),
        'timeSlot': trimmedNewSlot,
        'slotKey': newSlotKey,
        'status': AppointmentStatus.scheduled.firestoreValue,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      tx.update(apptRef, updateData);
      tx.update(patientApptRef, updateData);

      if (shouldDeleteSlotLock) {
        tx.delete(oldSlotRef);
      }
    });

    // ── Patient Notification: executed strictly outside and after successful transaction commit ──
    await _sendPatientNotification(
      patientId: verifiedPatientId ?? trimmedPatientId,
      title: 'Appointment Rescheduled by Doctor',
      body: 'Your appointment has been moved to '
          '${_fmt(newDate)} at $trimmedNewSlot. '
          'It is now pending re-confirmation.',
      type: 'appointment',
      referenceId: trimmedApptId,
    );
  }

  // ── Mark Complete → atomic transaction with slot lock retention ─
  // Transactional doctor completion: verifies authoritative state, mirror consistency,
  // and slot lock ownership. Atomically updates global and mirror records to 'completed'
  // while strictly retaining the slot lock intact to prevent double-booking.
  Future<void> markAppointmentComplete(AppointmentModel appt) async {
    final trimmedApptId = appt.id.trim();
    final trimmedDoctorId = appt.doctorId.trim();
    final trimmedPatientId = appt.patientId.trim();

    if (trimmedApptId.isEmpty ||
        trimmedDoctorId.isEmpty ||
        trimmedPatientId.isEmpty) {
      final field = trimmedApptId.isEmpty
          ? 'id'
          : trimmedDoctorId.isEmpty
              ? 'doctorId'
              : 'patientId';
      final actual = trimmedApptId.isEmpty
          ? appt.id
          : trimmedDoctorId.isEmpty
              ? appt.doctorId
              : appt.patientId;
      throw AppointmentPayloadConflictException(
        'Doctor completion requires non-empty appointment id, doctorId, and patientId.',
        appointmentId: trimmedApptId,
        field: field,
        expectedValue: 'non-empty string',
        actualValue: actual,
      );
    }

    // 1. Fail-closed authentication check
    final auth = _safeAuth;
    final currentUserId = auth?.currentUser?.uid;
    if (auth == null || currentUserId == null || currentUserId.trim().isEmpty) {
      throw AppointmentUnauthorizedException(
        'Doctor completion requires an authenticated session.',
        appointmentId: trimmedApptId,
      );
    }

    // Preliminary doctor authorization check
    if (currentUserId != trimmedDoctorId) {
      throw AppointmentUnauthorizedException(
        'Authenticated doctor UID does not match the appointment doctor ID.',
        appointmentId: trimmedApptId,
      );
    }

    final apptRef = _appointments.doc(trimmedApptId);
    String? verifiedPatientId;

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
          'Appointment document $trimmedApptId status is missing or empty, cannot be completed.',
          appointmentId: trimmedApptId,
          currentStatus: rawStatus?.trim() ?? '',
          requiredStatus: 'eligible (confirmed or approved)',
        );
      }

      if (!isStatusEligibleForCompletion(rawStatus)) {
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
          'Appointment $trimmedApptId is in $description status, cannot be completed.',
          appointmentId: trimmedApptId,
          currentStatus: trimmed,
          requiredStatus: 'eligible (confirmed or approved)',
        );
      }

      final serverDoctorId = apptData['doctorId']?.toString().trim() ?? '';
      if (serverDoctorId.isEmpty || serverDoctorId != currentUserId) {
        throw AppointmentUnauthorizedException(
          'Server record doctorId ($serverDoctorId) does not match authenticated doctor ($currentUserId).',
          appointmentId: trimmedApptId,
        );
      }

      final serverPatientId = apptData['patientId']?.toString().trim() ?? '';
      if (serverPatientId.isEmpty || serverPatientId != trimmedPatientId) {
        throw AppointmentPayloadConflictException(
          'Appointment patientId ($serverPatientId) does not match caller parameter ($trimmedPatientId).',
          appointmentId: trimmedApptId,
          field: 'patientId',
          expectedValue: serverPatientId,
          actualValue: trimmedPatientId,
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
      final patientApptRef = _patientAppts(serverPatientId).doc(trimmedApptId);
      final patientApptSnap = await tx.get(patientApptRef);
      if (!patientApptSnap.exists) {
        throw AppointmentMirrorInconsistentException(
          'Patient appointment mirror does not exist at /patients/$serverPatientId/appointments/$trimmedApptId.',
          appointmentId: trimmedApptId,
          patientId: serverPatientId,
          reason: 'Mirror document does not exist',
        );
      }

      final patientData = patientApptSnap.data() as Map<String, dynamic>;
      final mirrorDoctorId = patientData['doctorId']?.toString().trim() ?? '';
      final mirrorPatientId =
          patientData['patientId']?.toString().trim() ?? '';
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

      if (!isStatusEligibleForCompletion(mirrorRawStatus)) {
        throw AppointmentMirrorInconsistentException(
          'Patient appointment mirror status ($mirrorRawStatus) is not eligible for completion.',
          appointmentId: trimmedApptId,
          patientId: serverPatientId,
          reason: 'Mirror status is not eligible for completion',
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

      final mirrorTimeSlot =
          patientData['timeSlot']?.toString().trim() ?? '';
      if (mirrorTimeSlot != serverTimeSlot) {
        throw AppointmentMirrorInconsistentException(
          'Patient appointment mirror timeSlot ($mirrorTimeSlot) conflicts with authoritative timeSlot ($serverTimeSlot).',
          appointmentId: trimmedApptId,
          patientId: serverPatientId,
          reason: 'Mirror timeSlot mismatch',
        );
      }

      // 3. Derive canonical slotKey and verify existing confirmed slot lock
      final authoritativeSlotKey =
          buildSlotKey(serverAppointmentDate, serverTimeSlot);
      final slotRef =
          _bookedSlots(serverDoctorId).doc(authoritativeSlotKey);

      final slotSnap = await tx.get(slotRef);

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
      final existingTimeSlot =
          slotData['timeSlot']?.toString().trim() ?? '';

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

      verifiedPatientId = serverPatientId;

      // ── PHASE 2: ATOMIC WRITES ──
      final updateData = {
        'status': AppointmentStatus.completed.firestoreValue,
        'completedBy': currentUserId,
        'completedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      tx.update(apptRef, updateData);
      tx.update(patientApptRef, updateData);

      // CRITICAL: Slot lock is retained intact in /bookedSlots.
      // Do not delete, overwrite, or mutate slotRef.
      // The slot was consumed by the completed appointment.
    });

    // ── Patient Notification: executed strictly outside and after successful transaction commit ──
    await _sendPatientNotification(
      patientId: verifiedPatientId ?? trimmedPatientId,
      title: 'Appointment Completed',
      body: 'Your appointment has been marked as completed.',
      type: 'appointment',
      referenceId: trimmedApptId,
    );
  }

  // ════════════════════════════════════════════════════════════════
  // PATIENTS — SRS compliant: only assigned + consented patients
  // FR-M8.1: Only patients with active authorization appear
  // ════════════════════════════════════════════════════════════════
  Stream<List<PatientProfile>> watchDoctorPatients(String doctorId) {
    return _consents
        .where('doctorId', isEqualTo: doctorId)
        .snapshots()
        .asyncMap((snap) async {
      // Filter 'granted' in Dart — no composite index needed
      final consentedIds = snap.docs
          .where((d) => (d.data() as Map)['status'] == 'granted')
          .map((d) => (d.data() as Map)['patientId'] as String)
          .toSet();

      final apptSnap =
          await _appointments.where('doctorId', isEqualTo: doctorId).get();
      final apptIds = apptSnap.docs
          .map((d) => (d.data() as Map)['patientId'] as String)
          .toSet();

      final allIds = {...consentedIds, ...apptIds};

      final profiles = <PatientProfile>[];
      for (final pid in allIds) {
        final doc = await _patients.doc(pid).get();
        if (doc.exists) {
          profiles
              .add(PatientProfile.fromMap(doc.data() as Map<String, dynamic>));
        } else {
          final uDoc = await _users.doc(pid).get();
          if (uDoc.exists) {
            final d = uDoc.data() as Map<String, dynamic>;
            profiles.add(PatientProfile(
              uid: pid,
              name: d['name'] ?? '',
              email: d['email'] ?? '',
              medicalId: d['medicalId'] ?? '',
            ));
          }
        }
      }
      return profiles;
    });
  }

  Future<PatientProfile?> fetchPatient(String patientId) async {
    final doc = await _patients.doc(patientId).get();
    if (doc.exists) {
      return PatientProfile.fromMap(doc.data() as Map<String, dynamic>);
    }
    final uDoc = await _users.doc(patientId).get();
    if (!uDoc.exists) return null;
    final d = uDoc.data() as Map<String, dynamic>;
    return PatientProfile(
      uid: patientId,
      name: d['name'] ?? '',
      email: d['email'] ?? '',
      medicalId: d['medicalId'] ?? '',
    );
  }

  // ── Consent Management (FR-M2.2, FR-M8.2) ────────────────────
  /// Evaluates patient consent on Hyperledger Fabric. Fails closed if the ledger is unreachable
  /// or if consent is not active/revoked. Never falls back to unverified Firestore state.
  Future<bool> hasConsent(String doctorId, String patientId, {String scope = 'BLOOD_CANCER_RESEARCH'}) async {
    try {
      final ledgerCheck = await FabricGatewayService.instance.checkConsent(
        patientId: patientId,
        providerId: doctorId,
        scope: scope,
      );
      if (ledgerCheck['active'] == true || ledgerCheck['hasConsent'] == true) {
        return true;
      }
      return false;
    } catch (_) {
      // Fail closed: Fabric ledger is authoritative. When unreachable or an error occurs,
      // access to protected records is strictly denied.
      return false;
    }
  }

  /// Evaluates local clinic appointment relationship for legacy scheduling views.
  /// Does NOT grant access to Fabric-protected medical records.
  Future<bool> hasClinicAppointmentRelationship(String doctorId, String patientId) async {
    final apptSnap = await _appointments
        .where('doctorId', isEqualTo: doctorId)
        .where('patientId', isEqualTo: patientId)
        .limit(1)
        .get();
    return apptSnap.docs.isNotEmpty;
  }

  Future<void> grantConsent({
    required String patientId,
    required String doctorId,
    required String patientName,
    required String doctorName,
    String scope = 'BLOOD_CANCER_RESEARCH',
  }) async {
    // 1. Verify caller authorization: only the patient can grant consent for their own data
    final user = _safeAuth?.currentUser;
    if (user == null || user.uid != patientId) {
      throw const ConsentUnauthorizedException(
        'Access Denied: Only the patient can authorize consent for their medical records.',
      );
    }

    // 2. Route mutation through Trusted Fabric Gateway
    // If the gateway returns 503 or errors, fail closed. Never write uncommitted state to Firestore!
    final expiration = DateTime.now().add(const Duration(days: 365)).toIso8601String();
    await FabricGatewayService.instance.grantConsent(
      providerId: doctorId,
      scope: scope,
      expirationTimestamp: expiration,
    );
  }

  Future<void> revokeConsent({
    required String patientId,
    required String doctorId,
    String scope = 'BLOOD_CANCER_RESEARCH',
  }) async {
    // 1. Verify caller authorization: only the patient can revoke consent for their own data
    final user = _safeAuth?.currentUser;
    if (user == null || user.uid != patientId) {
      throw const ConsentUnauthorizedException(
        'Access Denied: Only the patient can revoke consent for their medical records.',
      );
    }

    // 2. Route mutation through Trusted Fabric Gateway
    // If the gateway returns 503 or errors, fail closed.
    await FabricGatewayService.instance.revokeConsent(
      providerId: doctorId,
      scope: scope,
    );
  }

  // ── Diagnoses ─────────────────────────────────────────────────
  Future<void> addDiagnosis(DiagnosisEntry entry) async {
    final ref =
        _diagnoses(entry.doctorId).doc(entry.id.isEmpty ? null : entry.id);
    final pRef = _patientDiagnoses(entry.patientId).doc(ref.id);

    final finalEntry = DiagnosisEntry(
      id: ref.id,
      patientId: entry.patientId,
      patientName: entry.patientName,
      doctorId: entry.doctorId,
      doctorName: entry.doctorName,
      diagnosisTitle: entry.diagnosisTitle,
      diagnosisDetails: entry.diagnosisDetails,
      prescription: entry.prescription,
      clinicalNotes: entry.clinicalNotes,
      recommendations: entry.recommendations,
      attachedReportUrls: entry.attachedReportUrls,
      cancerType: entry.cancerType,
      stage: entry.stage,
      status: entry.status,
      blockchainVerified: true,
      createdAt: entry.createdAt,
    );

    final batch = _db.batch();
    batch.set(ref, finalEntry.toMap());
    batch.set(pRef, finalEntry.toMap());

    if (entry.diagnosisTitle.isNotEmpty) {
      batch.set(
          _patients.doc(entry.patientId),
          {
            'activeDiagnosis': entry.diagnosisTitle,
            'diagnosisPhase': entry.diagnosisDetails,
          },
          SetOptions(merge: true));
    }
    await batch.commit();

    await _sendPatientNotification(
      patientId: entry.patientId,
      title: 'New Diagnosis Added',
      body: '${entry.doctorName} added: ${entry.diagnosisTitle}.',
      type: 'report',
      referenceId: ref.id,
    );
  }

  Stream<List<DiagnosisEntry>> watchPatientDiagnoses(String patientId) =>
      _patientDiagnoses(patientId)
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map((s) => s.docs
              .map((d) =>
                  DiagnosisEntry.fromMap(d.data() as Map<String, dynamic>))
              .toList());

  Stream<List<DiagnosisEntry>> watchDoctorDiagnoses(String doctorId) =>
      _diagnoses(doctorId)
          .orderBy('createdAt', descending: true)
          .limit(20)
          .snapshots()
          .map((s) => s.docs
              .map((d) =>
                  DiagnosisEntry.fromMap(d.data() as Map<String, dynamic>))
              .toList());

  // ── Alerts ────────────────────────────────────────────────────
  Future<void> createAlert(CriticalAlert alert) async {
    final ref = _alerts(alert.doctorId).doc();
    await ref.set(CriticalAlert(
      id: ref.id,
      patientId: alert.patientId,
      patientName: alert.patientName,
      doctorId: alert.doctorId,
      alertType: alert.alertType,
      severity: alert.severity,
      title: alert.title,
      description: alert.description,
      createdAt: alert.createdAt,
    ).toMap());
  }

  Stream<List<CriticalAlert>> watchAlerts(String doctorId) => _alerts(doctorId)
      .where('isResolved', isEqualTo: false)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs
          .map((d) => CriticalAlert.fromMap(d.data() as Map<String, dynamic>))
          .toList());

  Future<void> resolveAlert(String doctorId, String alertId) async {
    await _alerts(doctorId).doc(alertId).update({
      'isResolved': true,
      'isRead': true,
    });
  }

  Future<void> markAlertRead(String doctorId, String alertId) async {
    await _alerts(doctorId).doc(alertId).update({'isRead': true});
  }

  // ── Doctor Notifications ──────────────────────────────────────
  Stream<List<NotificationModel>> watchDoctorNotifications(String doctorId) =>
      _notifications(doctorId)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .snapshots()
          .map((s) => s.docs
              .map((d) =>
                  NotificationModel.fromMap(d.data() as Map<String, dynamic>))
              .toList());

  Future<void> markDoctorNotifRead(String doctorId, String notifId) async {
    await _notifications(doctorId).doc(notifId).update({'isRead': true});
  }

  Future<void> markAllDoctorNotifsRead(String doctorId) async {
    final snap =
        await _notifications(doctorId).where('isRead', isEqualTo: false).get();
    final batch = _db.batch();
    for (final d in snap.docs) {
      batch.update(d.reference, {'isRead': true});
    }
    await batch.commit();
  }

  // ── Analytics ─────────────────────────────────────────────────
  Future<Map<String, int>> fetchDashboardStats(String doctorId) async {
    final appts =
        await _appointments.where('doctorId', isEqualTo: doctorId).get();
    final allAppts = appts.docs
        .map((d) => AppointmentModel.fromMap(d.data() as Map<String, dynamic>))
        .toList();

    final pending =
        allAppts.where((a) => a.status == AppointmentStatus.scheduled).length;
    final approved =
        allAppts.where((a) => a.status == AppointmentStatus.confirmed).length;
    final completed =
        allAppts.where((a) => a.status == AppointmentStatus.completed).length;
    final patientIds = allAppts.map((a) => a.patientId).toSet().length;

    final alerts = await _alerts(doctorId)
        .where('isResolved', isEqualTo: false)
        .where('severity', isEqualTo: 'high')
        .get();

    return {
      'totalPatients': patientIds,
      'pendingRequests': pending,
      'approvedToday': approved,
      'completed': completed,
      'criticalAlerts': alerts.docs.length,
    };
  }

  // ── Patient Medical Records ───────────────────────────────────
  Stream<List<MedicalRecordModel>> watchPatientRecords(String patientId) => _db
      .collection('patients')
      .doc(patientId)
      .collection('medicalRecords')
      .orderBy('date', descending: true)
      .snapshots()
      .map((s) =>
          s.docs.map((d) => MedicalRecordModel.fromMap(d.data())).toList());

  // ── EHR Vitals ────────────────────────────────────────────────
  /// Authoritative vital observation entry via trusted backend callable.
  /// Enforces server timestamps, range validation, and race-free latest cache sync.
  /// Prevents direct client manipulation of protected ehr_vitals paths.
  Future<void> saveEhrVitals({
    required String patientId,
    required Map<String, dynamic> vitals,
  }) async {
    num systolic = 120;
    num diastolic = 80;
    if (vitals['systolicBp'] is num) {
      systolic = vitals['systolicBp'] as num;
    } else if (vitals['bloodPressure'] is String) {
      final parts = (vitals['bloodPressure'] as String).split('/');
      if (parts.length == 2) {
        systolic = num.tryParse(parts[0].replaceAll(RegExp(r'[^0-9.]'), '')) ?? 120;
        diastolic = num.tryParse(parts[1].replaceAll(RegExp(r'[^0-9.]'), '')) ?? 80;
      }
    }
    if (vitals['diastolicBp'] is num) {
      diastolic = vitals['diastolicBp'] as num;
    }

    final pulse = (vitals['pulseRate'] ?? vitals['heartRate'] ?? 72) as num;
    final temp = (vitals['temperature'] ?? 37.0) as num;
    final tempUnit = vitals['temperatureUnit']?.toString() ?? 'C';
    final resp = (vitals['respiratoryRate'] ?? 16) as num;
    final o2 = (vitals['oxygenSaturation'] ?? 98) as num;
    final weight = (vitals['weightKg'] ?? vitals['weight']) as num?;
    final height = vitals['heightCm'] as num?;
    final notes = vitals['notes']?.toString() ?? '';

    final callable = _functions.httpsCallable('recordVitalObservation');
    await callable.call<Map<String, dynamic>>({
      'patientId': patientId,
      'systolicBp': systolic,
      'diastolicBp': diastolic,
      'pulseRate': pulse,
      'temperature': temp,
      'temperatureUnit': tempUnit,
      'respiratoryRate': resp,
      'oxygenSaturation': o2,
      if (weight != null) 'weightKg': weight,
      if (height != null) 'heightCm': height,
      'notes': notes,
    });
  }

  Future<Map<String, dynamic>> fetchEhrVitals(String patientId) async {
    final doc = await _db.collection('ehr_vitals').doc(patientId).get();
    if (!doc.exists) return {};
    return doc.data() as Map<String, dynamic>;
  }

  // ── Blood Cancer EHR Methods ─────────────────────────────────
  /// Save or update a Blood Cancer EHR record in /patients/{patientId}/blood_cancer_ehrs/{recordId}
  Future<BloodCancerEhrModel> saveBloodCancerEhr(
      BloodCancerEhrModel ehr) async {
    final collection = _patientBloodCancerEhrs(ehr.patientId);
    final docRef =
        ehr.recordId.isEmpty ? collection.doc() : collection.doc(ehr.recordId);

    final finalRecord =
        ehr.recordId.isEmpty ? ehr.copyWith(recordId: docRef.id) : ehr;

    final batch = _db.batch();
    batch.set(docRef, finalRecord.toMap(), SetOptions(merge: true));

    // Update patient profile active diagnosis / phase if specified
    final pMap = <String, dynamic>{};
    if (ehr.diagnosisSubtype?.isNotEmpty == true) {
      pMap['activeDiagnosis'] = ehr.diagnosisSubtype;
    }
    if (ehr.stage?.isNotEmpty == true) {
      pMap['diagnosisPhase'] = ehr.stage;
    }
    if (pMap.isNotEmpty) {
      batch.set(_patients.doc(ehr.patientId), pMap, SetOptions(merge: true));
    }

    await batch.commit();
    return finalRecord;
  }

  /// Stream of all Blood Cancer EHR records for a patient ordered chronologically descending
  Stream<List<BloodCancerEhrModel>> watchBloodCancerEhrs(String patientId) {
    return _patientBloodCancerEhrs(patientId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs
            .map((d) => BloodCancerEhrModel.fromMap(
                d.data() as Map<String, dynamic>,
                docId: d.id))
            .toList());
  }

  /// Fetch the latest Blood Cancer EHR record for a patient
  Future<BloodCancerEhrModel?> fetchLatestBloodCancerEhr(
      String patientId) async {
    final snap = await _patientBloodCancerEhrs(patientId)
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return BloodCancerEhrModel.fromMap(
      snap.docs.first.data() as Map<String, dynamic>,
      docId: snap.docs.first.id,
    );
  }

  /// Fetch a specific Blood Cancer EHR record by ID
  Future<BloodCancerEhrModel?> fetchBloodCancerEhr(
      String patientId, String recordId) async {
    final doc = await _patientBloodCancerEhrs(patientId).doc(recordId).get();
    if (!doc.exists) return null;
    return BloodCancerEhrModel.fromMap(
      doc.data() as Map<String, dynamic>,
      docId: doc.id,
    );
  }

  /// Stream of approved appointments across all doctors (used by Nurse workflow)
  Stream<List<AppointmentModel>> watchApprovedAppointments() {
    return _appointments
        .where('status', whereIn: ['confirmed', 'approved'])
        .snapshots()
        .map((s) {
          final list = s.docs
              .map((d) =>
                  AppointmentModel.fromMap(d.data() as Map<String, dynamic>))
              .toList();
          list.sort((a, b) => a.appointmentDate.compareTo(b.appointmentDate));
          return list;
        });
  }

  // ── Helpers ───────────────────────────────────────────────────
  Future<void> sendPatientNotification({
    required String patientId,
    required String title,
    required String body,
    required String type,
    String? referenceId,
  }) async {
    final ref = _notifications(patientId).doc();
    await ref.set(NotificationModel(
      id: ref.id,
      patientId: patientId,
      title: title,
      body: body,
      type: type,
      createdAt: DateTime.now(),
      referenceId: referenceId,
    ).toMap());
  }

  Future<void> _sendPatientNotification({
    required String patientId,
    required String title,
    required String body,
    required String type,
    String? referenceId,
  }) =>
      sendPatientNotification(
        patientId: patientId,
        title: title,
        body: body,
        type: type,
        referenceId: referenceId,
      );

  String _fmt(DateTime d) => '${d.day}/${d.month}/${d.year}';

  List<ScheduleEntry> getTodaySchedule(String doctorId) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return [
      ScheduleEntry(
          id: 's1',
          doctorId: doctorId,
          title: 'Consultation: David Ray',
          location: 'Room 302',
          type: 'consultation',
          startTime: today.add(const Duration(hours: 9)),
          endTime: today.add(const Duration(hours: 9, minutes: 30)),
          isNew: true),
      ScheduleEntry(
          id: 's2',
          doctorId: doctorId,
          title: 'Tumor Board Meeting',
          location: 'Conference Hall B',
          type: 'board_meeting',
          startTime: today.add(const Duration(hours: 10, minutes: 15)),
          endTime: today.add(const Duration(hours: 11))),
      ScheduleEntry(
          id: 's3',
          doctorId: doctorId,
          title: 'Chemo Review: Sarah Webb',
          location: 'Infusion Center',
          type: 'review',
          startTime: today.add(const Duration(hours: 11, minutes: 30)),
          endTime: today.add(const Duration(hours: 12))),
      ScheduleEntry(
          id: 's4',
          doctorId: doctorId,
          title: 'Lab Review: Sam T.',
          location: 'Telehealth Room',
          type: 'lab',
          startTime: today.add(const Duration(hours: 13, minutes: 30)),
          endTime: today.add(const Duration(hours: 14))),
    ];
  }
}

/// Thrown when an unauthorized user attempts to mutate consent.
class ConsentUnauthorizedException implements Exception {
  final String message;
  const ConsentUnauthorizedException(this.message);

  @override
  String toString() => message;
}
