import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/generated_report.dart';
import '../models/operator_contact.dart';
import '../models/system_diagnostics.dart';
import '../models/terminal_stats.dart';
import 'notification_provider.dart';
import 'operations_repository.dart';

class AutomationHubProvider extends ChangeNotifier {
  AutomationHubProvider() {
    _hydrate();
    unawaited(refreshDiagnostics());
    _diagnosticsTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(refreshDiagnostics()),
    );
  }

  static const _contactsKey = 'automation_hub_contacts';
  static const _reportsKey = 'automation_hub_reports';

  final Battery _battery = Battery();
  final Connectivity _connectivity = Connectivity();

  SharedPreferences? _preferences;
  Timer? _diagnosticsTimer;

  List<OperatorContact> _contacts = List<OperatorContact>.of(_defaultContacts);
  List<GeneratedReport> _reports = const [];
  final List<_OperationalSnapshot> _snapshots = [];
  SystemDiagnostics _diagnostics = SystemDiagnostics.initial();
  bool _isHydrated = false;
  bool _isRefreshingDiagnostics = false;

  List<OperatorContact> get contacts => List.unmodifiable(_contacts);
  List<GeneratedReport> get reports => List.unmodifiable(_reports);
  SystemDiagnostics get diagnostics => _diagnostics;
  bool get isHydrated => _isHydrated;
  bool get isRefreshingDiagnostics => _isRefreshingDiagnostics;
  int get storedSnapshotCount => _snapshots.length;

  Future<void> _hydrate() async {
    final preferences = await SharedPreferences.getInstance();
    _preferences = preferences;

    final contactsRaw = preferences.getString(_contactsKey);
    if (contactsRaw != null && contactsRaw.isNotEmpty) {
      final decoded = jsonDecode(contactsRaw) as List<dynamic>;
      _contacts = decoded
          .map((item) => OperatorContact.fromJson(item as Map<String, dynamic>))
          .toList(growable: false);
    }

    final reportsRaw = preferences.getString(_reportsKey);
    if (reportsRaw != null && reportsRaw.isNotEmpty) {
      final decoded = jsonDecode(reportsRaw) as List<dynamic>;
      _reports = decoded
          .map((item) => GeneratedReport.fromJson(item as Map<String, dynamic>))
          .toList(growable: false);
    }

    _isHydrated = true;
    notifyListeners();
  }

  Future<void> addContact(OperatorContact contact) async {
    _contacts = [contact, ..._contacts];
    notifyListeners();
    await _persistContacts();
  }

  Future<void> removeContact(String id) async {
    _contacts =
        _contacts.where((item) => item.id != id).toList(growable: false);
    notifyListeners();
    await _persistContacts();
  }

  Future<void> clearReports() async {
    _reports = const [];
    notifyListeners();
    await _persistReports();
  }

  void captureSnapshot({
    required TerminalStats stats,
    required OperationsRepository operations,
    required NotificationProvider notifications,
  }) {
    final now = DateTime.now();
    final snapshot = _OperationalSnapshot(
      timestamp: now,
      completedContainers: operations.completedDeliveries,
      queuedContainers: operations.deliveriesByStatus('Queued').length,
      activeAlerts: operations.activeAlerts,
      operatorNotices: notifications.unreadCount,
      averageBatteryLevel: operations.averageBatteryLevel,
      efficiency: stats.efficiency,
      teuCounter: stats.teuCounter,
    );

    if (_snapshots.isNotEmpty &&
        now.difference(_snapshots.last.timestamp) <
            const Duration(minutes: 5)) {
      _snapshots[_snapshots.length - 1] = snapshot;
    } else {
      _snapshots.add(snapshot);
    }

    if (_snapshots.length > 540) {
      _snapshots.removeRange(0, _snapshots.length - 540);
    }

    notifyListeners();
  }

  GeneratedReport generateReport({
    required ReportWindow window,
    required TerminalStats stats,
    required OperationsRepository operations,
    required NotificationProvider notifications,
  }) {
    captureSnapshot(
      stats: stats,
      operations: operations,
      notifications: notifications,
    );

    final endAt = DateTime.now();
    final startAt = _windowStart(window, endAt);
    final relevant = _snapshots
        .where((snapshot) => !snapshot.timestamp.isBefore(startAt))
        .toList(growable: false);

    final deliveredContainers = relevant.fold<int>(
      0,
      (sum, snapshot) => sum + snapshot.completedContainers,
    );
    final queuedContainers = _roundAverage(
      relevant.map((snapshot) => snapshot.queuedContainers.toDouble()),
      fallback: operations.deliveriesByStatus('Queued').length,
    );
    final activeAlerts = _roundAverage(
      relevant.map((snapshot) => snapshot.activeAlerts.toDouble()),
      fallback: operations.activeAlerts,
    );
    final operatorNotices = _roundAverage(
      relevant.map((snapshot) => snapshot.operatorNotices.toDouble()),
      fallback: notifications.unreadCount,
    );
    final averageBatteryLevel = _average(
      relevant.map((snapshot) => snapshot.averageBatteryLevel),
      fallback: operations.averageBatteryLevel,
    );
    final averageEfficiency = _average(
      relevant.map((snapshot) => snapshot.efficiency),
      fallback: stats.efficiency,
    );

    final recommendation = _buildRecommendation(
      activeAlerts: activeAlerts,
      queuedContainers: queuedContainers,
      averageBatteryLevel: averageBatteryLevel,
      diagnostics: _diagnostics,
    );

    final report = GeneratedReport(
      id: 'report-${endAt.microsecondsSinceEpoch}',
      title: '${_windowLabel(window)} Operations Report',
      window: window,
      windowLabel: _windowLabel(window),
      generatedAt: endAt,
      startAt: startAt,
      endAt: endAt,
      summary: _buildSummary(
        deliveredContainers: deliveredContainers,
        queuedContainers: queuedContainers,
        activeAlerts: activeAlerts,
        operatorNotices: operatorNotices,
        averageBatteryLevel: averageBatteryLevel,
        averageEfficiency: averageEfficiency,
      ),
      recommendation: recommendation,
      deliveredContainers: deliveredContainers,
      queuedContainers: queuedContainers,
      activeAlerts: activeAlerts,
      operatorNotices: operatorNotices,
      averageBatteryLevel: averageBatteryLevel,
      averageEfficiency: averageEfficiency,
      networkStatus: _diagnostics.networkStatus,
      powerStatus:
          '${_diagnostics.powerStatus} • ${_diagnostics.estimatedRuntime}',
      sampledMoments: relevant.length,
    );

    _reports = [report, ..._reports].take(16).toList(growable: false);
    notifyListeners();
    unawaited(_persistReports());
    return report;
  }

  Future<void> refreshDiagnostics() async {
    if (_isRefreshingDiagnostics) {
      return;
    }

    _isRefreshingDiagnostics = true;
    notifyListeners();

    try {
      final Object connectivity = await _connectivity.checkConnectivity();
      final adapters = _normalizeConnectivity(connectivity);

      int? batteryLevel;
      BatteryState batteryState = BatteryState.unknown;
      try {
        batteryLevel = await _battery.batteryLevel;
        batteryState = await _battery.batteryState;
      } catch (_) {
        batteryLevel = null;
        batteryState = BatteryState.unknown;
      }

      _diagnostics = SystemDiagnostics(
        deviceLabel: _deviceLabel(),
        networkStatus: _networkStatus(adapters),
        networkDetail: _networkDetail(adapters),
        batteryPercent: batteryLevel,
        isCharging: batteryState == BatteryState.charging,
        powerStatus: _powerStatusLabel(batteryState, batteryLevel),
        estimatedRuntime: _estimatedRuntimeLabel(batteryLevel, batteryState),
        lastUpdated: DateTime.now(),
      );
    } catch (_) {
      _diagnostics = SystemDiagnostics(
        deviceLabel: _deviceLabel(),
        networkStatus: 'Unknown',
        networkDetail: 'Could not read active adapters',
        batteryPercent: null,
        isCharging: false,
        powerStatus: 'Power sensor unavailable',
        estimatedRuntime: 'Runtime unavailable',
        lastUpdated: DateTime.now(),
      );
    } finally {
      _isRefreshingDiagnostics = false;
      notifyListeners();
    }
  }

  Future<void> _persistContacts() async {
    final preferences = _preferences;
    if (preferences == null) {
      return;
    }

    await preferences.setString(
      _contactsKey,
      jsonEncode(
          _contacts.map((item) => item.toJson()).toList(growable: false)),
    );
  }

  Future<void> _persistReports() async {
    final preferences = _preferences;
    if (preferences == null) {
      return;
    }

    await preferences.setString(
      _reportsKey,
      jsonEncode(_reports.map((item) => item.toJson()).toList(growable: false)),
    );
  }

  DateTime _windowStart(ReportWindow window, DateTime now) {
    switch (window) {
      case ReportWindow.hours:
        return now.subtract(const Duration(hours: 24));
      case ReportWindow.days:
        return now.subtract(const Duration(days: 7));
      case ReportWindow.weeks:
        return now.subtract(const Duration(days: 28));
      case ReportWindow.months:
        return DateTime(now.year, now.month - 6, now.day);
      case ReportWindow.yearly:
        return DateTime(now.year - 1, now.month, now.day);
    }
  }

  String _windowLabel(ReportWindow window) {
    switch (window) {
      case ReportWindow.hours:
        return 'Last 24 Hours';
      case ReportWindow.days:
        return 'Last 7 Days';
      case ReportWindow.weeks:
        return 'Last 4 Weeks';
      case ReportWindow.months:
        return 'Last 6 Months';
      case ReportWindow.yearly:
        return 'Last 12 Months';
    }
  }

  String _buildSummary({
    required int deliveredContainers,
    required int queuedContainers,
    required int activeAlerts,
    required int operatorNotices,
    required double averageBatteryLevel,
    required double averageEfficiency,
  }) {
    return 'Delivered $deliveredContainers containers across the selected window while '
        'holding queue pressure near $queuedContainers manifests. Average efficiency '
        'tracked at ${averageEfficiency.toStringAsFixed(1)}%, AGV fleet charge averaged '
        '${averageBatteryLevel.toStringAsFixed(0)}%, and $activeAlerts active alerts with '
        '$operatorNotices operator notices required manual attention.';
  }

  String _buildRecommendation({
    required int activeAlerts,
    required int queuedContainers,
    required double averageBatteryLevel,
    required SystemDiagnostics diagnostics,
  }) {
    if (activeAlerts >= 4) {
      return 'Escalate anomaly review, confirm camera uplinks, and assign a repair operator before automation resumes.';
    }
    if (queuedContainers >= 8) {
      return 'Shift one operator to dispatch supervision and increase quay-to-yard synchronization for the next cycle.';
    }
    if (averageBatteryLevel < 55) {
      return 'Stage AGVs near charge points and avoid stacking new autonomous trips until battery reserve stabilizes.';
    }
    if (diagnostics.networkStatus.toLowerCase() == 'offline') {
      return 'Network health is the current risk. Keep manual contact chains active until device connectivity recovers.';
    }
    return 'Terminal flow is stable. Keep automated routing enabled and use the operator directory for shift handoff coverage.';
  }

  List<ConnectivityResult> _normalizeConnectivity(Object result) {
    if (result is List<ConnectivityResult>) {
      return result;
    }
    if (result is ConnectivityResult) {
      return [result];
    }
    return const [];
  }

  String _networkStatus(List<ConnectivityResult> adapters) {
    if (adapters.isEmpty ||
        adapters.every((item) => item == ConnectivityResult.none)) {
      return 'Offline';
    }
    if (adapters.contains(ConnectivityResult.ethernet)) {
      return 'Ethernet';
    }
    if (adapters.contains(ConnectivityResult.wifi)) {
      return 'Wi-Fi';
    }
    if (adapters.contains(ConnectivityResult.mobile)) {
      return 'Cellular';
    }
    return 'Connected';
  }

  String _networkDetail(List<ConnectivityResult> adapters) {
    if (adapters.isEmpty ||
        adapters.every((item) => item == ConnectivityResult.none)) {
      return 'No hardware adapter currently reports active connectivity.';
    }

    final labels = adapters
        .where((item) => item != ConnectivityResult.none)
        .map(
          (item) => switch (item) {
            ConnectivityResult.bluetooth => 'Bluetooth',
            ConnectivityResult.ethernet => 'Ethernet',
            ConnectivityResult.mobile => 'Cellular',
            ConnectivityResult.vpn => 'VPN',
            ConnectivityResult.wifi => 'Wi-Fi',
            ConnectivityResult.other => 'Other',
            ConnectivityResult.satellite => 'Satellite',
            ConnectivityResult.none => 'Offline',
          },
        )
        .toSet()
        .join(' + ');
    return '$labels link available for telemetry uplink.';
  }

  String _powerStatusLabel(BatteryState state, int? batteryLevel) {
    if (batteryLevel == null) {
      return 'Battery sensor unavailable';
    }

    switch (state) {
      case BatteryState.charging:
        return 'Charging at $batteryLevel%';
      case BatteryState.full:
        return 'External power attached';
      case BatteryState.discharging:
        return 'Running on battery';
      case BatteryState.connectedNotCharging:
        return 'Connected to power';
      case BatteryState.unknown:
        return 'Power state unavailable';
    }
  }

  String _estimatedRuntimeLabel(int? batteryLevel, BatteryState state) {
    if (batteryLevel == null) {
      return 'Runtime unavailable';
    }
    if (state == BatteryState.full) {
      return 'Battery full';
    }
    if (state == BatteryState.charging) {
      final minutesToFull = math.max(8, ((100 - batteryLevel) * 2.1).round());
      return 'Approx. ${_formatDuration(Duration(minutes: minutesToFull))} to full';
    }

    final remainingMinutes = math.max(20, (batteryLevel * 4.1).round());
    return 'Approx. ${_formatDuration(Duration(minutes: remainingMinutes))} remaining';
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours <= 0) {
      return '${minutes}m';
    }
    return '${hours}h ${minutes}m';
  }

  String _deviceLabel() {
    if (kIsWeb) {
      return 'Browser session';
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'Android field tablet';
      case TargetPlatform.iOS:
        return 'iOS field device';
      case TargetPlatform.macOS:
        return 'macOS control station';
      case TargetPlatform.windows:
        return 'Windows control station';
      case TargetPlatform.linux:
        return 'Linux edge console';
      case TargetPlatform.fuchsia:
        return 'Fuchsia control device';
    }
  }

  int _roundAverage(Iterable<double> values, {required int fallback}) {
    final list = values.toList(growable: false);
    if (list.isEmpty) {
      return fallback;
    }
    return (list.reduce((a, b) => a + b) / list.length).round();
  }

  double _average(Iterable<double> values, {required double fallback}) {
    final list = values.toList(growable: false);
    if (list.isEmpty) {
      return fallback;
    }
    return list.reduce((a, b) => a + b) / list.length;
  }

  @override
  void dispose() {
    _diagnosticsTimer?.cancel();
    super.dispose();
  }
}

