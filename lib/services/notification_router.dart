// lib/services/notification_router.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/notification_payload.dart';
import '../models/appointment_model.dart';
import '../models/medical_record_model.dart';
import '../models/user_model.dart';
import 'notification_service.dart';
import 'appointment_service.dart';
import 'doctor_service.dart';
import 'auth_service.dart';

// Destination screens
import '../screens/patient/appointment_detail_screen.dart';
import '../screens/patient/appointment_list_screen.dart';
import '../screens/patient/report_viewer_screen.dart';
import '../screens/patient/medical_records_screen.dart';
import '../screens/patient/notifications_screen.dart';
import '../screens/doctor/appointment_detail_doctor_screen.dart';
import '../screens/doctor/appointment_requests_screen.dart';
import '../screens/doctor/critical_alerts_screen.dart';
import '../screens/doctor/doctor_notifications_screen.dart';

/// Central domain router that validates, authorizes, resolves, and navigates
/// notification payloads to relevant application screens.
class NotificationRouter {
  static const Set<String> supportedTypes = {
    'appointment',
    'report',
    'vital_alert',
    'general',
  };

  static const Set<String> recognizedUnsupportedTypes = {
    'message',
    'reminder',
    'access_request',
    'consent',
    'follow_up',
  };

  final FirebaseAuth? _customAuth;
  final GlobalKey<NavigatorState> _navigatorKey;
  final Future<AppointmentModel?> Function(String appointmentId)? _appointmentResolver;
  final Future<MedicalRecordModel?> Function(String patientId, String recordId)? _recordResolver;
  final Future<OVUser?> Function(String uid)? _profileResolver;
  final String? Function()? _currentUserIdResolver;
  final DoctorService Function()? _doctorServiceFactory;

  FirebaseAuth get _auth => _customAuth ?? FirebaseAuth.instance;

  NotificationRouter({
    FirebaseAuth? auth,
    GlobalKey<NavigatorState>? navigatorKey,
    Future<AppointmentModel?> Function(String appointmentId)? appointmentResolver,
    Future<MedicalRecordModel?> Function(String patientId, String recordId)? recordResolver,
    Future<OVUser?> Function(String uid)? profileResolver,
    String? Function()? currentUserIdResolver,
    DoctorService Function()? doctorServiceFactory,
  })  : _customAuth = auth,
        _navigatorKey = navigatorKey ?? NotificationService.navigatorKey,
        _appointmentResolver = appointmentResolver,
        _recordResolver = recordResolver,
        _profileResolver = profileResolver,
        _currentUserIdResolver = currentUserIdResolver,
        _doctorServiceFactory = doctorServiceFactory;

  /// Global shared instance used across application.
  static NotificationRouter instance = NotificationRouter();

  /// Static entry point for routing an [AppNotificationPayload].
  static Future<bool> route(AppNotificationPayload payload) =>
      instance.routePayload(payload);

  /// Resolves an appointment by ID using the injected resolver or AppointmentService.
  Future<AppointmentModel?> _resolveAppointment(String id) async {
    try {
      if (_appointmentResolver != null) {
        return await _appointmentResolver!(id);
      }
      return await AppointmentService().getAppointment(id);
    } catch (_) {
      return null;
    }
  }

  /// Resolves a medical record by ID and patientId.
  Future<MedicalRecordModel?> _resolveRecord(String patientId, String recordId) async {
    try {
      if (_recordResolver != null) {
        return await _recordResolver!(patientId, recordId);
      }
      return await MedicalRecordService().getRecord(patientId, recordId);
    } catch (_) {
      return null;
    }
  }

  /// Resolves user profile by UID.
  Future<OVUser?> _resolveProfile(String uid) async {
    try {
      if (_profileResolver != null) {
        return await _profileResolver!(uid);
      }
      return await AuthService().fetchProfile(uid);
    } catch (_) {
      return null;
    }
  }

