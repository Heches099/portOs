import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/realtime_telemetry.dart';
import '../providers/machine_selection_controller.dart';
import '../theme/industrial_theme.dart';

/// Fleet roster for the Live Operations workspace.
///
/// Lists every AGV and automated crane with a live status dot, state label,
/// battery/sensor tiles and mission line. Selecting a machine updates the
/// [MachineSelectionController], which drives the camera, control panel,
/// telemetry bar and AI overlay together.
class MachineSidebar extends StatefulWidget {
  const MachineSidebar({super.key, this.horizontal = false});

  /// When true the roster is rendered as a horizontal chip rail (used on
  /// tablet widths instead of the fixed vertical column).
  final bool horizontal;

  @override
  State<MachineSidebar> createState() => _MachineSidebarState();
}

class _MachineSidebarState extends State<MachineSidebar> {
  @override
  Widget build(BuildContext context) {
    final controller = context.watch<MachineSelectionController>();

    if (widget.horizontal) {
      return _HorizontalRoster(controller: controller);
    }

    return Container(
      width: 248,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [IndustrialTheme.panelDeep, IndustrialTheme.panel],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: IndustrialTheme.border),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0A1524).withValues(alpha: 0.9),
            blurRadius: 22,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SigLine(),
          _SidebarHeader(controller: controller),
          const Divider(color: IndustrialTheme.border, height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 10),
              children: [
                _FleetSection(
                  title: 'AGV FLEET',
                  machines: controller.fleet
                      .where((m) => m.kind == MachineKind.agv)
                      .toList(),
                  controller: controller,
                ),
                const SizedBox(height: 12),
                _FleetSection(
                  title: 'AUTOMATED CRANES',
                  machines: controller.fleet
                      .where((m) => m.kind == MachineKind.crane)
                      .toList(),
                  controller: controller,
                ),
              ],
            ),
          ),
          const Divider(color: IndustrialTheme.border, height: 1),
          _SidebarFooter(controller: controller),
        ],
      ),
    );
  }
}

/// Top accent hairline that glows cyan (live gateway) or idle.
class _SigLine extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final controller = context.watch<MachineSelectionController>();
    final live = controller.gatewayConnection == MachineConnectionState.online;
    final color = live ? IndustrialTheme.control : IndustrialTheme.idle;
    return Container(
      height: 2,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.05),
            color,
            color.withValues(alpha: 0.05),
          ],
        ),
      ),
    );
  }
}

class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader({required this.controller});

  final MachineSelectionController controller;

  @override
  Widget build(BuildContext context) {
    final selected = controller.selectedMachine;
    final live = controller.gatewayConnection == MachineConnectionState.online;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _BrandTile(live: live),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'PortOS',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        letterSpacing: 1.2,
                        shadows: [
                          Shadow(
                            color: Color(0xFF38BDF8),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 1),
                    Row(
                      children: [
                        Text(
                          'LIVE OPERATIONS',
                          style: TextStyle(
                            color: IndustrialTheme.textMuted,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.4,
                          ),
                        ),
                        SizedBox(width: 6),
                        SizedBox(
                          width: 4,
                          height: 4,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: IndustrialTheme.ready,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (live) const _SigBars(),
            ],
          ),
          const SizedBox(height: 12),
          _SelectedChip(machine: selected, controller: controller),
        ],
      ),
    );
  }
}

/// Signature app tile with a stacked gradient + edge highlight.
class _BrandTile extends StatelessWidget {
  const _BrandTile({required this.live});

  final bool live;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(11),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2563EB), Color(0xFF38BDF8)],
        ),
        boxShadow: [
          BoxShadow(
            color: (live ? IndustrialTheme.control : IndustrialTheme.idle)
                .withValues(alpha: 0.45),
            blurRadius: 14,
            offset: const Offset(0, 0),
          ),
        ],
      ),
      child: const Icon(Icons.blur_on_rounded, color: Colors.white, size: 21),
    );
  }
}

/// Compact live-link coded chip for the currently selected machine.
class _SelectedChip extends StatelessWidget {
  const _SelectedChip({required this.machine, required this.controller});

  final OperationalMachine machine;
  final MachineSelectionController controller;

