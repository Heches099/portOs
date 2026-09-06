import 'package:flutter/material.dart';

import '../models/machine_command.dart';
import '../providers/theme_provider.dart';
import '../services/machine_control_service.dart';
import 'emergency_stop_button.dart';
import 'glass_card.dart';

enum AgvControlMode { joystick, timed }

class AgvControlCard extends StatefulWidget {
  const AgvControlCard({super.key, required this.machineId, required this.service});

  final String machineId;
  final MachineControlService service;

  @override
  State<AgvControlCard> createState() => _AgvControlCardState();
}

class _AgvControlCardState extends State<AgvControlCard> {
  AgvControlMode _mode = AgvControlMode.joystick;
  double _speed = 100;
  double _duration = 3;
  bool _executing = false;
  String? _lastError;

  Future<void> _sendCommand(String command, {int? speed, int? duration}) async {
    if (_executing) return;
    setState(() { _executing = true; _lastError = null; });
    try {
      await widget.service.sendCommand(
        widget.machineId,
        AgvCommandRequest(
          command: command,
          speed: speed,
          duration: duration,
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _lastError = e.toString());
    } finally {
      if (mounted) setState(() => _executing = false);
    }
  }

  Future<void> _emergencyStop() async {
    await _sendCommand('stop');
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
              Icon(Icons.smart_toy_rounded, color: AppPalette.accent, size: 20),
              const SizedBox(width: 8),
              Text('AGV Control', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              _ModeToggle(
                mode: _mode,
                onChanged: (m) => setState(() => _mode = m),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (_lastError != null)
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 12),
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

          Text(
            'Direction Control',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white54 : Colors.grey[600],
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 10),
          _DirectionPad(
            executing: _executing,
            onCommand: (cmd) {
              if (_mode == AgvControlMode.timed) {
                _sendCommand(
                  cmd,
                  speed: _speed.toInt(),
                  duration: (_duration * 1000).toInt(),
                );
              } else {
                _sendCommand(cmd, speed: _speed.toInt());
              }
            },
          ),
          const SizedBox(height: 16),

          _SliderRow(
            label: 'Speed',
            value: _speed,
            min: 10,
            max: 255,
            divisions: 49,
            suffix: '${_speed.toInt()}',
            onChanged: (v) => setState(() => _speed = v),
          ),
          if (_mode == AgvControlMode.timed) ...[
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
          const SizedBox(height: 16),

          _QuickButton(
            label: 'BLINK',
            icon: Icons.lightbulb_outline,
            color: AppPalette.warning,
            executing: _executing,
            onPressed: () => _sendCommand('blink', speed: 3),
          ),
          const SizedBox(height: 12),

          EmergencyStopButton(onPressed: _emergencyStop, isExecuting: _executing),
        ],
      ),
    );
  }
}

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.mode, required this.onChanged});
  final AgvControlMode mode;
  final ValueChanged<AgvControlMode> onChanged;

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
        children: AgvControlMode.values.map((m) {
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
                m == AgvControlMode.joystick ? 'Joystick' : 'Timed',
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

class _DirectionPad extends StatelessWidget {
  const _DirectionPad({required this.executing, required this.onCommand});
  final bool executing;
  final void Function(String) onCommand;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey[100];
    final borderColor = isDark ? Colors.white.withValues(alpha: 0.12) : Colors.grey[300]!;

    return SizedBox(
      width: 200,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(width: 56),
              _DpadButton(
                icon: Icons.arrow_upward_rounded,
                enabled: !executing,
                onTap: () => onCommand('forward'),
                bgColor: bgColor,
                borderColor: borderColor,
              ),
              const SizedBox(width: 56),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _DpadButton(
                icon: Icons.arrow_back_rounded,
                enabled: !executing,
                onTap: () => onCommand('left'),
                bgColor: bgColor,
                borderColor: borderColor,
              ),
              _DpadButton(
                icon: Icons.stop_rounded,
                enabled: !executing,
                onTap: () => onCommand('stop'),
                bgColor: AppPalette.coral.withValues(alpha: 0.12),
                borderColor: AppPalette.coral.withValues(alpha: 0.3),
                iconColor: AppPalette.coral,
              ),
              _DpadButton(
                icon: Icons.arrow_forward_rounded,
                enabled: !executing,
                onTap: () => onCommand('right'),
                bgColor: bgColor,
                borderColor: borderColor,
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(width: 56),
              _DpadButton(
                icon: Icons.arrow_downward_rounded,
                enabled: !executing,
                onTap: () => onCommand('backward'),
                bgColor: bgColor,
                borderColor: borderColor,
              ),
              const SizedBox(width: 56),
            ],
          ),
        ],
      ),
    );
  }
}

class _DpadButton extends StatelessWidget {
  const _DpadButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
    this.bgColor,
    this.borderColor,
    this.iconColor,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final Color? bgColor;
  final Color? borderColor;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: bgColor ?? (enabled ? null : Colors.grey[200]),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor ?? Colors.grey[300]!),
          ),
          child: Icon(
            icon,
            size: 22,
            color: enabled
                ? (iconColor ?? Theme.of(context).colorScheme.onSurface)
                : Colors.grey,
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
    required this.min,
    required this.max,
    required this.divisions,
    required this.suffix,
    required this.onChanged,
  });

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
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white54 : Colors.grey[600],
            ),
          ),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            activeColor: AppPalette.accent,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 45,
          child: Text(
            suffix,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white70 : Colors.grey[700],
            ),
          ),
        ),
      ],
    );
  }
}

class _QuickButton extends StatelessWidget {
  const _QuickButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.executing,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool executing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: executing ? null : onPressed,
        icon: Icon(icon, size: 16),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.8)),
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color.withValues(alpha: 0.4)),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
