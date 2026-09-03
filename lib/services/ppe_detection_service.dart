import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/ppe_detection_result.dart';

class PortBackend {
  PortBackend._();

  /// Base URL of the FastAPI backend.
  ///
  /// Override at build time with:
  ///   --dart-define=PORT_API_BASE_URL=https://your-backend.onrender.com
  /// Defaults to a local FastAPI server for development.
  static const String baseUrl = String.fromEnvironment(
    'PORT_API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );
}

class PpeDetectionException implements Exception {
  const PpeDetectionException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PpeDetectionService {
  PpeDetectionService({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        baseUrl = baseUrl ?? PortBackend.baseUrl;

  final http.Client _client;
  final String baseUrl;

  Future<PpeDetectionResult> detectFromBytes(
    Uint8List imageBytes, {
    String filename = 'ppe-frame.jpg',
  }) async {
    if (imageBytes.isEmpty) {
      throw const PpeDetectionException('Captured frame was empty.');
    }

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/ai/ppe-detect'),
    )..files.add(
        http.MultipartFile.fromBytes('file', imageBytes, filename: filename),
      );

    late final http.StreamedResponse response;
    try {
      response = await _client
          .send(request)
          .timeout(const Duration(seconds: 45));
    } on Exception catch (error) {
      throw PpeDetectionException(
        'Could not reach the PPE backend at $baseUrl ($error). '
        'Make sure the FastAPI server is running.',
      );
    }

    final body = utf8.decode(await response.stream.toBytes());
    dynamic payload;
    try {
      payload = jsonDecode(body);
    } on FormatException {
      payload = null;
    }

    if (response.statusCode != 200) {
      throw PpeDetectionException(_errorMessage(response.statusCode, payload));
    }

    if (payload is! Map<String, dynamic>) {
      throw const PpeDetectionException(
        'PPE backend returned an unexpected response.',
      );
    }

    return PpeDetectionResult.fromJson(payload);
  }

  String _errorMessage(int statusCode, dynamic payload) {
    if (payload is Map<String, dynamic>) {
      final detail = payload['detail'];
      if (detail is String && detail.trim().isNotEmpty) {
        return detail;
      }
    }
    return 'PPE detection failed (HTTP $statusCode).';
  }

  void dispose() {
    _client.close();
  }
}
