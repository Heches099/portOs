import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/generated_report.dart';
import '../providers/automation_hub_provider.dart';
import '../providers/notification_provider.dart';
import '../providers/operations_repository.dart';
import '../providers/terminal_state_provider.dart';
import '../utils/extensions.dart';
import 'glass_card.dart';

class OperationsReportsView extends StatefulWidget {
  const OperationsReportsView({
    super.key,
    required this.terminal,
    required this.operations,
    required this.notifications,
  });

  final TerminalStateProvider terminal;
  final OperationsRepository operations;
  final NotificationProvider notifications;

  @override
  State<OperationsReportsView> createState() => _OperationsReportsViewState();
}

class _OperationsReportsViewState extends State<OperationsReportsView> {
  ReportWindow _window = ReportWindow.hours;
  bool _isGenerating = false;

  Future<void> _generateReport() async {
    if (_isGenerating) {
      return;
    }

    setState(() => _isGenerating = true);
    final hub = context.read<AutomationHubProvider>();
    await hub.refreshDiagnostics();
    final report = hub.generateReport(
      window: _window,
      stats: widget.terminal.stats,
      operations: widget.operations,
      notifications: widget.notifications,
    );

    if (!mounted) {
      return;
    }

    setState(() => _isGenerating = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${report.title} saved to the report history.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hub = context.watch<AutomationHubProvider>();
    final latest = hub.reports.isEmpty ? null : hub.reports.first;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GlassCard(
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
                            'REPORT CENTER',
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
                            'Generate professional operation reports from stored telemetry snapshots and save them for later handoff, review, or export.',
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
                    FilledButton.icon(
                      onPressed: _isGenerating ? null : _generateReport,
                      icon: _isGenerating
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.description_outlined),
                      label: Text(
                        _isGenerating ? 'Building report' : 'Generate report',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: ReportWindow.values
                      .map(
                        (window) => ChoiceChip(
                          label: Text(_windowLabel(window)),
                          selected: _window == window,
                          onSelected: (_) => setState(() => _window = window),
                          selectedColor:
                              const Color(0xFF2563EB).withValues(alpha: 0.35),
                          backgroundColor: Colors.white.withValues(alpha: 0.05),
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                          labelStyle: const TextStyle(color: Colors.white),
                        ),
                      )
                      .toList(growable: false),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: [
                    _ReportStatusTile(
                      label: 'Stored telemetry points',
                      value: '${hub.storedSnapshotCount}',
                      accent: const Color(0xFF60A5FA),
                    ),
                    _ReportStatusTile(
                      label: 'Saved reports',
                      value: '${hub.reports.length}',
                      accent: const Color(0xFF2DD4BF),
                    ),
                    _ReportStatusTile(
                      label: 'Active alerts',
                      value: '${widget.operations.activeAlerts}',
                      accent: const Color(0xFFFB7185),
                    ),
                    _ReportStatusTile(
                      label: 'Network',
                      value: hub.diagnostics.networkStatus,
                      accent: const Color(0xFFF59E0B),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 1040;
              final latestCard = _LatestReportCard(report: latest);
              final historyCard = _ReportHistoryCard(reports: hub.reports);

              if (compact) {
                return Column(
                  children: [
                    latestCard,
                    const SizedBox(height: 20),
                    historyCard,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 7, child: latestCard),
                  const SizedBox(width: 20),
                  Expanded(flex: 5, child: historyCard),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _LatestReportCard extends StatelessWidget {
  const _LatestReportCard({required this.report});

  final GeneratedReport? report;

  @override
  Widget build(BuildContext context) {
    if (report == null) {
      return GlassCard(
        padding: const EdgeInsets.all(26),
        color: const Color(0xCC0A1626),
        borderRadius: 34,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'LATEST REPORT',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
            ),
            const SizedBox(height: 14),
            Text(
              'No report has been generated yet. Choose a time filter and build one to capture deliveries, alerts, connectivity, and fleet readiness in a professional summary.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white70,
                    height: 1.45,
                  ),
            ),
          ],
        ),
      );
    }

    final activeReport = report!;
    final metrics = [
      (
        'Delivered',
        '${activeReport.deliveredContainers}',
        const Color(0xFF2DD4BF)
      ),
      (
        'Queued avg',
        '${activeReport.queuedContainers}',
        const Color(0xFF60A5FA)
      ),
      ('Alerts avg', '${activeReport.activeAlerts}', const Color(0xFFFB7185)),
      (
        'Battery avg',
        '${activeReport.averageBatteryLevel.toStringAsFixed(0)}%',
        const Color(0xFFF59E0B)
      ),
    ];

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
                      activeReport.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${activeReport.startAt.shortTimestamp} to ${activeReport.endAt.shortTimestamp}',
                      style: const TextStyle(color: Colors.white54),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              _Pill(
                label: activeReport.windowLabel,
                accent: const Color(0xFF2563EB),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            activeReport.summary,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.white70,
                  height: 1.45,
                ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: metrics
                .map(
                  (metric) => _MetricTile(
                    label: metric.$1,
                    value: metric.$2,
                    accent: metric.$3,
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: 20),
          Container(
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
                const Text(
                  'RECOMMENDATION',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  activeReport.recommendation,
                  style: const TextStyle(color: Colors.white70, height: 1.45),
                ),
                const SizedBox(height: 12),
                Text(
                  'Network: ${activeReport.networkStatus} • Power: ${activeReport.powerStatus}',
                  style: const TextStyle(color: Colors.white54),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportHistoryCard extends StatelessWidget {
  const _ReportHistoryCard({required this.reports});

  final List<GeneratedReport> reports;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(26),
      color: const Color(0xCC0A1626),
      borderRadius: 34,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'REPORT HISTORY',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
              ),
              const Spacer(),
              TextButton(
                onPressed: reports.isEmpty
                    ? null
                    : context.read<AutomationHubProvider>().clearReports,
                child: const Text('Clear history'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (reports.isEmpty)
            const Text(
              'Generated reports will be stored here for shift handoff and later review.',
              style: TextStyle(color: Colors.white60),
            ),
          for (final report in reports) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                color: Colors.white.withValues(alpha: 0.04),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          report.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        report.generatedAt.shortTimestamp,
                        style: const TextStyle(color: Colors.white54),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    report.summary,
                    style: const TextStyle(color: Colors.white70, height: 1.45),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Delivered ${report.deliveredContainers} • Alerts ${report.activeAlerts} • ${report.windowLabel}',
                    style: const TextStyle(color: Colors.white54),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReportStatusTile extends StatelessWidget {
  const _ReportStatusTile({
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
      width: 200,
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

class _MetricTile extends StatelessWidget {
  const _MetricTile({
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
      width: 170,
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

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.accent,
  });

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: accent.withValues(alpha: 0.16),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: accent,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

String _windowLabel(ReportWindow window) {
  switch (window) {
    case ReportWindow.hours:
      return '24h';
    case ReportWindow.days:
      return '7d';
    case ReportWindow.weeks:
      return '4w';
    case ReportWindow.months:
      return '6m';
    case ReportWindow.yearly:
      return '12m';
  }
}
