import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/agv_telemetry.dart';
import '../models/camera_feed.dart';
import '../models/crane_telemetry.dart';
import '../models/delivery_record.dart';
import '../models/sensor_reading.dart';
import '../models/terminal_stats.dart';
import '../providers/auth_provider.dart';
import '../providers/automation_hub_provider.dart';
import '../providers/notification_provider.dart';
import '../providers/operations_repository.dart';
import '../providers/terminal_state_provider.dart';
import '../providers/theme_provider.dart';
import '../services/port_api_service.dart';
import '../utils/extensions.dart';
import '../widgets/ai_operations_copilot_card.dart';
import '../widgets/alert_center_sheet.dart';
import '../widgets/glass_card.dart';
import '../widgets/live_camera_spotlight.dart';
import '../widgets/operations_pie_analysis_card.dart';
import '../widgets/operations_reports_view.dart';
import '../widgets/operator_directory_card.dart';

enum _CommandPage { dashboard, vessels, cctv, iot, reports, config }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  _CommandPage _currentPage = _CommandPage.dashboard;
  final Set<_CommandPage> _visitedPages = {_CommandPage.dashboard};

  void _selectPage(_CommandPage page) {
    setState(() {
      _currentPage = page;
      _visitedPages.add(page);
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      final auth = context.read<AuthProvider>();
      if (!auth.isAuthenticated) {
        return;
      }

      unawaited(context.read<OperationsRepository>().refreshData());
      unawaited(context.read<TerminalStateProvider>().connect());
    });
  }

  Future<void> _refreshCommandCenter() async {
    final operations = context.read<OperationsRepository>();
    final terminal = context.read<TerminalStateProvider>();
    final notifications = context.read<NotificationProvider>();
    final automationHub = context.read<AutomationHubProvider>();

    await operations.refreshData();
    await terminal.connect();
    await automationHub.refreshDiagnostics();
    notifications.push(
      title: 'Telemetry refreshed',
      message: operations.isRealtimeMode
          ? 'Command center synchronized Firestore yard data and live stats.'
          : 'Command center synchronized presentation yard data and live stats.',
    );
    automationHub.captureSnapshot(
      stats: terminal.stats,
      operations: operations,
      notifications: notifications,
    );

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          operations.isRealtimeMode
              ? 'Command center Firestore telemetry refreshed.'
              : 'Command center presentation telemetry refreshed.',
        ),
      ),
    );
  }

  Future<void> _signOut() async {
    await context.read<AuthProvider>().signOut();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final terminal = context.watch<TerminalStateProvider>();
    final operations = context.watch<OperationsRepository>();
    final notifications = context.watch<NotificationProvider>();
    final theme = context.watch<ThemeProvider>();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 1180;

        final content = Column(
          children: [
            _CommandHeader(
              page: _currentPage,
              auth: auth,
              terminal: terminal,
              unreadCount: notifications.unreadCount + operations.activeAlerts,
              operations: operations,
              notifications: notifications,
              onRefresh: _refreshCommandCenter,
            ),
            Expanded(
              // Keep every operational page mounted. In particular, this keeps
              // the browser/device camera stream alive while an operator checks
              // another page and then returns to the vision wall.
              child: IndexedStack(
                index: _currentPage.index,
                children: [
                  for (final page in _CommandPage.values)
                    _visitedPages.contains(page)
                        ? _buildPageView(
                            page: page,
                            terminal: terminal,
                            operations: operations,
                            notifications: notifications,
                            auth: auth,
                            theme: theme,
                          )
                        : const SizedBox.shrink(),
                ],
              ),
            ),
          ],
        );

        return Scaffold(
          backgroundColor: const Color(0xFF030712),
          body: Stack(
            children: [
              const Positioned.fill(child: _CommandBackground()),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: isDesktop
                      ? Row(
                          children: [
                            _CommandSidebar(
                              currentPage: _currentPage,
                              onPageSelected: _selectPage,
                              onSignOut: _signOut,
                            ),
                            const SizedBox(width: 16),
                            Expanded(child: content),
                          ],
                        )
                      : Column(
                          children: [
                            Expanded(child: content),
                            const SizedBox(height: 16),
                            _MobileNavigationBar(
                              currentPage: _currentPage,
                              onPageSelected: _selectPage,
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPageView({
    required _CommandPage page,
    required TerminalStateProvider terminal,
    required OperationsRepository operations,
    required NotificationProvider notifications,
    required AuthProvider auth,
    required ThemeProvider theme,
  }) {
    switch (page) {
      case _CommandPage.dashboard:
        return _DashboardView(
          terminal: terminal,
          operations: operations,
          notifications: notifications,
          onRefresh: _refreshCommandCenter,
        );
      case _CommandPage.vessels:
        return _VesselOperationsView(
          terminal: terminal,
          operations: operations,
        );
      case _CommandPage.cctv:
        return _CctvView(
          terminal: terminal,
          operations: operations,
          notifications: notifications,
        );
      case _CommandPage.iot:
        return _IoTView(
          terminal: terminal,
          operations: operations,
        );
      case _CommandPage.reports:
        return OperationsReportsView(
          terminal: terminal,
          operations: operations,
          notifications: notifications,
        );
      case _CommandPage.config:
        return _ConfigView(
          terminal: terminal,
          notifications: notifications,
          auth: auth,
          theme: theme,
          onRefresh: _refreshCommandCenter,
          onSignOut: _signOut,
        );
    }
  }
}

class _DashboardView extends StatelessWidget {
  const _DashboardView({
    required this.terminal,
    required this.operations,
    required this.notifications,
    required this.onRefresh,
  });

  final TerminalStateProvider terminal;
  final OperationsRepository operations;
  final NotificationProvider notifications;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final stats = terminal.stats;
    final feedEvents = _buildFeedEvents(operations, notifications);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 1080;
        final metricWidth = constraints.maxWidth < 760
            ? constraints.maxWidth
            : (constraints.maxWidth - (constraints.maxWidth < 1320 ? 20 : 60)) /
                (constraints.maxWidth < 1320 ? 2 : 4);

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isCompact) ...[
                _CommandHero(
                  stats: stats,
                  terminal: terminal,
                  operations: operations,
                  onRefresh: onRefresh,
                ),
                const SizedBox(height: 20),
                _CommandRail(
                  terminal: terminal,
                  operations: operations,
                  notifications: notifications,
                ),
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 7,
                      child: _CommandHero(
                        stats: stats,
                        terminal: terminal,
                        operations: operations,
                        onRefresh: onRefresh,
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      flex: 4,
                      child: _CommandRail(
                        terminal: terminal,
                        operations: operations,
                        notifications: notifications,
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 20,
                runSpacing: 20,
                children: [
                  SizedBox(
                    width: metricWidth,
                    child: _MetricPanel(
                      eyebrow: 'Throughput',
                      value: '${stats.teuCounter}',
                      change: '+312 today',
                      tone: const Color(0xFF60A5FA),
                      chartPoints: [
                        stats.teuCounter - 320,
                        stats.teuCounter - 280,
                        stats.teuCounter - 240,
                        stats.teuCounter - 160,
                        stats.teuCounter - 98,
                        stats.teuCounter.toDouble(),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: metricWidth,
                    child: _MetricPanel(
                      eyebrow: 'Efficiency',
                      value: '${stats.efficiency.toStringAsFixed(1)}%',
                      change: 'lift cycle stable',
                      tone: const Color(0xFF2DD4BF),
                      chartPoints: operations.cranes
                          .map((crane) => crane.utilization)
                          .toList(growable: false),
                    ),
                  ),
                  SizedBox(
                    width: metricWidth,
                    child: _MetricPanel(
                      eyebrow: 'Fleet Charge',
                      value:
                          '${operations.averageBatteryLevel.toStringAsFixed(0)}%',
                      change: 'AGV battery mean',
                      tone: const Color(0xFFF59E0B),
                      chartPoints: operations.agvBatteryTrend,
                    ),
                  ),
                  SizedBox(
                    width: metricWidth,
                    child: _MetricPanel(
                      eyebrow: 'Active Alerts',
                      value: '${operations.activeAlerts}',
                      change: '${notifications.unreadCount} operator notices',
                      tone: const Color(0xFFFB7185),
                      chartPoints: [
                        2,
                        3,
                        3,
                        operations.activeAlerts.toDouble().clamp(1, 5),
                        (operations.activeAlerts + 1).toDouble(),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (isCompact) ...[
                _DigitalTwinCard(
                  stats: stats,
                  agvs: operations.agvs,
                  deliveries: operations.deliveries,
                ),
                const SizedBox(height: 20),
                _OperationsFeedCard(events: feedEvents),
                const SizedBox(height: 20),
                _DeliveryBoardCard(deliveries: operations.deliveries),
                const SizedBox(height: 20),
                _AlertDeckCard(operations: operations),
              ] else ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 7,
                      child: _DigitalTwinCard(
                        stats: stats,
                        agvs: operations.agvs,
                        deliveries: operations.deliveries,
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      flex: 5,
                      child: _OperationsFeedCard(events: feedEvents),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 7,
                      child: _DeliveryBoardCard(
                        deliveries: operations.deliveries,
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      flex: 5,
                      child: _AlertDeckCard(operations: operations),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              OperationsPieAnalysisCard(
                stats: stats,
                operations: operations,
                noticeCount: notifications.unreadCount,
              ),
              const SizedBox(height: 20),
              AIOperationsCopilotCard(
                stats: stats,
                operations: operations,
                notifications: notifications,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _VesselOperationsView extends StatelessWidget {
  const _VesselOperationsView({
    required this.terminal,
    required this.operations,
  });

  final TerminalStateProvider terminal;
  final OperationsRepository operations;

  @override
  Widget build(BuildContext context) {
    final berthRecords = operations.deliveries.take(4).toList(growable: false);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 1040;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
          child: Column(
            children: [
              if (isCompact) ...[
                _BerthOverviewCard(
                  terminal: terminal,
                  deliveries: berthRecords,
                ),
                const SizedBox(height: 20),
                _CraneAssignmentCard(cranes: operations.cranes),
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 7,
                      child: _BerthOverviewCard(
                        terminal: terminal,
                        deliveries: berthRecords,
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      flex: 5,
                      child: _CraneAssignmentCard(cranes: operations.cranes),
                    ),
                  ],
                ),
              const SizedBox(height: 20),
              _ManifestRunSheet(deliveries: operations.deliveries),
            ],
          ),
        );
      },
    );
  }
}

class _CctvView extends StatefulWidget {
  const _CctvView({
    required this.terminal,
    required this.operations,
    required this.notifications,
  });

  final TerminalStateProvider terminal;
  final OperationsRepository operations;
  final NotificationProvider notifications;

  @override
  State<_CctvView> createState() => _CctvViewState();
}

class _CctvViewState extends State<_CctvView> {
  bool _deviceCameraConnected = false;

  void _connectSource(_VisionSource source) {
    if (source == _VisionSource.device) {
      setState(() => _deviceCameraConnected = true);
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${source.label} sources appear in this wall after their camera feed is added to Firestore.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final feeds = widget.operations.cameraFeeds;
    final wallFeeds = <CameraFeed>[
      if (_deviceCameraConnected)
        CameraFeed(
          id: 'local-device-camera',
          title: 'USB / DEVICE CAMERA',
          location: 'This workstation',
          isOnline: true,
          viewers: 1,
          lastUpdated: DateTime.now(),
        ),
      ...feeds.where((feed) => feed.id != 'local-device-camera'),
    ].take(4).toList(growable: false);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktopWall = constraints.maxWidth >= 900;
        final desktopColumns = wallFeeds.length >= 4
            ? 4
            : wallFeeds.length >= 3
                ? 3
                : wallFeeds.length >= 2
                    ? 2
                    : 1;

        final wall = wallFeeds.isEmpty
            ? const Center(
                child: Text(
                  'No camera feeds are available yet.',
                  style: TextStyle(color: Colors.white70),
                ),
              )
            : GridView.builder(
                padding: EdgeInsets.zero,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  // A CCTV wall uses one row on desktop so all configured
                  // sources remain visible without scrolling.
                  crossAxisCount: isDesktopWall ? desktopColumns : 1,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  childAspectRatio: isDesktopWall ? 1.35 : 1.15,
                ),
                itemCount: wallFeeds.length,
                itemBuilder: (context, index) {
                  final feed = wallFeeds[index];
                  // The first panel is the live, permission-backed device
                  // preview; the remaining panels form the CCTV wall from the
                  // configured Firestore camera sources.
                  if (index == 0) {
                    if (_deviceCameraConnected) {
                      return _VisionSpotlightCard(
                        feed: feed,
                        liveSources: widget.terminal.stats.liveSources,
                      );
                    }
                  }
                  return _CctvStreamCard(feed: feed);
                },
              );

        if (!isDesktopWall) {
          return Column(
            children: [
              _VisionWallToolbar(
                feedCount: wallFeeds.length,
                onSourceSelected: _connectSource,
              ),
              const SizedBox(height: 12),
              Expanded(child: wall),
            ],
          );
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
          child: Column(
            children: [
              _VisionWallToolbar(
                feedCount: wallFeeds.length,
                onSourceSelected: _connectSource,
              ),
              const SizedBox(height: 14),
              Expanded(child: wall),
            ],
          ),
        );
      },
    );
  }
}

class _VisionWallToolbar extends StatelessWidget {
  const _VisionWallToolbar({
    required this.feedCount,
    required this.onSourceSelected,
  });

  final int feedCount;
  final ValueChanged<_VisionSource> onSourceSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.videocam_rounded, color: Color(0xFF2DD4BF)),
        const SizedBox(width: 10),
        const Text(
          'CCTV WALL',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(width: 10),
        _StatusChip(
            label: '$feedCount sources', accent: const Color(0xFF2DD4BF)),
        const Spacer(),
        PopupMenuButton<_VisionSource>(
          tooltip: 'Connect camera',
          onSelected: onSourceSelected,
          itemBuilder: (context) => [
            for (final source in _VisionSource.values)
              PopupMenuItem(
                value: source,
                child: Row(
                  children: [
                    Icon(source.icon, size: 20),
                    const SizedBox(width: 10),
                    Text(source.label),
                  ],
                ),
              ),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF2DD4BF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_rounded, color: Color(0xFF042F2E)),
                SizedBox(width: 8),
                Text(
                  'Connect camera',
                  style: TextStyle(
                    color: Color(0xFF042F2E),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

enum _VisionSource { device, rtsp, onvif, nvr }

extension on _VisionSource {
  String get label => switch (this) {
        _VisionSource.device => 'USB / this device',
        _VisionSource.rtsp => 'IP / RTSP stream',
        _VisionSource.onvif => 'ONVIF camera',
        _VisionSource.nvr => 'NVR recorder',
      };

  IconData get icon => switch (this) {
        _VisionSource.device => Icons.usb_rounded,
        _VisionSource.rtsp => Icons.wifi_tethering_rounded,
        _VisionSource.onvif => Icons.videocam_rounded,
        _VisionSource.nvr => Icons.dns_rounded,
      };
}

class _IoTView extends StatelessWidget {
  const _IoTView({
    required this.terminal,
    required this.operations,
  });

  final TerminalStateProvider terminal;
  final OperationsRepository operations;

  @override
  Widget build(BuildContext context) {
    final normalSensors = operations.sensorReadings
        .where((sensor) => sensor.isInNormalRange)
        .length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 1080;
        final topWidth = constraints.maxWidth < 760
            ? constraints.maxWidth
            : (constraints.maxWidth - 40) / 3;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 20,
                runSpacing: 20,
                children: [
                  SizedBox(
                    width: topWidth,
                    child: _MetricPanel(
                      eyebrow: 'Sensor Mesh',
                      value:
                          '$normalSensors/${operations.sensorReadings.length}',
                      change: 'channels in normal band',
                      tone: const Color(0xFF2DD4BF),
                      chartPoints: operations.sensorReadings
                          .map((sensor) => sensor.value)
                          .toList(growable: false),
                    ),
                  ),
                  SizedBox(
                    width: topWidth,
                    child: _MetricPanel(
                      eyebrow: 'AGV Autonomy',
                      value:
                          '${operations.averageBatteryLevel.toStringAsFixed(0)}%',
                      change: '${operations.agvs.length} units online',
                      tone: const Color(0xFF60A5FA),
                      chartPoints: operations.agvs
                          .map((agv) => agv.speedKph * 8)
                          .toList(growable: false),
                    ),
                  ),
                  SizedBox(
                    width: topWidth,
                    child: _MetricPanel(
                      eyebrow: 'Lift Utilization',
                      value:
                          '${operations.craneUtilization.toStringAsFixed(0)}%',
                      change: '${terminal.stats.activeCranes} cranes linked',
                      tone: const Color(0xFFF472B6),
                      chartPoints: operations.craneLoadTrend,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (isCompact) ...[
                _AutonomyFieldCard(
                  terminal: terminal,
                  agvs: operations.agvs,
                ),
                const SizedBox(height: 20),
                _SensorMatrixCard(sensors: operations.sensorReadings),
                const SizedBox(height: 20),
                _CraneResponseCard(cranes: operations.cranes),
              ] else ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 7,
                      child: _AutonomyFieldCard(
                        terminal: terminal,
                        agvs: operations.agvs,
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      flex: 5,
                      child: _SensorMatrixCard(
                        sensors: operations.sensorReadings,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _CraneResponseCard(cranes: operations.cranes),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ConfigView extends StatelessWidget {
  const _ConfigView({
    required this.terminal,
    required this.notifications,
    required this.auth,
    required this.theme,
    required this.onRefresh,
    required this.onSignOut,
  });

  final TerminalStateProvider terminal;
  final NotificationProvider notifications;
  final AuthProvider auth;
  final ThemeProvider theme;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 1040;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
          child: Column(
            children: [
              if (isCompact) ...[
                _OperatorConsoleCard(auth: auth, terminal: terminal),
                const SizedBox(height: 20),
                _StackReadinessCard(terminal: terminal),
                const SizedBox(height: 20),
                OperatorDirectoryCard(auth: auth),
                const SizedBox(height: 20),
                _SystemControlsCard(
                  theme: theme,
                  notifications: notifications,
                  onRefresh: onRefresh,
                  onSignOut: onSignOut,
                ),
              ] else ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 5,
                      child: _OperatorConsoleCard(
                        auth: auth,
                        terminal: terminal,
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      flex: 7,
                      child: _StackReadinessCard(terminal: terminal),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 5,
                      child: _SystemControlsCard(
                        theme: theme,
                        notifications: notifications,
                        onRefresh: onRefresh,
                        onSignOut: onSignOut,
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      flex: 7,
                      child: OperatorDirectoryCard(auth: auth),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _CommandHeader extends StatelessWidget {
  const _CommandHeader({
    required this.page,
    required this.auth,
    required this.terminal,
    required this.unreadCount,
    required this.operations,
    required this.notifications,
    required this.onRefresh,
  });

  final _CommandPage page;
  final AuthProvider auth;
  final TerminalStateProvider terminal;
  final int unreadCount;
  final OperationsRepository operations;
  final NotificationProvider notifications;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 900;

    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      color: const Color(0xBB08111F),
      borderRadius: 32,
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _HeaderTitleBlock(page: page),
                const SizedBox(height: 16),
                _HeaderActions(
                  auth: auth,
                  terminal: terminal,
                  unreadCount: unreadCount,
                  operations: operations,
                  notifications: notifications,
                  onRefresh: onRefresh,
                ),
              ],
            )
          : Row(
              children: [
                const SizedBox(width: 4),
                _HeaderTitleBlock(page: page),
                const Spacer(),
                _HeaderActions(
                  auth: auth,
                  terminal: terminal,
                  unreadCount: unreadCount,
                  operations: operations,
                  notifications: notifications,
                  onRefresh: onRefresh,
                ),
              ],
            ),
    );
  }
}

class _HeaderTitleBlock extends StatelessWidget {
  const _HeaderTitleBlock({required this.page});

  final _CommandPage page;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _pageKicker(page),
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: const Color(0xFF7DD3FC),
                fontWeight: FontWeight.w700,
                letterSpacing: 1.7,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          _pageTitle(page),
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          _pageSubtitle(page),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.white70,
                height: 1.45,
              ),
        ),
      ],
    );
  }
}

class _HeaderActions extends StatelessWidget {
  const _HeaderActions({
    required this.auth,
    required this.terminal,
    required this.unreadCount,
    required this.operations,
    required this.notifications,
    required this.onRefresh,
  });

  final AuthProvider auth;
  final TerminalStateProvider terminal;
  final int unreadCount;
  final OperationsRepository operations;
  final NotificationProvider notifications;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.end,
      spacing: 12,
      runSpacing: 12,
      children: [
        _InfoPill(
          icon: Icons.wifi_tethering_rounded,
          label: _syncStateLabel(terminal.syncState),
          value: terminal.lastSync.shortTime,
          accent: _syncStateColor(terminal.syncState),
        ),
        _InfoPill(
          icon: Icons.notifications_active_outlined,
          label: 'alerts',
          value: '$unreadCount',
          accent: const Color(0xFFF59E0B),
          onTap: () async {
            await context.read<AutomationHubProvider>().refreshDiagnostics();
            if (!context.mounted) {
              return;
            }
            await showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (context) => AlertCenterSheet(
                terminal: terminal,
                operations: operations,
                notifications: notifications,
              ),
            );
          },
        ),
        IconButton.filledTonal(
          onPressed: onRefresh,
          style: IconButton.styleFrom(
            backgroundColor: Colors.white.withValues(alpha: 0.07),
            foregroundColor: Colors.white,
          ),
          icon: const Icon(Icons.sync_rounded),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFF2563EB),
                child: Text(
                  _initials(auth.displayName),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    auth.displayName.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const Text(
                    'authenticated',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CommandSidebar extends StatelessWidget {
  const _CommandSidebar({
    required this.currentPage,
    required this.onPageSelected,
    required this.onSignOut,
  });

  final _CommandPage currentPage;
  final ValueChanged<_CommandPage> onPageSelected;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 118,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(34),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xEE08111F),
            Color(0xD50B1324),
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 40,
            offset: const Offset(0, 24),
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 18),
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFF2563EB), Color(0xFF38BDF8)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF38BDF8).withValues(alpha: 0.35),
                  blurRadius: 30,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: const Icon(
              Icons.blur_on_rounded,
              color: Colors.white,
              size: 34,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'PORT Automation System',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
              fontSize: 11,
            ),
          ),
          const Text(
            'Takes us to the future ',
            style: TextStyle(
              color: Colors.white38,
              letterSpacing: 1.6,
              fontSize: 9,
            ),
          ),
          const SizedBox(height: 22),
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: _navItems.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = _navItems[index];
                return _SidebarButton(
                  item: item,
                  active: currentPage == item.page,
                  onTap: () => onPageSelected(item.page),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Divider(color: Colors.white.withValues(alpha: 0.08)),
          ),
          const SizedBox(height: 8),
          IconButton(
            onPressed: onSignOut,
            tooltip: 'Sign out',
            icon: const Icon(Icons.power_settings_new_rounded),
            color: Colors.white70,
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.05),
              minimumSize: const Size(62, 62),
            ),
          ),
          const SizedBox(height: 18),
        ],
      ),
    );
  }
}

class _SidebarButton extends StatelessWidget {
  const _SidebarButton({
    required this.item,
    required this.active,
    required this.onTap,
  });

  final _NavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final activeColor = _pageAccent(item.page);

    return Tooltip(
      message: item.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(26),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: 88,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: active
                ? LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      activeColor.withValues(alpha: 0.28),
                      activeColor.withValues(alpha: 0.12),
                    ],
                  )
                : null,
            border: Border.all(
              color: active
                  ? activeColor.withValues(alpha: 0.5)
                  : Colors.white.withValues(alpha: 0.05),
            ),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: activeColor.withValues(alpha: 0.22),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ]
                : null,
          ),
          child: Column(
            children: [
              Icon(
                item.icon,
                color: active ? Colors.white : Colors.white38,
                size: 24,
              ),
              const SizedBox(height: 8),
              Text(
                item.compactLabel,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: active ? Colors.white : Colors.white38,
                  fontSize: 10,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileNavigationBar extends StatelessWidget {
  const _MobileNavigationBar({
    required this.currentPage,
    required this.onPageSelected,
  });

  final _CommandPage currentPage;
  final ValueChanged<_CommandPage> onPageSelected;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      color: const Color(0xCC08111F),
      borderRadius: 28,
      child: Row(
        children: _navItems
            .map(
              (item) => Expanded(
                child: InkWell(
                  onTap: () => onPageSelected(item.page),
                  borderRadius: BorderRadius.circular(22),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      color: currentPage == item.page
                          ? _pageAccent(item.page).withValues(alpha: 0.18)
                          : Colors.transparent,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          item.icon,
                          color: currentPage == item.page
                              ? Colors.white
                              : Colors.white38,
                          size: 20,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          item.compactLabel,
                          style: TextStyle(
                            color: currentPage == item.page
                                ? Colors.white
                                : Colors.white38,
                            fontSize: 10,
                            fontWeight: currentPage == item.page
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _CommandHero extends StatelessWidget {
  const _CommandHero({
    required this.stats,
    required this.terminal,
    required this.operations,
    required this.onRefresh,
  });

  final TerminalStats stats;
  final TerminalStateProvider terminal;
  final OperationsRepository operations;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    const sectors = ['Sector Alpha', 'Sector Beta', 'Sector Gamma'];

    return GlassCard(
      padding: const EdgeInsets.all(28),
      color: const Color(0xCC08111F),
      borderRadius: 38,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 14,
            runSpacing: 14,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: const Color(0xFF38BDF8).withValues(alpha: 0.12),
                  border: Border.all(
                    color: const Color(0xFF38BDF8).withValues(alpha: 0.28),
                  ),
                ),
                child: const Text(
                  'LIVE PORT OPERATIONS ',
                  style: TextStyle(
                    color: Color(0xFFBAE6FD),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              Text(
                terminal.connectionMessage,
                style: const TextStyle(
                  color: Colors.white60,
                  height: 1.45,
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 760;

              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _HeroValueBlock(stats: stats),
                    const SizedBox(height: 18),
                    _HeroAside(
                      stats: stats,
                      operations: operations,
                      onRefresh: onRefresh,
                    ),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 6, child: _HeroValueBlock(stats: stats)),
                  const SizedBox(width: 20),
                  Expanded(
                    flex: 4,
                    child: _HeroAside(
                      stats: stats,
                      operations: operations,
                      onRefresh: onRefresh,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: sectors
                .map(
                  (sector) => _SectorChip(
                    label: sector,
                    selected: terminal.selectedSector == sector,
                    onTap: () => terminal.selectSector(sector),
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: 24),
          _RadarStage(
            stats: stats,
            agvs: operations.agvs,
            deliveries: operations.deliveries,
          ),
        ],
      ),
    );
  }
}

class _HeroValueBlock extends StatelessWidget {
  const _HeroValueBlock({required this.stats});

  final TerminalStats stats;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Color(0xFFFFFFFF), Color(0xFF93C5FD), Color(0xFF2DD4BF)],
          ).createShader(bounds),
          child: Text(
            '${stats.teuCounter}',
            style: Theme.of(context).textTheme.displayLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  height: 0.95,
                ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'containers orchestrated through the command lattice today',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.white70,
                height: 1.4,
              ),
        ),
        const SizedBox(height: 22),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _SignalCell(
              label: 'yard',
              value: '${stats.yardUtilization}%',
              accent: const Color(0xFFF59E0B),
            ),
            _SignalCell(
              label: 'cranes',
              value: '${stats.activeCranes}',
              accent: const Color(0xFF60A5FA),
            ),
            _SignalCell(
              label: 'dwell',
              value: '${stats.avgDwellDays.oneDecimal} days',
              accent: const Color(0xFF2DD4BF),
            ),
          ],
        ),
      ],
    );
  }
}

class _HeroAside extends StatelessWidget {
  const _HeroAside({
    required this.stats,
    required this.operations,
    required this.onRefresh,
  });

  final TerminalStats stats;
  final OperationsRepository operations;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        color: Colors.white.withValues(alpha: 0.05),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.auto_awesome_rounded,
                color: Color(0xFF2DD4BF),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'predictive dispatch',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Four-hour forecast sees gate pressure peaking at ${stats.yardUtilization + 6}% if quay lift tempo stays flat.',
            style: const TextStyle(
              color: Colors.white70,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 18),
          _InlineStat(
            label: 'active ground spots',
            value: '${stats.activeGroundSpots}',
          ),
          const SizedBox(height: 10),
          _InlineStat(
            label: 'avg AGV speed',
            value:
                '${_average(operations.agvs.map((agv) => agv.speedKph)).toStringAsFixed(1)} kph',
          ),
          const SizedBox(height: 10),
          _InlineStat(
            label: 'critical queue',
            value:
                '${operations.deliveries.where((item) => item.priority == 'Critical').length}',
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.bolt_rounded),
              label: const Text('Pulse Sync'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommandRail extends StatelessWidget {
  const _CommandRail({
    required this.terminal,
    required this.operations,
    required this.notifications,
  });

  final TerminalStateProvider terminal;
  final OperationsRepository operations;
  final NotificationProvider notifications;

  @override
  Widget build(BuildContext context) {
    final queued = operations.deliveriesByStatus('Queued').length;
    final inFlight = operations.deliveriesByStatus('In Progress').length;

    return Column(
      children: [
        _RailCard(
          title: 'sync integrity',
          accent: _syncStateColor(terminal.syncState),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _syncStateLabel(terminal.syncState).toUpperCase(),
                style: TextStyle(
                  color: _syncStateColor(terminal.syncState),
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                terminal.connectionMessage,
                style: const TextStyle(color: Colors.white70, height: 1.45),
              ),
              const SizedBox(height: 16),
              _MiniBar(
                label: 'stream coverage',
                value: terminal.stats.liveSources / 10,
                accent: const Color(0xFF60A5FA),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _RailCard(
          title: 'dispatch pressure',
          accent: const Color(0xFF2DD4BF),
          child: Column(
            children: [
              _CompactCountRow(
                label: 'queued releases',
                value: '$queued',
                accent: const Color(0xFF38BDF8),
              ),
              const SizedBox(height: 10),
              _CompactCountRow(
                label: 'active turnarounds',
                value: '$inFlight',
                accent: const Color(0xFF2DD4BF),
              ),
              const SizedBox(height: 10),
              _CompactCountRow(
                label: 'operator alerts',
                value: '${notifications.unreadCount}',
                accent: const Color(0xFFF59E0B),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _RailCard(
          title: 'shift pulse',
          accent: const Color(0xFFFB7185),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: notifications.items
                .take(3)
                .map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _PulseRow(
                      color: _notificationColor(item.severity),
                      title: item.title,
                      subtitle: item.createdAt.shortTime,
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        ),
      ],
    );
  }
}

class _DigitalTwinCard extends StatelessWidget {
  const _DigitalTwinCard({
    required this.stats,
    required this.agvs,
    required this.deliveries,
  });

  final TerminalStats stats;
  final List<AgvTelemetry> agvs;
  final List<DeliveryRecord> deliveries;

  @override
  Widget build(BuildContext context) {
    final criticalCount =
        deliveries.where((delivery) => delivery.priority == 'Critical').length;

    return GlassCard(
      padding: const EdgeInsets.all(26),
      color: const Color(0xCC08111F),
      borderRadius: 34,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'DIGITAL TWIN // ${stats.digitalTwinSector.toUpperCase()}',
                    style: const TextStyle(
                      color: Color(0xFF7DD3FC),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.6,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Traffic lattice with predictive yard overlays',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
              const Spacer(),
              _StatusChip(
                label: '$criticalCount priority stacks',
                accent: const Color(0xFFFB7185),
              ),
            ],
          ),
          const SizedBox(height: 20),
          AspectRatio(
            aspectRatio: 1.75,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF08101F),
                      Color(0xFF10203B),
                      Color(0xFF06111D),
                    ],
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _TwinGridPainter(
                          activeColor: const Color(0xFF2563EB),
                        ),
                      ),
                    ),
                    ..._prioritySpots(deliveries),
                    ...agvs.map(_buildAgvNode),
                    Positioned(
                      left: 18,
                      top: 18,
                      child: _MapLabel(
                        title: 'QUAY VECTOR',
                        subtitle: '${stats.activeCranes} cranes linked',
                      ),
                    ),
                    Positioned(
                      right: 18,
                      top: 18,
                      child: _MapLabel(
                        title: 'PREDICTIVE HORIZON',
                        subtitle: '+${stats.predictionWindowHours} hours',
                      ),
                    ),
                    Positioned(
                      left: 18,
                      right: 18,
                      bottom: 18,
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _StatusChip(
                            label: '${stats.activeGroundSpots} active spots',
                            accent: const Color(0xFF60A5FA),
                          ),
                          _StatusChip(
                            label: '${agvs.length} AGVs in mesh',
                            accent: const Color(0xFF2DD4BF),
                          ),
                          _StatusChip(
                            label: '${deliveries.length} live manifests',
                            accent: const Color(0xFFF59E0B),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _prioritySpots(List<DeliveryRecord> deliveries) {
    final highlighted = deliveries
        .where((item) => item.priority != 'Normal')
        .take(3)
        .toList(growable: false);

    return List<Widget>.generate(highlighted.length, (index) {
      final left = 0.18 + (index * 0.24);
      final top = 0.22 + ((index % 2) * 0.28);

      return Positioned(
        left: null,
        right: null,
        child: FractionalTranslation(
          translation: const Offset(-0.5, -0.5),
          child: Align(
            alignment: Alignment(left * 2 - 1, top * 2 - 1),
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFB7185).withValues(alpha: 0.18),
                border: Border.all(
                  color: const Color(0xFFFB7185).withValues(alpha: 0.8),
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFB7185).withValues(alpha: 0.28),
                    blurRadius: 24,
                    spreadRadius: 3,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _buildAgvNode(AgvTelemetry agv) {
    return Positioned(
      left: null,
      right: null,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: Align(
          alignment: Alignment(agv.x * 2 - 1, agv.y * 2 - 1),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Colors.white.withValues(alpha: 0.08),
              border: Border.all(
                color: const Color(0xFF2DD4BF).withValues(alpha: 0.32),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF2DD4BF).withValues(alpha: 0.2),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF2DD4BF),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  agv.id,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OperationsFeedCard extends StatelessWidget {
  const _OperationsFeedCard({required this.events});

  final List<_FeedEvent> events;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(24),
      color: const Color(0xB3121A2B),
      borderRadius: 34,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SHIFT PULSE FEED',
            style: TextStyle(
              color: Color(0xFFF8FAFC),
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Realtime operator notes, manifest motion, and anomaly signals.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white70,
                  height: 1.45,
                ),
          ),
          const SizedBox(height: 20),
          for (final event in events) ...[
            _FeedTile(event: event),
            if (event != events.last)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Divider(color: Colors.white.withValues(alpha: 0.06)),
              ),
          ],
        ],
      ),
    );
  }
}

class _DeliveryBoardCard extends StatelessWidget {
  const _DeliveryBoardCard({required this.deliveries});

  final List<DeliveryRecord> deliveries;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(24),
      color: const Color(0xBB0A1626),
      borderRadius: 34,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'COMMAND QUEUE',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
              ),
              const Spacer(),
              _StatusChip(
                label: '${deliveries.length} active manifests',
                accent: const Color(0xFF60A5FA),
              ),
            ],
          ),
          const SizedBox(height: 18),
          for (final delivery in deliveries.take(5)) ...[
            _DeliveryLine(delivery: delivery),
            if (delivery != deliveries.take(5).last)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Divider(color: Colors.white.withValues(alpha: 0.06)),
              ),
          ],
        ],
      ),
    );
  }
}

class _AlertDeckCard extends StatelessWidget {
  const _AlertDeckCard({required this.operations});

  final OperationsRepository operations;

  @override
  Widget build(BuildContext context) {
    final flaggedSensors = operations.sensorReadings
        .where((sensor) => !sensor.isInNormalRange)
        .toList(growable: false);
    final flaggedFeeds = operations.cameraFeeds
        .where((feed) => feed.alert != null || !feed.isOnline)
        .toList(growable: false);

    return GlassCard(
      padding: const EdgeInsets.all(24),
      color: const Color(0xBB1C1022),
      borderRadius: 34,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ANOMALY DECK',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 18),
          ...flaggedSensors.map(
            (sensor) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _AlertLine(
                title: sensor.label,
                detail:
                    '${sensor.value.oneDecimal}${sensor.unit} outside ${sensor.minNormal.oneDecimal}-${sensor.maxNormal.oneDecimal}${sensor.unit}',
                accent: const Color(0xFFFB7185),
              ),
            ),
          ),
          ...flaggedFeeds.map(
            (feed) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _AlertLine(
                title: feed.title,
                detail: feed.alert ?? 'Video uplink offline',
                accent: const Color(0xFFF59E0B),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BerthOverviewCard extends StatelessWidget {
  const _BerthOverviewCard({
    required this.terminal,
    required this.deliveries,
  });

  final TerminalStateProvider terminal;
  final List<DeliveryRecord> deliveries;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(26),
      color: const Color(0xCC08111F),
      borderRadius: 34,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'BERTH HORIZON',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
              ),
              const Spacer(),
              _StatusChip(
                label: terminal.selectedSector,
                accent: const Color(0xFF38BDF8),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'A sharper vessel board, crane pairing, and manifest readiness wall.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white70,
                  height: 1.45,
                ),
          ),
          const SizedBox(height: 22),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: List.generate(deliveries.length, (index) {
              final delivery = deliveries[index];
              return SizedBox(
                width: 250,
                child: _BerthTile(
                  berthName: 'BERTH A${index + 1}',
                  delivery: delivery,
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _CraneAssignmentCard extends StatelessWidget {
  const _CraneAssignmentCard({required this.cranes});

  final List<CraneTelemetry> cranes;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(24),
      color: const Color(0xBB111827),
      borderRadius: 34,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'CRANE PAIRING',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 18),
          for (final crane in cranes) ...[
            _CraneLine(crane: crane),
            if (crane != cranes.last)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Divider(color: Colors.white.withValues(alpha: 0.06)),
              ),
          ],
        ],
      ),
    );
  }
}

class _ManifestRunSheet extends StatelessWidget {
  const _ManifestRunSheet({required this.deliveries});

  final List<DeliveryRecord> deliveries;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(24),
      color: const Color(0xCC0A1626),
      borderRadius: 34,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'MANIFEST RUN SHEET',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
          ),
          const SizedBox(height: 18),
          _SheetHeader(),
          const SizedBox(height: 12),
          for (final delivery in deliveries) ...[
            _SheetRow(delivery: delivery),
            if (delivery != deliveries.last)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Divider(color: Colors.white.withValues(alpha: 0.06)),
              ),
          ],
        ],
      ),
    );
  }
}

class _VisionSpotlightCard extends StatelessWidget {
  const _VisionSpotlightCard({
    required this.feed,
    required this.liveSources,
  });

  final CameraFeed feed;
  final int liveSources;

  @override
  Widget build(BuildContext context) {
    return LiveCameraSpotlight(
      feed: feed,
      liveSources: liveSources,
    );
  }
}

class _VisionEventsCard extends StatelessWidget {
  const _VisionEventsCard({
    required this.notifications,
    required this.feeds,
  });

  final List<AppNotification> notifications;
  final List<CameraFeed> feeds;

  @override
  Widget build(BuildContext context) {
    final feedAlerts = feeds
        .where((feed) => feed.alert != null || !feed.isOnline)
        .toList(growable: false);

    return GlassCard(
      padding: const EdgeInsets.all(24),
      color: const Color(0xBB101827),
      borderRadius: 34,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'VISION EVENTS',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 18),
          ...feedAlerts.map(
            (feed) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _AlertLine(
                title: feed.title,
                detail: feed.alert ?? 'Uplink requires intervention',
                accent: !feed.isOnline
                    ? const Color(0xFFFB7185)
                    : const Color(0xFFF59E0B),
              ),
            ),
          ),
          ...notifications.take(2).map(
                (notice) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _AlertLine(
                    title: notice.title,
                    detail: notice.message,
                    accent: _notificationColor(notice.severity),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _CctvStreamCard extends StatelessWidget {
  const _CctvStreamCard({required this.feed});

  final CameraFeed feed;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(0),
      color: const Color(0xCC050B15),
      borderRadius: 30,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: AspectRatio(
          aspectRatio: 1.55,
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: feed.isOnline
                        ? const [
                            Color(0xFF09111E),
                            Color(0xFF0D1D33),
                            Color(0xFF050B15),
                          ]
                        : const [
                            Color(0xFF170B10),
                            Color(0xFF261019),
                            Color(0xFF09080A),
                          ],
                  ),
                ),
              ),
              Center(
                child: Icon(
                  feed.isOnline
                      ? Icons.sensors_rounded
                      : Icons
                          .signal_wifi_statusbar_connected_no_internet_4_rounded,
                  color: Colors.white.withValues(alpha: 0.08),
                  size: 72,
                ),
              ),
              Positioned(
                top: 18,
                left: 18,
                child: _StatusChip(
                  label: feed.isOnline ? 'live' : 'offline',
                  accent: feed.isOnline
                      ? const Color(0xFF2DD4BF)
                      : const Color(0xFFFB7185),
                ),
              ),
              Positioned(
                bottom: 18,
                left: 18,
                right: 18,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      feed.title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${feed.location}  |  ${feed.viewers} viewers',
                      style: const TextStyle(color: Colors.white60),
                    ),
                    if (feed.alert != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        feed.alert!,
                        style: const TextStyle(
                          color: Color(0xFFFDE68A),
                          fontWeight: FontWeight.w600,
                        ),
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
}

class _AutonomyFieldCard extends StatelessWidget {
  const _AutonomyFieldCard({
    required this.terminal,
    required this.agvs,
  });

  final TerminalStateProvider terminal;
  final List<AgvTelemetry> agvs;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(26),
      color: const Color(0xCC08111F),
      borderRadius: 34,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'AUTONOMY FIELD',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
              ),
              const Spacer(),
              _StatusChip(
                label: terminal.selectedSector,
                accent: const Color(0xFF2DD4BF),
              ),
            ],
          ),
          const SizedBox(height: 20),
          AspectRatio(
            aspectRatio: 1.72,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF051017),
                      Color(0xFF0C1B2A),
                      Color(0xFF06111C),
                    ],
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _TwinGridPainter(
                          activeColor: const Color(0xFF2DD4BF),
                        ),
                      ),
                    ),
                    ...agvs.map(
                      (agv) => Positioned(
                        left: null,
                        right: null,
                        child: FractionalTranslation(
                          translation: const Offset(-0.5, -0.5),
                          child: Align(
                            alignment: Alignment(agv.x * 2 - 1, agv.y * 2 - 1),
                            child: _AgvBeacon(agv: agv),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: agvs
                .map(
                    (agv) => SizedBox(width: 184, child: _AgvCapsule(agv: agv)))
                .toList(growable: false),
          ),
        ],
      ),
    );
  }
}

class _SensorMatrixCard extends StatelessWidget {
  const _SensorMatrixCard({required this.sensors});

  final List<SensorReading> sensors;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(24),
      color: const Color(0xBB111827),
      borderRadius: 34,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SENSOR MATRIX',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 18),
          for (final sensor in sensors) ...[
            _SensorLine(sensor: sensor),
            if (sensor != sensors.last)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Divider(color: Colors.white.withValues(alpha: 0.06)),
              ),
          ],
        ],
      ),
    );
  }
}

