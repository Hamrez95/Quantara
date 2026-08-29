import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quantara_app/features/auto_trade/data/bitunix_local_live_api_client.dart';
import 'package:quantara_app/features/auto_trade/domain/auto_trade_models.dart';
import 'package:quantara_app/features/auto_trade/domain/local_live_trade_models.dart';

void main() {
  const credentials = BitunixApiCredentials(
    apiKey: 'api-key-for-tests',
    secretKey: 'secret-key-for-tests',
  );

  BitunixLocalLiveApiClient client(
    Future<http.Response> Function(http.Request request) handler,
  ) => BitunixLocalLiveApiClient(
    client: MockClient(handler),
    utcNow: () => DateTime.utc(2026, 7, 30, 20),
    secureRandom: Random(74),
  );

  test('parses official trading-pair precision and leverage limits', () async {
    final api = client((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/v1/futures/market/trading_pairs');
      expect(request.url.queryParameters['symbols'], 'BTCUSDT');
      return http.Response(
        jsonEncode({
          'code': 0,
          'msg': 'Success',
          'data': [
            {
              'symbol': 'BTCUSDT',
              'minTradeVolume': '0.0001',
              'maxMarketOrderVolume': '50000',
              'basePrecision': 4,
              'quotePrecision': 1,
              'minLeverage': 1,
              'maxLeverage': 125,
              'symbolStatus': 'OPEN',
              'isApiSupported': true,
            },
          ],
        }),
        200,
      );
    });

    final rules = await api.fetchInstrumentRules('BTCUSDT');

    expect(rules.minimumQuantity, 0.0001);
    expect(rules.maximumMarketQuantity, 50000);
    expect(rules.roundQuantityDown(0.123456), 0.1234);
    expect(rules.roundPrice(61234.56), 61234.6);
    expect(rules.maximumLeverage, 125);
    expect(rules.open, isTrue);
    expect(rules.apiSupported, isTrue);
  });

  test(
    'submits market entry with deterministic client ID and protective stop',
    () async {
      final api = client((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/futures/trade/place_order');
        expect(request.headers['api-key'], credentials.apiKey);
        expect(request.headers['sign'], isNotEmpty);
        final body = jsonDecode(request.body) as Map<String, Object?>;
        expect(body['symbol'], 'BTCUSDT');
        expect(body['side'], 'BUY');
        expect(body['tradeSide'], 'OPEN');
        expect(body['orderType'], 'MARKET');
        expect(body['reduceOnly'], false);
        expect(body['clientId'], 'q-local-test');
        expect(body['slPrice'], '59000');
        expect(body['slStopType'], 'MARK_PRICE');
        expect(body['slOrderType'], 'MARKET');
        return http.Response(
          jsonEncode({
            'code': 0,
            'msg': 'Success',
            'data': {'orderId': 'entry-1', 'clientId': 'q-local-test'},
          }),
          200,
        );
      });

      final placed = await api.placeMarketEntry(
        symbol: 'BTCUSDT',
        quantity: 0.01,
        long: true,
        clientId: 'q-local-test',
        stopLoss: 59000,
        credentials: credentials,
      );

      expect(placed.orderId, 'entry-1');
      expect(placed.clientId, 'q-local-test');
    },
  );

  test('emergency close uses position-id flash close contract', () async {
    final api = client((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/api/v1/futures/trade/flash_close_position');
      final body = jsonDecode(request.body) as Map<String, Object?>;
      expect(body, {'positionId': 'position-1'});
      expect(request.body, isNot(contains('withdraw')));
      expect(request.body, isNot(contains('transfer')));
      return http.Response(
        jsonEncode({
          'code': 0,
          'msg': 'Success',
          'data': {'positionId': 'position-1'},
        }),
        200,
      );
    });

    final result = await api.closePositionReduceOnly(
      position: const BitunixLivePosition(
        positionId: 'position-1',
        symbol: 'BTCUSDT',
        quantity: 0.01,
        side: 'LONG',
        marginMode: 'ISOLATION',
        positionMode: 'HEDGE',
        leverage: 10,
        averageOpenPrice: 60000,
        realizedPnl: 0,
        unrealizedPnl: 0,
        fee: 0,
        funding: 0,
      ),
      clientId: 'ignored-by-flash-close',
      credentials: credentials,
    );

    expect(result.orderId, 'position-1');
  });

  test('maps rejected private response to a redacted safe exception', () async {
    final api = client(
      (request) async => http.Response(
        jsonEncode({'code': 10004, 'msg': 'Signature error'}),
        401,
      ),
    );

    expect(
      () => api.fetchOrderDetail(orderId: 'order-1', credentials: credentials),
      throwsA(
        isA<LocalLiveTradeSafeException>().having(
          (error) => error.message,
          'message',
          'Signature error',
        ),
      ),
    );
  });

  test(
    'cancels an unresolved entry using the official batch contract',
    () async {
      final api = client((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/futures/trade/cancel_orders');
        final body = jsonDecode(request.body) as Map<String, Object?>;
        expect(body['symbol'], 'BTCUSDT');
        expect(body['orderList'], [
          {'clientId': 'q-local-test', 'orderId': 'entry-1'},
        ]);
        return http.Response(
          jsonEncode({
            'code': 0,
            'msg': 'Success',
            'data': {
              'successList': ['entry-1'],
              'failureList': [],
            },
          }),
          200,
        );
      });

      await api.cancelEntryOrder(
        symbol: 'BTCUSDT',
        orderId: 'entry-1',
        clientId: 'q-local-test',
        credentials: credentials,
      );
    },
  );

  test('service never treats a partial fill as a protected full entry', () {
    final source = File(
      'lib/features/auto_trade/application/local_live_trade_service.dart',
    ).readAsStringSync();
    expect(source, contains('detail.fullyFilled'));
    expect(source, contains('cancelEntryOrder'));
    expect(source, contains('PartialFillCloseConfirmationPolicy.provesFlat'));
    expect(source.contains('if (detail.hasFill && position != null)'), isFalse);
  });
}
