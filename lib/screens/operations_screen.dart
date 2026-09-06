import 'dart:async';

import 'package:flutter/material.dart';

import '../models/machine_command.dart';
import '../models/machine_status.dart';
import '../services/machine_control_service.dart';
import '../utils/movement_calibration.dart';
import '../widgets/agv_control_card.dart';
import '../widgets/command_history_table.dart';
import '../widgets/crane_drive_card.dart';
import '../widgets/machine_control_widgets.dart';
import '../widgets/trolley_control_card.dart';

enum _OpsMachine { agv, crane, trolley }

enum _MoveMode { time, distance }

enum _ControlKind { agv, crane, trolley }

enum _DistanceUnit { mm, cm, m }

// ---------------------------------------------------------------------------
// Industrial visual constants
// ---------------------------------------------------------------------------

const _colorBg = Color(0xFF08111F);
const _colorPanel = Color(0xFF0D1A2A);
const _colorPanelAlt = Color(0xFF11223A);
const _colorBorder = Color(0xFF1D334D);
const _colorBorderHi = Color(0xFF2A4365);

const _textPrimary = Colors.white;
const _textSecondary = Color(0xFFB9C5D6);
const _textMuted = Color(0xFF72819C);

const _toneActive = Color(0xFF38BDF8); // cyan   = active control / interaction
const _toneReady = Color(0xFF22C55E); // green  = ready / online / healthy
const _toneWarn = Color(0xFFF5A524); // amber  = warning / degraded / simulation
const _toneDanger = Color(0xFFEF4444); // red    = error / stopped / emergency
const _toneIdle = Color(0xFF7C8AA3); // gray   = offline / disabled

const _mono = 'monospace';

class OperationsScreen extends StatefulWidget {
  const OperationsScreen({super.key});

  @override
  State<OperationsScreen> createState() => _OperationsScreenState();
}

class _OperationsScreenState extends State<OperationsScreen> {
  static const _agvId = '1';
  static const _craneId = '2';

  late final MachineControlService _service;
  late final String _networkLabel;

  MachineDetail? _agv;
  MachineDetail? _crane;
  bool _loaded = false;
  String? _error;

  final Map<String, DriveStatus> _driveStatuses = {};
  final Map<String, AutoModeStatus> _autoStatuses = {};
  final Map<String, MachineCommand> _latestCommands = {};

  Timer? _timer;

  _ControlKind _selected = _ControlKind.agv;

  bool get _backendOk => _error == null;

  bool get _simMode => _loaded && _backendOk && !_anyOnline();

  @override
  void initState() {
    super.initState();
    _service = MachineControlService();
    final base = _service.baseUrl;
    _networkLabel =
        (base.contains('127.0.0.1') || base.contains('localhost')) ? 'LOCAL' : 'CLOUD';
    _load();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _service.dispose();
    super.dispose();
  }

  _MachineSpec _specFor(_ControlKind kind) {
    return switch (kind) {
      _ControlKind.agv => const _MachineSpec(
          id: _agvId,
          name: 'AGV-01',
          typeLabel: 'Automated Guided Vehicle',
          accent: _toneActive,
          icon: Icons.directions_car_filled_rounded,
          calibration: agvCalibration,
        ),
      _ControlKind.crane => const _MachineSpec(
          id: _craneId,
          name: 'CRANE-01',
          typeLabel: 'Quay Crane',
          accent: _toneActive,
          icon: Icons.construction_rounded,
          calibration: craneCalibration,
        ),
      _ControlKind.trolley => const _MachineSpec(
          id: _craneId,
          name: 'TROLLEY-01',
          typeLabel: 'Trolley / Hoist Unit',
          accent: _toneActive,
          icon: Icons.swap_horiz_rounded,
          calibration: trolleyCalibration,
        ),
    };
  }

