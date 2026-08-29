import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/application/local_live_orphan_recovery.dart';
import 'package:quantara_app/features/auto_trade/data/bitunix_local_live_api_client.dart';
import 'package:quantara_app/features/auto_trade/domain/trading_pnl_projection.dart';

void main() {
  final openedAt = DateTime.utc(2026, 8, 5, 6);
  const position = BitunixLivePosition(
    positionId: 'xrp-position-1',
    symbol: 'XRPUSDT',
    quantity: 67.8,
    side: 'BUY',
    marginMode: 'ISOLATION',
    positionMode: 'HEDGE',
    leverage: 10,
    averageOpenPrice: 1.069,
    realizedPnl: 0,
    unrealizedPnl: 0.217,
    fee: 0.0434,
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

  PositionPnlProjection projection({
    bool withExit = false,
    bool sourceVerified = true,
  }) {
    final fills = <ExchangePnlFill>[
      ExchangePnlFill(
        tradeId: 'entry-trade',
        orderId: 'entry-order',
        positionId: 'xrp-position-1',
        symbol: 'XRPUSDT',
        quantity: 67.8,
        price: 1.069,
        realizedPnl: 0,
        fee: 0.0434,
        reduceOnly: false,
        occurredAt: openedAt,
        clientId: 'q-local-abcdef12',
        side: 'BUY',
      ),
      if (withExit)
        ExchangePnlFill(
          tradeId: 'exit-trade',
          orderId: 'tp-1',
          positionId: 'xrp-position-1',
          symbol: 'XRPUSDT',
          quantity: 1,
          price: 1.0746,
          realizedPnl: 0.0056,
          fee: 0.001,
          reduceOnly: true,
          occurredAt: openedAt.add(const Duration(minutes: 5)),
        ),
    ];
    return TradingPnlProjection.reconcile(
      currency: 'USDT',
      asOf: openedAt.add(const Duration(minutes: 10)),
      unrealizedByPosition: const {
        'xrp-position-1': ExchangeUnrealizedPnl(
          positionId: 'xrp-position-1',
          symbol: 'XRPUSDT',
          value: 0.217,
          realizedPnl: 0,
          fee: 0.0434,
          funding: 0,
        ),
      },
      fills: fills,
      settlements: const [],
      fillsAvailable: true,
      settlementsAvailable: true,
      sourceVerified: sourceVerified,
    ).forPositionId('xrp-position-1')!;
  }

  List<BitunixPendingProtection> protection() => const [
    BitunixPendingProtection(
      orderId: 'stop-1',
      positionId: 'xrp-position-1',
      symbol: 'XRPUSDT',
      takeProfitPrice: 0,
      stopLossPrice: 1.0647,
      takeProfitQuantity: 0,
      stopLossQuantity: 67.8,
    ),
    BitunixPendingProtection(
      orderId: 'tp-1',
      positionId: 'xrp-position-1',
      symbol: 'XRPUSDT',
      takeProfitPrice: 1.0746,
      stopLossPrice: 0,
      takeProfitQuantity: 51,
      stopLossQuantity: 0,
    ),
    BitunixPendingProtection(
      orderId: 'tp-2',
      positionId: 'xrp-position-1',
      symbol: 'XRPUSDT',
      takeProfitPrice: 1.0794,
      stopLossPrice: 0,
      takeProfitQuantity: 13.5,
      stopLossQuantity: 0,
    ),
    BitunixPendingProtection(
      orderId: 'tp-3',
      positionId: 'xrp-position-1',
      symbol: 'XRPUSDT',
      takeProfitPrice: 1.0841,
      stopLossPrice: 0,
      takeProfitQuantity: 3.3,
      stopLossQuantity: 0,
    ),
  ];

  const quantaraOrder = BitunixOrderDetail(
    orderId: 'entry-order',
    clientId: 'q-local-abcdef12',
    symbol: 'XRPUSDT',
    quantity: 67.8,
    filledQuantity: 67.8,
    status: 'FILLED',
    fee: 0.0434,
    realizedPnl: 0,
  );

  test('recovers the physical XRP position from complete exchange truth', () {
    final decision = LocalLiveOrphanRecoveryPolicy.evaluate(
      position: position,
      pnl: projection(),
      protection: protection(),
      entryOrder: quantaraOrder,
      rules: rules,
    );

    expect(decision.allowed, isTrue);
    final managed = decision.managed!;
    expect(managed.positionId, 'xrp-position-1');
    expect(managed.initialQuantity, 67.8);
    expect(managed.originalStopLoss, 1.0647);
    expect(managed.targetQuantities, [51, 13.5, 3.3]);
    expect(managed.targetOrderIds, ['tp-1', 'tp-2', 'tp-3']);
    expect(managed.clientId, startsWith('q-local-'));
    expect(
      managed.targetAllocation.fractions.reduce((a, b) => a + b),
      closeTo(1, 1e-9),
    );
  });

  test('refuses a manual or foreign entry order', () {
    const manualOrder = BitunixOrderDetail(
      orderId: 'entry-order',
      clientId: 'manual-mobile-order',
      symbol: 'XRPUSDT',
      quantity: 67.8,
      filledQuantity: 67.8,
      status: 'FILLED',
      fee: 0.0434,
      realizedPnl: 0,
    );
    final decision = LocalLiveOrphanRecoveryPolicy.evaluate(
      position: position,
      pnl: projection(),
      protection: protection(),
      entryOrder: manualOrder,
      rules: rules,
    );
    expect(decision.allowed, isFalse);
    expect(decision.reason, contains('not a verified Quantara'));
  });

  test('refuses a position that was already partially closed', () {
    final decision = LocalLiveOrphanRecoveryPolicy.evaluate(
      position: position,
      pnl: projection(withExit: true),
      protection: protection(),
      entryOrder: quantaraOrder,
      rules: rules,
    );
    expect(decision.allowed, isFalse);
    expect(decision.reason, contains('partially closed'));
  });

  test('refuses unverified exchange history', () {
    final decision = LocalLiveOrphanRecoveryPolicy.evaluate(
      position: position,
      pnl: projection(sourceVerified: false),
      protection: protection(),
      entryOrder: quantaraOrder,
      rules: rules,
    );
    expect(decision.allowed, isFalse);
    expect(decision.reason, contains('not exchange-verified'));
  });

  test('refuses incomplete protection', () {
    final incomplete = protection().toList()..removeLast();
    final decision = LocalLiveOrphanRecoveryPolicy.evaluate(
      position: position,
      pnl: projection(),
      protection: incomplete,
      entryOrder: quantaraOrder,
      rules: rules,
    );
    expect(decision.allowed, isFalse);
    expect(decision.reason, contains('do not cover'));
  });

  test('REST fallback accepts exactly one valid position candidate', () {
    final candidates = <BitunixLivePosition>[position];
    expect(candidates.firstOrNull?.positionId, 'xrp-position-1');
  });

  test('REST fallback treats an empty position set as flat', () {
    expect(<BitunixLivePosition>[].firstOrNull, isNull);
  });

  test('REST fallback retains risk for ambiguous position candidates', () {
    const second = BitunixLivePosition(
      positionId: 'xrp-position-2',
      symbol: 'XRPUSDT',
      quantity: 10,
      side: 'SELL',
      marginMode: 'ISOLATION',
      positionMode: 'HEDGE',
      leverage: 10,
      averageOpenPrice: 1.07,
      realizedPnl: 0,
      unrealizedPnl: 0,
      fee: 0,
      funding: 0,
    );
    final candidates = <BitunixLivePosition>[position, second];
    expect(() => candidates.firstOrNull, throwsStateError);
  });

  test('REST fallback retains risk for invalid single-position identity', () {
    const invalid = BitunixLivePosition(
      positionId: '',
      symbol: 'XRPUSDT',
      quantity: 67.8,
      side: 'BUY',
      marginMode: 'ISOLATION',
      positionMode: 'HEDGE',
      leverage: 10,
      averageOpenPrice: 1.069,
      realizedPnl: 0,
      unrealizedPnl: 0,
      fee: 0,
      funding: 0,
    );
    expect(() => <BitunixLivePosition>[invalid].firstOrNull, throwsStateError);
  });
}