class _CraneResponseCard extends StatelessWidget {
  const _CraneResponseCard({required this.cranes});

  final List<CraneTelemetry> cranes;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(24),
      color: const Color(0xCC0A1626),
      borderRadius: 34,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CRANE RESPONSE BAND',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: cranes
                .map(
                  (crane) => SizedBox(
                    width: 280,
                    child: _CranePanel(crane: crane),
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ),
    );
  }
}

class _OperatorConsoleCard extends StatelessWidget {
  const _OperatorConsoleCard({
    required this.auth,
    required this.terminal,
  });

  final AuthProvider auth;
  final TerminalStateProvider terminal;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(26),
      color: const Color(0xCC08111F),
      borderRadius: 34,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'OPERATOR CONSOLE',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: const Color(0xFF2563EB),
                child: Text(
                  _initials(auth.displayName),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    auth.displayName,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Authenticated operator',
                    style: TextStyle(color: Colors.white60),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          _InlineStat(
            label: 'last sync',
            value: terminal.lastSync.shortTimestamp,
          ),
          const SizedBox(height: 10),
          _InlineStat(
            label: 'current sector',
            value: terminal.selectedSector,
          ),
          const SizedBox(height: 10),
          _InlineStat(
            label: 'sync state',
            value: _syncStateLabel(terminal.syncState),
          ),
        ],
      ),
    );
  }
}

