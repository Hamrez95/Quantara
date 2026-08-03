import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quantara_app/features/auto_trade/data/bitunix_private_api_client.dart';
import 'package:quantara_app/features/auto_trade/domain/auto_trade_models.dart';

void main() {
  const credentials = BitunixApiCredentials(
    apiKey: 'api-key-for-pnl-fixture',
    secretKey: 'secret-key-for-pnl-fixture',
  );

  test(
    'maps TP1 and remaining stop fills to one closed XRP position',
    () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        return switch (request.url.path) {
          '/api/v1/futures/account' => _success({
            'marginCoin': 'USDT',
            'available': '30.031',
            'frozen': '0',
            'margin': '0',
            'crossUnrealizedPNL': '0',
            'isolationUnrealizedPNL': '0',
            'positionMode': 'HEDGE',
          }),
          '/api/v1/futures/position/get_pending_positions' => _success([]),
          '/api/v1/futures/trade/get_pending_orders' => _success({
            'orderList': <Object>[],
          }),
          '/api/v1/futures/position/get_history_positions' => _success({
            'positionList': [
              {
                'positionId': 'xrp-position-1',
                'symbol': 'XRPUSDT',
                'fee': '0.017',
                'funding': '-0.002',
                'realizedPNL': '0.050',
                'ctime': 1785767820000,
                'mtime': 1785769080000,
              },
            ],
          }),
          '/api/v1/futures/trade/get_history_trades' => _success({
            'tradeList': [
              _trade(
                tradeId: 'stop-fill-1',
                orderId: 'stop-order-1',
                quantity: '7.49',
                price: '1.0691',
                realized: '-0.050',
                fee: '0.003',
                reduceOnly: true,
                at: 1785769080000,
              ),
              _trade(
                tradeId: 'tp1-fill-1',
                orderId: 'tp1-order-1',
                quantity: '13.91',
                price: '1.0603',
                realized: '0.100',
                fee: '0.004',
                reduceOnly: true,
                at: 1785768120000,
              ),
              _trade(
                tradeId: 'entry-fill-1',
                orderId: 'entry-order-1',
                quantity: '21.4',
                price: '1.0665',
                realized: '0',
                fee: '0.010',
                reduceOnly: false,
                at: 1785767820000,
              ),
              _trade(
                tradeId: 'tp1-fill-1',
                orderId: 'tp1-order-1',
                quantity: '13.91',
                price: '1.0603',
                realized: '0.100',
                fee: '0.004',
                reduceOnly: true,
                at: 1785768120000,
              ),
            ],
          }),
          _ => throw StateError('Unexpected path ${request.url.path}'),
        };
      });
      addTearDown(client.close);
      final api = BitunixPrivateApiClient(
        client: client,
        utcNow: () => DateTime.utc(2026, 8, 3, 12, 20),
        secureRandom: Random(139),
      );

      final snapshot = await api.fetchAccountSnapshot(credentials);
      final pnl = snapshot.authoritativePnl;

      expect(pnl.isVerified, isTrue);
      expect(pnl.positions, hasLength(1));
      expect(pnl.positions.single.positionId, 'xrp-position-1');
      expect(pnl.positions.single.exchangeFillIds, hasLength(3));
      expect(pnl.positions.single.exitFills, hasLength(2));
      expect(pnl.accountRealizedGross.value, closeTo(0.050, 0.0000001));
      expect(pnl.accountFees.value, closeTo(0.017, 0.0000001));
      expect(pnl.accountFunding.value, closeTo(-0.002, 0.0000001));
      expect(pnl.accountNetRealized.value, closeTo(0.031, 0.0000001));
    },
  );

  test(
    'failed funding history stays unavailable instead of becoming zero',
    () async {
      final client = MockClient((request) async {
        return switch (request.url.path) {
          '/api/v1/futures/account' => _success({
            'marginCoin': 'USDT',
            'available': '27.85',
            'frozen': '0',
            'margin': '2.30',
            'crossUnrealizedPNL': '0',
            'isolationUnrealizedPNL': '-0.012',
            'positionMode': 'HEDGE',
          }),
          '/api/v1/futures/position/get_pending_positions' => _success([
            {
              'positionId': 'xrp-position-1',
              'symbol': 'XRPUSDT',
              'qty': '7.49',
              'side': 'SHORT',
              'marginMode': 'ISOLATION',
              'positionMode': 'HEDGE',
              'leverage': '10',
              'margin': '0.80',
              'unrealizedPNL': '-0.012',
              'avgOpenPrice': '1.0665',
              'realizedPNL': '0.100',
              'fee': '0.014',
            },
          ]),
          '/api/v1/futures/trade/get_pending_orders' => _success({
            'orderList': <Object>[],
          }),
          '/api/v1/futures/tpsl/get_pending_orders' => _success({
            'orderList': <Object>[],
          }),
          '/api/v1/futures/position/get_history_positions' => http.Response(
            jsonEncode({'code': 503, 'msg': 'funding history unavailable'}),
            503,
          ),
          '/api/v1/futures/trade/get_history_trades' => _success({
            'tradeList': [
              _trade(
                tradeId: 'entry-fill-1',
                orderId: 'entry-order-1',
                quantity: '21.4',
                price: '1.0665',
                realized: '0',
                fee: '0.010',
                reduceOnly: false,
                at: 1785767820000,
              ),
              _trade(
                tradeId: 'tp1-fill-1',
                orderId: 'tp1-order-1',
                quantity: '13.91',
                price: '1.0603',
                realized: '0.100',
                fee: '0.004',
                reduceOnly: true,
                at: 1785768120000,
              ),
            ],
          }),
          _ => throw StateError('Unexpected path ${request.url.path}'),
        };
      });
      addTearDown(client.close);
      final api = BitunixPrivateApiClient(
        client: client,
        utcNow: () => DateTime.utc(2026, 8, 3, 12, 5),
        secureRandom: Random(140),
      );

      final snapshot = await api.fetchAccountSnapshot(credentials);
      final pnl = snapshot.authoritativePnl;

      expect(snapshot.positions, hasLength(1));
      expect(pnl.accountRealizedGross.value, closeTo(0.100, 0.0000001));
      expect(pnl.accountFees.value, closeTo(0.014, 0.0000001));
      expect(pnl.accountFunding.value, isNull);
      expect(pnl.accountFunding.isAvailable, isFalse);
      expect(pnl.accountNetRealized.value, isNull);
      expect(pnl.warning, contains('funding history unavailable'));
    },
  );
}

Map<String, Object?> _trade({
  required String tradeId,
  required String orderId,
  required String quantity,
  required String price,
  required String realized,
  required String fee,
  required bool reduceOnly,
  required int at,
}) => {
  'tradeId': tradeId,
  'orderId': orderId,
  'symbol': 'XRPUSDT',
  'qty': quantity,
  'price': price,
  'realizedPNL': realized,
  'fee': fee,
  'reduceOnly': reduceOnly,
  'ctime': at,
  'side': reduceOnly ? 'BUY' : 'SELL',
};

http.Response _success(Object data) =>
    http.Response(jsonEncode({'code': 0, 'msg': 'Success', 'data': data}), 200);
