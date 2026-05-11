// lib/services/appointment_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/appointment_model.dart';
import '../models/medical_record_model.dart';

class AppointmentService {
  final _db = FirebaseFirestore.instance;

  // ── Collections ───────────────────────────────────────────────
  // /appointments/{id}         — all appointments (doctor module reads this)
  // /patients/{uid}/appointments/{id}  — subcollection for fast patient queries
  // /notifications/{patientId}/items/{id}

  CollectionReference get _appointments => _db.collection('appointments');
  CollectionReference _patientAppts(String uid) =>
      _db.collection('patients').doc(uid).collection('appointments');
  CollectionReference _notifications(String uid) =>
      _db.collection('notifications').doc(uid).collection('items');

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
    final data = {
      'status':    AppointmentStatus.cancelled.firestoreValue,
      'updatedAt': Timestamp.now(),
    };
    final batch = _db.batch();
    batch.update(_appointments.doc(appointmentId), data);
    batch.update(_patientAppts(patientId).doc(appointmentId), data);
    await batch.commit();

    await _createNotification(
      patientId:   patientId,
      title:       'Appointment Cancelled',
      body:        'Your appointment has been successfully cancelled.',
      type:        'appointment',
      referenceId: appointmentId,
    );
  }

  // ── Reschedule Appointment ────────────────────────────────────
  Future<void> rescheduleAppointment({
    required String appointmentId,
    required String patientId,
    required DateTime newDate,
    required String newTimeSlot,
  }) async {
    final data = {
      'appointmentDate': Timestamp.fromDate(newDate),
      'timeSlot':        newTimeSlot,
      'status':          AppointmentStatus.rescheduled.firestoreValue,
      'updatedAt':       Timestamp.now(),
    };
    final batch = _db.batch();
    batch.update(_appointments.doc(appointmentId), data);
    batch.update(_patientAppts(patientId).doc(appointmentId), data);
    await batch.commit();

    await _createNotification(
      patientId:   patientId,
      title:       'Appointment Rescheduled',
      body:        'Your appointment has been rescheduled to ${_fmtDate(newDate)} at $newTimeSlot. Awaiting doctor confirmation.',
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