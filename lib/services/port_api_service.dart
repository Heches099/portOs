import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/agv_telemetry.dart';
import '../models/camera_feed.dart';
import '../models/crane_telemetry.dart';
import '../models/delivery_record.dart';
import '../models/sensor_reading.dart';
import '../models/terminal_stats.dart';
import 'ppe_detection_service.dart';

class PortApiService {
  PortApiService({bool firebaseEnabled = false})
      : _firebaseEnabled = firebaseEnabled,
        _firestore = firebaseEnabled ? FirebaseFirestore.instance : null;

  final bool _firebaseEnabled;
  final FirebaseFirestore? _firestore;

  /// Base URL of the FastAPI backend, shared with the PPE detector.
  String get backendBaseUrl => PortBackend.baseUrl;

  bool get isUsingFirebaseData => _firebaseEnabled && _firestore != null;

  Stream<TerminalStats> getLiveTerminalStats() async* {
    if (!isUsingFirebaseData) {
      yield* const Stream<TerminalStats>.empty();
      return;
    }

    yield* _terminalStatsDocument().snapshots().map((snapshot) {
      final payload = snapshot.data();
      return TerminalStats.fromJson(payload ?? const <String, dynamic>{});
    });
  }

  Stream<List<AgvTelemetry>> watchAgvs() async* {
    if (!isUsingFirebaseData) {
      yield const <AgvTelemetry>[];
      return;
    }

    yield* _watchCollection(
      collection: 'agvs',
      documentIdKey: 'id',
      fromJson: AgvTelemetry.fromJson,
      sort: (items) => items.sort((left, right) => left.id.compareTo(right.id)),
    );
  }

  Stream<List<CraneTelemetry>> watchCranes() async* {
    if (!isUsingFirebaseData) {
      yield const <CraneTelemetry>[];
      return;
    }

    yield* _watchCollection(
      collection: 'cranes',
      documentIdKey: 'id',
      fromJson: CraneTelemetry.fromJson,
      sort: (items) => items.sort((left, right) => left.id.compareTo(right.id)),
    );
  }

  Stream<List<DeliveryRecord>> watchDeliveries() async* {
    if (!isUsingFirebaseData) {
      yield const <DeliveryRecord>[];
      return;
    }

    yield* _watchCollection(
      collection: 'deliveries',
      documentIdKey: 'containerId',
      fromJson: DeliveryRecord.fromJson,
      sort: (items) => items.sort(
        (left, right) => left.containerId.compareTo(right.containerId),
      ),
    );
  }

  Stream<List<CameraFeed>> watchCameraFeeds() async* {
    if (!isUsingFirebaseData) {
      yield const <CameraFeed>[];
      return;
    }

    yield* _watchCollection(
      collection: 'camera_feeds',
      documentIdKey: 'id',
      fromJson: CameraFeed.fromJson,
      sort: (items) => items.sort((left, right) => left.id.compareTo(right.id)),
    );
  }

  Stream<List<SensorReading>> watchSensorReadings() async* {
    if (!isUsingFirebaseData) {
      yield const <SensorReading>[];
      return;
    }

    yield* _watchCollection(
      collection: 'sensor_readings',
      documentIdKey: 'id',
      fromJson: SensorReading.fromJson,
      sort: (items) => items.sort((left, right) => left.id.compareTo(right.id)),
    );
  }

  Future<void> updateContainerRecord(
    String id,
    Map<String, dynamic> data,
  ) async {
    if (!isUsingFirebaseData) {
      return;
    }

    await _collection('deliveries').doc(id).set(data, SetOptions(merge: true));
  }

  CollectionReference<Map<String, dynamic>> _collection(String name) {
    return _firestore!.collection(name);
  }

  DocumentReference<Map<String, dynamic>> _terminalStatsDocument() {
    return _collection('terminal_stats').doc('current');
  }

  Stream<List<T>> _watchCollection<T>({
    required String collection,
    required String documentIdKey,
    required T Function(Map<String, dynamic> json) fromJson,
    required void Function(List<T> items) sort,
  }) {
    return _collection(collection).snapshots().map((snapshot) {
      final items = snapshot.docs.map((doc) {
        final payload = doc.data();
        payload.putIfAbsent(documentIdKey, () => doc.id);
        return fromJson(payload);
      }).toList(growable: false);

      final sortedItems = items.toList(growable: true);
      sort(sortedItems);
      return List<T>.unmodifiable(sortedItems);
    });
  }
}
