// lib/services/foreground_notification_presenter.dart
import 'package:flutter/material.dart';
import '../models/notification_payload.dart';
import '../theme/app_theme.dart';
import 'notification_router.dart';
import 'notification_service.dart';

/// Presenter responsible for displaying incoming foreground notifications as
/// non-disruptive in-app SnackBars with an explicit "Open" action.
///
/// Guaranteed properties:
/// - Does NOT trigger automatic page navigation
/// - Does NOT evaluate business routing logic
/// - Auto-dismisses after a short timeout if ignored
class ForegroundNotificationPresenter {
  final GlobalKey<NavigatorState> _navigatorKey;

  ForegroundNotificationPresenter({
    GlobalKey<NavigatorState>? navigatorKey,
  }) : _navigatorKey = navigatorKey ?? NotificationService.navigatorKey;

  static ForegroundNotificationPresenter instance =
      ForegroundNotificationPresenter();

  /// Displays an in-app SnackBar banner for the incoming foreground [payload].
  /// Returns `true` if the SnackBar was presented, `false` otherwise.
  bool presentForegroundNotification(AppNotificationPayload payload) {
    final context = _navigatorKey.currentContext;
    if (context == null) {
      debugPrint('ForegroundNotificationPresenter: navigator context unavailable.');
      return false;
    }

    try {
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) {
        return false;
      }

      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          backgroundColor: OV.slateDark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                payload.title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.white,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (payload.body.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  payload.body,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white70,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
          action: SnackBarAction(
            label: 'Open',
            textColor: OV.tertiaryContainer,
            onPressed: () {
              NotificationRouter.route(payload);
            },
          ),
        ),
      );
      return true;
    } catch (e) {
      debugPrint('ForegroundNotificationPresenter error: $e');
      return false;
    }
  }
}