  Future<void> _load({bool silent = false}) async {
    try {
      final agv = await _service.fetchMachineDetail(_agvId);
      final crane = await _service.fetchMachineDetail(_craneId);

      final driveStatuses = <String, DriveStatus>{};
      final autoStatuses = <String, AutoModeStatus>{};
      final latestCommands = <String, MachineCommand>{};

      for (final id in [_agvId, _craneId]) {
        try {
          driveStatuses[id] = await _service.fetchDriveStatus(id);
        } catch (_) {}
        try {
          autoStatuses[id] = await _service.fetchAutoModeStatus(id);
        } catch (_) {}
        try {
          final history = await _service.fetchCommandHistory(id);
          if (history.isNotEmpty) latestCommands[id] = history.first;
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _agv = agv;
          _crane = crane;
          _driveStatuses
            ..clear()
            ..addAll(driveStatuses);
          _autoStatuses
            ..clear()
            ..addAll(autoStatuses);
          _latestCommands
            ..clear()
            ..addAll(latestCommands);
          _loaded = true;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && !silent) {
        setState(() {
          _loaded = true;
          _error = e.toString();
        });
      }
    }
  }

  MachineDetail? _machineFor(_OpsMachine m) {
    return switch (m) {
      _OpsMachine.agv => _agv,
      _OpsMachine.crane => _crane,
      _OpsMachine.trolley => _crane,
    };
  }

  bool _anyOnline() => _driveStatuses.values.any((s) => s.online);

  bool _agvLinked() => _driveStatuses[_agvId]?.online ?? false;

  bool _craneLinked() => _driveStatuses[_craneId]?.online ?? false;

  List<_Alert> _buildAlerts() {
    final alerts = <_Alert>[];
    if (!_backendOk) {
      alerts.add(const _Alert(
        severity: 2,
        title: 'Gateway unreachable',
        detail: 'Machine telemetry is unavailable. Status shown may be stale.',
      ));
      return alerts;
    }
    if (_simMode) {
      alerts.add(const _Alert(
        severity: 1,
        title: 'Simulation mode',
        detail: 'No physical controller is reporting. Commands are queued by the gateway until hardware is linked.',
      ));
    }
    if (!_agvLinked()) {
      alerts.add(const _Alert(
        severity: 1,
        title: 'AGV-01 hardware disconnected',
        detail: 'No link to the AGV controller. Commands will be queued.',
      ));
    }
    if (!_craneLinked()) {
      alerts.add(const _Alert(
        severity: 1,
        title: 'CRANE-01 hardware disconnected',
        detail: 'No link to the crane controller. Commands will be queued.',
      ));
    }
    final agvAuto = _autoStatuses[_agvId]?.running ?? false;
    final craneAuto = _autoStatuses[_craneId]?.running ?? false;
    if (agvAuto || craneAuto) {
      alerts.add(_Alert(
        severity: 0,
        title: 'Auto mode active',
        detail: agvAuto && craneAuto
            ? 'Both AGV and Crane are executing automated routines.'
            : (agvAuto ? 'AGV is executing an automated routine.' : 'Crane is executing an automated routine.'),
      ));
    }
    return alerts;
  }

  @override
  Widget build(BuildContext context) {
    final alerts = _buildAlerts();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _OpsHeader(
            systemLabel: !_backendOk
                ? 'OFFLINE'
                : (_anyOnline() ? 'OPERATIONAL' : 'SIMULATION'),
            systemColor: !_backendOk
                ? _toneDanger
                : (_anyOnline() ? _toneReady : _toneWarn),
            networkLabel: _networkLabel,
            alertCount: alerts.length,
            eStopLabel: _machineLabel(_selected),
            onEStop: () => _emergencyStop(_selected),
          ),
          const SizedBox(height: 12),
          if (!_backendOk) ...[
            _TelemetryErrorPanel(
              detail: _error!,
              onRetry: () {
                setState(() => _error = null);
                _load();
              },
            ),
            const SizedBox(height: 12),
          ],
          if (!_loaded && _agv == null) ...[
            const _LoadingPanel(),
            const SizedBox(height: 12),
          ],
          _SectionLabel(
            title: 'Machine Overview',
            trailing: _SystemMiniChip(simMode: _simMode, backendOk: _backendOk),
          ),
          const SizedBox(height: 8),
          _layoutOverview(),
          const SizedBox(height: 18),
          _QuickControlPanel(
            service: _service,
            selected: _selected,
            onSelect: (k) => setState(() => _selected = k),
            spec: _specFor(_selected),
            onOpenDetailed: () => _openDetailed(_selected),
          ),
          const SizedBox(height: 18),
          _ActiveMissionPanel(
            autoStatus: _autoStatuses[_agvId],
            latestCommand: _latestCommands[_agvId],
            agvState: _agv?.status,
            craneState: _crane?.status,
            agvLinked: _agvLinked(),
            craneLinked: _craneLinked(),
          ),
          const SizedBox(height: 18),
          _layoutActivity(alerts),
        ],
      ),
    );
  }

  Widget _layoutOverview() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final cards = [
          _buildOverviewCard(
            machine: _machineFor(_OpsMachine.agv),
            driveStatus: _driveStatuses[_agvId],
            autoStatus: _autoStatuses[_agvId],
            latestCommand: _latestCommands[_agvId],
            spec: _specFor(_ControlKind.agv),
            kind: _ControlKind.agv,
          ),
          _buildOverviewCard(
            machine: _machineFor(_OpsMachine.crane),
            driveStatus: _driveStatuses[_craneId],
            autoStatus: _autoStatuses[_craneId],
            latestCommand: _latestCommands[_craneId],
            spec: _specFor(_ControlKind.crane),
            kind: _ControlKind.crane,
          ),
          _buildOverviewCard(
            machine: _machineFor(_OpsMachine.trolley),
            driveStatus: _driveStatuses[_craneId],
            autoStatus: _autoStatuses[_craneId],
            latestCommand: _latestCommands[_craneId],
            spec: _specFor(_ControlKind.trolley),
            kind: _ControlKind.trolley,
          ),
        ];

        if (width >= 1080) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: cards[0]),
              const SizedBox(width: 14),
              Expanded(child: cards[1]),
              const SizedBox(width: 14),
              Expanded(child: cards[2]),
            ],
          );
        }
        if (width >= 700) {
          return Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              SizedBox(width: (width - 14) / 2, child: cards[0]),
              SizedBox(width: (width - 14) / 2, child: cards[1]),
              SizedBox(width: width, child: cards[2]),
            ],
          );
        }
        return Column(
          children: [
            cards[0],
            const SizedBox(height: 14),
            cards[1],
            const SizedBox(height: 14),
            cards[2],
          ],
        );
      },
    );
  }

  Widget _buildOverviewCard({
    required MachineDetail? machine,
    required DriveStatus? driveStatus,
    required AutoModeStatus? autoStatus,
    required MachineCommand? latestCommand,
    required _MachineSpec spec,
    required _ControlKind kind,
  }) {
    final linked = driveStatus?.online ?? false;
    final stateColor = _stateTone(machine?.status);
    final stateLabel = _stateLabel(machine?.status);

    return _Panel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _StatusDot(color: stateColor, size: 8),
              const SizedBox(width: 8),
              Text(
                stateLabel,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: _textPrimary,
                ),
              ),
              const Spacer(),
              Icon(spec.icon, size: 16, color: spec.accent),
              const SizedBox(width: 6),
              Text(
                spec.name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            spec.typeLabel.toUpperCase(),
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: _textMuted,
            ),
          ),
          const SizedBox(height: 12),
          _MetricGrid(
            leftLabel: 'Speed',
            leftValue: (machine?.speed ?? 0) > 0
                ? machine!.speed.toStringAsFixed(0)
                : '--',
            leftTone: _textPrimary,
            rightLabel: 'Battery',
            rightValue: (machine?.batteryLevel ?? 0) > 0
                ? '${machine!.batteryLevel.toStringAsFixed(0)}%'
                : '--',
            rightTone: _textPrimary,
          ),
          const SizedBox(height: 10),
          _MetricGrid(
            leftLabel: 'Connection',
            leftValue: linked ? 'LINKED' : 'SIMULATED',
            leftTone: linked ? _toneReady : _toneWarn,
            rightLabel: 'Auto',
            rightValue: (autoStatus?.running ?? false)
                ? (autoStatus!.currentPhase.isEmpty
                    ? 'RUNNING'
                    : autoStatus.currentPhase.toUpperCase())
                : 'OFF',
            rightTone: (autoStatus?.running ?? false) ? _toneActive : _toneIdle,
          ),
          const Divider(color: _colorBorder, height: 22),
          Row(
            children: [
              Text(
                'CURRENT COMMAND',
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: _textMuted,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  latestCommand != null
                      ? '${latestCommand.command.toUpperCase()}${latestCommand.params.isEmpty ? '' : ' · ${latestCommand.params}'}'
                      : 'NONE',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: _mono,
                    fontSize: 11,
                    color: _textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 36,
            child: OutlinedButton(
              onPressed: () => _selectAndControl(kind),
              style: OutlinedButton.styleFrom(
                foregroundColor: _toneActive,
                side: const BorderSide(color: Color(0xFF2B5A78)),
                backgroundColor: _toneActive.withValues(alpha: 0.10),
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              child: const Text(
                'OPEN CONTROL',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _selectAndControl(_ControlKind kind) {
    setState(() {
      _selected = kind;
    });
    _openDetailed(kind);
  }

  void _openDetailed(_ControlKind kind) {
    final spec = _specFor(kind);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _DetailedControlSheet(
        spec: spec,
        service: _service,
        kind: kind,
      ),
    );
  }

  Future<void> _emergencyStop(_ControlKind kind) async {
    final spec = _specFor(kind);
    final confirmed = await confirmOperation(
      context,
      title: 'Emergency Stop ${spec.name}',
      message: 'Send an immediate STOP to ${spec.name}?',
      confirmLabel: 'STOP',
    );
    if (!confirmed) return;
    try {
      await _service.sendCommand(spec.id, const AgvCommandRequest(command: 'stop'));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('STOP sent'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to stop: ${_friendlyError(e)}'),
            backgroundColor: _toneDanger,
          ),
        );
      }
    }
  }

  Widget _layoutActivity(List<_Alert> alerts) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 960;
        final alertPanel = _AlertsPanel(alerts: alerts, onRetry: _load);
        final activityPanel = _LiveActivityPanel(
          service: _service,
          agvId: _agvId,
          craneId: _craneId,
        );

        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 6, child: activityPanel),
              const SizedBox(width: 14),
              Expanded(flex: 4, child: alertPanel),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            activityPanel,
            const SizedBox(height: 14),
            alertPanel,
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Shared industrial primitives
// ---------------------------------------------------------------------------

class _Panel extends StatelessWidget {
  const _Panel({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color = _colorPanel,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.all(Radius.circular(10)),
        border: Border.all(color: _colorBorder),
      ),
      child: child,
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
            color: _textSecondary,
          ),
        ),
        const Spacer(),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.color, this.size = 8});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 6),
        ],
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({
    required this.leftLabel,
    required this.leftValue,
    required this.leftTone,
    required this.rightLabel,
    required this.rightValue,
    required this.rightTone,
  });

  final String leftLabel;
  final String leftValue;
  final Color leftTone;
  final String rightLabel;
  final String rightValue;
  final Color rightTone;

  @override
  Widget build(BuildContext context) {
    Widget cell(String label, String value, Color tone) {
      return Expanded(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              label.toUpperCase(),
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: _textMuted,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: _mono,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: tone,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      children: [
        cell(leftLabel, leftValue, leftTone),
        const SizedBox(width: 12),
        cell(rightLabel, rightValue, rightTone),
      ],
    );
  }
}

