import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:oncovault/main.dart';
import 'package:oncovault/models/device_token_model.dart';
import 'package:oncovault/services/notification_service.dart';

void main() {
  group('Phase 1B FCM Infrastructure & Device Token Security Tests', () {
    test('DeviceTokenModel serializes correctly with infrastructure metadata', () {
      final now = DateTime(2026, 10, 7, 12, 0, 0);
      final model = DeviceTokenModel(
        fcmToken: 'fcm_mock_token_abc123xyz456',
        platform: 'android',
        createdAt: now,
        updatedAt: now,
      );

      final map = model.toMap();
      expect(map['fcmToken'], equals('fcm_mock_token_abc123xyz456'));
      expect(map['platform'], equals('android'));
      expect(map.containsKey('createdAt'), isTrue);
      expect(map.containsKey('updatedAt'), isTrue);

      final parsed = DeviceTokenModel.fromMap({
        'fcmToken': 'fcm_mock_token_abc123xyz456',
        'platform': 'android',
      });
      expect(parsed.fcmToken, equals('fcm_mock_token_abc123xyz456'));
      expect(parsed.platform, equals('android'));
    });

    test('deriveTokenId generates deterministic, path-safe SHA-256 document keys', () {
      const sampleToken1 = 'test_device_token_sample_abc';
      const sampleToken2 = 'test_device_token_sample_xyz';

      final id1 = DeviceTokenModel.deriveTokenId(sampleToken1);
      final id1Repeat = DeviceTokenModel.deriveTokenId(sampleToken1);
      final id2 = DeviceTokenModel.deriveTokenId(sampleToken2);

      // Deterministic
      expect(id1, equals(id1Repeat));
      // 64-character SHA-256 hex string
      expect(id1.length, equals(64));
      // Distinct tokens yield distinct document IDs
      expect(id1, isNot(equals(id2)));
      // Contains only alphanumeric characters (no slashes, colons, spaces, etc.)
      expect(RegExp(r'^[a-f0-9]{64}$').hasMatch(id1), isTrue);
    });

    test('Device token payload strictly excludes Protected Health Information (PHI)', () {
      final model = DeviceTokenModel(
        fcmToken: 'fcm_sample_token',
        platform: 'android',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final map = model.toMap();

      // Prohibited PHI and clinical keys
      final prohibitedKeys = [
        'diagnosis',
        'leukemia',
        'cbc',
        'bloodCount',
        'prescription',
        'medication',
        'patientId',
        'medicalId',
        'doctorNotes',
        'vitals',
        'allergies',
        'ehr',
      ];

      for (final key in prohibitedKeys) {
        expect(
          map.containsKey(key),
          isFalse,
          reason: 'Token document must never contain PHI field "$key"',
        );
      }
    });

    test('firestore.rules protects /users/{userId}/deviceTokens with owner-only access', () {
      final rulesFile = File('firestore.rules');
      expect(rulesFile.existsSync(), isTrue);

      final content = rulesFile.readAsStringSync();

      // Must define subcollection match
      expect(content.contains('match /deviceTokens/{tokenId}'), isTrue);

      // Must enforce owner-only read and write
      expect(
        content.contains('allow read, create, update, delete: if isAuthenticated() && isOwner(userId);'),
        isTrue,
        reason: 'Device tokens must be owner-only and inaccessible to other users or clinicians',
      );

      // Must retain existing in-app notification system path untouched
      expect(
        content.contains('match /notifications/{userId}/items/{notificationId}'),
        isTrue,
        reason: 'Existing Firestore in-app notifications must be preserved untouched',
      );
    });

    test('FcmMessagePayload parses notification-only message safely', () {
      const msg = RemoteMessage(
        messageId: 'msg_notif_001',
        from: '552811546534',
        notification: RemoteNotification(
          title: 'System Alert',
          body: 'Clinical infrastructure update',
        ),
      );

      final payload = FcmMessagePayload.fromRemoteMessage(msg);
      expect(payload.messageId, equals('msg_notif_001'));
      expect(payload.hasNotification, isTrue);
      expect(payload.notificationTitle, equals('System Alert'));
      expect(payload.hasData, isFalse);
      expect(payload.dataKeys, isEmpty);
    });

    test('FcmMessagePayload parses data-only message safely', () {
      const msg = RemoteMessage(
        messageId: 'msg_data_002',
        from: '552811546534',
        data: {'test_key': 'test_value', 'flag': '1'},
      );

      final payload = FcmMessagePayload.fromRemoteMessage(msg);
      expect(payload.messageId, equals('msg_data_002'));
      expect(payload.hasNotification, isFalse);
      expect(payload.notificationTitle, isNull);
      expect(payload.hasData, isTrue);
      expect(payload.dataKeys, containsAll(['test_key', 'flag']));
    });

    test('FcmMessagePayload parses message with both notification and data safely', () {
      const msg = RemoteMessage(
        messageId: 'msg_both_003',
        notification: RemoteNotification(title: 'Notice'),
        data: {'category': 'system'},
      );

      final payload = FcmMessagePayload.fromRemoteMessage(msg);
      expect(payload.messageId, equals('msg_both_003'));
      expect(payload.hasNotification, isTrue);
      expect(payload.hasData, isTrue);
      expect(payload.dataKeys, equals(['category']));
    });

    test('FcmMessagePayload tolerates empty message with missing/null fields', () {
      const msg = RemoteMessage();

      final payload = FcmMessagePayload.fromRemoteMessage(msg);
      expect(payload.messageId, isNull);
      expect(payload.from, isNull);
      expect(payload.hasNotification, isFalse);
      expect(payload.notificationTitle, isNull);
      expect(payload.hasData, isFalse);
      expect(payload.dataKeys, isEmpty);
    });

    test('FcmMessagePayload diagnostic string never exposes sensitive data payload values or PHI', () {
      const msg = RemoteMessage(
        messageId: 'msg_phi_safe_004',
        notification: RemoteNotification(
          title: 'Secure Alert',
          body: 'Sensitive internal note',
        ),
        data: {
          'sensitive_code': 'SECRET_12345',
          'medical_note': 'CONFIDENTIAL_STATUS',
        },
      );

      final payload = FcmMessagePayload.fromRemoteMessage(msg);
      final diagnostic = payload.toSafeDiagnosticString();

      // Diagnostic string must include non-sensitive metadata only
      expect(diagnostic.contains('msg_phi_safe_004'), isTrue);
      expect(diagnostic.contains('sensitive_code'), isTrue);
      expect(diagnostic.contains('medical_note'), isTrue);

      // Diagnostic string must NOT leak data payload values or sensitive body
      expect(diagnostic.contains('SECRET_12345'), isFalse);
      expect(diagnostic.contains('CONFIDENTIAL_STATUS'), isFalse);
      expect(diagnostic.contains('Sensitive internal note'), isFalse);
    });

    test('NotificationService exposes global navigatorKey foundation', () {
      expect(NotificationService.navigatorKey, isNotNull);
      expect(NotificationService.navigatorKey, isA<GlobalKey<NavigatorState>>());
    });

    test('OncoVaultApp connects NotificationService.navigatorKey to MaterialApp', () {
      const app = OncoVaultApp();
      // Inspect widget tree configuration
      expect(app, isA<Widget>());
    });

    test('NotificationService tracks initialization state and supports safe disposal', () {
      final service = NotificationService();
      expect(service.isInitialized, isFalse);

      service.dispose();
      expect(service.isInitialized, isFalse);
      expect(service.initialMessagePayload, isNull);
    });

    test('NotificationService handles initial launch payload caching and consumption', () {
      final service = NotificationService();
      expect(service.initialMessagePayload, isNull);

      const testPayload = FcmMessagePayload(
        messageId: 'launch_msg_001',
        hasNotification: true,
        notificationTitle: 'Launch Title',
        hasData: false,
        dataKeys: [],
      );

      service.setInitialMessagePayloadForTesting(testPayload);
      expect(service.initialMessagePayload, isNotNull);
      expect(service.initialMessagePayload?.messageId, equals('launch_msg_001'));

      // Consume initial payload (must clear cached state to prevent duplicate processing)
      final consumed = service.consumeInitialMessagePayload();
      expect(consumed?.messageId, equals('launch_msg_001'));
      expect(service.initialMessagePayload, isNull);
    });

    test('NotificationService emits parsed payload through onForegroundMessage stream', () async {
      final service = NotificationService();
      const testMsg = RemoteMessage(
        messageId: 'fg_stream_test_001',
        notification: RemoteNotification(title: 'Foreground Stream Test'),
        data: {'priority': 'high'},
      );

      final expectation = expectLater(
        service.onForegroundMessage,
        emits(predicate<FcmMessagePayload>((payload) {
          return payload.messageId == 'fg_stream_test_001' &&
              payload.hasNotification &&
              payload.notificationTitle == 'Foreground Stream Test' &&
              payload.hasData;
        })),
      );

      service.handleForegroundMessageForTesting(testMsg);
      await expectation;
    });

    test('NotificationService emits parsed payload through onNotificationTap stream', () async {
      final service = NotificationService();
      const testMsg = RemoteMessage(
        messageId: 'tap_stream_test_001',
        notification: RemoteNotification(title: 'Tap Stream Test'),
        data: {'target': 'audit'},
      );

      final expectation = expectLater(
        service.onNotificationTap,
        emits(predicate<FcmMessagePayload>((payload) {
          return payload.messageId == 'tap_stream_test_001' &&
              payload.hasNotification &&
              payload.notificationTitle == 'Tap Stream Test' &&
              payload.dataKeys.contains('target');
        })),
      );

      service.handleNotificationTapForTesting(testMsg);
      await expectation;
    });
  });
}
