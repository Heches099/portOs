import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/automation_hub_provider.dart';
import '../providers/notification_provider.dart';
import '../providers/operations_repository.dart';
import '../providers/terminal_state_provider.dart';
import '../utils/extensions.dart';

class AlertCenterSheet extends StatelessWidget {
  const AlertCenterSheet({
    super.key,
    required this.terminal,
    required this.operations,
    required this.notifications,
  });

  final TerminalStateProvider terminal;
  final OperationsRepository operations;
  final NotificationProvider notifications;

  @override
  Widget build(BuildContext context) {
    final hub = context.watch<AutomationHubProvider>();
    final diagnostics = hub.diagnostics;
    final sensorAlerts = operations.sensorReadings
        .where((sensor) => !sensor.isInNormalRange)
        .toList(growable: false);
    final feedAlerts = operations.cameraFeeds
        .where((feed) => feed.alert != null || !feed.isOnline)
        .toList(growable: false);
    final queuedDeliveries = operations.deliveriesByStatus('Queued').length;
    final inProgressDeliveries =
        operations.deliveriesByStatus('In Progress').length;
    final criticalDeliveries = operations.deliveries
        .where((delivery) => delivery.priority == 'Critical')
        .length;
    final criticalNotices = notifications.items
        .where((item) => item.severity == NotificationSeverity.critical)
        .length;

    final totalAlerts =
        sensorAlerts.length + feedAlerts.length + notifications.items.length;
    final attentionBars = [
      _BarDatum('Sensors', sensorAlerts.length.toDouble(),
          const Color(0xFFFB7185)),
      _BarDatum('Video', feedAlerts.length.toDouble(), const Color(0xFFF59E0B)),
      _BarDatum('Notices', notifications.items.length.toDouble(),
          const Color(0xFF60A5FA)),
      _BarDatum(
        'Critical',
        (criticalDeliveries + criticalNotices).toDouble(),
        const Color(0xFF8B5CF6),
      ),
    ];
    final flowBars = [
      _BarDatum(
        'Queued',
        queuedDeliveries.toDouble(),
        const Color(0xFFF59E0B),
      ),
      _BarDatum(
        'Active',
        inProgressDeliveries.toDouble(),
        const Color(0xFF2DD4BF),
      ),
      _BarDatum(
        'Done',
        operations.completedDeliveries.toDouble(),
        const Color(0xFF60A5FA),
      ),
      _BarDatum(
        'Cranes',
        operations.cranes.length.toDouble(),
        const Color(0xFF94A3B8),
      ),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            color: const Color(0xFF07111F),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.32),
                blurRadius: 36,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 54,
                    height: 5,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: Colors.white.withValues(alpha: 0.18),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ALERT CENTER',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.1,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Hardware alarms, operator notices, and device health in one repair-ready view.',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: Colors.white70,
                                  height: 1.45,
                                ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    IconButton.filledTonal(
                      onPressed: context
                          .read<AutomationHubProvider>()
                          .refreshDiagnostics,
                      icon: hub.isRefreshingDiagnostics
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync_rounded),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.08),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: [
                    _SummaryTile(
                      label: 'Total attention items',
                      value: '$totalAlerts',
                      accent: const Color(0xFFFB7185),
                    ),
                    _SummaryTile(
                      label: 'Network',
                      value: diagnostics.networkStatus,
                      accent: const Color(0xFF60A5FA),
                    ),
                    _SummaryTile(
                      label: 'Battery',
                      value: diagnostics.batteryLabel,
                      accent: const Color(0xFFF59E0B),
                    ),
                    _SummaryTile(
                      label: 'Backend sync',
                      value: _syncStateLabel(terminal.syncState),
                      accent: _syncStateColor(terminal.syncState),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 980;
                    final attentionCard = _BarInsightCard(
                      title: 'Attention load',
                      subtitle:
                          'Where humans are most likely to focus first in the current shift window.',
                      bars: attentionBars,
                      explanation: _attentionExplanation(
                        sensorAlerts: sensorAlerts.length,
                        feedAlerts: feedAlerts.length,
                        noticeCount: notifications.items.length,
                        criticalCount: criticalDeliveries + criticalNotices,
                      ),
                    );
                    final flowCard = _BarInsightCard(
                      title: 'Flow pressure',
                      subtitle:
                          'Backlog, execution, and finished work in one view for fast handoff decisions.',
                      bars: flowBars,
                      explanation: _flowExplanation(
                        queuedDeliveries: queuedDeliveries,
                        inProgressDeliveries: inProgressDeliveries,
                        completedDeliveries: operations.completedDeliveries,
                        craneCount: operations.cranes.length,
                      ),
                    );

                    if (compact) {
                      return Column(
                        children: [
                          attentionCard,
                          const SizedBox(height: 18),
                          flowCard,
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: attentionCard),
                        const SizedBox(width: 18),
                        Expanded(child: flowCard),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 18),
                _SectionCard(
                  title: 'Device and system status',
                  children: [
                    _AlertRow(
                      title: diagnostics.deviceLabel,
                      detail:
                          '${diagnostics.networkDetail} ${diagnostics.powerStatus}. ${diagnostics.estimatedRuntime}.',
                      accent: diagnostics.networkStatus == 'Offline'
                          ? const Color(0xFFFB7185)
                          : const Color(0xFF60A5FA),
                    ),
                    const SizedBox(height: 12),
                    _AlertRow(
                      title: 'Realtime backend',
                      detail:
                          '${terminal.connectionMessage} Last sync ${terminal.lastSync.shortTimestamp}.',
                      accent: _syncStateColor(terminal.syncState),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _SectionCard(
                  title: 'Hardware alerts',
                  children: [
                    if (sensorAlerts.isEmpty && feedAlerts.isEmpty)
                      const _EmptyStateLine(
                        message: 'No hardware anomalies are active right now.',
                      ),
                    ...sensorAlerts.map(
                      (sensor) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _AlertRow(
                          title: sensor.label,
                          detail:
                              '${sensor.value.oneDecimal}${sensor.unit} outside ${sensor.minNormal.oneDecimal}-${sensor.maxNormal.oneDecimal}${sensor.unit}',
                          accent: const Color(0xFFFB7185),
                        ),
                      ),
                    ),
                    ...feedAlerts.map(
                      (feed) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _AlertRow(
                          title: feed.title,
                          detail: feed.alert ?? 'Video uplink offline',
                          accent: !feed.isOnline
                              ? const Color(0xFFFB7185)
                              : const Color(0xFFF59E0B),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _SectionCard(
                  title: 'Operator notices',
                  children: [
                    if (notifications.items.isEmpty)
                      const _EmptyStateLine(
                        message: 'No operator messages are waiting.',
                      ),
                    ...notifications.items.map(
                      (notice) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _AlertRow(
                          title: notice.title,
                          detail:
                              '${notice.message} • ${notice.createdAt.shortTimestamp}',
                          accent: _notificationColor(notice.severity),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: Colors.white.withValues(alpha: 0.04),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class _BarInsightCard extends StatelessWidget {
  const _BarInsightCard({
    required this.title,
    required this.subtitle,
    required this.bars,
    required this.explanation,
  });

  final String title;
  final String subtitle;
  final List<_BarDatum> bars;
  final String explanation;

  @override
  Widget build(BuildContext context) {
    final maxValue = bars
        .map((item) => item.value)
        .fold<double>(0, (left, right) => left > right ? left : right);
    final maxY = maxValue <= 0 ? 1.0 : (maxValue + 1).ceilToDouble();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: Colors.white.withValues(alpha: 0.04),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(color: Colors.white70, height: 1.45),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 220,
            child: BarChart(
              BarChartData(
                minY: 0,
                maxY: maxY,
                alignment: BarChartAlignment.spaceAround,
                barTouchData: BarTouchData(enabled: false),
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Colors.white.withValues(alpha: 0.08),
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: maxY <= 4 ? 1 : (maxY / 4).ceilToDouble(),
                      getTitlesWidget: (value, meta) => Text(
                        value.toInt().toString(),
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= bars.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            bars[index].label,
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: [
                  for (var index = 0; index < bars.length; index++)
                    BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: bars[index].value,
                          width: 22,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(8),
                            topRight: Radius.circular(8),
                          ),
                          color: bars[index].color,
                          backDrawRodData: BackgroundBarChartRodData(
                            show: true,
                            toY: maxY,
                            color: Colors.white.withValues(alpha: 0.04),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: bars
                .map(
                  (bar) => _LegendPill(
                    label: '${bar.label} ${bar.value.toInt()}',
                    color: bar.color,
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: 14),
          Text(
            explanation,
            style: const TextStyle(color: Colors.white70, height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _LegendPill extends StatelessWidget {
  const _LegendPill({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: 0.12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _BarDatum {
  const _BarDatum(this.label, this.value, this.color);

  final String label;
  final double value;
  final Color color;
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
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
      width: 190,
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
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({
    required this.title,
    required this.detail,
    required this.accent,
  });

  final String title;
  final String detail;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 11,
          height: 11,
          margin: const EdgeInsets.only(top: 5),
          decoration: BoxDecoration(
            color: accent,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.28),
                blurRadius: 14,
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
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                detail,
                style: const TextStyle(color: Colors.white70, height: 1.45),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyStateLine extends StatelessWidget {
  const _EmptyStateLine({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: const TextStyle(color: Colors.white60),
    );
  }
}

String _syncStateLabel(TerminalSyncState state) {
  switch (state) {
    case TerminalSyncState.connecting:
      return 'connecting';
    case TerminalSyncState.live:
      return 'live';
    case TerminalSyncState.degraded:
      return 'degraded';
  }
}

Color _syncStateColor(TerminalSyncState state) {
  switch (state) {
    case TerminalSyncState.connecting:
      return const Color(0xFFF59E0B);
    case TerminalSyncState.live:
      return const Color(0xFF2DD4BF);
    case TerminalSyncState.degraded:
      return const Color(0xFFFB7185);
  }
}

Color _notificationColor(NotificationSeverity severity) {
  switch (severity) {
    case NotificationSeverity.info:
      return const Color(0xFF60A5FA);
    case NotificationSeverity.warning:
      return const Color(0xFFF59E0B);
    case NotificationSeverity.critical:
      return const Color(0xFFFB7185);
  }
}

String _attentionExplanation({
  required int sensorAlerts,
  required int feedAlerts,
  required int noticeCount,
  required int criticalCount,
}) {
  final entries = {
    'sensor anomalies': sensorAlerts,
    'video issues': feedAlerts,
    'operator notices': noticeCount,
    'critical flags': criticalCount,
  }.entries.toList()
    ..sort((left, right) => right.value.compareTo(left.value));

  if (entries.first.value == 0) {
    return 'Attention demand is flat right now, so operators can spend more time on observation than intervention.';
  }

  return 'The heaviest attention source is ${entries.first.key} at ${entries.first.value}. '
      'That means the first visual scan should start there before drilling into the detailed alert rows below.';
}

String _flowExplanation({
  required int queuedDeliveries,
  required int inProgressDeliveries,
  required int completedDeliveries,
  required int craneCount,
}) {
  if (queuedDeliveries > inProgressDeliveries) {
    return 'Backlog is running ahead of live execution, so the next operator review should focus on clearing queued deliveries and checking whether crane coverage is enough at $craneCount active links.';
  }

  if (completedDeliveries >= queuedDeliveries &&
      completedDeliveries >= inProgressDeliveries) {
    return 'Completion is leading the flow picture, which suggests the shift is processing work faster than new queue pressure is forming.';
  }

  return 'Execution is roughly balanced across backlog and completion, so operators can use the chart to spot whether queue pressure or crane availability starts pulling the flow off center.';
}
