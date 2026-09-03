import 'model_parsers.dart';

class PpeDetection {
  const PpeDetection({
    required this.className,
    required this.confidence,
    this.classId = 0,
    this.boundingBox = const <String, double>{},
  });

  final int classId;
  final String className;
  final double confidence;
  final Map<String, double> boundingBox;

  factory PpeDetection.fromJson(Map<String, dynamic> json) {
    final rawBox = json['boundingBox'];
    final box = <String, double>{};
    if (rawBox is Map) {
      for (final entry in rawBox.entries) {
        box[entry.key.toString()] = readDouble(entry.value);
      }
    }

    return PpeDetection(
      classId: readInt(json['classId']),
      className: readString(json['className'], fallback: 'object'),
      confidence: readDouble(json['confidence']),
      boundingBox: box,
    );
  }
}

class PpeDetectionResult {
  const PpeDetectionResult({
    required this.detections,
    required this.counts,
    required this.imageWidth,
    required this.imageHeight,
    required this.analyzedAt,
  });

  static const List<String> trackedClasses = <String>[
    'helmet',
    'vest',
    'head',
  ];

  final List<PpeDetection> detections;
  final Map<String, int> counts;
  final int imageWidth;
  final int imageHeight;
  final DateTime analyzedAt;

  int countFor(String className) => counts[className] ?? 0;

  bool isDetected(String className) => countFor(className) > 0;

  double get topConfidence {
    if (detections.isEmpty) {
      return 0;
    }
    return detections
        .map((detection) => detection.confidence)
        .reduce((left, right) => left > right ? left : right);
  }

  List<String> get extraClassNames {
    final extras = counts.keys
        .where((name) => !trackedClasses.contains(name))
        .toList()
      ..sort();
    return extras;
  }

  factory PpeDetectionResult.fromJson(Map<String, dynamic> json) {
    final rawDetections = json['detections'];
    final detections = <PpeDetection>[];
    if (rawDetections is List) {
      for (final entry in rawDetections) {
        if (entry is Map<String, dynamic>) {
          detections.add(PpeDetection.fromJson(entry));
        }
      }
    }

    final rawCounts = json['counts'];
    final counts = <String, int>{};
    if (rawCounts is Map) {
      for (final entry in rawCounts.entries) {
        counts[entry.key.toString()] = readInt(entry.value);
      }
    }

    return PpeDetectionResult(
      detections: detections,
      counts: counts,
      imageWidth: readInt(json['imageWidth']),
      imageHeight: readInt(json['imageHeight']),
      analyzedAt: DateTime.now(),
    );
  }
}
