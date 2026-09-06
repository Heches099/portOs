import 'model_parsers.dart';

enum MachineType { agv, crane }

/// Structured, distance-first command vocabulary forwarded to the realtime
/// backend. Commands that the existing machine architecture does not support
/// (e.g. gantry traverse) are explicitly NOT defined here rather than
/// pretending hardware exists that does not.
class MachineCommandSets {
  static const List<String> agv = <String>[
    'move_forward',
    'move_backward',
    'move_left',
    'move_right',
    'stop',
    'home',
    'blink',
    'set_speed',
    'cancel_mission',
  ];

  static const List<String> crane = <String>[
    'hoist_up',
    'hoist_down',
    'trolley_forward',
    'trolley_backward',
    'grab',
    'release',
    'stop',
    'blink',
    'cancel_mission',
  ];

  static const String emergencyStop = 'emergency_stop';
}

/// A command envelope: distance-first, speed explicit, optional timing used
/// by the backend only for watchdog/expiry (never the primary abstraction).
class MachineCommandEnvelope {
  const MachineCommandEnvelope({
    required this.machineId,
    required this.command,
    this.direction,
    this.distanceMm,
    this.speedMps,
    this.durationMs,
    this.steps,
  });

  final String machineId;
  final String command;

  /// Direction for AGV movement commands (forward/backward/left/right).
  final String? direction;

  /// Requested physical distance in millimetres (primary representation).
  final double? distanceMm;

  /// Requested speed in metres/second (watchdog + UI estimation).
  final double? speedMps;

  /// Optional watchdog/expiry window in milliseconds.
  final int? durationMs;

  /// Legacy low-level stepper magnitude for crane commands.
  final int? steps;

  Map<String, dynamic> toJson() => {
        'machine_id': machineId,
        'command': command,
        if (direction != null) 'direction': direction,
        if (distanceMm != null) 'distance_mm': distanceMm,
        if (speedMps != null) 'speed_mps': speedMps,
        if (durationMs != null) 'duration_ms': durationMs,
        if (steps != null) 'steps': steps,
      };

  /// Map a classic low-level control-panel command onto the structured
  /// distance-first vocabulary.
  factory MachineCommandEnvelope.fromLegacy({
    required String machineId,
    required String command,
    required MachineType type,
    double? distanceMm,
    int? steps,
  }) {
    var resolved = command;
    switch (command) {
      case 'forward':
        resolved = 'move_forward';
      case 'backward':
        resolved = 'move_backward';
      case 'left':
        resolved = 'move_left';
      case 'right':
        resolved = 'move_right';
      case 'magnet_on':
        resolved = 'grab';
      case 'magnet_off':
        resolved = 'release';
    }
    return MachineCommandEnvelope(
      machineId: machineId,
      command: resolved,
      direction: switch (command) {
        'forward' => 'forward',
        'backward' => 'backward',
        'left' => 'left',
        'right' => 'right',
        _ => null,
      },
      distanceMm: distanceMm,
      steps: steps,
    );
  }
}

enum CommandStatus { pending, inProgress, completed, failed, cancelled }

class MachineCommand {
  const MachineCommand({
    required this.id,
    required this.machineId,
    required this.command,
    this.params = '',
    this.status = CommandStatus.pending,
    this.createdAt,
    this.executedAt,
    this.completedAt,
  });

  final String id;
  final String machineId;
  final String command;
  final String params;
  final CommandStatus status;
  final DateTime? createdAt;
  final DateTime? executedAt;
  final DateTime? completedAt;

  factory MachineCommand.fromJson(Map<String, dynamic> json) {
    return MachineCommand(
      id: readString(json['id']),
      machineId: readString(json['machineId']),
      command: readString(json['command']),
      params: readString(json['params']),
      status: _parseStatus(json['status']),
      createdAt: json['createdAt'] != null ? readDateTime(json['createdAt']) : null,
      executedAt: json['executedAt'] != null ? readDateTime(json['executedAt']) : null,
      completedAt: json['completedAt'] != null ? readDateTime(json['completedAt']) : null,
    );
  }

  static CommandStatus _parseStatus(dynamic value) {
    final str = readString(value);
    return CommandStatus.values.firstWhere(
      (e) => e.name == str,
      orElse: () => CommandStatus.pending,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'machineId': machineId,
      'command': command,
      'params': params,
      'status': status.name,
      if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
      if (executedAt != null) 'executedAt': executedAt!.toIso8601String(),
      if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
    };
  }
}

class AgvCommandRequest {
  const AgvCommandRequest({
    required this.command,
    this.speed,
    this.duration,
  });

  final String command;
  final int? speed;
  final int? duration;

  Map<String, dynamic> toJson() {
    final params = <String, dynamic>{'command': command};
    if (speed != null) params['speed'] = speed;
    if (duration != null) params['duration'] = duration;
    return params;
  }
}

class CraneCommandRequest {
  const CraneCommandRequest({
    required this.command,
    this.steps,
  });

  final String command;
  final int? steps;

  Map<String, dynamic> toJson() {
    final params = <String, dynamic>{'command': command};
    if (steps != null) params['steps'] = steps;
    return params;
  }
}

class DriveRequest {
  const DriveRequest({required this.move, required this.speed});

  final String move;
  final int speed;

  Map<String, dynamic> toJson() => {'move': move, 'speed': speed};
}

class AutoModeRequest {
  const AutoModeRequest({
    this.cargo = 0,
    this.moveTime = 1000,
    this.loadTime = 1000,
    this.unloadTime = 1000,
  });

  final int cargo;
  final int moveTime;
  final int loadTime;
  final int unloadTime;

  Map<String, dynamic> toJson() => {
        'cargo': cargo,
        'moveTime': moveTime,
        'loadTime': loadTime,
        'unloadTime': unloadTime,
      };
}
