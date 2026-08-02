import 'dart:async';
import 'dart:math' as math;

import '../domain/bitunix_public_stream_models.dart';
import 'bitunix_public_stream_codec.dart';
import 'bitunix_subscription_planner.dart';
import 'bitunix_web_socket_adapter.dart';

enum BitunixPublicConnectionState {
  idle,
  connecting,
  live,
  backingOff,
  stopped,
}

enum BitunixPublicStreamFaultKind {
  connect,
  transport,
  malformedPayload,
  silenceTimeout,
  callback,
}

final class BitunixPublicStreamFault {
  const BitunixPublicStreamFault({
    required this.kind,
    required this.message,
    required this.occurredAtUtc,
    required this.shardIndex,
  });

  final BitunixPublicStreamFaultKind kind;
  final String message;
  final DateTime occurredAtUtc;
  final int shardIndex;
}

final class BitunixReconnectPolicy {
  BitunixReconnectPolicy({
    this.baseDelay = const Duration(seconds: 1),
    this.maximumDelay = const Duration(seconds: 30),
    this.maximumJitter = const Duration(milliseconds: 250),
  }) {
    if (baseDelay <= Duration.zero) {
      throw ArgumentError.value(baseDelay, 'baseDelay');
    }
    if (maximumDelay < baseDelay) {
      throw ArgumentError.value(maximumDelay, 'maximumDelay');
    }
    if (maximumJitter < Duration.zero) {
      throw ArgumentError.value(maximumJitter, 'maximumJitter');
    }
  }

  final Duration baseDelay;
  final Duration maximumDelay;
  final Duration maximumJitter;

  Duration delayFor({required int attempt, required int shardIndex}) {
    if (attempt < 0) throw ArgumentError.value(attempt, 'attempt');
    if (shardIndex < 0) throw ArgumentError.value(shardIndex, 'shardIndex');

    var milliseconds = baseDelay.inMilliseconds;
    for (var index = 0; index < attempt; index++) {
      if (milliseconds >= maximumDelay.inMilliseconds) break;
      milliseconds = math.min(milliseconds * 2, maximumDelay.inMilliseconds);
    }
    final jitterRange = maximumJitter.inMilliseconds;
    final jitter = jitterRange == 0
        ? 0
        : ((shardIndex * 73) + (attempt * 31)) % (jitterRange + 1);
    return Duration(
      milliseconds: math.min(
        milliseconds + jitter,
        maximumDelay.inMilliseconds + jitterRange,
      ),
    );
  }
}

final class BitunixPublicStreamConfig {
  BitunixPublicStreamConfig({
    String endpoint = 'wss://fapi.bitunix.com/public/',
    this.connectTimeout = const Duration(seconds: 10),
    this.pingInterval = const Duration(seconds: 20),
    this.silenceTimeout = const Duration(seconds: 45),
    this.malformedPayloadBudget = 3,
  }) : endpoint = endpoint.trim(),
       endpointUri = _parseEndpoint(endpoint) {
    if (connectTimeout <= Duration.zero) {
      throw ArgumentError.value(connectTimeout, 'connectTimeout');
    }
    if (pingInterval <= Duration.zero) {
      throw ArgumentError.value(pingInterval, 'pingInterval');
    }
    if (silenceTimeout <= pingInterval) {
      throw ArgumentError.value(silenceTimeout, 'silenceTimeout');
    }
    if (malformedPayloadBudget < 1) {
      throw ArgumentError.value(
        malformedPayloadBudget,
        'malformedPayloadBudget',
      );
    }
  }

  final String endpoint;
  final Uri endpointUri;
  final Duration connectTimeout;
  final Duration pingInterval;
  final Duration silenceTimeout;
  final int malformedPayloadBudget;

  static Uri _parseEndpoint(String value) {
    final normalized = value.trim();
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        uri.scheme != 'wss' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      throw FormatException('Invalid Bitunix public WebSocket endpoint.');
    }
    return uri;
  }
}

typedef BitunixUtcClock = DateTime Function();
typedef BitunixAsyncDelay = Future<void> Function(Duration duration);
typedef BitunixStreamEventHandler =
    FutureOr<void> Function(BitunixPublicStreamEvent event);
typedef BitunixStreamFaultHandler =
    FutureOr<void> Function(BitunixPublicStreamFault fault);
