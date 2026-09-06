import 'model_parsers.dart';

/// Stages of the command lifecycle observed by the operator.
///
/// "SENT" means the UI submitted the command. Nothing further is claimed
/// until the backend/hardware reports it: the UI never pretends success.
enum CommandStage {
  sent,
  acknowledged,
  executing,
  completed,
  rejected,
  failed,
  estopRequested,
  estopConfirmed,
}

CommandStage parseCommandStage(dynamic value) {
  switch (readString(value).toLowerCase()) {
    case 'sent':
    case 'queued':
      return CommandStage.sent;
    case 'acknowledged':
    case 'ack':
      return CommandStage.acknowledged;
    case 'executing':
    case 'in_progress':
      return CommandStage.executing;
    case 'completed':
    case 'done':
      return CommandStage.completed;
    case 'rejected':
      return CommandStage.rejected;
    case 'failed':
    case 'error':
      return CommandStage.failed;
    case 'estop_requested':
      return CommandStage.estopRequested;
    case 'estop_confirmed':
      return CommandStage.estopConfirmed;
    default:
      return CommandStage.sent;
  }
}

/// Acknowledgement of a machine command, driven by backend/hardware events.
class CommandAck {
  const CommandAck({
    required this.commandId,
    required this.machineId,
    required this.command,
    required this.stage,
    this.message = '',
    this.distanceRequestedMm = 0,
    this.distanceMovedMm = 0,
    this.distanceRemainingMm = 0,
    this.estimatedDurationMs = 0,
    this.timestamp,
    this.mock = false,
  });

  final String commandId;
  final String machineId;
  final String command;
  final CommandStage stage;
  final String message;
  final double distanceRequestedMm;
  final double distanceMovedMm;
  final double distanceRemainingMm;
  final int estimatedDurationMs;
  final DateTime? timestamp;
  final bool mock;

  factory CommandAck.fromJson(Map<String, dynamic> json, {bool mock = false}) {
    return CommandAck(
      commandId: readString(json['command_id']),
      machineId: readString(json['machine_id']),
      command: readString(json['command']),
      stage: parseCommandStage(json['stage'] ?? json['status']),
      message: readString(json['message']),
      distanceRequestedMm: readDouble(json['distance_requested_mm']),
      distanceMovedMm: readDouble(json['distance_moved_mm']),
      distanceRemainingMm: readDouble(json['distance_remaining_mm']),
      estimatedDurationMs: readInt(json['estimated_duration_ms']),
      timestamp: json['timestamp'] != null ? readDateTime(json['timestamp']) : null,
      mock: mock,
    );
  }
}

/// Discrete backend/hardware events (machine moved, battery changed, safety
/// alarm, AI detection, emergency stop, ...).
class MachineEvent {
  const MachineEvent({
    required this.type,
    required this.machineId,
    this.message = '',
    this.severity = 'info',
    this.data = const {},
    this.timestamp,
    this.mock = false,
  });

  final String type;
  final String machineId;
  final String message;
  final String severity;
  final Map<String, dynamic> data;
  final DateTime? timestamp;
  final bool mock;

  bool get isWarning => severity == 'warning' || severity == 'critical';

  factory MachineEvent.fromJson(Map<String, dynamic> json, {bool mock = false}) {
    final data = json['data'];
    return MachineEvent(
      type: readString(json['type']),
      machineId: readString(json['machine_id']).isNotEmpty
          ? readString(json['machine_id'])
          : readString(json['machineId']),
      message: readString(json['message']),
      severity: readString(json['severity'], fallback: 'info'),
      data: data is Map<String, dynamic> ? data : const {},
      timestamp: json['timestamp'] != null ? readDateTime(json['timestamp']) : null,
      mock: mock,
    );
  }
}