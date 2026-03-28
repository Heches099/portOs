import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/agv_telemetry.dart';
import '../models/camera_feed.dart';
import '../models/crane_telemetry.dart';
import '../models/delivery_record.dart';
import '../models/sensor_reading.dart';
import '../models/terminal_stats.dart';
import 'demo_port_data.dart';

class PortApiService {
  PortApiService({bool firebaseEnabled = false})
      : _firebaseEnabled = firebaseEnabled,
        _firestore = firebaseEnabled ? FirebaseFirestore.instance : null;

  static const String apiBaseUrl = String.fromEnvironment(
    'PORT_API_BASE_URL',
    defaultValue: 'https://your-fastapi-instance.com',
  );

  final bool _firebaseEnabled;
  final FirebaseFirestore? _firestore;
  Future<void>? _seedFuture;

  bool get isUsingFirebaseData => _firebaseEnabled && _firestore != null;
  bool get isUsingPresentationData => !isUsingFirebaseData;
  bool get isUsingPlaceholderBackend =>
      !isUsingFirebaseData && apiBaseUrl == 'https://your-fastapi-instance.com';

  Future<void> ensureRealtimeSeedData() async {
    if (!isUsingFirebaseData) {
      return;
    }

    _seedFuture ??= _seedRealtimeDataIfNeeded();
    await _seedFuture;
  }

  Stream<TerminalStats> getLiveTerminalStats() async* {
    if (!isUsingFirebaseData) {
      yield* _mockTerminalStats();
      return;
    }

    await ensureRealtimeSeedData();
    yield* _terminalStatsDocument().snapshots().map((snapshot) {
      final payload = snapshot.data();
      if (payload == null || payload.isEmpty) {
        return DemoPortData.snapshot().terminalStats;
      }
      return TerminalStats.fromJson(payload);
    });
  }

  Stream<List<AgvTelemetry>> watchAgvs() async* {
    if (!isUsingFirebaseData) {
      yield DemoPortData.snapshot().agvs;
      return;
    }

    await ensureRealtimeSeedData();
    yield* _watchCollection(
      collection: 'agvs',
      documentIdKey: 'id',
      fromJson: AgvTelemetry.fromJson,
      sort: (items) => items.sort((left, right) => left.id.compareTo(right.id)),
    );
  }

  Stream<List<CraneTelemetry>> watchCranes() async* {
    if (!isUsingFirebaseData) {
      yield DemoPortData.snapshot().cranes;
      return;
    }

    await ensureRealtimeSeedData();
    yield* _watchCollection(
      collection: 'cranes',
      documentIdKey: 'id',
      fromJson: CraneTelemetry.fromJson,
      sort: (items) => items.sort((left, right) => left.id.compareTo(right.id)),
    );
  }

  Stream<List<DeliveryRecord>> watchDeliveries() async* {
    if (!isUsingFirebaseData) {
      yield DemoPortData.snapshot().deliveries;
      return;
    }

    await ensureRealtimeSeedData();
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
      yield DemoPortData.snapshot().cameraFeeds;
      return;
    }

    await ensureRealtimeSeedData();
    yield* _watchCollection(
      collection: 'camera_feeds',
      documentIdKey: 'id',
      fromJson: CameraFeed.fromJson,
      sort: (items) => items.sort((left, right) => left.id.compareTo(right.id)),
    );
  }

  Stream<List<SensorReading>> watchSensorReadings() async* {
    if (!isUsingFirebaseData) {
      yield DemoPortData.snapshot().sensorReadings;
      return;
    }

    await ensureRealtimeSeedData();
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
      await Future<void>.delayed(const Duration(milliseconds: 250));
      return;
    }

    await _collection('deliveries').doc(id).set(data, SetOptions(merge: true));
  }

  Future<void> _seedRealtimeDataIfNeeded() async {
    final firestore = _firestore;
    if (firestore == null) {
      return;
    }

    final checks = await Future.wait([
      _terminalStatsDocument().get(),
      _collection('agvs').limit(1).get(),
      _collection('cranes').limit(1).get(),
      _collection('deliveries').limit(1).get(),
      _collection('camera_feeds').limit(1).get(),
      _collection('sensor_readings').limit(1).get(),
    ]);

    final statsDoc = checks[0] as DocumentSnapshot<Map<String, dynamic>>;
    final collectionsAreEmpty = checks
        .skip(1)
        .cast<QuerySnapshot<Map<String, dynamic>>>()
        .every((snapshot) => snapshot.docs.isEmpty);

    if (statsDoc.exists || !collectionsAreEmpty) {
      return;
    }

    final demoSnapshot = DemoPortData.snapshot();
    final batch = firestore.batch();

    batch.set(_terminalStatsDocument(), demoSnapshot.terminalStats.toJson());

    for (final agv in demoSnapshot.agvs) {
      batch.set(_collection('agvs').doc(agv.id), agv.toJson());
    }
    for (final crane in demoSnapshot.cranes) {
      batch.set(_collection('cranes').doc(crane.id), crane.toJson());
    }
    for (final delivery in demoSnapshot.deliveries) {
      batch.set(
        _collection('deliveries').doc(delivery.containerId),
        delivery.toJson(),
      );
    }
    for (final feed in demoSnapshot.cameraFeeds) {
      batch.set(_collection('camera_feeds').doc(feed.id), feed.toJson());
    }
    for (final reading in demoSnapshot.sensorReadings) {
      batch.set(
        _collection('sensor_readings').doc(reading.id),
        reading.toJson(),
      );
    }

    await batch.commit();
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

  Stream<TerminalStats> _mockTerminalStats() async* {
    final timeline = DemoPortData.terminalTimeline();
    var index = 0;

    while (true) {
      final current = timeline[index % timeline.length];
      yield current.copyWith(lastSync: DateTime.now());
      index++;
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }
}
