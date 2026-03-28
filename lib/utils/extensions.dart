import 'package:intl/intl.dart';

import '../models/sensor_reading.dart';

extension DateFormattingExtension on DateTime {
  String get shortTimestamp => DateFormat('MMM d, HH:mm').format(this);
  String get shortTime => DateFormat('HH:mm').format(this);
}

extension SensorReadingExtension on SensorReading {
  bool get isInNormalRange => value >= minNormal && value <= maxNormal;
}

extension NumberFormattingExtension on num {
  String percentText() => '${toStringAsFixed(0)}%';
  String get oneDecimal => toStringAsFixed(1);
}
