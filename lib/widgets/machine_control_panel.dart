import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/machine_command.dart';
import '../models/realtime_message.dart';
import '../providers/machine_selection_controller.dart';
import '../theme/industrial_theme.dart';
import '../utils/movement_calibration.dart';

enum _MoveMode { distance, time }

enum _DistanceUnit { mm, cm, m }

/// Context-aware machine control panel for the Live Operations workspace.
///
/// Rebuilds whenever the selected machine changes so the operator always
/// controls the machine they are watching. Movement is distance-first
/// (see [MovementCalibration]); timed commands remain available for delays,
/// timeouts and scheduled actions.
class MachineControlPanel extends StatefulWidget {
  const MachineControlPanel({super.key, this.compact = false, this.showEStop = true});

  final bool compact;

  /// When false the full-width emergency stop button is omitted, allowing the
  /// parent to surface a dedicated always-visible stop control instead.
  final bool showEStop;

  @override
  State<MachineControlPanel> createState() => _MachineControlPanelState();
}

class _MachineControlPanelState extends State<MachineControlPanel> {
  String? _lastMachineId;
  String? _pending;
  _MoveMode _mode = _MoveMode.distance;
  double _speed = 1.2;
  double _durationSeconds = 3;
  double _distance = 50;
  _DistanceUnit _distanceUnit = _DistanceUnit.cm;
  String? _lastError;
  bool _confirmingEstop = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = context.read<MachineSelectionController>();
    final id = controller.selectedMachine.id;
    if (id != _lastMachineId) {
      _lastMachineId = id;
      _pending = null;
      _lastError = null;
      _distanceUnit =
          controller.selectedMachine.kind == MachineKind.crane
              ? _DistanceUnit.mm
              : _DistanceUnit.cm;
      _distance = controller.selectedMachine.kind == MachineKind.crane ? 200 : 50;
    }
  }

  double get _distanceValueMm => switch (_distanceUnit) {
        _DistanceUnit.mm => _distance,
        _DistanceUnit.cm => _distance * 10,
        _DistanceUnit.m => _distance * 1000,
      };

  (double, double) get _distanceBounds => switch (_distanceUnit) {
        _DistanceUnit.mm => (5, 2000),
        _DistanceUnit.cm => (5, 500),
        _DistanceUnit.m => (0.5, 50),
      };

  String _formatDistance(double v) => switch (_distanceUnit) {
        _DistanceUnit.mm || _DistanceUnit.cm => v.toStringAsFixed(0),
        _DistanceUnit.m => v.toStringAsFixed(1),
      };

  String _unitSymbol() => switch (_distanceUnit) {
        _DistanceUnit.mm => 'mm',
        _DistanceUnit.cm => 'cm',
        _DistanceUnit.m => 'm',
      };

  int get _durationMs => (_durationSeconds * 1000).round().clamp(100, 60000);

  void _arm(String command) {
    if (_pending == command) {
      setState(() {
        _pending = null;
        _lastError = null;
      });
      return;
    }
    setState(() {
      _pending = command;
      _lastError = null;
    });
  }

  String _pendingReadout(String command,
      {required bool isAgv, required MovementCalibration calibration}) {
    final c = command.toUpperCase();
    if (command == 'stop') return c;
    if (_mode == _MoveMode.distance) {
      return '$c · EST ${_formatDistance(_distance)}${_unitSymbol()}';
    }
    if (isAgv) {
      return '$c · ${_durationSeconds.toStringAsFixed(1)}s @ ${(_speed / 1.2 * 100).round()}%';
    }
    return '$c · ${_speed.toStringAsFixed(1)} × ${_durationSeconds.toStringAsFixed(1)}s';
  }

  Future<void> _execute(String command) async {
    final controller = context.read<MachineSelectionController>();
    final machine = controller.selectedMachine;
    final isAgv = machine.kind == MachineKind.agv;
    final calibration = isAgv ? agvCalibration : craneCalibration;

    int? steps;
    int? durationMs;

    if (isAgv) {
      if (_mode == _MoveMode.distance && command != 'stop' && command != 'blink') {
        final speedFraction = (_speed / 1.2).clamp(0.1, 1.0);
        durationMs = calibration.distanceMmToDurationMs(
          distanceMm: _distanceValueMm,
          speedFraction: speedFraction,
        );
      } else if (_mode == _MoveMode.time && command != 'stop' && command != 'blink') {
        durationMs = _durationMs;
      }
    } else if (command != 'stop' &&
        command != 'magnet_on' &&
        command != 'magnet_off') {
      if (_mode == _MoveMode.distance) {
        steps = calibration.distanceMmToSteps(distanceMm: _distanceValueMm);
      } else {
        steps = (_speed * _durationSeconds).round().clamp(1, 10000);
      }
    }

    final structured = command != 'blink' &&
        command != 'magnet_on' &&
        command != 'magnet_off';

    setState(() => _lastError = null);
    final envelope = MachineCommandEnvelope(
      machineId: machine.id,
      command: command,
      direction: structured ? command : null,
      distanceMm: _mode == _MoveMode.distance && structured
          ? _distanceValueMm
          : null,
      speedMps: structured ? (isAgv ? _speed : null) : null,
      durationMs: _mode == _MoveMode.time && structured ? durationMs : null,
      steps: structured && !isAgv && _mode == _MoveMode.time && steps != null
          ? steps
          : null,
    );

    final ack = await controller.sendCommandEnvelope(envelope);
    if (!mounted) return;
    if (ack == null ||
        ack.stage == CommandStage.rejected ||
        ack.stage == CommandStage.failed) {
      setState(() {
        final ackMessage =
            ack != null && ack.message.isNotEmpty ? ack.message : null;
        _lastError =
            ackMessage ?? controller.lastCommandResult ?? 'Command failed';
      });
      return;
    }
    setState(() => _pending = null);
    if (command == 'stop') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('STOP command sent'),
          backgroundColor: IndustrialTheme.danger,
          duration: Duration(milliseconds: 900),
        ),
      );
    }
  }

  Future<void> _runPending() async {
    final command = _pending;
    if (command == null) return;
    await _execute(command);
  }

  Future<void> _emergencyStop() async {
    final controller = context.read<MachineSelectionController>();
    if (_confirmingEstop || controller.commandExecuting) return;
    setState(() => _confirmingEstop = true);
    try {
      final confirmed = await confirmOperation(
        context,
        title: 'EMERGENCY STOP ${controller.selectedMachine.name}',
        message:
            'This immediately halts all movement and overrides any active command. '
            'The machine must be re-commanded manually to move again.',
        confirmLabel: 'STOP NOW',
      );
      if (confirmed && mounted) {
        await controller.emergencyStop();
        if (mounted) setState(() => _pending = null);
      }
    } finally {
      if (mounted) setState(() => _confirmingEstop = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<MachineSelectionController>();
    final machine = controller.selectedMachine;
    final telemetry = controller.telemetry;
    final isAgv = machine.kind == MachineKind.agv;
    final executing = controller.commandExecuting;
    final estopLabel = controller.estopLabelFor(machine.id);
    final estopActive = estopLabel != null;
    final movementLocked = executing || estopActive;
    final ack = controller.activeAck;

    return Container(
      decoration: BoxDecoration(
        color: IndustrialTheme.panelDeep,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: IndustrialTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PanelHeader(
            machine: machine,
            telemetry: telemetry,
            statusLabel: controller.statusLabel,
            executing: executing,
          ),
          const Divider(color: IndustrialTheme.border, height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (estopActive) ...[
                    _EstopBanner(label: estopLabel),
                    const SizedBox(height: 10),
                  ],
                  _StatusStrip(telemetry: telemetry, isAgv: isAgv),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text(
                        'MOVEMENT MODE',
                        style: TextStyle(
                          color: IndustrialTheme.textMuted,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(width: 10),
                      _ModeToggle(
                        mode: _mode,
                        onChanged: (m) => setState(() => _mode = m),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isAgv ? 'DRIVE CONTROL' : 'CRANE CONTROL',
                    style: const TextStyle(
                      color: IndustrialTheme.textSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  isAgv
                      ? _AgvDirectionPad(
                          executing: movementLocked,
                          pending: _pending,
                          onCommand: _arm,
                          onStop: _arm,
                        )
                      : _CraneControlPad(
                          executing: movementLocked,
                          pending: _pending,
                          onCommand: _arm,
                          onStop: _arm,
                        ),
                  const SizedBox(height: 14),
                  if (_mode == _MoveMode.distance) ...[
                    _DistancePresets(
                      unit: _distanceUnit,
                      distance: _distance,
                      onUnit: (u) => setState(() => _distanceUnit = u),
                      onApply: (value) {
                        setState(() => _distance = value);
                        _adjustForUnit();
                      },
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(
                          Icons.straighten_rounded,
                          size: 14,
                          color: IndustrialTheme.control,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'CUSTOM DISTANCE',
                          style: TextStyle(
                            color: IndustrialTheme.textMuted,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                          ),
                        ),
                        const Spacer(),
                        _UnitSelector(
                          unit: _distanceUnit,
                          onChanged: (u) => setState(() => _distanceUnit = u),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _DistanceSlider(
                      value: _distance,
                      min: _distanceBounds.$1,
                      max: _distanceBounds.$2,
                      label: '${_formatDistance(_distance)} ${_unitSymbol()}',
                      onChanged: (v) => setState(() => _distance = v),
                    ),
                  ] else ...[
                    _SpeedRow(
                      label: 'Speed',
                      value: _speed,
                      display: '${_speed.toStringAsFixed(2)} m/s',
                      onChanged: (v) => setState(() => _speed = v),
                    ),
                    const SizedBox(height: 4),
                    _SpeedRow(
                      label: 'Duration',
                      value: _durationSeconds,
                      display: '${_durationSeconds.toStringAsFixed(1)} s',
                      min: 0.5,
                      max: 10,
                      onChanged: (v) => setState(() => _durationSeconds = v),
                    ),
                    const SizedBox(height: 4),
                    const _TimedNote(),
                  ],
                  const SizedBox(height: 10),
                  const Divider(color: IndustrialTheme.border, height: 18),
                  _CommandReadout(
                    label: 'COMMAND',
                    value: _pending == null
                        ? 'NONE SELECTED'
                        : _pendingReadout(
                            _pending!,
                            isAgv: isAgv,
                            calibration:
                                isAgv ? agvCalibration : craneCalibration,
                          ),
                    hasPending: _pending != null,
                    onClear: _pending == null
                        ? null
                        : () => setState(() => _pending = null),
                  ),
                  if (_lastError != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: IndustrialTheme.danger.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: IndustrialTheme.danger.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            size: 15,
                            color: IndustrialTheme.danger,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _lastError!,
                              style: const TextStyle(
                                color: IndustrialTheme.danger,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  if (ack != null && !estopActive)
                    _AckLifecycle(ack: ack),
                  if (ack != null && !estopActive) const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        flex: 7,
                        child: SizedBox(
                          height: 42,
                          child: FilledButton(
                            onPressed:
                                (_pending == null || movementLocked) ? null : _runPending,
                            style: FilledButton.styleFrom(
                              backgroundColor: IndustrialTheme.control,
                              disabledBackgroundColor: IndustrialTheme.panelAlt,
                              disabledForegroundColor: IndustrialTheme.textMuted,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text(
                              'EXECUTE',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 3,
                        child: SizedBox(
                          height: 42,
                          child: OutlinedButton(
                            onPressed: movementLocked ? null : () => _arm('stop'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: IndustrialTheme.danger,
                              side: const BorderSide(
                                color: Color(0xFF5A2B2B),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text(
                              'STOP',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (widget.showEStop)
                    _EmergencyStopButton(
                      confirming: _confirmingEstop,
                      executing: executing,
                      onPressed: _emergencyStop,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _adjustForUnit() {
    final bounds = _distanceBounds;
    if (_distance < bounds.$1) _distance = bounds.$1;
    if (_distance > bounds.$2) _distance = bounds.$2;
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({
    required this.machine,
    required this.telemetry,
    required this.statusLabel,
    required this.executing,
  });

  final OperationalMachine machine;
  final MachineTelemetrySnapshot telemetry;
  final String statusLabel;
  final bool executing;

  @override
  Widget build(BuildContext context) {
    final statusColor = telemetry.stateColor;
    final labelColor = switch (statusLabel) {
      'SIMULATED' => IndustrialTheme.warn,
      'LINKED' => IndustrialTheme.ready,
      'OFFLINE' || 'DEGRADED' => IndustrialTheme.danger,
      _ => IndustrialTheme.control,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          Icon(machine.icon, size: 18, color: machine.accent),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'MACHINE CONTROL',
                style: TextStyle(
                  color: machine.accent,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.4,
                ),
              ),
              Row(
                children: [
                  Text(
                    machine.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: statusColor,
                      boxShadow: [
                        BoxShadow(color: statusColor.withValues(alpha: 0.6), blurRadius: 7),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    telemetry.stateLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.7,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                statusLabel,
                style: TextStyle(
                  color: labelColor,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 3),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (executing)
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.8),
                    ),
                  if (executing) const SizedBox(width: 6),
                  Text(
                    executing ? 'SENDING' : 'READY',
                    style: const TextStyle(
                      color: IndustrialTheme.textMuted,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.telemetry, required this.isAgv});

  final MachineTelemetrySnapshot telemetry;
  final bool isAgv;

  @override
  Widget build(BuildContext context) {
    final items = <_StatusItem>[
      _StatusItem(
        label: isAgv ? 'POSITION' : 'GANTRY',
        value: isAgv
            ? 'X: ${telemetry.positionX.toStringAsFixed(1)} m  Y: ${telemetry.positionY.toStringAsFixed(1)} m'
            : '${telemetry.positionX.toStringAsFixed(1)} m',
      ),
      _StatusItem(
        label: 'DESTINATION',
        value: telemetry.destination,
      ),
      if (isAgv)
        _StatusItem(
          label: 'REMAINING',
          value: '${telemetry.remainingDistance.toStringAsFixed(1)} m',
        ),
      if (!isAgv)
        _StatusItem(
          label: 'TROLLEY',
          value: '${telemetry.trolliePosition.toStringAsFixed(2)} m',
        ),
      if (!isAgv)
        _StatusItem(
          label: 'HOIST',
          value: '${telemetry.hoistHeight.toStringAsFixed(1)} m',
        ),
      _StatusItem(
        label: 'SPEED',
        value: '${telemetry.speed.toStringAsFixed(2)} m/s',
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: IndustrialTheme.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: IndustrialTheme.border),
      ),
      child: Wrap(
        spacing: 18,
        runSpacing: 8,
        children: items.map((item) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.label,
                style: const TextStyle(
                  color: IndustrialTheme.textMuted,
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                item.value,
                style: const TextStyle(
                  fontFamily: IndustrialTheme.mono,
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _StatusItem {
  const _StatusItem({required this.label, required this.value});
  final String label;
  final String value;
}

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.mode, required this.onChanged});

  final _MoveMode mode;
  final ValueChanged<_MoveMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: IndustrialTheme.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: IndustrialTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: _MoveMode.values.map((m) {
          final active = mode == m;
          return GestureDetector(
            onTap: () => onChanged(m),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: active ? IndustrialTheme.control.withValues(alpha: 0.2) : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: active ? IndustrialTheme.control : IndustrialTheme.textMuted,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    m == _MoveMode.distance ? 'Distance' : 'Time',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: active ? IndustrialTheme.control : IndustrialTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(growable: false),
      ),
    );
  }
}

class _AgvDirectionPad extends StatelessWidget {
  const _AgvDirectionPad({
    required this.executing,
    required this.pending,
    required this.onCommand,
    required this.onStop,
  });

  final bool executing;
  final String? pending;
  final ValueChanged<String> onCommand;
  final ValueChanged<String> onStop;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(width: 52),
            _PadButton(
              icon: Icons.arrow_upward_rounded,
              label: 'FWD',
              active: pending == 'forward',
              onTap: executing ? null : () => onCommand('forward'),
            ),
            const SizedBox(width: 52),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _PadButton(
              icon: Icons.arrow_back_rounded,
              label: 'LEFT',
              active: pending == 'left',
              onTap: executing ? null : () => onCommand('left'),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: SizedBox(
                width: 48,
                child: Padding(
                  padding: EdgeInsets.only(top: 14),
                  child: Text(
                    'STOP',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: IndustrialTheme.textMuted,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
            ),
            _PadButton(
              icon: Icons.arrow_forward_rounded,
              label: 'RIGHT',
              active: pending == 'right',
              onTap: executing ? null : () => onCommand('right'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(width: 52),
            _PadButton(
              icon: Icons.arrow_downward_rounded,
              label: 'BCK',
              active: pending == 'backward',
              onTap: executing ? null : () => onCommand('backward'),
            ),
            const SizedBox(width: 52),
          ],
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: executing ? null : () => onCommand('blink'),
          icon: const Icon(Icons.lightbulb_outline, size: 15, color: IndustrialTheme.warn),
          label: const Text(
            'BLINK',
            style: TextStyle(
              color: IndustrialTheme.warn,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: IndustrialTheme.warn.withValues(alpha: 0.4)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ],
    );
  }
}

class _CraneControlPad extends StatelessWidget {
  const _CraneControlPad({
    required this.executing,
    required this.pending,
    required this.onCommand,
    required this.onStop,
  });

  final bool executing;
  final String? pending;
  final ValueChanged<String> onCommand;
  final ValueChanged<String> onStop;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _ActionButton(
                icon: Icons.arrow_upward_rounded,
                label: 'UP',
                active: pending == 'hoist_up',
                onPressed: executing ? null : () => onCommand('hoist_up'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ActionButton(
                icon: Icons.arrow_downward_rounded,
                label: 'DOWN',
                active: pending == 'hoist_down',
                onPressed: executing ? null : () => onCommand('hoist_down'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _ActionButton(
                icon: Icons.arrow_back_rounded,
                label: 'TROLLEY <',
                active: pending == 'trolley_forward',
                onPressed: executing ? null : () => onCommand('trolley_forward'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ActionButton(
                icon: Icons.arrow_forward_rounded,
                label: 'TROLLEY >',
                active: pending == 'trolley_backward',
                onPressed: executing ? null : () => onCommand('trolley_backward'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _ActionButton(
                icon: Icons.check_circle_outline,
                label: 'GRAB',
                accent: IndustrialTheme.ready,
                active: pending == 'magnet_on',
                onPressed: executing ? null : () => onCommand('magnet_on'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ActionButton(
                icon: Icons.cancel_outlined,
                label: 'RELEASE',
                accent: IndustrialTheme.textMuted,
                active: pending == 'magnet_off',
                onPressed: executing ? null : () => onCommand('magnet_off'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ActionButton(
                icon: Icons.stop_circle_rounded,
                label: 'STOP',
                accent: IndustrialTheme.danger,
                filled: true,
                active: pending == 'stop',
                onPressed: executing ? null : () => onCommand('stop'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PadButton extends StatelessWidget {
  const _PadButton({
    required this.icon,
    required this.label,
    required this.active,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: active
              ? IndustrialTheme.control.withValues(alpha: 0.18)
              : IndustrialTheme.panel,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? IndustrialTheme.control : IndustrialTheme.border,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 19,
              color: active ? IndustrialTheme.control : Colors.white70,
            ),
            const SizedBox(height: 1),
            Text(
              label,
              style: TextStyle(
                color: active ? IndustrialTheme.control : IndustrialTheme.textMuted,
                fontSize: 8,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.active,
    this.onPressed,
    this.accent = IndustrialTheme.control,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onPressed;
  final Color accent;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: accent,
          disabledForegroundColor: IndustrialTheme.textMuted,
          disabledBackgroundColor: IndustrialTheme.panelAlt,
          side: BorderSide(
            color: active
                ? accent
                : filled
                    ? accent.withValues(alpha: 0.5)
                    : IndustrialTheme.border,
          ),
          backgroundColor: filled || active
              ? accent.withValues(alpha: 0.14)
              : IndustrialTheme.panel,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: EdgeInsets.zero,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 17),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.7,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DistancePresets extends StatelessWidget {
  const _DistancePresets({
    required this.unit,
    required this.distance,
    required this.onUnit,
    required this.onApply,
  });

  final _DistanceUnit unit;
  final double distance;
  final ValueChanged<_DistanceUnit> onUnit;
  final ValueChanged<double> onApply;

  /// mm values: 10 cm, 50 cm, 1 m, 5 m — the operator's primary movement
  /// distances. Selecting one applies the physical distance directly.
  static const _presetsMm = <(String, int)>[
    ('10 cm', 100),
    ('50 cm', 500),
    ('1 m', 1000),
    ('5 m', 5000),
  ];

  @override
  Widget build(BuildContext context) {
    Widget presetRow(String label) {
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          Container(
            alignment: Alignment.centerLeft,
            width: 72,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              label,
              style: const TextStyle(
                color: IndustrialTheme.textSecondary,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
          ),
          ..._presetsMm.map((preset) {
            return _PresetChip(
              label: preset.$1,
              onTap: () => _applyMm(preset.$2),
            );
          }),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        presetRow('MOVE FWD'),
        const SizedBox(height: 4),
        presetRow('MOVE BCK'),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(
              Icons.straighten_rounded,
              size: 14,
              color: IndustrialTheme.control,
            ),
            const SizedBox(width: 8),
            const Text(
              'CUSTOM DISTANCE',
              style: TextStyle(
                color: IndustrialTheme.textMuted,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(width: 6),
            const Text(
              '[ use slider ]',
              style: TextStyle(
                color: IndustrialTheme.textSecondary,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
            const Spacer(),
            _UnitSelector(
              unit: unit,
              onChanged: onUnit,
            ),
          ],
        ),
      ],
    );
  }

  void _applyMm(int mm) {
    final valueInUnit = switch (unit) {
      _DistanceUnit.mm => mm.toDouble(),
      _DistanceUnit.cm => mm / 10,
      _DistanceUnit.m => mm / 1000,
    };
    onApply(valueInUnit);
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: IndustrialTheme.panel,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: IndustrialTheme.borderHi),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _UnitSelector extends StatelessWidget {
  const _UnitSelector({required this.unit, required this.onChanged});

  final _DistanceUnit unit;
  final ValueChanged<_DistanceUnit> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: IndustrialTheme.panel,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: IndustrialTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: _DistanceUnit.values.map((u) {
          final active = unit == u;
          return GestureDetector(
            onTap: () => onChanged(u),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: active ? IndustrialTheme.control.withValues(alpha: 0.2) : Colors.transparent,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                u.name.toUpperCase(),
                style: TextStyle(
                  color: active ? IndustrialTheme.control : IndustrialTheme.textMuted,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          );
        }).toList(growable: false),
      ),
    );
  }
}

class _DistanceSlider extends StatelessWidget {
  const _DistanceSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.label,
    required this.onChanged,
  });

  final double value;
  final double min;
  final double max;
  final String label;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            activeColor: IndustrialTheme.control,
            inactiveColor: IndustrialTheme.border,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 74,
          child: Text(
            label,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontFamily: IndustrialTheme.mono,
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _SpeedRow extends StatelessWidget {
  const _SpeedRow({
    required this.label,
    required this.value,
    required this.display,
    required this.onChanged,
    this.min = 0.1,
    this.max = 1.8,
  });

  final String label;
  final double value;
  final String display;
  final ValueChanged<double> onChanged;
  final double min;
  final double max;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: const TextStyle(
              color: IndustrialTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            activeColor: IndustrialTheme.control,
            inactiveColor: IndustrialTheme.border,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 74,
          child: Text(
            display,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontFamily: IndustrialTheme.mono,
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _TimedNote extends StatelessWidget {
  const _TimedNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: IndustrialTheme.warn.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: IndustrialTheme.warn.withValues(alpha: 0.3)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.timer_outlined, size: 14, color: IndustrialTheme.warn),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Timed movement is used for delays, timeouts and scheduled actions. '
              'Distance mode is the primary movement concept.',
              style: TextStyle(
                color: IndustrialTheme.textSecondary,
                fontSize: 10,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommandReadout extends StatelessWidget {
  const _CommandReadout({
    required this.label,
    required this.value,
    required this.hasPending,
    required this.onClear,
  });

  final String label;
  final String value;
  final bool hasPending;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: IndustrialTheme.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasPending
              ? IndustrialTheme.control.withValues(alpha: 0.5)
              : IndustrialTheme.border,
        ),
      ),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: const TextStyle(
              color: IndustrialTheme.textMuted,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontFamily: IndustrialTheme.mono,
                color: hasPending ? IndustrialTheme.control : Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
          if (onClear != null)
            IconButton(
              onPressed: onClear,
              icon: const Icon(
                Icons.close_rounded,
                size: 16,
                color: IndustrialTheme.textMuted,
              ),
              tooltip: 'Clear selection',
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}

class _EstopBanner extends StatelessWidget {
  const _EstopBanner({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final confirmed = label == 'E-STOP CONFIRMED';
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: IndustrialTheme.danger.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: IndustrialTheme.danger.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(
            confirmed ? Icons.gpp_bad_rounded : Icons.pending_rounded,
            size: 18,
            color: IndustrialTheme.danger,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$label — movement commands are BLOCKED. '
              'This machine must be manually re-armed and commanded again.',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AckLifecycle extends StatelessWidget {
  const _AckLifecycle({required this.ack});

  final CommandAck ack;

  @override
  Widget build(BuildContext context) {
    final stages = CommandStage.values
        .where((s) =>
            s != CommandStage.estopRequested &&
            s != CommandStage.estopConfirmed)
        .toList();
    final activeIndex = stages.indexOf(ack.stage);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: IndustrialTheme.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: IndustrialTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: stages.asMap().entries.map((entry) {
              final idx = entry.key;
              final stage = entry.value;
              final reached = idx <= activeIndex;
              final done = idx < activeIndex;
              return Expanded(
                child: Row(
                  children: [
                    Icon(
                      done
                          ? Icons.check_circle_rounded
                          : reached
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                      size: 15,
                      color: done
                          ? IndustrialTheme.ready
                          : reached
                              ? IndustrialTheme.control
                              : IndustrialTheme.textMuted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      stage.name.toUpperCase(),
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                        color: reached
                            ? Colors.white
                            : IndustrialTheme.textMuted,
                      ),
                    ),
                    if (idx < stages.length - 1) ...[
                      const SizedBox(width: 4),
                      Expanded(
                        child: Container(
                          height: 1,
                          color: done
                              ? IndustrialTheme.ready
                              : IndustrialTheme.border,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }).toList(),
          ),
          if (ack.message.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              ack.message,
              style: TextStyle(
                color: ack.stage == CommandStage.rejected ||
                        ack.stage == CommandStage.failed
                    ? IndustrialTheme.danger
                    : IndustrialTheme.control,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmergencyStopButton extends StatelessWidget {
  const _EmergencyStopButton({
    required this.confirming,
    required this.executing,
    required this.onPressed,
  });

  final bool confirming;
  final bool executing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final disabled = confirming || executing;
    return SizedBox(
      height: 56,
      child: ElevatedButton(
        onPressed: disabled ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: IndustrialTheme.danger,
          foregroundColor: Colors.white,
          disabledBackgroundColor: IndustrialTheme.danger.withValues(alpha: 0.4),
          disabledForegroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 6,
          shadowColor: IndustrialTheme.danger.withValues(alpha: 0.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (confirming)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            else
              const Icon(Icons.stop_circle_rounded, size: 24),
            const SizedBox(width: 10),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  confirming ? 'CONFIRM STOP...' : 'EMERGENCY STOP',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                    fontSize: 13,
                  ),
                ),
                const Text(
                  'HALTS ALL MOVEMENT IMMEDIATELY',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}