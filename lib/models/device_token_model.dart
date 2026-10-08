import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Clean model representing an FCM device token registration.
/// Strictly contains infrastructure metadata and NO Protected Health Information (PHI).
class DeviceTokenModel {
  final String fcmToken;
  final String platform;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const DeviceTokenModel({
    required this.fcmToken,
    required this.platform,
    this.createdAt,
    this.updatedAt,
  });

  /// Deterministically derives a URL/path-safe document ID from the raw FCM token.
  /// Uses SHA-256 to guarantee a fixed-length hexadecimal key without special characters.
  static String deriveTokenId(String token) {
    return sha256.convert(utf8.encode(token.trim())).toString();
  }

  Map<String, dynamic> toMap() => {
    'fcmToken': fcmToken.trim(),
    'platform': platform,
    'createdAt': createdAt != null
        ? Timestamp.fromDate(createdAt!)
        : FieldValue.serverTimestamp(),
    'updatedAt': updatedAt != null
        ? Timestamp.fromDate(updatedAt!)
        : FieldValue.serverTimestamp(),
  };

  factory DeviceTokenModel.fromMap(Map<String, dynamic> map) => DeviceTokenModel(
    fcmToken: map['fcmToken'] ?? '',
    platform: map['platform'] ?? 'unknown',
    createdAt: map['createdAt'] is Timestamp
        ? (map['createdAt'] as Timestamp).toDate()
        : null,
    updatedAt: map['updatedAt'] is Timestamp
        ? (map['updatedAt'] as Timestamp).toDate()
        : null,
  );
}
