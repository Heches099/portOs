import 'model_parsers.dart';

/// Real connectivity state of a machine (or of the realtime gateway itself).
enum MachineConnectionState { online, connecting, degraded, offline }

MachineConnectionState parseConnectionState(dynamic value) {
  switch (readString(value).toLowerCase()) {
    case 'online':
      return MachineConnectionState.online;
    case 'connecting':
      return MachineConnectionState.connecting;
    case 'degraded':
      return MachineConnectionState.degraded;
    case 'offline':
    default:
      return MachineConnectionState.offline;
  }
}

/// Strongly typed realtime telemetry frame produced by the FastAPI WebSocket
/// broadcaster (or by the mock provider in simulation mode).
///
/// Mirrors the backend `MachineTelemetryPayload` schema. Every field is plain
/// measured/derived data; no value is synthesized by the production UI.
class MachineRealtimeTelemetry {
  const MachineRealtimeTelemetry({
    required this.machineId,
    this.machineType = 'agv',
    this.state = 'idle',
    this.positionX = 0,
    this.positionY = 0,
    this.positionZ = 0,
    this.speedMps = 0,
    this.direction = 'stopped',
    this.distanceM = 0,
    this.distanceTravelledM = 0,
    this.remainingM = 0,
    this.batteryPercent,
    this.load = '',
    this.loadPercent = 0,
    this.temperatureC,
    this.connection = 'online',
    this.activeMission = '',
    this.safetyState = 'safe',
    this.trolleyM = 0,
    this.gantryM = 0,
    this.hoistM = 0,
    this.emergencyStop = false,
    this.aiStatus = 'offline',
    this.aiSafetyState = 'unknown',
    this.simulated = false,
    this.feedbackSource = 'watchdog',
    this.encoderMm = 0,
    this.motorState = 'unknown',
    this.limitSwitches = const {},
    this.batteryVoltage,
    this.currentA,
    this.timestamp,
  });

  final String machineId;
  final String machineType;
  final String state;
  final double positionX;
  final double positionY;
  final double positionZ;
  final double speedMps;
  final String direction;
  final double distanceM;
  final double distanceTravelledM;
  final double remainingM;

  /// null when the hardware does not report a battery level (never fabricated).
  final double? batteryPercent;
  final String load;
  final double loadPercent;

  /// null when the hardware does not report a temperature (never fabricated).
  final double? temperatureC;
  final String connection;
  final String activeMission;
  final String safetyState;
  final double trolleyM;
  final double gantryM;
  final double hoistM;
  final bool emergencyStop;

  /// Backend ai/vision status: 'offline' | 'active' | 'error'.
  final String aiStatus;
  final String aiSafetyState;

  /// true when the frame comes from the backend simulation, never mixed with
  /// real hardware telemetry.
  final bool simulated;

  /// 'measured' when position feedback comes from the encoder/sensor,
  /// 'watchdog' otherwise.
  final String feedbackSource;
  final double encoderMm;
  final String motorState;
  final Map<String, dynamic> limitSwitches;
  final double? batteryVoltage;
  final double? currentA;
  final DateTime? timestamp;

  bool get isCrane => machineType == 'crane';

  MachineConnectionState get connectionState => parseConnectionState(connection);

