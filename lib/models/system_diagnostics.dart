class SystemDiagnostics {
  const SystemDiagnostics({
    required this.deviceLabel,
    required this.networkStatus,
    required this.networkDetail,
    required this.batteryPercent,
    required this.isCharging,
    required this.powerStatus,
    required this.estimatedRuntime,
    required this.lastUpdated,
  });

  final String deviceLabel;
  final String networkStatus;
  final String networkDetail;
  final int? batteryPercent;
  final bool isCharging;
  final String powerStatus;
  final String estimatedRuntime;
  final DateTime lastUpdated;

  factory SystemDiagnostics.initial() {
    return SystemDiagnostics(
      deviceLabel: 'Command device',
      networkStatus: 'Checking',
      networkDetail: 'Collecting adapter data',
      batteryPercent: null,
      isCharging: false,
      powerStatus: 'Awaiting device sensor',
      estimatedRuntime: 'Runtime unavailable',
      lastUpdated: DateTime.now(),
    );
  }

  String get batteryLabel =>
      batteryPercent == null ? 'Unavailable' : '$batteryPercent%';
}