class _SystemMiniChip extends StatelessWidget {
  const _SystemMiniChip({required this.simMode, required this.backendOk});

  final bool simMode;
  final bool backendOk;

  @override
  Widget build(BuildContext context) {
    final color = !backendOk
        ? _toneDanger
        : (simMode ? _toneWarn : _toneReady);
    final label = !backendOk ? 'GATEWAY OFFLINE' : (simMode ? 'SIMULATION' : 'SYSTEM ONLINE');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StatusDot(color: color, size: 7),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
            color: color,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _OpsHeader extends StatelessWidget {
  const _OpsHeader({
    required this.systemLabel,
    required this.systemColor,
    required this.networkLabel,
    required this.alertCount,
    required this.eStopLabel,
    required this.onEStop,
  });

  final String systemLabel;
  final Color systemColor;
  final String networkLabel;
  final int alertCount;
  final String eStopLabel;
  final VoidCallback onEStop;

  @override
  Widget build(BuildContext context) {
    final title = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: _toneActive.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _colorBorderHi),
          ),
          child: const Icon(Icons.precision_manufacturing_rounded,
              color: _toneActive, size: 18),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'OPERATIONS',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.4,
                color: _textPrimary,
              ),
            ),
            const Text(
              'PORT AUTOMATION CONTROL CENTER',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: _textMuted,
              ),
            ),
          ],
        ),
      ],
    );

    final chips = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _HeaderChip(
          icon: Icons.sensors_rounded,
          label: systemLabel,
          tone: systemColor,
        ),
        _HeaderChip(
          icon: networkLabel == 'CLOUD'
              ? Icons.cloud_outlined
              : Icons.dns_outlined,
          label: networkLabel,
          tone: networkLabel == 'CLOUD' ? _toneActive : _textSecondary,
        ),
        _HeaderAlertsChip(count: alertCount),
        SizedBox(
          height: 34,
          child: OutlinedButton.icon(
            onPressed: onEStop,
            style: OutlinedButton.styleFrom(
              foregroundColor: _toneDanger,
              side: const BorderSide(color: Color(0xFF5A2B2B)),
              backgroundColor: _toneDanger.withValues(alpha: 0.12),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              visualDensity: VisualDensity.compact,
            ),
            icon: const Icon(Icons.stop_circle_rounded, size: 15),
            label: Text(
              'E-STOP $eStopLabel',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ),
      ],
    );

    return _Panel(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 880) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                title,
                const SizedBox(height: 12),
                chips,
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: title),
              const SizedBox(width: 16),
              chips,
            ],
          );
        },
      ),
    );
  }
}

class _HeaderChip extends StatelessWidget {
  const _HeaderChip({required this.icon, required this.label, required this.tone});

  final IconData icon;
  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: tone.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StatusDot(color: tone, size: 7),
          const SizedBox(width: 6),
          Icon(icon, size: 13, color: tone),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: tone,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderAlertsChip extends StatelessWidget {
  const _HeaderAlertsChip({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final tone = count > 0 ? _toneWarn : _toneReady;
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _colorBorderHi),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            count > 0 ? Icons.warning_amber_rounded : Icons.error_outline_rounded,
            size: 13,
            color: tone,
          ),
          const SizedBox(width: 6),
          Text(
            'ALERTS $count',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: count > 0 ? _textPrimary : _textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Machine control panel
// ---------------------------------------------------------------------------

class _QuickControlPanel extends StatefulWidget {
  const _QuickControlPanel({
    required this.service,
    required this.selected,
    required this.onSelect,
    required this.spec,
    required this.onOpenDetailed,
  });

  final MachineControlService service;
  final _ControlKind selected;
  final ValueChanged<_ControlKind> onSelect;
  final _MachineSpec spec;
  final VoidCallback onOpenDetailed;

  @override
  State<_QuickControlPanel> createState() => _QuickControlPanelState();
}

class _QuickControlPanelState extends State<_QuickControlPanel> {
  _MoveMode _mode = _MoveMode.time;
  double _speed = 100;
  double _durationSeconds = 3;
  double _distance = 50;
  _DistanceUnit _distanceUnit = _DistanceUnit.cm;
  bool _executing = false;
  String? _pending;
  String? _lastErrorFriendly;
  String? _lastErrorDetail;

  _ControlKind get _kind => widget.selected;
  _MachineSpec get _spec => widget.spec;

  int get _durationMs => (_durationSeconds * 1000).round().clamp(100, 60000);

  @override
  void didUpdateWidget(_QuickControlPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) {
      _pending = null;
      _lastErrorFriendly = null;
      _lastErrorDetail = null;
      _distanceUnit = switch (widget.selected) {
        _ControlKind.agv || _ControlKind.crane => _DistanceUnit.cm,
        _ControlKind.trolley => _DistanceUnit.mm,
      };
    }
  }

  double get _distanceValueMm => switch (_distanceUnit) {
        _DistanceUnit.mm => _distance,
        _DistanceUnit.cm => _distance * 10,
        _DistanceUnit.m => _distance * 1000,
      };

  (double min, double max) get _distanceBounds => switch (_distanceUnit) {
        _DistanceUnit.mm => (5, 2000),
        _DistanceUnit.cm => (5, 500),
        _DistanceUnit.m => (0.5, 50),
      };

  String _formatDistance(double v) => switch (_distanceUnit) {
        _DistanceUnit.mm => v.toStringAsFixed(0),
        _DistanceUnit.cm => v.toStringAsFixed(0),
        _DistanceUnit.m => v.toStringAsFixed(1),
      };

  void _arm(String command) {
    if (_executing || _pending == command) return;
    setState(() {
      _pending = command;
      _lastErrorFriendly = null;
      _lastErrorDetail = null;
    });
  }

  Future<void> _stopNow() async {
    if (_executing) return;
    final confirmed = await confirmOperation(
      context,
      title: 'Stop ${_machineLabel(_kind)}',
      message: 'This stops all movement. Continue?',
      confirmLabel: 'STOP',
    );
    if (!confirmed) return;
    await _execute('stop');
  }

  Future<void> _runPending() async {
    final command = _pending;
    if (command == null || _executing) return;
    await _execute(command);
  }

  Future<void> _execute(String command) async {
    setState(() {
      _executing = true;
      _lastErrorFriendly = null;
      _lastErrorDetail = null;
    });

    try {
      await _sendFor(_kind, command);
      if (mounted) {
        setState(() => _pending = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              command == 'stop'
                  ? 'STOP sent to ${_spec.name}'
                  : '${_spec.name} · ${_pendingReadout(command)}',
            ),
            duration: const Duration(milliseconds: 900),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _lastErrorFriendly = _friendlyError(e);
          _lastErrorDetail = e.toString();
        });
      }
    } finally {
      if (mounted) setState(() => _executing = false);
    }
  }

