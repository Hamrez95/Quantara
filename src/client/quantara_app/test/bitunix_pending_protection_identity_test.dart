import 'dart:convert';
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
  ) {
    return BitunixLocalLiveApiClient(
      client: MockClient(handler),
      utcNow: () => DateTime.utc(2026, 8, 30, 16),
      secureRandom: Random(107),
    );
  }

  Map<String, Object?> protection({required String positionId}) {
    return {
      'id': 'tp-1',
      'positionId': positionId,
      'symbol': 'BTCUSDT',
      'tpPrice': '62000',
      'slPrice': '59000',
      'tpQty': '0.01',
      'slQty': '0.01',
    };
  }

  test('position-scoped protection accepts exact exchange identity', () async {
    final api = client((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/v1/futures/tpsl/get_pending_orders');
      expect(request.url.queryParameters['symbol'], 'BTCUSDT');
      expect(request.url.queryParameters['positionId'], 'position-1');
      return http.Response(
        jsonEncode({
          'code': 0,
          'msg': 'Success',
          'data': {
            'orderList': [protection(positionId: 'position-1')],
          },
        }),
        200,
      );
    });

    final result = await api.fetchPendingProtection(
      credentials,
      symbol: 'BTCUSDT',
      positionId: 'position-1',
    );

    expect(result, hasLength(1));
    expect(result.single.positionId, 'position-1');
    expect(result.single.orderId, 'tp-1');
  });

  test(
    'position-scoped protection rejects stale mismatched identity',
    () async {
      final api = client((request) async {
        return http.Response(
          jsonEncode({
            'code': 0,
            'msg': 'Success',
            'data': {
              'orderList': [protection(positionId: 'position-stale')],
            },
          }),
          200,
        );
      });

      await expectLater(
        api.fetchPendingProtection(
          credentials,
          symbol: 'BTCUSDT',
          positionId: 'position-1',
        ),
        throwsA(
          isA<LocalLiveTradeSafeException>().having(
            (error) => error.message,
            'message',
            contains('identity did not match'),
          ),
        ),
      );
    },
  );

  test('position-scoped protection rejects blank requested identity', () async {
    final api = client((request) async {
      return http.Response('{}', 500);
    });

    await expectLater(
      api.fetchPendingProtection(
        credentials,
        symbol: 'BTCUSDT',
        positionId: '   ',
      ),
      throwsA(
        isA<LocalLiveTradeSafeException>().having(
          (error) => error.message,
          'message',
          contains('identity was missing'),
        ),
      ),
    );
  });
}
