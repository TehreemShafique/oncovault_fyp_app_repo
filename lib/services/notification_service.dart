import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint, visibleForTesting;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../models/device_token_model.dart';

/// Top-level background message handler required by FlutterFire.
/// Executes in a background isolate when an FCM message arrives while the app is in
/// background or terminated.
///
/// Strictly minimal:
/// - Does NOT access BuildContext
/// - Does NOT navigate or manipulate UI
/// - Does NOT write to Firestore or modify application state
/// - Does NOT log sensitive payload values or PHI
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    final payload = FcmMessagePayload.fromRemoteMessage(message);
    debugPrint('FCM background message received: messageId=${payload.messageId ?? "none"}');
  } catch (_) {
    // Fail-safe: background isolate handler must never terminate with unhandled exceptions
  }
}

/// Safe abstraction of an incoming FCM message payload.
/// Inspects message metadata defensively without assuming presence of notification or data fields.
/// Tolerates:
/// - notification-only messages
/// - data-only messages
/// - messages containing both
/// - messages containing neither
/// Protects against null pointers, missing keys, and prevents accidental PHI logging.
class FcmMessagePayload {
  final String? messageId;
  final String? from;
  final DateTime? sentTime;
  final bool hasNotification;
  final String? notificationTitle;
  final bool hasData;
  final List<String> dataKeys;

  const FcmMessagePayload({
    this.messageId,
    this.from,
    this.sentTime,
    required this.hasNotification,
    this.notificationTitle,
    required this.hasData,
    required this.dataKeys,
  });

  factory FcmMessagePayload.fromRemoteMessage(RemoteMessage message) {
    return FcmMessagePayload(
      messageId: message.messageId,
      from: message.from,
      sentTime: message.sentTime,
      hasNotification: message.notification != null,
      notificationTitle: message.notification?.title,
      hasData: message.data.isNotEmpty,
      dataKeys: List<String>.unmodifiable(message.data.keys),
    );
  }

  /// Safe diagnostic string that excludes payload values and PHI.
  String toSafeDiagnosticString() {
    return 'FcmMessagePayload(id: ${messageId ?? "none"}, hasNotification: $hasNotification, dataKeys: [${dataKeys.join(", ")}])';
  }
}

