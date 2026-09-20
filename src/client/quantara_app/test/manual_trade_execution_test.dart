import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/domain/auto_trade_models.dart';
import 'package:quantara_app/features/auto_trade/domain/manual_trade_execution.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';

void main() {
  final now = DateTime.utc(2026, 9, 20, 16);

  test(
    'default proposal uses quality only to scale risk below the hard cap',
    () {
      final high = ManualTradeSizingPolicy.propose(
        setup: _setup(now, quality: 100),
        account: _account(now),
        rules: _rules(),
        markPrice: 100,
        nowUtc: now,
        targetCount: 3,
      );
      final lower = ManualTradeSizingPolicy.propose(
        setup: _setup(now, quality: 60),
        account: _account(now),
        rules: _rules(),
        markPrice: 100,
        nowUtc: now,
        targetCount: 3,
      );

      expect(high.allowed, isTrue);
      expect(lower.allowed, isTrue);
      expect(high.maximumLoss, lessThanOrEqualTo(high.hardRiskCap + 1e-9));
      expect(lower.maximumLoss, lessThan(high.maximumLoss));
      expect(lower.qualityRiskMultiplier, 0.8);
      expect(high.qualityRiskMultiplier, 1);
    },
  );

  test('user margin override cannot exceed the hard setup risk cap', () {
    final plan = ManualTradeSizingPolicy.recalculate(
      setup: _setup(now),
      account: _account(now),
      rules: _rules(),
      markPrice: 100,
      nowUtc: now,
      margin: 1000,
      leverage: 5,
      targetCount: 3,
    );

    expect(plan.allowed, isFalse);
    expect(plan.blockReason, ManualTradePlanBlockReason.hardRiskExceeded);
    expect(plan.maximumLoss, greaterThan(plan.hardRiskCap));
  });

  test('user leverage stays inside both exchange and setup safe caps', () {
    final plan = ManualTradeSizingPolicy.recalculate(
      setup: _setup(now, maximumSafeLeverage: 8),
      account: _account(now),
      rules: _rules(maximumLeverage: 50),
      markPrice: 100,
      nowUtc: now,
      margin: 100,
      leverage: 9,
      targetCount: 1,
    );

    expect(plan.allowed, isFalse);
    expect(plan.blockReason, ManualTradePlanBlockReason.invalidLeverage);
    expect(plan.maximumPermittedLeverage, 8);
  });

  test('one two and three TP selections preserve exact full allocation', () {
    for (final count in [1, 2, 3]) {
      final plan = ManualTradeSizingPolicy.recalculate(
        setup: _setup(now),
        account: _account(now),
        rules: _rules(),
        markPrice: 100,
        nowUtc: now,
        margin: 100,
        leverage: 5,
        targetCount: count,
      );

      expect(plan.allowed, isTrue, reason: 'TP count $count should be valid');
      expect(plan.targets, hasLength(count));
      expect(plan.targetQuantities, hasLength(count));
      expect(
        plan.targetQuantities.fold<double>(0, (sum, value) => sum + value),
        closeTo(plan.quantity, 1e-9),
      );
      expect(plan.targetAllocation.activeTargetCount, count);
    }
  });

  test('selecting more targets than the setup owns fails closed', () {
    final plan = ManualTradeSizingPolicy.recalculate(
      setup: _setup(now, targets: const [104, 108]),
      account: _account(now),
      rules: _rules(),
      markPrice: 100,
      nowUtc: now,
      margin: 100,
      leverage: 5,
      targetCount: 3,
    );

    expect(plan.allowed, isFalse);
    expect(plan.blockReason, ManualTradePlanBlockReason.insufficientTargets);
  });

  test('stale private account truth blocks the trade sheet plan', () {
    final plan = ManualTradeSizingPolicy.propose(
      setup: _setup(now),
      account: _account(now.subtract(const Duration(minutes: 2))),
      rules: _rules(),
      markPrice: 100,
      nowUtc: now,
      targetCount: 3,
    );

    expect(plan.allowed, isFalse);
    expect(plan.blockReason, ManualTradePlanBlockReason.staleAccount);
  });

  test('market price outside the setup entry zone cannot be market-chased', () {
    final plan = ManualTradeSizingPolicy.propose(
      setup: _setup(now),
      account: _account(now),
      rules: _rules(),
      markPrice: 102,
      nowUtc: now,
      targetCount: 3,
    );

    expect(plan.allowed, isFalse);
    expect(plan.blockReason, ManualTradePlanBlockReason.marketOutsideEntryZone);
  });

  test('exchange quantity minimum is enforced after rounding', () {
    final plan = ManualTradeSizingPolicy.recalculate(
      setup: _setup(now),
      account: _account(now),
      rules: _rules(minimumQuantity: 2),
      markPrice: 100,
      nowUtc: now,
      margin: 10,
      leverage: 5,
      targetCount: 1,
    );

    expect(plan.allowed, isFalse);
    expect(plan.blockReason, ManualTradePlanBlockReason.quantityTooSmall);
  });

  test('expired and already-resolved setups cannot create new manual risk', () {
    final expired = ManualTradeSizingPolicy.propose(
      setup: _setup(
        now.subtract(const Duration(hours: 3)),
        validUntil: now.subtract(const Duration(minutes: 1)),
      ),
      account: _account(now),
      rules: _rules(),
      markPrice: 100,
      nowUtc: now,
    );
    final resolved = ManualTradeSizingPolicy.propose(
      setup: _setup(now, outcome: SignalOutcome.tp1),
      account: _account(now),
      rules: _rules(),
      markPrice: 100,
      nowUtc: now,
    );

    expect(expired.blockReason, ManualTradePlanBlockReason.setupExpired);
    expect(resolved.blockReason, ManualTradePlanBlockReason.setupNotExecutable);
  });
}

