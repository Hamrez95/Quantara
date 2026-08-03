import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/owner_alpha/data/bitunix_public_stream_transport.dart';
import 'package:quantara_app/features/owner_alpha/data/bitunix_web_socket_adapter.dart';
import 'package:quantara_app/features/owner_alpha/domain/bitunix_public_stream_models.dart';

void main() {
  group('BitunixReconnectPolicy', () {
    test('applies exponential backoff with a deterministic cap', () {
      final policy = BitunixReconnectPolicy(
        baseDelay: const Duration(seconds: 1),
        maximumDelay: const Duration(seconds: 8),
        maximumJitter: Duration.zero,
      );

      expect(
        policy.delayFor(attempt: 0, shardIndex: 0),
        const Duration(seconds: 1),
      );
      expect(
        policy.delayFor(attempt: 1, shardIndex: 0),
        const Duration(seconds: 2),
      );
      expect(
        policy.delayFor(attempt: 3, shardIndex: 0),
        const Duration(seconds: 8),
      );
      expect(
        policy.delayFor(attempt: 8, shardIndex: 0),
        const Duration(seconds: 8),
      );
    });

    test('produces stable shard-aware jitter', () {
      final policy = BitunixReconnectPolicy(
        maximumJitter: const Duration(milliseconds: 250),
      );

      final first = policy.delayFor(attempt: 2, shardIndex: 4);
      final second = policy.delayFor(attempt: 2, shardIndex: 4);
      final otherShard = policy.delayFor(attempt: 2, shardIndex: 5);

      expect(first, second);
      expect(otherShard, isNot(first));
    });
  });

  group('BitunixPublicStreamConfig', () {
    test('rejects insecure or credential-bearing endpoints immediately', () {
      expect(
        () => BitunixPublicStreamConfig(endpoint: 'ws://example.test/public'),
        throwsFormatException,
      );
      expect(
        () => BitunixPublicStreamConfig(
          endpoint: 'wss://user:secret@example.test/public',
        ),
        throwsFormatException,
      );
      expect(
        () => BitunixPublicStreamConfig(
          endpoint: 'wss://example.test/public?token=secret',
        ),
        throwsFormatException,
      );
    });
  });

  group('BitunixPublicStreamConnection', () {
    test(
      'subscribes after ready, emits validated data and stops cleanly',
      () async {
        final socket = _FakeSocket();
        final connector = _QueueConnector([socket]);
        final events = <BitunixPublicStreamEvent>[];
        final states = <BitunixPublicConnectionState>[];
        final faults = <BitunixPublicStreamFault>[];
        final connection = _connection(
          connector: connector,
          onEvent: events.add,
          onState: states.add,
          onFault: faults.add,
        );

        final running = connection.run();
        await _waitUntil(() => socket.sent.isNotEmpty);
        socket.add(_tickerPayload());
        await _waitUntil(() => events.isNotEmpty);
        await connection.stop();
        await running;

        final subscribe = jsonDecode(socket.sent.first) as Map<String, Object?>;
        expect(subscribe['op'], 'subscribe');
        expect(events.single, isA<BitunixTickerEvent>());
        expect((events.single as BitunixTickerEvent).symbol, 'BTCUSDT');
        expect(
          states,
          containsAllInOrder([
            BitunixPublicConnectionState.connecting,
            BitunixPublicConnectionState.live,
            BitunixPublicConnectionState.stopped,
          ]),
        );
        expect(faults, isEmpty);
        expect(socket.closeCode, 1000);
      },
    );

    test('reconnects after an unexpected close using policy delay', () async {
      final first = _FakeSocket();
      final second = _FakeSocket();
      final connector = _QueueConnector([first, second]);
      final delays = <Duration>[];
      final connection = _connection(
        connector: connector,
        delay: (duration) async {
          delays.add(duration);
        },
      );

      final running = connection.run();
      await _waitUntil(() => first.sent.isNotEmpty);
      await first.serverClose();
      await _waitUntil(() => connector.connectCount == 2);
      await _waitUntil(() => second.sent.isNotEmpty);
      await connection.stop();
      await running;

      expect(delays, isNotEmpty);
      expect(delays.first, const Duration(seconds: 1));
      expect(
        connector.uris,
        everyElement(Uri.parse('wss://fapi.bitunix.com/public/')),
      );
    });

    test(
      'closes and backs off after malformed payload budget is exceeded',
      () async {
        final socket = _FakeSocket();
        final connector = _QueueConnector([socket]);
        final faults = <BitunixPublicStreamFault>[];
        late BitunixPublicStreamConnection connection;
        connection = _connection(
          connector: connector,
          malformedPayloadBudget: 2,
          onFault: faults.add,
          delay: (duration) async {
            await connection.stop();
          },
        );

        final running = connection.run();
        await _waitUntil(() => socket.sent.isNotEmpty);
        socket.add('{broken');
        socket.add('{still-broken');
        await running;

        expect(
          faults.where(
            (fault) =>
                fault.kind == BitunixPublicStreamFaultKind.malformedPayload,
          ),
          hasLength(2),
        );
        expect(socket.closeCode, 1003);
        expect(connection.state, BitunixPublicConnectionState.stopped);
      },
    );

    test(
      'reports callback failure and continues delivering later events',
      () async {
        final socket = _FakeSocket();
        final connector = _QueueConnector([socket]);
        final faults = <BitunixPublicStreamFault>[];
        var calls = 0;
        final connection = _connection(
          connector: connector,
          onFault: faults.add,
          onEvent: (event) {
            calls++;
            if (calls == 1) throw StateError('injected callback failure');
          },
        );

        final running = connection.run();
        await _waitUntil(() => socket.sent.isNotEmpty);
        socket.add(_tickerPayload());
        socket.add(_tickerPayload(timestampOffsetMilliseconds: 500));
        await _waitUntil(() => calls == 2);
        await connection.stop();
        await running;

        expect(calls, 2);
        expect(
          faults.any(
            (fault) => fault.kind == BitunixPublicStreamFaultKind.callback,
          ),
          isTrue,
        );
      },
    );
  });
}

