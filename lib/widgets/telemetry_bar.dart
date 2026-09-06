import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/ppe_detection_result.dart';
import '../models/realtime_telemetry.dart';
import '../providers/machine_selection_controller.dart';
import '../theme/industrial_theme.dart';

/// Bottom real-time telemetry strip for the Live Operations workspace.
///
/// All readings are bound to the shared [MachineSelectionController] so they
/// track the selected machine, the live AI result, and the gateway state.
/// Each cell is plain data that a WebSocket / FastAPI / ESP32 feed can drive.
class TelemetryBar extends StatefulWidget {
  const TelemetryBar({super.key});

  @override
  State<TelemetryBar> createState() => _TelemetryBarState();
}

class _TelemetryBarState extends State<TelemetryBar> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<MachineSelectionController>();
    final machine = controller.selectedMachine;
    final telemetry = controller.telemetry;
    final isAgv = machine.kind == MachineKind.agv;

    final connectionState = controller.connectionStateFor(machine.id);
    final stale = controller.isTelemetryStaleFor(machine.id);
    final age = controller.telemetryAgeFor(machine.id);

    final aiActive = controller.aiScanning || controller.aiResult != null;
    final aiViolation = controller.aiResult != null &&
        _hasViolation(controller.aiResult!);
    final safetyOk = !aiViolation &&
        (telemetry.safetyStatus == 'SAFE' || telemetry.safetyStatus == 'CLEAR');

    final cells = <_TelemetryCell>[
      _TelemetryCell(
        label: 'MACHINE',
        value: machine.name,
        color: machine.accent,
        mono: false,
      ),
      _TelemetryCell(
        label: 'SYSTEM',
        value: controller.simulatedMode ? 'SIMULATED' : 'REAL HARDWARE',
        color: controller.simulatedMode
            ? IndustrialTheme.warn
            : IndustrialTheme.ready,
        mono: false,
      ),
      _TelemetryCell(
        label: 'STATE',
        value: stale ? 'STALE' : telemetry.stateLabel,
        color: stale ? IndustrialTheme.danger : telemetry.stateColor,
        mono: false,
      ),
      _TelemetryCell(
        label: 'POSITION',
        value: isAgv
            ? '${telemetry.positionX.toStringAsFixed(1)}, ${telemetry.positionY.toStringAsFixed(1)} m'
            : '${telemetry.positionX.toStringAsFixed(1)} m',
      ),
      _TelemetryCell(
        label: 'SPEED',
        value: '${telemetry.speed.toStringAsFixed(2)} m/s',
        color: telemetry.speed > 0 ? IndustrialTheme.control : null,
      ),
      _TelemetryCell(
        label: 'DISTANCE',
        value: telemetry.remainingDistance > 0
            ? '${telemetry.remainingDistance.toStringAsFixed(1)} m'
            : '${(telemetry.distanceTravelled / 1000).toStringAsFixed(1)} km',
      ),
      _TelemetryCell(
        label: 'BATTERY',
        value: telemetry.battery == null
            ? '--'
            : '${telemetry.battery!.toStringAsFixed(0)}%',
        color: telemetry.battery == null
            ? IndustrialTheme.textMuted
            : (telemetry.battery! <= 20
                ? IndustrialTheme.danger
                : (telemetry.battery! <= 40
                    ? IndustrialTheme.warn
                    : null)),
      ),
      _TelemetryCell(
        label: 'LOAD',
        value: telemetry.loadStatus,
        color: telemetry.loadStatus == 'LOADED'
            ? IndustrialTheme.warn
            : null,
        mono: false,
      ),
      _TelemetryCell(
        label: 'TEMP',
        value: telemetry.temperature == null
            ? '--'
            : '${telemetry.temperature!.toStringAsFixed(1)}°C',
        color: telemetry.temperature == null
            ? IndustrialTheme.textMuted
            : (telemetry.temperature! > 70
                ? IndustrialTheme.danger
                : null),
      ),
      _TelemetryCell(
        label: 'MISSION',
        value: telemetry.mission,
        color: telemetry.mission == '--' ? IndustrialTheme.textMuted : null,
        mono: false,
      ),
      _TelemetryCell(
        label: 'CONNECTION',
        value: connectionState == MachineConnectionState.online
            ? 'ONLINE'
            : connectionState == MachineConnectionState.connecting
                ? 'CONNECTING'
                : connectionState == MachineConnectionState.degraded
                    ? 'DEGRADED'
                    : 'OFFLINE',
        color: switch (connectionState) {
          MachineConnectionState.online => IndustrialTheme.ready,
          MachineConnectionState.connecting => IndustrialTheme.warn,
          MachineConnectionState.degraded ||
          MachineConnectionState.offline => IndustrialTheme.danger,
        },
        mono: false,
      ),
      _TelemetryCell(
        label: 'AGE',
        value: stale
            ? 'TELEMETRY STALE'
            : age == null
                ? '--'
                : '${(age.inMilliseconds / 1000).toStringAsFixed(1)}s ago',
        color: stale ? IndustrialTheme.danger : null,
        mono: false,
      ),
      _TelemetryCell(
        label: 'AI STATUS',
        value: aiActive ? 'ACTIVE' : 'STANDBY',
        color: aiActive ? IndustrialTheme.teal : IndustrialTheme.textMuted,
        mono: false,
      ),
      _TelemetryCell(
        label: 'SAFETY',
        value: safetyOk ? 'CLEAR' : 'VIOLATION',
        color: safetyOk ? IndustrialTheme.ready : IndustrialTheme.danger,
        mono: false,
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: IndustrialTheme.panelDeep,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: IndustrialTheme.border),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            for (var i = 0; i < cells.length; i++) ...[
              cells[i],
              if (i != cells.length - 1)
                Container(
                  width: 1,
                  height: 28,
                  margin: const EdgeInsets.symmetric(horizontal: 14),
                  color: IndustrialTheme.border,
                ),
            ],
          ],
        ),
      ),
    );
  }

  bool _hasViolation(PpeDetectionResult result) {
    final headCount = result.countFor('head');
    final helmetCount = result.countFor('helmet');
    final vestCount = result.countFor('vest');
    return headCount > helmetCount || headCount > vestCount;
  }
}

class _TelemetryCell extends StatelessWidget {
  const _TelemetryCell({
    required this.label,
    required this.value,
    this.color,
    this.mono = true,
  });

  final String label;
  final String value;
  final Color? color;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: IndustrialTheme.textMuted,
            fontSize: 8,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            fontFamily: mono ? IndustrialTheme.mono : null,
            color: color ?? Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}