typedef BitunixConnectionStateHandler =
    FutureOr<void> Function(BitunixPublicConnectionState state);

final class BitunixPublicStreamConnection {
  BitunixPublicStreamConnection({
    required this.shard,
    required this.connector,
    required this.onEvent,
    required this.onFault,
    required this.onState,
    BitunixPublicStreamConfig? config,
    BitunixReconnectPolicy? reconnectPolicy,
    BitunixUtcClock? clock,
    BitunixAsyncDelay? delay,
  }) : config = config ?? BitunixPublicStreamConfig(),
       reconnectPolicy = reconnectPolicy ?? BitunixReconnectPolicy(),
       clock = clock ?? _utcNow,
       delay = delay ?? _delay;

  final BitunixSubscriptionShard shard;
  final BitunixWebSocketConnector connector;
  final BitunixStreamEventHandler onEvent;
  final BitunixStreamFaultHandler onFault;
  final BitunixConnectionStateHandler onState;
  final BitunixPublicStreamConfig config;
  final BitunixReconnectPolicy reconnectPolicy;
  final BitunixUtcClock clock;
  final BitunixAsyncDelay delay;

  final BitunixOutboundMessageSchedule _outboundSchedule =
      BitunixOutboundMessageSchedule();
  Future<void> _outboundTail = Future.value();
  BitunixWebSocket? _socket;
  Timer? _heartbeatTimer;
  DateTime? _lastMessageAtUtc;
  var _running = false;
  var _stopping = false;
  var _validPayloadSeen = false;

  BitunixPublicConnectionState _state = BitunixPublicConnectionState.idle;

  BitunixPublicConnectionState get state => _state;

  Future<void> run() async {
    if (_running) throw StateError('This Bitunix stream is already running.');
    _running = true;
    _stopping = false;
    var attempt = 0;

    try {
      while (!_stopping) {
        try {
          await _transition(BitunixPublicConnectionState.connecting);
          _validPayloadSeen = false;
          final socket = connector.connect(config.endpointUri);
          _socket = socket;
          await socket.ready.timeout(config.connectTimeout);
          _outboundSchedule.reset();
          _lastMessageAtUtc = clock();
          await _send(
            socket,
            BitunixPublicStreamCodec.encodeSubscribe(shard.subscriptions),
          );
          await _transition(BitunixPublicConnectionState.live);
          _startHeartbeat(socket);
          await _consume(socket);
          if (!_stopping) {
            throw StateError('Bitunix public WebSocket closed unexpectedly.');
          }
        } on TimeoutException catch (error) {
          await _report(
            BitunixPublicStreamFaultKind.connect,
            'Bitunix connection timed out: $error',
          );
        } on Object catch (error) {
          if (!_stopping) {
            await _report(
              BitunixPublicStreamFaultKind.transport,
              'Bitunix public stream failed: $error',
            );
          }
        } finally {
          _heartbeatTimer?.cancel();
          _heartbeatTimer = null;
          final socket = _socket;
          _socket = null;
          if (socket != null) {
            try {
              await socket.close();
            } on Object {
              // Closing is best-effort after the fault was already surfaced.
            }
          }
        }

        if (_stopping) break;
        if (_validPayloadSeen) attempt = 0;
        final backoff = reconnectPolicy.delayFor(
          attempt: attempt,
          shardIndex: shard.index,
        );
        attempt++;
        await _transition(BitunixPublicConnectionState.backingOff);
        await delay(backoff);
      }
    } finally {
      _heartbeatTimer?.cancel();
      _heartbeatTimer = null;
      _socket = null;
      _running = false;
      await _transition(BitunixPublicConnectionState.stopped);
    }
  }

  Future<void> stop() async {
    _stopping = true;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    final socket = _socket;
    if (socket != null) {
      try {
        await socket.close(code: 1000, reason: 'Quantara stream stop');
      } on Object {
        // The run loop will finish cleanup and publish the stopped state.
      }
    }
  }

