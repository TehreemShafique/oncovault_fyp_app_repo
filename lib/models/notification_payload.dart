// lib/models/notification_payload.dart
import 'package:firebase_messaging/firebase_messaging.dart';
import 'medical_record_model.dart';

/// Origin of an incoming or handled notification payload.
enum NotificationSource {
  fcmForeground,
  fcmTap,
  fcmColdStart,
  inAppHistory,
}

/// Normalized, validated domain-level notification payload.
/// Strictly excludes arbitrary data maps (no rawData) and protects against Protected Health Information (PHI).
class AppNotificationPayload {
  final String? messageId;
  final String type;             // Whitelisted, lowercase, trimmed
  final String? referenceId;     // Optional entity reference ID (trimmed)
  final String title;            // Sanitized user-facing title
  final String body;             // Sanitized user-facing body
  final NotificationSource source;

  const AppNotificationPayload({
    this.messageId,
    required this.type,
    this.referenceId,
    required this.title,
    required this.body,
    required this.source,
  });

  /// Factory creating an [AppNotificationPayload] from an FCM [RemoteMessage].
  /// Extracts only explicitly known fields; never retains arbitrary raw payload data.
  factory AppNotificationPayload.fromRemoteMessage(
    RemoteMessage message, {
    required NotificationSource source,
  }) {
    final data = message.data;
    final rawType = (data['type'] ?? 'general').toString().trim().toLowerCase();
    final rawRefId = data['referenceId']?.toString().trim();
    final title = message.notification?.title ??
        data['title']?.toString().trim() ??
        'OncoVault Notification';
    final body = message.notification?.body ??
        data['body']?.toString().trim() ??
        '';

    return AppNotificationPayload(
      messageId: message.messageId,
      type: rawType.isEmpty ? 'general' : rawType,
      referenceId: (rawRefId != null && rawRefId.isNotEmpty) ? rawRefId : null,
      title: title,
      body: body,
      source: source,
    );
  }

  /// Factory creating an [AppNotificationPayload] from a Firestore [NotificationModel].
  factory AppNotificationPayload.fromNotificationModel(
    NotificationModel model,
  ) {
    final rawType = model.type.trim().toLowerCase();
    final rawRefId = model.referenceId?.trim();

    return AppNotificationPayload(
      messageId: model.id.isNotEmpty ? model.id : null,
      type: rawType.isEmpty ? 'general' : rawType,
      referenceId: (rawRefId != null && rawRefId.isNotEmpty) ? rawRefId : null,
      title: model.title.trim(),
      body: model.body.trim(),
      source: NotificationSource.inAppHistory,
    );
  }

  /// Safe diagnostic string that excludes PHI and unnecessary data.
  String toSafeDiagnosticString() {
    return 'AppNotificationPayload(id: ${messageId ?? "none"}, type: $type, hasRefId: ${referenceId != null}, source: $source)';
  }
}
