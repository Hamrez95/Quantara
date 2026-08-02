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

abstract final class ProfitProtectionPolicy {
  static const _range = ProfitProtectionPlan(
    profile: ProfitProtectionProfile.rangeDefense,
    targetFractions: [0.55, 0.30, 0.15],
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
    targetFractions: [0.60, 0.25, 0.15],
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
