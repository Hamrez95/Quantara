import 'dart:math' as math;

import '../../market_analysis/domain/market_chart_models.dart';
import '../domain/owner_alpha_models.dart';
import 'professional_strategy_engine.dart';

abstract final class TradeIdeaFactory {
  static const assumedRoundTripCostRate = 0.0023;
  static const targetMarginFraction = 0.20;

  static TradeIdea create({
    required TimeframeChartAnalysis analysis,
    required double capital,
    required double riskPercent,
    Map<String, ChartDirection> confluence = const {},
    String languageCode = 'fa',
    AnalysisStrategy strategy = AnalysisStrategy.structureZones,
    SignalCadence cadence = SignalCadence.balanced,
    ProfessionalStrategyContext? professionalContext,
  }) => ProfessionalStrategyEngine.create(
    analysis: analysis,
    capital: capital,
    riskPercent: riskPercent,
    confluence: confluence,
    languageCode: languageCode,
    strategy: strategy,
    cadence: cadence,
    context: professionalContext,
  );

  static bool protectiveAlignment(
    TimeframeChartAnalysis analysis,
    List<ChartPriceZone> supports,
    List<ChartPriceZone> resistances,
  ) {
    final current = analysis.latestCandle.close;
    final zones = analysis.direction == ChartDirection.bullish
        ? supports
        : resistances;
    if (zones.isEmpty || current <= 0) return false;
    final distance = (current - zones.first.center).abs() / current;
    return distance <= math.max(
      0.008,
      analysis.volatilityPercent / 100 * 1.4,
    );
  }

  static String strategyVersion(AnalysisStrategy strategy) =>
      switch (strategy) {
        AnalysisStrategy.structureZones => 'professional-auto/1.0',
        AnalysisStrategy.trendPullback => 'trend-pullback/1.0',
        AnalysisStrategy.momentumContinuation => 'breakout-retest/1.0',
      };

  static int confidenceLeverageCap(
    double directionStrength,
    double protectiveZoneStrength,
  ) {
    final combined = directionStrength * 0.6 + protectiveZoneStrength * 0.4;
    if (combined < 0.45) return 2;
    if (combined < 0.6) return 3;
    if (combined < 0.75) return 5;
    return 8;
  }
}
