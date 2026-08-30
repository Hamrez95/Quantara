import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/application/local_live_orphan_recovery.dart';
import 'package:quantara_app/features/auto_trade/data/bitunix_local_live_api_client.dart';
import 'package:quantara_app/features/auto_trade/domain/trading_pnl_projection.dart';

void main() {
  final openedAt = DateTime.utc(2026, 8, 29, 8);
  const position = BitunixLivePosition(
    positionId: 'position-1',
    symbol: 'XRPUSDT',
    quantity: 10,
    side: 'LONG',
    marginMode: 'ISOLATION',
    positionMode: 'HEDGE',
    leverage: 5,
    averageOpenPrice: 1,
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
    orderId: 'entry-1',
    clientId: 'q-local-abcdef12',
    symbol: 'XRPUSDT',
    quantity: 10,
    filledQuantity: 10,
    status: 'FILLED',
    fee: 0,
    realizedPnl: 0,
  );

  PositionPnlProjection pnl() => TradingPnlProjection.reconcile(
    currency: 'USDT',
    asOf: openedAt.add(const Duration(minutes: 1)),
    unrealizedByPosition: const {
      'position-1': ExchangeUnrealizedPnl(
        positionId: 'position-1',
        symbol: 'XRPUSDT',
        value: 0,
        realizedPnl: 0,
        fee: 0,
        funding: 0,
      ),
    },
    fills: [
      ExchangePnlFill(
        tradeId: 'trade-1',
        orderId: 'entry-1',
        positionId: 'position-1',
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
  ).forPositionId('position-1')!;

  List<BitunixPendingProtection> protection(double stopQuantity) => [
    BitunixPendingProtection(
      orderId: 'stop-1',
      positionId: 'position-1',
      symbol: 'XRPUSDT',
      takeProfitPrice: 0,
      stopLossPrice: 0.9,
      takeProfitQuantity: 0,
      stopLossQuantity: stopQuantity,
    ),
    const BitunixPendingProtection(
      orderId: 'tp-1',
      positionId: 'position-1',
      symbol: 'XRPUSDT',
      takeProfitPrice: 1.1,
      stopLossPrice: 0,
      takeProfitQuantity: 10,
      stopLossQuantity: 0,
    ),
  ];

  test('recovery accepts Bitunix whole-position stop semantics', () {
    final decision = LocalLiveOrphanRecoveryPolicy.evaluate(
      position: position,
      pnl: pnl(),
      protection: protection(0),
      entryOrder: entryOrder,
      rules: rules,
    );

    expect(decision.allowed, isTrue);
    expect(decision.managed?.stopOrderId, 'stop-1');
  });

  test('recovery still rejects a positive undersized stop quantity', () {
    final decision = LocalLiveOrphanRecoveryPolicy.evaluate(
      position: position,
      pnl: pnl(),
      protection: protection(5),
      entryOrder: entryOrder,
      rules: rules,
    );

    expect(decision.allowed, isFalse);
    expect(decision.reason, contains('does not cover'));
  });
}