  String _pendingReadout(String command) {
    final c = command.toUpperCase();
    if (command == 'stop') return c;
    if (_mode == _MoveMode.distance) {
      return '$c · EST ${_formatDistance(_distance)}${_unitSymbol(_distanceUnit)}';
    }
    if (_kind == _ControlKind.agv) {
      return '$c · ${_durationSeconds.toStringAsFixed(1)}s @ ${_speed.toInt()}%';
    }
    return '$c · ${_speed.toInt()} × ${_durationSeconds.toStringAsFixed(1)}s';
  }

  int _agvDuration() {
    if (_mode == _MoveMode.distance) {
      final speedFraction = (_speed / 255).clamp(0.1, 1.0);
      return _spec.calibration.distanceMmToDurationMs(
        distanceMm: _distanceValueMm,
        speedFraction: speedFraction,
      );
    }
    return _durationMs;
  }

  int _stepsFor() {
    if (_mode == _MoveMode.distance) {
      return _spec.calibration.distanceMmToSteps(distanceMm: _distanceValueMm);
    }
    return (_speed * _durationSeconds).round().clamp(1, 10000);
  }

  Future<void> _sendFor(_ControlKind kind, String command) async {
    switch (kind) {
      case _ControlKind.agv:
        final isBlink = command == 'blink';
        final isStop = command == 'stop';
        final duration = isBlink || isStop ? null : _agvDuration();
        await widget.service.sendCommand(
          _spec.id,
          AgvCommandRequest(
            command: command,
            speed: isBlink ? 3 : _speed.toInt(),
            duration: duration,
          ),
        );
      case _ControlKind.crane:
        final isStop = command == 'stop';
        final steps = isStop ? null : _stepsFor();
        await widget.service.sendCraneCommand(
          _spec.id,
          CraneCommandRequest(command: command, steps: steps),
        );
      case _ControlKind.trolley:
        final isStop = command == 'stop';
        final isMagnet = command == 'magnet_on' || command == 'magnet_off';
        final steps = isStop || isMagnet ? null : _stepsFor();
        await widget.service.sendCraneCommand(
          _spec.id,
          CraneCommandRequest(command: command, steps: steps),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'MACHINE CONTROL',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                  color: _textSecondary,
                ),
              ),
              const Spacer(),
              Text(
                _spec.name,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: _toneActive,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _MachineTabs(
            selected: _kind,
            onSelect: (k) => widget.onSelect(k),
          ),
          const SizedBox(height: 16),
          if (_lastErrorFriendly != null) ...[
            _CommandErrorBox(
              message: _lastErrorFriendly!,
              detail: _lastErrorDetail ?? '',
            ),
            const SizedBox(height: 12),
          ],
          LayoutBuilder(
            builder: (context, constraints) {
              final body = _buildBody(context);
              if (constraints.maxWidth < 820) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    body.controlSide,
                    const SizedBox(height: 14),
                    body.inputSide,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: body.controlSide),
                  const SizedBox(width: 16),
                  Expanded(flex: 6, child: body.inputSide),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  _ControlBody _buildBody(BuildContext context) {
    switch (_kind) {
      case _ControlKind.agv:
        return _buildAgvBody(context);
      case _ControlKind.crane:
        return _buildCraneBody(context);
      case _ControlKind.trolley:
        return _buildTrolleyBody(context);
    }
  }

  Widget _buildControlInputs() {
    final useSteps = _kind != _ControlKind.agv;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'MOVEMENT MODE',
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                color: _textMuted,
              ),
            ),
            const SizedBox(width: 10),
            _ModeToggle(mode: _mode, onChanged: (m) => setState(() => _mode = m)),
          ],
        ),
        const SizedBox(height: 12),
        _SliderRow(
          label: 'Speed',
          value: _kind == _ControlKind.agv
              ? '${_speed.toInt()}%'
              : '${_speed.toInt()} st/s',
          v: _speed,
          min: 10,
          max: _kind == _ControlKind.agv ? 255 : 2000,
          onChanged: (v) => setState(() => _speed = v),
        ),
        const SizedBox(height: 4),
        if (_mode == _MoveMode.time)
          _SliderRow(
            label: 'Duration',
            value: '${_durationSeconds.toStringAsFixed(1)}s',
            v: _durationSeconds,
            min: 0.5,
            max: 10,
            onChanged: (v) => setState(() => _durationSeconds = v),
          )
        else ...[
          _SliderRow(
            label: 'Distance',
            value: '${_formatDistance(_distance)} ${_unitSymbol(_distanceUnit)}',
            v: _distance,
            min: _distanceBounds.$1,
            max: _distanceBounds.$2,
            onChanged: (v) => setState(() => _distance = v),
          ),
          const SizedBox(height: 6),
          _UnitSelector(
            unit: _distanceUnit,
            onChanged: (u) => setState(() => _distanceUnit = u),
          ),
          const SizedBox(height: 8),
          _LinedCallout(
            icon: useSteps ? Icons.speed_rounded : Icons.timer_outlined,
            text: useSteps
                ? 'ESTIMATED ${_stepsFor()} steps via ${_spec.calibration.stepsPerMm.toStringAsFixed(1)} steps/mm'
                : 'ESTIMATED ${(_agvDuration() / 1000).toStringAsFixed(1)}s timed run at ${_speed.toInt()}%',
            note: 'Open-loop calibration · distance is estimated',
          ),
        ],
        const Divider(color: _colorBorder, height: 24),
        _CommandReadout(
          label: 'COMMAND',
          value: _pending == null
              ? 'NONE SELECTED'
              : _pendingReadout(_pending!),
          hasPending: _pending != null,
          onClear: _pending == null
              ? null
              : () => setState(() => _pending = null),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              flex: 7,
              child: SizedBox(
                height: 40,
                child: FilledButton(
                  onPressed: (_pending == null || _executing) ? null : _runPending,
                  style: FilledButton.styleFrom(
                    backgroundColor: _toneActive,
                    disabledBackgroundColor: _colorPanelAlt,
                    disabledForegroundColor: _textMuted,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    padding: EdgeInsets.zero,
                  ),
                  child: const Text(
                    'EXECUTE',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
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
                height: 40,
                child: OutlinedButton(
                  onPressed: _executing ? null : _stopNow,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _toneDanger,
                    side: const BorderSide(color: Color(0xFF5A2B2B)),
                    backgroundColor: _toneDanger.withValues(alpha: 0.08),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    padding: EdgeInsets.zero,
                  ),
                  child: const Text(
                    'STOP',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  _ControlBody _buildAgvBody(BuildContext context) {
    final controlSide = _Panel(
      padding: const EdgeInsets.all(12),
      color: _colorPanelAlt,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DirectionPad(
            executing: _executing,
            onCommand: _arm,
            onStop: _stopNow,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  icon: Icons.lightbulb_outline,
                  label: 'LIGHTS',
                  accent: _toneWarn,
                  onPressed: _executing ? null : () => _arm('blink'),
                  active: _pending == 'blink',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionButton(
                  icon: Icons.open_in_full_rounded,
                  label: 'DETAILED',
                  accent: _toneActive,
                  onPressed: widget.onOpenDetailed,
                  active: false,
                ),
              ),
            ],
          ),
        ],
      ),
    );
    final inputSide = _buildControlInputs();
    return _ControlBody(controlSide: controlSide, inputSide: inputSide);
  }

  _ControlBody _buildCraneBody(BuildContext context) {
    final controlSide = _Panel(
      padding: const EdgeInsets.all(12),
      color: _colorPanelAlt,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RaiseLowerPad(
            label: 'HOIST',
            executing: _executing,
            onUp: () => _arm('hoist_up'),
            onDown: () => _arm('hoist_down'),
            onStop: _stopNow,
            pending: _pending,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  icon: Icons.arrow_back_rounded,
                  label: 'TROLLEY <',
                  accent: _toneActive,
                  onPressed: _executing ? null : () => _arm('trolley_forward'),
                  active: _pending == 'trolley_forward',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionButton(
                  icon: Icons.arrow_forward_rounded,
                  label: 'TROLLEY >',
                  accent: _toneActive,
                  onPressed: _executing ? null : () => _arm('trolley_backward'),
                  active: _pending == 'trolley_backward',
                ),
              ),
            ],
          ),
        ],
      ),
    );
    final inputSide = _buildControlInputs();
    return _ControlBody(controlSide: controlSide, inputSide: inputSide);
  }

  _ControlBody _buildTrolleyBody(BuildContext context) {
    final controlSide = _Panel(
      padding: const EdgeInsets.all(12),
      color: _colorPanelAlt,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _ActionButton(
                icon: Icons.arrow_back_rounded,
                label: 'LEFT',
                accent: _toneActive,
                onPressed: _executing ? null : () => _arm('trolley_forward'),
                active: _pending == 'trolley_forward',
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: _ActionButton(
                  icon: Icons.stop_circle_rounded,
                  label: 'STOP',
                  accent: _toneDanger,
                  onPressed: _executing ? null : _stopNow,
                  active: _pending == 'stop',
                  filled: true,
                ),
              ),
              _ActionButton(
                icon: Icons.arrow_forward_rounded,
                label: 'RIGHT',
                accent: _toneActive,
                onPressed: _executing ? null : () => _arm('trolley_backward'),
                active: _pending == 'trolley_backward',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  icon: Icons.arrow_downward_rounded,
                  label: 'HOIST DOWN',
                  accent: _toneActive,
                  onPressed: _executing ? null : () => _arm('hoist_down'),
                  active: _pending == 'hoist_down',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionButton(
                  icon: Icons.arrow_upward_rounded,
                  label: 'HOIST UP',
                  accent: _toneActive,
                  onPressed: _executing ? null : () => _arm('hoist_up'),
                  active: _pending == 'hoist_up',
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
                  label: 'MAGNET ON',
                  accent: _toneReady,
                  onPressed: _executing ? null : () => _arm('magnet_on'),
                  active: _pending == 'magnet_on',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionButton(
                  icon: Icons.cancel_outlined,
                  label: 'MAGNET OFF',
                  accent: _textMuted,
                  onPressed: _executing ? null : () => _arm('magnet_off'),
                  active: _pending == 'magnet_off',
                ),
              ),
            ],
          ),
        ],
      ),
    );
    final inputSide = _buildControlInputs();
    return _ControlBody(controlSide: controlSide, inputSide: inputSide);
  }
}

