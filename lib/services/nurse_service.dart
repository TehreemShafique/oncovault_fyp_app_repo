// lib/services/nurse_service.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/vital_sign_model.dart';
import '../models/nurse_assignment_model.dart';
import '../models/clinical_note_model.dart';
import '../utils/vital_validator.dart';
import 'fabric_gateway_service.dart';

/// Exception thrown when a nurse is not actively authorized or assigned to a patient.
class NurseAuthorizationException implements Exception {
  final String message;
  final String? patientId;
  final String? nurseId;

  const NurseAuthorizationException(this.message, {this.patientId, this.nurseId});

  @override
  String toString() => 'NurseAuthorizationException: $message (patient: $patientId, nurse: $nurseId)';
}

/// Exception thrown when vital sign measurements fail validation.
class VitalValidationException extends ArgumentError {
  final String? field;

  VitalValidationException(super.message, {this.field});

  @override
  String toString() => message;
}

/// Primary service managing nurse care workflows, vital-sign observations,
/// nurse-patient assignments, and dashboard metrics.
class NurseService {
  final FirebaseFirestore? _customDb;
  final FirebaseFunctions? _customFunctions;
  final FirebaseAuth? _customAuth;
  final FabricGatewayService? _customFabricGateway;

  // Optional dependency injection hooks for unit/mock testing
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> data)? _customRecordCallable;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> data)? _customAssignCallable;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> data)? _customSaveNoteDraftCallable;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> data)? _customSubmitNoteCallable;

  NurseService({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    FirebaseAuth? auth,
    FabricGatewayService? fabricGateway,
    Future<Map<String, dynamic>> Function(Map<String, dynamic> data)? customRecordCallable,
    Future<Map<String, dynamic>> Function(Map<String, dynamic> data)? customAssignCallable,
    Future<Map<String, dynamic>> Function(Map<String, dynamic> data)? customSaveNoteDraftCallable,
    Future<Map<String, dynamic>> Function(Map<String, dynamic> data)? customSubmitNoteCallable,
  })  : _customDb = firestore,
        _customFunctions = functions,
        _customAuth = auth,
        _customFabricGateway = fabricGateway,
        _customRecordCallable = customRecordCallable,
        _customAssignCallable = customAssignCallable,
        _customSaveNoteDraftCallable = customSaveNoteDraftCallable,
        _customSubmitNoteCallable = customSubmitNoteCallable;

  FabricGatewayService get _fabricGateway => _customFabricGateway ?? FabricGatewayService.instance;

  FirebaseFirestore get _db => _customDb ?? FirebaseFirestore.instance;
  FirebaseFunctions get _functions => _customFunctions ?? FirebaseFunctions.instanceFor(region: 'us-central1');
  FirebaseAuth get _auth => _customAuth ?? FirebaseAuth.instance;

  String? get _currentNurseUid {
    try {
      return _auth.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  String? get _currentNurseName {
    try {
      return _auth.currentUser?.displayName;
    } catch (_) {
      return null;
    }
  }

  // ─── Collection References ───────────────────────────────────
  CollectionReference get _assignments => _db.collection('nurse_patient_assignments');
  CollectionReference get _ehrVitals => _db.collection('ehr_vitals');
  CollectionReference get _nurses => _db.collection('nurses');

  CollectionReference _observations(String patientId) =>
      _ehrVitals.doc(patientId).collection('observations');

  // ─── Timezone Utility (PKT UTC+05:00 Hospital Standard) ─────
  static String getTodayPktDateKey({DateTime? now}) {
    final effectiveNow = now ?? DateTime.now();
    final pktNow = effectiveNow.toUtc().add(const Duration(hours: 5));
    final y = pktNow.year.toString().padLeft(4, '0');
    final m = pktNow.month.toString().padLeft(2, '0');
    final d = pktNow.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Calculates the duration from [now] until the next 00:00:00 PKT (UTC+5).
  static Duration durationUntilNextPktMidnight({DateTime? now}) {
    final effectiveNow = now ?? DateTime.now();
    final pktNow = effectiveNow.toUtc().add(const Duration(hours: 5));
    final nextMidnightPktUtc = DateTime.utc(
      pktNow.year,
      pktNow.month,
      pktNow.day + 1,
      0,
      0,
      0,
      50, // 50ms buffer past midnight
    ).subtract(const Duration(hours: 5));

    final diff = nextMidnightPktUtc.difference(effectiveNow.toUtc());
    return diff.isNegative ? const Duration(seconds: 1) : diff;
  }

  /// Reactive stream that emits the current PKT date key ('YYYY-MM-DD') and schedules
  /// a timer to emit the new date key at exactly 00:00:00 PKT without polling.
  /// Supports injection of [clockStream] or [nowProvider] for deterministic testing.
  static Stream<String> pktDateKeyStream({
    DateTime Function()? nowProvider,
    Stream<DateTime>? clockStream,
  }) {
    if (clockStream != null) {
      return clockStream
          .map((dt) => getTodayPktDateKey(now: dt))
          .distinct();
    }

    late StreamController<String> controller;
    Timer? midnightTimer;

    void schedule() {
      final now = nowProvider != null ? nowProvider() : DateTime.now();
      final currentKey = getTodayPktDateKey(now: now);
      if (!controller.isClosed) {
        controller.add(currentKey);
      }
      final delay = durationUntilNextPktMidnight(now: now);
      midnightTimer = Timer(delay, () {
        if (!controller.isClosed) {
          schedule();
        }
      });
    }

    controller = StreamController<String>.broadcast(
      onListen: () {
        schedule();
      },
      onCancel: () {
        midnightTimer?.cancel();
      },
    );

    return controller.stream.distinct();
  }

  // ─── Nurse-Patient Assignment Management ──────────────────────

  /// Checks whether a specific nurse is actively assigned to care for [patientId].
  Future<bool> isNurseAssignedToPatient({
    required String nurseId,
    required String patientId,
  }) async {
    final assignmentId = '${nurseId}_$patientId';
    final doc = await _assignments.doc(assignmentId).get();
    if (!doc.exists) return false;
    final data = doc.data() as Map<String, dynamic>?;
    return (data?['status'] as String? ?? '').toLowerCase() == 'active';
  }

  /// Streams active patient assignments for [nurseId].
  Stream<List<NursePatientAssignment>> watchNurseAssignments(String nurseId) {
    return _assignments
        .where('nurseId', isEqualTo: nurseId)
        .where('status', isEqualTo: 'active')
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => NursePatientAssignment.fromMap(d.data() as Map<String, dynamic>, docId: d.id))
            .toList());
  }

  /// Establishes an authorized care assignment linking a nurse to a patient.
  /// Dispatches through trusted Cloud Function to prevent client self-assignment.
  Future<void> assignNurseToPatient({
    required String nurseId,
    required String patientId,
    String hospitalId = 'Oncology Ward 3A',
    String notes = '',
  }) async {
    try {
      if (_customAssignCallable != null) {
        await _customAssignCallable!({
          'nurseId': nurseId,
          'patientId': patientId,
          'hospitalId': hospitalId,
          'notes': notes,
        });
        return;
      }

      final callable = _functions.httpsCallable('assignNurse');
      await callable.call<Map<String, dynamic>>({
        'nurseId': nurseId,
        'patientId': patientId,
        'hospitalId': hospitalId,
        'notes': notes,
      });
    } on FirebaseFunctionsException catch (e) {
      throw NurseAuthorizationException(
        e.message ?? 'Assignment authorization failed: ${e.code}',
        patientId: patientId,
        nurseId: nurseId,
      );
    } catch (e) {
      if (e is NurseAuthorizationException) rethrow;
      throw NurseAuthorizationException(
        'Failed to establish nurse-patient assignment: $e',
        patientId: patientId,
        nurseId: nurseId,
      );
    }
  }

  /// Revokes an existing care assignment.
  Future<void> revokeNurseAssignment({
    required String nurseId,
    required String patientId,
    String reason = 'Shift concluded',
  }) async {
    try {
      final callable = _functions.httpsCallable('revokeNurseAssignment');
      await callable.call<Map<String, dynamic>>({
        'nurseId': nurseId,
        'patientId': patientId,
        'reason': reason,
      });
    } on FirebaseFunctionsException catch (e) {
      throw NurseAuthorizationException(e.message ?? 'Revocation failed: ${e.code}');
    }
  }

  // ─── Vital Sign Observations (Immutable History & Latest) ────

  /// Submits and persists a new vital sign observation.
  /// 1. Validates all inputs against clinical permissible bounds.
  /// 2. Performs clinical reference range assessment.
  /// 3. Dispatches via trusted backend or atomic transaction to ensure
  ///    an immutable observation history record and race-free latest cache update.
  Future<VitalSignModel> recordVitalObservation({
    VitalSignModel? observation,
    String? patientId,
    String? patientName,
    num? systolicBp,
    num? diastolicBp,
    num? pulseRate,
    num? temperatureCelsius,
    num? respiratoryRate,
    num? oxygenSaturation,
    double? weightKg,
    double? heightCm,
    String? notes,
    String? appointmentId,
  }) async {
    final VitalSignModel obs;
    if (observation != null) {
      obs = observation;
    } else {
      final pid = patientId ?? '';
      final currentUid = _currentNurseUid ?? 'nurse_demo';
      final currentName = _currentNurseName ?? 'Nurse';
      obs = VitalSignModel(
        id: '',
        patientId: pid,
        nurseId: currentUid,
        nurseName: currentName,
        recordedAt: DateTime.now(),
        systolicBp: (systolicBp ?? 0).toDouble(),
        diastolicBp: (diastolicBp ?? 0).toDouble(),
        pulseRate: (pulseRate ?? 0).toDouble(),
        temperature: (temperatureCelsius ?? 37.0).toDouble(),
        temperatureUnit: 'C',
        respiratoryRate: (respiratoryRate ?? 0).toDouble(),
        oxygenSaturation: (oxygenSaturation ?? 0).toDouble(),
        weightKg: weightKg,
        heightCm: heightCm,
        notes: notes ?? '',
      );
    }

    // Client-side completeness & permissible bounds check
    final sysRes = VitalValidator.validateSystolic(obs.systolicBp.toString());
    if (!sysRes.isValid) throw VitalValidationException(sysRes.errorMessage!, field: 'systolicBp');

    final diaRes = VitalValidator.validateDiastolic(
      obs.diastolicBp.toString(),
      systolicVal: obs.systolicBp,
    );
    if (!diaRes.isValid) throw VitalValidationException(diaRes.errorMessage!, field: 'diastolicBp');

    final pulseRes = VitalValidator.validatePulse(obs.pulseRate.toString());
    if (!pulseRes.isValid) throw VitalValidationException(pulseRes.errorMessage!, field: 'pulseRate');

    final tempRes = VitalValidator.validateTemperature(
      obs.temperature.toString(),
      unit: obs.temperatureUnit,
    );
    if (!tempRes.isValid) throw VitalValidationException(tempRes.errorMessage!, field: 'temperature');

    final respRes = VitalValidator.validateRespiratory(obs.respiratoryRate.toString());
    if (!respRes.isValid) throw VitalValidationException(respRes.errorMessage!, field: 'respiratoryRate');

    final o2Res = VitalValidator.validateOxygenSaturation(obs.oxygenSaturation.toString());
    if (!o2Res.isValid) throw VitalValidationException(o2Res.errorMessage!, field: 'oxygenSaturation');

    // Clinical reference assessment
    final tempInC = obs.temperatureUnit == 'F'
        ? VitalValidator.fahrenheitToCelsius(obs.temperature)
        : obs.temperature;

    final assessment = VitalValidator.assessVitals(
      systolicBp: obs.systolicBp,
      diastolicBp: obs.diastolicBp,
      pulseRate: obs.pulseRate,
      temperatureC: tempInC,
      respiratoryRate: obs.respiratoryRate,
      oxygenSaturation: obs.oxygenSaturation,
    );

    final finalObservation = obs.copyWith(
      temperature: tempInC,
      isCritical: assessment.isCritical,
      severity: assessment.severity,
      warningFlags: assessment.warnings,
      criticalReasons: assessment.criticalReasons,
    );

    // Dispatch via backend callable
    try {
      if (_customRecordCallable != null) {
        final res = await _customRecordCallable!({
          'patientId': finalObservation.patientId,
          'systolicBp': finalObservation.systolicBp,
          'diastolicBp': finalObservation.diastolicBp,
          'pulseRate': finalObservation.pulseRate,
          'temperature': finalObservation.temperature,
          'temperatureUnit': finalObservation.temperatureUnit,
          'respiratoryRate': finalObservation.respiratoryRate,
          'oxygenSaturation': finalObservation.oxygenSaturation,
          'weightKg': finalObservation.weightKg,
          'heightCm': finalObservation.heightCm,
          'notes': finalObservation.notes,
        });

        final obsId = res['observationId'] as String? ?? 'obs_${DateTime.now().millisecondsSinceEpoch}';
        return finalObservation.copyWith(id: obsId);
      }

      final callable = _functions.httpsCallable('recordVitalObservation');
      final result = await callable.call<Map<String, dynamic>>({
        if (finalObservation.id.isNotEmpty) 'observationId': finalObservation.id,
        'patientId': finalObservation.patientId,
        'systolicBp': finalObservation.systolicBp,
        'diastolicBp': finalObservation.diastolicBp,
        'pulseRate': finalObservation.pulseRate,
        'temperature': finalObservation.temperature,
        'temperatureUnit': finalObservation.temperatureUnit,
        'respiratoryRate': finalObservation.respiratoryRate,
        'oxygenSaturation': finalObservation.oxygenSaturation,
        'weightKg': finalObservation.weightKg,
        'heightCm': finalObservation.heightCm,
        'notes': finalObservation.notes,
      });

      final obsId = result.data['observationId'] as String? ?? finalObservation.id;
      return finalObservation.copyWith(id: obsId);
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'permission-denied') {
        throw NurseAuthorizationException(
          e.message ?? 'Nurse is not assigned to this patient.',
          patientId: finalObservation.patientId,
          nurseId: finalObservation.nurseId,
        );
      }
      throw VitalValidationException(e.message ?? 'Submission rejected: ${e.code}');
    } catch (e) {
      if (e is NurseAuthorizationException || e is VitalValidationException) rethrow;
      throw VitalValidationException('Vital recording failed via authoritative backend: $e');
    }
  }

  /// Streams the immutable chronological history of vital observations for [patientId].
  Stream<List<VitalSignModel>> watchPatientVitalsHistory(String patientId) {
    return _observations(patientId)
        .orderBy('recordedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => VitalSignModel.fromMap(d.data() as Map<String, dynamic>, docId: d.id))
            .toList());
  }

  /// Streams the latest cached vital signs summary for [patientId].
  Stream<VitalSignModel?> watchLatestPatientVitals(String patientId) {
    return _ehrVitals.doc(patientId).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      return VitalSignModel.fromMap(snap.data() as Map<String, dynamic>, docId: snap.id);
    });
  }

  /// Fetches a one-shot snapshot of the latest vitals for [patientId].
  Future<VitalSignModel?> fetchLatestPatientVitals(String patientId) async {
    final snap = await _ehrVitals.doc(patientId).get();
    if (!snap.exists || snap.data() == null) return null;
    return VitalSignModel.fromMap(snap.data() as Map<String, dynamic>, docId: snap.id);
  }

  // ─── Dashboard Metric Streams (SDS Mockup M9) ────────────────

  /// Real-time stream of vitals recorded today by [nurseId] (FR-NHO.2).
  /// Resets automatically at 00:00 PKT each calendar day.
  /// Dynamically transitions to the new PKT date key at midnight without requiring
  /// a screen reload or full-collection querying.
  Stream<int> watchNurseTodayVitalsCount(
    String nurseId, {
    DateTime Function()? nowProvider,
    Stream<DateTime>? clockStream,
    Stream<String>? customDateKeyStream,
  }) {
    final keyStream = customDateKeyStream ??
        pktDateKeyStream(nowProvider: nowProvider, clockStream: clockStream);

    late StreamController<int> controller;
    StreamSubscription<String>? keySub;
    StreamSubscription<DocumentSnapshot>? docSub;

    controller = StreamController<int>(
      onListen: () {
        keySub = keyStream.listen(
          (dateKey) {
            docSub?.cancel();
            docSub = _nurses
                .doc(nurseId)
                .collection('daily_stats')
                .doc(dateKey)
                .snapshots()
                .listen(
              (snap) {
                if (controller.isClosed) return;
                if (!snap.exists || snap.data() == null) {
                  controller.add(0);
                  return;
                }
                final data = snap.data() as Map<String, dynamic>;
                final count = data['vitalsRecordedToday'];
                controller.add(count is num ? count.toInt() : 0);
              },
              onError: (err) {
                if (!controller.isClosed) controller.addError(err);
              },
            );
          },
          onError: (err) {
            if (!controller.isClosed) controller.addError(err);
          },
        );
      },
      onCancel: () async {
        await docSub?.cancel();
        await keySub?.cancel();
      },
    );

    return controller.stream;
  }

  /// Real-time stream of total patients actively assigned to [nurseId] (FR-NHO.1).
  Stream<int> watchNurseAssignedPatientsCount(String nurseId) {
    return watchNurseAssignments(nurseId).map((list) => list.length);
  }

  /// Stream of medical reports uploaded by [nurseId] (FR-NHO.3).
  /// Note: Existing MedicalRecordModel does not have an uploaderId field.
  /// Returns 0 if no attribution collection exists, documented for Phase 3A alignment.
  Stream<int> watchNurseReportsUploadedCount(String nurseId) {
    return _db
        .collection('nurses')
        .doc(nurseId)
        .collection('reports_uploaded')
        .snapshots()
        .map((snap) => snap.docs.length);
  }

  // ─── Clinical Notes (Phase 3C) ────────────────────────────────

  CollectionReference _clinicalNotes(String patientId) =>
      _db.collection('patients').doc(patientId).collection('clinical_notes');

  /// Saves a draft of a clinical note via trusted Cloud Function.
  /// Unconfirmed drafts are editable by the authoring nurse.
  Future<Map<String, dynamic>> saveClinicalNoteDraft(Map<String, dynamic> noteData) async {
    if (_customSaveNoteDraftCallable != null) {
      return await _customSaveNoteDraftCallable!(noteData);
    }
    final callable = _functions.httpsCallable('saveClinicalNoteDraft');
    final result = await callable.call<Map<String, dynamic>>(noteData);
    return Map<String, dynamic>.from(result.data);
  }

  /// Submits a finalized clinical note via trusted Cloud Function.
  /// Computes canonical SHA-256 hash, transitions status to SUBMITTED,
  /// links amendments atomically if specified, and makes record immutable.
  /// Blockchain verification is managed asynchronously by the background reconciliation worker.
  Future<Map<String, dynamic>> submitClinicalNote(Map<String, dynamic> noteData) async {
    Map<String, dynamic> responseData;
    if (_customSubmitNoteCallable != null) {
      responseData = await _customSubmitNoteCallable!(noteData);
    } else {
      final callable = _functions.httpsCallable('submitClinicalNote');
      final result = await callable.call<Map<String, dynamic>>(noteData);
      responseData = Map<String, dynamic>.from(result.data);
    }

    return responseData;
  }

  /// Retries anchoring a submitted clinical note to Hyperledger Fabric.
  Future<FabricProofInfo> anchorClinicalNoteOnFabric({
    required String noteId,
    required String patientId,
    String noteType = 'progress_note',
  }) async {
    return await _fabricGateway.anchorRecord(
      recordId: noteId,
      patientId: patientId,
      metadata: {
        'documentType': 'CLINICAL_NOTE',
        'noteType': noteType,
      },
    );
  }

  /// Real-time stream of all clinical notes for [patientId], ordered newest first.
  Stream<List<ClinicalNoteModel>> watchPatientClinicalNotes(String patientId) {
    return _clinicalNotes(patientId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => ClinicalNoteModel.fromMap(d.data() as Map<String, dynamic>, docId: d.id))
            .toList());
  }

  /// Fetches a single clinical note by [patientId] and [noteId].
  Future<ClinicalNoteModel?> fetchClinicalNote(String patientId, String noteId) async {
    final doc = await _clinicalNotes(patientId).doc(noteId).get();
    if (!doc.exists || doc.data() == null) return null;
    return ClinicalNoteModel.fromMap(doc.data() as Map<String, dynamic>, docId: doc.id);
  }
}
