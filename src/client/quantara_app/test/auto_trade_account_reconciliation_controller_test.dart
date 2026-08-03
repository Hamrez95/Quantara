import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quantara_app/features/auto_trade/application/auto_trade_controller.dart';
import 'package:quantara_app/features/auto_trade/data/bitunix_private_api_client.dart';
import 'package:quantara_app/features/auto_trade/data/secure_auto_trade_credentials_store.dart';
import 'package:quantara_app/features/auto_trade/domain/auto_trade_models.dart';
import 'package:quantara_app/features/auto_trade/domain/private_account_reconciliation.dart';

void main() {
  test(
    'controller reconciles Local Live divergence into a new authoritative cycle',
    () async {
      var now = DateTime.utc(2026, 8, 3, 11, 27);
      var requestCount = 0;
      final client = MockClient((request) async {
        requestCount++;
        return _successResponse(request.url.path);
      });
      final controller = AutoTradeController(
        apiClient: BitunixPrivateApiClient(client: client, utcNow: () => now),
        credentialsStore: _MemoryCredentialsStore(_credentials),
        utcNow: () => now,
      );
      addTearDown(() {
        controller.dispose();
        client.close();
      });

      await controller.initialize();

      expect(requestCount, 3);
      expect(
        controller.reconciliation.health,
        PrivateAccountReconciliationHealth.fresh,
      );
      final initialCycle = controller.reconciliation.cycleId;

      now = now.add(const Duration(seconds: 6));
      final reconciled = await controller.observeLocalLiveOpenPositions(
        openPositionCount: 0,
        observedAt: now.subtract(const Duration(seconds: 1)),
        exchangeSyncedAt: now.subtract(const Duration(seconds: 1)),
      );

      expect(reconciled, isTrue);
      expect(requestCount, 6);
      expect(controller.snapshot?.positions, hasLength(1));
      expect(controller.reconciliation.cycleId, isNot(initialCycle));
      expect(
        controller.reconciliation.health,
        PrivateAccountReconciliationHealth.fresh,
      );
    },
  );

  test(
    'failed refresh preserves the last exchange-confirmed position',
    () async {
      var now = DateTime.utc(2026, 8, 3, 11, 27);
      var failRequests = false;
      final client = MockClient((request) async {
        if (failRequests) {
          return http.Response(
            jsonEncode({'code': 503, 'msg': 'temporary failure'}),
            503,
          );
        }
        return _successResponse(request.url.path);
      });
      final controller = AutoTradeController(
        apiClient: BitunixPrivateApiClient(client: client, utcNow: () => now),
        credentialsStore: _MemoryCredentialsStore(_credentials),
        utcNow: () => now,
      );
      addTearDown(() {
        controller.dispose();
        client.close();
      });

      await controller.initialize();
      final lastGoodSnapshot = controller.snapshot;
      failRequests = true;
      now = now.add(const Duration(minutes: 1));

      expect(await controller.refresh(), isFalse);
      expect(controller.snapshot, same(lastGoodSnapshot));
      expect(controller.snapshot?.positions.single.symbol, 'XRPUSDT');
      expect(
        controller.reconciliation.health,
        PrivateAccountReconciliationHealth.stale,
      );
      expect(controller.reconciliation.blocksNewEntries, isTrue);
      expect(controller.canManageExistingPosition, isTrue);
    },
  );

  test(
    'Phase 1 gate never arms a new real entry from fresh account truth',
    () async {
      final now = DateTime.utc(2026, 8, 3, 11, 27);
      final client = MockClient(
        (request) async => _successResponse(request.url.path),
      );
      final controller = AutoTradeController(
        apiClient: BitunixPrivateApiClient(client: client, utcNow: () => now),
        credentialsStore: _MemoryCredentialsStore(_credentials),
        utcNow: () => now,
      );
      addTearDown(() {
        controller.dispose();
        client.close();
      });

      await controller.initialize();

      expect(ExchangeTruthPhaseOneGate.realEntriesAllowed, isFalse);
      expect(controller.reconciliation.blocksNewEntries, isFalse);
      expect(controller.canStartNewEntry, isFalse);
      expect(controller.canManageExistingPosition, isTrue);
    },
  );
}

const _credentials = BitunixApiCredentials(
  apiKey: 'test-api-key-123',
  secretKey: 'test-secret-key-123',
);

http.Response _successResponse(String path) {
  final Object data = switch (path) {
    '/api/v1/futures/account' => {
      'marginCoin': 'USDT',
      'available': '27.85',
      'frozen': '0',
      'margin': '2.30',
      'crossUnrealizedPNL': '0',
      'isolationUnrealizedPNL': '0.0021',
      'positionMode': 'HEDGE',
    },
    '/api/v1/futures/position/get_pending_positions' => [
      {
        'positionId': 'xrp-position-1',
        'symbol': 'XRPUSDT',
        'qty': '21.4',
        'side': 'SHORT',
        'marginMode': 'ISOLATION',
        'positionMode': 'HEDGE',
        'leverage': '10',
        'margin': '2.30',
        'unrealizedPNL': '0.0021',
        'liqPrice': '1.12',
        'avgOpenPrice': '1.0665',
      },
    ],
    '/api/v1/futures/trade/get_pending_orders' => {'orderList': <Object>[]},
    _ => throw StateError('Unexpected Bitunix path: $path'),
  };
  return http.Response(jsonEncode({'code': 0, 'data': data}), 200);
}

final class _MemoryCredentialsStore implements AutoTradeCredentialsStore {
  _MemoryCredentialsStore(this.value);

  BitunixApiCredentials? value;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<BitunixApiCredentials?> load() async => value;

  @override
  Future<void> save(BitunixApiCredentials credentials) async {
    value = credentials;
  }
}
