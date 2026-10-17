// lib/services/audio_recorder_service.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

class RecordedAudioResult {
  final String? filePath;
  final Uint8List? bytes;
  final String fileName;

  const RecordedAudioResult({
    this.filePath,
    this.bytes,
    required this.fileName,
  });
}

class AudioRecorderService {
  static final AudioRecorderService _instance = AudioRecorderService._internal();
  factory AudioRecorderService() => _instance;
  AudioRecorderService._internal();

  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;

  bool get isRecording => _isRecording;
  Stream<Amplitude> get onAmplitudeChanged => _recorder.onAmplitudeChanged(const Duration(milliseconds: 100));

  Future<bool> hasPermission() async {
    try {
      return await _recorder.hasPermission();
    } catch (e) {
      if (kDebugMode) print("AudioRecorderService hasPermission error: $e");
      return false;
    }
  }

  Future<bool> startRecording() async {
    final permitted = await hasPermission();
    if (!permitted) return false;

    if (_isRecording) {
      await stopRecording();
    }

    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      if (kIsWeb) {
        await _recorder.start(
          const RecordConfig(
            encoder: AudioEncoder.opus,
            sampleRate: 48000,
            bitRate: 128000,
            numChannels: 1,
          ),
          path: '',
        );
      } else {
        final tempDir = await getTemporaryDirectory();
        final path = '${tempDir.path}/clinical_dictation_$timestamp.m4a';
        await _recorder.start(
          const RecordConfig(
            encoder: AudioEncoder.aacLc,
            sampleRate: 48000,
            bitRate: 128000,
            numChannels: 1,
          ),
          path: path,
        );
      }
      _isRecording = true;
      return true;
    } catch (e) {
      if (kDebugMode) print("AudioRecorderService startRecording error: $e");
      _isRecording = false;
      return false;
    }
  }

  Future<RecordedAudioResult?> stopRecording() async {
    if (!_isRecording) return null;

    try {
      final path = await _recorder.stop();
      _isRecording = false;

      if (path == null || path.isEmpty) {
        return null;
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;

      if (kIsWeb) {
        // In Flutter Web, path is a blob URL (e.g. blob:http://...)
        Uint8List? audioBytes;
        try {
          final res = await http.get(Uri.parse(path));
          if (res.statusCode == 200) {
            audioBytes = res.bodyBytes;
          }
        } catch (e) {
          if (kDebugMode) print("Failed to fetch web blob audio bytes: $e");
        }
        return RecordedAudioResult(
          filePath: null,
          bytes: audioBytes,
          fileName: 'clinical_dictation_$timestamp.webm',
        );
      } else {
        return RecordedAudioResult(
          filePath: path,
          bytes: null,
          fileName: 'clinical_dictation_$timestamp.m4a',
        );
      }
    } catch (e) {
      if (kDebugMode) print("AudioRecorderService stopRecording error: $e");
      _isRecording = false;
      return null;
    }
  }

  Future<void> cancelRecording() async {
    if (_isRecording) {
      try {
        await _recorder.cancel();
      } catch (_) {}
      _isRecording = false;
    }
  }

  /// Safely deletes a local temporary audio recording file to guarantee PHI cleanup.
  Future<void> deleteAudioFile(String? filePath) async {
    if (filePath == null || filePath.isEmpty || kIsWeb) return;
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      if (kDebugMode) print("Failed to delete temporary audio file: $e");
    }
  }

  void dispose() {
    cancelRecording();
    _recorder.dispose();
  }
}
