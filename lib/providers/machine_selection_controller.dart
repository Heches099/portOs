import 'dart:async';

import 'package:flutter/material.dart';

import '../config/realtime_config.dart';
import '../models/machine_command.dart';
import '../models/operational_machine.dart';
import '../models/ppe_detection_result.dart';
import '../models/realtime_message.dart';
import '../models/realtime_telemetry.dart';
import '../services/machine_control_service.dart';
import '../theme/industrial_theme.dart';
import 'machine_data_provider.dart';

export '../models/operational_machine.dart';

/// Shared operational state for the Live Operations workspace.
///
/// This is the SINGLE source of context for the workspace: whichever machine
/// is selected here determines the camera, telemetry, controls, AI result,
/// mission and safety state shown everywhere else.
///
/// All realtime data flows in through a [MachineDataProvider] (mock for
/// development, WebSocket for the real FastAPI gateway), never through
/// hard-coded production values.
class MachineSelectionController extends ChangeNotifier {
  factory MachineSelectionController({
    MachineControlService? service,
    MachineDataProvider? dataProvider,
  }) {
    final svc = service ?? MachineControlService();
    return MachineSelectionController._(
      svc,
      dataProvider ??
          createDefaultDataProvider(service: svc, fleet: kOperationalFleet),
    );
  }

  MachineSelectionController._(this._service, this._dataProvider) {
    _fleet = kOperationalFleet;
    _selectedId = kOperationalFleet.first.id;
    _loadFallbackTimer();
    _wireProvider();
    _dataProvider.start();
    for (final machine in _fleet) {
      if (machine.backendId != null) {
        _dataProvider.subscribeTo(machine);
      }
    }
    _tick();
  }

  final MachineControlService _service;
  final MachineDataProvider _dataProvider;

  late final List<OperationalMachine> _fleet;
  late String _selectedId;

  Timer? _ticker;
  bool _loading = true;

  final Map<String, MachineTelemetrySnapshot> _telemetry = {};
  final Map<String, DateTime> _lastFrameAt = {};
  final Map<String, _EstopState> _eStop = {};
  final Map<String, CommandAck> _lastAck = {};

  // Shared AI vision state (written by the camera panel).
  PpeDetectionResult? _aiResult;
  bool _aiScanning = false;
  String? _aiError;

  bool _commandExecuting = false;
  String? _lastCommandResult;
  final List<MachineEvent> _recentEvents = [];

  List<OperationalMachine> get fleet => List.unmodifiable(_fleet);
  OperationalMachine get selectedMachine => _byId(_selectedId);
  bool get loading => _loading;
  bool get backendReachable => _dataProvider.backendReachable;
  String? get backendError => _lastCommandResult;

  bool get commandExecuting => _commandExecuting;
  String? get lastCommandResult => _lastCommandResult;

  PpeDetectionResult? get aiResult => _aiResult;
  bool get aiScanning => _aiScanning;
  String? get aiError => _aiError;

  /// Gateway-level connection state (mock vs live WebSocket).
  MachineConnectionState get gatewayConnection =>
      _dataProvider.connectionState;

  /// Whether the active telemetry pipeline represents simulated or real
  /// hardware. Driven by the backend `simulated` frame flag (the backend is
  /// authoritative) and never silently guessed by the UI.
  late bool _simulatedMode = _dataProvider.mode == RealtimeMode.mock;
  bool get simulatedMode => _simulatedMode;

  MachineDataProvider get dataProvider => _dataProvider;
  MachineControlService get controlService => _service;

  MachineTelemetrySnapshot get telemetry =>
      _telemetry[_selectedId] ?? MachineTelemetrySnapshot.idle;

  /// Most recent command acknowledgement for the selected machine.
  CommandAck? get activeAck => _lastAck[_selectedId];

  List<MachineEvent> get recentEvents => List.unmodifiable(_recentEvents);

  MachineTelemetrySnapshot? snapshotFor(String id) => _telemetry[id];

  OperationalMachine? byId(String id) => _byIdOrNull(id);

  bool isSelected(String id) => _selectedId == id;

  OperationalMachine _byId(String id) {
    return _fleet.firstWhere((m) => m.id == id);
  }

