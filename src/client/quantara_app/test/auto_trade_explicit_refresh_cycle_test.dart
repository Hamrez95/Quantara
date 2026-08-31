import 'dart:async';
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
    'manual refresh queues its own REST cycle when active polling is in flight',
    () async {
      await _verifyExplicitRefreshAfterActivePoll(
        explicitRefresh: (controller) => controller.refresh(),
      );
    },
  );

  test(
    'app resume queues its own REST cycle when active polling is in flight',
    () async {
      await _verifyExplicitRefreshAfterActivePoll(
        explicitRefresh: (controller) => controller.reconcile(
          reason: PrivateAccountRefreshReason.appResume,
          force: true,
        ),
      );
    },
  );
}

Future<void> _verifyExplicitRefreshAfterActivePoll({
  required Future<bool> Function(AutoTradeController controller)
      explicitRefresh,
}) async {
  var now = DateTime.utc(2026, 8, 31, 10);
  var accountRequests = 0;
  final secondAccountRequestStarted = Completer<void>();
  final releaseSecondAccountRequest = Completer<void>();
  final client = MockClient((request) async {
    if (request.url.path == '/api/v1/futures/account') {
      accountRequests += 1;
      if (accountRequests == 2) {
        secondAccountRequestStarted.complete();
        await releaseSecondAccountRequest.future;
      }
    }
    return _flatSuccessResponse(request.url.path);
  });
  final controller = AutoTradeController(
    apiClient: BitunixPrivateApiClient(client: client, utcNow: () => now),
    credentialsStore: _MemoryCredentialsStore(_credentials),
    utcNow: () => now,
    staleAfter: const Duration(seconds: 45),
    activePollMinimumInterval: const Duration(seconds: 15),
  );
  addTearDown(() {
    controller.dispose();
    client.close();
  });

  await controller.initialize();
  expect(accountRequests, 1);
  expect(controller.snapshot?.positions, isEmpty);
  expect(
    controller.reconciliation.health,
    PrivateAccountReconciliationHealth.fresh,
  );

  now = now.add(const Duration(minutes: 1));
  final activePoll = controller.reconcile(
    reason: PrivateAccountRefreshReason.activePolling,
  );
  await secondAccountRequestStarted.future;

  final explicit = explicitRefresh(controller);
  releaseSecondAccountRequest.complete();

  expect(await activePoll, isTrue);
  expect(await explicit, isTrue);
  expect(
    accountRequests,
    3,
    reason:
        'The explicit refresh must not be swallowed by the in-flight poll.',
  );
  expect(controller.snapshot?.positions, isEmpty);
  expect(
    controller.reconciliation.health,
    PrivateAccountReconciliationHealth.fresh,
  );
  expect(controller.reconciliation.blocksNewEntries, isFalse);
}

const _credentials = BitunixApiCredentials(
  apiKey: 'test-api-key-123',
  secretKey: 'test-secret-key-123',
);

http.Response _flatSuccessResponse(String path) {
  final Object data = switch (path) {
    '/api/v1/futures/account' => {
      'marginCoin': 'USDT',
      'available': '29.88',
      'frozen': '0',
      'margin': '0',
      'crossUnrealizedPNL': '0',
      'isolationUnrealizedPNL': '0',
      'positionMode': 'HEDGE',
    },
    '/api/v1/futures/position/get_pending_positions' => <Object>[],
    '/api/v1/futures/trade/get_pending_orders' => {'orderList': <Object>[]},
    '/api/v1/futures/position/get_history_positions' => {
      'positionList': <Object>[],
    },
    '/api/v1/futures/trade/get_history_trades' => {'tradeList': <Object>[]},
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
