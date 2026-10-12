// lib/services/appointment_exceptions.dart

/// Base domain exception for all appointment scheduling operations.
abstract class AppointmentException implements Exception {
  final String message;
  const AppointmentException(this.message);

  @override
  String toString() => message;
}

/// Thrown when attempting to approve, reserve, or occupy a slot that is already
/// occupied by another appointment.
class SlotAlreadyBookedException extends AppointmentException {
  final String slotKey;
  final String? conflictingAppointmentId;

  const SlotAlreadyBookedException(
    super.message, {
    required this.slotKey,
    this.conflictingAppointmentId,
  });
}

/// Thrown when an existing booked-slot document contains malformed or corrupt lock data.
class SlotLockCorruptException extends AppointmentException {
  final String slotKey;

  const SlotLockCorruptException(
    super.message, {
    required this.slotKey,
  });
}

/// Thrown when an appointment's current status prevents the requested operation
/// (e.g. attempting to approve an appointment that is already cancelled or confirmed).
class AppointmentStateConflictException extends AppointmentException {
  final String appointmentId;
  final String currentStatus;
  final String requiredStatus;

  const AppointmentStateConflictException(
    super.message, {
    required this.appointmentId,
    required this.currentStatus,
    required this.requiredStatus,
  });
}

/// Thrown when the target appointment document does not exist in Firestore.
class AppointmentNotFoundException extends AppointmentException {
  final String appointmentId;

  const AppointmentNotFoundException(
    super.message, {
    required this.appointmentId,
  });
}

/// Thrown when a user/doctor is not authorized to perform the operation on this appointment.
class AppointmentUnauthorizedException extends AppointmentException {
  final String appointmentId;

  const AppointmentUnauthorizedException(
    super.message, {
    required this.appointmentId,
  });
}

/// Thrown when the patient appointment mirror is missing or inconsistent with
/// the authoritative global appointment document.
class AppointmentMirrorInconsistentException extends AppointmentException {
  final String appointmentId;
  final String patientId;
  final String reason;

  const AppointmentMirrorInconsistentException(
    super.message, {
    required this.appointmentId,
    required this.patientId,
    required this.reason,
  });
}

/// Thrown when caller-supplied appointment details conflict with authoritative
/// stored appointment data (e.g. date, time slot, doctor ID, patient ID).
class AppointmentPayloadConflictException extends AppointmentException {
  final String appointmentId;
  final String field;
  final String expectedValue;
  final String actualValue;

  const AppointmentPayloadConflictException(
    super.message, {
    required this.appointmentId,
    required this.field,
    required this.expectedValue,
    required this.actualValue,
  });
}