  OperationalMachine? _byIdOrNull(String id) {
    for (final machine in _fleet) {
      if (machine.id == id) return machine;
    }
    return null;
  }

  // ---------------------------------------------------------------------
  // Provider wiring
  // ---------------------------------------------------------------------

  void _wireProvider() {
    _dataProvider.telemetryStream.listen(_onTelemetry);
    _dataProvider.commandAcks.listen(_onCommandAck);
    _dataProvider.events.listen(_onEvent);
  }

  void _onTelemetry(MachineRealtimeTelemetry frame) {
    final machine = _matchMachine(frame.machineId);
    if (machine == null) return;

    _simulatedMode = frame.simulated;
    _lastFrameAt[machine.id] = frame.timestamp ?? DateTime.now();
    _telemetry[machine.id] =
        _snapshotFromRealtime(machine, frame, _telemetry[machine.id]);
    _loading = false;

    if (frame.emergencyStop && _eStop[machine.id] != _EstopState.confirmed) {
      _eStop[machine.id] = _EstopState.confirmed;
    }
    notifyListeners();
  }

  void _onCommandAck(CommandAck ack) {
    final machine = _matchMachine(ack.machineId);
    if (machine == null) return;

    _lastAck[machine.id] = ack;

    switch (ack.stage) {
      case CommandStage.sent || CommandStage.acknowledged:
        _commandExecuting = true;
        _lastCommandResult = null;
      case CommandStage.executing:
        _commandExecuting = true;
      case CommandStage.completed:
        _commandExecuting = false;
      case CommandStage.failed || CommandStage.rejected:
        _commandExecuting = false;
        _lastCommandResult = ack.message.isNotEmpty ? ack.message : ack.stage.name;
      case CommandStage.estopRequested:
        _eStop[machine.id] = _EstopState.requested;
        _commandExecuting = true;
      case CommandStage.estopConfirmed:
        _eStop[machine.id] = _EstopState.confirmed;
        _commandExecuting = false;
        _applyEstopToSnapshot(machine.id);
    }
    notifyListeners();
  }

  void _onEvent(MachineEvent event) {
    if (event.mock || event.type == 'heartbeat') {
      // Mock heartbeat noise is not interesting to the operator.
    }
    if (event.machineId == 'gateway') {
      return;
    }
    _recentEvents.insert(0, event);
    if (_recentEvents.length > 30) _recentEvents.removeLast();

    final machine = _matchMachine(event.machineId);
    if (machine != null) {
      final snapshot = _telemetry[machine.id];
      if (snapshot != null && (event.isWarning || event.type == 'emergency_stop')) {
        _telemetry[machine.id] = snapshot.copyWith(
          safetyStatus: event.type == 'emergency_stop'
              ? 'EMERGENCY'
              : 'ALARM',
          safetyColor: IndustrialTheme.danger,
        );
      }
    }
    notifyListeners();
  }

  OperationalMachine? _matchMachine(String machineId) {
    for (final machine in _fleet) {
      if (machine.id == machineId ||
          machine.backendId == machineId ||
          machine.name.toLowerCase() == machineId.toLowerCase()) {
        return machine;
      }
    }
    return null;
  }

  void _applyEstopToSnapshot(String id) {
    final snapshot = _telemetry[id];
    if (snapshot == null) return;
    _telemetry[id] = snapshot.copyWith(
      stateLabel: 'EST\u00ADSTOP',
      stateColor: IndustrialTheme.danger,
      speed: 0,
      connected: false,
      safetyStatus: 'EMERGENCY',
      safetyColor: IndustrialTheme.danger,
    );
  }

  void _loadFallbackTimer() {
    Timer(const Duration(seconds: 4), () {
      if (_loading) {
        _loading = false;
        notifyListeners();
      }
    });
  }

  // ---------------------------------------------------------------------
  // Selection
  // ---------------------------------------------------------------------

