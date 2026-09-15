import 'dart:async';
import 'package:flutter/material.dart';

import '../models/machine_command.dart';
import '../providers/theme_provider.dart';
import '../services/machine_control_service.dart';
import 'glass_card.dart';

class TrolleyControlCard extends StatefulWidget {
  const TrolleyControlCard({super.key, required this.machineId, required this.service});

  final String machineId;
  final MachineControlService service;

  @override
  State<TrolleyControlCard> createState() => _TrolleyControlCardState();
}

class _TrolleyControlCardState extends State<TrolleyControlCard> {
  double _speed = 300;
  double _duration = 1;
  bool _magnetOn = false;
  bool _executing = false;
  String? _lastError;
  int? _hoistPosition;
  Timer? _hoistTimer;

  @override
  void initState() {
    super.initState();
    _refreshHoist();
    _hoistTimer = Timer.periodic(const Duration(seconds: 4), (_) => _refreshHoist());
  }

  @override
  void dispose() {
    _hoistTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshHoist() async {
    try {
      final detail = await widget.service.fetchMachineDetail(widget.machineId);
      if (!mounted) return;
      final parsed = _parseHoistPosition(detail.notes);
      if (parsed != _hoistPosition) setState(() => _hoistPosition = parsed);
    } catch (_) {}
  }

  static int? _parseHoistPosition(String notes) {
    if (notes.isEmpty) return null;
    final part = notes
        .split(';')
        .where((p) => p.trim().startsWith('hoist:') || p.trim().startsWith('hoist='))
        .toList();
    if (part.isEmpty) return null;
    final field = part.first.trim();
    final colon = field.indexOf(':');
    final eq = field.indexOf('=');
    final sep = colon >= 0 ? colon : eq;
    if (sep < 0) return null;
    final n = int.tryParse(field.substring(sep + 1).trim());
    return (n != null && n.isFinite) ? n : null;
  }

  Future<void> _sendCommand(String command, {int? steps}) async {
    if (_executing) return;
    setState(() {
      _executing = true;
      _lastError = null;
    });
    try {
      await widget.service.sendCraneCommand(
        widget.machineId,
        CraneCommandRequest(command: command, steps: steps),
      );
      if (command == 'magnet_on') setState(() => _magnetOn = true);
      if (command == 'magnet_off') setState(() => _magnetOn = false);
    } catch (e) {
      if (mounted) setState(() => _lastError = e.toString());
    } finally {
      if (mounted) setState(() => _executing = false);
    }
  }

  int get _steps => (_speed * _duration).toInt().clamp(1, 10000);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.linear_scale_rounded, color: AppPalette.accent, size: 20),
              const SizedBox(width: 8),
              Text('Trolley Control', style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 16),

          _ControlSection(
            title: 'Trolley Movement',
            children: [
              _ThreeButtonRow(
                leftLabel: 'LEFT',
                rightLabel: 'RIGHT',
                executing: _executing,
                onLeft: () => _sendCommand('trolley_forward', steps: _steps),
                onStop: () => _sendCommand('stop'),
                onRight: () => _sendCommand('trolley_backward', steps: _steps),
              ),
            ],
          ),
          const SizedBox(height: 16),

          _ControlSection(
            title: 'Hoist',
            children: [
              if (_hoistPosition != null) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppPalette.warning.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.height_rounded, size: 13, color: AppPalette.warning),
                          const SizedBox(width: 5),
                          Text(
                            'Hoist position: $_hoistPosition steps',
                            style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w600, color: AppPalette.warning,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              _ThreeButtonRow(
                leftLabel: 'DOWN',
                rightLabel: 'UP',
                executing: _executing,
                onLeft: () => _sendCommand('hoist_down', steps: _steps),
                onStop: () => _sendCommand('stop'),
                onRight: () => _sendCommand('hoist_up', steps: _steps),
                leftIcon: Icons.arrow_downward_rounded,
                rightIcon: Icons.arrow_upward_rounded,
              ),
            ],
          ),
          const SizedBox(height: 16),

          _ControlSection(
            title: 'Electromagnet',
            children: [
              Row(
                children: [
                  Expanded(
                    child: _MagnetButton(
                      label: 'DETACH',
                      icon: Icons.cancel_outlined,
                      active: !_magnetOn,
                      executing: _executing,
                      onTap: () => _sendCommand('magnet_off'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MagnetButton(
                      label: 'ATTACH',
                      icon: Icons.check_circle_outline,
                      active: _magnetOn,
                      executing: _executing,
                      onTap: () => _sendCommand('magnet_on'),
                      activeColor: AppPalette.success,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  'Magnet: ${_magnetOn ? "ATTACHED" : "DETACHED"}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _magnetOn ? AppPalette.success : (isDark ? Colors.white38 : Colors.grey[500]),
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
          if (_lastError != null) ...[
            const SizedBox(height: 12),
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
          const SizedBox(height: 16),

          _SliderRow(
            label: 'Steps',
            value: _speed,
            min: 50,
            max: 2000,
            divisions: 39,
            suffix: '$_steps',
            onChanged: (v) => setState(() => _speed = v),
          ),
          _SliderRow(
            label: 'Repeat',
            value: _duration,
            min: 1,
            max: 10,
            divisions: 9,
            suffix: '${_duration.toInt()}x',
            onChanged: (v) => setState(() => _duration = v),
          ),
        ],
      ),
    );
  }
}

class _ControlSection extends StatelessWidget {
  const _ControlSection({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white54 : Colors.grey[600],
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }
}

class _ThreeButtonRow extends StatelessWidget {
  const _ThreeButtonRow({
    required this.leftLabel,
    required this.rightLabel,
    required this.executing,
    required this.onLeft,
    required this.onStop,
    required this.onRight,
    this.leftIcon,
    this.rightIcon,
  });

  final String leftLabel;
  final String rightLabel;
  final bool executing;
  final VoidCallback onLeft;
  final VoidCallback onStop;
  final VoidCallback onRight;
  final IconData? leftIcon;
  final IconData? rightIcon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ActionBtn(
            label: leftLabel,
            icon: leftIcon ?? Icons.arrow_back_rounded,
            color: AppPalette.accent,
            enabled: !executing,
            onTap: onLeft,
          ),
        ),
        const SizedBox(width: 6),
        _ActionBtn(
          label: 'STOP',
          icon: Icons.stop_rounded,
          color: AppPalette.coral,
          enabled: !executing,
          onTap: onStop,
          filled: true,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _ActionBtn(
            label: rightLabel,
            icon: rightIcon ?? Icons.arrow_forward_rounded,
            color: AppPalette.accent,
            enabled: !executing,
            onTap: onRight,
          ),
        ),
      ],
    );
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.enabled,
    required this.onTap,
    this.filled = false,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: filled ? color.withValues(alpha: 0.18) : color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: filled ? 0.4 : 0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: enabled ? color : Colors.grey),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: enabled ? color : Colors.grey,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MagnetButton extends StatelessWidget {
  const _MagnetButton({
    required this.label,
    required this.icon,
    required this.active,
    required this.executing,
    required this.onTap,
    this.activeColor,
  });

  final String label;
  final IconData icon;
  final bool active;
  final bool executing;
  final VoidCallback onTap;
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    final color = active ? (activeColor ?? AppPalette.success) : Colors.grey;

    return GestureDetector(
      onTap: executing ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: executing ? Colors.grey : color),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: executing ? Colors.grey : color,
                letterSpacing: 0.8,
              ),
            ),
          ],
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