class _ControlBody {
  const _ControlBody({required this.controlSide, required this.inputSide});
  final Widget controlSide;
  final Widget inputSide;
}

class _MachineTabs extends StatelessWidget {
  const _MachineTabs({required this.selected, required this.onSelect});

  final _ControlKind selected;
  final ValueChanged<_ControlKind> onSelect;

  @override
  Widget build(BuildContext context) {
    const items = <(_ControlKind, String, IconData)>[
      (_ControlKind.agv, 'AGV', Icons.directions_car_filled_rounded),
      (_ControlKind.crane, 'CRANE', Icons.construction_rounded),
      (_ControlKind.trolley, 'TROLLEY', Icons.swap_horiz_rounded),
    ];
    return Container(
      decoration: BoxDecoration(
        color: _colorBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _colorBorder),
      ),
      child: Row(
        children: [
          for (final (kind, label, icon) in items)
            Expanded(
              child: GestureDetector(
                onTap: () => onSelect(kind),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    color: selected == kind
                        ? _toneActive.withValues(alpha: 0.16)
                        : Colors.transparent,
                    border: Border(
                      bottom: BorderSide(
                        color: selected == kind
                            ? _toneActive
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon,
                          size: 15,
                          color: selected == kind
                              ? _toneActive
                              : _textMuted),
                      const SizedBox(width: 7),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                          color: selected == kind
                              ? _toneActive
                              : _textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.accent,
    this.onPressed,
    this.active = false,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback? onPressed;
  final bool active;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final Color border = active ? accent : _colorBorder;
    final Color bg = filled
        ? accent.withValues(alpha: 0.18)
        : (active ? accent.withValues(alpha: 0.12) : _colorBg);
    return SizedBox(
      height: 40,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: accent,
          side: BorderSide(color: border),
          backgroundColor: bg,
          disabledForegroundColor: _textMuted,
          disabledBackgroundColor: _colorPanelAlt,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
          padding: EdgeInsets.zero,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DirectionPad extends StatelessWidget {
  const _DirectionPad({
    required this.executing,
    required this.onCommand,
    required this.onStop,
  });

  final bool executing;
  final void Function(String) onCommand;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    Widget btn({
      required IconData icon,
      required String label,
      required VoidCallback tap,
      Color? accent,
      bool stop = false,
    }) {
      final Color fg = stop ? _toneDanger : (accent ?? _toneActive);
      return Expanded(
        child: GestureDetector(
          onTap: executing ? null : tap,
          child: Container(
            height: 46,
            decoration: BoxDecoration(
              color: stop
                  ? _toneDanger.withValues(alpha: 0.16)
                  : (accent == null
                      ? _toneActive.withValues(alpha: 0.10)
                      : _colorBg),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: stop ? const Color(0xFF7A3A3A) : _colorBorderHi,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 17, color: fg),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        Row(
          children: [
            const SizedBox(width: 76),
            btn(
              icon: Icons.arrow_upward_rounded,
              label: 'FORWARD',
              tap: () => onCommand('forward'),
            ),
            const SizedBox(width: 76),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            btn(
              icon: Icons.arrow_back_rounded,
              label: 'LEFT',
              tap: () => onCommand('left'),
            ),
            const SizedBox(width: 6),
            btn(
              icon: Icons.stop_rounded,
              label: 'STOP',
              tap: onStop,
              stop: true,
            ),
            const SizedBox(width: 6),
            btn(
              icon: Icons.arrow_forward_rounded,
              label: 'RIGHT',
              tap: () => onCommand('right'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const SizedBox(width: 76),
            btn(
              icon: Icons.arrow_downward_rounded,
              label: 'REVERSE',
              tap: () => onCommand('backward'),
            ),
            const SizedBox(width: 76),
          ],
        ),
      ],
    );
  }
}

class _RaiseLowerPad extends StatelessWidget {
  const _RaiseLowerPad({
    required this.label,
    required this.executing,
    required this.onUp,
    required this.onDown,
    required this.onStop,
    required this.pending,
  });

  final String label;
  final bool executing;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final VoidCallback onStop;
  final String? pending;

  @override
  Widget build(BuildContext context) {
    Widget btn({
      required IconData icon,
      required String text,
      required VoidCallback tap,
      bool active = false,
      bool stop = false,
    }) {
      final Color fg = stop ? _toneDanger : _toneActive;
      return SizedBox(
        width: double.infinity,
        height: 46,
        child: OutlinedButton(
          onPressed: executing ? null : tap,
          style: OutlinedButton.styleFrom(
            foregroundColor: fg,
            side: BorderSide(
              color: stop
                  ? const Color(0xFF7A3A3A)
                  : (active ? _toneActive : _colorBorderHi),
            ),
            backgroundColor: stop
                ? _toneDanger.withValues(alpha: 0.16)
                : (active
                    ? _toneActive.withValues(alpha: 0.12)
                    : _colorBg),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
            padding: EdgeInsets.zero,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16),
              const SizedBox(width: 8),
              Text(
                text,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: _textMuted,
          ),
        ),
        const SizedBox(height: 8),
        btn(
          icon: Icons.arrow_upward_rounded,
          text: 'UP',
          tap: onUp,
          active: pending == 'hoist_up',
        ),
        const SizedBox(height: 6),
        btn(icon: Icons.stop_rounded, text: 'STOP', tap: onStop, stop: true),
        const SizedBox(height: 6),
        btn(
          icon: Icons.arrow_downward_rounded,
          text: 'DOWN',
          tap: onDown,
          active: pending == 'hoist_down',
        ),
      ],
    );
  }
}

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.mode, required this.onChanged});

  final _MoveMode mode;
  final ValueChanged<_MoveMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _colorBg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ModeButton(
            label: 'TIME',
            active: mode == _MoveMode.time,
            onTap: () => onChanged(_MoveMode.time),
          ),
          _ModeButton(
            label: 'DISTANCE',
            active: mode == _MoveMode.distance,
            onTap: () => onChanged(_MoveMode.distance),
          ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? _toneActive : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: active ? _textPrimary : _textMuted,
          ),
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.v,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final String value;
  final double v;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 68,
          child: Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: _textMuted,
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: _toneActive,
              inactiveTrackColor: _colorBorder,
              thumbColor: _toneActive,
              overlayColor: _toneActive.withValues(alpha: 0.18),
            ),
            child: Slider(
              value: v,
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 76,
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontFamily: _mono,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

class _UnitSelector extends StatelessWidget {
  const _UnitSelector({required this.unit, required this.onChanged});

  final _DistanceUnit unit;
  final ValueChanged<_DistanceUnit> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget item(_DistanceUnit u, String label) {
      final active = unit == u;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(u),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: active ? _toneActive.withValues(alpha: 0.16) : Colors.transparent,
              border: Border(
                bottom: BorderSide(
                  color: active ? _toneActive : _colorBorder,
                  width: active ? 2 : 1,
                ),
              ),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: active ? _toneActive : _textMuted,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: _colorBg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          item(_DistanceUnit.mm, 'MM'),
          item(_DistanceUnit.cm, 'CM'),
          item(_DistanceUnit.m, 'M'),
        ],
      ),
    );
  }
}

class _LinedCallout extends StatelessWidget {
  const _LinedCallout({required this.icon, required this.text, required this.note});

  final IconData icon;
  final String text;
  final String note;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _colorBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _colorBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: _toneWarn),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: const TextStyle(
                    fontFamily: _mono,
                    fontSize: 10,
                    color: _textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  note.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: _textMuted,
                  ),
                ),
              ],
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
    this.onClear,
  });

  final String label;
  final String value;
  final bool hasPending;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
            color: _textMuted,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: _mono,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: hasPending ? _toneActive : _textSecondary,
            ),
          ),
        ),
        if (hasPending && onClear != null)
          GestureDetector(
            onTap: onClear,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: _colorBg,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(Icons.close_rounded, size: 13, color: _textMuted),
            ),
          ),
      ],
    );
  }
}

