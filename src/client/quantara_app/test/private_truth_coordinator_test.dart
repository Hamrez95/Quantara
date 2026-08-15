import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/application/private_truth_coordinator.dart';
import 'package:quantara_app/features/auto_trade/data/bitunix_private_websocket_client.dart';
import 'package:quantara_app/features/auto_trade/domain/auto_trade_models.dart';

final class _CoordinatorTransport implements PrivateWsTransport {
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
  final now = DateTime.utc(2026, 8, 15, 12);

  AutoTradeAccountSnapshot verifiedSnapshot() => AutoTradeAccountSnapshot(
    marginCoin: 'USDT',
    available: 450,
    frozen: 0,
    positionMargin: 50,
    crossUnrealizedPnl: 0,
    isolatedUnrealizedPnl: 1,
    positionMode: 'ONE_WAY',
    positions: const [
      AutoTradePosition(
        positionId: 'p-1',
        symbol: 'BTCUSDT',
        quantity: 0.01,
        side: 'LONG',
        marginMode: 'ISOLATION',
        positionMode: 'ONE_WAY',
        leverage: 3,
        margin: 50,
        unrealizedPnl: 1,
        liquidationPrice: 70000,
        averageOpenPrice: 100000,
      ),
    ],
    orders: const [],
    protectionOrders: const [
      AutoTradeProtectionOrder.stopLoss(
        exchangeId: 'sl-1',
        positionId: 'p-1',
        symbol: 'BTCUSDT',
        price: 95000,
        quantity: 0.01,
      ),
    ],
    protectionVerifications: {
      'p-1': AutoTradeProtectionVerification.verified(asOf: now),
    },
    syncedAt: now,
  );

  test(
    'reconnect blocks entries until a fresh REST rebuild completes',
    () async {
      final first = _CoordinatorTransport();
      final second = _CoordinatorTransport();
      final transports = [first, second];
      var connectionIndex = 0;
      var restFetches = 0;
      final socket = BitunixPrivateWebSocketClient(
        connector: (_) async => transports[connectionIndex++],
        delay: (_) async {},
        clock: () => now,
        nonceFactory: () => 'nonce',
        heartbeatInterval: const Duration(hours: 1),
        staleAfter: const Duration(hours: 2),
      );
      final coordinator = PrivateTruthCoordinator(
        socket,
        (_) async {
          restFetches++;
          return verifiedSnapshot();
        },
        clock: () => now,
        restVerificationInterval: const Duration(hours: 1),
      );

      await coordinator.start(credentials);
      first.emit(<String, Object?>{'op': 'login', 'code': 0});
      await _flush(2);
      first.emit(<String, Object?>{'op': 'subscribe', 'code': 0});
      await _flush(3);

      expect(restFetches, 1);
      expect(coordinator.canAdmitNewEntries, isTrue);
      expect(coordinator.reduceOnlyManagementAvailable, isTrue);

      await first.controller.close();
      await _flush(4);
      expect(coordinator.canAdmitNewEntries, isFalse);
      expect(coordinator.reduceOnlyManagementAvailable, isTrue);
      expect(coordinator.current.restVerifiedAtUtc, isNull);
      expect(connectionIndex, 2);

      second.emit(<String, Object?>{'op': 'login', 'code': 0});
      await _flush(2);
      second.emit(<String, Object?>{'op': 'subscribe', 'code': 0});
      await _flush(3);

      expect(restFetches, 2);
      expect(coordinator.canAdmitNewEntries, isTrue);
      expect(coordinator.current.reconciliationGeneration, 2);

      await coordinator.dispose();
    },
  );

  test(
    'REST verification failure keeps the active socket fail-closed',
    () async {
      final transport = _CoordinatorTransport();
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
        (_) async =>
            throw const AutoTradeSafeException('temporary REST failure'),
        clock: () => now,
        restVerificationInterval: const Duration(hours: 1),
      );

      await coordinator.start(credentials);
      transport.emit(<String, Object?>{'op': 'login', 'code': 0});
      await _flush(2);
      transport.emit(<String, Object?>{'op': 'subscribe', 'code': 0});
      await _flush(3);

      expect(coordinator.canAdmitNewEntries, isFalse);
      expect(coordinator.current.lagReason.name, 'restVerificationStale');

      await coordinator.dispose();
    },
  );
}
