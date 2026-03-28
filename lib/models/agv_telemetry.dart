import 'model_parsers.dart';

class AgvTelemetry {
  const AgvTelemetry({
    required this.id,
    required this.x,
    required this.y,
    required this.batteryLevel,
    required this.speedKph,
    required this.status,
    required this.zone,
    required this.lastUpdated,
  });

  final String id;
  final double x;
  final double y;
  final double batteryLevel;
  final double speedKph;
  final String status;
  final String zone;
  final DateTime lastUpdated;

  factory AgvTelemetry.fromJson(Map<String, dynamic> json) {
    return AgvTelemetry(
      id: readString(json['id']),
      x: readDouble(json['x']),
      y: readDouble(json['y']),
      batteryLevel: readDouble(json['batteryLevel']),
      speedKph: readDouble(json['speedKph']),
      status: readString(json['status']),
      zone: readString(json['zone']),
      lastUpdated: readDateTime(json['lastUpdated']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'x': x,
      'y': y,
      'batteryLevel': batteryLevel,
      'speedKph': speedKph,
      'status': status,
      'zone': zone,
      'lastUpdated': lastUpdated,
    };
  }
}
