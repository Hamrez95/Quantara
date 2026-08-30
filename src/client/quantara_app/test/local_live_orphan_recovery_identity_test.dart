import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/application/local_live_orphan_recovery.dart';
import 'package:quantara_app/features/auto_trade/data/bitunix_local_live_api_client.dart';
import 'package:quantara_app/features/auto_trade/domain/trading_pnl_projection.dart';

void main() {
  final openedAt = DateTime.utc(2026, 8, 30, 12);
  const position = BitunixLivePosition(
    positionId: 'xrp-position-1',
    symbol: 'XRPUSDT',
    quantity: 10,
    side: 'BUY',
    marginMode: 'ISOLATION',
    positionMode: 'HEDGE',
    leverage: 5,
    averageOpenPrice: 1.0,
    realizedPnl: 0,
    unrealizedPnl: 0,
    fee: 0,
    funding: 0,
  );
  const rules = BitunixInstrumentRules(
    symbol: 'XRPUSDT',
    minimumQuantity: 0.1,
    maximumMarketQuantity: 100000,
    quantityPrecision: 1,
    pricePrecision: 4,
    minimumLeverage: 1,
    maximumLeverage: 125,
    open: true,
    apiSupported: true,
  );
  const entryOrder = BitunixOrderDetail(
    orderId: 'entry-order',
    clientId: 'q-local-abcdef12',
    symbol: 'XRPUSDT',
    quantity: 10,
    filledQuantity: 10,
    status: 'FILLED',
    fee: 0,
    realizedPnl: 0,
  );
  const protection = <BitunixPendingProtection>[
    BitunixPendingProtection(
      orderId: 'stop-1',
      positionId: 'xrp-position-1',
      symbol: 'XRPUSDT',
      takeProfitPrice: 0,
      stopLossPrice: 0.95,
      takeProfitQuantity: 0,
      stopLossQuantity: 10,
    ),
    BitunixPendingProtection(
      orderId: 'tp-1',
      positionId: 'xrp-position-1',
      symbol: 'XRPUSDT',
      takeProfitPrice: 1.1,
      stopLossPrice: 0,
      takeProfitQuantity: 10,
      stopLossQuantity: 0,
    ),
  ];

  PositionPnlProjection verifiedProjection() {
    return TradingPnlProjection.reconcile(
      currency: 'USDT',
      asOf: openedAt.add(const Duration(minutes: 1)),
      unrealizedByPosition: const {
        'xrp-position-1': ExchangeUnrealizedPnl(
          positionId: 'xrp-position-1',
          symbol: 'XRPUSDT',
          value: 0,
        ),
      },
      fills: [
        ExchangePnlFill(
          tradeId: 'entry-trade',
          orderId: 'entry-order',
          positionId: 'xrp-position-1',
          symbol: 'XRPUSDT',
          quantity: 10,
          price: 1,
          realizedPnl: 0,
          fee: 0,
          reduceOnly: false,
          occurredAt: openedAt,
          clientId: 'q-local-abcdef12',
          side: 'BUY',
        ),
      ],
      settlements: const [],
      fillsAvailable: true,
      settlementsAvailable: true,
      sourceVerified: true,
    ).forPositionId('xrp-position-1')!;
  }

  test('refuses a pnl projection bound to another symbol', () {
    final json = Map<String, Object?>.from(verifiedProjection().toJson());
    json['symbol'] = 'BTCUSDT';
    final inconsistent = PositionPnlProjection.fromJson(json);

    final decision = LocalLiveOrphanRecoveryPolicy.evaluate(
      position: position,
      pnl: inconsistent,
      protection: protection,
      entryOrder: entryOrder,
      rules: rules,
    );

    expect(decision.allowed, isFalse);
    expect(decision.reason, contains('PnL exchange identity'));
  });

  test('refuses an entry fill bound to another symbol', () {
    final json = Map<String, Object?>.from(verifiedProjection().toJson());
    final fills = (json['fills']! as List<Object?>)
        .map((item) => Map<String, Object?>.from(item! as Map))
        .toList(growable: false);
    fills.first['symbol'] = 'BTCUSDT';
    json['fills'] = fills;
    final inconsistent = PositionPnlProjection.fromJson(json);

    final decision = LocalLiveOrphanRecoveryPolicy.evaluate(
      position: position,
      pnl: inconsistent,
      protection: protection,
      entryOrder: entryOrder,
      rules: rules,
    );

    expect(decision.allowed, isFalse);
    expect(decision.reason, contains('fill exchange identity'));
  });
}
