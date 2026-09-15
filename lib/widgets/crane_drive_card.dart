import 'dart:async';
import 'package:flutter/material.dart';

import '../models/machine_command.dart';
import '../models/machine_status.dart';
import '../providers/theme_provider.dart';
import '../services/machine_control_service.dart';
import 'glass_card.dart';

enum CraneDriveMode { joystick, timed }

class CraneDriveCard extends StatefulWidget {
  const CraneDriveCard({super.key, required this.machineId, required this.service});

  final String machineId;
  final MachineControlService service;

  @override
  State<CraneDriveCard> createState() => _CraneDriveCardState();
}

class _CraneDriveCardState extends State<CraneDriveCard> {
  CraneDriveMode _mode = CraneDriveMode.joystick;
  double _speed = 100;
  double _duration = 3;
  bool _executing = false;
  String? _lastError;
  String? _activeMove;
  DriveStatus? _driveStatus;
  Timer? _statusTimer;
  Timer? _stopTimer;

  @override
  void initState() {
    super.initState();
    _refreshDriveStatus();
    _statusTimer = Timer.periodic(const Duration(seconds: 10), (_) => _refreshDriveStatus());
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _stopTimer?.cancel();
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

  void _stopNow() {
    if (_stopTimer != null) {
      _stopTimer!.cancel();
      _stopTimer = null;
    }
    setState(() => _activeMove = null);
    _sendDrive('stop');
  }

  // Joystick: drive is a single start on press, stop on release. The crane
  // drive ESP keeps moving until a 'stop' arrives.
  void _joystickStart(String move) {
    _stopTimer?.cancel();
    _stopTimer = null;
    setState(() => _activeMove = move);
    _sendDrive(move);
  }

  void _joystickEnd() {
    if (_activeMove != null) _stopNow();
  }

  // Timed: start moving, auto-stop after the configured duration.
  void _timedMove(String move) {
    _sendDrive(move);
    _stopTimer?.cancel();
    setState(() => _activeMove = move);
    _stopTimer = Timer(Duration(milliseconds: (_duration * 1000).round()), () {
      _stopTimer = null;
      setState(() => _activeMove = null);
      _sendDrive('stop');
    });
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
            mode: _mode,
            executing: _executing,
            onJoystickStart: _joystickStart,
            onJoystickEnd: _joystickEnd,
            onTimedMove: _timedMove,
            onStop: _stopNow,
          ),
          if (_activeMove != null) ...[
            const SizedBox(height: 10),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: AppPalette.success.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.play_arrow_rounded, size: 14, color: AppPalette.success),
                    const SizedBox(width: 4),
                    Text(
                      'Moving $_activeMove at ${_speed.toInt()}%',
                      style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700, color: AppPalette.success,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _mode == CraneDriveMode.joystick
                    ? 'Press and hold to move, release to stop'
                    : 'Move for a set time then auto-stop',
                style: TextStyle(
                  fontSize: 10,
                  color: isDark ? Colors.white38 : Colors.grey[500],
                ),
              ),
              _ModeToggle(
                mode: _mode,
                onChanged: (m) {
                  _stopTimer?.cancel();
                  _stopTimer = null;
                  setState(() {
                    _mode = m;
                    _activeMove = null;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 12),

          _SliderRow(
            label: 'Speed',
            value: _speed,
            min: 10,
            max: 255,
            divisions: 49,
            suffix: '${_speed.toInt()}',
            onChanged: (v) => setState(() => _speed = v),
          ),
          if (_mode == CraneDriveMode.timed) ...[
            const SizedBox(height: 8),
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
        ],
      ),
    );
  }
}

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.mode, required this.onChanged});
  final CraneDriveMode mode;
  final ValueChanged<CraneDriveMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey[100],
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: CraneDriveMode.values.map((m) {
          final active = mode == m;
          return GestureDetector(
            onTap: () => onChanged(m),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: active ? AppPalette.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                m == CraneDriveMode.joystick ? 'Joystick' : 'Timed',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: active ? Colors.white : (isDark ? Colors.white54 : Colors.grey[600]),
                ),
              ),
            ),
          );
        }).toList(),
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
  const _CraneDirectionPad({
    required this.mode,
    required this.executing,
    required this.onJoystickStart,
    required this.onJoystickEnd,
    required this.onTimedMove,
    required this.onStop,
  });

  final CraneDriveMode mode;
  final bool executing;
  final void Function(String) onJoystickStart;
  final VoidCallback onJoystickEnd;
  final void Function(String) onTimedMove;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey[100];
    final borderColor = isDark ? Colors.white.withValues(alpha: 0.12) : Colors.grey[300]!;
    final joystick = mode == CraneDriveMode.joystick;

    Widget moveBtn(String move, IconData icon, {Color? color}) {
      return _PadBtn(
        icon: icon,
        enabled: !executing,
        onJoystickStart: joystick ? () => onJoystickStart(move) : null,
        onJoystickEnd: joystick ? onJoystickEnd : null,
        onTap: joystick ? null : () => onTimedMove(move),
        bg: bgColor,
        border: borderColor,
        iconColor: color,
      );
    }

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(width: 56),
            moveBtn('forward', Icons.arrow_upward_rounded),
            const SizedBox(width: 56),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            moveBtn('backward', Icons.arrow_back_rounded),
            _PadBtn(
              icon: Icons.stop_rounded,
              enabled: !executing,
              onJoystickStart: joystick ? onStop : null,
              onTap: joystick ? null : onStop,
              bg: AppPalette.coral.withValues(alpha: 0.12),
              border: AppPalette.coral.withValues(alpha: 0.3),
              iconColor: AppPalette.coral,
            ),
            moveBtn('forward', Icons.arrow_forward_rounded),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(width: 56),
            moveBtn('backward', Icons.arrow_downward_rounded),
            const SizedBox(width: 56),
          ],
        ),
      ],
    );
  }
}

class _PadBtn extends StatelessWidget {
  const _PadBtn({
    required this.icon,
    required this.enabled,
    this.onJoystickStart,
    this.onJoystickEnd,
    this.onTap,
    this.bg,
    this.border,
    this.iconColor,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback? onJoystickStart;
  final VoidCallback? onJoystickEnd;
  final VoidCallback? onTap;
  final Color? bg;
  final Color? border;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final hasHold = onJoystickStart != null && onJoystickEnd != null;
    return Padding(
      padding: const EdgeInsets.all(4),
      child: GestureDetector(
        onTapDown: hasHold ? (_) => onJoystickStart!() : null,
        onTapUp: hasHold ? (_) => onJoystickEnd!() : null,
        onTapCancel: hasHold ? onJoystickEnd : null,
        onTap: (!hasHold && enabled && onTap != null) ? onTap : null,
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