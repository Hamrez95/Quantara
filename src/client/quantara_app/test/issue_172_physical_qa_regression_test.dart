import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quantara_app/features/auto_trade/application/auto_trade_controller.dart';
import 'package:quantara_app/features/auto_trade/data/bitunix_pnl_mapper.dart';
import 'package:quantara_app/features/auto_trade/data/bitunix_private_api_client.dart';
import 'package:quantara_app/features/auto_trade/data/secure_auto_trade_credentials_store.dart';
import 'package:quantara_app/features/auto_trade/domain/auto_trade_models.dart';
import 'package:quantara_app/features/auto_trade/domain/private_account_reconciliation.dart';
import 'package:quantara_app/features/auto_trade/domain/trading_pnl_projection.dart';

void main() {
  test(
    'old unattributed GRAM trade stays diagnostic but does not block open BNB',
    () {
      final bnbOpenedAt = DateTime.utc(2026, 8, 8, 10);
      final oldTradeAt = DateTime.utc(2026, 8, 5, 3, 19, 14);
      final open = <ExchangeUnrealizedPnl>[
        ExchangeUnrealizedPnl(
          positionId: 'bnb-open',
          symbol: 'BNBUSDT',
          value: -0.0228,
          realizedPnl: 0,
          fee: 0,
          funding: 0,
          openedAt: bnbOpenedAt,
        ),
      ];
      final fills = BitunixPnlMapper.fills(
        {
          'tradeList': [
            {
              'tradeId': '2795413522294203930',
              'orderId': '7352379888826528074',
              'symbol': 'GRAMUSDT',
              'qty': '42.9',
              'price': '1.389',
              'realizedPNL': '-0.2574',
              'fee': '0.03575286',
              'ctime': oldTradeAt.millisecondsSinceEpoch,
              'reduceOnly': true,
              'side': 'SELL',
            },
          ],
        },
        openPositions: open,
        settlements: const [],
      );

      expect(fills.verified, isTrue);
      expect(fills.warning, contains('could not be assigned'));
      expect(
        fills.values.single.positionId,
        'unassigned-trade:2795413522294203930',
      );

      final projection = TradingPnlProjection.reconcile(
        currency: 'USDT',
        asOf: DateTime.utc(2026, 8, 8, 10, 5),
        unrealizedByPosition: {open.single.positionId: open.single},
        fills: fills.values,
        settlements: const [],
        sourceVerified: fills.verified,
      );

      expect(projection.isVerified, isTrue);
      expect(projection.isReadyForRiskGates, isTrue);
      expect(projection.forPositionId('bnb-open')?.isVerified, isTrue);
      final quarantined = projection.positions.singleWhere(
        (item) => item.positionId.startsWith('unassigned-trade:'),
      );
      expect(quarantined.isVerified, isFalse);
      expect(quarantined.warning, contains('quarantined'));
    },
  );

  test(
    'unattributed fill that could belong to an active same-symbol position blocks',
    () {
      final openedAt = DateTime.utc(2026, 8, 8, 10);
      final tradeAt = openedAt.add(const Duration(minutes: 5));
      final open = <ExchangeUnrealizedPnl>[
        ExchangeUnrealizedPnl(
          positionId: 'bnb-a',
          symbol: 'BNBUSDT',
          value: 0,
          realizedPnl: 0,
          fee: 0,
          funding: 0,
          openedAt: openedAt,
        ),
        ExchangeUnrealizedPnl(
          positionId: 'bnb-b',
          symbol: 'BNBUSDT',
          value: 0,
          realizedPnl: 0,
          fee: 0,
          funding: 0,
          openedAt: openedAt,
        ),
      ];
      final fills = BitunixPnlMapper.fills(
        {
          'tradeList': [
            {
              'tradeId': 'active-ambiguous',
              'orderId': 'active-order',
              'symbol': 'BNBUSDT',
              'qty': '0.01',
              'price': '596.2',
              'realizedPNL': '0',
              'fee': '0.001',
              'ctime': tradeAt.millisecondsSinceEpoch,
              'reduceOnly': false,
              'side': 'BUY',
            },
          ],
        },
        openPositions: open,
        settlements: const [],
      );
      expect(fills.verified, isTrue);
      expect(
        fills.values.single.positionId,
        'unassigned-trade:active-ambiguous',
      );

      final projection = TradingPnlProjection.reconcile(
        currency: 'USDT',
        asOf: tradeAt.add(const Duration(seconds: 1)),
        unrealizedByPosition: {for (final item in open) item.positionId: item},
        fills: fills.values,
        settlements: const [],
        sourceVerified: fills.verified,
      );
      expect(projection.isVerified, isFalse);
      expect(projection.isReadyForRiskGates, isFalse);
    },
  );

  test(
    'Local Live mismatch is confirmed before listeners can see divergent state',
    () async {
      var pendingPositionReads = 0;
      final now = DateTime.utc(2026, 8, 8, 12);
      final client = MockClient((request) async {
        if (request.url.path ==
            '/api/v1/futures/position/get_pending_positions') {
          pendingPositionReads += 1;
        }
        return _response(
          request.url.path,
          includeOpenPosition: pendingPositionReads <= 1,
        );
      });
      final controller = AutoTradeController(
        apiClient: BitunixPrivateApiClient(client: client, utcNow: () => now),
        credentialsStore: _MemoryCredentialsStore(_credentials),
        utcNow: () => now,
      );
      final observedHealth = <PrivateAccountReconciliationHealth>[];
      controller.addListener(
        () => observedHealth.add(controller.reconciliation.health),
      );
      addTearDown(() {
        controller.dispose();
        client.close();
      });

      await controller.initialize();
      observedHealth.clear();
      final ok = await controller.observeLocalLiveOpenPositions(
        openPositionCount: 0,
        observedAt: now.add(const Duration(seconds: 5)),
        exchangeSyncedAt: now.add(const Duration(seconds: 5)),
      );

      expect(ok, isTrue);
      expect(controller.snapshot?.positions, isEmpty);
      expect(
        controller.reconciliation.health,
        PrivateAccountReconciliationHealth.fresh,
      );
      expect(
        observedHealth,
        isNot(contains(PrivateAccountReconciliationHealth.divergent)),
      );
    },
  );

  test(
    'persistent Local Live mismatch still fails closed after confirmation',
    () async {
      final now = DateTime.utc(2026, 8, 8, 12);
      final client = MockClient(
        (request) async =>
            _response(request.url.path, includeOpenPosition: true),
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
      final ok = await controller.observeLocalLiveOpenPositions(
        openPositionCount: 0,
        observedAt: now.add(const Duration(seconds: 5)),
        exchangeSyncedAt: now.add(const Duration(seconds: 5)),
      );

      expect(ok, isFalse);
      expect(
        controller.reconciliation.health,
        PrivateAccountReconciliationHealth.divergent,
      );
      expect(controller.reconciliation.blocksNewEntries, isTrue);
      expect(controller.canManageExistingPosition, isTrue);
    },
  );

  test(
    'dispose during delayed connect completion does not throw or notify afterward',
    () async {
      final gate = Completer<void>();
      final client = MockClient((request) async {
        await gate.future;
        return _response(request.url.path, includeOpenPosition: false);
      });
      final controller = AutoTradeController(
        apiClient: BitunixPrivateApiClient(client: client),
        credentialsStore: _MemoryCredentialsStore(null),
      );
      var notifications = 0;
      controller.addListener(() => notifications += 1);
      final operation = controller.connect(
        apiKey: _credentials.apiKey,
        secretKey: _credentials.secretKey,
      );
      await Future<void>.delayed(Duration.zero);
      controller.dispose();
      final beforeRelease = notifications;
      gate.complete();
      await operation;
      expect(notifications, beforeRelease);
      client.close();
    },
  );

  test('source keeps fast sync, centered loader and real indicator wiring', () {
    final privateSource = File(
      'lib/features/auto_trade/data/bitunix_private_api_client.dart',
    ).readAsStringSync();
    final pageSource = File(
      'lib/features/owner_alpha/presentation/owner_alpha_page.dart',
    ).readAsStringSync();
    final strategySource = File(
      'lib/features/owner_alpha/data/professional_strategy_engine.dart',
    ).readAsStringSync();
    final serviceSource = File(
      'lib/features/auto_trade/application/local_live_trade_service.dart',
    ).readAsStringSync();

    expect(privateSource, contains('Future.wait<Map<String, Object?>>'));
    expect(privateSource, contains('_signedGetCachedCompleteHistory'));
    expect(privateSource, contains("merged.length != total"));
    expect(pageSource, contains('SliverFillRemaining('));
    expect(pageSource, contains('hasScrollBody: false'));
    expect(
      strategySource,
      contains('indicatorSnapshot: _indicatorSnapshot(indicators)'),
    );
    for (final key in const [
      'ema20',
      'ema50',
      'ema200',
      'atr14',
      'rsi14',
      'adx14',
      'plusDi14',
      'minusDi14',
      'relativeVolume20',
      'volumeZScore20',
      'trendEfficiency20',
      'recentSwingHigh',
      'recentSwingLow',
    ]) {
      expect(strategySource, contains("'$key': value.$key"));
    }
    expect(
      serviceSource,
      isNot(
        contains(
          'final account = await exchange.fetchAccountSnapshot(credentials);\n      final positions = await exchange.fetchPositions(credentials);',
        ),
      ),
    );
  });
}

const _credentials = BitunixApiCredentials(
  apiKey: 'test-api-key-123',
  secretKey: 'test-secret-key-123',
);

http.Response _response(String path, {required bool includeOpenPosition}) {
  final Object data = switch (path) {
    '/api/v1/futures/account' => {
      'marginCoin': 'USDT',
      'available': '29.0',
      'frozen': '0',
      'margin': includeOpenPosition ? '2.4' : '0',
      'crossUnrealizedPNL': '0',
      'isolationUnrealizedPNL': includeOpenPosition ? '-0.02' : '0',
      'positionMode': 'HEDGE',
    },
    '/api/v1/futures/position/get_pending_positions' =>
      includeOpenPosition
          ? [
              {
                'positionId': 'bnb-position',
                'symbol': 'BNBUSDT',
                'qty': '0.04',
                'side': 'LONG',
                'marginMode': 'ISOLATION',
                'positionMode': 'HEDGE',
                'leverage': '10',
                'margin': '2.4',
                'unrealizedPNL': '-0.02',
                'liqPrice': '500',
                'avgOpenPrice': '596.26',
                'ctime': DateTime.utc(2026, 8, 8, 10).millisecondsSinceEpoch,
              },
            ]
          : <Object>[],
    '/api/v1/futures/trade/get_pending_orders' => {'orderList': <Object>[]},
    '/api/v1/futures/tpsl/get_pending_orders' => {'orderList': <Object>[]},
    '/api/v1/futures/position/get_history_positions' => {
      'positionList': <Object>[],
      'total': 0,
    },
    '/api/v1/futures/trade/get_history_trades' => {
      'tradeList': <Object>[],
      'total': 0,
    },
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
