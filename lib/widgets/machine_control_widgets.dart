import 'dart:async';

import 'package:flutter/material.dart';

import '../models/machine_command.dart';
import '../models/machine_status.dart';
import '../providers/theme_provider.dart';
import '../services/machine_control_service.dart';
import 'glass_card.dart';

enum HardwareLinkState { simulation, connected, disconnected }

class MachineSimulationBanner extends StatefulWidget {
  const MachineSimulationBanner({
    super.key,
    required this.machineId,
    required this.service,
  });

  final String machineId;
  final MachineControlService service;

  @override
  State<MachineSimulationBanner> createState() =>
      _MachineSimulationBannerState();
}

class _MachineSimulationBannerState extends State<MachineSimulationBanner> {
  DriveStatus? _driveStatus;
  bool _loaded = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final status = await widget.service.fetchDriveStatus(widget.machineId);
      if (mounted) {
        setState(() {
          _driveStatus = status;
          _loaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  HardwareLinkState get _state {
    if (!_loaded || _driveStatus == null) return HardwareLinkState.disconnected;
    return _driveStatus!.online
        ? HardwareLinkState.connected
        : HardwareLinkState.simulation;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final state = _state;

    final (color, icon, title, subtitle) = switch (state) {
      HardwareLinkState.connected => (
          AppPalette.success,
          Icons.link_rounded,
          'HARDWARE CONNECTED',
          'Controller is linked. Commands are forwarded to the ESP8266 / STM32 unit.',
        ),
      HardwareLinkState.simulation => (
          AppPalette.warning,
          Icons.science_outlined,
          'SIMULATION MODE',
          'No physical controller reported in. Commands are simulated by the backend.',
        ),
      HardwareLinkState.disconnected => (
          AppPalette.coral,
          Icons.link_off_rounded,
          'HARDWARE DISCONNECTED',
          'Controller unreachable or pending first heartbeat from the drive.',
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.14 : 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.35,
                    color: isDark ? Colors.white60 : Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
          if (state == HardwareLinkState.simulation)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppPalette.warning.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _driveStatus?.lastChecked != null
                    ? 'checked ${_driveStatus!.lastChecked!.toLocal().hour.toString().padLeft(2, '0')}:${_driveStatus!.lastChecked!.toLocal().minute.toString().padLeft(2, '0')}'
                    : 'awaiting heartbeat',
                style: const TextStyle(
                  color: AppPalette.warning,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class MachineInfoBar extends StatelessWidget {
  const MachineInfoBar({super.key, required this.machine});

  final MachineDetail? machine;

  @override
  Widget build(BuildContext context) {
    if (machine == null) return const SizedBox.shrink();
    final m = machine!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final items = <_InfoItem>[
      if (m.location.isNotEmpty)
        _InfoItem(Icons.location_on_outlined, 'Location', m.location),
      if (m.operatorName.isNotEmpty)
        _InfoItem(Icons.person_outline, 'Operator', m.operatorName),
      if (m.batteryLevel > 0)
        _InfoItem(
          Icons.battery_std_rounded,
          'Battery',
          '${m.batteryLevel.toStringAsFixed(0)}%',
        ),
      if (m.speed > 0)
        _InfoItem(Icons.speed, 'Speed', m.speed.toStringAsFixed(0)),
      if (m.loadCapacity > 0)
        _InfoItem(
          Icons.inventory_2_outlined,
          'Load',
          '${m.currentLoad.toStringAsFixed(0)}/${m.loadCapacity.toStringAsFixed(0)}',
        ),
    ];

    if (items.isEmpty) return const SizedBox.shrink();

    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Wrap(
        spacing: 20,
        runSpacing: 8,
        children: items.map((item) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(item.icon, size: 14, color: AppPalette.accent),
              const SizedBox(width: 6),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.label,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white38 : Colors.grey[500],
                      letterSpacing: 0.4,
                    ),
                  ),
                  Text(
                    item.value,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white70 : Colors.grey[800],
                    ),
                  ),
                ],
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _InfoItem {
  const _InfoItem(this.icon, this.label, this.value);
  final IconData icon;
  final String label;
  final String value;
}

class AutoModeCard extends StatefulWidget {
  const AutoModeCard({
    super.key,
    required this.machineId,
    required this.service,
    this.machineType,
  });

  final String machineId;
  final MachineControlService service;
  final String? machineType;

  @override
  State<AutoModeCard> createState() => _AutoModeCardState();
}

class _AutoModeCardState extends State<AutoModeCard> {
  AutoModeStatus? _status;
  bool _busy = false;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final status = await widget.service.fetchAutoModeStatus(widget.machineId);
      if (mounted) setState(() => _status = status);
    } catch (_) {}
  }

  Future<void> _start() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.startAutoMode(widget.machineId, const AutoModeRequest(cargo: 5));
      await _refresh();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.stopAutoMode(widget.machineId);
      await _refresh();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final running = _status?.running ?? false;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.autorenew_rounded, color: AppPalette.accent, size: 20),
              const SizedBox(width: 8),
              Text('Auto Mode', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: (running ? AppPalette.success : isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey[100]!)
                      .withValues(alpha: running ? 0.15 : 1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  running ? 'RUNNING' : 'IDLE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: running ? AppPalette.success : (isDark ? Colors.white54 : Colors.grey[600]),
                  ),
                ),
              ),
            ],
          ),
          if (running) ...[
            const SizedBox(height: 12),
            if (_status!.cargoTotal > 0) ...[
              _ProgressBar(
                remaining: _status!.cargoRemaining,
                total: _status!.cargoTotal,
              ),
              const SizedBox(height: 6),
            ],
            if (_status!.currentPhase.isNotEmpty)
              Text(
                'Phase: ${_status!.currentPhase.toUpperCase()}',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white60 : Colors.grey[600],
                ),
              ),
          ] else
            const SizedBox(height: 8),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(color: AppPalette.coral, fontSize: 11),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _start,
                  icon: _busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(Icons.play_arrow_rounded, size: 16),
                  label: const Text('Start Auto', style: TextStyle(fontWeight: FontWeight.w700)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppPalette.success,
                    side: BorderSide(color: AppPalette.success.withValues(alpha: 0.4)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _stop,
                  icon: _busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(Icons.stop_rounded, size: 16),
                  label: const Text('Stop Auto', style: TextStyle(fontWeight: FontWeight.w700)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppPalette.coral,
                    side: BorderSide(color: AppPalette.coral.withValues(alpha: 0.4)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.remaining, required this.total});

  final int remaining;
  final int total;

  @override
  Widget build(BuildContext context) {
    final fraction = total == 0 ? 0.0 : remaining / total;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: LinearProgressIndicator(
        value: fraction,
        minHeight: 8,
        backgroundColor: Colors.white.withValues(alpha: 0.08),
        valueColor: AlwaysStoppedAnimation(
          fraction < 0.3 ? AppPalette.coral : AppPalette.warning,
        ),
      ),
    );
  }
}

class MachineActivityFeed extends StatefulWidget {
  const MachineActivityFeed({
    super.key,
    required this.machineId,
    required this.service,
    this.limit = 8,
  });

  final String machineId;
  final MachineControlService service;
  final int limit;

  @override
  State<MachineActivityFeed> createState() => _MachineActivityFeedState();
}

class _MachineActivityFeedState extends State<MachineActivityFeed> {
  List<MachineActivity> _logs = [];
  bool _loading = true;
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
    try {
      final logs = await widget.service.fetchMachineLogs(widget.machineId);
      if (mounted) {
        setState(() {
          _logs = logs;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _tone(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return AppPalette.success;
      case 'running':
      case 'auto':
        return AppPalette.warning;
      case 'command':
        return AppPalette.accent;
      case 'error':
        return AppPalette.coral;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final visible = _logs.take(widget.limit).toList(growable: false);

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long_outlined, color: isDark ? Colors.white70 : Colors.grey[700], size: 18),
              const SizedBox(width: 8),
              Text('Activity', style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (visible.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'No activity recorded yet.',
                  style: TextStyle(color: isDark ? Colors.white38 : Colors.grey[500], fontSize: 12),
                ),
              ),
            )
          else
            ...visible.map((log) {
              final tone = _tone(log.status);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(top: 5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: tone,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        log.message,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white70 : Colors.grey[800],
                          height: 1.3,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _shortTime(log.time),
                      style: TextStyle(
                        fontSize: 10,
                        color: isDark ? Colors.white38 : Colors.grey[500],
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

  String _shortTime(String iso) {
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return '';
    final local = parsed.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}:${local.second.toString().padLeft(2, '0')}';
  }
}

class ControlSectionTitle extends StatelessWidget {
  const ControlSectionTitle({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Text(
      title,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: isDark ? Colors.white54 : Colors.grey[600],
        letterSpacing: 0.6,
      ),
    );
  }
}

class MachineStatePill extends StatelessWidget {
  const MachineStatePill({super.key, required this.machine});

  final MachineDetail? machine;

  @override
  Widget build(BuildContext context) {
    if (machine == null) {
      return const SizedBox.shrink();
    }
    final color = _statusColor(machine!.status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        machine!.status.name.toUpperCase(),
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color),
      ),
    );
  }
}

Color _statusColor(MachineStatus status) {
  return switch (status) {
    MachineStatus.idle => AppPalette.sky,
    MachineStatus.running => AppPalette.success,
    MachineStatus.maintenance => AppPalette.warning,
    MachineStatus.error => AppPalette.coral,
    MachineStatus.disconnected => Colors.grey,
  };
}