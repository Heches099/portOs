/// Runtime mode of the realtime operational data pipeline.
///
/// Modes are chosen at build time so the production app can be compiled with
/// the live WebSocket pipeline while developers keep using the isolated mock
/// provider without hardware.
///
///   --dart-define=PORT_REALTIME_MODE=websocket   (real backend)
///   --dart-define=PORT_REALTIME_MODE=mock        (default, no hardware)
enum RealtimeMode { mock, websocket }

/// Central realtime configuration.
class RealtimeConfig {
  RealtimeConfig._();

  static const String _modeValue =
      String.fromEnvironment('PORT_REALTIME_MODE', defaultValue: 'mock');

  static const RealtimeMode mode =
      _modeValue == 'websocket' ? RealtimeMode.websocket : RealtimeMode.mock;

  /// How long a machine may go without a telemetry frame before it is
  /// considered stale / offline.
  static const Duration telemetryStaleAfter = Duration(seconds: 10);

  /// Connection retry backoff bounds for the WebSocket client.
  static const Duration wsMinBackoff = Duration(seconds: 1);
  static const Duration wsMaxBackoff = Duration(seconds: 15);

  /// Interval at which the mock provider emits a telemetry frame.
  static const Duration mockTick = Duration(seconds: 2);

  /// Optional configured machine IDs to subscribe to (empty = all).
  static const List<String> watchlist = <String>[];
}