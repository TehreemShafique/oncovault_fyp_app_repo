import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'theme/app_theme.dart';
import 'screens/splash_screen.dart';
import 'firebase_options.dart';
import 'services/notification_service.dart';
import 'services/notification_coordinator.dart';

const bool kUseFirebaseEmulators = bool.fromEnvironment('USE_FIREBASE_EMULATORS', defaultValue: false);

/// Checks if a TCP port is reachable with a short timeout.
Future<bool> _checkPort(String host, int port, {Duration timeout = const Duration(milliseconds: 1500)}) async {
  try {
    final socket = await Socket.connect(host, port, timeout: timeout);
    await socket.close();
    return true;
  } catch (_) {
    return false;
  }
}

/// Validates the emulator environment. Returns null if valid, or an error message if invalid.
Future<String?> _validateEmulatorEnvironment() async {
  try {
    final app = Firebase.app();
    if (app.options.projectId != 'demo-oncovault-local') {
      return 'SAFETY VIOLATION: Firebase project ID is "${app.options.projectId}", expected "demo-oncovault-local". Production Firebase calls are blocked.';
    }

    // Ping emulator endpoints to confirm ADB reverse or local ports are active
    const host = '127.0.0.1';
    final authOk = await _checkPort(host, 9099);
    final firestoreOk = await _checkPort(host, 8080);
    final functionsOk = await _checkPort(host, 5001);

    if (!authOk || !firestoreOk || !functionsOk) {
      final missing = <String>[];
      if (!authOk) missing.add('Auth (9099)');
      if (!firestoreOk) missing.add('Firestore (8080)');
      if (!functionsOk) missing.add('Functions (5001)');
      return 'UNREACHABLE EMULATORS:\n${missing.join(', ')}\n\nPlease ensure Firebase emulators are running and run:\nadb reverse tcp:9099 tcp:9099\nadb reverse tcp:8080 tcp:8080\nadb reverse tcp:5001 tcp:5001';
    }
  } catch (e) {
    return 'Environment validation error: $e';
  }
  return null;
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  String? initError;

  try {
    if (kUseFirebaseEmulators) {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.emulatorOptions,
        );
      }
      const emulatorHost = '127.0.0.1';
      await FirebaseAuth.instance.useAuthEmulator(
        emulatorHost,
        9099,
        automaticHostMapping: false,
      );
      FirebaseFirestore.instance.useFirestoreEmulator(
        emulatorHost,
        8080,
        sslEnabled: false,
        automaticHostMapping: false,
      );
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: false,
        sslEnabled: false,
        host: '127.0.0.1:8080',
      );
      FirebaseFunctions.instance.useFunctionsEmulator(
        emulatorHost,
        5001,
        automaticHostMapping: false,
      );
      FirebaseFunctions.instanceFor(region: 'us-central1').useFunctionsEmulator(
        emulatorHost,
        5001,
        automaticHostMapping: false,
      );

      // Sign out any persisted session so each test run starts clean
      try {
        await FirebaseAuth.instance.signOut();
      } catch (_) {}

      // Validate environment isolation & emulator connectivity
      initError = await _validateEmulatorEnvironment();
    } else {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }

      // Initialize NotificationService
      NotificationService().initialize();

      // Initialize NotificationCoordinator
      NotificationCoordinator.initialize();
    }
  } catch (e, stack) {
    debugPrint('Firebase initialization failed: $e\n$stack');
    initError = 'Firebase initialization exception: $e';
  }

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  if (initError != null) {
    runApp(EnvironmentErrorApp(errorMessage: initError));
  } else {
    runApp(const OncoVaultApp());
  }
}

/// Fallback fail-closed error screen to prevent black screens and alert the developer
class EnvironmentErrorApp extends StatelessWidget {
  final String errorMessage;
  const EnvironmentErrorApp({super.key, required this.errorMessage});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF1E1E2C),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.amberAccent,
                  size: 64,
                ),
                const SizedBox(height: 20),
                const Text(
                  'Environment Validation Blocked',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2D2B3F),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    errorMessage,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontFamily: 'monospace',
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () {
                    // Retry startup
                    main();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry Connection'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class OncoVaultApp extends StatelessWidget {
  const OncoVaultApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: NotificationService.navigatorKey,
      title: 'OncoVault',
      debugShowCheckedModeBanner: false,
      theme: OV.theme,
      home: const SplashScreen(),
      builder: (context, child) {
        if (!kUseFirebaseEmulators || child == null) return child ?? const SizedBox.shrink();
        return Directionality(
          textDirection: TextDirection.ltr,
          child: Banner(
            message: 'EMULATOR',
            location: BannerLocation.topStart,
            color: Colors.deepOrange,
            child: child,
          ),
        );
      },
    );
  }
}