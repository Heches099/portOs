import '../models/agv_telemetry.dart';
import '../models/camera_feed.dart';
import '../models/crane_telemetry.dart';
import '../models/delivery_record.dart';
import '../models/sensor_reading.dart';
import '../models/terminal_stats.dart';

class DemoPortDataSnapshot {
  const DemoPortDataSnapshot({
    required this.terminalStats,
    required this.agvs,
    required this.cranes,
    required this.deliveries,
    required this.cameraFeeds,
    required this.sensorReadings,
  });

  final TerminalStats terminalStats;
  final List<AgvTelemetry> agvs;
  final List<CraneTelemetry> cranes;
  final List<DeliveryRecord> deliveries;
  final List<CameraFeed> cameraFeeds;
  final List<SensorReading> sensorReadings;
}

class DemoPortData {
  static DemoPortDataSnapshot snapshot({DateTime? now}) {
    final referenceTime = now ?? DateTime.now();

    return DemoPortDataSnapshot(
      terminalStats: TerminalStats.initial().copyWith(lastSync: referenceTime),
      agvs: [
        AgvTelemetry(
          id: 'AGV-01',
          x: 0.18,
          y: 0.28,
          batteryLevel: 92,
          speedKph: 5.4,
          status: 'Charging',
          zone: 'North Loop',
          lastUpdated: referenceTime.subtract(const Duration(seconds: 18)),
        ),
        AgvTelemetry(
          id: 'AGV-02',
          x: 0.44,
          y: 0.62,
          batteryLevel: 76,
          speedKph: 9.2,
          status: 'Delivering',
          zone: 'Bay 02',
          lastUpdated: referenceTime.subtract(const Duration(seconds: 11)),
        ),
        AgvTelemetry(
          id: 'AGV-03',
          x: 0.71,
          y: 0.36,
          batteryLevel: 64,
          speedKph: 7.6,
          status: 'Idle',
          zone: 'Staging',
          lastUpdated: referenceTime.subtract(const Duration(seconds: 7)),
        ),
        AgvTelemetry(
          id: 'AGV-04',
          x: 0.82,
          y: 0.79,
          batteryLevel: 58,
          speedKph: 10.1,
          status: 'Delivering',
          zone: 'Bay 07',
          lastUpdated: referenceTime.subtract(const Duration(seconds: 5)),
        ),
      ],
      cranes: [
        CraneTelemetry(
          id: 'CR-01',
          loadTons: 12.6,
          hookHeightMeters: 18.4,
          utilization: 78,
          status: 'Active',
          operatorName: 'N. Barnes',
          lastUpdated: referenceTime.subtract(const Duration(minutes: 1)),
        ),
        CraneTelemetry(
          id: 'CR-02',
          loadTons: 9.8,
          hookHeightMeters: 15.2,
          utilization: 64,
          status: 'Standby',
          operatorName: 'A. Patel',
          lastUpdated: referenceTime.subtract(const Duration(minutes: 4)),
        ),
      ],
      deliveries: [
        DeliveryRecord(
          containerId: 'del-1',
          shipmentCode: 'JP-2041',
          destination: 'Dock A',
          eta: referenceTime.add(const Duration(minutes: 24)),
          status: 'Queued',
          priority: 'High',
          itemsCount: 18,
          expectedGateOutAt: referenceTime.add(const Duration(minutes: 34)),
          verifiedAt: null,
          exceptionReason: null,
        ),
        DeliveryRecord(
          containerId: 'del-2',
          shipmentCode: 'MX-3177',
          destination: 'Cold Store',
          eta: referenceTime.add(const Duration(minutes: 12)),
          status: 'In Progress',
          priority: 'Critical',
          itemsCount: 7,
          expectedGateOutAt: referenceTime.add(const Duration(minutes: 20)),
          verifiedAt: null,
          exceptionReason: 'Seal verification pending',
        ),
        DeliveryRecord(
          containerId: 'del-3',
          shipmentCode: 'US-4430',
          destination: 'Bay 03',
          eta: referenceTime.subtract(const Duration(minutes: 5)),
          status: 'Completed',
          priority: 'Normal',
          itemsCount: 24,
          expectedGateOutAt: referenceTime.subtract(const Duration(minutes: 2)),
          verifiedAt: referenceTime.subtract(const Duration(minutes: 4)),
          exceptionReason: null,
        ),
        DeliveryRecord(
          containerId: 'del-4',
          shipmentCode: 'CA-1184',
          destination: 'Bay 05',
          eta: referenceTime.add(const Duration(minutes: 38)),
          status: 'Queued',
          priority: 'Normal',
          itemsCount: 13,
          expectedGateOutAt: referenceTime.add(const Duration(minutes: 49)),
          verifiedAt: null,
          exceptionReason: null,
        ),
        DeliveryRecord(
          containerId: 'del-5',
          shipmentCode: 'DE-9901',
          destination: 'Returns',
          eta: referenceTime.add(const Duration(minutes: 16)),
          status: 'In Progress',
          priority: 'High',
          itemsCount: 11,
          expectedGateOutAt: referenceTime.add(const Duration(minutes: 23)),
          verifiedAt: null,
          exceptionReason: 'Documentation review',
        ),
        DeliveryRecord(
          containerId: 'del-6',
          shipmentCode: 'IN-7812',
          destination: 'Bay 08',
          eta: referenceTime.subtract(const Duration(minutes: 17)),
          status: 'Completed',
          priority: 'Normal',
          itemsCount: 29,
          expectedGateOutAt:
              referenceTime.subtract(const Duration(minutes: 13)),
          verifiedAt: referenceTime.subtract(const Duration(minutes: 14)),
          exceptionReason: null,
        ),
      ],
      cameraFeeds: [
        CameraFeed(
          id: 'cam-1',
          title: 'Gate Camera',
          location: 'Inbound Gate',
          isOnline: true,
          viewers: 3,
          lastUpdated: referenceTime.subtract(const Duration(seconds: 15)),
        ),
        CameraFeed(
          id: 'cam-2',
          title: 'Crane Overview',
          location: 'Lift Zone',
          isOnline: true,
          viewers: 5,
          lastUpdated: referenceTime.subtract(const Duration(seconds: 9)),
          alert: 'Queue density rising',
        ),
        CameraFeed(
          id: 'cam-3',
          title: 'Dock South',
          location: 'Dispatch Lane',
          isOnline: false,
          viewers: 0,
          lastUpdated: referenceTime.subtract(const Duration(minutes: 3)),
          alert: 'Signal lost',
        ),
      ],
      sensorReadings: [
        SensorReading(
          id: 'sensor-1',
          label: 'Ambient Temp',
          unit: 'C',
          value: 22.8,
          minNormal: 18,
          maxNormal: 24,
          timestamp: referenceTime.subtract(const Duration(seconds: 30)),
        ),
        SensorReading(
          id: 'sensor-2',
          label: 'Humidity',
          unit: '%',
          value: 58.3,
          minNormal: 40,
          maxNormal: 60,
          timestamp: referenceTime.subtract(const Duration(seconds: 45)),
        ),
        SensorReading(
          id: 'sensor-3',
          label: 'Vibration',
          unit: 'Hz',
          value: 15.4,
          minNormal: 5,
          maxNormal: 12,
          timestamp: referenceTime.subtract(const Duration(seconds: 18)),
        ),
        SensorReading(
          id: 'sensor-4',
          label: 'Voltage',
          unit: 'V',
          value: 231.2,
          minNormal: 220,
          maxNormal: 235,
          timestamp: referenceTime.subtract(const Duration(seconds: 14)),
        ),
      ],
    );
  }

