import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/domain/local_live_trade_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/profit_protection_policy.dart';

void main() {
  LocalLiveTradeConfiguration configuration({
    ProfitProtectionTargetAllocation targetAllocation =
        ProfitProtectionTargetAllocation.standard,
  }) => LocalLiveTradeConfiguration(
    symbols: const ['XRPUSDT'],
    timeframes: const ['15m'],
    leverage: 10,
    riskPercent: 0.5,
    dailyLossLimitPercent: 2,
    maximumConcurrentPositions: 1,
    strategy: AnalysisStrategy.structureZones,
    cadence: SignalCadence.balanced,
    languageCode: 'fa',
    targetAllocation: targetAllocation,
  );

  test('new Local Live plans default to 65/20/15', () {
    final value = configuration();

    expect(value.targetAllocation.tp1Fraction, closeTo(0.65, 0.0000001));
    expect(value.targetAllocation.tp2Fraction, closeTo(0.20, 0.0000001));
    expect(value.targetAllocation.tp3Fraction, closeTo(0.15, 0.0000001));
    value.validate();
  });

  test('custom 70/20/10 allocation survives configuration JSON round-trip', () {
    final allocation = ProfitProtectionTargetAllocation.checked(
      tp1Fraction: 0.70,
      tp2Fraction: 0.20,
      tp3Fraction: 0.10,
    );
    final restored = LocalLiveTradeConfiguration.fromJson(
      configuration(targetAllocation: allocation).toJson(),
    );

    expect(restored.targetAllocation, allocation);
    expect(restored.targetAllocation.fractions, const [0.70, 0.20, 0.10]);
  });

  test('one and two active targets survive configuration JSON round-trip', () {
    final oneTarget = ProfitProtectionTargetAllocation.checked(
      tp1Fraction: 1,
      tp2Fraction: 0,
      tp3Fraction: 0,
    );
    final twoTargets = ProfitProtectionTargetAllocation.checked(
      tp1Fraction: 0.80,
      tp2Fraction: 0.20,
      tp3Fraction: 0,
    );

    expect(
      LocalLiveTradeConfiguration.fromJson(
        configuration(targetAllocation: oneTarget).toJson(),
      ).targetAllocation,
      oneTarget,
    );
    expect(
      LocalLiveTradeConfiguration.fromJson(
        configuration(targetAllocation: twoTargets).toJson(),
      ).targetAllocation,
      twoTargets,
    );
  });

  test('invalid totals, zero TP1 and target gaps fail before arming', () {
    expect(
      () => ProfitProtectionTargetAllocation.checked(
        tp1Fraction: 0.70,
        tp2Fraction: 0.20,
        tp3Fraction: 0.20,
      ),
      throwsFormatException,
    );
    expect(
      () => ProfitProtectionTargetAllocation.checked(
        tp1Fraction: 0,
        tp2Fraction: 0.80,
        tp3Fraction: 0.20,
      ),
      throwsFormatException,
    );
    expect(
      () => ProfitProtectionTargetAllocation.checked(
        tp1Fraction: 0.80,
        tp2Fraction: 0,
        tp3Fraction: 0.20,
      ),
      throwsFormatException,
    );
    expect(
      () => ProfitProtectionTargetAllocation.checked(
        tp1Fraction: 0.80,
        tp2Fraction: -0.05,
        tp3Fraction: 0.25,
      ),
      throwsFormatException,
    );
  });

  test(
    'allocation rounds down safely and assigns only exchange dust to TP1',
    () {
      final plan = ProfitProtectionPlan(
        profile: ProfitProtectionProfile.transitionBalance,
        targetAllocation: ProfitProtectionTargetAllocation.checked(
          tp1Fraction: 0.65,
          tp2Fraction: 0.20,
          tp3Fraction: 0.15,
        ),
      );
      final allocation = ProfitProtectionAllocation.allocate(
        totalQuantity: 21.4,
        plan: plan,
        roundDown: (value) => (value * 10).floor() / 10,
      );

      expect(allocation.quantities, const [14.0, 4.2, 3.2]);
      expect(
        allocation.quantities.fold<double>(0, (sum, value) => sum + value),
        closeTo(21.4, 0.0000001),
      );
      expect(allocation.residualQuantity, closeTo(0, 0.0000001));
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
      clientId: 'q-local-xrp',
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
