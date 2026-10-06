import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quantara_app/features/auto_trade/data/bitunix_private_api_client.dart';
import 'package:quantara_app/features/auto_trade/data/bitunix_local_live_api_client.dart';
import 'package:quantara_app/features/auto_trade/domain/auto_trade_models.dart';

const _credentials = BitunixApiCredentials(
  apiKey: 'fixture',
  secretKey: 'fixture-secret',
);
final _at = DateTime.utc(2026, 10, 4, 17);

void main() {
  test(
    'flat HEDGE account recovers overlapping closed history from position filters',
    () async {
      var scopedRequests = 0;
      final client = MockClient((request) async {
        if (request.url.queryParameters.containsKey('positionId')) {
          scopedRequests++;
        }
        return _response(request);
      });
      addTearDown(client.close);
      final api = BitunixPrivateApiClient(
        client: client,
        utcNow: () => _at,
        secureRandom: Random(1),
      );
      final snapshot = await api.fetchAccountSnapshot(_credentials);
      expect(snapshot.positions, isEmpty);
      expect(snapshot.authoritativePnl.isReadyForRiskGates, isTrue);
      expect(snapshot.authoritativePnl.accountRealizedGross.value, -1);
      expect(snapshot.authoritativePnl.accountFees.value, closeTo(0.2, 1e-9));
      expect(
        snapshot.authoritativePnl.accountNetRealized.value,
        closeTo(-1.2, 1e-9),
      );
      expect(scopedRequests, 2);
      final second = await api.fetchAccountSnapshot(_credentials);
      expect(second.authoritativePnl.isReadyForRiskGates, isTrue);
      expect(
        scopedRequests,
        2,
        reason: 'Verified immutable attribution is reused',
      );
      await api.fetchAccountSnapshot(
        const BitunixApiCredentials(
          apiKey: 'another',
          secretKey: 'another-secret',
        ),
      );
      expect(
        scopedRequests,
        4,
        reason: 'Credentials must not share account history',
      );
    },
  );

  test(
    'secondary pre-mutation account path uses complete attribution too',
    () async {
      final client = MockClient(_response);
      addTearDown(client.close);
      final api = BitunixLocalLiveApiClient(client: client, utcNow: () => _at);
      final snapshot = await api.fetchCurrentAccountSnapshot(_credentials);
      expect(snapshot.authoritativePnl.isReadyForRiskGates, isTrue);
    },
  );

  test('same fill returned for two filtered positions fails closed', () async {
    final client = MockClient(
      (request) async => _response(request, ambiguous: true),
    );
    addTearDown(client.close);
    final api = BitunixPrivateApiClient(client: client, utcNow: () => _at);
    final snapshot = await api.fetchAccountSnapshot(_credentials);
    expect(snapshot.authoritativePnl.isReadyForRiskGates, isFalse);
    expect(snapshot.authoritativePnl.warning, contains('inconsistent'));
  });

  test('filtered economics mismatch fails closed', () async {
    final client = MockClient(
      (request) async => _response(request, changedPrice: true),
    );
    addTearDown(client.close);
    final api = BitunixPrivateApiClient(client: client, utcNow: () => _at);
    final snapshot = await api.fetchAccountSnapshot(_credentials);
    expect(snapshot.authoritativePnl.isReadyForRiskGates, isFalse);
    expect(snapshot.authoritativePnl.warning, contains('economics'));
  });

  test('truncated history cannot claim full account truth', () async {
    final client = MockClient(
      (request) async => _response(request, truncated: true),
    );
    addTearDown(client.close);
    final api = BitunixPrivateApiClient(client: client, utcNow: () => _at);
    final snapshot = await api.fetchAccountSnapshot(_credentials);
    expect(snapshot.authoritativePnl.isReadyForRiskGates, isFalse);
    expect(snapshot.authoritativePnl.warning, contains('incomplete'));
  });
}

Future<http.Response> _response(
  http.Request request, {
  bool ambiguous = false,
  bool changedPrice = false,
  bool truncated = false,
}) async {
  expect(request.method, 'GET');
  Object data;
  switch (request.url.path) {
    case '/api/v1/futures/account':
      data = {
        'marginCoin': 'USDT',
        'available': '29.11',
        'frozen': '0',
        'margin': '0',
        'crossUnrealizedPNL': '0',
        'isolationUnrealizedPNL': '0',
        'positionMode': 'HEDGE',
      };
    case '/api/v1/futures/position/get_pending_positions':
      data = <Object>[];
    case '/api/v1/futures/trade/get_pending_orders':
      data = {'orderList': <Object>[]};
    case '/api/v1/futures/position/get_history_positions':
      data = {
        'total': 2,
        'positionList': [
          for (final id in ['a', 'b'])
            {
              'positionId': id,
              'symbol': 'XRPUSDT',
              'ctime': _at
                  .subtract(const Duration(hours: 2))
                  .millisecondsSinceEpoch,
              'mtime': _at
                  .subtract(const Duration(minutes: 10))
                  .millisecondsSinceEpoch,
              'realizedPNL': id == 'a' ? '-2' : '1',
              'fee': '0.1',
              'funding': '0',
            },
        ],
      };
    case '/api/v1/futures/trade/get_history_trades':
      final positionId = request.url.queryParameters['positionId'];
      final ids = positionId == null
          ? ['a', 'b']
          : [ambiguous ? 'a' : positionId];
      data = {
        'total': truncated ? 5 : ids.length,
        'tradeList': [
          for (final id in ids)
            {
              'tradeId': 'trade-$id',
              'orderId': 'order-$id',
              'symbol': 'XRPUSDT',
              'qty': '1',
              'price': changedPrice && positionId != null ? '2' : '1',
              'realizedPNL': id == 'a' ? '-2' : '1',
              'fee': '0.1',
              'reduceOnly': true,
              'ctime': _at
                  .subtract(const Duration(hours: 1))
                  .millisecondsSinceEpoch,
            },
        ],
      };
    default:
      throw StateError('Unexpected endpoint ${request.url.path}');
  }
  return http.Response(
    jsonEncode({'code': 0, 'data': data, 'msg': 'Success'}),
    200,
  );
}