class _StackReadinessCard extends StatelessWidget {
  const _StackReadinessCard({required this.terminal});

  final TerminalStateProvider terminal;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final apiService = context.read<PortApiService>();

    final rows = [
      (
        'FastAPI orchestration',
        apiService.backendBaseUrl.contains('127.0.0.1') ||
                apiService.backendBaseUrl.contains('localhost')
            ? 'local API endpoint'
            : 'configured API endpoint',
        const Color(0xFF60A5FA),
      ),
      (
        'Firestore sync layer',
        apiService.isUsingFirebaseData
            ? (terminal.syncState == TerminalSyncState.live
                ? 'live collection snapshots active'
                : 'ready after operator sign-in')
            : 'ready for collection snapshots',
        const Color(0xFF2DD4BF),
      ),
      (
        'RTSP / WebRTC bridge',
        'awaiting edge video source',
        const Color(0xFFF59E0B),
      ),
      (
        'Firebase operator auth',
        auth.isAuthenticated ? 'enabled' : 'unavailable',
        const Color(0xFFFB7185),
      ),
    ];

    return GlassCard(
      padding: const EdgeInsets.all(26),
      color: const Color(0xBB101827),
      borderRadius: 34,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'STACK READINESS',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
          ),
          const SizedBox(height: 10),
          Text(
            'The screen now looks like a command center, and this panel keeps the real backend roadmap visible.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white70,
                  height: 1.45,
                ),
          ),
          const SizedBox(height: 20),
          ...rows.map(
            (row) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _StackLine(
                title: row.$1,
                status: row.$2,
                accent: row.$3,
              ),
            ),
          ),
          const SizedBox(height: 10),
          _MiniBar(
            label: 'stream readiness',
            value: terminal.syncState == TerminalSyncState.live ? 0.74 : 0.48,
            accent: _syncStateColor(terminal.syncState),
          ),
        ],
      ),
    );
  }
}

