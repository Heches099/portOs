import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/delivery_record.dart';
import '../models/terminal_stats.dart';
import '../services/port_api_service.dart';

enum TerminalSyncState { connecting, live, degraded }

class TerminalStateProvider extends ChangeNotifier {
  TerminalStateProvider({required PortApiService apiService})
      : _apiService = apiService {
    if (_apiService.isUsingFirebaseData) {
      _connectionMessage =
          'Firestore telemetry is ready after operator sign-in.';
    } else {
      connect();
    }
  }

  final PortApiService _apiService;
  StreamSubscription<TerminalStats>? _statsSubscription;

  TerminalStats _stats = TerminalStats.initial();
  TerminalSyncState _syncState = TerminalSyncState.connecting;
  String _selectedSector = 'Sector Alpha';
  String _connectionMessage = 'Initializing command center stream...';

  TerminalStats get stats => _stats;
  TerminalSyncState get syncState => _syncState;
  String get selectedSector => _selectedSector;
  String get connectionMessage => _connectionMessage;
  DateTime get lastSync => _stats.lastSync;

  Future<void> connect() async {
    _syncState = TerminalSyncState.connecting;
    _connectionMessage = _apiService.isUsingFirebaseData
        ? 'Connecting to Firestore telemetry stream...'
        : 'Connecting to presentation telemetry stream...';
    notifyListeners();

    await _statsSubscription?.cancel();
    _statsSubscription = _apiService.getLiveTerminalStats().listen(
      (stats) {
        _stats = stats;
        _selectedSector = stats.digitalTwinSector;
        _syncState = TerminalSyncState.live;
        _connectionMessage = _apiService.isUsingFirebaseData
            ? 'Firestore telemetry sync active.'
            : 'Firebase telemetry is unavailable.';
        notifyListeners();
      },
      onError: (_) {
        _syncState = TerminalSyncState.degraded;
        _connectionMessage = 'Realtime telemetry sync degraded.';
        notifyListeners();
      },
    );
  }

  void selectSector(String sector) {
    _selectedSector = sector;
    notifyListeners();
  }

  Future<void> syncDeliveryRecord(DeliveryRecord record) async {
    await _apiService.updateContainerRecord(record.containerId, {
      'shipmentCode': record.shipmentCode,
      'destination': record.destination,
      'status': record.status,
      'priority': record.priority,
      'expectedGateOutAt': record.expectedGateOutAt.toIso8601String(),
    });
  }

  @override
  void dispose() {
    _statsSubscription?.cancel();
    super.dispose();
  }
}
