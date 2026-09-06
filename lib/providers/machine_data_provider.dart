import 'dart:async';
import 'dart:math' as math;

import '../config/realtime_config.dart';
import '../models/machine_command.dart';
import '../models/operational_machine.dart';
import '../models/realtime_message.dart';
import '../models/realtime_telemetry.dart';
import '../services/machine_control_service.dart';
import '../services/machine_realtime_service.dart';

/// Data-source abstraction for the Live Operations workspace.
///
/// The UI binds to this interface only. Two implementations exist:
///   - [MockMachineDataProvider]  (REALTIME_MODE=mock) - simulated telemetry,
///     simulated command lifecycle, every frame clearly flagged.
///   - [WebSocketMachineDataProvider] (REALTIME_MODE=websocket) - live
///     telemetry/events/acks over WebSocket; commands over REST.
abstract class MachineDataProvider {
  RealtimeMode get mode;

  MachineConnectionState get connectionState;

  bool get backendReachable;

  String get statusLabel;

  Stream<MachineRealtimeTelemetry> get telemetryStream;

  Stream<CommandAck> get commandAcks;

  Stream<MachineEvent> get events;

  /// Opens the data channel and starts delivering frames.
  void start();

  Future<void> subscribeTo(OperationalMachine machine);

  Future<void> unsubscribeFrom(OperationalMachine machine);

  /// Submit a structured, distance-first command. Returns the initial
  /// acknowledgement (sent / rejected / failed). Later stages arrive on
  /// [commandAcks].
  Future<CommandAck> sendCommand(MachineCommandEnvelope envelope);

  /// Submit an emergency stop. Acks (estopRequested -> estopConfirmed) arrive
  /// on [commandAcks].
  Future<CommandAck> emergencyStop(OperationalMachine machine);

  void dispose();
}

MachineDataProvider createDefaultDataProvider({
  required MachineControlService service,
  required List<OperationalMachine> fleet,
}) {
  if (RealtimeConfig.mode == RealtimeMode.websocket) {
    return WebSocketMachineDataProvider(http: service);
  }
  return MockMachineDataProvider(fleet: fleet);
}

// ─────────────────────────────────────────────────────────────────────────
// MOCK PROVIDER (isolated dev/simulation mode)
// ─────────────────────────────────────────────────────────────────────────

class _SimMachine {
  _SimMachine(this.machine)
      : baseX = _basePosition(machine).$1,
        baseY = _basePosition(machine).$2 {
    battery = switch (machine.name) {
      'AGV-01' => 92.0,
      'AGV-02' => 64.0,
      'AGV-03' => 97.0,
      'CRANE-01' => 88.0,
      'CRANE-02' => 100.0,
      _ => 100.0,
    };
    temperature = machine.kind == MachineKind.crane ? 46.0 : 41.0;
    mission = machine.kicker;
    loadStatus = machine.kind == MachineKind.crane ? 'LOADED' : 'EMPTY';
    trolleyM = machine.kind == MachineKind.crane ? 12.0 : 0;
    hoistM = machine.kind == MachineKind.crane ? 6.0 : 0;
  }

  final OperationalMachine machine;
  final double baseX;
  final double baseY;

  double posX = 0;
  double posY = 0;
  double speedMps = 0;
  String state = 'idle';
  bool estop = false;
  double battery = 100;
  double temperature = 41;
  String direction = 'stopped';
  double distanceTravelledM = 0;
  double remainingM = 0;
  String mission = '';
  String loadStatus = 'EMPTY';
  String safety = 'safe';
  double trolleyM = 0;
  double hoistM = 0;
  int moveStep = 0;