  Future<void> select(String id) async {
    final machine = _byIdOrNull(id);
    if (machine == null || _selectedId == id) return;
    _selectedId = id;
    _lastCommandResult = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Per-machine status used by the fleet sidebar.
  // ---------------------------------------------------------------------

  String stateLabelFor(String id) => _telemetry[id]?.stateLabel ?? '--';

  Color stateColorFor(String id) => _telemetry[id]?.stateColor ?? IndustrialTheme.idle;

  bool connectedFor(String id) {
    final snapshot = _telemetry[id];
    if (snapshot == null) return false;
    return connectionStateFor(id) == MachineConnectionState.online;
  }

  String missionFor(String id) {
    final mission = _telemetry[id]?.mission;
    return (mission == null || mission.isEmpty) ? '--' : mission;
  }

  MachineConnectionState connectionStateFor(String id) {
    if (_dataProvider.mode == RealtimeMode.mock) {
      return _telemetry[id] != null
          ? MachineConnectionState.online
          : MachineConnectionState.offline;
    }
    final last = _lastFrameAt[id];
    if (last == null) {
      return _dataProvider.connectionState == MachineConnectionState.online
          ? MachineConnectionState.connecting
          : _dataProvider.connectionState;
    }
    final age = DateTime.now().difference(last);
    if (age > RealtimeConfig.telemetryStaleAfter * 2) {
      return MachineConnectionState.offline;
    }
    if (age > RealtimeConfig.telemetryStaleAfter) {
      return MachineConnectionState.degraded;
    }
    return MachineConnectionState.online;
  }

  String connectionLabelFor(String id) {
    switch (connectionStateFor(id)) {
      case MachineConnectionState.online:
        return 'ONLINE';
      case MachineConnectionState.connecting:
        return 'CONNECTING';
      case MachineConnectionState.degraded:
        return 'DEGRADED';
      case MachineConnectionState.offline:
        return 'OFFLINE';
    }
  }

  bool isTelemetryStaleFor(String id) {
    return connectionStateFor(id) != MachineConnectionState.online &&
        _dataProvider.mode == RealtimeMode.websocket;
  }

  Duration? telemetryAgeFor(String id) {
    final last = _lastFrameAt[id];
    if (last == null) return null;
    return DateTime.now().difference(last);
  }

  _EstopState _estopStateFor(String id) => _eStop[id] ?? _EstopState.none;

  String? estopLabelFor(String id) => switch (_estopStateFor(id)) {
        _EstopState.none => null,
        _EstopState.requested => 'E-STOP REQUESTED',
        _EstopState.confirmed => 'E-STOP CONFIRMED',
      };

  bool get selectedEmergencyStop => _estopStateFor(_selectedId) != _EstopState.none;

  bool get selectedLinked {
    final machine = selectedMachine;
    return connectedFor(machine.id);
  }

  // ---------------------------------------------------------------------
  // Command helpers
  // ---------------------------------------------------------------------

  /// Submit a structured, distance-first command envelope.
  Future<CommandAck?> sendCommandEnvelope(MachineCommandEnvelope envelope) async {
    _commandExecuting = true;
    _lastCommandResult = null;
    notifyListeners();
    try {
      final ack = await _dataProvider.sendCommand(envelope);
      _onCommandAck(ack);
      return ack;
    } finally {
      // keep the executing flag driven by acks; only clear if nothing followed
      Timer(const Duration(milliseconds: 300), () {
        if (!_commandExecuting) notifyListeners();
      });
    }
  }

  /// Legacy convenience: builds a structured envelope from low-level params.
  Future<CommandAck?> sendCommand(
    String command, {
    String? direction,
    double? distanceMm,
    double? speedMps,
    int? durationMs,
    int? steps,
  }) async {
    final machine = _byId(_selectedId);
    final envelope = MachineCommandEnvelope(
      machineId: machine.id,
      command: command,
      direction: direction,
      distanceMm: distanceMm,
      speedMps: speedMps,
      durationMs: durationMs,
      steps: steps,
    );
    return sendCommandEnvelope(envelope);
  }

  Future<void> emergencyStop() async {
    final machine = _byId(_selectedId);
    final ack = await _dataProvider.emergencyStop(machine);
    _onCommandAck(ack);
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // AI vision state (shared with camera panel and telemetry bar)
  // ---------------------------------------------------------------------

  void setAiScanning(bool scanning) {
    _aiScanning = scanning;
    notifyListeners();
  }

  void setAiResult(PpeDetectionResult? result, {String? error}) {
    _aiResult = result;
    _aiError = error;
    notifyListeners();
  }

  void clearAiResult() {
    _aiResult = null;
    _aiError = null;
    notifyListeners();
  }

  String get statusLabel {
    if (_dataProvider.mode == RealtimeMode.mock) {
      return 'SIMULATED';
    }
    return switch (_dataProvider.connectionState) {
      MachineConnectionState.online =>
        selectedLinked ? 'LINKED' : 'CONNECTING',
      MachineConnectionState.connecting => 'CONNECTING',
      MachineConnectionState.degraded => 'DEGRADED',
      MachineConnectionState.offline => 'OFFLINE',
    };
  }

  // ---------------------------------------------------------------------
  // Snapshot rendering
  // ---------------------------------------------------------------------

  MachineTelemetrySnapshot _snapshotFromRealtime(
    OperationalMachine machine,
    MachineRealtimeTelemetry frame,
    MachineTelemetrySnapshot? previous,
  ) {
    final stateLabel = switch (frame.state.toLowerCase()) {
      'estop' || 'emergency' => 'E-STOP',
      'moving' || 'running' || 'in_progress' => 'MOVING',
      'charging' => 'CHARGING',
      'error' || 'fault' => 'FAULT',
      'idle' => 'IDLE',
      _ => frame.state.toUpperCase(),
    };
    final stateColor = switch (frame.state.toLowerCase()) {
      'estop' || 'emergency' || 'error' || 'fault' => IndustrialTheme.danger,
      'moving' || 'running' || 'in_progress' => IndustrialTheme.ready,
      'charging' => IndustrialTheme.warn,
      _ => IndustrialTheme.control,
    };
    final safetyOk =
        frame.safetyState.toLowerCase() == 'safe' ||
        frame.safetyState.toLowerCase() == 'clear';
    final loadStatus = frame.load.isNotEmpty && frame.load != 'EMPTY'
        ? 'LOADED'
        : 'EMPTY';

    return MachineTelemetrySnapshot(
      positionX: frame.positionX,
      positionY: frame.positionY,
      destination: machine.kicker,
      distanceTravelled: frame.distanceTravelledM,
      remainingDistance: frame.remainingM,
      speed: frame.speedMps,
      direction: frame.direction.toUpperCase(),
      battery: frame.batteryPercent,
      temperature: frame.temperatureC,
      loadStatus: loadStatus,
      connected: frame.connectionState == MachineConnectionState.online,
      stateLabel: stateLabel,
      stateColor: stateColor,
      trolliePosition: frame.trolleyM,
      hoistHeight: frame.hoistM,
      targetPosition: frame.isCrane ? frame.gantryM : 0,
      containerId: frame.load.isNotEmpty ? frame.load : '--',
      safetyStatus: frame.emergencyStop
          ? 'EMERGENCY'
          : safetyOk
              ? 'CLEAR'
              : 'ALARM',
      safetyColor: frame.emergencyStop || !safetyOk
          ? IndustrialTheme.danger
          : IndustrialTheme.ready,
      mission: frame.activeMission.isEmpty ? '--' : frame.activeMission,
      connection: frame.connectionState,
      lastTelemetryAt: frame.timestamp ?? DateTime.now(),
    );
  }

  // ---------------------------------------------------------------------
  // Ticker for live ages + stale transitions.
  // ---------------------------------------------------------------------

  void _tick() {
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (_dataProvider.mode == RealtimeMode.websocket) {
        var dirty = false;
        for (final machine in _fleet) {
          if (isTelemetryStaleFor(machine.id)) {
            final snapshot = _telemetry[machine.id];
            if (snapshot != null && snapshot.connected) {
              _telemetry[machine.id] = snapshot.copyWith(connected: false);
              dirty = true;
            }
          }
        }
        if (dirty || _connectionChanged()) {
          notifyListeners();
        }
      }
    });
  }

  bool _lastGatewayState = false;
  bool _connectionChanged() {
    final current = _dataProvider.connectionState == MachineConnectionState.online;
    final changed = current != _lastGatewayState;
    _lastGatewayState = current;
    return changed;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _dataProvider.dispose();
    _service.dispose();
    super.dispose();
  }
}

enum _EstopState { none, requested, confirmed }