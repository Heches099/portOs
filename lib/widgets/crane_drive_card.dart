import 'dart:async';
import 'package:flutter/material.dart';

import '../models/machine_command.dart';
import '../models/machine_status.dart';
import '../providers/theme_provider.dart';
import '../services/machine_control_service.dart';
import 'glass_card.dart';

class CraneDriveCard extends StatefulWidget {
  const CraneDriveCard({super.key, required this.machineId, required this.service});

  final String machineId;
  final MachineControlService service;

  @override
  State<CraneDriveCard> createState() => _CraneDriveCardState();
}

class _CraneDriveCardState extends State<CraneDriveCard> {
  double _speed = 100;
  double _duration = 3;
  bool _executing = false;
  String? _lastError;
  DriveStatus? _driveStatus;
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    _refreshDriveStatus();
    _statusTimer = Timer.periodic(const Duration(seconds: 10), (_) => _refreshDriveStatus());
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshDriveStatus() async {
    try {
      final status = await widget.service.fetchDriveStatus(widget.machineId);
      if (mounted) setState(() => _driveStatus = status);
    } catch (_) {}
  }

  Future<void> _sendDrive(String move) async {
    if (_executing) return;
    setState(() {
      _executing = true;
      _lastError = null;
    });
    try {
      await widget.service.sendDriveCommand(
        widget.machineId,
        DriveRequest(move: move, speed: _speed.toInt()),
      );
    } catch (e) {
      if (mounted) setState(() => _lastError = e.toString());
    } finally {
      if (mounted) setState(() => _executing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.construction_rounded, color: AppPalette.accent, size: 20),
              const SizedBox(width: 8),
              Text('Crane Drive', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              _OnlineIndicator(online: _driveStatus?.online ?? false),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _driveStatus?.online == true
                ? 'Drive online — polling every 10s'
                : 'Drive offline or unreachable',
            style: TextStyle(
              fontSize: 11,
              color: _driveStatus?.online == true
                  ? AppPalette.success
                  : (isDark ? Colors.white38 : Colors.grey[500]),
            ),
          ),
          if (_lastError != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppPalette.coral.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: AppPalette.coral, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _lastError!,
                      style: const TextStyle(color: AppPalette.coral, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),

          Text(
            'Whole Crane Movement',
            style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600,
              color: isDark ? Colors.white54 : Colors.grey[600],
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 10),
          _CraneDirectionPad(
            executing: _executing,
            onDrive: _sendDrive,
          ),
          const SizedBox(height: 14),

          _SliderRow(
            label: 'Speed',
            value: _speed,
            min: 10,
            max: 255,
            divisions: 49,
            suffix: '${_speed.toInt()}',
            onChanged: (v) => setState(() => _speed = v),
          ),
          _SliderRow(
            label: 'Duration',
            value: _duration,
            min: 0.5,
            max: 10,
            divisions: 19,
            suffix: '${_duration.toStringAsFixed(1)}s',
            onChanged: (v) => setState(() => _duration = v),
          ),
        ],
      ),
    );
  }
}

class _OnlineIndicator extends StatelessWidget {
  const _OnlineIndicator({required this.online});
  final bool online;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: online ? AppPalette.success : Colors.grey,
            boxShadow: online
                ? [BoxShadow(color: AppPalette.success.withValues(alpha: 0.4), blurRadius: 6)]
                : null,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          online ? 'Online' : 'Offline',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: online ? AppPalette.success : Colors.grey,
          ),
        ),
      ],
    );
  }
}

class _CraneDirectionPad extends StatelessWidget {
  const _CraneDirectionPad({required this.executing, required this.onDrive});
  final bool executing;
  final void Function(String) onDrive;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey[100];
    final borderColor = isDark ? Colors.white.withValues(alpha: 0.12) : Colors.grey[300]!;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(width: 56),
            _PadBtn(icon: Icons.arrow_upward_rounded, enabled: !executing, onTap: () => onDrive('forward'), bg: bgColor, border: borderColor),
            const SizedBox(width: 56),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _PadBtn(icon: Icons.arrow_back_rounded, enabled: !executing, onTap: () => onDrive('backward'), bg: bgColor, border: borderColor),
            _PadBtn(
              icon: Icons.stop_rounded, enabled: !executing,
              onTap: () => onDrive('stop'),
              bg: AppPalette.coral.withValues(alpha: 0.12),
              border: AppPalette.coral.withValues(alpha: 0.3),
              iconColor: AppPalette.coral,
            ),
            _PadBtn(icon: Icons.arrow_forward_rounded, enabled: !executing, onTap: () => onDrive('forward'), bg: bgColor, border: borderColor),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(width: 56),
            _PadBtn(icon: Icons.arrow_downward_rounded, enabled: !executing, onTap: () => onDrive('backward'), bg: bgColor, border: borderColor),
            const SizedBox(width: 56),
          ],
        ),
      ],
    );
  }
}

class _PadBtn extends StatelessWidget {
  const _PadBtn({required this.icon, required this.enabled, required this.onTap, this.bg, this.border, this.iconColor});
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final Color? bg;
  final Color? border;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border ?? Colors.grey[300]!),
          ),
          child: Icon(icon, size: 22, color: enabled ? (iconColor ?? Theme.of(context).colorScheme.onSurface) : Colors.grey),
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({required this.label, required this.value, required this.min, required this.max, required this.divisions, required this.suffix, required this.onChanged});
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String suffix;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        SizedBox(width: 70, child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? Colors.white54 : Colors.grey[600]))),
        Expanded(child: Slider(value: value, min: min, max: max, divisions: divisions, activeColor: AppPalette.accent, onChanged: onChanged)),
        SizedBox(width: 45, child: Text(suffix, textAlign: TextAlign.right, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: isDark ? Colors.white70 : Colors.grey[700]))),
      ],
    );
  }
}
