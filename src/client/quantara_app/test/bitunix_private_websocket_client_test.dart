import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/data/bitunix_private_websocket_client.dart';
import 'package:quantara_app/features/auto_trade/domain/auto_trade_models.dart';
import 'package:quantara_app/features/auto_trade/domain/private_truth_models.dart';

final class _FakeTransport implements PrivateWsTransport {
  final StreamController<Object?> controller = StreamController<Object?>();
  final List<Object> sent = [];
  bool closed = false;

  @override
  Future<void> get ready async {}

  @override
  Stream<Object?> get stream => controller.stream;

  @override
  void add(Object data) => sent.add(data);

  @override
  Future<void> close() async {
    closed = true;
    if (!controller.isClosed) await controller.close();
  }

  void emit(Map<String, Object?> message) =>
      controller.add(jsonEncode(message));
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  const credentials = BitunixApiCredentials(
    apiKey: 'api-key',
    secretKey: 'top-secret',
  );

  test('authenticates, subscribes, then emits typed private pushes', () async {
    final transport = _FakeTransport();
    final statuses = <PrivateWsClientStatus>[];
    final events = <PrivateTruthEvent>[];
    final client = BitunixPrivateWebSocketClient(
      connector: (_) async => transport,
      delay: (_) async {},
      clock: () => DateTime.utc(2026, 8, 15, 12),
      nonceFactory: () => 'nonce',
      heartbeatInterval: const Duration(hours: 1),
      staleAfter: const Duration(hours: 2),
    );
    final statusSub = client.statuses.listen(statuses.add);
    final eventSub = client.events.listen(events.add);

    await client.start(credentials);
    expect(transport.sent, hasLength(1));
    final login =
        jsonDecode(transport.sent.first as String) as Map<String, Object?>;
    expect(login['op'], 'login');
    expect(
      transport.sent.first.toString(),
      isNot(contains(credentials.secretKey)),
    );

    transport.emit(<String, Object?>{'op': 'login', 'code': 0});
    await _flush();
    expect(transport.sent, hasLength(2));
    final subscribe =
        jsonDecode(transport.sent[1] as String) as Map<String, Object?>;
    expect(subscribe['op'], 'subscribe');

    transport.emit(<String, Object?>{'op': 'subscribe', 'code': 0});
    await _flush();
    expect(statuses.last.state, PrivateWsClientState.active);

    transport.emit(<String, Object?>{
      'ch': 'order',
      'ts': 1786795200000,
      'data': <String, Object?>{
        'event': 'UPDATE',
        'orderId': 'o-1',
        'clientId': 'c-1',
        'symbol': 'BTCUSDT',
        'side': 'BUY',
        'type': 'MARKET',
        'orderStatus': 'FILLED',
        'qty': '0.01',
        'dealAmount': '0.01',
        'averagePrice': '100000',
        'fee': '0.6',
      },
    });
    await _flush();

    expect(events, hasLength(1));
    expect(events.single.channel, PrivateTruthChannel.order);
    expect((events.single.payload as PrivateOrderUpdate).isTerminal, isTrue);

    await client.dispose();
    await statusSub.cancel();
    await eventSub.cancel();
  });

  test(
    'flat account advances handshake without Bitunix control acknowledgements',
    () async {
      final transport = _FakeTransport();
      final statuses = <PrivateWsClientStatus>[];
      final client = BitunixPrivateWebSocketClient(
        connector: (_) async => transport,
        delay: (_) async {},
        clock: () => DateTime.utc(2026, 9, 1, 13, 53),
        nonceFactory: () => 'nonce',
        heartbeatInterval: const Duration(hours: 1),
        staleAfter: const Duration(hours: 2),
        handshakeAckTimeout: Duration.zero,
      );
      final statusSub = client.statuses.listen(statuses.add);

      await client.start(credentials);
      await _flush();
      await _flush();

      expect(transport.sent, hasLength(2));
      expect(
        (jsonDecode(transport.sent[0] as String) as Map<String, Object?>)['op'],
        'login',
      );
      expect(
        (jsonDecode(transport.sent[1] as String) as Map<String, Object?>)['op'],
        'subscribe',
      );
      expect(statuses.last.state, PrivateWsClientState.active);
      expect(client.droppedOrMalformedEvents, 0);

      transport.emit(<String, Object?>{'op': 'ping', 'ping': 1788270780});
      await _flush();
      expect(client.droppedOrMalformedEvents, 0);

      await client.dispose();
      await statusSub.cancel();
    },
  );

  test('reconnects with bounded backoff and re-authenticates', () async {
    final first = _FakeTransport();
    final second = _FakeTransport();
    final transports = <_FakeTransport>[first, second];
    final delays = <Duration>[];
    var connections = 0;
    final client = BitunixPrivateWebSocketClient(
      connector: (_) async => transports[connections++],
      delay: (duration) async => delays.add(duration),
      clock: () => DateTime.utc(2026, 8, 15, 12),
      nonceFactory: () => 'nonce',
      heartbeatInterval: const Duration(hours: 1),
      staleAfter: const Duration(hours: 2),
      baseReconnectDelay: const Duration(milliseconds: 10),
      maximumReconnectDelay: const Duration(milliseconds: 100),
    );

    await client.start(credentials);
    expect(connections, 1);
    await first.controller.close();
    await _flush();
    await _flush();

    expect(delays, contains(const Duration(milliseconds: 10)));
    expect(connections, 2);
    expect(second.sent, hasLength(1));
    final login =
        jsonDecode(second.sent.first as String) as Map<String, Object?>;
    expect(login['op'], 'login');

    await client.dispose();
  });

  test(
    'rejected authentication reconnects and never subscribes on failed socket',
    () async {
      final first = _FakeTransport();
      final second = _FakeTransport();
      final transports = <_FakeTransport>[first, second];
      var connections = 0;
      final client = BitunixPrivateWebSocketClient(
        connector: (_) async => transports[connections++],
        delay: (_) async {},
        clock: () => DateTime.utc(2026, 8, 15, 12),
        nonceFactory: () => 'nonce',
        heartbeatInterval: const Duration(hours: 1),
        staleAfter: const Duration(hours: 2),
      );

      await client.start(credentials);
      first.emit(<String, Object?>{'op': 'login', 'code': 10001});
      await _flush();
      await _flush();

      expect(first.sent, hasLength(1));
      expect(connections, 2);
      expect(second.sent, hasLength(1));

      await client.dispose();
    },
  );
}