  MachineRealtimeTelemetry toFrame(DateTime now) {
    final x = baseX + posX;
    final y = baseY + posY;
    return MachineRealtimeTelemetry(
      machineId: machine.id,
      machineType: machine.kind == MachineKind.agv ? 'agv' : 'crane',
      state: estop ? 'estop' : state,
      positionX: x,
      positionY: y,
      positionZ: machine.kind == MachineKind.crane ? hoistM : 0,
      speedMps: speedMps,
      direction: direction,
      distanceM: remainingM,
      distanceTravelledM: distanceTravelledM,
      remainingM: remainingM,
      batteryPercent: battery,
      load: loadStatus,
      loadPercent: loadStatus == 'LOADED' ? 82 : 0,
      temperatureC: temperature,
      connection: 'online',
      activeMission: mission,
      safetyState: safety,
      trolleyM: trolleyM,
      gantryM: 0,
      hoistM: hoistM,
      emergencyStop: estop,
      simulated: true,
      feedbackSource: 'watchdog',
      timestamp: now,
    );
  }
}

class MockMachineDataProvider implements MachineDataProvider {
  MockMachineDataProvider({required List<OperationalMachine> fleet}) {
    for (final machine in fleet) {
      _sim[machine.id] = _SimMachine(machine);
    }
  }

  final Map<String, _SimMachine> _sim = {};
  final StreamController<MachineRealtimeTelemetry> _telemetry =
      StreamController<MachineRealtimeTelemetry>.broadcast();
  final StreamController<CommandAck> _acks =
      StreamController<CommandAck>.broadcast();
  final StreamController<MachineEvent> _events =
      StreamController<MachineEvent>.broadcast();

  Timer? _ticker;
  bool _started = false;

  @override
  RealtimeMode get mode => RealtimeMode.mock;

  @override
  MachineConnectionState get connectionState => MachineConnectionState.online;

  @override
  bool get backendReachable => true;

  @override
  String get statusLabel => 'SIMULATED';

  @override
  Stream<MachineRealtimeTelemetry> get telemetryStream => _telemetry.stream;

  @override
  Stream<CommandAck> get commandAcks => _acks.stream;

  @override
  Stream<MachineEvent> get events => _events.stream;

  @override
  void start() {
    if (_started) return;
    _started = true;
    _emitAll(DateTime.now());
    _ticker = Timer.periodic(RealtimeConfig.mockTick, (_) => _emitAll(DateTime.now()));
  }

  void _emitAll(DateTime now) {
    for (final sim in _sim.values) {
      _telemetry.add(sim.toFrame(now));
    }
    _emitEvent(MachineEvent(
      type: 'heartbeat',
      machineId: 'gateway',
      severity: 'debug',
      timestamp: now,
      mock: true,
    ));
  }

  void _emitEvent(MachineEvent event) {
    if (event.mock && !_events.isClosed) _events.add(event);
  }

  void _emitAck(CommandAck ack) {
    if (!_acks.isClosed) _acks.add(ack);
  }

  @override
  Future<void> subscribeTo(OperationalMachine machine) async {}

  @override
  Future<void> unsubscribeFrom(OperationalMachine machine) async {}