SignalJournalEntry _setup(
  DateTime now, {
  int quality = 80,
  int maximumSafeLeverage = 10,
  List<double> targets = const [104, 108, 112],
  SignalOutcome outcome = SignalOutcome.pendingEntry,
  DateTime? validUntil,
}) => SignalJournalEntry(
  setupId: 'setup-540',
  symbol: 'BTCUSDT',
  timeframe: '1h',
  direction: TradeDirection.long,
  strategy: AnalysisStrategy.trendPullback,
  strategyVersion: 'trend-pullback/test',
  createdAt: now.subtract(const Duration(minutes: 5)),
  validUntil: validUntil ?? now.add(const Duration(hours: 2)),
  entryLower: 99.5,
  entryUpper: 100.5,
  stopLoss: 98,
  targets: targets,
  maximumLoss: 100,
  positionSize: 40,
  notionalValue: 4000,
  estimatedRoundTripCosts: 9.2,
  recommendedLeverage: 5,
  maximumSafeLeverage: maximumSafeLeverage,
  selectedLeverage: 5,
  summary: 'fixture',
  invalidation: 'fixture',
  setupQualityScore: quality,
  confidencePercent: quality,
  sizingCapital: 10000,
  outcome: outcome,
);

AutoTradeAccountSnapshot _account(DateTime syncedAt) =>
    AutoTradeAccountSnapshot(
      marginCoin: 'USDT',
      available: 5000,
      frozen: 0,
      positionMargin: 0,
      crossUnrealizedPnl: 0,
      isolatedUnrealizedPnl: 0,
      positionMode: 'HEDGE',
      positions: const [],
      orders: const [],
      syncedAt: syncedAt,
    );

ManualTradeInstrumentRules _rules({
  double minimumQuantity = 0.001,
  int maximumLeverage = 50,
}) => ManualTradeInstrumentRules(
  symbol: 'BTCUSDT',
  minimumQuantity: minimumQuantity,
  maximumMarketQuantity: 1000,
  quantityPrecision: 3,
  pricePrecision: 1,
  minimumLeverage: 1,
  maximumLeverage: maximumLeverage,
  open: true,
  apiSupported: true,
);