class _SystemControlsCard extends StatelessWidget {
  const _SystemControlsCard({
    required this.theme,
    required this.notifications,
    required this.onRefresh,
    required this.onSignOut,
  });

  final ThemeProvider theme;
  final NotificationProvider notifications;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    final diagnostics = context.watch<AutomationHubProvider>().diagnostics;

    return GlassCard(
      padding: const EdgeInsets.all(26),
      color: const Color(0xCC0A1626),
      borderRadius: 34,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SYSTEM CONTROLS',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
          ),
          const SizedBox(height: 20),
          SwitchListTile(
            value: theme.isDarkMode,
            onChanged: (_) => theme.toggleTheme(),
            dense: true,
            activeThumbColor: const Color(0xFF38BDF8),
            activeTrackColor: const Color(0xFF38BDF8),
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Theme engine',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              theme.isDarkMode ? 'Dark mode active' : 'Light mode active',
              style: const TextStyle(color: Colors.white60),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              ElevatedButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.sync_rounded),
                label: const Text('Refresh telemetry'),
              ),
              OutlinedButton.icon(
                onPressed: notifications.clear,
                icon: const Icon(Icons.clear_all_rounded),
                label: const Text('Clear notices'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
                ),
              ),
              OutlinedButton.icon(
                onPressed: onSignOut,
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Sign out'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              _StatusChip(
                label: 'network ${diagnostics.networkStatus.toLowerCase()}',
                accent: const Color(0xFF60A5FA),
              ),
              _StatusChip(
                label: 'battery ${diagnostics.batteryLabel}',
                accent: const Color(0xFFF59E0B),
              ),
              _StatusChip(
                label: diagnostics.estimatedRuntime,
                accent: const Color(0xFF2DD4BF),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'Refresh requests the latest telemetry from the connected real-time systems.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white70,
                  height: 1.45,
                ),
          ),
        ],
      ),
    );
  }
}