/// Service managing Firebase Cloud Messaging (FCM) device token lifecycle,
/// message reception streams, and notification tap detection foundation.
/// Strictly scoped to push infrastructure.
/// Does NOT contain PHI, business notification logic, or UI routing.
class NotificationService {
  /// Global navigator key shared with MaterialApp to establish the future routing foundation.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService({
    FirebaseMessaging? messaging,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  }) {
    if (messaging != null) _instance._customMessaging = messaging;
    if (firestore != null) _instance._customFirestore = firestore;
    if (auth != null) _instance._customAuth = auth;
    return _instance;
  }

  NotificationService._internal();

  FirebaseMessaging? _customMessaging;
  FirebaseFirestore? _customFirestore;
  FirebaseAuth? _customAuth;

  FirebaseMessaging get _messaging =>
      _customMessaging ?? FirebaseMessaging.instance;
  FirebaseFirestore get _firestore =>
      _customFirestore ?? FirebaseFirestore.instance;
  FirebaseAuth get _auth => _customAuth ?? FirebaseAuth.instance;

  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _foregroundMessageSubscription;
  StreamSubscription<RemoteMessage>? _messageOpenedAppSubscription;
  String? _lastTokenId;
  bool _isInitialized = false;

  FcmMessagePayload? _initialMessagePayload;

  /// Cached payload from an FCM notification that launched the application from a terminated state, if any.
  FcmMessagePayload? get initialMessagePayload => _initialMessagePayload;

  /// Consumes and clears the cached initial notification launch payload.
  /// Prevents double-processing when the initial route or UI layer handles the launch event.
  FcmMessagePayload? consumeInitialMessagePayload() {
    final payload = _initialMessagePayload;
    _initialMessagePayload = null;
    return payload;
  }

  final StreamController<FcmMessagePayload> _foregroundMessageController =
      StreamController<FcmMessagePayload>.broadcast();

  final StreamController<FcmMessagePayload> _notificationTapController =
      StreamController<FcmMessagePayload>.broadcast();

  /// Stream emitting incoming foreground FCM messages parsed safely into [FcmMessagePayload].
  Stream<FcmMessagePayload> get onForegroundMessage =>
      _foregroundMessageController.stream;

  /// Stream emitting notification tap events (from background resume or handled launch).
  Stream<FcmMessagePayload> get onNotificationTap =>
      _notificationTapController.stream;

  /// Whether the notification service has completed its initialization setup.
  bool get isInitialized => _isInitialized;

  /// Returns the current runtime operating platform string.
  String _detectPlatform() {
    if (kIsWeb) return 'web';
    try {
      if (Platform.isAndroid) return 'android';
      if (Platform.isIOS) return 'ios';
      if (Platform.isMacOS) return 'macos';
      if (Platform.isWindows) return 'windows';
      if (Platform.isLinux) return 'linux';
    } catch (_) {}
    return 'unknown';
  }

  /// Initial setup for notification service lifecycle, background handler, and listeners.
  /// Idempotent: repeated calls will not create duplicate listeners.
  /// Safe to call during app startup after Firebase.initializeApp().
  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }
    _isInitialized = true;

    try {
      // Register background message handler early
      try {
        FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      } catch (_) {
        // Safe degradation on unsupported platforms or test environments
      }

      initTokenRefreshListener();
      initForegroundMessageListener();
      initMessageOpenedAppListener();

      // Check terminated-app launch notification
      try {
        final initialMessage = await _messaging.getInitialMessage();
        if (initialMessage != null) {
          final payload = FcmMessagePayload.fromRemoteMessage(initialMessage);
          _initialMessagePayload = payload;
          debugPrint('FCM launch notification received: messageId=${payload.messageId ?? "none"}');
          if (!_notificationTapController.isClosed) {
            _notificationTapController.add(payload);
          }
        }
      } catch (_) {
        // Safe degradation if getInitialMessage fails
      }

      if (_auth.currentUser != null) {
        await registerCurrentDeviceToken();
      }
    } catch (_) {
      // Graceful degradation: never crash app startup
    }
  }

  /// Requests notification permissions via Firebase Messaging.
  /// Gracefully returns NotificationSettings without throwing on denial.
  Future<NotificationSettings?> requestPermission() async {
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );
      return settings;
    } catch (_) {
      return null;
    }
  }

  /// Retrieves the device's FCM registration token.
  /// Strictly requires an active authenticated user. Returns null if unauthenticated.
  /// Never logs the raw token string.
  Future<String?> getDeviceToken() async {
    final user = _auth.currentUser;
    if (user == null) {
      return null;
    }

    try {
      final token = await _messaging.getToken();
      if (token == null || token.trim().isEmpty) {
        return null;
      }
      return token.trim();
    } catch (_) {
      return null;
    }
  }

  /// Persists or updates the current device's FCM token under:
  /// `/users/{uid}/deviceTokens/{tokenId}`
  ///
  /// Uses a deterministic SHA-256 hash for [tokenId] to ensure the same device
  /// updates its existing record rather than generating duplicates.
  Future<String?> registerCurrentDeviceToken() async {
    final user = _auth.currentUser;
    if (user == null) {
      return null;
    }

    final token = await getDeviceToken();
    if (token == null || token.isEmpty) {
      return null;
    }

    final tokenId = DeviceTokenModel.deriveTokenId(token);
    try {
      final docRef = _firestore
          .collection('users')
          .doc(user.uid)
          .collection('deviceTokens')
          .doc(tokenId);

      final snapshot = await docRef.get();
      if (snapshot.exists) {
        await docRef.update({
          'fcmToken': token,
          'platform': _detectPlatform(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        await docRef.set({
          'fcmToken': token,
          'platform': _detectPlatform(),
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      _lastTokenId = tokenId;
      return tokenId;
    } catch (_) {
      return null;
    }
  }

  /// Sets up a listener for FCM token refresh events.
  /// Automatically synchronizes the new token to Firestore under the authenticated user
  /// and removes the old token document to prevent stale entries.
  void initTokenRefreshListener() {
    _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription =
        _messaging.onTokenRefresh.listen((newToken) async {
      final user = _auth.currentUser;
      if (user == null || newToken.trim().isEmpty) {
        return;
      }

      final newTokenId = DeviceTokenModel.deriveTokenId(newToken);
      final oldTokenId = _lastTokenId;

      try {
        if (oldTokenId != null && oldTokenId != newTokenId) {
          try {
            await _firestore
                .collection('users')
                .doc(user.uid)
                .collection('deviceTokens')
                .doc(oldTokenId)
                .delete();
          } catch (_) {}
        }

        final docRef = _firestore
            .collection('users')
            .doc(user.uid)
            .collection('deviceTokens')
            .doc(newTokenId);

        await docRef.set({
          'fcmToken': newToken.trim(),
          'platform': _detectPlatform(),
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        _lastTokenId = newTokenId;
      } catch (_) {
        // Safe fallback: never crash on background token refresh
      }
    });
  }

  /// Sets up a listener for foreground FCM messages.
  /// Receives messages while the app is active and safely processes metadata.
  ///
  /// Guarantees:
  /// - Does NOT trigger navigation or deep linking
  /// - Does NOT modify Firestore in-app notification records
  /// - Does NOT log sensitive payload values or PHI
  void initForegroundMessageListener() {
    _foregroundMessageSubscription?.cancel();
    _foregroundMessageSubscription =
        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      try {
        final payload = FcmMessagePayload.fromRemoteMessage(message);
        debugPrint('FCM foreground message received: messageId=${payload.messageId ?? "none"}');
        if (!_foregroundMessageController.isClosed) {
          _foregroundMessageController.add(payload);
        }
      } catch (_) {
        // Fail-safe: message parsing error must never crash the active application
      }
    });
  }

  /// Sets up a listener for background notification tap events (when user taps an OS tray notification).
  /// Receives the tap event on resume and emits the parsed payload through [onNotificationTap].
  ///
  /// Guarantees:
  /// - Does NOT automatically navigate or execute arbitrary routes
  /// - Does NOT expose sensitive payload contents or PHI
  void initMessageOpenedAppListener() {
    _messageOpenedAppSubscription?.cancel();
    _messageOpenedAppSubscription =
        FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      try {
        final payload = FcmMessagePayload.fromRemoteMessage(message);
        debugPrint('FCM notification tap received (background resume): messageId=${payload.messageId ?? "none"}');
        if (!_notificationTapController.isClosed) {
          _notificationTapController.add(payload);
        }
      } catch (_) {
        // Fail-safe: tap event processing error must never crash the application
      }
    });
  }

  /// Removes the current device's token document from Firestore on logout,
  /// and deletes the FCM token locally.
  /// Multiple devices belonging to the same user remain unaffected.
  Future<void> deleteCurrentDeviceToken() async {
    final user = _auth.currentUser;
    final tokenId = _lastTokenId;

    if (user != null && tokenId != null && tokenId.isNotEmpty) {
      try {
        await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('deviceTokens')
            .doc(tokenId)
            .delete();
      } catch (_) {
        // Token deletion failure must never block application logout
      }
    }

    _lastTokenId = null;

    try {
      await _messaging.deleteToken();
    } catch (_) {
      // Safe fallback if local token deletion fails
    }
  }

  /// Handles a foreground RemoteMessage directly for testing purposes.
  @visibleForTesting
  void handleForegroundMessageForTesting(RemoteMessage message) {
    final payload = FcmMessagePayload.fromRemoteMessage(message);
    if (!_foregroundMessageController.isClosed) {
      _foregroundMessageController.add(payload);
    }
  }

  /// Handles a notification tap RemoteMessage directly for testing purposes.
  @visibleForTesting
  void handleNotificationTapForTesting(RemoteMessage message) {
    final payload = FcmMessagePayload.fromRemoteMessage(message);
    _initialMessagePayload = payload;
    if (!_notificationTapController.isClosed) {
      _notificationTapController.add(payload);
    }
  }

  /// Sets the initial message payload directly for testing purposes.
  @visibleForTesting
  void setInitialMessagePayloadForTesting(FcmMessagePayload? payload) {
    _initialMessagePayload = payload;
  }

  /// Disposes active stream subscriptions and resets initialization state.
  void dispose() {
    _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;
    _foregroundMessageSubscription?.cancel();
    _foregroundMessageSubscription = null;
    _messageOpenedAppSubscription?.cancel();
    _messageOpenedAppSubscription = null;
    _initialMessagePayload = null;
    _isInitialized = false;
  }
}
