// lib/services/appointment_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/appointment_model.dart';
import '../models/medical_record_model.dart';

class AppointmentService {
  final _db = FirebaseFirestore.instance;

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

  // ── Slot Key Helper ───────────────────────────────────────────
  // Produces a deterministic key from a date + time slot string.
  // e.g. date=2025-06-15, slot="09:30 AM"  →  "2025-06-15_09:30 AM"
  String _slotKey(DateTime date, String timeSlot) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '${y}-${m}-${d}_$timeSlot';
  }

  // ── Check if a slot is booked ─────────────────────────────────
  /// Returns true when the slot is already taken (approved appointment exists).
  Future<bool> isSlotBooked(String doctorId, DateTime date, String timeSlot) async {
    final key = _slotKey(date, timeSlot);
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
      id:               ref.id,
      patientId:        patientId,
      patientName:      patientName,
      doctorId:         doctorId,
      doctorName:       doctorName,
      doctorSpecialty:  doctorSpecialty,
      appointmentDate:  appointmentDate,
      timeSlot:         timeSlot,
      durationMinutes:  durationMinutes,
      status:           AppointmentStatus.pending,
      notes:            notes,
      createdAt:        DateTime.now(),
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
      body:  'Your appointment with $doctorName on ${_fmtDate(appointmentDate)} at $timeSlot is pending approval.',
      type:  'appointment',
      referenceId: ref.id,
    );

    return appt;
  }

  // ── Cancel Appointment ────────────────────────────────────────
  Future<void> cancelAppointment(String appointmentId, String patientId) async {
    // Fetch the appointment so we can free its slot if it was approved.
    final apptDoc = await _appointments.doc(appointmentId).get();
    AppointmentModel? appt;
    if (apptDoc.exists) {
      appt = AppointmentModel.fromMap(apptDoc.data() as Map<String, dynamic>);
    }

    final data = {
      'status':    AppointmentStatus.cancelled.firestoreValue,
      'updatedAt': Timestamp.now(),
    };
    final batch = _db.batch();
    batch.update(_appointments.doc(appointmentId), data);
    batch.update(_patientAppts(patientId).doc(appointmentId), data);

    // Free the booked slot if it was previously approved.
    if (appt != null && appt.status == AppointmentStatus.approved && appt.doctorId.isNotEmpty) {
      final key = _slotKey(appt.appointmentDate, appt.timeSlot);
      batch.delete(_bookedSlots(appt.doctorId).doc(key));
    }

    await batch.commit();

    await _createNotification(
      patientId:   patientId,
      title:       'Appointment Cancelled',
      body:        'Your appointment has been successfully cancelled.',
      type:        'appointment',
      referenceId: appointmentId,
    );
  }

  // ── Reschedule Appointment (by Patient) ───────────────────────
  // FEATURE: Status is reset to PENDING so the doctor must re-approve.
  // If the old appointment was already approved, its booked slot is freed.
  Future<void> rescheduleAppointment({
    required String appointmentId,
    required String patientId,
    required DateTime newDate,
    required String newTimeSlot,
    // Pass these so we can free the old slot when it was approved.
    String doctorId = '',
    DateTime? oldDate,
    String oldTimeSlot = '',
    AppointmentStatus oldStatus = AppointmentStatus.pending,
  }) async {
    final data = {
      'appointmentDate': Timestamp.fromDate(newDate),
      'timeSlot':        newTimeSlot,
      // Reset to PENDING — doctor must re-approve the new date/time.
      'status':          AppointmentStatus.pending.firestoreValue,
      'updatedAt':       Timestamp.now(),
    };

    final batch = _db.batch();
    batch.update(_appointments.doc(appointmentId), data);
    batch.update(_patientAppts(patientId).doc(appointmentId), data);

    // If the appointment was approved, release the old booked slot.
    if (oldStatus == AppointmentStatus.approved &&
        doctorId.isNotEmpty &&
        oldDate != null &&
        oldTimeSlot.isNotEmpty) {
      final oldKey = _slotKey(oldDate, oldTimeSlot);
      batch.delete(_bookedSlots(doctorId).doc(oldKey));
    }

    await batch.commit();

    await _createNotification(
      patientId:   patientId,
      title:       'Appointment Rescheduled — Awaiting Approval',
      body:        'Your appointment has been rescheduled to ${_fmtDate(newDate)} at $newTimeSlot. The doctor must approve the new time.',
      type:        'appointment',
      referenceId: appointmentId,
    );
  }

  // ── Fetch Patient Appointments ────────────────────────────────
  Stream<List<AppointmentModel>> watchPatientAppointments(String patientId) =>
      _patientAppts(patientId)
          .snapshots()
          .map((s) {
        final list = s.docs
            .map((d) => AppointmentModel.fromMap(d.data() as Map<String, dynamic>))
            .toList();
        list.sort((a, b) => a.appointmentDate.compareTo(b.appointmentDate));
        return list;
      });

  Future<List<AppointmentModel>> getPatientAppointments(String patientId) async {
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
          .map((d) => NotificationModel.fromMap(d.data() as Map<String, dynamic>))
          .toList());

  Future<void> markNotificationRead(String patientId, String notifId) async {
    await _notifications(patientId).doc(notifId).update({'isRead': true});
  }

  Future<void> markAllRead(String patientId) async {
    final snap = await _notifications(patientId).where('isRead', isEqualTo: false).get();
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
      id: ref.id, patientId: patientId,
      title: title, body: body, type: type,
      createdAt: DateTime.now(), referenceId: referenceId,
    );
    await ref.set(notif.toMap());
  }

  String _fmtDate(DateTime d) => '${d.day}/${d.month}/${d.year}';
}