class _MetricPanel extends StatelessWidget {
  const _MetricPanel({
    required this.eyebrow,
    required this.value,
    required this.change,
    required this.tone,
    required this.chartPoints,
  });

  final String eyebrow;
  final String value;
  final String change;
  final Color tone;
  final List<double> chartPoints;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(22),
      color: const Color(0xBB0A1626),
      borderRadius: 30,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            eyebrow.toUpperCase(),
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            change,
            style: TextStyle(
              color: tone,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 56,
            child: CustomPaint(
              painter: _SparklinePainter(
                color: tone,
                points: chartPoints.isEmpty ? const [1, 1, 1] : chartPoints,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RailCard extends StatelessWidget {
  const _RailCard({
    required this.title,
    required this.accent,
    required this.child,
  });

  final String title;
  final Color accent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(22),
      color: const Color(0xBB111827),
      borderRadius: 30,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.45),
                      blurRadius: 12,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                title.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _RadarStage extends StatelessWidget {
  const _RadarStage({
    required this.stats,
    required this.agvs,
    required this.deliveries,
  });

  final TerminalStats stats;
  final List<AgvTelemetry> agvs;
  final List<DeliveryRecord> deliveries;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.85,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Stack(
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF07111F),
                    Color(0xFF10203D),
                    Color(0xFF08111F),
                  ],
                ),
              ),
            ),
            Positioned.fill(
              child: CustomPaint(
                painter: _TwinGridPainter(activeColor: const Color(0xFF38BDF8)),
              ),
            ),
            for (final agv in agvs)
              Positioned(
                left: null,
                right: null,
                child: FractionalTranslation(
                  translation: const Offset(-0.5, -0.5),
                  child: Align(
                    alignment: Alignment(agv.x * 2 - 1, agv.y * 2 - 1),
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF38BDF8),
                        boxShadow: [
                          BoxShadow(
                            color:
                                const Color(0xFF38BDF8).withValues(alpha: 0.45),
                            blurRadius: 18,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 18,
              top: 18,
              child: _StatusChip(
                label: stats.digitalTwinSector,
                accent: const Color(0xFF38BDF8),
              ),
            ),
            Positioned(
              right: 18,
              top: 18,
              child: _StatusChip(
                label: '${deliveries.length} manifest threads',
                accent: const Color(0xFF2DD4BF),
              ),
            ),
            Positioned(
              left: 18,
              right: 18,
              bottom: 18,
              child: Text(
                'Digital twin overlay ready for live container positions, priority glow states, and future congestion rendering.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white70,
                      height: 1.45,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectorChip extends StatelessWidget {
  const _SectorChip({
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
      borderRadius: BorderRadius.circular(22),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: selected
              ? const LinearGradient(
                  colors: [Color(0xFF1D4ED8), Color(0xFF0EA5E9)],
                )
              : null,
          color: selected ? null : Colors.white.withValues(alpha: 0.06),
          border: Border.all(
            color: selected
                ? Colors.white.withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: selected ? 1 : 0.7),
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _SignalCell extends StatelessWidget {
  const _SignalCell({
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white.withValues(alpha: 0.06),
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
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: accent,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineStat extends StatelessWidget {
  const _InlineStat({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white54),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _MiniBar extends StatelessWidget {
  const _MiniBar({
    required this.label,
    required this.value,
    required this.accent,
  });

  final String label;
  final double value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: LinearProgressIndicator(
            value: value.clamp(0.0, 1.0),
            minHeight: 8,
            color: accent,
            backgroundColor: Colors.white.withValues(alpha: 0.08),
          ),
        ),
      ],
    );
  }
}

class _CompactCountRow extends StatelessWidget {
  const _CompactCountRow({
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
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: Colors.white70),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _PulseRow extends StatelessWidget {
  const _PulseRow({
    required this.color,
    required this.title,
    required this.subtitle,
  });

  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _LivePulse(color: color),
        const SizedBox(width: 10),
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
              Text(
                subtitle,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MapLabel extends StatelessWidget {
  const _MapLabel({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.black.withValues(alpha: 0.28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.accent,
  });

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: accent.withValues(alpha: 0.12),
        border: Border.all(color: accent.withValues(alpha: 0.24)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: accent,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _FeedTile extends StatelessWidget {
  const _FeedTile({required this.event});

  final _FeedEvent event;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 12,
          height: 12,
          margin: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(
            color: event.color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: event.color.withValues(alpha: 0.35),
                blurRadius: 14,
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                event.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                event.detail,
                style: const TextStyle(color: Colors.white70, height: 1.45),
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Text(
          event.timeLabel,
          style: const TextStyle(color: Colors.white38, fontSize: 12),
        ),
      ],
    );
  }
}

class _DeliveryLine extends StatelessWidget {
  const _DeliveryLine({required this.delivery});

  final DeliveryRecord delivery;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              colors: [
                _priorityColor(delivery.priority).withValues(alpha: 0.45),
                _priorityColor(delivery.priority).withValues(alpha: 0.16),
              ],
            ),
          ),
          child: const Icon(Icons.inventory_2_rounded, color: Colors.white),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                delivery.shipmentCode,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${delivery.destination}  |  ${delivery.itemsCount} items',
                style: const TextStyle(color: Colors.white70),
              ),
              if (delivery.exceptionReason != null) ...[
                const SizedBox(height: 6),
                Text(
                  delivery.exceptionReason!,
                  style: const TextStyle(
                    color: Color(0xFFFDE68A),
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _StatusChip(
              label: delivery.status,
              accent: _statusColor(delivery.status),
            ),
            const SizedBox(height: 8),
            Text(
              delivery.expectedGateOutAt.shortTime,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      ],
    );
  }
}

class _AlertLine extends StatelessWidget {
  const _AlertLine({
    required this.title,
    required this.detail,
    required this.accent,
  });

  final String title;
  final String detail;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: accent.withValues(alpha: 0.08),
        border: Border.all(color: accent.withValues(alpha: 0.16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LivePulse(color: accent, size: 10),
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
                  style: const TextStyle(color: Colors.white70, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BerthTile extends StatelessWidget {
  const _BerthTile({
    required this.berthName,
    required this.delivery,
  });

  final String berthName;
  final DeliveryRecord delivery;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _priorityColor(delivery.priority).withValues(alpha: 0.18),
            Colors.white.withValues(alpha: 0.04),
          ],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            berthName,
            style: const TextStyle(
              color: Colors.white54,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            delivery.shipmentCode,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            delivery.destination,
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 16),
          _InlineStat(label: 'status', value: delivery.status),
          const SizedBox(height: 8),
          _InlineStat(label: 'priority', value: delivery.priority),
          const SizedBox(height: 8),
          _InlineStat(label: 'eta', value: delivery.eta.shortTime),
        ],
      ),
    );
  }
}

class _CraneLine extends StatelessWidget {
  const _CraneLine({required this.crane});

  final CraneTelemetry crane;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              crane.id,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Spacer(),
            _StatusChip(
              label: crane.status,
              accent: _statusColor(crane.status),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          '${crane.operatorName}  |  ${crane.loadTons.oneDecimal}t load  |  hook ${crane.hookHeightMeters.oneDecimal}m',
          style: const TextStyle(color: Colors.white70),
        ),
        const SizedBox(height: 12),
        _MiniBar(
          label: 'utilization',
          value: crane.utilization / 100,
          accent: const Color(0xFF38BDF8),
        ),
      ],
    );
  }
}

class _SheetHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(
          flex: 3,
          child: Text(
            'Shipment',
            style:
                TextStyle(color: Colors.white54, fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            'Destination',
            style:
                TextStyle(color: Colors.white54, fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            'ETA',
            style:
                TextStyle(color: Colors.white54, fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            'Status',
            style:
                TextStyle(color: Colors.white54, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _SheetRow extends StatelessWidget {
  const _SheetRow({required this.delivery});

  final DeliveryRecord delivery;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                delivery.shipmentCode,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '${delivery.itemsCount} items',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            delivery.destination,
            style: const TextStyle(color: Colors.white70),
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            delivery.eta.shortTime,
            style: const TextStyle(color: Colors.white70),
          ),
        ),
        Expanded(
          flex: 2,
          child: Align(
            alignment: Alignment.centerLeft,
            child: _StatusChip(
              label: delivery.status,
              accent: _statusColor(delivery.status),
            ),
          ),
        ),
      ],
    );
  }
}

class _AgvBeacon extends StatelessWidget {
  const _AgvBeacon({required this.agv});

  final AgvTelemetry agv;

  @override
  Widget build(BuildContext context) {
    final accent = agv.status == 'Charging'
        ? const Color(0xFFF59E0B)
        : agv.status == 'Idle'
            ? const Color(0xFF94A3B8)
            : const Color(0xFF2DD4BF);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.black.withValues(alpha: 0.35),
        border: Border.all(color: accent.withValues(alpha: 0.32)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.2),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _LivePulse(color: accent, size: 8),
          const SizedBox(width: 8),
          Text(
            agv.id,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _AgvCapsule extends StatelessWidget {
  const _AgvCapsule({required this.agv});

  final AgvTelemetry agv;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: Colors.white.withValues(alpha: 0.05),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                agv.id,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                '${agv.batteryLevel.toStringAsFixed(0)}%',
                style: const TextStyle(
                  color: Color(0xFFFCD34D),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            agv.zone,
            style: const TextStyle(color: Colors.white60),
          ),
          const SizedBox(height: 10),
          _MiniBar(
            label: 'battery',
            value: agv.batteryLevel / 100,
            accent: const Color(0xFFF59E0B),
          ),
        ],
      ),
    );
  }
}

class _SensorLine extends StatelessWidget {
  const _SensorLine({required this.sensor});

  final SensorReading sensor;

  @override
  Widget build(BuildContext context) {
    final accent = sensor.isInNormalRange
        ? const Color(0xFF2DD4BF)
        : const Color(0xFFFB7185);
    final ratio = ((sensor.value - sensor.minNormal) /
            (sensor.maxNormal - sensor.minNormal))
        .clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              sensor.label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Text(
              '${sensor.value.oneDecimal}${sensor.unit}',
              style: TextStyle(color: accent, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _MiniBar(
          label:
              'normal ${sensor.minNormal.oneDecimal}-${sensor.maxNormal.oneDecimal}${sensor.unit}',
          value: ratio,
          accent: accent,
        ),
      ],
    );
  }
}

class _CranePanel extends StatelessWidget {
  const _CranePanel({required this.crane});

  final CraneTelemetry crane;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _statusColor(crane.status).withValues(alpha: 0.18),
            Colors.white.withValues(alpha: 0.04),
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                crane.id,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              _StatusChip(
                label: crane.status,
                accent: _statusColor(crane.status),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${crane.loadTons.oneDecimal}t lift demand',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 6),
          Text(
            '${crane.operatorName} on deck',
            style: const TextStyle(color: Colors.white54),
          ),
          const SizedBox(height: 14),
          _MiniBar(
            label: 'utilization',
            value: crane.utilization / 100,
            accent: const Color(0xFF60A5FA),
          ),
        ],
      ),
    );
  }
}

class _StackLine extends StatelessWidget {
  const _StackLine({
    required this.title,
    required this.status,
    required this.accent,
  });

  final String title;
  final String status;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Colors.white.withValues(alpha: 0.04),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          _LivePulse(color: accent),
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
                  status,
                  style: const TextStyle(color: Colors.white60),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: Colors.white.withValues(alpha: 0.05),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: accent, size: 18),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) {
      return child;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: child,
    );
  }
}

class _CommandBackground extends StatelessWidget {
  const _CommandBackground();

  @override
  Widget build(BuildContext context) {
    return const Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF040712),
                  Color(0xFF07101D),
                  Color(0xFF02060D),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          top: -120,
          right: -40,
          child: _GlowOrb(
            size: 340,
            color: Color(0x6638BDF8),
          ),
        ),
        Positioned(
          top: 120,
          left: -100,
          child: _GlowOrb(
            size: 280,
            color: Color(0x442DD4BF),
          ),
        ),
        Positioned(
          bottom: -120,
          right: 120,
          child: _GlowOrb(
            size: 300,
            color: Color(0x33F472B6),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: _BackdropGridPainter()),
          ),
        ),
      ],
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({
    required this.size,
    required this.color,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color,
              color.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}

class _LivePulse extends StatelessWidget {
  const _LivePulse({
    required this.color,
    this.size = 8,
  });

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: color, blurRadius: 12),
        ],
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.color,
    required this.points,
  });

  final Color color;
  final List<double> points;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) {
      return;
    }

    final minPoint = points.reduce(math.min);
    final maxPoint = points.reduce(math.max);
    final range =
        (maxPoint - minPoint).abs() < 0.0001 ? 1.0 : maxPoint - minPoint;
    final widthStep = size.width / (points.length - 1);

    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = i * widthStep;
      final normalized = (points[i] - minPoint) / range;
      final y = size.height - (normalized * (size.height - 8)) - 4;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: 0.25),
          color.withValues(alpha: 0),
        ],
      ).createShader(Offset.zero & size);

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.points != points;
  }
}

