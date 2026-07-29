enum MarketRegime {
  directionalTrend,
  range,
  breakoutExpansion,
  transition,
  disorder,
}

enum SignalPlaybook {
  structureZones,
  trendPullback,
  donchianBreakout,
  ichimokuKijun,
  rangeMeanReversion,
  priceActionReversal,
}

enum SignalQualityTier { none, candidate, qualified, highConviction }

final class MarketRegimeAssessment {
  const MarketRegimeAssessment({
    required this.regime,
    required this.confidencePercent,
    required this.reasons,
  });

  final MarketRegime regime;
  final int confidencePercent;
  final List<String> reasons;
}