  factory MachineRealtimeTelemetry.fromJson(Map<String, dynamic> json) {
    final position = json['position'];
    final x = position is Map ? readDouble(position['x']) : readDouble(json['position_x']);
    final y = position is Map ? readDouble(position['y']) : readDouble(json['position_y']);
    final z = position is Map ? readDouble(position['z']) : readDouble(json['position_z']);
    final switches = json['limit_switches'];
    return MachineRealtimeTelemetry(
      machineId: readString(json['machine_id']),
      machineType: readString(json['machine_type'], fallback: 'agv'),
      state: readString(json['state'], fallback: 'idle'),
      positionX: x,
      positionY: y,
      positionZ: z,
      speedMps: readDouble(json['speed_mps']),
      direction: readString(json['direction'], fallback: 'stopped'),
      distanceM: readDouble(json['distance_m']),
      distanceTravelledM: readDouble(json['distance_travelled_m']),
      remainingM: readDouble(json['remaining_m']),
      batteryPercent: readNullableDouble(json['battery_percent']),
      load: readString(json['load']),
      loadPercent: readDouble(json['load_percent']),
      temperatureC: readNullableDouble(json['temperature_c']),
      connection: readString(json['connection'], fallback: 'online'),
      activeMission: readString(json['active_mission']),
      safetyState: readString(json['safety_state'], fallback: 'safe'),
      trolleyM: readDouble(json['trolley_m']),
      gantryM: readDouble(json['gantry_m']),
      hoistM: readDouble(json['hoist_m']),
      emergencyStop: json['emergency_stop'] == true,
      aiStatus: readString(json['ai_status'], fallback: 'offline'),
      aiSafetyState: readString(json['ai_safety_state'], fallback: 'unknown'),
      simulated: json['simulated'] == true,
      feedbackSource: readString(json['feedback_source'], fallback: 'watchdog'),
      encoderMm: readDouble(json['encoder_mm']),
      motorState: readString(json['motor_state'], fallback: 'unknown'),
      limitSwitches: switches is Map<String, dynamic> ? switches : const {},
      batteryVoltage: readNullableDouble(json['battery_v']),
      currentA: readNullableDouble(json['current_a']),
      timestamp: json['timestamp'] != null ? readDateTime(json['timestamp']) : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'machine_id': machineId,
        'machine_type': machineType,
        'state': state,
        'position': {'x': positionX, 'y': positionY, 'z': positionZ},
        'speed_mps': speedMps,
        'direction': direction,
        'distance_m': distanceM,
        'distance_travelled_m': distanceTravelledM,
        'remaining_m': remainingM,
        'battery_percent': batteryPercent,
        'load': load,
        'load_percent': loadPercent,
        'temperature_c': temperatureC,
        'connection': connection,
        'active_mission': activeMission,
        'safety_state': safetyState,
        'trolley_m': trolleyM,
        'gantry_m': gantryM,
        'hoist_m': hoistM,
        'emergency_stop': emergencyStop,
        'ai_status': aiStatus,
        'ai_safety_state': aiSafetyState,
        'simulated': simulated,
        'feedback_source': feedbackSource,
        'encoder_mm': encoderMm,
        'motor_state': motorState,
        'limit_switches': limitSwitches,
        'battery_v': batteryVoltage,
        'current_a': currentA,
        'timestamp': timestamp?.toIso8601String(),
      };

  MachineRealtimeTelemetry copyWith({
    double? positionX,
    double? positionY,
    double? positionZ,
    double? speedMps,
    String? direction,
    double? distanceM,
    double? remainingM,
    double? batteryPercent,
    String? load,
    double? loadPercent,
    double? temperatureC,
    String? connection,
    String? activeMission,
    String? safetyState,
    bool? emergencyStop,
    String? aiStatus,
    String? aiSafetyState,
    bool? simulated,
    String? feedbackSource,
    double? encoderMm,
    String? motorState,
    Map<String, dynamic>? limitSwitches,
    double? batteryVoltage,
    double? currentA,
    DateTime? timestamp,
  }) {
    return MachineRealtimeTelemetry(
      machineId: machineId,
      machineType: machineType,
      state: state,
      positionX: positionX ?? this.positionX,
      positionY: positionY ?? this.positionY,
      positionZ: positionZ ?? this.positionZ,
      speedMps: speedMps ?? this.speedMps,
      direction: direction ?? this.direction,
      distanceM: distanceM ?? this.distanceM,
      distanceTravelledM: distanceTravelledM,
      remainingM: remainingM ?? this.remainingM,
      batteryPercent: batteryPercent ?? this.batteryPercent,
      load: load ?? this.load,
      loadPercent: loadPercent ?? this.loadPercent,
      temperatureC: temperatureC ?? this.temperatureC,
      connection: connection ?? this.connection,
      activeMission: activeMission ?? this.activeMission,
      safetyState: safetyState ?? this.safetyState,
      trolleyM: trolleyM,
      gantryM: gantryM,
      hoistM: hoistM,
      emergencyStop: emergencyStop ?? this.emergencyStop,
      aiStatus: aiStatus ?? this.aiStatus,
      aiSafetyState: aiSafetyState ?? this.aiSafetyState,
      simulated: simulated ?? this.simulated,
      feedbackSource: feedbackSource ?? this.feedbackSource,
      encoderMm: encoderMm ?? this.encoderMm,
      motorState: motorState ?? this.motorState,
      limitSwitches: limitSwitches ?? this.limitSwitches,
      batteryVoltage: batteryVoltage ?? this.batteryVoltage,
      currentA: currentA ?? this.currentA,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}