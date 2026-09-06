import 'dart:async';

import 'package:flutter/material.dart';

import '../models/machine_command.dart';
import '../models/machine_status.dart';
import '../providers/theme_provider.dart';
import '../services/machine_control_service.dart';
import '../widgets/glass_card.dart';

class MachineStatusScreen extends StatefulWidget {
  const MachineStatusScreen({
    super.key,
    this.onOpenAgv,
    this.onOpenCrane,
    this.onOpenTrolley,
  });

  final VoidCallback? onOpenAgv;
  final VoidCallback? onOpenCrane;
  final VoidCallback? onOpenTrolley;

  @override
  State<MachineStatusScreen> createState() => _MachineStatusScreenState();
}

class _MachineStatusScreenState extends State<MachineStatusScreen> {
  late final MachineControlService _service;
  DashboardSummary? _summary;
  Map<String, DriveStatus> _driveStatuses = {};
  Map<String, AutoModeStatus> _autoStatuses = {};
  Map<String, MachineCommand> _latestCommands = {};
  bool _loading = true;
  String? _error;
  Timer? _timer;

  static const _agvId = '1';
  static const _craneId = '2';

  @override
  void initState() {
    super.initState();
    _service = MachineControlService();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _service.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    try {
      final summary = await _service.fetchDashboardSummary();
      final drive = <String, DriveStatus>{};
      final auto = <String, AutoModeStatus>{};
      final latest = <String, MachineCommand>{};
      for (final machine in summary.machines) {
        drive[machine.id] = await _service.fetchDriveStatus(machine.id);
        final first = await _firstCommand(machine.id);
        if (first != null) latest[machine.id] = first;
        try {
          auto[machine.id] = await _service.fetchAutoModeStatus(machine.id);
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _summary = summary;
          _driveStatuses = drive;
          _autoStatuses = auto;
          _latestCommands = latest;
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        if (!silent) _error = e.toString();
      }
    }
  }

  Future<MachineCommand?> _firstCommand(String machineId) async {
    try {
      final history = await _service.fetchCommandHistory(machineId);
      return history.isEmpty ? null : history.first;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PageHeading(
            icon: Icons.monitor_heart_rounded,
            accent: const Color(0xFF38BDF8),
            title: 'Machine Status',
            subtitle:
                'Live overview of the port automation fleet, connection state, and last command for every controller.',
          ),
          const SizedBox(height: 16),
          if (_error != null) ...[
            _ErrorBanner(error: _error!, onRetry: _load),
            const SizedBox(height: 12),
          ],
          DashboardSummaryPillBar(
            summary: _summary,
            driveStatuses: _driveStatuses,
          ),
          const SizedBox(height: 20),
          if (_loading && _summary == null)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(48),
                child: CircularProgressIndicator(color: AppPalette.accent),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final cardWidth = constraints.maxWidth >= 1000
                    ? (constraints.maxWidth - 32) / 3
                    : constraints.maxWidth >= 660
                        ? (constraints.maxWidth - 16) / 2
                        : constraints.maxWidth;
                return Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    SizedBox(
                      width: cardWidth,
                      child: _FleetStatusCard(
                        machineId: _agvId,
                        machine: _machineFor(_agvId),
                        driveStatus: _driveStatuses[_agvId],
                        autoStatus: _autoStatuses[_agvId],
                        latestCommand: _latestCommands[_agvId],
                        accent: const Color(0xFF38BDF8),
                        icon: Icons.smart_toy_rounded,
                        typeLabel: 'Automated Guided Vehicle',
                        onOpen: widget.onOpenAgv,
                      ),
                    ),
                    SizedBox(
                      width: cardWidth,
                      child: _FleetStatusCard(
                        machineId: _craneId,
                        machine: _machineFor(_craneId),
                        driveStatus: _driveStatuses[_craneId],
                        autoStatus: _autoStatuses[_craneId],
                        latestCommand: _latestCommands[_craneId],
                        accent: const Color(0xFF38BDF8),
                        icon: Icons.construction_rounded,
                        typeLabel: 'Quay Crane',
                        onOpen: widget.onOpenCrane,
                      ),
                    ),
                    SizedBox(
                      width: cardWidth,
                      child: _FleetStatusCard(
                        machineId: _craneId,
                        machine: _machineFor(_craneId),
                        driveStatus: _driveStatuses[_craneId],
                        autoStatus: _autoStatuses[_craneId],
                        latestCommand: _latestCommands[_craneId],
                        accent: const Color(0xFF2DD4BF),
                        icon: Icons.linear_scale_rounded,
                        typeLabel: 'Trolley / Hoist unit',
                        isTrolley: true,
                        onOpen: widget.onOpenTrolley,
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  MachineDetail? _machineFor(String id) {
    final machines = _summary?.machines ?? const <MachineDetail>[];
    for (final machine in machines) {
      if (machine.id == id) return machine;
    }
    return null;
  }
}

class DashboardSummaryPillBar extends StatelessWidget {
  const DashboardSummaryPillBar({
    super.key,
    required this.summary,
    required this.driveStatuses,
  });

  final DashboardSummary? summary;
  final Map<String, DriveStatus> driveStatuses;

  @override
  Widget build(BuildContext context) {
    final machines = summary?.machines ?? const <MachineDetail>[];
    if (machines.isEmpty) return const SizedBox.shrink();

    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        children: machines.map((machine) {
          final online = driveStatuses[machine.id]?.online ?? false;
          final anyOnline = driveStatuses.values.any((s) => s.online);
          final simMode = !anyOnline;
          return _SummaryPill(
            label: '${machine.name} · ${machine.status.name.toUpperCase()}',
            detail: simMode ? 'SIMULATION' : 'LINKED',
            tone: simMode ? AppPalette.warning : AppPalette.success,
            icon: online ? Icons.link_rounded : Icons.science_outlined,
          );
        }).toList(),
      ),
    );
  }
}

class _SummaryPill extends StatelessWidget {
  const _SummaryPill({
    required this.label,
    required this.detail,
    required this.tone,
    required this.icon,
  });

  final String label;
  final String detail;
  final Color tone;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tone.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: tone),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: tone),
          ),
          const SizedBox(width: 8),
          Container(
            width: 3,
            height: 3,
            decoration: BoxDecoration(shape: BoxShape.circle, color: tone),
          ),
          const SizedBox(width: 6),
          Text(
            detail,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: tone),
          ),
        ],
      ),
    );
  }
}

