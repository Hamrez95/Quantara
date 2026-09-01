import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../domain/auto_trade_models.dart';
import '../domain/private_truth_models.dart';
import 'bitunix_private_ws_protocol.dart';

enum PrivateWsClientState {
  stopped,
  connecting,
  authenticating,
  subscribing,
  active,
  reconnecting,
}

final class PrivateWsClientStatus {
  const PrivateWsClientStatus({
    required this.state,
    required this.atUtc,
    required this.reconnectAttempt,
    this.reason = '',
  });

  final PrivateWsClientState state;
  final DateTime atUtc;
  final int reconnectAttempt;
  final String reason;
}

abstract interface class PrivateWsTransport {
  Future<void> get ready;
  Stream<Object?> get stream;
  void add(Object data);
  Future<void> close();
}

typedef PrivateWsConnector = Future<PrivateWsTransport> Function(Uri uri);
typedef PrivateWsDelay = Future<void> Function(Duration duration);
typedef PrivateWsClock = DateTime Function();
typedef PrivateWsNonceFactory = String Function();

final class WebSocketChannelPrivateTransport implements PrivateWsTransport {
  WebSocketChannelPrivateTransport(this._channel);

  final WebSocketChannel _channel;

  @override
  Future<void> get ready => _channel.ready;

  @override
  Stream<Object?> get stream => _channel.stream;

  @override
  void add(Object data) => _channel.sink.add(data);

  @override
  Future<void> close() async {
    await _channel.sink.close();
  }
}

Future<PrivateWsTransport> connectBitunixPrivateWebSocket(Uri uri) async {
  final channel = WebSocketChannel.connect(uri);
  final transport = WebSocketChannelPrivateTransport(channel);
  await transport.ready;
  return transport;
}

abstract interface class PrivateTruthStreamClient {
  Stream<PrivateTruthEvent> get events;
  Stream<PrivateWsClientStatus> get statuses;
  bool get isRunning;
  int get droppedOrMalformedEvents;

  Future<void> start(BitunixApiCredentials credentials);
  Future<void> stop();
  Future<void> dispose();
}

final class BitunixPrivateWebSocketClient implements PrivateTruthStreamClient {
  BitunixPrivateWebSocketClient({
    PrivateWsConnector? connector,
    PrivateWsDelay? delay,
    PrivateWsClock? clock,
    PrivateWsNonceFactory? nonceFactory,
    this.heartbeatInterval = const Duration(seconds: 3),
    this.staleAfter = const Duration(seconds: 12),
    this.baseReconnectDelay = const Duration(seconds: 1),
    this.maximumReconnectDelay = const Duration(seconds: 15),
    this.handshakeAckTimeout = const Duration(seconds: 2),
  }) : _connector = connector ?? connectBitunixPrivateWebSocket,
       _delay = delay ?? Future<void>.delayed,
       _clock = clock ?? (() => DateTime.now().toUtc()),
       _nonceFactory = nonceFactory ?? _secureNonce;

  final PrivateWsConnector _connector;
  final PrivateWsDelay _delay;
  final PrivateWsClock _clock;
  final PrivateWsNonceFactory _nonceFactory;
  final Duration heartbeatInterval;
  final Duration staleAfter;
  final Duration baseReconnectDelay;
  final Duration maximumReconnectDelay;

  /// Bitunix's official private-WebSocket examples send login and subscribe
  /// frames without waiting for control acknowledgements. Keep a short grace
  /// period for explicit rejections, then advance the transport handshake.
  /// Entry admission still remains fail-closed behind fresh REST verification
  /// in [PrivateTruthCoordinator].
  final Duration handshakeAckTimeout;

  final StreamController<PrivateTruthEvent> _events =
      StreamController<PrivateTruthEvent>.broadcast(sync: true);
  final StreamController<PrivateWsClientStatus> _status =
      StreamController<PrivateWsClientStatus>.broadcast(sync: true);

  PrivateWsTransport? _transport;
  StreamSubscription<Object?>? _subscription;
  Timer? _heartbeat;
  Timer? _handshakeTimer;
  BitunixApiCredentials? _credentials;
  DateTime? _lastInboundAtUtc;
  DateTime? _lastSentAtUtc;
  PrivateWsClientState _state = PrivateWsClientState.stopped;
  bool _running = false;
  bool _connecting = false;
  bool _disposed = false;
  int _generation = 0;
  int _reconnectAttempt = 0;
  int _droppedOrMalformedEvents = 0;