  @override
  Future<CommandAck> sendCommand(MachineCommandEnvelope envelope) async {
    final sim = _sim[envelope.machineId];
    if (sim == null) {
      return CommandAck(
        commandId: _nextId(),
        machineId: envelope.machineId,
        command: envelope.command,
        stage: CommandStage.failed,
        message: 'Unknown machine: ${envelope.machineId}',
        mock: true,
      );
    }

    if (sim.estop && envelope.command != MachineCommandSets.emergencyStop) {
      return CommandAck(
        commandId: _nextId(),
        machineId: envelope.machineId,
        command: envelope.command,
        stage: CommandStage.rejected,
        message: 'MACHINE UNDER EMERGENCY STOP - restore before commanding',
        mock: true,
        timestamp: DateTime.now(),
      );
    }

    final id = _nextId();
    if (envelope.command == MachineCommandSets.emergencyStop) {
      _emitAck(CommandAck(
        commandId: id,
        machineId: envelope.machineId,
        command: envelope.command,
        stage: CommandStage.estopRequested,
        message: 'E-STOP requested',
        mock: true,
        timestamp: DateTime.now(),
      ));
      sim.estop = true;
      sim.speedMps = 0;
      sim.state = 'estop';
      sim.remainingM = 0;
      sim.safety = 'emergency_stop';
      _telemetry.add(sim.toFrame(DateTime.now()));
      _emitEvent(MachineEvent(
        type: 'emergency_stop',
        machineId: envelope.machineId,
        message: 'Emergency stop requested (simulated)',
        severity: 'critical',
        mock: true,
        timestamp: DateTime.now(),
      ));
      unawaited(Future<void>.delayed(
        const Duration(milliseconds: 700),
        () {
          _emitAck(CommandAck(
            commandId: id,
            machineId: envelope.machineId,
            command: envelope.command,
            stage: CommandStage.estopConfirmed,
            message: 'E-STOP confirmed by machine',
            mock: true,
            timestamp: DateTime.now(),
          ));
        },
      ));
      return CommandAck(
        commandId: id,
        machineId: envelope.machineId,
        command: envelope.command,
        stage: CommandStage.estopRequested,
        message: 'E-STOP requested',
        mock: true,
        timestamp: DateTime.now(),
      );
    }

    final isAgv = sim.machine.kind == MachineKind.agv;
    final distanceMm = envelope.distanceMm ?? 0;
    final distanceM = distanceMm / 1000;
    final speedMps = (envelope.speedMps ?? 1.0).clamp(0.1, 2.0);

    var durationMs = envelope.durationMs ?? 1000;
    if (envelope.direction != null && distanceM > 0 && envelope.durationMs == null) {
      durationMs = (distanceM / speedMps * 1000).round().clamp(200, 60000);
    }
    if (!isAgv && envelope.direction == null && envelope.distanceMm != null) {
      durationMs = 1500;
    }

    // Movement / action commands follow the full lifecycle.
    _emitAck(CommandAck(
      commandId: id,
      machineId: envelope.machineId,
      command: envelope.command,
      stage: CommandStage.sent,
      message: 'command sent',
      distanceRequestedMm: distanceMm,
      distanceRemainingMm: distanceMm,
      estimatedDurationMs: durationMs,
      mock: true,
      timestamp: DateTime.now(),
    ));

    final isMove = envelope.direction != null || !isAgv && envelope.distanceMm != null;
    unawaited(_runLifecycle(sim, envelope, id, distanceMm, distanceM, speedMps,
        durationMs, isMove));

    return CommandAck(
      commandId: id,
      machineId: envelope.machineId,
      command: envelope.command,
      stage: CommandStage.sent,
      message: 'command sent (SIMULATED)',
      distanceRequestedMm: distanceMm,
      distanceRemainingMm: distanceMm,
      estimatedDurationMs: durationMs,
      mock: true,
      timestamp: DateTime.now(),
    );
  }