class _FleetStatusCard extends StatelessWidget {
  const _FleetStatusCard({
    required this.machineId,
    required this.machine,
    required this.driveStatus,
    required this.autoStatus,
    required this.latestCommand,
    required this.accent,
    required this.icon,
    required this.typeLabel,
    this.isTrolley = false,
    this.onOpen,
  });

  final String machineId;
  final MachineDetail? machine;
  final DriveStatus? driveStatus;
  final AutoModeStatus? autoStatus;
  final MachineCommand? latestCommand;
  final Color accent;
  final IconData icon;
  final String typeLabel;
  final bool isTrolley;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final online = driveStatus?.online ?? false;
    final simMode = !online;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: 0.15),
                ),
                child: Icon(icon, color: accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isTrolley ? 'Trolley' : (machine?.name ?? 'Machine $machineId'),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : AppPalette.navy,
                      ),
                    ),
                    Text(
                      typeLabel,
                      style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.grey[500]),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: (simMode ? AppPalette.warning : AppPalette.success).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: simMode ? AppPalette.warning : AppPalette.success,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      simMode ? 'SIMULATION' : 'LINKED',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        color: simMode ? AppPalette.warning : AppPalette.success,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (machine != null)
            _InfoRow(label: 'State', value: machine!.status.name.toUpperCase(), tone: accent)
          else
            const _InfoRow(label: 'State', value: '—', tone: Colors.grey),
          const SizedBox(height: 8),
          _InfoRow(
            label: 'Connection',
            value: online ? 'ONLINE' : 'OFFLINE',
            tone: online ? AppPalette.success : Colors.grey,
          ),
          const SizedBox(height: 8),
          _InfoRow(
            label: 'Auto Mode',
            value: (autoStatus?.running ?? false)
                ? autoStatus!.currentPhase.toUpperCase()
                : 'OFF',
            tone: (autoStatus?.running ?? false) ? AppPalette.warning : Colors.grey,
          ),
          const SizedBox(height: 8),
          _InfoRow(
            label: 'Last Command',
            value: latestCommand != null
                ? '${latestCommand!.command}${latestCommand!.params.isEmpty ? '' : ' : ${latestCommand!.params}'}'
                : '—',
            tone: latestCommand != null ? AppPalette.accent : Colors.grey,
          ),
          const SizedBox(height: 8),
          _InfoRow(
            label: 'Command Status',
            value: latestCommand == null ? '—' : latestCommand!.status.name.toUpperCase(),
            tone: latestCommand == null ? Colors.grey : _commandTone(latestCommand!.status),
          ),
          const SizedBox(height: 14),
          if (onOpen != null)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onOpen,
                icon: const Icon(Icons.tune_rounded, size: 16),
                label: Text(
                  'Open ${isTrolley ? 'Trolley Control' : 'Controller'}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: accent,
                  side: BorderSide(color: accent.withValues(alpha: 0.4)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, required this.tone});

  final String label;
  final String value;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        SizedBox(
          width: 92,
          child: Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
              color: isDark ? Colors.white38 : Colors.grey[500],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: tone,
            ),
          ),
        ),
      ],
    );
  }
}

Color _commandTone(CommandStatus status) {
  return switch (status) {
    CommandStatus.pending => AppPalette.warning,
    CommandStatus.inProgress => AppPalette.accent,
    CommandStatus.completed => AppPalette.success,
    CommandStatus.failed => AppPalette.coral,
    CommandStatus.cancelled => Colors.grey,
  };
}

class _PageHeading extends StatelessWidget {
  const _PageHeading({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accent.withValues(alpha: 0.15),
          ),
          child: Icon(icon, color: accent, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : AppPalette.navy,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(fontSize: 12, height: 1.4, color: isDark ? Colors.white54 : Colors.grey[600]),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppPalette.coral.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppPalette.coral.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppPalette.coral, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Machine telemetry unavailable: $error',
              style: const TextStyle(color: AppPalette.coral, fontSize: 12),
            ),
          ),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 14),
            label: const Text('Retry', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(foregroundColor: AppPalette.coral),
          ),
        ],
      ),
    );
  }
}