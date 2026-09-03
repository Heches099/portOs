import 'model_parsers.dart';

class TerminalStats {
  const TerminalStats({
    required this.teuCounter,
    required this.efficiency,
    required this.activeCranes,
    required this.yardUtilization,
    required this.avgDwellDays,
    required this.activeGroundSpots,
    required this.liveSources,
    required this.digitalTwinSector,
    required this.predictionWindowHours,
    required this.lastSync,
  });

  final int teuCounter;
  final double efficiency;
  final int activeCranes;
  final int yardUtilization;
  final double avgDwellDays;
  final int activeGroundSpots;
  final int liveSources;
  final String digitalTwinSector;
  final int predictionWindowHours;
  final DateTime lastSync;

  factory TerminalStats.initial() {
    return TerminalStats(
      teuCounter: 0,
      efficiency: 0,
      activeCranes: 0,
      yardUtilization: 0,
      avgDwellDays: 0,
      activeGroundSpots: 0,
      liveSources: 0,
      digitalTwinSector: '--',
      predictionWindowHours: 0,
      lastSync: DateTime.now(),
    );
  }

  factory TerminalStats.fromJson(Map<String, dynamic> json) {
    final avgDwellValue = json['avg_dwell_days'] ?? json['avgDwellDays'] ?? 0;
    final lastSyncRaw = json['last_sync'] ?? json['lastSync'];

    return TerminalStats(
      teuCounter:
          readInt(json['teu_counter'] ?? json['teuCounter'] ?? json['teu']),
      efficiency: readDouble(json['efficiency']),
      activeCranes: readInt(json['active_cranes'] ?? json['activeCranes']),
      yardUtilization:
          readInt(json['yard_utilization'] ?? json['yardUtilization']),
      avgDwellDays: readDouble(avgDwellValue),
      activeGroundSpots:
          readInt(json['active_ground_spots'] ?? json['activeGroundSpots']),
      liveSources: readInt(json['live_sources'] ?? json['liveSources']),
      digitalTwinSector: readString(
        json['digital_twin_sector'] ?? json['digitalTwinSector'],
        fallback: '--',
      ),
      predictionWindowHours: readInt(
        json['prediction_window_hours'] ?? json['predictionWindowHours'],
      ),
      lastSync: readDateTime(lastSyncRaw),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'teuCounter': teuCounter,
      'efficiency': efficiency,
      'activeCranes': activeCranes,
      'yardUtilization': yardUtilization,
      'avgDwellDays': avgDwellDays,
      'activeGroundSpots': activeGroundSpots,
      'liveSources': liveSources,
      'digitalTwinSector': digitalTwinSector,
      'predictionWindowHours': predictionWindowHours,
      'lastSync': lastSync,
    };
  }

  TerminalStats copyWith({
    int? teuCounter,
    double? efficiency,
    int? activeCranes,
    int? yardUtilization,
    double? avgDwellDays,
    int? activeGroundSpots,
    int? liveSources,
    String? digitalTwinSector,
    int? predictionWindowHours,
    DateTime? lastSync,
  }) {
    return TerminalStats(
      teuCounter: teuCounter ?? this.teuCounter,
      efficiency: efficiency ?? this.efficiency,
      activeCranes: activeCranes ?? this.activeCranes,
      yardUtilization: yardUtilization ?? this.yardUtilization,
      avgDwellDays: avgDwellDays ?? this.avgDwellDays,
      activeGroundSpots: activeGroundSpots ?? this.activeGroundSpots,
      liveSources: liveSources ?? this.liveSources,
      digitalTwinSector: digitalTwinSector ?? this.digitalTwinSector,
      predictionWindowHours:
          predictionWindowHours ?? this.predictionWindowHours,
      lastSync: lastSync ?? this.lastSync,
    );
  }
}
