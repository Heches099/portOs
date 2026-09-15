import 'model_parsers.dart';

/// A single safety preflight check for commissioning, as reported by
/// `GET /machines/{id}/commission` (key, friendly label, pass/fail).
class PreflightCheck {
  const PreflightCheck({
    required this.key,
    required this.label,
    required this.passed,
  });

  final String key;
  final String label;
  final bool passed;

  factory PreflightCheck.fromJson(Map<String, dynamic> json) {
    return PreflightCheck(
      key: readString(json['key']),
      label: readString(json['label']),
      passed: json['passed'] == true,
    );
  }
}

/// Result of the commissioning-mode status endpoint. Live hardware starts
/// fully blocked (0 mm) and unlocks movement through the approved levels;
/// `levelDisplay` mirrors the backend (BLOCKED / N mm / UNLIMITED).
class CommissionStatus {
  const CommissionStatus({
    required this.machineId,
    required this.mode,
    required this.commissionDistanceMm,
    required this.commissioned,
    required this.unlimited,
    required this.levelDisplay,
    required this.nextLevelMm,
    required this.preflight,
  });

  final String machineId;
  final String mode;
  final double commissionDistanceMm;
  final bool commissioned;
  final bool unlimited;
  final String levelDisplay;
  final double? nextLevelMm;
  final List<PreflightCheck> preflight;

  bool get allOk =>
      preflight.isNotEmpty && preflight.every((check) => check.passed);

  static const List<String> _knownKeys = [
    'connection_ok',
    'telemetry_fresh',
    'estop_clear',
    'ack_path_ok',
    'encoder_ok',
    'sensors_seen',
    'identity_ok',
    'camera_ok',
  ];

  static const Map<String, String> _labels = {
    'connection_ok': 'Online connection',
    'telemetry_fresh': 'Fresh telemetry',
    'estop_clear': 'E-STOP clear',
    'ack_path_ok': 'Ack path (dashboard WS)',
    'encoder_ok': 'Measured encoder',
    'sensors_seen': 'Sensors reporting',
    'identity_ok': 'Machine identity',
    'camera_ok': 'Camera feed',
  };

  factory CommissionStatus.fromJson(Map<String, dynamic> json) {
    final preflightRaw =
        json['preflight'] is Map<String, dynamic>
            ? json['preflight'] as Map<String, dynamic>
            : <String, dynamic>{};
    final checks = <PreflightCheck>[];
    for (final key in _knownKeys) {
      if (preflightRaw.containsKey(key)) {
        checks.add(PreflightCheck(
          key: key,
          label: _labels[key] ?? key,
          passed: preflightRaw[key] == true,
        ));
      }
    }
    return CommissionStatus(
      machineId: readString(json['machine_id']),
      mode: readString(json['mode']),
      commissionDistanceMm: readDouble(json['commissionDistanceMm']),
      commissioned: json['commissioned'] == true,
      unlimited: json['unlimited'] == true,
      levelDisplay: readString(json['level_display']),
      nextLevelMm: json['next_level_mm'] is num
          ? (json['next_level_mm'] as num).toDouble()
          : null,
      preflight: checks,
    );
  }
}