enum ReportWindow { hours, days, weeks, months, yearly }

class GeneratedReport {
  const GeneratedReport({
    required this.id,
    required this.title,
    required this.window,
    required this.windowLabel,
    required this.generatedAt,
    required this.startAt,
    required this.endAt,
    required this.summary,
    required this.recommendation,
    required this.deliveredContainers,
    required this.queuedContainers,
    required this.activeAlerts,
    required this.operatorNotices,
    required this.averageBatteryLevel,
    required this.averageEfficiency,
    required this.networkStatus,
    required this.powerStatus,
    required this.sampledMoments,
  });

  final String id;
  final String title;
  final ReportWindow window;
  final String windowLabel;
  final DateTime generatedAt;
  final DateTime startAt;
  final DateTime endAt;
  final String summary;
  final String recommendation;
  final int deliveredContainers;
  final int queuedContainers;
  final int activeAlerts;
  final int operatorNotices;
  final double averageBatteryLevel;
  final double averageEfficiency;
  final String networkStatus;
  final String powerStatus;
  final int sampledMoments;

  factory GeneratedReport.fromJson(Map<String, dynamic> json) {
    return GeneratedReport(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Operations report',
      window: ReportWindow.values.firstWhere(
        (item) => item.name == json['window'],
        orElse: () => ReportWindow.hours,
      ),
      windowLabel: json['windowLabel'] as String? ?? 'Last 24 hours',
      generatedAt: DateTime.tryParse(json['generatedAt'] as String? ?? '') ??
          DateTime.now(),
      startAt:
          DateTime.tryParse(json['startAt'] as String? ?? '') ?? DateTime.now(),
      endAt:
          DateTime.tryParse(json['endAt'] as String? ?? '') ?? DateTime.now(),
      summary: json['summary'] as String? ?? '',
      recommendation: json['recommendation'] as String? ?? '',
      deliveredContainers: json['deliveredContainers'] as int? ?? 0,
      queuedContainers: json['queuedContainers'] as int? ?? 0,
      activeAlerts: json['activeAlerts'] as int? ?? 0,
      operatorNotices: json['operatorNotices'] as int? ?? 0,
      averageBatteryLevel:
          (json['averageBatteryLevel'] as num?)?.toDouble() ?? 0,
      averageEfficiency: (json['averageEfficiency'] as num?)?.toDouble() ?? 0,
      networkStatus: json['networkStatus'] as String? ?? '--',
      powerStatus: json['powerStatus'] as String? ?? '--',
      sampledMoments: json['sampledMoments'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'window': window.name,
      'windowLabel': windowLabel,
      'generatedAt': generatedAt.toIso8601String(),
      'startAt': startAt.toIso8601String(),
      'endAt': endAt.toIso8601String(),
      'summary': summary,
      'recommendation': recommendation,
      'deliveredContainers': deliveredContainers,
      'queuedContainers': queuedContainers,
      'activeAlerts': activeAlerts,
      'operatorNotices': operatorNotices,
      'averageBatteryLevel': averageBatteryLevel,
      'averageEfficiency': averageEfficiency,
      'networkStatus': networkStatus,
      'powerStatus': powerStatus,
      'sampledMoments': sampledMoments,
    };
  }
}
