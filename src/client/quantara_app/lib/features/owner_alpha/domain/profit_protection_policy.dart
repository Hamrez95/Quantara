import '../../market_analysis/domain/market_regime_models.dart';
import 'owner_alpha_models.dart';

enum ProfitProtectionProfile {
  rangeDefense,
  trendBalance,
  breakoutRunner,
  transitionBalance,
  disorderDefense,
}

final class ProfitProtectionPlan {
  const ProfitProtectionPlan({
    required this.profile,
    required this.targetFractions,
    this.costBufferRate = 0.0017,
  });

  final ProfitProtectionProfile profile;
  final List<double> targetFractions;
  final double costBufferRate;

  double get minimumTargetFraction =>
      targetFractions.reduce((left, right) => left < right ? left : right);

  double get tp1RemainingTrigger =>
      (1 - targetFractions.first + 0.02).clamp(0, 1).toDouble();

  double get tp2RemainingTrigger =>
      (targetFractions.last + 0.02).clamp(0, 1).toDouble();
}

final class ProfitProtectionAllocation {
  const ProfitProtectionAllocation({
    required this.totalQuantity,
    required this.quantities,
  });

  final double totalQuantity;
  final List<double> quantities;

  List<double> get actualFractions => List.unmodifiable(
    quantities.map(
      (quantity) => totalQuantity <= 0 ? 0 : quantity / totalQuantity,
    ),
  );

  bool isValidFor(double minimumQuantity) =>
      totalQuantity > 0 &&
      quantities.length == 3 &&
      quantities.every(
        (quantity) => quantity.isFinite && quantity >= minimumQuantity,
      );

  static ProfitProtectionAllocation allocate({
    required double totalQuantity,
    required ProfitProtectionPlan plan,
    required double Function(double value) roundDown,
  }) {
    // TP2 and TP3 are rounded first; every exchange-step remainder is assigned
    // to TP1. This preserves «TP1 closes the largest part» even on tiny sizes.
    final tp2 = roundDown(totalQuantity * plan.targetFractions[1]);
    final tp3 = roundDown(totalQuantity * plan.targetFractions[2]);
    final tp1 = roundDown(totalQuantity - tp2 - tp3);
    return ProfitProtectionAllocation(
      totalQuantity: totalQuantity,
      quantities: List.unmodifiable([tp1, tp2, tp3]),
    );
  }
}

abstract final class ProfitProtectionPolicy {
  // No tranche is smaller than 25%. This keeps the three exchange-native TP
  // orders viable for small accounts while still saving the largest portion
  // at TP1 and preserving a larger runner for confirmed breakouts.
  static const _range = ProfitProtectionPlan(
    profile: ProfitProtectionProfile.rangeDefense,
    targetFractions: [0.50, 0.25, 0.25],
  );
  static const _trend = ProfitProtectionPlan(
    profile: ProfitProtectionProfile.trendBalance,
    targetFractions: [0.45, 0.30, 0.25],
  );
  static const _breakout = ProfitProtectionPlan(
    profile: ProfitProtectionProfile.breakoutRunner,
    targetFractions: [0.40, 0.25, 0.35],
  );
  static const _transition = ProfitProtectionPlan(
    profile: ProfitProtectionProfile.transitionBalance,
    targetFractions: [0.40, 0.30, 0.30],
  );
  static const _disorder = ProfitProtectionPlan(
    profile: ProfitProtectionProfile.disorderDefense,
    targetFractions: [0.50, 0.25, 0.25],
  );

  static ProfitProtectionPlan forRegime(MarketRegime regime) =>
      switch (regime) {
        MarketRegime.range => _range,
        MarketRegime.directionalTrend => _trend,
        MarketRegime.breakoutExpansion => _breakout,
        MarketRegime.transition => _transition,
        MarketRegime.disorder => _disorder,
      };

  static ProfitProtectionPlan forIdea(TradeIdea idea) =>
      forRegime(idea.marketRegime);

  static ProfitProtectionPlan forJournal(SignalJournalEntry entry) =>
      forRegime(entry.marketRegime);
}
