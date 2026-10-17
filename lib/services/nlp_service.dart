// lib/services/nlp_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import '../config/api_config.dart';
import '../models/nlp_extraction_model.dart';

class NlpServiceException implements Exception {
  final String message;
  final int? statusCode;
  const NlpServiceException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class NlpService {
  static final NlpService _instance = NlpService._internal();
  factory NlpService() => _instance;
  NlpService._internal();

  final http.Client _client = http.Client();

  /// Acquires fresh Firebase ID token for authentication against Python NLP service
  Future<String?> _getAuthHeader() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final token = await user.getIdToken();
        if (token != null && token.isNotEmpty) {
          return 'Bearer $token';
        }
      }
    } catch (_) {}
    return null;
  }

  /// Health check for the clinical analysis engine (unauthenticated monitoring endpoint)
  Future<bool> checkHealth() async {
    try {
      final uri = Uri.parse(ApiConfig.nlpHealthEndpoint);
      final response = await _client.get(uri).timeout(const Duration(seconds: 4));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Sends clinical dictation text for concept extraction
  Future<NlpExtractionResponse> extractClinicalInformation(
    String transcriptionText, {
    String? patientId,
    String? customAuthHeader,
  }) async {
    final cleanText = transcriptionText.trim();
    if (cleanText.isEmpty) {
      throw const NlpServiceException('Please provide non-empty clinical text for analysis.');
    }

    final uri = Uri.parse(ApiConfig.nlpExtractEndpoint);
    if (kDebugMode) {
      print('Calling Clinical NLP service at: $uri');
    }

    try {
      final authHeader = customAuthHeader ?? await _getAuthHeader();
      final headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (authHeader != null) 'Authorization': authHeader,
        if (patientId != null) 'X-Patient-Id': patientId,
      };

      final response = await _client.post(
        uri,
        headers: headers,
        body: jsonEncode({'text': cleanText}),
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw const NlpServiceException(
            'The clinical analysis service timed out. Please verify your connection and try again.',
          );
        },
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> body = jsonDecode(utf8.decode(response.bodyBytes));
        return NlpExtractionResponse.fromMap(body);
      } else if (response.statusCode == 422) {
        throw const NlpServiceException('The provided text could not be processed due to invalid format.');
      } else {
        throw NlpServiceException(
          'Clinical service error (Status ${response.statusCode}). Please verify the backend service.',
          statusCode: response.statusCode,
        );
      }
    } on NlpServiceException {
      rethrow;
    } catch (e) {
      if (kDebugMode) print('NlpService network error: $e');
      throw NlpServiceException(
        'Unable to connect to clinical analysis service (${ApiConfig.nlpBaseUrl}). You can continue using manual documentation.',
      );
    }
  }

  /// Transcribes recorded audio using Whisper speech-to-text on the backend
  Future<String> transcribeAudio({
    String? filePath,
    Uint8List? audioBytes,
    String? fileName,
    String? patientId,
    String? customAuthHeader,
  }) async {
    final uri = Uri.parse(ApiConfig.nlpTranscribeEndpoint);
    if (kDebugMode) {
      print('Calling Whisper Transcription service at: $uri');
    }

    try {
      final authHeader = customAuthHeader ?? await _getAuthHeader();
      final request = http.MultipartRequest('POST', uri);
      if (authHeader != null) {
        request.headers['Authorization'] = authHeader;
      }
      if (patientId != null) {
        request.headers['X-Patient-Id'] = patientId;
      }

      if (audioBytes != null && audioBytes.isNotEmpty) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'audio',
            audioBytes,
            filename: fileName ?? 'recording.wav',
          ),
        );
      } else if (filePath != null && filePath.isNotEmpty) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'audio',
            filePath,
            filename: fileName,
          ),
        );
      } else {
        throw const NlpServiceException('No audio data provided for transcription.');
      }

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 90),
        onTimeout: () {
          throw const NlpServiceException(
            'Transcription service timed out. Please check that the Python backend is running and Whisper model has finished loading.',
          );
        },
      );

      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final Map<String, dynamic> body = jsonDecode(utf8.decode(response.bodyBytes));
        final transcript = body['transcript'] as String? ?? '';
        return transcript.trim();
      } else {
        String detail = 'Transcription failed (Status ${response.statusCode})';
        try {
          final errBody = jsonDecode(utf8.decode(response.bodyBytes));
          if (errBody['detail'] != null) detail = errBody['detail'];
        } catch (_) {}
        throw NlpServiceException(detail, statusCode: response.statusCode);
      }
    } on NlpServiceException {
      rethrow;
    } catch (e) {
      if (kDebugMode) print('NlpService transcription error: $e');
      throw NlpServiceException(
        'Unable to connect to clinical voice service (${ApiConfig.nlpBaseUrl}). You can continue using manual documentation.',
      );
    }
  }
}
