import 'package:cloud_firestore/cloud_firestore.dart';

bool readBool(dynamic value, {bool fallback = false}) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true') {
      return true;
    }
    if (normalized == 'false') {
      return false;
    }
  }
  return fallback;
}

DateTime readDateTime(dynamic value, {DateTime? fallback}) {
  if (value is Timestamp) {
    return value.toDate();
  }
  if (value is DateTime) {
    return value;
  }
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) {
      return parsed;
    }
  }
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value);
  }
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  }
  return fallback ?? DateTime.now();
}

double readDouble(dynamic value, {double fallback = 0}) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value) ?? fallback;
  }
  return fallback;
}

/// Parses a numeric value that may legitimately be absent ("unavailable").
/// Returns null for null, non-numeric, empty, or NaN/Infinity markers.
double? readNullableDouble(dynamic value) {
  if (value is num && value.isFinite) {
    return value.toDouble();
  }
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.toLowerCase() == 'null') {
      return null;
    }
    final parsed = double.tryParse(trimmed);
    if (parsed != null && parsed.isFinite) {
      return parsed;
    }
  }
  return null;
}

int readInt(dynamic value, {int fallback = 0}) {
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value) ?? fallback;
  }
  return fallback;
}

String readString(dynamic value, {String fallback = ''}) {
  return value is String ? value : fallback;
}
