import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/generated_report.dart';
import '../models/system_diagnostics.dart';
import '../models/terminal_stats.dart';
import '../providers/automation_hub_provider.dart';
import '../providers/notification_provider.dart';
import '../providers/operations_repository.dart';
import '../services/gemini_service.dart';
import '../utils/extensions.dart';
import 'glass_card.dart';

class AIOperationsCopilotCard extends StatefulWidget {
  const AIOperationsCopilotCard({
    super.key,
    required this.stats,
    required this.operations,
    required this.notifications,
  });

  final TerminalStats stats;
  final OperationsRepository operations;
  final NotificationProvider notifications;

  @override
  State<AIOperationsCopilotCard> createState() =>
      _AIOperationsCopilotCardState();
}

class _AIOperationsCopilotCardState extends State<AIOperationsCopilotCard> {
  final TextEditingController _controller = TextEditingController();
  final List<_AiMessage> _messages = [
    const _AiMessage(
      role: _AiMessageRole.assistant,
      text:
          'I can summarize terminal health, explain alerts, suggest manual repair steps, and turn live telemetry into operator-ready actions.',
    ),
  ];

  bool _isSending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _sendPrompt([String? rawPrompt]) async {
    final prompt = (rawPrompt ?? _controller.text).trim();
    if (prompt.isEmpty || _isSending) {
      return;
    }

    final hub = context.read<AutomationHubProvider>();
    final fallback = _fallbackResponse(
      prompt: prompt,
      hub: hub,
      latestReport: hub.reports.isEmpty ? null : hub.reports.first,
    );

    setState(() {
      _messages.add(_AiMessage(role: _AiMessageRole.user, text: prompt));
      _controller.clear();
      _isSending = true;
    });

    final response = await GeminiService.callGemini(
      _buildPrompt(
        prompt: prompt,
        hub: hub,
        latestReport: hub.reports.isEmpty ? null : hub.reports.first,
      ),
      systemInstruction:
          'You are an operations copilot for an automated port command center. '
          'Answer briefly, use plain language, reference the supplied telemetry, '
          'highlight when human intervention is necessary, and prioritize safety, '
          'repair handoff, and communication continuity.',
      fallback: fallback,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _messages.add(_AiMessage(role: _AiMessageRole.assistant, text: response));
      _isSending = false;
    });
  }

  String _buildPrompt({
    required String prompt,
    required AutomationHubProvider hub,
    required GeneratedReport? latestReport,
  }) {
    final diagnostics = hub.diagnostics;
    final queued = widget.operations.deliveriesByStatus('Queued').length;
    final inProgress =
        widget.operations.deliveriesByStatus('In Progress').length;

    return '''
User question: $prompt

Live terminal context:
- TEU counter: ${widget.stats.teuCounter}
- Efficiency: ${widget.stats.efficiency.toStringAsFixed(1)}%
- Active cranes: ${widget.stats.activeCranes}
- Yard utilization: ${widget.stats.yardUtilization}%
- Active alerts: ${widget.operations.activeAlerts}
- Operator notices: ${widget.notifications.unreadCount}
- Queued deliveries: $queued
- In-progress deliveries: $inProgress
- Completed deliveries: ${widget.operations.completedDeliveries}
- Average AGV battery: ${widget.operations.averageBatteryLevel.toStringAsFixed(0)}%
- Network: ${diagnostics.networkStatus} (${diagnostics.networkDetail})
- Power: ${diagnostics.powerStatus}
- Runtime estimate: ${diagnostics.estimatedRuntime}
- Contact roster size: ${hub.contacts.length}
- Latest report: ${latestReport?.summary ?? 'No report generated yet'}

Give a practical response that combines automation guidance with human fallback.
''';
  }

  String _fallbackResponse({
    required String prompt,
    required AutomationHubProvider hub,
    required GeneratedReport? latestReport,
  }) {
    final lower = prompt.toLowerCase();
    final exactEntityMatch = _entityMatchResponse(lower);
    if (exactEntityMatch != null) {
      return exactEntityMatch;
    }

    if (_containsAny(lower, [
      'delivery',
      'deliveries',
      'container',
      'shipment',
      'manifest',
      'queue',
      'queued',
      'completed',
      'destination',
      'gate',
    ])) {
      return _deliveryResponse();
    }

    if (_containsAny(lower, [
      'agv',
      'fleet',
      'vehicle',
      'battery',
      'charging',
      'zone',
      'speed',
    ])) {
      return _agvResponse();
    }

    if (_containsAny(lower, [
      'crane',
      'cranes',
      'hook',
      'load',
      'berth',
      'operator',
      'utilization',
    ])) {
      return _craneResponse();
    }

    if (_containsAny(lower, [
      'sensor',
      'sensors',
      'temperature',
      'pressure',
      'reading',
      'iot',
      'telemetry',
    ])) {
      return _sensorResponse();
    }

    if (_containsAny(lower, [
      'camera',
      'cameras',
      'cctv',
      'video',
      'vision',
      'feed',
      'feeds',
    ])) {
      return _cameraResponse();
    }

    if (_containsAny(lower, [
      'alert',
      'alerts',
      'alarm',
      'incident',
      'issue',
      'issues',
      'problem',
      'problems',
      'exception',
    ])) {
      return _alertsResponse();
    }

    if (_containsAny(lower, [
      'network',
      'power',
      'runtime',
      'device',
      'connectivity',
      'online',
      'offline',
    ])) {
      return _diagnosticsResponse(hub);
    }

    final diagnostics = hub.diagnostics;
    final topContact = hub.contacts.isEmpty ? null : hub.contacts.first;
    final queued = widget.operations.deliveriesByStatus('Queued').length;
    final sensorIssues = widget.operations.sensorReadings
        .where((sensor) => !sensor.isInNormalRange)
        .length;
    final cameraIssues = widget.operations.cameraFeeds
        .where((feed) => feed.alert != null || !feed.isOnline)
        .length;

    if (lower.contains('repair') ||
        lower.contains('manual') ||
        lower.contains('human')) {
      final contactLine = topContact == null
          ? 'No saved operator contact is available yet.'
          : 'Start with ${topContact.name} (${topContact.role}) on ${topContact.phoneNumber} or Telegram ${topContact.telegramHandle}.';
      return 'Manual fallback is recommended when automation drifts or the stack goes down. '
          'Current repair pressure comes from $sensorIssues sensor issues, $cameraIssues vision issues, '
          'and ${widget.notifications.unreadCount} operator notices. $contactLine';
    }

    if (lower.contains('alert') || lower.contains('alarm')) {
      return 'The alert picture is led by $sensorIssues sensor exceptions, $cameraIssues camera or uplink issues, '
          'and ${widget.notifications.unreadCount} operator notices. ${_alertsResponse()}';
    }

    if (lower.contains('report')) {
      return latestReport == null
          ? 'No report has been generated yet. Open the Reports section to create a professional summary for the last 24 hours, 7 days, 4 weeks, 6 months, or 12 months.'
          : 'Latest report: ${latestReport.summary} Recommendation: ${latestReport.recommendation}';
    }

    final criticalNotices = widget.notifications.items
        .where((item) => item.severity == NotificationSeverity.critical)
        .length;
    final warningNotices = widget.notifications.items
        .where((item) => item.severity == NotificationSeverity.warning)
        .length;

    return 'Local operations snapshot: efficiency is ${widget.stats.efficiency.toStringAsFixed(1)}%, '
        'yard utilization is ${widget.stats.yardUtilization}%, and TEU counter is ${widget.stats.teuCounter}. '
        'Deliveries are at $queued queued, ${widget.operations.deliveriesByStatus('In Progress').length} in progress, '
        'and ${widget.operations.completedDeliveries} completed. '
        'Fleet average battery is ${widget.operations.averageBatteryLevel.toStringAsFixed(0)}% across ${widget.operations.agvs.length} AGVs, '
        'with ${widget.operations.cranes.length} cranes reporting. '
        'The current issue load is ${widget.operations.activeAlerts} active hardware alerts, '
        '$sensorIssues abnormal sensors, $cameraIssues camera issues, '
        '$warningNotices warning notices, and $criticalNotices critical notices. '
        'Device status is ${diagnostics.networkStatus} connectivity with ${diagnostics.powerStatus.toLowerCase()}.';
  }

  bool _containsAny(String text, List<String> keywords) {
    return keywords.any(text.contains);
  }

  String? _entityMatchResponse(String promptLower) {
    for (final delivery in widget.operations.deliveries) {
      if (promptLower.contains(delivery.containerId.toLowerCase()) ||
          promptLower.contains(delivery.shipmentCode.toLowerCase())) {
        final exception = delivery.exceptionReason == null
            ? 'No exception is recorded.'
            : 'Exception: ${delivery.exceptionReason}.';
        return 'Delivery ${delivery.containerId} for ${delivery.destination} is ${delivery.status} with ${delivery.priority} priority. '
            'Shipment ${delivery.shipmentCode} has ${delivery.itemsCount} items and expected gate-out at '
            '${delivery.expectedGateOutAt.toLocal().toString().substring(0, 16)}. $exception';
      }
    }

    for (final agv in widget.operations.agvs) {
      if (promptLower.contains(agv.id.toLowerCase())) {
        return 'AGV ${agv.id} is ${agv.status} in ${agv.zone}, battery ${agv.batteryLevel.toStringAsFixed(0)}%, '
            'speed ${agv.speedKph.toStringAsFixed(1)} kph, last update ${agv.lastUpdated.toLocal().toString().substring(0, 16)}.';
      }
    }

    for (final crane in widget.operations.cranes) {
      if (promptLower.contains(crane.id.toLowerCase())) {
        return 'Crane ${crane.id} is ${crane.status} under ${crane.operatorName}, '
            'load ${crane.loadTons.toStringAsFixed(1)} tons, hook height ${crane.hookHeightMeters.toStringAsFixed(1)} m, '
            'utilization ${crane.utilization.toStringAsFixed(0)}%.';
      }
    }

    for (final camera in widget.operations.cameraFeeds) {
      if (promptLower.contains(camera.id.toLowerCase())) {
        final alert = camera.alert == null ? 'No camera alert is recorded.' : 'Alert: ${camera.alert}.';
        return 'Camera ${camera.id} at ${camera.location} is ${camera.isOnline ? 'online' : 'offline'} with ${camera.viewers} viewers. $alert';
      }
    }

    for (final sensor in widget.operations.sensorReadings) {
      if (promptLower.contains(sensor.id.toLowerCase())) {
        return 'Sensor ${sensor.id} (${sensor.label}) is reading ${sensor.value.toStringAsFixed(1)} ${sensor.unit}. '
            'Normal range is ${sensor.minNormal.toStringAsFixed(1)} to ${sensor.maxNormal.toStringAsFixed(1)} ${sensor.unit}, '
            'so it is currently ${sensor.isInNormalRange ? 'normal' : 'out of range'}.';
      }
    }

    return null;
  }

  String _deliveryResponse() {
    final queued = widget.operations.deliveriesByStatus('Queued');
    final inProgress = widget.operations.deliveriesByStatus('In Progress');
    final completed = widget.operations.deliveriesByStatus('Completed');
    final critical = widget.operations.deliveries
        .where((item) => item.priority == 'Critical')
        .toList(growable: false);
    final exceptions = widget.operations.deliveries
        .where((item) => item.exceptionReason != null)
        .take(2)
        .map((item) => '${item.containerId}: ${item.exceptionReason}')
        .join('; ');

    return 'Delivery state is ${queued.length} queued, ${inProgress.length} in progress, and ${completed.length} completed. '
        'Critical manifests: ${critical.isEmpty ? 'none' : critical.map((item) => item.containerId).take(3).join(', ')}. '
        '${exceptions.isEmpty ? 'No active delivery exceptions are recorded.' : 'Top delivery exceptions: $exceptions.'}';
  }

  String _agvResponse() {
    final agvs = widget.operations.agvs;
    final lowBattery = agvs
        .where((item) => item.batteryLevel < 30)
        .toList(growable: true)
      ..sort((left, right) => left.batteryLevel.compareTo(right.batteryLevel));
    final parked = agvs.where((item) => item.speedKph <= 0.5).length;

    return 'Fleet status covers ${agvs.length} AGVs with average battery ${widget.operations.averageBatteryLevel.toStringAsFixed(0)}%. '
        '${lowBattery.isEmpty ? 'No AGV is below 30% battery.' : 'Low-battery AGVs: ${lowBattery.take(3).map((item) => '${item.id} ${item.batteryLevel.toStringAsFixed(0)}%').join(', ')}.'} '
        '$parked units are effectively stationary right now.';
  }

  String _craneResponse() {
    final cranes = widget.operations.cranes.toList(growable: true)
      ..sort((left, right) =>
          right.utilization.compareTo(left.utilization));
    final top = cranes.take(2).map((item) {
      return '${item.id} ${item.utilization.toStringAsFixed(0)}% under ${item.operatorName}';
    }).join(', ');

    return 'Crane operations show ${cranes.length} active crane feeds with average utilization ${widget.operations.craneUtilization.toStringAsFixed(0)}%. '
        '${top.isEmpty ? 'No crane utilization detail is available.' : 'Highest-utilization cranes: $top.'}';
  }

  String _sensorResponse() {
    final abnormal = widget.operations.sensorReadings
        .where((item) => !item.isInNormalRange)
        .toList(growable: false);
    final highlights = abnormal.take(3).map((item) {
      return '${item.label} ${item.value.toStringAsFixed(1)} ${item.unit}';
    }).join(', ');

    return abnormal.isEmpty
        ? 'All ${widget.operations.sensorReadings.length} monitored sensors are currently within their normal ranges.'
        : '${abnormal.length} sensors are out of range. Highest-priority readings: $highlights.';
  }

  String _cameraResponse() {
    final offline = widget.operations.cameraFeeds
        .where((item) => !item.isOnline)
        .toList(growable: false);
    final alerted = widget.operations.cameraFeeds
        .where((item) => item.alert != null)
        .toList(growable: false);

    return 'Camera coverage includes ${widget.operations.cameraFeeds.length} feeds. '
        '${offline.isEmpty ? 'No feeds are offline.' : 'Offline feeds: ${offline.take(3).map((item) => item.title).join(', ')}.'} '
        '${alerted.isEmpty ? 'No camera alerts are active.' : 'Camera alerts: ${alerted.take(3).map((item) => '${item.title} ${item.alert}').join(', ')}.'}';
  }

  String _alertsResponse() {
    final abnormalSensors = widget.operations.sensorReadings
        .where((item) => !item.isInNormalRange)
        .length;
    final cameraIssues = widget.operations.cameraFeeds
        .where((item) => !item.isOnline || item.alert != null)
        .length;
    final criticalNotices = widget.notifications.items
        .where((item) => item.severity == NotificationSeverity.critical)
        .take(2)
        .map((item) => item.title)
        .join(', ');

    return 'Current issues break down into $abnormalSensors abnormal sensors, $cameraIssues camera issues, '
        'and ${widget.notifications.unreadCount} operator notices. '
        '${criticalNotices.isEmpty ? 'No critical notice titles are queued right now.' : 'Critical notices: $criticalNotices.'}';
  }

  String _diagnosticsResponse(AutomationHubProvider hub) {
    final diagnostics = hub.diagnostics;
    return 'Device diagnostics show ${diagnostics.networkStatus} connectivity on ${diagnostics.deviceLabel}. '
        'Detail: ${diagnostics.networkDetail}. Power state: ${diagnostics.powerStatus}. '
        'Battery is ${diagnostics.batteryLabel} and estimated runtime is ${diagnostics.estimatedRuntime}.';
  }

  @override
  Widget build(BuildContext context) {
    final hub = context.watch<AutomationHubProvider>();
    final diagnostics = hub.diagnostics;
    final latestReport = hub.reports.isEmpty ? null : hub.reports.first;
    final suggestions = [
      'Summarize terminal health',
      'Which alerts need human repair?',
      'Explain battery and network risk',
      'How should operators coordinate?',
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
                      'AI OPERATIONS COPILOT',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Talk to the system about automation health, repair fallback, operator coordination, and live terminal telemetry.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.white70,
                            height: 1.45,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              _AiStatusChip(
                label: GeminiService.isConfigured
                    ? 'Gemini via Firebase'
                    : 'Local demo fallback',
                accent: GeminiService.isConfigured
                    ? const Color(0xFF2DD4BF)
                    : const Color(0xFFF59E0B),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: suggestions
                .map(
                  (item) => ActionChip(
                    label: Text(item),
                    onPressed: () => _sendPrompt(item),
                    backgroundColor: Colors.white.withValues(alpha: 0.06),
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                    labelStyle: const TextStyle(color: Colors.white),
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 980;
              final conversation = _ConversationPanel(
                messages: _messages,
                isSending: _isSending,
              );
              final contextPanel = _CopilotContextPanel(
                diagnostics: diagnostics,
                latestReport: latestReport,
                contactCount: hub.contacts.length,
                stats: widget.stats,
                operations: widget.operations,
              );

              if (compact) {
                return Column(
                  children: [
                    conversation,
                    const SizedBox(height: 18),
                    contextPanel,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 7, child: conversation),
                  const SizedBox(width: 18),
                  Expanded(flex: 4, child: contextPanel),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              color: Colors.white.withValues(alpha: 0.04),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    onSubmitted: (_) => _sendPrompt(),
                    minLines: 1,
                    maxLines: 3,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText:
                          'Ask about system information, alerts, repairs, reports, or operator coordination',
                      hintStyle: TextStyle(color: Colors.white54),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _isSending ? null : () => _sendPrompt(),
                  icon: _isSending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                  label: Text(_isSending ? 'Thinking' : 'Ask AI'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConversationPanel extends StatelessWidget {
  const _ConversationPanel({
    required this.messages,
    required this.isSending,
  });

  final List<_AiMessage> messages;
  final bool isSending;

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
        height: 330,
        child: ListView.separated(
          itemCount: messages.length + (isSending ? 1 : 0),
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            if (isSending && index == messages.length) {
              return const _MessageBubble(
                message: _AiMessage(
                  role: _AiMessageRole.assistant,
                  text: 'Analyzing the current command-center state...',
                ),
                pending: true,
              );
            }
            return _MessageBubble(message: messages[index]);
          },
        ),
      ),
    );
  }
}

class _CopilotContextPanel extends StatelessWidget {
  const _CopilotContextPanel({
    required this.diagnostics,
    required this.latestReport,
    required this.contactCount,
    required this.stats,
    required this.operations,
  });

  final SystemDiagnostics diagnostics;
  final GeneratedReport? latestReport;
  final int contactCount;
  final TerminalStats stats;
  final OperationsRepository operations;

  @override
  Widget build(BuildContext context) {
    final tiles = [
      ('Network', diagnostics.networkStatus, const Color(0xFF60A5FA)),
      ('Battery', diagnostics.batteryLabel, const Color(0xFFF59E0B)),
      ('Alerts', '${operations.activeAlerts}', const Color(0xFFFB7185)),
      ('Contacts', '$contactCount', const Color(0xFF2DD4BF)),
    ];

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
                'SYSTEM CONTEXT',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 16),
              for (final tile in tiles) ...[
                _ContextStatRow(
                  label: tile.$1,
                  value: tile.$2,
                  accent: tile.$3,
                ),
                if (tile != tiles.last) const SizedBox(height: 12),
              ],
              const SizedBox(height: 14),
              Divider(color: Colors.white.withValues(alpha: 0.08)),
              const SizedBox(height: 14),
              _ContextStatRow(
                label: 'Efficiency',
                value: '${stats.efficiency.toStringAsFixed(1)}%',
                accent: const Color(0xFF2DD4BF),
              ),
              const SizedBox(height: 12),
              _ContextStatRow(
                label: 'Last sync',
                value: stats.lastSync.shortTimestamp,
                accent: const Color(0xFF60A5FA),
              ),
              const SizedBox(height: 12),
              Text(
                diagnostics.networkDetail,
                style: const TextStyle(color: Colors.white60, height: 1.45),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Container(
          width: double.infinity,
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
                'LATEST REPORT',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                latestReport?.windowLabel ?? 'No report saved yet',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                latestReport?.summary ??
                    'Generate a report to give the AI a wider time-sliced summary of deliveries, alerts, and battery trends.',
                style: const TextStyle(color: Colors.white70, height: 1.45),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    this.pending = false,
  });

  final _AiMessage message;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final isAssistant = message.role == _AiMessageRole.assistant;

    return Align(
      alignment: isAssistant ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: isAssistant
              ? Colors.white.withValues(alpha: 0.06)
              : const Color(0xFF2563EB).withValues(alpha: 0.72),
          border: Border.all(
            color: isAssistant
                ? Colors.white.withValues(alpha: 0.08)
                : const Color(0xFF60A5FA).withValues(alpha: 0.45),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isAssistant ? 'Copilot' : 'You',
              style: TextStyle(
                color: isAssistant ? Colors.white54 : Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message.text,
              style: TextStyle(
                color: pending ? Colors.white60 : Colors.white,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContextStatRow extends StatelessWidget {
  const _ContextStatRow({
    required this.label,
    required this.value,
    required this.accent,
  });

  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: Colors.white60),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: accent,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _AiStatusChip extends StatelessWidget {
  const _AiStatusChip({
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
        border: Border.all(color: accent.withValues(alpha: 0.3)),
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

enum _AiMessageRole { assistant, user }

class _AiMessage {
  const _AiMessage({
    required this.role,
    required this.text,
  });

  final _AiMessageRole role;
  final String text;
}
