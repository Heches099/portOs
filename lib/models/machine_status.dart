import 'model_parsers.dart';

enum MachineStatus { idle, running, maintenance, error, disconnected }

class MachineDetail {
  const MachineDetail({
    required this.id,
    required this.name,
    required this.type,
    this.status = MachineStatus.idle,
    this.location = '',
    this.operatorName = '',
    this.batteryLevel = 0,
    this.speed = 0,
    this.loadCapacity = 0,
    this.currentLoad = 0,
    this.lastMaintenance = '',
    this.notes = '',
    this.lastUpdated,
  });

  final String id;
  final String name;
  final String type;
  final MachineStatus status;
  final String location;
  final String operatorName;
  final double batteryLevel;
  final double speed;
  final double loadCapacity;
  final double currentLoad;
  final String lastMaintenance;
  final String notes;
  final DateTime? lastUpdated;

  factory MachineDetail.fromJson(Map<String, dynamic> json) {
    return MachineDetail(
      id: readString(json['id']),
      name: readString(json['name']),
      type: readString(json['type']),
      status: _parseStatus(json['status']),
      location: readString(json['location']),
      operatorName: readString(json['operatorName']),
      batteryLevel: readDouble(json['batteryLevel']),
      speed: readDouble(json['speed']),
      loadCapacity: readDouble(json['loadCapacity']),
      currentLoad: readDouble(json['currentLoad']),
      lastMaintenance: readString(json['lastMaintenance']),
      notes: readString(json['notes']),
      lastUpdated: json['lastUpdated'] != null ? readDateTime(json['lastUpdated']) : null,
    );
  }

  static MachineStatus _parseStatus(dynamic value) {
    final str = readString(value).toLowerCase();
    switch (str) {
      case 'running':
        return MachineStatus.running;
      case 'maintenance':
        return MachineStatus.maintenance;
      case 'error':
        return MachineStatus.error;
      case 'disconnected':
        return MachineStatus.disconnected;
      default:
        return MachineStatus.idle;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        'status': status.name,
        'location': location,
        'operatorName': operatorName,
        'batteryLevel': batteryLevel,
        'speed': speed,
        'loadCapacity': loadCapacity,
        'currentLoad': currentLoad,
        'lastMaintenance': lastMaintenance,
        'notes': notes,
        if (lastUpdated != null) 'lastUpdated': lastUpdated!.toIso8601String(),
      };
}

class DriveStatus {
  const DriveStatus({this.online = false, this.lastChecked});

  final bool online;
  final DateTime? lastChecked;

  factory DriveStatus.fromJson(Map<String, dynamic> json) {
    return DriveStatus(
      online: json['online'] == true,
      lastChecked: json['lastChecked'] != null ? readDateTime(json['lastChecked']) : null,
    );
  }
}

class AutoModeStatus {
  const AutoModeStatus({
    this.running = false,
    this.cargoRemaining = 0,
    this.cargoTotal = 0,
    this.currentPhase = '',
  });

  final bool running;
  final int cargoRemaining;
  final int cargoTotal;
  final String currentPhase;

  factory AutoModeStatus.fromJson(Map<String, dynamic> json) {
    return AutoModeStatus(
      running: json['running'] == true,
      cargoRemaining: readInt(json['cargoRemaining']),
      cargoTotal: readInt(json['cargoTotal']),
      currentPhase: readString(json['currentPhase']),
    );
  }
}

class MachineActivity {
  const MachineActivity({
    this.status = '',
    this.message = '',
    this.time = '',
  });

  final String status;
  final String message;
  final String time;

  factory MachineActivity.fromJson(Map<String, dynamic> json) {
    return MachineActivity(
      status: readString(json['status']),
      message: readString(json['message']),
      time: readString(json['time']),
    );
  }
}

class DashboardSummary {
  const DashboardSummary({this.machines = const [], this.recentLogs = const []});

  final List<MachineDetail> machines;
  final List<MachineActivity> recentLogs;

  factory DashboardSummary.fromJson(Map<String, dynamic> json) {
    final machineList = (json['machines'] as List<dynamic>?)
            ?.map((m) => MachineDetail.fromJson(m as Map<String, dynamic>))
            .toList() ??
        [];
    final logList = (json['recentLogs'] as List<dynamic>?)
            ?.map((l) => MachineActivity.fromJson(l as Map<String, dynamic>))
            .toList() ??
        [];
    return DashboardSummary(machines: machineList, recentLogs: logList);
  }
}
