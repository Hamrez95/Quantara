import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/domain/auto_trade_models.dart';
import 'package:quantara_app/features/auto_trade/domain/exchange_position_ownership.dart';
import 'package:quantara_app/features/auto_trade/domain/local_live_trade_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';

void main() {
  final now = DateTime.utc(2026, 8, 15, 12);

  const position = AutoTradePosition(
    positionId: 'p-1',
    symbol: 'BTCUSDT',
    quantity: 1,
    side: 'LONG',
    marginMode: 'ISOLATION',
    positionMode: 'ONE_WAY',
    leverage: 3,
    margin: 50,
    unrealizedPnl: 2,
    liquidationPrice: 70000,
    averageOpenPrice: 100000,
  );

  List<AutoTradeProtectionOrder> fullProtection() => const [
    AutoTradeProtectionOrder.stopLoss(
      exchangeId: 'sl-1',
      positionId: 'p-1',
      symbol: 'BTCUSDT',
      price: 95000,
      quantity: 1,
    ),
    AutoTradeProtectionOrder.takeProfit(
      exchangeId: 'tp-1',
      positionId: 'p-1',
      symbol: 'BTCUSDT',
      price: 103000,
      quantity: 0.4,
    ),
    AutoTradeProtectionOrder.takeProfit(
      exchangeId: 'tp-2',
      positionId: 'p-1',
      symbol: 'BTCUSDT',
      price: 106000,
      quantity: 0.3,
    ),
    AutoTradeProtectionOrder.takeProfit(
      exchangeId: 'tp-3',
      positionId: 'p-1',
      symbol: 'BTCUSDT',
      price: 110000,
      quantity: 0.3,
    ),
  ];

  AutoTradeAccountSnapshot account({
    List<AutoTradePosition> positions = const [position],
    List<AutoTradeOrder> orders = const [],
    List<AutoTradeProtectionOrder>? protectionOrders,
    bool verified = true,
  }) => AutoTradeAccountSnapshot(
    marginCoin: 'USDT',
    available: 450,
    frozen: 0,
    positionMargin: 50,
    crossUnrealizedPnl: 0,
    isolatedUnrealizedPnl: 2,
    positionMode: 'ONE_WAY',
    positions: positions,
    orders: orders,
    protectionOrders: protectionOrders ?? fullProtection(),
    protectionVerifications: {
      for (final item in positions)
        if (item.positionId.isNotEmpty)
          item.positionId: verified
              ? AutoTradeProtectionVerification.verified(asOf: now)
              : AutoTradeProtectionVerification.unverified(
                  asOf: now,
                  reason: 'unverified',
                ),
    },
    syncedAt: now,
  );

  LocalLiveManagedPosition managed() => LocalLiveManagedPosition(
    setupId: 'setup-1',
    symbol: 'BTCUSDT',
    timeframe: '1h',
    direction: TradeDirection.long,
    positionId: 'p-1',
    entryOrderId: 'entry-1',
    clientId: 'client-1',
    initialQuantity: 1,
    entryPrice: 100000,
    originalStopLoss: 95000,
    targets: const [103000, 106000, 110000],
    leverage: 3,
    openedAt: now.subtract(const Duration(hours: 2)),
    stopOrderId: 'sl-1',
    targetQuantities: const [0.4, 0.3, 0.3],
    targetOrderIds: const ['tp-1', 'tp-2', 'tp-3'],
  );

  test('exact persisted ownership remains managed', () {
    final result = ExchangePositionOwnershipClassifier.classify(
      account: account(),
      managedPositions: [managed()],
    );

    expect(result.managedCount, 1);
    expect(result.blocksNewEntries, isFalse);
    expect(result.positions.single.kind, ExchangePositionOwnershipKind.managed);
  });

  test(
    'fully protected orphan is not recoverable until history is verified clear',
    () {
      final result = ExchangePositionOwnershipClassifier.classify(
        account: account(),
        managedPositions: const [],
      );

      final orphan = result.positions.single;
      expect(orphan.kind, ExchangePositionOwnershipKind.externalUnmanaged);
      expect(
        orphan.recoveryBlocks,
        contains(ExchangePositionRecoveryBlock.exchangeHistoryNotVerifiedClear),
      );
      expect(result.blocksNewEntries, isTrue);
    },
  );

  test(
    'history-clear isolated fully protected orphan becomes recoverable only',
    () {
      final result = ExchangePositionOwnershipClassifier.classify(
        account: account(),
        managedPositions: const [],
        historyVerifiedClearPositionIds: const ['p-1'],
      );

      final orphan = result.positions.single;
      expect(orphan.kind, ExchangePositionOwnershipKind.recoverableOrphan);
      expect(orphan.recoverable, isTrue);
      expect(orphan.blocksNewEntries, isTrue);
      expect(result.freeSlots(3), 2);
    },
  );

  test(
    'missing TP ladder or unverified protection can never be recoverable',
    () {
      final missingTp = ExchangePositionOwnershipClassifier.classify(
        account: account(
          protectionOrders: fullProtection().take(3).toList(growable: false),
        ),
        managedPositions: const [],
        historyVerifiedClearPositionIds: const ['p-1'],
      ).positions.single;
      expect(
        missingTp.recoveryBlocks,
        contains(ExchangePositionRecoveryBlock.protectionIncomplete),
      );

      final unverified = ExchangePositionOwnershipClassifier.classify(
        account: account(verified: false),
        managedPositions: const [],
        historyVerifiedClearPositionIds: const ['p-1'],
      ).positions.single;
      expect(
        unverified.recoveryBlocks,
        contains(ExchangePositionRecoveryBlock.protectionUnverified),
      );
    },
  );

  test('regular pending order or cross margin forces external/unmanaged', () {
    const pending = AutoTradeOrder(
      orderId: 'o-1',
      clientId: 'c-1',
      symbol: 'BTCUSDT',
      quantity: 1,
      filledQuantity: 0,
      side: 'SELL',
      orderType: 'LIMIT',
      marginMode: 'ISOLATION',
      leverage: 3,
      reduceOnly: true,
    );
    final withOrder = ExchangePositionOwnershipClassifier.classify(
      account: account(orders: const [pending]),
      managedPositions: const [],
      historyVerifiedClearPositionIds: const ['p-1'],
    ).positions.single;
    expect(
      withOrder.recoveryBlocks,
      contains(ExchangePositionRecoveryBlock.conflictingRegularOrders),
    );

    const cross = AutoTradePosition(
      positionId: 'p-1',
      symbol: 'BTCUSDT',
      quantity: 1,
      side: 'LONG',
      marginMode: 'CROSS',
      positionMode: 'ONE_WAY',
      leverage: 3,
      margin: 50,
      unrealizedPnl: 2,
      liquidationPrice: 70000,
      averageOpenPrice: 100000,
    );
    final crossResult = ExchangePositionOwnershipClassifier.classify(
      account: account(positions: const [cross]),
      managedPositions: const [],
      historyVerifiedClearPositionIds: const ['p-1'],
    ).positions.single;
    expect(
      crossResult.recoveryBlocks,
      contains(ExchangePositionRecoveryBlock.nonIsolatedMargin),
    );
  });

  test('exchange truth, not local managed count, consumes portfolio slots', () {
    final result = ExchangePositionOwnershipClassifier.classify(
      account: account(),
      managedPositions: const [],
    );

    expect(result.exchangeOpenPositionCount, 1);
    expect(result.managedCount, 0);
    expect(result.hasContradictoryLocalCount, isTrue);
    expect(result.consumedSlots(3), 1);
    expect(result.freeSlots(3), 2);
  });
}
