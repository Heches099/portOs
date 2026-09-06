import 'package:flutter/material.dart';

import '../theme/industrial_theme.dart';
import 'realtime_telemetry.dart';

/// The family of automated machines operated from the Live Operations screen.
enum MachineKind { agv, crane }

class OperationalMachine {
  const OperationalMachine({
    required this.id,
    required this.name,
    required this.kind,
    this.backendId,
    this.kicker = '',
    this.icon = Icons.precision_manufacturing_rounded,
    this.accent = IndustrialTheme.control,
  });

  /// Stable UI id (e.g. `agv-01`).
  final String id;

  final String name;

  final MachineKind kind;

  /// Id used by the FastAPI machine-control gateway (e.g. `1`), when the unit
  /// is wired to real hardware. `null` today means the unit has no hardware.
  final String? backendId;

  final String kicker;
  final IconData icon;
  final Color accent;

  bool get isSimulated => backendId == null;

  String get shortLabel => kind == MachineKind.agv ? 'AGV' : 'CRANE';
}

/// Fleet roster consumed by the Live Operations workspace.
///
/// Units without a [OperationalMachine.backendId] have no hardware yet; the
/// mock data provider still simulates them so the workspace is fully
/// demonstrable, but every mock frame/ack is clearly flagged.
const kOperationalFleet = <OperationalMachine>[
  OperationalMachine(
    id: 'agv-01',
    name: 'AGV-01',
    kind: MachineKind.agv,
    backendId: '1',
    kicker: 'Container Yard B07',
    icon: Icons.directions_car_filled_rounded,
    accent: IndustrialTheme.control,
  ),
  OperationalMachine(
    id: 'agv-02',
    name: 'AGV-02',
    kind: MachineKind.agv,
    kicker: 'Container Yard B08',
    icon: Icons.directions_car_filled_rounded,
  ),
  OperationalMachine(
    id: 'agv-03',
    name: 'AGV-03',
    kind: MachineKind.agv,
    kicker: 'Charging Bay 2',
    icon: Icons.directions_car_filled_rounded,
    accent: IndustrialTheme.ready,
  ),
  OperationalMachine(
    id: 'agv-04',
    name: 'AGV-04',
    kind: MachineKind.agv,
    kicker: 'Service Dock',
    icon: Icons.directions_car_filled_rounded,
    accent: IndustrialTheme.idle,
  ),
  OperationalMachine(
    id: 'crane-01',
    name: 'CRANE-01',
    kind: MachineKind.crane,
    backendId: '2',
    kicker: 'Berth 3 · Quay',
    icon: Icons.construction_rounded,
    accent: IndustrialTheme.violet,
  ),
  OperationalMachine(
    id: 'crane-02',
    name: 'CRANE-02',
    kind: MachineKind.crane,
    kicker: 'Berth 4 · Quay',
    icon: Icons.construction_rounded,
    accent: IndustrialTheme.violet,
  ),
];

/// A full telemetry snapshot for a machine, bound to the Live Operations UI.
///
/// This is the UI-facing presentation of a [MachineRealtimeTelemetry] frame
/// (or the mock provider output). It carries plain data plus derived display
/// state; it is never a source of truth for physical machine state.
class MachineTelemetrySnapshot {
  const MachineTelemetrySnapshot({
    this.positionX = 0,
    this.positionY = 0,
    this.destination = '--',
    this.distanceTravelled = 0,
    this.remainingDistance = 0,
    this.speed = 0,
    this.direction = 'STOPPED',
    this.battery,
    this.temperature,
    this.loadStatus = 'EMPTY',
    this.connected = false,
    this.stateLabel = 'IDLE',
    this.stateColor = IndustrialTheme.idle,
    this.trolliePosition = 0,
    this.hoistHeight = 0,
    this.targetPosition = 0,
    this.containerId = '--',
    this.safetyStatus = 'SAFE',
    this.safetyColor = IndustrialTheme.ready,
    this.mission = '--',
    this.connection = MachineConnectionState.offline,
    this.lastTelemetryAt,
  });

  final double positionX;
  final double positionY;
  final String destination;
  final double distanceTravelled;
  final double remainingDistance;
  final double speed;
  final String direction;
  final double? battery;
  final double? temperature;
  final String loadStatus;
  final bool connected;

  final String stateLabel;
  final Color stateColor;

  // Crane-only values (0 when the machine is an AGV).
  final double trolliePosition;
  final double hoistHeight;
  final double targetPosition;
  final String containerId;
  final String safetyStatus;
  final Color safetyColor;

  /// Active mission/handling descriptor reported by the machine.
  final String mission;

  /// Realtime gateway connection state for this machine.
  final MachineConnectionState connection;

  /// When the last telemetry frame for this machine was received.
  final DateTime? lastTelemetryAt;

  MachineTelemetrySnapshot copyWith({
    double? positionX,
    double? positionY,
    String? destination,
    double? distanceTravelled,
    double? remainingDistance,
    double? speed,
    String? direction,
    double? battery,
    double? temperature,
    String? loadStatus,
    bool? connected,
    String? stateLabel,
    Color? stateColor,
    double? trolliePosition,
    double? hoistHeight,
    double? targetPosition,
    String? containerId,
    String? safetyStatus,
    Color? safetyColor,
    String? mission,
    MachineConnectionState? connection,
    DateTime? lastTelemetryAt,
  }) {
    return MachineTelemetrySnapshot(
      positionX: positionX ?? this.positionX,
      positionY: positionY ?? this.positionY,
      destination: destination ?? this.destination,
      distanceTravelled: distanceTravelled ?? this.distanceTravelled,
      remainingDistance: remainingDistance ?? this.remainingDistance,
      speed: speed ?? this.speed,
      direction: direction ?? this.direction,
      battery: battery ?? this.battery,
      temperature: temperature ?? this.temperature,
      loadStatus: loadStatus ?? this.loadStatus,
      connected: connected ?? this.connected,
      stateLabel: stateLabel ?? this.stateLabel,
      stateColor: stateColor ?? this.stateColor,
      trolliePosition: trolliePosition ?? this.trolliePosition,
      hoistHeight: hoistHeight ?? this.hoistHeight,
      targetPosition: targetPosition ?? this.targetPosition,
      containerId: containerId ?? this.containerId,
      safetyStatus: safetyStatus ?? this.safetyStatus,
      safetyColor: safetyColor ?? this.safetyColor,
      mission: mission ?? this.mission,
      connection: connection ?? this.connection,
      lastTelemetryAt: lastTelemetryAt ?? this.lastTelemetryAt,
    );
  }

  static const idle = MachineTelemetrySnapshot();
}