import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/application/private_truth_coordinator.dart';
import 'package:quantara_app/features/auto_trade/data/bitunix_private_websocket_client.dart';
import 'package:quantara_app/features/auto_trade/domain/auto_trade_models.dart';

final class _FlatAccountTransport implements PrivateWsTransport {
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
}

Future<void> _flush([int count = 1]) async {
  for (var i = 0; i < count; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test(
    'flat account with fresh REST truth becomes entry-admissible without WS control acks',
    () async {
      final now = DateTime.utc(2026, 9, 1, 13, 53, 16);
      final transport = _FlatAccountTransport();
      var restFetches = 0;
      final socket = BitunixPrivateWebSocketClient(
        connector: (_) async => transport,
        delay: (_) async {},
        clock: () => now,
        nonceFactory: () => '0123456789abcdef0123456789abcdef',
        heartbeatInterval: const Duration(hours: 1),
        staleAfter: const Duration(hours: 2),
        handshakeAckTimeout: Duration.zero,
      );
      final coordinator = PrivateTruthCoordinator(
        socket,
        (_) async {
          restFetches++;
          return AutoTradeAccountSnapshot(
            marginCoin: 'USDT',
            available: 29.884792335310113,
            frozen: 0,
            positionMargin: 0,
            crossUnrealizedPnl: 0,
            isolatedUnrealizedPnl: 0,
            positionMode: 'HEDGE',
            positions: const [],
            orders: const [],
            protectionOrders: const [],
            protectionVerifications: const {},
            syncedAt: now,
          );
        },
        clock: () => now,
        restVerificationInterval: const Duration(hours: 1),
      );

      await coordinator.start(
        const BitunixApiCredentials(
          apiKey: 'api-key',
          secretKey: 'secret-key',
        ),
      );
      await _flush(6);

      expect(transport.sent, hasLength(2));
      expect(
        (jsonDecode(transport.sent[0] as String) as Map<String, Object?>)['op'],
        'login',
      );
      expect(
        (jsonDecode(transport.sent[1] as String) as Map<String, Object?>)['op'],
        'subscribe',
      );
      expect(restFetches, 1);
      expect(coordinator.current.restVerifiedAtUtc, now);
      expect(coordinator.canAdmitNewEntries, isTrue);
      expect(coordinator.reduceOnlyManagementAvailable, isTrue);

      await coordinator.dispose();
    },
  );
}