class _TwinGridPainter extends CustomPainter {
  _TwinGridPainter({required this.activeColor});

  final Color activeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 1;

    const columns = 8;
    const rows = 5;

    for (var i = 0; i <= columns; i++) {
      final dx = size.width * i / columns;
      canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), gridPaint);
    }

    for (var i = 0; i <= rows; i++) {
      final dy = size.height * i / rows;
      canvas.drawLine(Offset(0, dy), Offset(size.width, dy), gridPaint);
    }

    final lanePaint = Paint()
      ..color = activeColor.withValues(alpha: 0.18)
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke;

    final lanePath = Path()
      ..moveTo(size.width * 0.05, size.height * 0.72)
      ..quadraticBezierTo(
        size.width * 0.25,
        size.height * 0.6,
        size.width * 0.42,
        size.height * 0.64,
      )
      ..quadraticBezierTo(
        size.width * 0.68,
        size.height * 0.68,
        size.width * 0.94,
        size.height * 0.26,
      );

    canvas.drawPath(lanePath, lanePaint);
  }

  @override
  bool shouldRepaint(covariant _TwinGridPainter oldDelegate) {
    return oldDelegate.activeColor != activeColor;
  }
}

class _BackdropGridPainter extends CustomPainter {
  const _BackdropGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.03)
      ..strokeWidth = 1;

    const step = 48.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }

    final beamPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0),
          const Color(0xFF38BDF8).withValues(alpha: 0.08),
          Colors.white.withValues(alpha: 0),
        ],
      ).createShader(Offset.zero & size)
      ..strokeWidth = 1.6;

    canvas.drawLine(
      Offset(size.width * 0.55, 0),
      Offset(size.width, size.height * 0.45),
      beamPaint,
    );
    canvas.drawLine(
      Offset(0, size.height * 0.8),
      Offset(size.width * 0.42, size.height),
      beamPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _FeedEvent {
  const _FeedEvent({
    required this.title,
    required this.detail,
    required this.timeLabel,
    required this.color,
  });

  final String title;
  final String detail;
  final String timeLabel;
  final Color color;
}

class _NavItem {
  const _NavItem({
    required this.page,
    required this.label,
    required this.compactLabel,
    required this.icon,
  });

  final _CommandPage page;
  final String label;
  final String compactLabel;
  final IconData icon;
}

const _navItems = [
  _NavItem(
    page: _CommandPage.dashboard,
    label: 'Dashboard',
    compactLabel: 'Nexus',
    icon: Icons.grid_view_rounded,
  ),
  _NavItem(
    page: _CommandPage.vessels,
    label: 'Vessels',
    compactLabel: 'Berths',
    icon: Icons.anchor_rounded,
  ),
  _NavItem(
    page: _CommandPage.cctv,
    label: 'CCTV',
    compactLabel: 'Vision',
    icon: Icons.videocam_rounded,
  ),
  _NavItem(
    page: _CommandPage.iot,
    label: 'IoT',
    compactLabel: 'Mesh',
    icon: Icons.memory_rounded,
  ),
  _NavItem(
    page: _CommandPage.reports,
    label: 'Reports',
    compactLabel: 'Reports',
    icon: Icons.assessment_rounded,
  ),
  _NavItem(
    page: _CommandPage.config,
    label: 'Config',
    compactLabel: 'Config',
    icon: Icons.tune_rounded,
  ),
];

List<_FeedEvent> _buildFeedEvents(
  OperationsRepository operations,
  NotificationProvider notifications,
) {
  final deliveryEvents = operations.deliveries.take(2).map(
        (delivery) => _FeedEvent(
          title: 'Manifest ${delivery.shipmentCode} rerouted',
          detail:
              '${delivery.destination} now pacing against ${delivery.status.toLowerCase()} flow.',
          timeLabel: delivery.expectedGateOutAt.shortTime,
          color: _statusColor(delivery.status),
        ),
      );

  final noticeEvents = notifications.items.take(3).map(
        (notice) => _FeedEvent(
          title: notice.title,
          detail: notice.message,
          timeLabel: notice.createdAt.shortTime,
          color: _notificationColor(notice.severity),
        ),
      );

  return [...noticeEvents, ...deliveryEvents].toList(growable: false);
}

String _pageTitle(_CommandPage page) {
  switch (page) {
    case _CommandPage.dashboard:
      return 'Command Center';
    case _CommandPage.vessels:
      return 'Berth Orchestration';
    case _CommandPage.cctv:
      return 'Auto port system';
    case _CommandPage.iot:
      return 'Autonomy Mesh';
    case _CommandPage.reports:
      return 'Reporting Center';
    case _CommandPage.config:
      return 'System Integrity';
  }
}

String _pageSubtitle(_CommandPage page) {
  switch (page) {
    case _CommandPage.dashboard:
      return 'A cinematic live shell for yard flow, predictive pressure, and operator command rhythm.';
    case _CommandPage.vessels:
      return 'Crane pairing, manifest readiness, and berth movement presented like an actual ops board.';
    case _CommandPage.cctv:
      return 'Primary stream spotlight, event overlays, and feed cards with clearer operational hierarchy.';
    case _CommandPage.iot:
      return 'Fleet motion, sensor health, and lift telemetry fused into one darker tactical view.';
    case _CommandPage.reports:
      return 'Time-filtered operational reports, stored telemetry snapshots, and handoff-ready summaries.';
    case _CommandPage.config:
      return 'Operator identity, stack readiness, and control actions for the real backend transition.';
  }
}

String _pageKicker(_CommandPage page) {
  switch (page) {
    case _CommandPage.dashboard:
      return 'Realtime Nexus';
    case _CommandPage.vessels:
      return 'Berth Matrix';
    case _CommandPage.cctv:
      return 'Vision Ops';
    case _CommandPage.iot:
      return 'IoT Mesh';
    case _CommandPage.reports:
      return 'Reporting';
    case _CommandPage.config:
      return 'Control Plane';
  }
}

Color _pageAccent(_CommandPage page) {
  switch (page) {
    case _CommandPage.dashboard:
      return const Color(0xFF38BDF8);
    case _CommandPage.vessels:
      return const Color(0xFF60A5FA);
    case _CommandPage.cctv:
      return const Color(0xFF2DD4BF);
    case _CommandPage.iot:
      return const Color(0xFFF59E0B);
    case _CommandPage.reports:
      return const Color(0xFF2DD4BF);
    case _CommandPage.config:
      return const Color(0xFFF472B6);
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

Color _priorityColor(String priority) {
  switch (priority.toLowerCase()) {
    case 'critical':
      return const Color(0xFFFB7185);
    case 'high':
      return const Color(0xFFF59E0B);
    default:
      return const Color(0xFF60A5FA);
  }
}

Color _statusColor(String status) {
  switch (status.toLowerCase()) {
    case 'completed':
    case 'active':
      return const Color(0xFF2DD4BF);
    case 'in progress':
    case 'delivering':
    case 'standby':
      return const Color(0xFF60A5FA);
    case 'queued':
    case 'charging':
      return const Color(0xFFF59E0B);
    default:
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

String _initials(String value) {
  final parts = value
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) {
    return 'OP';
  }
  if (parts.length == 1) {
    return parts.first
        .substring(0, math.min(2, parts.first.length))
        .toUpperCase();
  }
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}

double _average(Iterable<double> values) {
  final list = values.toList(growable: false);
  if (list.isEmpty) {
    return 0;
  }
  return list.reduce((a, b) => a + b) / list.length;
}