class _OperationalSnapshot {
  const _OperationalSnapshot({
    required this.timestamp,
    required this.completedContainers,
    required this.queuedContainers,
    required this.activeAlerts,
    required this.operatorNotices,
    required this.averageBatteryLevel,
    required this.efficiency,
    required this.teuCounter,
  });

  final DateTime timestamp;
  final int completedContainers;
  final int queuedContainers;
  final int activeAlerts;
  final int operatorNotices;
  final double averageBatteryLevel;
  final double efficiency;
  final int teuCounter;
}

const _defaultContacts = [
  OperatorContact(
    id: 'contact-1',
    name: 'Miriam Stone',
    role: 'Shift supervisor',
    email: 'miriam.stone@portos.io',
    phoneNumber: '+12025550101',
    whatsAppNumber: '+12025550101',
    telegramHandle: 'miriam_port_ops',
    notes: 'Escalation owner for berth coordination and manual fallback.',
  ),
  OperatorContact(
    id: 'contact-2',
    name: 'Daniel Kato',
    role: 'Electrical repair lead',
    email: 'daniel.kato@portos.io',
    phoneNumber: '+12025550102',
    whatsAppNumber: '+12025550102',
    telegramHandle: 'daniel_repair_ops',
    notes: 'Handles AGV charge faults, camera uplinks, and sensor replacement.',
  ),
];