  Future<void> _runLifecycle(
    _SimMachine sim,
    MachineCommandEnvelope envelope,
    String id,
    double distanceMm,
    double distanceM,
    double speedMps,
    int durationMs,
    bool isMove,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (_acks.isClosed) return;

    _emitAck(CommandAck(
      commandId: id,
      machineId: envelope.machineId,
      command: envelope.command,
      stage: CommandStage.acknowledged,
      message: 'machine acknowledged',
      distanceRequestedMm: distanceMm,
      distanceRemainingMm: distanceMm,
      mock: true,
      timestamp: DateTime.now(),
    ));

    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (_acks.isClosed || sim.estop) {
      if (!_acks.isClosed) {
        _emitAck(CommandAck(
          commandId: id,
          machineId: envelope.machineId,
          command: envelope.command,
          stage: CommandStage.failed,
          message: sim.estop ? 'interrupted by emergency stop' : 'cancelled',
          mock: true,
          timestamp: DateTime.now(),
        ));
      }
      return;
    }
    _emitAck(CommandAck(
      commandId: id,
      machineId: envelope.machineId,
      command: envelope.command,
      stage: CommandStage.executing,
      message: isMove ? 'executing move' : 'executing',
      distanceRequestedMm: distanceMm,
      distanceRemainingMm: distanceMm,
      mock: true,
      timestamp: DateTime.now(),
    ));

    if (isMove) {
      sim.state = 'moving';
      sim.safety = 'clear';
      sim.speedMps = speedMps;
      sim.direction = envelope.direction ?? 'moving';
      sim.remainingM = distanceM;
      _telemetry.add(sim.toFrame(DateTime.now()));
      _emitEvent(MachineEvent(
        type: 'machine_moving',
        machineId: envelope.machineId,
        message: '${sim.machine.name} moving (simulated)',
        mock: true,
        timestamp: DateTime.now(),
      ));
    } else {
      // Non-movement commands (grab/release/blink) complete quickly.
      if (envelope.command == 'grab') sim.loadStatus = 'LOADED';
      if (envelope.command == 'release') sim.loadStatus = 'EMPTY';
    }

    final steps = math.max(1, (durationMs ~/ 200));
    for (var i = 1; i <= steps && !sim.estop; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (_acks.isClosed) return;
      if (isMove && !sim.estop) {
        final fraction = i / steps;
        sim.remainingM = math.max(0, distanceM * (1 - fraction));
        sim.distanceTravelledM += distanceM / steps;
        sim.posX += (envelope.direction == 'forward' ? 1 : envelope.direction == 'backward' ? -1 : 0) *
            distanceM / steps;
        sim.posY += (envelope.direction == 'left' ? -1 : envelope.direction == 'right' ? 1 : 0) *
            distanceM / steps;
        sim.battery = math.max(0, sim.battery - 0.02);
        _emitAck(CommandAck(
          commandId: id,
          machineId: envelope.machineId,
          command: envelope.command,
          stage: CommandStage.executing,
          message: 'moving',
          distanceRequestedMm: distanceMm,
          distanceMovedMm: distanceMm * (1 - sim.remainingM / distanceM),
          distanceRemainingMm: sim.remainingM * 1000,
          estimatedDurationMs: durationMs,
          mock: true,
          timestamp: DateTime.now(),
        ));
        _telemetry.add(sim.toFrame(DateTime.now()));
      }
    }

    if (sim.estop) return;

    sim.state = 'idle';
    sim.speedMps = 0;
    sim.direction = 'stopped';
    sim.remainingM = 0;
    sim.safety = 'clear';
    _telemetry.add(sim.toFrame(DateTime.now()));
    _emitAck(CommandAck(
      commandId: id,
      machineId: envelope.machineId,
      command: envelope.command,
      stage: CommandStage.completed,
      message: 'command completed (SIMULATED)',
      distanceRequestedMm: distanceMm,
      distanceMovedMm: distanceMm,
      distanceRemainingMm: 0,
      mock: true,
      timestamp: DateTime.now(),
    ));
  }

  @override
  Future<CommandAck> emergencyStop(OperationalMachine machine) {
    return sendCommand(MachineCommandEnvelope(
      machineId: machine.id,
      command: MachineCommandSets.emergencyStop,
    ));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _telemetry.close();
    _acks.close();
    _events.close();
  }

  static int _counter = 0;
  String _nextId() {
    _counter++;
    return 'sim-${DateTime.now().millisecondsSinceEpoch}-$_counter';
  }
}

// ─────────────────────────────────────────────────────────────────────────
// WEBSOCKET PROVIDER (live FastAPI gateway)
// ─────────────────────────────────────────────────────────────────────────

class WebSocketMachineDataProvider implements MachineDataProvider {
  WebSocketMachineDataProvider({
    required MachineControlService http,
    MachineRealtimeService? realtime,
  })  : _http = http,
        _realtime = realtime ?? MachineRealtimeService();

  final MachineControlService _http;
  final MachineRealtimeService _realtime;
  final StreamController<MachineRealtimeTelemetry> _telemetry =
      StreamController<MachineRealtimeTelemetry>.broadcast();
  final StreamController<CommandAck> _acks =
      StreamController<CommandAck>.broadcast();
  final StreamController<MachineEvent> _events =
      StreamController<MachineEvent>.broadcast();

  StreamSubscription<MachineConnectionState>? _connectionSub;
  StreamSubscription<RealtimeServerMessage>? _messageSub;
  bool _started = false;

  @override
  RealtimeMode get mode => RealtimeMode.websocket;

  @override
  MachineConnectionState get connectionState => _realtime.connectionState;

  @override
  bool get backendReachable =>
      _realtime.connectionState != MachineConnectionState.offline;