  @override
  Stream<PrivateTruthEvent> get events => _events.stream;
  @override
  Stream<PrivateWsClientStatus> get statuses => _status.stream;
  @override
  bool get isRunning => _running;
  @override
  int get droppedOrMalformedEvents => _droppedOrMalformedEvents;

  @override
  Future<void> start(BitunixApiCredentials credentials) async {
    if (_disposed) throw StateError('Private WebSocket client is disposed.');
    if (!_credentialsValid(credentials)) {
      throw const FormatException('Valid Bitunix credentials are required.');
    }
    _credentials = credentials;
    if (_running) return;
    _running = true;
    _reconnectAttempt = 0;
    await _connect();
  }

  @override
  Future<void> stop() async {
    _running = false;
    _generation++;
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    await _subscription?.cancel();
    _subscription = null;
    await _transport?.close();
    _transport = null;
    _connecting = false;
    _emitStatus(PrivateWsClientState.stopped);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    await stop();
    _disposed = true;
    await _events.close();
    await _status.close();
  }

  Future<void> _connect() async {
    if (!_running || _connecting || _disposed) return;
    final credentials = _credentials;
    if (credentials == null || !_credentialsValid(credentials)) return;
    _connecting = true;
    final generation = ++_generation;
    _emitStatus(
      _reconnectAttempt == 0
          ? PrivateWsClientState.connecting
          : PrivateWsClientState.reconnecting,
    );
    try {
      final transport = await _connector(BitunixPrivateWsProtocol.endpoint);
      if (!_running || generation != _generation) {
        await transport.close();
        return;
      }
      _transport = transport;
      _lastInboundAtUtc = _clock().toUtc();
      _subscription = transport.stream.listen(
        (message) => unawaited(_handleMessage(message, generation)),
        onError: (Object error, StackTrace stackTrace) {
          unawaited(_handleDisconnect(generation, 'transport_error'));
        },
        onDone: () {
          unawaited(_handleDisconnect(generation, 'transport_closed'));
        },
        cancelOnError: false,
      );
      _emitStatus(PrivateWsClientState.authenticating);
      await _send(
        BitunixPrivateWsProtocol.loginFrame(
          credentials: credentials,
          nonce: _nonceFactory(),
          unixSeconds: _clock().toUtc().millisecondsSinceEpoch ~/ 1000,
        ),
        generation,
      );
      _scheduleHandshakeFallback(generation);
      _startHeartbeat(generation);
    } on Object {
      await _handleDisconnect(generation, 'connect_failed');
    } finally {
      if (generation == _generation) _connecting = false;
    }
  }

  Future<void> _handleMessage(Object? raw, int generation) async {
    if (!_running || generation != _generation) return;
    _lastInboundAtUtc = _clock().toUtc();
    final decoded = _decode(raw);
    if (decoded is! Map<String, Object?>) {
      _droppedOrMalformedEvents++;
      return;
    }
    final op = decoded['op']?.toString().toLowerCase() ?? '';
    if (op == 'login') {
      if (!_success(decoded)) {
        await _handleDisconnect(generation, 'authentication_rejected');
        return;
      }
      if (_state == PrivateWsClientState.authenticating) {
        _handshakeTimer?.cancel();
        _handshakeTimer = null;
        await _subscribe(generation);
      }
      return;
    }
    if (op == 'subscribe') {
      if (!_success(decoded)) {
        await _handleDisconnect(generation, 'subscription_rejected');
        return;
      }
      if (_state == PrivateWsClientState.subscribing) {
        _markActive(generation);
      }
      return;
    }
    // Bitunix examples treat an inbound op=ping as the heartbeat response.
    if (op == 'pong' || op == 'ping' || decoded.containsKey('pong')) return;

    final event = BitunixPrivateWsProtocol.parsePush(
      decoded: decoded,
      receivedAtUtc: _clock().toUtc(),
      processedAtUtc: _clock().toUtc(),
    );
    if (event != null && !_events.isClosed) {
      _events.add(event);
    } else if (event == null) {
      _droppedOrMalformedEvents++;
    }
  }

