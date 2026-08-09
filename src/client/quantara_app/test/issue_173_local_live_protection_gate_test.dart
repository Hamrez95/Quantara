import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/domain/auto_trade_models.dart';
import 'package:quantara_app/features/auto_trade/domain/local_live_protection_gate.dart';
import 'package:quantara_app/features/auto_trade/domain/local_live_trade_models.dart';
import 'package:quantara_app/features/auto_trade/domain/profit_lock_stop_policy.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/profit_protection_policy.dart';

void main() {
  final asOf = DateTime.utc(2026, 8, 9, 6, 11, 55);

  AutoTradePosition aavePosition() => const AutoTradePosition(
    positionId: '3518418297103901915',
    symbol: 'AAVEUSDT',
    quantity: 0.1,
    side: 'SELL',
    marginMode: 'ISOLATION',
    positionMode: 'HEDGE',
    leverage: 10,
    margin: 0.9192,
    unrealizedPnl: 0.006,
    liquidationPrice: 99.83,
    averageOpenPrice: 91.26,
  );

  AutoTradeAccountSnapshot account({
    required List<AutoTradeProtectionOrder> protection,
  }) => AutoTradeAccountSnapshot(
    marginCoin: 'USDT',
    available: 28.65,
    frozen: 0,
    positionMargin: 0.9192,
    crossUnrealizedPnl: 0,
    isolatedUnrealizedPnl: 0.006,
    positionMode: 'HEDGE',
    positions: [aavePosition()],
    orders: const [],
    protectionOrders: protection,
    protectionVerifications: {
      '3518418297103901915': AutoTradeProtectionVerification.verified(
        asOf: asOf,
      ),
    },
    syncedAt: asOf,
  );

  LocalLiveManagedPosition managed(
    ProfitProtectionTargetAllocation allocation, {
    String? warning,
  }) => LocalLiveManagedPosition(
    setupId: 'aave-short-1h',
    symbol: 'AAVEUSDT',
    timeframe: '1h',
    direction: TradeDirection.short,
    positionId: '3518418297103901915',
    entryOrderId: '2086128842343002112',
    clientId: 'q-local-test',
    initialQuantity: 0.1,
    entryPrice: 91.26,
    originalStopLoss: 92.36,
    targets: const [88.8, 87.35, 85.9],
    leverage: 10,
    openedAt: DateTime.utc(2026, 8, 8, 16, 34, 9),
    targetAllocation: allocation,
    targetQuantities: const [0.1, 0, 0],
    targetOrderIds: const ['tp-1', '', ''],
    profitLockProgress: ProfitLockProgress(warning: warning),
  );

  final completeOneTargetProtection = <AutoTradeProtectionOrder>[
    const AutoTradeProtectionOrder.takeProfit(
      exchangeId: '8461862445554365515',
      positionId: '3518418297103901915',
      symbol: 'AAVEUSDT',
      price: 88.8,
      quantity: 0.1,
    ),
    const AutoTradeProtectionOrder.stopLoss(
      exchangeId: '6282824502978701723',
      positionId: '3518418297103901915',
      symbol: 'AAVEUSDT',
      price: 92.36,
      quantity: 0.1,
    ),
  ];

  test(
    '100/0/0 full TP plus full SL is fully protected despite PnL warning',
    () {
      final allocation = ProfitProtectionTargetAllocation.checked(
        tp1Fraction: 1,
        tp2Fraction: 0,
        tp3Fraction: 0,
      );

      expect(
        LocalLiveProtectionGate.allManagedPositionsFullyProtected(
          account: account(protection: completeOneTargetProtection),
          managed: [
            managed(
              allocation,
              warning: 'Trade-history attribution is temporarily unverified.',
            ),
          ],
        ),
        isTrue,
      );
    },
  );

  test('three-target plan still fails closed when only TP1 exists', () {
    expect(
      LocalLiveProtectionGate.allManagedPositionsFullyProtected(
        account: account(protection: completeOneTargetProtection),
        managed: [managed(ProfitProtectionTargetAllocation.standard)],
      ),
      isFalse,
    );
  });

  test('unverified protection never opens concurrency gate', () {
    final allocation = ProfitProtectionTargetAllocation.checked(
      tp1Fraction: 1,
      tp2Fraction: 0,
      tp3Fraction: 0,
    );
    final unverified = AutoTradeAccountSnapshot(
      marginCoin: 'USDT',
      available: 28.65,
      frozen: 0,
      positionMargin: 0.9192,
      crossUnrealizedPnl: 0,
      isolatedUnrealizedPnl: 0.006,
      positionMode: 'HEDGE',
      positions: [aavePosition()],
      orders: const [],
      protectionOrders: completeOneTargetProtection,
      protectionVerifications: {
        '3518418297103901915': AutoTradeProtectionVerification.unverified(
          asOf: asOf,
          reason: 'Dedicated protection read failed.',
        ),
      },
      syncedAt: asOf,
    );

    expect(
      LocalLiveProtectionGate.allManagedPositionsFullyProtected(
        account: unverified,
        managed: [managed(allocation)],
      ),
      isFalse,
    );
  });
}
