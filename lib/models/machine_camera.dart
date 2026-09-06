import 'model_parsers.dart';
import 'realtime_telemetry.dart';

/// Configuration of the camera associated with a machine, supplied by the
/// backend (`GET /machines/{id}/camera`) and never hard-coded in the UI.
class MachineCameraConfig {
  const MachineCameraConfig({
    required this.cameraId,
    required this.machineId,
    this.name = '',
    this.streamUrl,
    this.supportsPtz = false,
    this.aiEnabled = true,
    this.connection = MachineConnectionState.online,
    this.timestamp,
  });

  final String cameraId;
  final String machineId;
  final String name;

  /// Network stream URL (RTSP/HLS/MJPEG) when the camera is a remote feed.
  /// `null` means the machine's camera is the local device camera, which the
  /// Live Camera panel renders with the native `camera` plugin preview.
  final String? streamUrl;

  final bool supportsPtz;
  final bool aiEnabled;
  final MachineConnectionState connection;
  final DateTime? timestamp;

  factory MachineCameraConfig.fromJson(Map<String, dynamic> json) {
    return MachineCameraConfig(
      cameraId: readString(json['camera_id'], fallback: 'cam-0'),
      machineId: readString(json['machine_id']),
      name: readString(json['name']),
      streamUrl: json['stream_url'] is String && (json['stream_url'] as String).isNotEmpty
          ? json['stream_url'] as String
          : null,
      supportsPtz: json['supports_ptz'] == true,
      aiEnabled: json['ai_enabled'] != false,
      connection: parseConnectionState(json['connection'] ?? 'online'),
      timestamp: json['timestamp'] != null ? readDateTime(json['timestamp']) : null,
    );
  }

  bool get isRemote => streamUrl != null && streamUrl!.isNotEmpty;
}