BitunixPublicStreamConnection _connection({
  required BitunixWebSocketConnector connector,
  BitunixStreamEventHandler? onEvent,
  BitunixStreamFaultHandler? onFault,
  BitunixConnectionStateHandler? onState,
  BitunixAsyncDelay? delay,
  int malformedPayloadBudget = 3,
  String endpoint = 'wss://fapi.bitunix.com/public/',
}) => BitunixPublicStreamConnection(
  shard: BitunixSubscriptionShard(
    index: 0,
    subscriptions: [BitunixPublicSubscription.ticker('BTCUSDT')],
  ),
  connector: connector,
  onEvent: onEvent ?? (_) {},
  onFault: onFault ?? (_) {},
  onState: onState ?? (_) {},
  delay: delay,
  clock: () => DateTime.utc(2026, 8, 2, 12, 0, 1),
  config: BitunixPublicStreamConfig(
    endpoint: endpoint,
    connectTimeout: const Duration(seconds: 2),
    pingInterval: const Duration(hours: 1),
    silenceTimeout: const Duration(hours: 2),
    malformedPayloadBudget: malformedPayloadBudget,
  ),
  reconnectPolicy: BitunixReconnectPolicy(
    baseDelay: const Duration(seconds: 1),
    maximumDelay: const Duration(seconds: 4),
    maximumJitter: Duration.zero,
  ),
);

String _tickerPayload({int timestampOffsetMilliseconds = 0}) => jsonEncode({
  'ch': 'ticker',
  'symbol': 'BTCUSDT',
  'ts': DateTime.utc(2026, 8, 2, 12)
      .add(Duration(milliseconds: timestampOffsetMilliseconds))
      .millisecondsSinceEpoch,
  'data': {
    's': 'BTCUSDT',
    'o': '100',
    'h': '110',
    'l': '95',
    'la': '105',
    'b': '10',
    'q': '1020',
    'r': '5',
  },
});

Future<void> _waitUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Condition was not reached before timeout.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

final class _QueueConnector implements BitunixWebSocketConnector {
  _QueueConnector(List<_FakeSocket> sockets) : _sockets = List.of(sockets);

  final List<_FakeSocket> _sockets;
  final List<Uri> uris = [];
  var connectCount = 0;

  @override
  BitunixWebSocket connect(Uri uri) {
    uris.add(uri);
    if (connectCount >= _sockets.length) {
      throw StateError('No fake socket is available for connection attempt.');
    }
    return _sockets[connectCount++];
  }
}

final class _FakeSocket implements BitunixWebSocket {
  final StreamController<Object?> _controller = StreamController<Object?>();
  final List<String> sent = [];
  int? closeCode;
  String? closeReason;
  var _closed = false;

  @override
  Future<void> get ready async {}

  @override
  Stream<Object?> get messages => _controller.stream;

  @override
  void send(String message) {
    if (_closed) throw StateError('Socket is closed.');
    sent.add(message);
  }

  void add(Object? message) {
    if (_closed) throw StateError('Socket is closed.');
    _controller.add(message);
  }

  Future<void> serverClose() async {
    if (_closed) return;
    _closed = true;
    await _controller.close();
  }

  @override
  Future<void> close({int? code, String? reason}) async {
    closeCode ??= code;
    closeReason ??= reason;
    if (_closed) return;
    _closed = true;
    await _controller.close();
  }
}
