// lib/config/api_config.dart
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

class ApiConfig {
  static String? _customBaseUrl;

  /// Override the API base URL at runtime (e.g. for custom server IP or testing)
  static void setBaseUrl(String url) {
    _customBaseUrl = url.trim();
  }

  /// Reset to default platform-specific URL
  static void resetBaseUrl() {
    _customBaseUrl = null;
  }

  /// Get the active base URL for the Python NLP backend service
  static String get nlpBaseUrl {
    if (_customBaseUrl != null && _customBaseUrl!.isNotEmpty) {
      return _customBaseUrl!;
    }

    if (kIsWeb) {
      return 'http://127.0.0.1:8000';
    }

    try {
      if (Platform.isAndroid) {
        // Physical phone with ADB reverse or emulator mode uses 127.0.0.1 loopback
        const bool useAdbReverse = bool.fromEnvironment('USE_ADB_REVERSE', defaultValue: true);
        const bool useEmulators = bool.fromEnvironment('USE_FIREBASE_EMULATORS', defaultValue: false);
        if (useAdbReverse || useEmulators) {
          return 'http://127.0.0.1:8000';
        }
        // Legacy fallback for Android virtual emulator loopback alias
        return 'http://10.0.2.2:8000';
      } else if (Platform.isIOS || Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        return 'http://127.0.0.1:8000';
      }
    } catch (_) {}

    return 'http://127.0.0.1:8000';
  }

  static String get nlpExtractEndpoint => '$nlpBaseUrl/extract';
  static String get nlpTranscribeEndpoint => '$nlpBaseUrl/transcribe';
  static String get nlpHealthEndpoint => '$nlpBaseUrl/health';
  static String get predictSymptomsEndpoint => '$nlpBaseUrl/predict-symptoms';
  static String get predictCbcEndpoint => '$nlpBaseUrl/predict-cbc';
}