  Future<void> _subscribe(int generation) async {
    if (!_running || generation != _generation) return;
    _emitStatus(PrivateWsClientState.subscribing);
    await _send(BitunixPrivateWsProtocol.subscriptionFrame(), generation);
    if (!_running || generation != _generation) return;
    _scheduleHandshakeFallback(generation);
  }

  void _scheduleHandshakeFallback(int generation) {
    _handshakeTimer?.cancel();
    _handshakeTimer = Timer(handshakeAckTimeout, () {
      unawaited(_advanceHandshakeWithoutAck(generation));
    });
  }

  Future<void> _advanceHandshakeWithoutAck(int generation) async {
    if (!_running || generation != _generation || _disposed) return;
    if (_state == PrivateWsClientState.authenticating) {
      await _subscribe(generation);
      return;
    }
    if (_state == PrivateWsClientState.subscribing) {
      _markActive(generation);
    }
  }

  void _markActive(int generation) {
    if (!_running || generation != _generation) return;
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
    _reconnectAttempt = 0;
    _emitStatus(PrivateWsClientState.active);
  }

  void _startHeartbeat(int generation) {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(heartbeatInterval, (_) {
      if (!_running || generation != _generation) return;
      final now = _clock().toUtc();
      final lastInbound = _lastInboundAtUtc;
      if (lastInbound == null || now.difference(lastInbound) > staleAfter) {
        unawaited(_handleDisconnect(generation, 'heartbeat_stale'));
        return;
      }
      unawaited(
        _send(
          BitunixPrivateWsProtocol.pingFrame(
            now.millisecondsSinceEpoch ~/ 1000,
          ),
          generation,
        ),
      );
    });
  }

  Future<void> _send(Map<String, Object?> frame, int generation) async {
    if (!_running || generation != _generation) return;
    final transport = _transport;
    if (transport == null) return;
    final now = _clock().toUtc();
    final previous = _lastSentAtUtc;
    if (previous != null) {
      const minimumSpacing = Duration(milliseconds: 210);
      final elapsed = now.difference(previous);
      if (elapsed < minimumSpacing) {
        await _delay(minimumSpacing - elapsed);
        if (!_running || generation != _generation) return;
      }
    }
    transport.add(jsonEncode(frame));
    _lastSentAtUtc = _clock().toUtc();
  }

  Future<void> _handleDisconnect(int generation, String reason) async {
    if (generation != _generation) return;
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    await _subscription?.cancel();
    _subscription = null;
    await _transport?.close();
    _transport = null;
    _connecting = false;
    if (!_running || _disposed) return;
    _reconnectAttempt++;
    _emitStatus(PrivateWsClientState.reconnecting, reason: reason);
    final multiplier = 1 << min(_reconnectAttempt - 1, 4);
    final milliseconds = min(
      maximumReconnectDelay.inMilliseconds,
      baseReconnectDelay.inMilliseconds * multiplier,
    );
    final scheduledGeneration = ++_generation;
    await _delay(Duration(milliseconds: milliseconds));
    if (!_running || scheduledGeneration != _generation) return;
    await _connect();
  }

  void _emitStatus(PrivateWsClientState state, {String reason = ''}) {
    _state = state;
    if (_status.isClosed) return;
    _status.add(
      PrivateWsClientStatus(
        state: state,
        atUtc: _clock().toUtc(),
        reconnectAttempt: _reconnectAttempt,
        reason: reason,
      ),
    );
  }

  static bool _credentialsValid(BitunixApiCredentials credentials) =>
      credentials.apiKey.trim().isNotEmpty &&
      credentials.secretKey.trim().isNotEmpty;

  static bool _success(Map<String, Object?> message) {
    final raw = message['code'];
    if (raw == null) return true;
    final code = raw is num ? raw.toInt() : int.tryParse(raw.toString());
    return code == 0;
  }

  static Object? _decode(Object? raw) {
    try {
      if (raw is String) return jsonDecode(raw);
      if (raw is List<int>) return jsonDecode(utf8.decode(raw));
    } on Object {
      return null;
    }
    return null;
  }

  static String _secureNonce() {
    final random = Random.secure();
    return List<int>.generate(
      16,
      (_) => random.nextInt(256),
    ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  }
}
