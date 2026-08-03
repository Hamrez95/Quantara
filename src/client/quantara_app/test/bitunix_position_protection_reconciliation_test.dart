import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quantara_app/features/auto_trade/data/bitunix_private_api_client.dart';
import 'package:quantara_app/features/auto_trade/domain/auto_trade_models.dart';

void main() {
  const credentials = BitunixApiCredentials(
    apiKey: 'api-key-for-protection-fixture',
    secretKey: 'secret-key-for-protection-fixture',
  );

  test(
    'reconciles XRP position protection independently without double count',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        expect(request.method, 'GET');
        return switch (request.url.path) {
          '/api/v1/futures/account' => _success({
            'marginCoin': 'USDT',
            'available': '27.85',
            'frozen': '0',
            'margin': '2.30',
            'crossUnrealizedPNL': '0',
            'isolationUnrealizedPNL': '0.0021',
            'positionMode': 'HEDGE',
          }),
          '/api/v1/futures/position/get_pending_positions' => _success([
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
          ]),
          '/api/v1/futures/trade/get_pending_orders' => _success({
            'orderList': [
              {
                'orderId': 'protection-tp-1',
                'clientId': '',
                'symbol': 'XRPUSDT',
                'qty': '8.56',
                'tradeQty': '0',
                'side': 'BUY',
                'orderType': 'MARKET',
                'marginMode': 'ISOLATION',
                'leverage': '10',
                'reduceOnly': true,
              },
            ],
          }),
          '/api/v1/futures/tpsl/get_pending_orders' => _protectionSuccess(),
          _ => throw StateError('Unexpected Bitunix path: ${request.url.path}'),
        };
      });
      addTearDown(client.close);
      final api = BitunixPrivateApiClient(
        client: client,
        utcNow: () => DateTime.utc(2026, 8, 3, 11, 27),
        secureRandom: Random(135),
      );

      final snapshot = await api.fetchAccountSnapshot(credentials);

      final protectionRequest = requests.singleWhere(
        (request) =>
            request.url.path == '/api/v1/futures/tpsl/get_pending_orders',
      );
      expect(
        protectionRequest.url.queryParameters['positionId'],
        'xrp-position-1',
      );
      expect(protectionRequest.url.queryParameters['symbol'], 'XRPUSDT');
      expect(protectionRequest.url.queryParameters['positionMode'], 'HEDGE');

      expect(snapshot.orders, hasLength(1));
      expect(snapshot.protectionOrders, hasLength(4));
      expect(snapshot.totalPendingOrderCount, 4);

      final protection = snapshot.protectionForPosition(
        snapshot.positions.single,
      );
      expect(protection.status, AutoTradeProtectionStatus.fullyProtected);
      expect(protection.stopLoss?.price, closeTo(1.0691, 0.0000001));
      expect(
        protection.takeProfits.map((item) => item.price),
        orderedEquals([1.0603, 1.0567, 1.0531]),
      );
      expect(protection.totalTakeProfitQuantity, closeTo(21.4, 0.0000001));
      expect(protection.residualQuantity, closeTo(0, 0.0000001));
      expect(protection.hasResidualDust, isFalse);

      expect(requests.every((request) => request.method == 'GET'), isTrue);
      expect(
        requests.any(
          (request) =>
              request.url.path.contains('place_order') ||
              request.url.path.contains('cancel') ||
              request.url.path.contains('modify'),
        ),
        isFalse,
      );
    },
  );

  test(
    'keeps account truth but marks one failed TP/SL read as unverified',
    () async {
      final client = MockClient((request) async {
        return switch (request.url.path) {
          '/api/v1/futures/account' => _success({
            'marginCoin': 'USDT',
            'available': '27.85',
            'frozen': '0',
            'margin': '2.30',
            'crossUnrealizedPNL': '0',
            'isolationUnrealizedPNL': '0.0021',
            'positionMode': 'HEDGE',
          }),
          '/api/v1/futures/position/get_pending_positions' => _success([
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
          ]),
          '/api/v1/futures/trade/get_pending_orders' => _success({
            'orderList': <Object>[],
          }),
          '/api/v1/futures/tpsl/get_pending_orders' => http.Response(
            jsonEncode({'code': 503, 'msg': 'temporary TP/SL failure'}),
            503,
          ),
          _ => throw StateError('Unexpected path: ${request.url.path}'),
        };
      });
      addTearDown(client.close);
      final api = BitunixPrivateApiClient(
        client: client,
        utcNow: () => DateTime.utc(2026, 8, 3, 11, 27),
        secureRandom: Random(136),
      );

      final snapshot = await api.fetchAccountSnapshot(credentials);
      final protection = snapshot.protectionForPosition(
        snapshot.positions.single,
      );

      expect(snapshot.available, 27.85);
      expect(snapshot.positions, hasLength(1));
      expect(snapshot.protectionOrders, isEmpty);
      expect(protection.status, AutoTradeProtectionStatus.unverified);
      expect(protection.reason, contains('temporary TP/SL failure'));
    },
  );

  test('classifies missing, incomplete, unverified, and stale protection', () {
    const position = AutoTradePosition(
      positionId: 'xrp-position-1',
      symbol: 'XRPUSDT',
      quantity: 21.4,
      side: 'SHORT',
      marginMode: 'ISOLATION',
      positionMode: 'HEDGE',
      leverage: 10,
      margin: 2.30,
      unrealizedPnl: 0.0021,
      liquidationPrice: 1.12,
      averageOpenPrice: 1.0665,
    );
    final asOf = DateTime.utc(2026, 8, 3, 11, 27);

    final missingStop = AutoTradePositionProtection.reconcile(
      position: position,
      orders: [
        AutoTradeProtectionOrder.takeProfit(
          exchangeId: 'tp-1',
          positionId: position.positionId,
          symbol: position.symbol,
          price: 1.0603,
          quantity: 21.4,
        ),
      ],
      asOf: asOf,
    );
    expect(missingStop.status, AutoTradeProtectionStatus.missingStop);

    final incomplete = AutoTradePositionProtection.reconcile(
      position: position,
      orders: [
        AutoTradeProtectionOrder.stopLoss(
          exchangeId: 'sl-1',
          positionId: position.positionId,
          symbol: position.symbol,
          price: 1.0691,
          quantity: 21.4,
        ),
        AutoTradeProtectionOrder.takeProfit(
          exchangeId: 'tp-1',
          positionId: position.positionId,
          symbol: position.symbol,
          price: 1.0603,
          quantity: 8.56,
        ),
      ],
      asOf: asOf,
    );
    expect(incomplete.status, AutoTradeProtectionStatus.incompleteLadder);
    expect(incomplete.residualQuantity, closeTo(12.84, 0.0000001));

    final unverified = AutoTradePositionProtection.unverified(
      position: position,
      asOf: asOf,
      reason: 'Position TP/SL response could not be verified.',
    );
    expect(unverified.status, AutoTradeProtectionStatus.unverified);
    expect(
      unverified.effectiveStatus(stale: true),
      AutoTradeProtectionStatus.stale,
    );
  });
}