  @override
  String get statusLabel => switch (_realtime.connectionState) {
        MachineConnectionState.online => 'LINKED',
        MachineConnectionState.connecting => 'CONNECTING',
        MachineConnectionState.degraded => 'DEGRADED',
        MachineConnectionState.offline => 'OFFLINE',
      };

  @override
  Stream<MachineRealtimeTelemetry> get telemetryStream => _telemetry.stream;

  @override
  Stream<CommandAck> get commandAcks => _acks.stream;

  @override
  Stream<MachineEvent> get events => _events.stream;

  @override
  void start() {
    if (_started) return;
    _started = true;
    _messageSub = _realtime.messages.listen((message) {
      switch (message) {
        case TelemetryMessage(:final telemetry):
          _telemetry.add(telemetry);
        case CommandAckMessage(:final ack):
          _acks.add(ack);
        case EventMessage(:final event):
          _events.add(event);
        case GatewayConnectionMessage():
          break;
      }
    });
    _connectionSub = _realtime.connections.listen((_) {
      // Connection state is polled through the controller tick; nothing to
      // forward on the telemetry stream.
    });
    _realtime.connect();
  }

  @override
  Future<void> subscribeTo(OperationalMachine machine) async {
    await _realtime.subscribe([machine.backendId ?? machine.id]);
  }

  @override
  Future<void> unsubscribeFrom(OperationalMachine machine) async {
    await _realtime.unsubscribe([machine.backendId ?? machine.id]);
  }

  @override
  Future<CommandAck> sendCommand(MachineCommandEnvelope envelope) async {
    try {
      final record = await _http.sendMachineCommand(envelope.machineId, envelope.toJson());
      final stage = parseCommandStage(record['stage'] ?? record['status'] ?? 'sent');
      return CommandAck(
        commandId: _idOf(record),
        machineId: envelope.machineId,
        command: envelope.command,
        stage: stage == CommandStage.executing ? CommandStage.sent : stage,
        message: record['message'] ?? _stageMessage(stage),
        distanceRequestedMm: _doubleOf(record['distance_requested_mm']),
        estimatedDurationMs: _intOf(record['estimated_duration_ms']),
        timestamp: DateTime.now(),
      );
    } on MachineControlException catch (error) {
      return CommandAck(
        commandId: '',
        machineId: envelope.machineId,
        command: envelope.command,
        stage: CommandStage.failed,
        message: error.message,
        timestamp: DateTime.now(),
      );
    }
  }

  @override
  Future<CommandAck> emergencyStop(OperationalMachine machine) async {
    return sendCommand(MachineCommandEnvelope(
      machineId: machine.backendId ?? machine.id,
      command: MachineCommandSets.emergencyStop,
    ));
  }

  @override
  void dispose() {
    _connectionSub?.cancel();
    _messageSub?.cancel();
    _realtime.dispose();
    _telemetry.close();
    _acks.close();
    _events.close();
  }

  static String _idOf(Map<String, dynamic> record) {
    final id = record['id'];
    if (id is String || id is num) return id.toString();
    return '';
  }

  static double _doubleOf(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  static int _intOf(dynamic value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static String _stageMessage(CommandStage stage) {
    switch (stage) {
      case CommandStage.sent:
        return 'command accepted';
      case CommandStage.acknowledged:
        return 'machine acknowledged';
      case CommandStage.executing:
        return 'executing';
      case CommandStage.completed:
        return 'completed';
      case CommandStage.rejected:
        return 'rejected';
      case CommandStage.failed:
        return 'failed';
      case CommandStage.estopRequested:
        return 'E-STOP requested';
      case CommandStage.estopConfirmed:
        return 'E-STOP confirmed';
    }
  }
}

(double, double) _basePosition(OperationalMachine machine) {
  switch (machine.name) {
    case 'AGV-01':
      return (124.5, 82.3);
    case 'AGV-02':
      return (190.4, 146.7);
    case 'AGV-03':
      return (12.0, 244.3);
    case 'CRANE-01':
      return (60.0, 0);
    case 'CRANE-02':
      return (120.0, 0);
    default:
      return (0, 0);
  }
}