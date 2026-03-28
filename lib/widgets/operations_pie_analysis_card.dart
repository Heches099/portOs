import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/terminal_stats.dart';
import '../providers/operations_repository.dart';
import '../providers/theme_provider.dart';
import 'glass_card.dart';

enum _AnalysisWindow { minutes, hourly, daily, weekly, monthly }

class OperationsPieAnalysisCard extends StatefulWidget {
  const OperationsPieAnalysisCard({
    super.key,
    required this.stats,
    required this.operations,
    required this.noticeCount,
  });

  final TerminalStats stats;
  final OperationsRepository operations;
  final int noticeCount;

  @override
  State<OperationsPieAnalysisCard> createState() =>
      _OperationsPieAnalysisCardState();
}

class _OperationsPieAnalysisCardState extends State<OperationsPieAnalysisCard> {
  _AnalysisWindow _window = _AnalysisWindow.hourly;
  int _activeSliceIndex = -1;

  @override
  Widget build(BuildContext context) {
    final snapshot = _buildSnapshot(
      window: _window,
      stats: widget.stats,
      operations: widget.operations,
      noticeCount: widget.noticeCount,
    );
    final total = snapshot.slices.fold<double>(
      0,
      (sum, slice) => sum + slice.value,
    );
    final highlightedSlice =
        _activeSliceIndex >= 0 && _activeSliceIndex < snapshot.slices.length
            ? snapshot.slices[_activeSliceIndex]
            : snapshot.primarySlice;

    return GlassCard(
      padding: const EdgeInsets.all(26),
      color: const Color(0xCC08111F),
      borderRadius: 34,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'FILTERED PIE ANALYSIS',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Operational share by time window so the pie chart can flip between minutes, hours, days, and monthly analysis.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.white70,
                            height: 1.45,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              _FilterSummaryChip(
                label: snapshot.windowLabel,
                value: _compactNumber(total),
                accent: snapshot.primarySlice.color,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _AnalysisWindow.values
                .map(
                  (window) => _AnalysisFilterChip(
                    label: _analysisWindowLabel(window),
                    selected: _window == window,
                    onTap: () {
                      setState(() {
                        _window = window;
                        _activeSliceIndex = -1;
                      });
                    },
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: 22),
          LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 980;

              if (isCompact) {
                return Column(
                  children: [
                    _PiePanel(
                      snapshot: snapshot,
                      total: total,
                      activeSliceIndex: _activeSliceIndex,
                      onSliceChanged: (index) {
                        setState(() => _activeSliceIndex = index);
                      },
                    ),
                    const SizedBox(height: 20),
                    _AnalysisBreakdown(
                      snapshot: snapshot,
                      total: total,
                      highlightedSlice: highlightedSlice,
                    ),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 5,
                    child: _PiePanel(
                      snapshot: snapshot,
                      total: total,
                      activeSliceIndex: _activeSliceIndex,
                      onSliceChanged: (index) {
                        setState(() => _activeSliceIndex = index);
                      },
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    flex: 5,
                    child: _AnalysisBreakdown(
                      snapshot: snapshot,
                      total: total,
                      highlightedSlice: highlightedSlice,
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
}

class _PiePanel extends StatelessWidget {
  const _PiePanel({
    required this.snapshot,
    required this.total,
    required this.activeSliceIndex,
    required this.onSliceChanged,
  });

  final _AnalysisSnapshot snapshot;
  final double total;
  final int activeSliceIndex;
  final ValueChanged<int> onSliceChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        color: Colors.white.withValues(alpha: 0.04),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: SizedBox(
        height: 310,
        child: Stack(
          children: [
            PieChart(
              PieChartData(
                centerSpaceRadius: 72,
                sectionsSpace: 4,
                pieTouchData: PieTouchData(
                  touchCallback: (event, response) {
                    if (!event.isInterestedForInteractions ||
                        response == null ||
                        response.touchedSection == null) {
                      onSliceChanged(-1);
                      return;
                    }
                    onSliceChanged(
                      response.touchedSection!.touchedSectionIndex,
                    );
                  },
                ),
                sections: [
                  for (var index = 0; index < snapshot.slices.length; index++)
                    PieChartSectionData(
                      value: snapshot.slices[index].value,
                      color: snapshot.slices[index].color,
                      radius: activeSliceIndex == index ? 92 : 82,
                      title:
                          '${_slicePercentage(snapshot.slices[index].value, total)}%',
                      titleStyle:
                          Theme.of(context).textTheme.labelLarge?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                    ),
                ],
              ),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    snapshot.windowLabel.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _compactNumber(total),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'tracked events',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white60,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnalysisBreakdown extends StatelessWidget {
  const _AnalysisBreakdown({
    required this.snapshot,
    required this.total,
    required this.highlightedSlice,
  });

  final _AnalysisSnapshot snapshot;
  final double total;
  final _AnalysisSlice highlightedSlice;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            color: Colors.white.withValues(alpha: 0.04),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'BREAKDOWN',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 16),
              for (final slice in snapshot.slices) ...[
                _AnalysisLegendRow(
                  slice: slice,
                  total: total,
                ),
                if (slice != snapshot.slices.last) const SizedBox(height: 14),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _AnalysisInsightCard(
              label: 'Dominant Slice',
              value: highlightedSlice.label,
              accent: highlightedSlice.color,
            ),
            _AnalysisInsightCard(
              label: 'Peak Share',
              value:
                  '${_slicePercentage(highlightedSlice.value, total)}% of ${snapshot.windowLabel.toLowerCase()} flow',
              accent: snapshot.primarySlice.color,
            ),
            _AnalysisInsightCard(
              label: 'Trend Note',
              value: snapshot.insight,
              accent: const Color(0xFF2DD4BF),
            ),
          ],
        ),
      ],
    );
  }
}

class _AnalysisLegendRow extends StatelessWidget {
  const _AnalysisLegendRow({
    required this.slice,
    required this.total,
  });

  final _AnalysisSlice slice;
  final double total;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: slice.color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: slice.color.withValues(alpha: 0.32),
                blurRadius: 12,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                slice.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                slice.detail,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _compactNumber(slice.value),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              '${_slicePercentage(slice.value, total)}%',
              style: TextStyle(
                color: slice.color,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AnalysisInsightCard extends StatelessWidget {
  const _AnalysisInsightCard({
    required this.label,
    required this.value,
    required this.accent,
  });

  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 188,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: Colors.white.withValues(alpha: 0.04),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: accent == const Color(0xFF2DD4BF)
                        ? Colors.white
                        : accent,
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnalysisFilterChip extends StatelessWidget {
  const _AnalysisFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: selected
              ? const LinearGradient(
                  colors: [Color(0xFF2563EB), Color(0xFF38BDF8)],
                )
              : null,
          color: selected ? null : Colors.white.withValues(alpha: 0.05),
          border: Border.all(
            color: selected
                ? Colors.white.withValues(alpha: 0.16)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: selected ? 1 : 0.72),
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _FilterSummaryChip extends StatelessWidget {
  const _FilterSummaryChip({
    required this.label,
    required this.value,
    required this.accent,
  });

  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: accent.withValues(alpha: 0.12),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: accent,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalysisSnapshot {
  const _AnalysisSnapshot({
    required this.windowLabel,
    required this.slices,
    required this.insight,
  });

  final String windowLabel;
  final List<_AnalysisSlice> slices;
  final String insight;

  _AnalysisSlice get primarySlice => slices.reduce(
        (current, next) => current.value >= next.value ? current : next,
      );
}

class _AnalysisSlice {
  const _AnalysisSlice({
    required this.label,
    required this.value,
    required this.detail,
    required this.color,
  });

  final String label;
  final double value;
  final String detail;
  final Color color;
}

class _AnalysisSliceSeed {
  const _AnalysisSliceSeed({
    required this.label,
    required this.baseValue,
    required this.detail,
    required this.color,
    required this.multipliers,
  });

  final String label;
  final double baseValue;
  final String detail;
  final Color color;
  final Map<_AnalysisWindow, double> multipliers;

  _AnalysisSlice forWindow(_AnalysisWindow window) {
    final multiplier = multipliers[window] ?? 1;

    return _AnalysisSlice(
      label: label,
      value: baseValue * multiplier,
      detail: detail,
      color: color,
    );
  }
}

_AnalysisSnapshot _buildSnapshot({
  required _AnalysisWindow window,
  required TerminalStats stats,
  required OperationsRepository operations,
  required int noticeCount,
}) {
  final queued = operations.deliveriesByStatus('Queued').length.toDouble();
  final inProgress =
      operations.deliveriesByStatus('In Progress').length.toDouble();
  final completed = operations.completedDeliveries.toDouble();
  final alerts = math.max(1, operations.activeAlerts + noticeCount).toDouble();
  final agvCount = operations.agvs.length.toDouble();
  final craneCount = operations.cranes.length.toDouble();

  final sliceSeeds = [
    _AnalysisSliceSeed(
      label: 'Quay Lift',
      baseValue: stats.activeCranes * 4.2 + craneCount * 8,
      detail: 'crane picks and berth cycles',
      color: AppPalette.accent,
      multipliers: const {
        _AnalysisWindow.minutes: 1.0,
        _AnalysisWindow.hourly: 5.8,
        _AnalysisWindow.daily: 22.0,
        _AnalysisWindow.weekly: 38.9,
        _AnalysisWindow.monthly: 610.0,
      },
    ),
    _AnalysisSliceSeed(
      label: 'Yard Moves',
      baseValue:
          agvCount * 10 + inProgress * 7 + stats.activeGroundSpots * 0.05,
      detail: 'AGV relocation and yard routing',
      color: AppPalette.sky,
      multipliers: const {
        _AnalysisWindow.minutes: 0.9,
        _AnalysisWindow.hourly: 6.4,
        _AnalysisWindow.daily: 25.0,
        _AnalysisWindow.weekly: 90.7,
        _AnalysisWindow.monthly: 690.0,
      },
    ),
    _AnalysisSliceSeed(
      label: 'Gate Flow',
      baseValue: queued * 9 + completed * 11 + stats.teuCounter * 0.004,
      detail: 'turnaround and gate dispatch',
      color: AppPalette.mint,
      multipliers: const {
        _AnalysisWindow.minutes: 0.8,
        _AnalysisWindow.hourly: 5.2,
        _AnalysisWindow.daily: 21.0,
        _AnalysisWindow.weekly: 700.0,
        _AnalysisWindow.monthly: 570.0,
      },
    ),
    _AnalysisSliceSeed(
      label: 'Exceptions',
      baseValue: alerts * 5 + queued * 1.5,
      detail: 'alerts, holds, and exception checks',
      color: AppPalette.coral,
      multipliers: const {
        _AnalysisWindow.minutes: 0.65,
        _AnalysisWindow.hourly: 2.8,
        _AnalysisWindow.daily: 8.5,
        _AnalysisWindow.weekly: 0.78,
        _AnalysisWindow.monthly: 210.0,
      },
    ),
    _AnalysisSliceSeed(
      label: 'Cautions',
      baseValue: alerts * 8 + completed * 22 + queued * 3.7,
      detail: 'elevated risk needing operator review',
      color: AppPalette.navy,
      multipliers: const {
        _AnalysisWindow.minutes: 0.45,
        _AnalysisWindow.hourly: 2.2,
        _AnalysisWindow.daily: 7.2,
        _AnalysisWindow.weekly: 0.62,
        _AnalysisWindow.monthly: 175.0,
      },
    ),
  ];

  final windowLabel = _analysisWindowLabel(window);
  final scaledSlices = sliceSeeds
      .map((slice) => slice.forWindow(window))
      .toList(growable: false);

  final insight = switch (window) {
    _AnalysisWindow.minutes =>
      'Minute view is emphasizing the most immediate pressure points around cranes and gate turns.',
    _AnalysisWindow.hourly =>
      'Hourly analysis exposes the true balance between quay lifting, yard motion, and exception handling.',
    _AnalysisWindow.daily =>
      'Daily analysis highlights how AGV routing and berth work start to dominate over isolated alerts.',
    _AnalysisWindow.weekly =>
      'Weekly analysis smooths short spikes and shows the long-run operational mix across terminal systems.',
    _AnalysisWindow.monthly =>
      'Monthly analysis smooths short spikes and shows the long-run operational mix across terminal systems.',
  };

  return _AnalysisSnapshot(
    windowLabel: windowLabel,
    slices: scaledSlices,
    insight: insight,
  );
}

String _analysisWindowLabel(_AnalysisWindow window) {
  switch (window) {
    case _AnalysisWindow.minutes:
      return 'Minutes';
    case _AnalysisWindow.hourly:
      return 'Hourly';
    case _AnalysisWindow.daily:
      return 'Daily';
    case _AnalysisWindow.weekly:
      return 'Weekly';
    case _AnalysisWindow.monthly:
      return 'Monthly';
  }
}

int _slicePercentage(double value, double total) {
  if (total <= 0) {
    return 0;
  }
  return ((value / total) * 100).round();
}

String _compactNumber(double value) {
  if (value >= 1000000) {
    return '${(value / 1000000).toStringAsFixed(1)}M';
  }
  if (value >= 1000) {
    return '${(value / 1000).toStringAsFixed(1)}K';
  }
  return value.toStringAsFixed(0);
}