http.Response _success(Object data) =>
    http.Response(jsonEncode({'code': 0, 'msg': 'Success', 'data': data}), 200);

http.Response _protectionSuccess() => _success({
  'orderList': [
    {
      'id': 'protection-sl-1',
      'positionId': 'xrp-position-1',
      'symbol': 'XRPUSDT',
      'slPrice': '1.0691',
      'slStopType': 'MARK_PRICE',
      'slOrderType': 'MARKET',
      'slOrderPrice': '',
      'slQty': '21.4',
      'tpPrice': '',
      'tpQty': '',
    },
    {
      'id': 'protection-tp-1',
      'positionId': 'xrp-position-1',
      'symbol': 'XRPUSDT',
      'tpPrice': '1.0603',
      'tpStopType': 'MARK_PRICE',
      'tpOrderType': 'MARKET',
      'tpOrderPrice': '',
      'tpQty': '8.56',
      'slPrice': '',
      'slQty': '',
    },
    {
      'id': 'protection-tp-2',
      'positionId': 'xrp-position-1',
      'symbol': 'XRPUSDT',
      'tpPrice': '1.0567',
      'tpStopType': 'MARK_PRICE',
      'tpOrderType': 'MARKET',
      'tpOrderPrice': '',
      'tpQty': '6.42',
      'slPrice': '',
      'slQty': '',
    },
    {
      'id': 'protection-tp-3',
      'positionId': 'xrp-position-1',
      'symbol': 'XRPUSDT',
      'tpPrice': '1.0531',
      'tpStopType': 'MARK_PRICE',
      'tpOrderType': 'MARKET',
      'tpOrderPrice': '',
      'tpQty': '6.42',
      'slPrice': '',
      'slQty': '',
    },
  ],
});