  @override
  Widget build(BuildContext context) {
    final accent = machine.accent;
    final snapshot = controller.snapshotFor(machine.id);
    final linked = controller.connectedFor(machine.id);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            accent.withValues(alpha: 0.16),
            accent.withValues(alpha: 0.05),
          ],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.38)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Row(
          children: [
            _AccentIcon(icon: machine.icon, color: accent, size: 30),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    machine.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    machine.kicker,
                    style: const TextStyle(
                      color: IndustrialTheme.textMuted,
                      fontSize: 9,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            if (linked) ...[
              _StatusPill(
                text: 'LINKED',
                color: IndustrialTheme.ready,
                icon: Icons.link_rounded,
              ),
              const SizedBox(width: 6),
            ],
            if (snapshot != null) ...[
              if (linked) const SizedBox(width: 6),
              Text(
                snapshot.battery == null
                    ? '--'
                    : '${snapshot.battery!.round()}%',
                style: const TextStyle(
                  color: IndustrialTheme.textSecondary,
                  fontFamily: IndustrialTheme.mono,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FleetSection extends StatelessWidget {
  const _FleetSection({
    required this.title,
    required this.machines,
    required this.controller,
  });

  final String title;
  final List<OperationalMachine> machines;
  final MachineSelectionController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: IndustrialTheme.textMuted,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: IndustrialTheme.panelAlt,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: IndustrialTheme.border),
                ),
                child: Text(
                  '${machines.length} UNIT${machines.length == 1 ? '' : 'S'}',
                  style: const TextStyle(
                    color: IndustrialTheme.textMuted,
                    fontSize: 7,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
        ),
        ...machines.map(
          (machine) => _MachineCard(
            key: PageStorageKey<String>(machine.id),
            machine: machine,
            controller: controller,
          ),
        ),
      ],
    );
  }
}

class _MachineCard extends StatelessWidget {
  const _MachineCard({
    super.key,
    required this.machine,
    required this.controller,
  });

  final OperationalMachine machine;
  final MachineSelectionController controller;

  @override
  Widget build(BuildContext context) {
    final selected = controller.isSelected(machine.id);
    final accent = machine.accent;
    final stateLabel = controller.stateLabelFor(machine.id);
    final stateColor = controller.stateColorFor(machine.id);
    final connection = controller.connectionLabelFor(machine.id);
    final stale = controller.isTelemetryStaleFor(machine.id);
    final mission = controller.missionFor(machine.id);
    final estop = controller.estopLabelFor(machine.id);
    final snapshot = controller.snapshotFor(machine.id);
    final temp = snapshot?.temperature;
    final speed = snapshot?.speed;
    final online = connection == 'ONLINE';
    final age = controller.telemetryAgeFor(machine.id);

    final connectionColor = switch (connection) {
      'ONLINE' => IndustrialTheme.ready,
      'CONNECTING' => IndustrialTheme.warn,
      'DEGRADED' => IndustrialTheme.warn,
      _ => IndustrialTheme.danger,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: InkWell(
        onTap: () => controller.select(machine.id),
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: selected
                  ? [
                      accent.withValues(alpha: 0.18),
                      accent.withValues(alpha: 0.04),
                    ]
                  : const [IndustrialTheme.panelAlt, IndustrialTheme.panelDeep],
            ),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.5)
                  : IndustrialTheme.border,
              width: selected ? 1.2 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.25),
                      blurRadius: 12,
                      spreadRadius: 0.5,
                    ),
                  ]
                : null,
          ),
          child: Stack(
            children: [
              if (selected)
                Positioned(
                  left: 0,
                  top: 8,
                  bottom: 8,
                  child: Container(
                    width: 3,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [accent, accent.withValues(alpha: 0.1)],
                      ),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        _PulseDot(
                          color: stale
                              ? IndustrialTheme.danger
                              : online
                                  ? stateColor
                                  : connectionColor,
                          pulsing: online && !stale && stateLabel == 'MOVING',
                        ),
                        const SizedBox(width: 9),
                        _AccentIcon(icon: machine.icon, color: accent, size: 28),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                machine.name,
                                style: TextStyle(
                                  color: selected
                                      ? Colors.white
                                      : IndustrialTheme.textSecondary,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                machine.kicker,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: IndustrialTheme.textMuted,
                                  fontSize: 9,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _StatusPill(
                              text: connection,
                              color: connectionColor,
                            ),
                            if (age != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  _ageText(age),
                                  style: const TextStyle(
                                    color: IndustrialTheme.textMuted,
                                    fontFamily: IndustrialTheme.mono,
                                    fontSize: 8,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 9),
                    Row(
                      children: [
                        _BatteryBar(
                          percent: snapshot?.battery,
                          label: 'BATT',
                        ),
                        const SizedBox(width: 10),
                        _StatCell(
                          label: 'TEMP',
                          value: temp == null ? '--' : '${temp.round()}°',
                          color: temp != null && temp > 55
                              ? IndustrialTheme.warn
                              : IndustrialTheme.textSecondary,
                        ),
                        const SizedBox(width: 10),
                        _StatCell(
                          label: 'SPD',
                          value: speed == null
                              ? '--'
                              : '${speed.toStringAsFixed(1)}m/s',
                          color: IndustrialTheme.textSecondary,
                        ),
                        const Spacer(),
                        _StateTag(text: stateLabel, color: stateColor),
                      ],
                    ),
                    if (estop != null) ...[
                      const SizedBox(height: 8),
                      _EstopBanner(label: estop),
                    ] else if (mission != '--') ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.route_outlined,
                            size: 10,
                            color: IndustrialTheme.textMuted,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              mission,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: IndustrialTheme.textMuted,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _ageText(Duration age) {
    final seconds = age.inMilliseconds / 1000;
    if (seconds < 60) return '${seconds.toStringAsFixed(1)}s';
    return '${age.inMinutes}m';
  }
}

/// Pulsing/static status beacon with a soft glow halo.
class _PulseDot extends StatefulWidget {
  const _PulseDot({
    required this.color,
    this.pulsing = false,
  });

  final Color color;
  final bool pulsing;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    if (widget.pulsing) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_PulseDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulsing && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.pulsing && _controller.isAnimating) {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const dotSize = 9.0;
    final pad = dotSize * 1.7;
    return SizedBox(
      width: pad,
      height: pad,
      child: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value;
            return Container(
              width: dotSize,
              height: dotSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withValues(alpha: 0.18 + 0.55 * t),
                boxShadow: [
                  BoxShadow(
                    color: widget.color.withValues(alpha: 0.35 + 0.45 * t),
                    blurRadius: 6 + 4 * t,
                    spreadRadius: t * 2,
                  ),
                ],
              ),
              child: Center(
                child: Container(
                  width: dotSize * 0.42,
                  height: dotSize * 0.42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Declarative mini equalizer shown when the gateway is live.
class _SigBars extends StatefulWidget {
  const _SigBars();

  @override
  State<_SigBars> createState() => _SigBarsState();
}

class _SigBarsState extends State<_SigBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 26,
      height: 16,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(3, (i) {
              final t = math.sin((_controller.value * math.pi * 2) + i * 1.1);
              final h = 4 + (7 * (t * 0.5 + 0.5)).roundToDouble();
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.5),
                child: Container(
                  width: 3,
                  height: h,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        IndustrialTheme.control.withValues(alpha: 0.25),
                        IndustrialTheme.control,
                      ],
                    ),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

/// Accent-tinted rounded icon tile.
class _AccentIcon extends StatelessWidget {
  const _AccentIcon({
    required this.icon,
    required this.color,
    required this.size,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0.06)],
        ),
        borderRadius: BorderRadius.circular(size * 0.3),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Icon(icon, size: size * 0.56, color: color),
    );
  }
}

/// Small glowing status pill (ONLINE / CONNECTING / OFFLINE / LINKED).
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.text, required this.color, this.icon});

  final String text;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.18),
            blurRadius: 6,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 9, color: color),
            const SizedBox(width: 3),
          ],
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 8,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.7,
            ),
          ),
        ],
      ),
    );
  }
}