  /// Main routing dispatch method.
  /// Returns `true` if navigation was dispatched or safely handled, `false` otherwise.
  Future<bool> routePayload(AppNotificationPayload payload) async {
    // 1. Validate navigator availability
    final navState = _navigatorKey.currentState;
    if (navState == null) {
      debugPrint('NotificationRouter: NavigatorState is unavailable. Navigation dropped.');
      return false;
    }

    // 2. Verify active authentication
    final currentUserId = _currentUserIdResolver != null
        ? _currentUserIdResolver!()
        : _auth.currentUser?.uid;
    if (currentUserId == null || currentUserId.isEmpty) {
      debugPrint('NotificationRouter: User is unauthenticated. Navigation rejected.');
      return false;
    }

    // 3. Resolve user role
    final profile = await _resolveProfile(currentUserId);
    final role = (profile?.role ?? '').toLowerCase();
    if (role.isEmpty) {
      debugPrint('NotificationRouter: Unable to determine role for $currentUserId. Navigation rejected.');
      return false;
    }

    final displayName = profile?.name ?? (role == 'doctor' ? 'Doctor' : 'Patient');

    // 4. Validate reference ID if present
    final refId = payload.referenceId?.trim();
    final isRefIdValid = refId != null && refId.isNotEmpty && refId.length <= 128;
    final sanitizedRefId = isRefIdValid ? refId : null;

    // 5. Role-aware routing
    switch (role) {
      case 'patient':
        return await _routePatient(
          navState: navState,
          patientId: currentUserId,
          patientName: displayName,
          type: payload.type,
          referenceId: sanitizedRefId,
        );

      case 'doctor':
        return await _routeDoctor(
          navState: navState,
          doctorId: currentUserId,
          doctorName: displayName,
          type: payload.type,
          referenceId: sanitizedRefId,
        );

      case 'nurse':
      case 'admin':
      default:
        // No standalone notification inbox or screens exist for these roles in Phase 1.
        debugPrint('NotificationRouter: Role "$role" has no supported notification destinations.');
        return false;
    }
  }

  /// Handles routing for patient role.
  Future<bool> _routePatient({
    required NavigatorState navState,
    required String patientId,
    required String patientName,
    required String type,
    required String? referenceId,
  }) async {

    if (type == 'appointment') {
      if (referenceId != null) {
        final appt = await _resolveAppointment(referenceId);
        // Authorization check: appointment must belong to current patient
        if (appt != null && appt.patientId == patientId) {
          navState.push(MaterialPageRoute(
            builder: (_) => AppointmentDetailScreen(
              appointment: appt,
              patientId: patientId,
              patientName: patientName,
            ),
          ));
          return true;
        }
      }
      // Fallback: list screen
      navState.push(MaterialPageRoute(
        builder: (_) => AppointmentListScreen(
          patientId: patientId,
          patientName: patientName,
        ),
      ));
      return true;
    }

    if (type == 'report') {
      if (referenceId != null) {
        final record = await _resolveRecord(patientId, referenceId);
        // Authorization check: record must belong to current patient
        if (record != null && record.patientId == patientId) {
          navState.push(MaterialPageRoute(
            builder: (_) => ReportViewerScreen(record: record),
          ));
          return true;
        }
      }
      // Fallback: medical records screen
      navState.push(MaterialPageRoute(
        builder: (_) => MedicalRecordsScreen(patientId: patientId),
      ));
      return true;
    }

    if (type == 'vital_alert') {
      // Role Mismatch Protection: vital alerts are clinician-only
      debugPrint('NotificationRouter: Patient received vital_alert. Mismatch rejected.');
      navState.push(MaterialPageRoute(
        builder: (_) => NotificationsScreen(patientId: patientId),
      ));
      return true;
    }

    // Default / general / recognized unsupported / unknown fallback: notification inbox
    navState.push(MaterialPageRoute(
      builder: (_) => NotificationsScreen(patientId: patientId),
    ));
    return true;
  }

  /// Handles routing for doctor role.
  Future<bool> _routeDoctor({
    required NavigatorState navState,
    required String doctorId,
    required String doctorName,
    required String type,
    required String? referenceId,
  }) async {

    if (type == 'appointment') {
      if (referenceId != null) {
        final appt = await _resolveAppointment(referenceId);
        // Authorization check: appointment must belong to current doctor
        if (appt != null && appt.doctorId == doctorId) {
          final service = _doctorServiceFactory?.call() ?? DoctorService();
          navState.push(MaterialPageRoute(
            builder: (_) => AppointmentDetailDoctorScreen(
              appointment: appt,
              service: service,
            ),
          ));
          return true;
        }
      }
      // Fallback: requests screen
      navState.push(MaterialPageRoute(
        builder: (_) => AppointmentRequestsScreen(
          doctorId: doctorId,
          doctorName: doctorName,
        ),
      ));
      return true;
    }

    if (type == 'vital_alert') {
      navState.push(MaterialPageRoute(
        builder: (_) => CriticalAlertsScreen(doctorId: doctorId),
      ));
      return true;
    }

    if (type == 'report') {
      // Doctor has no dedicated standalone report viewer -> fallback to doctor notifications
      navState.push(MaterialPageRoute(
        builder: (_) => DoctorNotificationsScreen(doctorId: doctorId),
      ));
      return true;
    }

    // Default / general / recognized unsupported / unknown fallback: doctor notification inbox
    navState.push(MaterialPageRoute(
      builder: (_) => DoctorNotificationsScreen(doctorId: doctorId),
    ));
    return true;
  }
}
