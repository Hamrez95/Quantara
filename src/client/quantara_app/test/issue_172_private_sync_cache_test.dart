import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quantara_app/features/auto_trade/data/bitunix_private_api_client.dart';
import 'package:quantara_app/features/auto_trade/domain/auto_trade_models.dart';

void main() {
  test(
    'second private refresh validates page zero instead of replaying full history',
    () async {
      final positionRows = List<Map<String, Object?>>.generate(
        101,
        (index) => _positionHistoryRow(index),
      );
      final tradeRows = List<Map<String, Object?>>.generate(
        101,
        (index) => _tradeHistoryRow(index),
      );
      var positionHistoryRequests = 0;
      var tradeHistoryRequests = 0;

      final client = MockClient((request) async {
        final path = request.url.path;
        if (path == '/api/v1/futures/position/get_history_positions') {
          positionHistoryRequests += 1;
          return _historyResponse(
            request: request,
            listKey: 'positionList',
            rows: positionRows,
          );
        }
        if (path == '/api/v1/futures/trade/get_history_trades') {
          tradeHistoryRequests += 1;
          return _historyResponse(
            request: request,
            listKey: 'tradeList',
            rows: tradeRows,
          );
        }
        return switch (path) {
          '/api/v1/futures/account' => _ok({
            'marginCoin': 'USDT',
            'available': '30',
            'frozen': '0',
            'margin': '0',
            'crossUnrealizedPNL': '0',
            'isolationUnrealizedPNL': '0',
            'positionMode': 'HEDGE',
          }),
          '/api/v1/futures/position/get_pending_positions' => _ok(<Object>[]),
          '/api/v1/futures/trade/get_pending_orders' => _ok({
            'orderList': <Object>[],
          }),
          '/api/v1/futures/tpsl/get_pending_orders' => _ok({
            'orderList': <Object>[],
          }),
          _ => throw StateError('Unexpected Bitunix path: $path'),
        };
      });
      final api = BitunixPrivateApiClient(
        client: client,
        utcNow: () => DateTime.utc(2026, 8, 8, 13),
      );
      addTearDown(client.close);

      final first = await api.fetchAccountSnapshot(_credentials);
      expect(first.pnlProjection, isNotNull);
      expect(first.pnlProjection!.isVerified, isTrue);
      expect(first.pnlProjection!.positions, hasLength(101));
      expect(positionHistoryRequests, 2);
      expect(tradeHistoryRequests, 2);

      final second = await api.fetchAccountSnapshot(_credentials);
      expect(second.pnlProjection, isNotNull);
      expect(second.pnlProjection!.isVerified, isTrue);
      expect(second.pnlProjection!.positions, hasLength(101));
      expect(
        positionHistoryRequests,
        3,
        reason: 'cached refresh should add only one page-zero position request',
      );
      expect(
        tradeHistoryRequests,
        3,
        reason: 'cached refresh should add only one page-zero trade request',
      );
    },
  );
}

const _credentials = BitunixApiCredentials(
  apiKey: 'test-api-key-123',
  secretKey: 'test-secret-key-123',
);

Map<String, Object?> _positionHistoryRow(int index) {
  final openedAt = DateTime.utc(2026, 7, 1).add(Duration(hours: index * 2));
  final closedAt = openedAt.add(const Duration(minutes: 30));
  return {
    'positionId': 'position-$index',
    'symbol': 'TEST${index}USDT',
    'funding': '0',
    'realizedPNL': '0.10',
    'fee': '0.01',
    'ctime': openedAt.millisecondsSinceEpoch,
    'mtime': closedAt.millisecondsSinceEpoch,
  };
}

Map<String, Object?> _tradeHistoryRow(int index) {
  final occurredAt = DateTime.utc(
    2026,
    7,
    1,
  ).add(Duration(hours: index * 2, minutes: 30));
  return {
    'tradeId': 'trade-$index',
    'orderId': 'order-$index',
    'positionId': 'position-$index',
    'symbol': 'TEST${index}USDT',
    'qty': '1',
    'price': '10',
    'realizedPNL': '0.10',
    'fee': '0.01',
    'ctime': occurredAt.millisecondsSinceEpoch,
    'reduceOnly': true,
    'side': 'SELL',
  };
}

http.Response _historyResponse({
  required http.Request request,
  required String listKey,
  required List<Map<String, Object?>> rows,
}) {
  final skip = int.tryParse(request.url.queryParameters['skip'] ?? '') ?? 0;
  final limit = int.tryParse(request.url.queryParameters['limit'] ?? '') ?? 100;
  final end = math.min(rows.length, skip + limit);
  final page = skip >= rows.length
      ? const <Map<String, Object?>>[]
      : rows.sublist(skip, end);
  return _ok({listKey: page, 'total': rows.length});
}

http.Response _ok(Object data) =>
    http.Response(jsonEncode({'code': 0, 'data': data}), 200);
