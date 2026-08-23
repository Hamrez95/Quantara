import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/domain/local_live_preferences.dart';
import 'package:quantara_app/features/auto_trade/domain/local_live_trade_models.dart';
import 'package:quantara_app/features/auto_trade/domain/profit_protection_policy.dart';
import 'package:quantara_app/features/trading/domain/trade_idea.dart';

void main() {
  test('new Local Live plans default to 65/20/15', () {
    const allocation = ProfitProtectionTargetAllocation.defaultAllocation;

    expect(allocation.fractions, const [0.65, 0.20, 0.15]);
    expect(allocation.activeTargetCount, 3);
  });

  test('custom 70/20/10 allocation survives configuration JSON round-trip', () {
    final config = LocalLiveTradingConfig(
      apiKey: 'key',
      secretKey: 'secret',
      riskPerTradeUsdt: 2,
      maxConcurrentPositions: 2,
      stopCooldownMinutes: 15,
      symbols: const ['BTCUSDT'],
      timeframes: const ['15m'],
      strategyIds: const ['professional_auto'],
      targetAllocation: ProfitProtectionTargetAllocation.checked(
        tp1Fraction: 0.70,
        tp2Fraction: 0.20,
        tp3Fraction: 0.10,
      ),
    );

    final restored = LocalLiveTradingConfig.fromJson(config.toJson());
    expect(restored.targetAllocation.fractions, const [0.70, 0.20, 0.10]);
  });

  test('one and two active targets survive configuration JSON round-trip', () {
    final oneTarget = ProfitProtectionTargetAllocation.checked(
      tp1Fraction: 1,
      tp2Fraction: 0,
      tp3Fraction: 0,
    );
    final twoTargets = ProfitProtectionTargetAllocation.checked(
      tp1Fraction: 0.70,
      tp2Fraction: 0.30,
      tp3Fraction: 0,
    );

    expect(
      ProfitProtectionTargetAllocation.fromJson(oneTarget.toJson()).fractions,
      const [1.0, 0.0, 0.0],
    );
    expect(
      ProfitProtectionTargetAllocation.fromJson(twoTargets.toJson()).fractions,
      const [0.70, 0.30, 0.0],
    );
  });

  test('invalid totals, zero TP1 and target gaps fail before arming', () {
    expect(
      () => ProfitProtectionTargetAllocation.checked(
        tp1Fraction: 0.50,
        tp2Fraction: 0.30,
        tp3Fraction: 0.10,
      ),
      throwsArgumentError,
    );
    expect(
      () => ProfitProtectionTargetAllocation.checked(
        tp1Fraction: 0,
        tp2Fraction: 1,
        tp3Fraction: 0,
      ),
      throwsArgumentError,
    );
    expect(
      () => ProfitProtectionTargetAllocation.checked(
        tp1Fraction: 0.70,
        tp2Fraction: 0,
        tp3Fraction: 0.30,
      ),
      throwsArgumentError,
    );
  });

  test(
    'allocation rounds down safely and assigns only exchange dust to TP1',
    () {
      final allocation = ProfitProtectionTargetAllocation.checked(
        tp1Fraction: 0.65,
        tp2Fraction: 0.20,
        tp3Fraction: 0.15,
      ).allocate(
        totalQuantity: 1.003,
        quantityPrecision: 3,
      );

      expect(allocation.quantities, const [0.652, 0.200, 0.151]);
      expect(
        allocation.quantities.reduce((value, element) => value + element),
        closeTo(1.003, 1e-12),
      );
      expect(allocation.quantities.every((value) => value > 0), isTrue);
    },
  );

  test('selected fractions are snapshotted into a managed position', () {
    final managed = LocalLiveManagedPosition(
      setupId: 'setup-xrp',
      symbol: 'XRPUSDT',
      timeframe: '15m',
      direction: TradeDirection.short,
      positionId: 'position-xrp',
      entryOrderId: 'entry-order',
      clientId: 'q-local-0000abcd',
      openedAt: DateTime.utc(2026, 8, 4),
      entryPrice: 1.01,
      initialQuantity: 100,
      originalStopLoss: 1.02,
      targets: const [1.00, 0.99, 0.98],
      leverage: 10,
      targetQuantities: const [70, 20, 10],
      targetOrderIds: const ['tp1', 'tp2', 'tp3'],
      targetAllocation: ProfitProtectionTargetAllocation.checked(
        tp1Fraction: 0.70,
        tp2Fraction: 0.20,
        tp3Fraction: 0.10,
      ),
      stopOrderId: 'stop',
    );

    final restored = LocalLiveManagedPosition.fromJson(managed.toJson());
    expect(restored.targetAllocation.fractions, const [0.70, 0.20, 0.10]);
  });
}
