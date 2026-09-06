import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/realtime_config.dart';
import '../models/realtime_message.dart';
import '../models/realtime_telemetry.dart';
import 'ppe_detection_service.dart';

/// Incoming typed frames parsed from the realtime gateway.
sealed class RealtimeServerMessage {
  const RealtimeServerMessage();
}

class TelemetryMessage extends RealtimeServerMessage {
  const TelemetryMessage(this.telemetry);
  final MachineRealtimeTelemetry telemetry;
}

class CommandAckMessage extends RealtimeServerMessage {
  const CommandAckMessage(this.ack);
  final CommandAck ack;
}

class EventMessage extends RealtimeServerMessage {
  const EventMessage(this.event);
  final MachineEvent event;
}

class GatewayConnectionMessage extends RealtimeServerMessage {
  const GatewayConnectionMessage(this.online, [this.detail = '']);
  final bool online;
  final String detail;
}

/// Reusable WebSocket client for the FastAPI machine realtime hub.
///
/// Responsibilities: connect, subscribe to machine(s), parse frames safely,
/// auto-reconnect with back-off, expose connection state, and close cleanly.
/// A single instance is shared by the whole app - never one per widget build.
class MachineRealtimeService {
  MachineRealtimeService({String? baseWsUrl})
      : _baseWsUrl = baseWsUrl ?? _defaultWsUrl();

  final String _baseWsUrl;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;

  final StreamController<RealtimeServerMessage> _messages =
      StreamController<RealtimeServerMessage>.broadcast();

  final StreamController<MachineConnectionState> _connections =
      StreamController<MachineConnectionState>.broadcast();

  MachineConnectionState _connectionState = MachineConnectionState.offline;
  MachineConnectionState get connectionState => _connectionState;

  final Set<String> _subscribed = <String>{};
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  bool _disposed = false;
  bool _manuallyClosed = false;

  Stream<RealtimeServerMessage> get messages => _messages.stream;
  Stream<MachineConnectionState> get connections => _connections.stream;
  bool get isConnected => _connectionState == MachineConnectionState.online;

  static String _defaultWsUrl() {
    final httpUrl = PortBackend.baseUrl;
    if (httpUrl.startsWith('https://')) {
      return httpUrl.replaceFirst('https://', 'wss://');
    }
    if (httpUrl.startsWith('http://')) {
      return httpUrl.replaceFirst('http://', 'ws://');
    }
    return 'ws://$httpUrl';
  }

  /// Opens the connection (no-op if already connected).
  Future<void> connect() async {
    if (_disposed) return;
    _manuallyClosed = false;
    _reconnectTimer?.cancel();
    if (_channel != null) {
      return;
    }

    _setState(MachineConnectionState.connecting);

    try {
      final query = _subscribed.isEmpty
          ? ''
          : '?machine_ids=${_subscribed.join(',')}';
      final uri = Uri.parse('$_baseWsUrl/ws/machines$query');
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;

      _subscription?.cancel();
      _subscription = channel.stream.listen(
        _onFrame,
        onError: (_) => _onConnectionLost(),
        onDone: _onConnectionLost,
        cancelOnError: true,
      );

      _heartbeatTimer?.cancel();
      _heartbeatTimer = Timer.periodic(const Duration(seconds: 20), (_) {
        _send({'type': 'ping'});
      });
    } catch (_) {
      _onConnectionLost();
    }
  }

  void _onFrame(dynamic frame) {
    if (frame is! String) return;
    dynamic decoded;
    try {
      decoded = jsonDecode(frame);
    } on FormatException {
      return; // malformed frame -> ignore safely
    }
    if (decoded is! Map<String, dynamic>) return;

    final type = decoded['type'];

    switch (type) {
      case 'welcome' || 'pong':
        if (_connectionState != MachineConnectionState.online) {
          _setState(MachineConnectionState.online);
        }
        _messages.add(GatewayConnectionMessage(true, 'connected'));
      case 'telemetry':
        try {
          _messages.add(TelemetryMessage(
            MachineRealtimeTelemetry.fromJson(decoded),
          ));
        } catch (_) {}
      case 'command_ack':
        try {
          _messages.add(CommandAckMessage(CommandAck.fromJson(decoded)));
        } catch (_) {}
      case 'machine_event':
        try {
          _messages.add(EventMessage(MachineEvent.fromJson(decoded)));
        } catch (_) {}
      case 'disconnect':
        _messages.add(GatewayConnectionMessage(false, 'gateway disconnect'));
      default:
        return;
    }
  }

  void _onConnectionLost() {
    _subscription?.cancel();
    _subscription = null;
    _channel = null;
    _heartbeatTimer?.cancel();
    if (_manuallyClosed || _disposed) return;

    _setState(MachineConnectionState.connecting);
    final backoff = RealtimeConfig.wsMinBackoff;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(backoff, () {
      if (!_disposed && !_manuallyClosed) {
        connect();
      }
    });
  }

  void _setState(MachineConnectionState state) {
    if (_connectionState == state) return;
    _connectionState = state;
    if (!_connections.isClosed) {
      _connections.add(state);
    }
  }

  Future<void> subscribe(List<String> machineIds) async {
    final fresh = machineIds.where(_subscribed.add).toList();
    if (fresh.isNotEmpty) {
      _send({'type': 'subscribe', 'machine_ids': fresh});
    }
  }

  Future<void> unsubscribe(List<String> machineIds) async {
    final removed = machineIds.where(_subscribed.remove).toList();
    if (removed.isNotEmpty) {
      _send({'type': 'unsubscribe', 'machine_ids': removed});
    }
  }

  void _send(Map<String, dynamic> payload) {
    final channel = _channel;
    if (channel == null) return;
    try {
      channel.sink.add(jsonEncode(payload));
    } catch (_) {}
  }

  void dispose() {
    _disposed = true;
    _manuallyClosed = true;
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    _subscription?.cancel();
    _subscription = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _messages.close();
    _connections.close();
  }
}