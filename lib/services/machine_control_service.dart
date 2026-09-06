import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/machine_command.dart';
import '../models/machine_status.dart';
import 'ppe_detection_service.dart';

class MachineControlException implements Exception {
  const MachineControlException(this.message);
  final String message;
  @override
  String toString() => message;
}

class MachineControlService {
  MachineControlService({String? baseUrl})
      : _baseUrl = baseUrl ?? PortBackend.baseUrl;

  final String _baseUrl;
  final http.Client _client = http.Client();

  String get baseUrl => _baseUrl;

  Future<DashboardSummary> fetchDashboardSummary() async {
    final data = await _get('/machines/dashboard/summary');
    return DashboardSummary.fromJson(data);
  }

  Future<MachineDetail> fetchMachineDetail(String machineId) async {
    final data = await _get('/machines/$machineId');
    return MachineDetail.fromJson(data);
  }

  Future<MachineCommand> sendCommand(String machineId, AgvCommandRequest request) async {
    final data = await _post('/machines/$machineId/command', request.toJson());
    return MachineCommand.fromJson(data);
  }

  Future<MachineCommand> sendCraneCommand(String machineId, CraneCommandRequest request) async {
    final data = await _post('/machines/$machineId/command', request.toJson());
    return MachineCommand.fromJson(data);
  }

  /// Submit a structured, distance-first command envelope to the realtime
  /// backend. The backend maps physical distance onto the existing low-level
  /// machine protocol (calibrated) and emits command acknowledgements over the
  /// WebSocket hub.
  Future<Map<String, dynamic>> sendMachineCommand(
    String machineId,
    Map<String, dynamic> envelope,
  ) async {
    return _post('/machines/$machineId/command', envelope);
  }

  Future<void> sendDriveCommand(String machineId, DriveRequest request) async {
    await _post('/machines/$machineId/drive', request.toJson());
  }

  Future<void> startAutoMode(String machineId, AutoModeRequest request) async {
    await _post('/machines/$machineId/auto/start', request.toJson());
  }

  Future<void> stopAutoMode(String machineId) async {
    await _post('/machines/$machineId/auto/stop', {});
  }

  Future<AutoModeStatus> fetchAutoModeStatus(String machineId) async {
    final data = await _get('/machines/$machineId/auto/status');
    return AutoModeStatus.fromJson(data);
  }

  Future<DriveStatus> fetchDriveStatus(String machineId) async {
    final data = await _get('/machines/$machineId/drive/status');
    return DriveStatus.fromJson(data);
  }

  Future<List<MachineCommand>> fetchCommandHistory(String machineId) async {
    final data = await _get('/machines/$machineId/commands');
    final list = data['commands'] as List<dynamic>? ?? [];
    return list.map((c) => MachineCommand.fromJson(c as Map<String, dynamic>)).toList();
  }

  Future<List<MachineActivity>> fetchMachineLogs(String machineId) async {
    final data = await _get('/machines/$machineId/logs');
    final list = data['logs'] as List<dynamic>? ?? [];
    return list.map((l) => MachineActivity.fromJson(l as Map<String, dynamic>)).toList();
  }

  /// Camera registry for a machine: `camera_id`, `stream_url` (or null for the
  /// local device camera), PTZ support, AI toggle.
  Future<Map<String, dynamic>> fetchMachineCamera(String machineId) async {
    return _get('/machines/$machineId/camera');
  }

  /// Fetch a single JPEG frame proxied from the machine's real camera stream.
  /// The stream URL stays on the backend; the client only ever asks for a
  /// frame for a specific machine (identity is preserved end-to-end).
  Future<Uint8List> fetchCameraFrame(String machineId) async {
    try {
      final response = await _client
          .get(Uri.parse('$_baseUrl/machines/$machineId/camera/frame'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return response.bodyBytes;
      }

      String detail = 'camera frame unavailable';
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic> && decoded['detail'] is String) {
          detail = decoded['detail'] as String;
        }
      } catch (_) {}
      throw MachineControlException('$detail (HTTP ${response.statusCode})');
    } on MachineControlException {
      rethrow;
    } on TimeoutException {
      throw const MachineControlException('Camera frame timed out.');
    } catch (e) {
      throw MachineControlException('Camera frame error: $e');
    }
  }

  Future<Map<String, dynamic>> _get(String path) async {
    try {
      final response = await _client
          .get(Uri.parse('$_baseUrl$path'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }

      throw MachineControlException(
        'Request failed: ${response.statusCode} ${response.body}',
      );
    } on MachineControlException {
      rethrow;
    } on TimeoutException {
      throw const MachineControlException('Connection timed out.');
    } catch (e) {
      throw MachineControlException('Network error: $e');
    }
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$_baseUrl$path'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }

      throw MachineControlException(
        'Request failed: ${response.statusCode} ${response.body}',
      );
    } on MachineControlException {
      rethrow;
    } on TimeoutException {
      throw const MachineControlException('Connection timed out.');
    } catch (e) {
      throw MachineControlException('Network error: $e');
    }
  }

  void dispose() {
    _client.close();
  }
}
