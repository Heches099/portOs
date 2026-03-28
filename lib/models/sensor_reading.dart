import 'model_parsers.dart';

class SensorReading {
  const SensorReading({
    required this.id,
    required this.label,
    required this.unit,
    required this.value,
    required this.minNormal,
    required this.maxNormal,
    required this.timestamp,
  });

  final String id;
  final String label;
  final String unit;
  final double value;
  final double minNormal;
  final double maxNormal;
  final DateTime timestamp;

  factory SensorReading.fromJson(Map<String, dynamic> json) {
    return SensorReading(
      id: readString(json['id']),
      label: readString(json['label']),
      unit: readString(json['unit']),
      value: readDouble(json['value']),
      minNormal: readDouble(json['minNormal']),
      maxNormal: readDouble(json['maxNormal']),
      timestamp: readDateTime(json['timestamp']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'label': label,
      'unit': unit,
      'value': value,
      'minNormal': minNormal,
      'maxNormal': maxNormal,
      'timestamp': timestamp,
    };
  }
}