  static List<TerminalStats> terminalTimeline() {
    return [
      TerminalStats(
        teuCounter: 14209,
        efficiency: 98.2,
        activeCranes: 11,
        yardUtilization: 82,
        avgDwellDays: 2.4,
        activeGroundSpots: 426,
        liveSources: 8,
        digitalTwinSector: 'Sector Alpha',
        predictionWindowHours: 4,
        lastSync: DateTime.fromMillisecondsSinceEpoch(0),
      ),
      TerminalStats(
        teuCounter: 14332,
        efficiency: 97.8,
        activeCranes: 10,
        yardUtilization: 84,
        avgDwellDays: 2.3,
        activeGroundSpots: 431,
        liveSources: 8,
        digitalTwinSector: 'Sector Alpha',
        predictionWindowHours: 4,
        lastSync: DateTime.fromMillisecondsSinceEpoch(0),
      ),
      TerminalStats(
        teuCounter: 14418,
        efficiency: 98.5,
        activeCranes: 11,
        yardUtilization: 81,
        avgDwellDays: 2.2,
        activeGroundSpots: 419,
        liveSources: 8,
        digitalTwinSector: 'Sector Beta',
        predictionWindowHours: 4,
        lastSync: DateTime.fromMillisecondsSinceEpoch(0),
      ),
    ];
  }
}