class MedicalRecordService {
  final _db = FirebaseFirestore.instance;

  CollectionReference _records(String uid) =>
      _db.collection('patients').doc(uid).collection('medicalRecords');

  Stream<List<MedicalRecordModel>> watchRecords(String patientId, {RecordType? type}) {
    Query q = _records(patientId).orderBy('date', descending: true);
    if (type != null) q = q.where('type', isEqualTo: type.firestoreValue);
    return q.snapshots().map((s) => s.docs
        .map((d) => MedicalRecordModel.fromMap(d.data() as Map<String, dynamic>))
        .toList());
  }

  Future<void> addRecord(MedicalRecordModel record) async {
    final ref = _records(record.patientId).doc(record.id.isEmpty ? null : record.id);
    await ref.set(record.toMap());
  }

  // Seed sample records for a new patient (called after signup)
  Future<void> seedSampleRecords(String patientId, String patientName) async {
    final now = DateTime.now();
    final samples = [
      MedicalRecordModel(
        id: 'rec_001_$patientId', patientId: patientId,
        title: 'MRI Scan - Lumbar Spine', type: RecordType.report, subtype: 'Imaging',
        facility: 'Radiology Center East', doctorName: 'Dr. Aris Thorne',
        date: now.subtract(const Duration(days: 13)),
        fileType: 'pdf', summary: 'No acute abnormality detected.',
        uploadedAt: now.subtract(const Duration(days: 13)),
      ),
      MedicalRecordModel(
        id: 'rec_002_$patientId', patientId: patientId,
        title: 'Complete Blood Count (CBC)', type: RecordType.report, subtype: 'Pathology',
        facility: 'City Oncology Lab', doctorName: 'Dr. Elena Vance',
        date: now.subtract(const Duration(days: 25)),
        fileType: 'pdf', summary: 'WBC: Normal, RBC: Slightly low.',
        uploadedAt: now.subtract(const Duration(days: 25)),
      ),
      MedicalRecordModel(
        id: 'rec_003_$patientId', patientId: patientId,
        title: 'Oncology Consultation Summary', type: RecordType.report, subtype: 'Clinical Notes',
        facility: 'OncoVault Medical Center', doctorName: 'Dr. Sarah Jenkins',
        date: now.subtract(const Duration(days: 49)),
        fileType: 'pdf', summary: 'Patient responding well to current protocol.',
        uploadedAt: now.subtract(const Duration(days: 49)),
      ),
      MedicalRecordModel(
        id: 'rec_004_$patientId', patientId: patientId,
        title: 'Hormone Therapy - Phase 2', type: RecordType.medicalHistory, subtype: 'Treatment',
        facility: 'OncoVault Medical Center', doctorName: 'Dr. Aris Thorne',
        date: now.subtract(const Duration(days: 60)),
        fileType: 'text',
        summary: 'Progressing according to treatment plan. Current cycle focuses on stabilization and long-term monitoring.',
        uploadedAt: now.subtract(const Duration(days: 60)),
      ),
    ];
    for (final r in samples) await addRecord(r);
  }
}