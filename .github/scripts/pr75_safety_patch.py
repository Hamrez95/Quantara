from pathlib import Path

api_path = Path(
    'src/client/quantara_app/lib/features/auto_trade/data/'
    'bitunix_local_live_api_client.dart'
)
api = api_path.read_text()
api_anchor = """  Future<String> placePositionStop({
"""
cancel_method = """  Future<void> cancelEntryOrder({
    required String symbol,
    required String orderId,
    required String clientId,
    required BitunixApiCredentials credentials,
  }) async {
    final response = await _signedPost(
      '/api/v1/futures/trade/cancel_orders',
      SplayTreeMap<String, Object?>.from({
        'orderList': [
          {'clientId': clientId, 'orderId': orderId},
        ],
        'symbol': symbol,
      }),
      credentials,
    );
    final data = response['data'];
    final failures = data is Map<String, Object?>
        ? _mapList(data['failureList'])
        : const <Map<String, Object?>>[];
    if (failures.isNotEmpty) {
      throw const LocalLiveTradeSafeException(
        'Bitunix did not confirm cancellation of the unresolved entry.',
      );
    }
  }

"""
if 'Future<void> cancelEntryOrder' not in api:
    if api_anchor not in api:
        raise SystemExit('API insertion anchor not found')
    api = api.replace(api_anchor, cancel_method + api_anchor, 1)
api_path.write_text(api)

service_path = Path(
    'src/client/quantara_app/lib/features/auto_trade/application/'
    'local_live_trade_service.dart'
)
service = service_path.read_text()
start_old = """        _entriesEnabled = true;
        _destroyed = false;
"""
start_new = """        _entriesEnabled = true;
        _destroyed = false;
        _sessionStartEquity = null;
"""
if start_old in service:
    service = service.replace(start_old, start_new, 1)
elif '_sessionStartEquity = null;' not in service:
    raise SystemExit('Session-equity reset anchor not found')

old = """      BitunixOrderDetail? detail;
      BitunixLivePosition? position;
      for (var attempt = 0; attempt < 10; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 750));
        detail = await exchange.fetchOrderDetail(
          orderId: placed.orderId,
          credentials: credentials,
        );
        final matches = await exchange.fetchPositions(
          credentials,
          symbol: idea.symbol,
        );
        if (matches.isNotEmpty) position = matches.first;
        if (detail.hasFill && position != null) break;
      }
      if (detail == null || !detail.hasFill || position == null) {
        _entriesEnabled = false;
        throw const LocalLiveTradeSafeException(
          'Entry fill could not be reconciled with a Bitunix position.',
        );
      }
"""
new = """      BitunixOrderDetail? detail;
      BitunixLivePosition? position;
      for (var attempt = 0; attempt < 10; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 750));
        detail = await exchange.fetchOrderDetail(
          orderId: placed.orderId,
          credentials: credentials,
        );
        final matches = await exchange.fetchPositions(
          credentials,
          symbol: idea.symbol,
        );
        position = matches.firstOrNull;
        if (detail.fullyFilled && position != null) break;
      }
      if (detail == null || !detail.fullyFilled || position == null) {
        _entriesEnabled = false;
        _auditEvent(
          'entry_reconciliation',
          'Entry was not fully reconciled; cancellation and fail-closed cleanup started.',
          symbol: idea.symbol,
        );
        try {
          await exchange.cancelEntryOrder(
            symbol: idea.symbol,
            orderId: placed.orderId,
            clientId: placed.clientId,
            credentials: credentials,
          );
        } on Object catch (error) {
          _auditEvent(
            'entry_cancel_failed',
            _safeError(error),
            symbol: idea.symbol,
          );
        }
        for (var attempt = 0; attempt < 10; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 750));
          detail = await exchange.fetchOrderDetail(
            orderId: placed.orderId,
            credentials: credentials,
          );
          final matches = await exchange.fetchPositions(
            credentials,
            symbol: idea.symbol,
          );
          position = matches.firstOrNull;
          if (detail.fullyFilled && position != null) break;
          if (detail.status == 'CANCELED') break;
        }
        if (detail == null || !detail.fullyFilled || position == null) {
          if (position != null && position.quantity > 0) {
            await exchange.closePositionReduceOnly(
              position: position,
              clientId: '$clientId-partial-close',
              credentials: credentials,
            );
            _auditEvent(
              'partial_fill_closed',
              'Unresolved partial fill was closed after entry cancellation.',
              symbol: idea.symbol,
            );
          }
          _executedSetupIds.add(idea.setupId);
          await _persistState();
          throw const LocalLiveTradeSafeException(
            'Entry did not reach a confirmed full fill. The remainder was cancelled and any partial position was closed.',
          );
        }
      }
"""
if old in service:
    service = service.replace(old, new, 1)
elif 'cancellation and fail-closed cleanup started' not in service:
    raise SystemExit('Service reconciliation block not found')
service_path.write_text(service)

test_path = Path(
    'src/client/quantara_app/test/bitunix_local_live_api_client_test.dart'
)
test = test_path.read_text()
if "import 'dart:io';" not in test:
    test = test.replace(
        "import 'dart:convert';\n",
        "import 'dart:convert';\nimport 'dart:io';\n",
        1,
    )
test_case = r'''

  test('cancels an unresolved entry using the official batch contract', () async {
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
          'data': {'successList': ['entry-1'], 'failureList': []},
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
  });

  test('service never treats a partial fill as a protected full entry', () {
    final source = File(
      'lib/features/auto_trade/application/local_live_trade_service.dart',
    ).readAsStringSync();
    expect(source, contains('detail.fullyFilled'));
    expect(source, contains('cancelEntryOrder'));
    expect(source, contains("detail.status == 'CANCELED'"));
    expect(source, isNot(contains('if (detail.hasFill && position != null)'));
  });
'''
if 'official batch contract' not in test:
    index = test.rfind('\n}')
    if index < 0:
        raise SystemExit('Test file closing brace not found')
    test = test[:index] + test_case + test[index:]
test_path.write_text(test)
