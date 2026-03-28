import 'model_parsers.dart';

class CraneTelemetry {
  const CraneTelemetry({
    required this.id,
    required this.loadTons,
    required this.hookHeightMeters,
    required this.utilization,
    required this.status,
    required this.operatorName,
    required this.lastUpdated,
  });

  final String id;
  final double loadTons;
  final double hookHeightMeters;
  final double utilization;
  final String status;
  final String operatorName;
  final DateTime lastUpdated;

  factory CraneTelemetry.fromJson(Map<String, dynamic> json) {
    return CraneTelemetry(
      id: readString(json['id']),
      loadTons: readDouble(json['loadTons']),
      hookHeightMeters: readDouble(json['hookHeightMeters']),
      utilization: readDouble(json['utilization']),
      status: readString(json['status']),
      operatorName: readString(json['operatorName']),
      lastUpdated: readDateTime(json['lastUpdated']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'loadTons': loadTons,
      'hookHeightMeters': hookHeightMeters,
      'utilization': utilization,
      'status': status,
      'operatorName': operatorName,
      'lastUpdated': lastUpdated,
    };
  }
}
