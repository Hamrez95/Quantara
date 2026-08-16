import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/application/private_truth_coordinator.dart';
import 'package:quantara_app/features/auto_trade/data/bitunix_private_websocket_client.dart';
import 'package:quantara_app/features/auto_trade/domain/auto_trade_models.dart';

final class _FillTransport implements PrivateWsTransport {
  final StreamController<Object?> controller = StreamController<Object?>();
  final List<Object> sent = [];

  @override
  Future<void> get ready async {}

  @override
  Stream<Object?> get stream => controller.stream;

  @override
  void add(Object data) => sent.add(data);

  @override
  Future<void> close() async {
    if (!controller.isClosed) await controller.close();
  }

  void emit(Map<String, Object?> message) =>
      controller.add(jsonEncode(message));
}

Future<void> _flush([int count = 1]) async {
  for (var i = 0; i < count; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  const credentials = BitunixApiCredentials(
    apiKey: 'api-key',
    secretKey: 'secret-key',
  );
  final now = DateTime.utc(2026, 8, 16, 1);

  AutoTradeAccountSnapshot baseline() => AutoTradeAccountSnapshot(
    marginCoin: 'USDT',
    available: 1000,
    frozen: 0,
    positionMargin: 0,
    crossUnrealizedPnl: 0,
    isolatedUnrealizedPnl: 0,
    positionMode: 'ONE_WAY',
    positions: const [],
    orders: const [],
    protectionOrders: const [],
    protectionVerifications: const {},
    syncedAt: now,
  );

  Future<PrivateTruthCoordinator> activeCoordinator(
    _FillTransport transport,
  ) async {
    final socket = BitunixPrivateWebSocketClient(
      connector: (_) async => transport,
      delay: (_) async {},
      clock: () => now,
      nonceFactory: () => 'nonce',
      heartbeatInterval: const Duration(hours: 1),
      staleAfter: const Duration(hours: 2),
    );
    final coordinator = PrivateTruthCoordinator(
      socket,
      (_) async => baseline(),
      clock: () => now,
      restVerificationInterval: const Duration(hours: 1),
    );
    await coordinator.start(credentials);
    transport.emit(<String, Object?>{'op': 'login', 'code': 0});
    await _flush(2);
    transport.emit(<String, Object?>{'op': 'subscribe', 'code': 0});
    await _flush(3);
    return coordinator;
  }

  test(
    'requires both exchange FILLED order and matching open position',
    () async {
      final transport = _FillTransport();
      final coordinator = await activeCoordinator(transport);
      final future = coordinator.waitForFullFill(
        orderId: 'ord-1',
        clientId: 'client-1',
        symbol: 'BTCUSDT',
        timeout: const Duration(seconds: 1),
      );

      transport.emit(<String, Object?>{
        'ch': 'order',
        'ts': 1786795200123,
        'data': <String, Object?>{
          'event': 'UPDATE',
          'orderId': 'ord-1',
          'clientId': 'client-1',
          'symbol': 'BTCUSDT',
          'side': 'BUY',
          'type': 'MARKET',
          'orderStatus': 'FILLED',
          'qty': '0.01',
          'dealAmount': '0.01',
          'averagePrice': '120000',
          'fee': '0.72',
          'mtime': 1786795200120,
        },
      });
      await _flush(2);

      transport.emit(<String, Object?>{
        'ch': 'position',
        'ts': 1786795200124,
        'data': <String, Object?>{
          'event': 'UPDATE',
          'positionId': 'pos-1',
          'symbol': 'BTCUSDT',
          'side': 'LONG',
          'marginMode': 'ISOLATION',
          'positionMode': 'ONE_WAY',
          'leverage': '3',
          'margin': '400',
          'qty': '0.01',
          'realizedPNL': '0',
          'unrealizedPNL': '0',
          'funding': '0',
          'fee': '0.72',
        },
      });

      final confirmation = await future;
      expect(confirmation, isNotNull);
      expect(confirmation!.order.orderId, 'ord-1');
      expect(confirmation.position.positionId, 'pos-1');
      expect(confirmation.order.orderStatus, 'FILLED');
      await coordinator.dispose();
    },
  );

  test(
    'submission without exchange fill evidence times out fail-closed',
    () async {
      final transport = _FillTransport();
      final coordinator = await activeCoordinator(transport);

      final confirmation = await coordinator.waitForFullFill(
        orderId: 'missing',
        clientId: 'client-missing',
        symbol: 'ETHUSDT',
        timeout: const Duration(milliseconds: 20),
      );

      expect(confirmation, isNull);
      await coordinator.dispose();
    },
  );
}