  Future<void> _consume(BitunixWebSocket socket) async {
    var malformedCount = 0;
    await for (final message in socket.messages) {
      if (_stopping) break;
      _lastMessageAtUtc = clock();
      if (message is! String) {
        malformedCount++;
        await _report(
          BitunixPublicStreamFaultKind.malformedPayload,
          'Bitunix sent a non-text public payload.',
        );
      } else {
        try {
          final events = BitunixPublicStreamCodec.decode(
            message,
            receivedAtUtc: clock(),
          );
          malformedCount = 0;
          _validPayloadSeen = true;
          for (final event in events) {
            try {
              await onEvent(event);
            } on Object catch (error) {
              await _report(
                BitunixPublicStreamFaultKind.callback,
                'Bitunix event callback failed: $error',
              );
            }
          }
        } on FormatException catch (error) {
          malformedCount++;
          await _report(
            BitunixPublicStreamFaultKind.malformedPayload,
            'Rejected Bitunix payload: $error',
          );
        }
      }

      if (malformedCount >= config.malformedPayloadBudget) {
        try {
          unawaited(
            socket.close(
              code: 1003,
              reason: 'Malformed public payload budget exceeded',
            ),
          );
        } on Object {
          // The transport fault below remains the source of truth.
        }
        throw StateError('Bitunix malformed payload budget exceeded.');
      }
    }
  }

  void _startHeartbeat(BitunixWebSocket socket) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(config.pingInterval, (_) {
      unawaited(_guardedHeartbeat(socket));
    });
  }

  Future<void> _guardedHeartbeat(BitunixWebSocket socket) async {
    try {
      await _heartbeat(socket);
    } on Object catch (error) {
      if (!_stopping && identical(socket, _socket)) {
        await _report(
          BitunixPublicStreamFaultKind.transport,
          'Bitunix heartbeat failed: $error',
        );
        try {
          await socket.close(code: 1011, reason: 'Public heartbeat failure');
        } on Object {
          // The stream loop will handle final cleanup.
        }
      }
    }
  }

  Future<void> _heartbeat(BitunixWebSocket socket) async {
    if (_stopping || !identical(socket, _socket)) return;
    final now = clock();
    final last = _lastMessageAtUtc;
    if (last != null && now.difference(last) > config.silenceTimeout) {
      await _report(
        BitunixPublicStreamFaultKind.silenceTimeout,
        'Bitunix public stream exceeded the silence timeout.',
      );
      await socket.close(code: 1001, reason: 'Public stream silence timeout');
      return;
    }
    await _send(
      socket,
      BitunixPublicStreamCodec.encodePing(now.millisecondsSinceEpoch ~/ 1000),
    );
  }

  Future<void> _send(BitunixWebSocket socket, String message) {
    final operation = _outboundTail.then((_) async {
      if (_stopping || !identical(socket, _socket)) return;
      final requestedAt = clock();
      final reservedAt = _outboundSchedule.reserve(requestedAt);
      final wait = reservedAt.difference(requestedAt);
      if (wait > Duration.zero) await delay(wait);
      if (_stopping || !identical(socket, _socket)) return;
      socket.send(message);
    });
    _outboundTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<void> _report(
    BitunixPublicStreamFaultKind kind,
    String message,
  ) async {
    try {
      await onFault(
        BitunixPublicStreamFault(
          kind: kind,
          message: message,
          occurredAtUtc: clock(),
          shardIndex: shard.index,
        ),
      );
    } on Object {
      // Diagnostics must not crash the transport loop.
    }
  }

  Future<void> _transition(BitunixPublicConnectionState next) async {
    if (_state == next) return;
    _state = next;
    try {
      await onState(next);
    } on Object catch (error) {
      await _report(
        BitunixPublicStreamFaultKind.callback,
        'Bitunix state callback failed: $error',
      );
    }
  }

  static DateTime _utcNow() => DateTime.now().toUtc();

  static Future<void> _delay(Duration duration) => Future.delayed(duration);
}

final class BitunixPublicStreamFleet {
  BitunixPublicStreamFleet(List<BitunixPublicStreamConnection> connections)
    : connections = List.unmodifiable(connections) {
    if (connections.isEmpty) {
      throw ArgumentError.value(connections, 'connections');
    }
  }

  final List<BitunixPublicStreamConnection> connections;
  var _started = false;

  Future<void> run() async {
    if (_started) throw StateError('The Bitunix stream fleet is already run.');
    _started = true;
    try {
      await Future.wait([
        for (final connection in connections) connection.run(),
      ]);
    } finally {
      _started = false;
    }
  }

  Future<void> stop() async {
    await Future.wait([
      for (final connection in connections) connection.stop(),
    ]);
  }
}
