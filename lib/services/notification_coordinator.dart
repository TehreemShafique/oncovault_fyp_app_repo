// lib/services/notification_coordinator.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/notification_payload.dart';
import 'notification_service.dart';
import 'notification_router.dart';
import 'foreground_notification_presenter.dart';

/// Application notification coordinator that connects low-level FCM push streams
/// to the domain [NotificationRouter] and [ForegroundNotificationPresenter].
///
/// Maintains strict separation of concerns:
/// - [NotificationService] handles push infrastructure and transport streams
/// - [ForegroundNotificationPresenter] presents in-app UI for active foreground messages
/// - [NotificationRouter] resolves, authorizes, and executes screen navigation
class NotificationCoordinator {
  static StreamSubscription<AppNotificationPayload>? _foregroundSubscription;
  static StreamSubscription<AppNotificationPayload>? _tapSubscription;
  static bool _isInitialized = false;

  /// Initializes listeners for incoming FCM notifications.
  /// Idempotent. Safe to call during app startup.
  static void initialize({
    NotificationService? notificationService,
    NotificationRouter? router,
    ForegroundNotificationPresenter? presenter,
  }) {
    if (_isInitialized) return;
    _isInitialized = true;

    final service = notificationService ?? NotificationService();
    final targetRouter = router ?? NotificationRouter.instance;
    final targetPresenter = presenter ?? ForegroundNotificationPresenter.instance;

    _foregroundSubscription?.cancel();
    _foregroundSubscription = service.onAppForegroundNotification.listen((payload) {
      debugPrint('NotificationCoordinator: foreground notification received');
      targetPresenter.presentForegroundNotification(payload);
    });

    _tapSubscription?.cancel();
    _tapSubscription = service.onAppNotificationTap.listen((payload) {
      debugPrint('NotificationCoordinator: notification tap received');
      targetRouter.routePayload(payload);
    });
  }

  /// Disposes active subscriptions (used in testing or teardown).
  @visibleForTesting
  static void dispose() {
    _foregroundSubscription?.cancel();
    _foregroundSubscription = null;
    _tapSubscription?.cancel();
    _tapSubscription = null;
    _isInitialized = false;
  }
}
