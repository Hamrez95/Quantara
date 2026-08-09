import 'dart:math' as math;

import '../../market_analysis/application/live_trade_context_registry.dart';
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
  }) {
    final idea = ProfessionalStrategyEngine.create(
      analysis: analysis,
      capital: capital,
      riskPercent: riskPercent,
      confluence: confluence,
      languageCode: languageCode,
      strategy: strategy,
      cadence: cadence,
      context: professionalContext,
    );
    if (!idea.isActionable) return _publish(analysis, idea);

    final requiredMargin = idea.requiredMargin;
    final marginCap = capital * targetMarginFraction;
    if (requiredMargin == null ||
        !requiredMargin.isFinite ||
        requiredMargin <= 0 ||
        requiredMargin > marginCap) {
      return _publish(
        analysis,
        _blockedIdea(
          idea: idea,
          maximumLoss: capital * riskPercent / 100,
          languageCode: languageCode,
          fa: 'مارجین موردنیاز از سقف محافظه‌کارانه هر پوزیشن بیشتر است.',
          en: 'Required margin exceeds the conservative per-position cap.',
        ),
      );
    }

    if (idea.strategyVersion == 'rangeReversal/1.0' &&
        !_hasCorrectSideRangeBoundary(analysis: analysis, idea: idea)) {
      return _publish(
        analysis,
        _blockedIdea(
          idea: idea,
          maximumLoss: capital * riskPercent / 100,
          languageCode: languageCode,
          fa: 'مرز ساختاری رنج در سمت صحیح قیمت قرار ندارد.',
          en: 'The structural range boundary is not on the correct price side.',
        ),
      );
    }
    return _publish(analysis, idea);
  }

  static TradeIdea _publish(
    TimeframeChartAnalysis analysis,
    TradeIdea idea,
  ) {
    LiveTradeContextRegistry.publish(analysis: analysis, idea: idea);
    return idea;
  }

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
    return distance <= math.max(0.008, analysis.volatilityPercent / 100 * 1.4);
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

  static bool _hasCorrectSideRangeBoundary({
    required TimeframeChartAnalysis analysis,
    required TradeIdea idea,
  }) {
    final entry = idea.direction == TradeDirection.long
        ? idea.entryUpper
        : idea.entryLower;
    if (entry == null || !entry.isFinite || entry <= 0) return false;
    return switch (idea.direction) {
      TradeDirection.long => analysis.zones.any(
        (zone) =>
            zone.role == ChartZoneRole.support &&
            zone.upper.isFinite &&
            zone.upper < entry,
      ),
      TradeDirection.short => analysis.zones.any(
        (zone) =>
            zone.role == ChartZoneRole.resistance &&
            zone.lower.isFinite &&
            zone.lower > entry,
      ),
      TradeDirection.wait => false,
    };
  }

  static TradeIdea _blockedIdea({
    required TradeIdea idea,
    required double maximumLoss,
    required String languageCode,
    required String fa,
    required String en,
  }) => TradeIdea(
    symbol: idea.symbol,
    timeframe: idea.timeframe,
    direction: TradeDirection.wait,
    confidencePercent: 35,
    entryLower: null,
    entryUpper: null,
    stopLoss: null,
    targets: const [],
    riskReward: null,
    maximumLoss: maximumLoss,
    positionSize: null,
    notionalValue: null,
    recommendedLeverage: null,
    maximumSafeLeverage: null,
    requiredMargin: null,
    estimatedRoundTripCosts: 0,
    setupId: '${idea.setupId}|blocked',
    candleClosedAt: idea.candleClosedAt,
    summary: languageCode == 'en' ? en : fa,
    invalidation: languageCode == 'en'
        ? 'Re-evaluate after a new closed candle and valid portfolio inputs.'
        : 'پس از کندل بسته جدید و ورودی معتبر پرتفوی دوباره ارزیابی شود.',
    reasons: [languageCode == 'en' ? en : fa],
    rejectionReason: SetupRejectionReason.insufficientRiskReward,
    strategy: idea.strategy,
    strategyVersion: idea.strategyVersion,
    marketRegime: idea.marketRegime,
  );
}
