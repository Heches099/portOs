import 'dart:async';
import 'package:flutter/foundation.dart';

import '../models/agv_telemetry.dart';
import '../models/camera_feed.dart';
import '../models/crane_telemetry.dart';
import '../models/delivery_record.dart';
import '../models/sensor_reading.dart';
import '../services/port_api_service.dart';

class OperationsRepository extends ChangeNotifier {
  OperationsRepository({required PortApiService apiService})
      : _apiService = apiService {
    if (_apiService.isUsingFirebaseData) {
      _isRealtimeMode = false;
      _statusMessage = 'Firestore data is ready after operator sign-in.';
    } else {
      _statusMessage = 'Waiting for Firebase and live operations data.';
    }
  }

  final PortApiService _apiService;
  StreamSubscription<List<AgvTelemetry>>? _agvsSubscription;
  StreamSubscription<List<CraneTelemetry>>? _cranesSubscription;
  StreamSubscription<List<DeliveryRecord>>? _deliveriesSubscription;
  StreamSubscription<List<CameraFeed>>? _cameraFeedsSubscription;
  StreamSubscription<List<SensorReading>>? _sensorReadingsSubscription;

  List<AgvTelemetry> _agvs = const [];
  List<CraneTelemetry> _cranes = const [];
  List<DeliveryRecord> _deliveries = const [];
  List<CameraFeed> _cameraFeeds = const [];
  List<SensorReading> _sensorReadings = const [];
  bool _isRealtimeMode = false;
  String _statusMessage = 'Waiting for live operations data.';

  List<AgvTelemetry> get agvs => List.unmodifiable(_agvs);
  List<CraneTelemetry> get cranes => List.unmodifiable(_cranes);
  List<DeliveryRecord> get deliveries => List.unmodifiable(_deliveries);
  List<CameraFeed> get cameraFeeds => List.unmodifiable(_cameraFeeds);
  List<SensorReading> get sensorReadings => List.unmodifiable(_sensorReadings);
  bool get isRealtimeMode => _isRealtimeMode;
  String get statusMessage => _statusMessage;

  double get averageBatteryLevel => _agvs.isEmpty
      ? 0
      : _agvs.map((item) => item.batteryLevel).reduce((a, b) => a + b) /
          _agvs.length;

  double get craneUtilization => _cranes.isEmpty
      ? 0
      : _cranes.map((item) => item.utilization).reduce((a, b) => a + b) /
          _cranes.length;

  int get activeAlerts =>
      _sensorReadings.where((sensor) => _isOutOfRange(sensor)).length +
      _cameraFeeds.where((feed) => !feed.isOnline || feed.alert != null).length;

  int get completedDeliveries =>
      _deliveries.where((record) => record.status == 'Completed').length;

  Map<String, double> get deliveryStatusBreakdown {
    final counts = <String, double>{
      'Queued': 0,
      'In Progress': 0,
      'Completed': 0,
    };
    for (final record in _deliveries) {
      counts.update(record.status, (value) => value + 1, ifAbsent: () => 1);
    }
    return counts;
  }

  List<double> get agvBatteryTrend =>
      _agvs.map((item) => item.batteryLevel).toList(growable: false);

  List<double> get craneLoadTrend =>
      _cranes.map((item) => item.loadTons).toList(growable: false);

  List<DeliveryRecord> deliveriesByStatus(String status) => _deliveries
      .where((item) => item.status == status)
      .toList(growable: false);

  Future<void> connect() async {
    if (!_apiService.isUsingFirebaseData) {
      _isRealtimeMode = false;
      _statusMessage =
          'Firebase is unavailable. Waiting for live operations data.';
      notifyListeners();
      return;
    }

    await _cancelSubscriptions();
    _isRealtimeMode = true;
    _statusMessage = 'Connecting to Firestore operations streams...';
    notifyListeners();

    try {
      _agvsSubscription = _apiService.watchAgvs().listen(
        (value) {
          _agvs = value;
          _statusMessage = 'Firestore operations streams active.';
          notifyListeners();
        },
        onError: _handleRealtimeError,
      );
      _cranesSubscription = _apiService.watchCranes().listen(
        (value) {
          _cranes = value;
          _statusMessage = 'Firestore operations streams active.';
          notifyListeners();
        },
        onError: _handleRealtimeError,
      );
      _deliveriesSubscription = _apiService.watchDeliveries().listen(
        (value) {
          _deliveries = value;
          _statusMessage = 'Firestore operations streams active.';
          notifyListeners();
        },
        onError: _handleRealtimeError,
      );
      _cameraFeedsSubscription = _apiService.watchCameraFeeds().listen(
        (value) {
          _cameraFeeds = value;
          _statusMessage = 'Firestore operations streams active.';
          notifyListeners();
        },
        onError: _handleRealtimeError,
      );
      _sensorReadingsSubscription = _apiService.watchSensorReadings().listen(
        (value) {
          _sensorReadings = value;
          _statusMessage = 'Firestore operations streams active.';
          notifyListeners();
        },
        onError: _handleRealtimeError,
      );
    } catch (error) {
      _handleRealtimeError(error);
    }
  }

  Future<void> refreshData() async {
    if (_apiService.isUsingFirebaseData) {
      await connect();
      return;
    }
    _statusMessage =
        'Firebase is unavailable. Waiting for live operations data.';
    notifyListeners();
  }

  bool _isOutOfRange(SensorReading reading) =>
      reading.value < reading.minNormal || reading.value > reading.maxNormal;

  Future<void> _cancelSubscriptions() async {
    await Future.wait([
      _agvsSubscription?.cancel() ?? Future<void>.value(),
      _cranesSubscription?.cancel() ?? Future<void>.value(),
      _deliveriesSubscription?.cancel() ?? Future<void>.value(),
      _cameraFeedsSubscription?.cancel() ?? Future<void>.value(),
      _sensorReadingsSubscription?.cancel() ?? Future<void>.value(),
    ]);

    _agvsSubscription = null;
    _cranesSubscription = null;
    _deliveriesSubscription = null;
    _cameraFeedsSubscription = null;
    _sensorReadingsSubscription = null;
  }

  void _handleRealtimeError(Object error) {
    _isRealtimeMode = false;
    _statusMessage = 'Realtime Firestore data is unavailable.';
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_cancelSubscriptions());
    super.dispose();
  }
}
