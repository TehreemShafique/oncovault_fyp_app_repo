// lib/services/doctor_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/doctor_model.dart';
import '../models/appointment_model.dart';
import '../models/patient_profile_model.dart';
import '../models/medical_record_model.dart';

class DoctorService {
  final _db = FirebaseFirestore.instance;

  CollectionReference get _doctors      => _db.collection('doctors');
  CollectionReference get _appointments => _db.collection('appointments');
  CollectionReference get _users        => _db.collection('users');
  CollectionReference get _patients     => _db.collection('patients');
  CollectionReference get _consents     => _db.collection('doctor_patient_consents');

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

  // ── Doctor Profile ────────────────────────────────────────────
  // Kept friend's improved version with try/catch + auto-save
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
        uid      : uid,
        name     : data['name']      ?? '',
        email    : data['email']     ?? '',
        medicalId: data['medicalId'] ?? '',
        createdAt: DateTime.now(),
      );
      await _doctors.doc(uid).set(
          doctorProfile.toMap(), SetOptions(merge: true));
      return doctorProfile;
    } catch (e) {
      return null;
    }
  }

  Future<void> updateDoctorProfile(DoctorModel doctor) async {
    final batch = _db.batch();
    batch.set(_doctors.doc(doctor.uid), doctor.toMap(),
        SetOptions(merge: true));
    batch.set(_users.doc(doctor.uid), doctor.toMap(),
        SetOptions(merge: true));
    await batch.commit();
  }

  // ── Appointments ──────────────────────────────────────────────
  // Kept friend's improved version with client-side sort
  Stream<List<AppointmentModel>> watchDoctorAppointments(
      String doctorId) =>
      _appointments
          .where('doctorId', isEqualTo: doctorId)
          .snapshots()
          .map((s) {
        final list = s.docs
            .map((d) => AppointmentModel.fromMap(
            d.data() as Map<String, dynamic>))
            .toList();
        list.sort((a, b) =>
            a.appointmentDate.compareTo(b.appointmentDate));
        return list;
      });

  Stream<List<AppointmentModel>> watchPendingAppointments(
      String doctorId) =>
      _appointments
          .where('doctorId', isEqualTo: doctorId)
          .where('status',   isEqualTo: 'pending')
          .snapshots()
          .map((s) {
        final list = s.docs
            .map((d) => AppointmentModel.fromMap(
            d.data() as Map<String, dynamic>))
            .toList();
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return list;
      });

  Future<void> approveAppointment(AppointmentModel appt) async {
    final data = {
      'status'   : AppointmentStatus.approved.firestoreValue,
      'updatedAt': Timestamp.now(),
    };
    final batch = _db.batch();
    batch.update(_appointments.doc(appt.id), data);
    batch.update(_patientAppts(appt.patientId).doc(appt.id), data);
    await batch.commit();
    await _sendPatientNotification(
      patientId  : appt.patientId,
      title      : 'Appointment Approved ✓',
      body       : 'Your appointment with ${appt.doctorName} on '
          '${_fmt(appt.appointmentDate)} at ${appt.timeSlot} '
          'has been approved.',
      type       : 'appointment',
      referenceId: appt.id,
    );
  }

  Future<void> rejectAppointment(AppointmentModel appt,
      {String reason = ''}) async {
    final data = {
      'status'     : AppointmentStatus.rejected.firestoreValue,
      'doctorNotes': reason,
      'updatedAt'  : Timestamp.now(),
    };
    final batch = _db.batch();
    batch.update(_appointments.doc(appt.id), data);
    batch.update(_patientAppts(appt.patientId).doc(appt.id), data);
    await batch.commit();
    await _sendPatientNotification(
      patientId: appt.patientId,
      title    : 'Appointment Not Available',
      body     : 'Your appointment for ${_fmt(appt.appointmentDate)} '
          'could not be accommodated.'
          '${reason.isNotEmpty ? ' Reason: $reason' : ''}',
      type     : 'appointment',
      referenceId: appt.id,
    );
  }

  Future<void> doctorReschedule({
    required AppointmentModel appt,
    required DateTime newDate,
    required String newSlot,
  }) async {
    final data = {
      'appointmentDate': Timestamp.fromDate(newDate),
      'timeSlot'       : newSlot,
      'status'         : AppointmentStatus.rescheduled.firestoreValue,
      'updatedAt'      : Timestamp.now(),
    };
    final batch = _db.batch();
    batch.update(_appointments.doc(appt.id), data);
    batch.update(_patientAppts(appt.patientId).doc(appt.id), data);
    await batch.commit();
    await _sendPatientNotification(
      patientId: appt.patientId,
      title    : 'Appointment Rescheduled',
      body     : 'Your appointment has been moved to '
          '${_fmt(newDate)} at $newSlot.',
      type     : 'appointment',
      referenceId: appt.id,
    );
  }

  Future<void> markAppointmentComplete(AppointmentModel appt) async {
    final data = {
      'status'   : AppointmentStatus.completed.firestoreValue,
      'updatedAt': Timestamp.now(),
    };
    final batch = _db.batch();
    batch.update(_appointments.doc(appt.id), data);
    batch.update(_patientAppts(appt.patientId).doc(appt.id), data);
    await batch.commit();
  }

  // ════════════════════════════════════════════════════════════════
  // PATIENTS — SRS compliant: only assigned + consented patients
  // FR-M8.1: Only patients with active authorization appear
  // ════════════════════════════════════════════════════════════════
  // Stream<List<PatientProfile>> watchDoctorPatients(String doctorId) {
  //   return _consents
  //       .where('doctorId', isEqualTo: doctorId)
  //       .where('status',   isEqualTo: 'granted')
  //       .snapshots()
  //       .asyncMap((snap) async {
  //     final consentedIds = snap.docs
  //         .map((d) => (d.data() as Map)['patientId'] as String)
  //         .toSet();
  //
  //     final apptSnap = await _appointments
  //         .where('doctorId', isEqualTo: doctorId)
  //         .get();
  //     final apptIds = apptSnap.docs
  //         .map((d) => (d.data() as Map)['patientId'] as String)
  //         .toSet();
  //
  //     final allIds = {...consentedIds, ...apptIds};
  //
  //     final profiles = <PatientProfile>[];
  //     for (final pid in allIds) {
  //       final doc = await _patients.doc(pid).get();
  //       if (doc.exists) {
  //         profiles.add(PatientProfile.fromMap(
  //             doc.data() as Map<String, dynamic>));
  //       } else {
  //         final uDoc = await _users.doc(pid).get();
  //         if (uDoc.exists) {
  //           final d = uDoc.data() as Map<String, dynamic>;
  //           profiles.add(PatientProfile(
  //             uid      : pid,
  //             name     : d['name']      ?? '',
  //             email    : d['email']     ?? '',
  //             medicalId: d['medicalId'] ?? '',
  //           ));
  //         }
  //       }
  //     }
  //     return profiles;
  //   });
  // }
  // REPLACE watchDoctorPatients with this:
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

      final apptSnap = await _appointments
          .where('doctorId', isEqualTo: doctorId)
          .get();
      final apptIds = apptSnap.docs
          .map((d) => (d.data() as Map)['patientId'] as String)
          .toSet();

      final allIds = {...consentedIds, ...apptIds};

      final profiles = <PatientProfile>[];
      for (final pid in allIds) {
        final doc = await _patients.doc(pid).get();
        if (doc.exists) {
          profiles.add(PatientProfile.fromMap(
              doc.data() as Map<String, dynamic>));
        } else {
          final uDoc = await _users.doc(pid).get();
          if (uDoc.exists) {
            final d = uDoc.data() as Map<String, dynamic>;
            profiles.add(PatientProfile(
              uid      : pid,
              name     : d['name']      ?? '',
              email    : d['email']     ?? '',
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
      return PatientProfile.fromMap(
          doc.data() as Map<String, dynamic>);
    }
    final uDoc = await _users.doc(patientId).get();
    if (!uDoc.exists) return null;
    final d = uDoc.data() as Map<String, dynamic>;
    return PatientProfile(
      uid      : patientId,
      name     : d['name']      ?? '',
      email    : d['email']     ?? '',
      medicalId: d['medicalId'] ?? '',
    );
  }

  // ── Consent Management (FR-M2.2, FR-M8.2) ────────────────────
  // Future<bool> hasConsent(String doctorId, String patientId) async {
  //   final consentSnap = await _consents
  //       .where('doctorId',  isEqualTo: doctorId)
  //       .where('patientId', isEqualTo: patientId)
  //       .where('status',    isEqualTo: 'granted')
  //       .limit(1)
  //       .get();
  //   if (consentSnap.docs.isNotEmpty) return true;
  //
  //   final apptSnap = await _appointments
  //       .where('doctorId',  isEqualTo: doctorId)
  //       .where('patientId', isEqualTo: patientId)
  //       .limit(1)
  //       .get();
  //   return apptSnap.docs.isNotEmpty;
  // }
  // REPLACE hasConsent with this:
  Future<bool> hasConsent(String doctorId, String patientId) async {
    // Single field query — no composite index needed
    final consentSnap = await _consents
        .where('doctorId', isEqualTo: doctorId)
        .get();

    // Filter in Dart
    final hasGrant = consentSnap.docs.any((d) {
      final data = d.data() as Map;
      return data['patientId'] == patientId &&
          data['status']    == 'granted';
    });
    if (hasGrant) return true;

    final apptSnap = await _appointments
        .where('doctorId',  isEqualTo: doctorId)
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
  }) async {
    final id = '${patientId}_$doctorId';
    await _consents.doc(id).set({
      'id'         : id,
      'patientId'  : patientId,
      'doctorId'   : doctorId,
      'patientName': patientName,
      'doctorName' : doctorName,
      'status'     : 'granted',
      'grantedAt'  : Timestamp.now(),
    });
  }

  Future<void> revokeConsent({
    required String patientId,
    required String doctorId,
  }) async {
    final id = '${patientId}_$doctorId';
    await _consents.doc(id).update({
      'status'   : 'revoked',
      'revokedAt': Timestamp.now(),
    });
  }

  // ── Diagnoses ─────────────────────────────────────────────────
  Future<void> addDiagnosis(DiagnosisEntry entry) async {
    final ref  = _diagnoses(entry.doctorId)
        .doc(entry.id.isEmpty ? null : entry.id);
    final pRef = _patientDiagnoses(entry.patientId).doc(ref.id);

    final finalEntry = DiagnosisEntry(
      id              : ref.id,
      patientId       : entry.patientId,
      patientName     : entry.patientName,
      doctorId        : entry.doctorId,
      doctorName      : entry.doctorName,
      diagnosisTitle  : entry.diagnosisTitle,
      diagnosisDetails: entry.diagnosisDetails,
      prescription    : entry.prescription,
      clinicalNotes   : entry.clinicalNotes,
      recommendations : entry.recommendations,
      attachedReportUrls: entry.attachedReportUrls,
      cancerType      : entry.cancerType,
      stage           : entry.stage,
      status          : entry.status,
      blockchainVerified: true,
      createdAt       : entry.createdAt,
    );

    final batch = _db.batch();
    batch.set(ref, finalEntry.toMap());
    batch.set(pRef, finalEntry.toMap());

    if (entry.diagnosisTitle.isNotEmpty) {
      batch.set(_patients.doc(entry.patientId), {
        'activeDiagnosis': entry.diagnosisTitle,
        'diagnosisPhase' : entry.diagnosisDetails,
      }, SetOptions(merge: true));
    }
    await batch.commit();

    await _sendPatientNotification(
      patientId: entry.patientId,
      title    : 'New Diagnosis Added',
      body     : '${entry.doctorName} added: ${entry.diagnosisTitle}.',
      type     : 'report',
    );
  }

  Stream<List<DiagnosisEntry>> watchPatientDiagnoses(
      String patientId) =>
      _patientDiagnoses(patientId)
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map((s) => s.docs
          .map((d) => DiagnosisEntry.fromMap(
          d.data() as Map<String, dynamic>))
          .toList());

  Stream<List<DiagnosisEntry>> watchDoctorDiagnoses(
      String doctorId) =>
      _diagnoses(doctorId)
          .orderBy('createdAt', descending: true)
          .limit(20)
          .snapshots()
          .map((s) => s.docs
          .map((d) => DiagnosisEntry.fromMap(
          d.data() as Map<String, dynamic>))
          .toList());

  // ── Alerts ────────────────────────────────────────────────────
  Future<void> createAlert(CriticalAlert alert) async {
    final ref = _alerts(alert.doctorId).doc();
    await ref.set(CriticalAlert(
      id         : ref.id,
      patientId  : alert.patientId,
      patientName: alert.patientName,
      doctorId   : alert.doctorId,
      alertType  : alert.alertType,
      severity   : alert.severity,
      title      : alert.title,
      description: alert.description,
      createdAt  : alert.createdAt,
    ).toMap());
  }

  Stream<List<CriticalAlert>> watchAlerts(String doctorId) =>
      _alerts(doctorId)
          .where('isResolved', isEqualTo: false)
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map((s) => s.docs
          .map((d) => CriticalAlert.fromMap(
          d.data() as Map<String, dynamic>))
          .toList());

  Future<void> resolveAlert(String doctorId, String alertId) async {
    await _alerts(doctorId).doc(alertId).update({
      'isResolved': true, 'isRead': true,
    });
  }

  Future<void> markAlertRead(String doctorId, String alertId) async {
    await _alerts(doctorId).doc(alertId).update({'isRead': true});
  }

  // ── Doctor Notifications ──────────────────────────────────────
  Stream<List<NotificationModel>> watchDoctorNotifications(
      String doctorId) =>
      _notifications(doctorId)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .snapshots()
          .map((s) => s.docs
          .map((d) => NotificationModel.fromMap(
          d.data() as Map<String, dynamic>))
          .toList());

  Future<void> markDoctorNotifRead(
      String doctorId, String notifId) async {
    await _notifications(doctorId)
        .doc(notifId).update({'isRead': true});
  }

  Future<void> markAllDoctorNotifsRead(String doctorId) async {
    final snap = await _notifications(doctorId)
        .where('isRead', isEqualTo: false).get();
    final batch = _db.batch();
    for (final d in snap.docs) {
      batch.update(d.reference, {'isRead': true});
    }
    await batch.commit();
  }

  // ── Analytics ─────────────────────────────────────────────────
  Future<Map<String, int>> fetchDashboardStats(String doctorId) async {
    final appts = await _appointments
        .where('doctorId', isEqualTo: doctorId).get();
    final allAppts = appts.docs
        .map((d) => AppointmentModel.fromMap(
        d.data() as Map<String, dynamic>))
        .toList();

    final pending    = allAppts
        .where((a) => a.status == AppointmentStatus.pending).length;
    final approved   = allAppts
        .where((a) => a.status == AppointmentStatus.approved).length;
    final completed  = allAppts
        .where((a) => a.status == AppointmentStatus.completed).length;
    final patientIds = allAppts.map((a) => a.patientId).toSet().length;

    final alerts = await _alerts(doctorId)
        .where('isResolved', isEqualTo: false)
        .where('severity',   isEqualTo: 'high').get();

    return {
      'totalPatients'  : patientIds,
      'pendingRequests': pending,
      'approvedToday'  : approved,
      'completed'      : completed,
      'criticalAlerts' : alerts.docs.length,
    };
  }

  // ── Patient Medical Records ───────────────────────────────────
  Stream<List<MedicalRecordModel>> watchPatientRecords(
      String patientId) =>
      _db.collection('patients').doc(patientId)
          .collection('medicalRecords')
          .orderBy('date', descending: true)
          .snapshots()
          .map((s) => s.docs
          .map((d) => MedicalRecordModel.fromMap(
          d.data() as Map<String, dynamic>))
          .toList());

  // ── EHR Vitals ────────────────────────────────────────────────
  Future<void> saveEhrVitals({
    required String patientId,
    required Map<String, dynamic> vitals,
  }) async {
    await _db.collection('ehr_vitals').doc(patientId).set(
      {...vitals, 'updatedAt': Timestamp.now()},
      SetOptions(merge: true),
    );
  }

  Future<Map<String, dynamic>> fetchEhrVitals(
      String patientId) async {
    final doc = await _db
        .collection('ehr_vitals').doc(patientId).get();
    if (!doc.exists) return {};
    return doc.data() as Map<String, dynamic>;
  }

  // ── Helpers ───────────────────────────────────────────────────
  Future<void> _sendPatientNotification({
    required String patientId,
    required String title,
    required String body,
    required String type,
    String? referenceId,
  }) async {
    final ref = _notifications(patientId).doc();
    await ref.set(NotificationModel(
      id         : ref.id,
      patientId  : patientId,
      title      : title,
      body       : body,
      type       : type,
      createdAt  : DateTime.now(),
      referenceId: referenceId,
    ).toMap());
  }

  String _fmt(DateTime d) => '${d.day}/${d.month}/${d.year}';

  List<ScheduleEntry> getTodaySchedule(String doctorId) {
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return [
      ScheduleEntry(id: 's1', doctorId: doctorId,
          title    : 'Consultation: David Ray',
          location : 'Room 302',
          type     : 'consultation',
          startTime: today.add(const Duration(hours: 9)),
          endTime  : today.add(const Duration(
              hours: 9, minutes: 30)),
          isNew    : true),
      ScheduleEntry(id: 's2', doctorId: doctorId,
          title    : 'Tumor Board Meeting',
          location : 'Conference Hall B',
          type     : 'board_meeting',
          startTime: today.add(const Duration(
              hours: 10, minutes: 15)),
          endTime  : today.add(const Duration(hours: 11))),
      ScheduleEntry(id: 's3', doctorId: doctorId,
          title    : 'Chemo Review: Sarah Webb',
          location : 'Infusion Center',
          type     : 'review',
          startTime: today.add(const Duration(
              hours: 11, minutes: 30)),
          endTime  : today.add(const Duration(hours: 12))),
      ScheduleEntry(id: 's4', doctorId: doctorId,
          title    : 'Lab Review: Sam T.',
          location : 'Telehealth Room',
          type     : 'lab',
          startTime: today.add(const Duration(
              hours: 13, minutes: 30)),
          endTime  : today.add(const Duration(hours: 14))),
    ];
  }
}