/// State tag (MOVING / IDLE / E-STOP / ...) rendered power-light style.
class _StateTag extends StatelessWidget {
  const _StateTag({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 8,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

/// Minimal battery meter with color-coded level and live machine value.
class _BatteryBar extends StatelessWidget {
  const _BatteryBar({required this.percent, required this.label});

  final double? percent;
  final String label;

  @override
  Widget build(BuildContext context) {
    final value = percent;
    final color = value == null
        ? IndustrialTheme.idle
        : value < 20
            ? IndustrialTheme.danger
            : value < 40
                ? IndustrialTheme.warn
                : IndustrialTheme.ready;
    return SizedBox(
      width: 82,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: IndustrialTheme.textMuted,
                  fontSize: 7,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              Text(
                value == null
                    ? '--'
                    : '${value.round()}%',
                style: TextStyle(
                  color: color,
                  fontFamily: IndustrialTheme.mono,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Container(
              height: 4,
              color: IndustrialTheme.panelDeep,
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: value == null ? 0 : (value / 100).clamp(0.0, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    gradient: LinearGradient(
                      colors: [color.withValues(alpha: 0.6), color],
                    ),
                    boxShadow: [
                      BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 4),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact sensor cell (monospace value under a tiny label).
class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: IndustrialTheme.textMuted,
            fontSize: 7,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontFamily: IndustrialTheme.mono,
            fontSize: 9,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

/// Full-width red banner drawn as soon as a machine enters E-STOP.
class _EstopBanner extends StatelessWidget {
  const _EstopBanner({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: IndustrialTheme.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: IndustrialTheme.danger.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: IndustrialTheme.danger.withValues(alpha: 0.25),
            blurRadius: 10,
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(
            Icons.gpp_bad_rounded,
            size: 11,
            color: IndustrialTheme.danger,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: IndustrialTheme.danger,
              fontSize: 8,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarFooter extends StatelessWidget {
  const _SidebarFooter({required this.controller});

  final MachineSelectionController controller;

  @override
  Widget build(BuildContext context) {
    final reachable = controller.backendReachable;
    final color = reachable
        ? (controller.selectedLinked
            ? IndustrialTheme.ready
            : IndustrialTheme.warn)
        : IndustrialTheme.danger;
    final label = controller.statusLabel;
    final simulated = controller.simulatedMode;
    final onlineCount =
        controller.fleet.where((m) => controller.connectedFor(m.id)).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _RoundedDot(
                size: 9,
                color: simulated ? IndustrialTheme.warn : IndustrialTheme.ready,
                glow: true,
              ),
              const SizedBox(width: 7),
              const Text(
                'SYSTEM MODE',
                style: TextStyle(
                  color: IndustrialTheme.textMuted,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              _FooterPill(
                text: simulated ? 'SIMULATION' : 'REAL HARDWARE',
                color: simulated ? IndustrialTheme.warn : IndustrialTheme.ready,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const _RoundedDot(size: 9, color: IndustrialTheme.control, glow: true),
              const SizedBox(width: 7),
              const Text(
                'GATEWAY',
                style: TextStyle(
                  color: IndustrialTheme.textMuted,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              _FooterPill(text: label, color: color),
            ],
          ),
          const SizedBox(height: 9),
          Container(
            height: 1,
            color: IndustrialTheme.border,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'OPERATIONAL $onlineCount/6',
                style: const TextStyle(
                  color: IndustrialTheme.textMuted,
                  fontFamily: IndustrialTheme.mono,
                  fontSize: 8,
                  letterSpacing: 0.6,
                ),
              ),
              const Spacer(),
              const Text(
                'v0.4 · SCADA',
                style: TextStyle(
                  color: IndustrialTheme.textMuted,
                  fontFamily: IndustrialTheme.mono,
                  fontSize: 8,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoundedDot extends StatelessWidget {
  const _RoundedDot({
    required this.size,
    required this.color,
    this.glow = false,
  });

  final double size;
  final Color color;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: glow
            ? [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6)]
            : null,
      ),
    );
  }
}

class _FooterPill extends StatelessWidget {
  const _FooterPill({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.15), blurRadius: 6),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '●',
            style: TextStyle(color: color, fontSize: 7),
          ),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.7,
            ),
          ),
        ],
      ),
    );
  }
}

class _HorizontalRoster extends StatelessWidget {
  const _HorizontalRoster({required this.controller});

  final MachineSelectionController controller;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: controller.fleet.map((machine) {
          final selected = controller.isSelected(machine.id);
          final stateColor = controller.stateColorFor(machine.id);
          final stateLabel = controller.stateLabelFor(machine.id);
          final connection = controller.connectionLabelFor(machine.id);
          final connectionColor = connection == 'ONLINE'
              ? IndustrialTheme.ready
              : connection == 'CONNECTING'
                  ? IndustrialTheme.warn
                  : IndustrialTheme.danger;
          final estop = controller.estopLabelFor(machine.id);
          final accent = machine.accent;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              onTap: () => controller.select(machine.id),
              borderRadius: BorderRadius.circular(12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: selected
                        ? [
                            accent.withValues(alpha: 0.2),
                            accent.withValues(alpha: 0.05),
                          ]
                        : const [IndustrialTheme.panel, IndustrialTheme.panelAlt],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected
                        ? accent.withValues(alpha: 0.55)
                        : IndustrialTheme.border,
                  ),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.25),
                            blurRadius: 10,
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (estop != null)
                      const _PulseDot(
                          color: IndustrialTheme.danger, pulsing: true)
                    else
                      _PulseDot(
                        color: stateColor,
                        pulsing: connection == 'ONLINE' &&
                            stateLabel == 'MOVING',
                      ),
                    const SizedBox(width: 8),
                    _AccentIcon(icon: machine.icon, color: accent, size: 26),
                    const SizedBox(width: 8),
                    Text(
                      machine.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(width: 9),
                    _StateTag(text: stateLabel, color: stateColor),
                    const SizedBox(width: 6),
                    Text(
                      connection,
                      style: TextStyle(
                        color: connectionColor,
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(growable: false),
      ),
    );
  }
}