class _CommandErrorBox extends StatelessWidget {
  const _CommandErrorBox({required this.message, this.detail = ''});

  final String message;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _toneDanger.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _toneDanger.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, color: _toneDanger, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _toneDanger,
                  ),
                ),
                if (detail.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: _mono,
                      fontSize: 9,
                      color: _textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Active mission
// ---------------------------------------------------------------------------

class _ActiveMissionPanel extends StatelessWidget {
  const _ActiveMissionPanel({
    required this.autoStatus,
    required this.latestCommand,
    required this.agvState,
    required this.craneState,
    required this.agvLinked,
    required this.craneLinked,
  });

  final AutoModeStatus? autoStatus;
  final MachineCommand? latestCommand;
  final MachineStatus? agvState;
  final MachineStatus? craneState;
  final bool agvLinked;
  final bool craneLinked;

  @override
  Widget build(BuildContext context) {
    final running = autoStatus?.running ?? false;
    final ctotal = autoStatus?.cargoTotal ?? 0;
    final cremaining = autoStatus?.cargoRemaining ?? 0;
    final fraction = ctotal == 0 ? 0.0 : ((ctotal - cremaining) / ctotal).clamp(0.0, 1.0);

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'ACTIVE MISSION',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                  color: _textSecondary,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (running ? _toneActive : _textMuted).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: (running ? _toneActive : _textMuted).withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  running ? 'RUNNING' : 'STANDING BY',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: running ? _toneActive : _textMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _MissionMachineChip(label: 'AGV', state: agvState, linked: agvLinked),
              const SizedBox(width: 8),
              _MissionMachineChip(label: 'CRANE', state: craneState, linked: craneLinked),
              const SizedBox(width: 8),
              _MissionMachineChip(
                label: 'TROLLEY',
                state: craneState,
                linked: craneLinked,
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (running) ...[
            if (ctotal > 0) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: fraction,
                  minHeight: 6,
                  backgroundColor: _colorBorder,
                  valueColor: const AlwaysStoppedAnimation(_toneActive),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(
                    '$cremaining / $ctotal CARGO REMAINING',
                    style: const TextStyle(
                      fontFamily: _mono,
                      fontSize: 10,
                      color: _textSecondary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${(fraction * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(
                      fontFamily: _mono,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: _toneActive,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
            Text(
              'CURRENT PHASE · ${_phaseLabel(autoStatus?.currentPhase ?? '')}',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: _textPrimary,
              ),
            ),
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.hourglass_empty_rounded,
                    size: 16, color: _textMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'NO ACTIVE MISSION',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                          color: _textSecondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Use the machine control panel to drive AGV, Crane, or Trolley.',
                        style: const TextStyle(fontSize: 11, color: _textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  String _phaseLabel(String phase) {
    if (phase.isEmpty) return 'EXECUTING AUTO ROUTINE';
    return phase.toUpperCase();
  }
}

class _MissionMachineChip extends StatelessWidget {
  const _MissionMachineChip({required this.label, required this.state, required this.linked});

  final String label;
  final MachineStatus? state;
  final bool linked;

  @override
  Widget build(BuildContext context) {
    final tone = !linked
        ? _toneWarn
        : _stateTone(state);

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: _colorBg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _colorBorder),
        ),
        child: Row(
          children: [
            _StatusDot(color: tone, size: 7),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
            const Spacer(),
            Text(
              !linked ? 'NO LINK' : _stateLabelShort(state),
              style: TextStyle(
                fontFamily: _mono,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: !linked ? _toneWarn : tone,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Live activity + alerts
// ---------------------------------------------------------------------------

class _LiveActivityPanel extends StatefulWidget {
  const _LiveActivityPanel({
    required this.service,
    required this.agvId,
    required this.craneId,
  });

  final MachineControlService service;
  final String agvId;
  final String craneId;

  @override
  State<_LiveActivityPanel> createState() => _LiveActivityPanelState();
}

class _LiveActivityPanelState extends State<_LiveActivityPanel> {
  List<_ActivityEntry> _entries = [];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final entries = <_ActivityEntry>[];
    for (final (id, label) in [(widget.agvId, 'AGV'), (widget.craneId, 'CRANE')]) {
      try {
        final logs = await widget.service.fetchMachineLogs(id);
        entries.addAll(logs.take(6).map((l) => _ActivityEntry(label: label, activity: l)));
      } catch (_) {}
    }
    entries.sort((a, b) {
      final aTime = DateTime.tryParse(a.activity.time) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = DateTime.tryParse(b.activity.time) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });
    if (mounted) {
      setState(() => _entries = entries.take(10).toList(growable: false));
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'LIVE ACTIVITY',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
              color: _textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          if (_entries.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: Text(
                  'NO RECENT ACTIVITY',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: _textMuted,
                  ),
                ),
              ),
            )
          else
            ..._entries.map((e) {
              final tone = _tone(e.activity.status);
              return Container(
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Color(0xFF14243A), width: 1),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _shortTime(e.activity.time),
                      style: const TextStyle(
                        fontFamily: _mono,
                        fontSize: 10,
                        color: _textMuted,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: 34,
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      decoration: BoxDecoration(
                        color: tone.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        e.label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                          color: tone,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        e.activity.message,
                        style: const TextStyle(
                          fontSize: 11,
                          color: _textSecondary,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Color _tone(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return _toneReady;
      case 'auto':
      case 'running':
        return _toneActive;
      case 'command':
        return _toneActive;
      case 'error':
        return _toneDanger;
      default:
        return _textMuted;
    }
  }

  String _shortTime(String iso) {
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return '';
    final local = parsed.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}:${local.second.toString().padLeft(2, '0')}';
  }
}

class _ActivityEntry {
  const _ActivityEntry({required this.label, required this.activity});
  final String label;
  final MachineActivity activity;
}

class _AlertsPanel extends StatelessWidget {
  const _AlertsPanel({required this.alerts, required this.onRetry});

  final List<_Alert> alerts;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'ALERTS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                  color: _textSecondary,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: (alerts.isEmpty ? _toneReady : _toneWarn).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${alerts.length}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: alerts.isEmpty ? _toneReady : _toneWarn,
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 16, color: _textMuted),
                tooltip: 'Refresh',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (alerts.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline, color: _toneReady, size: 16),
                  SizedBox(width: 10),
                  Text(
                    'All systems nominal.',
                    style: TextStyle(fontSize: 11, color: _textSecondary),
                  ),
                ],
              ),
            )
          else
            ...alerts.map((a) => Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Color(0xFF14243A), width: 1),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 3,
                        height: 30,
                        decoration: BoxDecoration(
                          color: a.tone,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              a.title.toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6,
                                color: a.tone,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              a.detail,
                              style: const TextStyle(
                                fontSize: 10,
                                color: _textMuted,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )),
        ],
      ),
    );
  }
}

class _Alert {
  const _Alert({required this.severity, required this.title, required this.detail});

  final int severity;
  final String title;
  final String detail;

  Color get tone => severity > 1
      ? _toneDanger
      : (severity == 1 ? _toneWarn : _toneActive);
}

// ---------------------------------------------------------------------------
// Connection / error handling
// ---------------------------------------------------------------------------

class _TelemetryErrorPanel extends StatefulWidget {
  const _TelemetryErrorPanel({required this.detail, required this.onRetry});

  final String detail;
  final VoidCallback onRetry;

  @override
  State<_TelemetryErrorPanel> createState() => _TelemetryErrorPanelState();
}

class _TelemetryErrorPanelState extends State<_TelemetryErrorPanel> {
  bool _showDetail = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _toneDanger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _toneDanger.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: _toneDanger, size: 18),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MACHINE TELEMETRY UNAVAILABLE',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: _textPrimary,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Unable to reach the machine gateway. Live status is paused.',
                      style: TextStyle(fontSize: 11, color: _textSecondary),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: widget.onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 14),
                label: const Text('RETRY',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
                style: TextButton.styleFrom(foregroundColor: _toneDanger),
              ),
            ],
          ),
          GestureDetector(
            onTap: () => setState(() => _showDetail = !_showDetail),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _showDetail ? Icons.expand_less : Icons.expand_more,
                  size: 14,
                  color: _textMuted,
                ),
                const SizedBox(width: 4),
                Text(
                  _showDetail ? 'HIDE DETAILS' : 'SHOW DETAILS',
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: _textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (_showDetail) ...[
            const SizedBox(height: 6),
            Text(
              widget.detail,
              style: const TextStyle(
                fontFamily: _mono,
                fontSize: 9,
                color: _textMuted,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LoadingPanel extends StatelessWidget {
  const _LoadingPanel();

  @override
  Widget build(BuildContext context) {
    return const _Panel(
      child: Center(
        child: SizedBox(
          width: double.infinity,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 160,
                child: ClipRRect(
                  borderRadius: BorderRadius.all(Radius.circular(3)),
                  child: LinearProgressIndicator(
                    minHeight: 4,
                    backgroundColor: _colorBorder,
                    valueColor: AlwaysStoppedAnimation(_toneActive),
                  ),
                ),
              ),
              SizedBox(height: 10),
              Text(
                'CONNECTING TO MACHINE GATEWAY…',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: _textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Detailed control sheet
// ---------------------------------------------------------------------------

class _DetailedControlSheet extends StatelessWidget {
  const _DetailedControlSheet({
    required this.spec,
    required this.service,
    required this.kind,
  });

  final _MachineSpec spec;
  final MachineControlService service;
  final _ControlKind kind;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.86,
      decoration: const BoxDecoration(
        color: _colorBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
        border: Border(top: BorderSide(color: _colorBorderHi, width: 1)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            width: 36,
            height: 3,
            decoration: BoxDecoration(
              color: _colorBorderHi,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: _toneActive.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _colorBorderHi),
                  ),
                  child: Icon(spec.icon, color: _toneActive, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${spec.name} · DETAILED CONTROL',
                        style: const TextStyle(
                          color: _textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                      Text(
                        spec.typeLabel.toUpperCase(),
                        style: const TextStyle(
                          color: _textMuted,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, color: _textSecondary),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          const Divider(color: _colorBorder, height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MachineSimulationBanner(machineId: spec.id, service: service),
                  const SizedBox(height: 12),
                  ..._buildDetailedControls(context),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildDetailedControls(BuildContext context) {
    switch (kind) {
      case _ControlKind.agv:
        return [
          AgvControlCard(machineId: spec.id, service: service),
          const SizedBox(height: 14),
          AutoModeCard(machineId: spec.id, service: service, machineType: 'agv'),
          const SizedBox(height: 14),
          CommandHistoryTable(machineId: spec.id, service: service),
          const SizedBox(height: 14),
          MachineActivityFeed(machineId: spec.id, service: service),
        ];
      case _ControlKind.crane:
        return [
          CraneDriveCard(machineId: spec.id, service: service),
          const SizedBox(height: 14),
          AutoModeCard(machineId: spec.id, service: service, machineType: 'crane'),
          const SizedBox(height: 14),
          CommandHistoryTable(machineId: spec.id, service: service),
          const SizedBox(height: 14),
          MachineActivityFeed(machineId: spec.id, service: service),
        ];
      case _ControlKind.trolley:
        return [
          TrolleyControlCard(machineId: spec.id, service: service),
          const SizedBox(height: 14),
          CommandHistoryTable(machineId: spec.id, service: service),
          const SizedBox(height: 14),
          MachineActivityFeed(machineId: spec.id, service: service),
        ];
    }
  }
}

// ---------------------------------------------------------------------------
// Machine spec + helpers
// ---------------------------------------------------------------------------

class _MachineSpec {
  const _MachineSpec({
    required this.id,
    required this.name,
    required this.typeLabel,
    required this.accent,
    required this.icon,
    required this.calibration,
  });

  final String id;
  final String name;
  final String typeLabel;
  final Color accent;
  final IconData icon;
  final MovementCalibration calibration;
}

String _machineLabel(_ControlKind kind) {
  return switch (kind) {
    _ControlKind.agv => 'AGV-01',
    _ControlKind.crane => 'CRANE-01',
    _ControlKind.trolley => 'TROLLEY-01',
  };
}

Color _stateTone(MachineStatus? status) {
  return switch (status) {
    MachineStatus.idle => _toneReady,
    MachineStatus.running => _toneActive,
    MachineStatus.maintenance => _toneWarn,
    MachineStatus.error => _toneDanger,
    MachineStatus.disconnected || null => _toneIdle,
  };
}

String _stateLabel(MachineStatus? status) {
  return switch (status) {
    MachineStatus.idle => 'READY',
    MachineStatus.running => 'WORKING',
    MachineStatus.maintenance => 'MAINTENANCE',
    MachineStatus.error => 'ERROR',
    MachineStatus.disconnected || null => 'OFFLINE',
  };
}

String _stateLabelShort(MachineStatus? status) {
  return switch (status) {
    MachineStatus.running => 'WRK',
    MachineStatus.maintenance => 'MNT',
    MachineStatus.error => 'ERR',
    MachineStatus.idle => 'RDY',
    MachineStatus.disconnected || null => 'OFF',
  };
}

String _unitSymbol(_DistanceUnit unit) {
  return switch (unit) {
    _DistanceUnit.mm => 'mm',
    _DistanceUnit.cm => 'cm',
    _DistanceUnit.m => 'm',
  };
}

String _friendlyError(Object error) {
  final s = error.toString();
  if (s.contains('Connection timed out')) {
    return 'The machine gateway timed out. Check the connection and retry.';
  }
  if (s.contains('SocketException') ||
      s.contains('ClientException') ||
      s.contains('Failed host lookup')) {
    return 'Unable to reach the machine gateway. Check the network and retry.';
  }
  if (s.contains('Invalid command')) {
    return 'The machine gateway rejected the command.';
  }
  if (s.contains('Request failed: 4')) {
    return 'The machine gateway rejected the request.';
  }
  if (s.contains('Request failed: 5')) {
    return 'The machine gateway is unavailable (server error).';
  }
  if (s.startsWith('MachineControlException')) {
    final rest = s.replaceFirst('MachineControlException: ', '').trim();
    if (rest.isNotEmpty && rest != s) return rest;
  }
  return 'The command could not be executed.';
}