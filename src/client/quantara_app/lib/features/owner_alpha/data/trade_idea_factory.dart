import 'dart:math' as math;

import '../../market_analysis/domain/market_chart_models.dart';
import '../../trading_journal/domain/trading_journal_chart_snapshot.dart';
import '../domain/owner_alpha_models.dart';
import 'professional_strategy_engine.dart';
import 'strategy_registry.dart';

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
    StrategyRegistry? strategyRegistry,
    String? requiredRegistryVersion,
    Map<String, Object?> strategyParameters = const {},
  }) {
    final registry = strategyRegistry ?? StrategyRegistry.shared;
    final parameters = <String, Object?>{
      ...strategyParameters,
      'cadence': cadence.name,
    };
    final resolution = registry.resolveForNewRun(
      selection: strategy,
      symbol: analysis.symbol,
      timeframe: analysis.timeframe,
      parameters: parameters,
      requiredVersion: requiredRegistryVersion,
    );
    if (resolution == null) {
      return _registryBlockedIdea(
        analysis: analysis,
        capital: capital,
        riskPercent: riskPercent,
        languageCode: languageCode,
        strategy: strategy,
        reason: requiredRegistryVersion == null
            ? 'strategy_registry_unavailable'
            : 'strategy_registry_version_unavailable',
      );
    }

    final rawIdea = resolution.module.evaluate(
      StrategyEvaluationRequest(
        analysis: analysis,
        capital: capital,
        riskPercent: riskPercent,
        confluence: confluence,
        languageCode: languageCode,
        cadence: cadence,
        professionalContext: professionalContext,
      ),
    );
    final journalIdea = _withJournalChartSnapshot(rawIdea, analysis);
    final snapshot = resolution.snapshot;
    final idea = journalIdea.copyWithRegistryIdentity(
      registryStrategyId: snapshot.strategyId,
      registryStrategyVersion: snapshot.strategyVersion,
      strategyParameterSchemaVersion: snapshot.parameterSchemaVersion,
      normalizedStrategyParameters: snapshot.normalizedParameters,
      strategySnapshotHash: snapshot.snapshotHash,
      managementPolicyVersion: snapshot.managementPolicyVersion,
      strategyImplementationVersion: snapshot.implementationVersion,
      strategyLifecycle: snapshot.lifecycle.name,
    );
    if (!idea.isActionable) return idea;

    final requiredMargin = idea.requiredMargin;
    final marginCap = capital * targetMarginFraction;
    if (requiredMargin == null ||
        !requiredMargin.isFinite ||
        requiredMargin <= 0 ||
        requiredMargin > marginCap) {
      return _blockedIdea(
        idea: idea,
        maximumLoss: capital * riskPercent / 100,
        languageCode: languageCode,
        fa: 'مارجین موردنیاز از سقف محافظه‌کارانه هر پوزیشن بیشتر است.',
        en: 'Required margin exceeds the conservative per-position cap.',
      );
    }

    if (idea.strategyVersion == 'rangeReversal/1.0' &&
        !_hasCorrectSideRangeBoundary(analysis: analysis, idea: idea)) {
      return _blockedIdea(
        idea: idea,
        maximumLoss: capital * riskPercent / 100,
        languageCode: languageCode,
        fa: 'مرز ساختاری رنج در سمت صحیح قیمت قرار ندارد.',
        en: 'The structural range boundary is not on the correct price side.',
      );
    }
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

  static String strategyVersion(AnalysisStrategy strategy) {
    for (final module in StrategyRegistry.shared.modules) {
      if (module.selection == strategy && module.acceptsNewRuns) {
        return module.strategyVersion;
      }
    }
    return 'unavailable';
  }

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

  static TradeIdea _withJournalChartSnapshot(
    TradeIdea idea,
    TimeframeChartAnalysis analysis,
  ) {
    final indicatorSnapshot = <String, double>{
      ...idea.indicatorSnapshot,
      ...TradingJournalChartSnapshot.encodeIntoIndicatorSnapshot(analysis),
    };
    return TradeIdea(
      symbol: idea.symbol,
      timeframe: idea.timeframe,
      direction: idea.direction,
      confidencePercent: idea.confidencePercent,
      entryLower: idea.entryLower,
      entryUpper: idea.entryUpper,
      stopLoss: idea.stopLoss,
      targets: idea.targets,
      riskReward: idea.riskReward,
      maximumLoss: idea.maximumLoss,
      positionSize: idea.positionSize,
      notionalValue: idea.notionalValue,
      recommendedLeverage: idea.recommendedLeverage,
      maximumSafeLeverage: idea.maximumSafeLeverage,
      requiredMargin: idea.requiredMargin,
      estimatedRoundTripCosts: idea.estimatedRoundTripCosts,
      setupId: idea.setupId,
      candleClosedAt: idea.candleClosedAt,
      summary: idea.summary,
      invalidation: idea.invalidation,
      reasons: idea.reasons,
      rejectionReason: idea.rejectionReason,
      strategy: idea.strategy,
      strategyVersion: idea.strategyVersion,
      registryStrategyId: idea.registryStrategyId,
      registryStrategyVersion: idea.registryStrategyVersion,
      strategyParameterSchemaVersion: idea.strategyParameterSchemaVersion,
      normalizedStrategyParameters: idea.normalizedStrategyParameters,
      strategySnapshotHash: idea.strategySnapshotHash,
      managementPolicyVersion: idea.managementPolicyVersion,
      strategyImplementationVersion: idea.strategyImplementationVersion,
      strategyLifecycle: idea.strategyLifecycle,
      marketRegime: idea.marketRegime,
      indicatorSnapshot: Map.unmodifiable(indicatorSnapshot),
      setupQualityScore: idea.setupQualityScore,
      expectation: idea.expectation,
      trigger: idea.trigger,
      contextVersion: idea.contextVersion,
      evidenceBreakdown: idea.evidenceBreakdown,
    );
  }

  static TradeIdea _registryBlockedIdea({
    required TimeframeChartAnalysis analysis,
    required double capital,
    required double riskPercent,
    required String languageCode,
    required AnalysisStrategy strategy,
    required String reason,
  }) {
    final fa = languageCode != 'en';
    final summary = fa
        ? 'نسخه ثبت‌شده استراتژی برای اجرای جدید قابل resolve نیست؛ اجرا متوقف شد.'
        : 'The registered strategy version cannot be resolved for a new run; execution is blocked.';
    return TradeIdea(
      symbol: analysis.symbol,
      timeframe: analysis.timeframe,
      direction: TradeDirection.wait,
      confidencePercent: 0,
      entryLower: null,
      entryUpper: null,
      stopLoss: null,
      targets: const [],
      riskReward: null,
      maximumLoss:
          capital.isFinite &&
              capital > 0 &&
              riskPercent.isFinite &&
              riskPercent > 0
          ? capital * riskPercent / 100
          : 0,
      positionSize: null,
      notionalValue: null,
      recommendedLeverage: null,
      maximumSafeLeverage: null,
      requiredMargin: null,
      estimatedRoundTripCosts: 0,
      setupId: '${analysis.symbol}|${analysis.timeframe}|registry-blocked',
      candleClosedAt: analysis.generatedAt.toUtc(),
      summary: summary,
      invalidation: fa
          ? 'فقط پس از resolve شدن نسخه دقیق و snapshot معتبر دوباره ارزیابی شود.'
          : 'Re-evaluate only after the exact version and a valid snapshot resolve.',
      reasons: <String>[reason],
      rejectionReason: SetupRejectionReason.dataUnavailable,
      strategy: strategy,
      strategyVersion: 'registry-blocked',
    );
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
    registryStrategyId: idea.registryStrategyId,
    registryStrategyVersion: idea.registryStrategyVersion,
    strategyParameterSchemaVersion: idea.strategyParameterSchemaVersion,
    normalizedStrategyParameters: idea.normalizedStrategyParameters,
    strategySnapshotHash: idea.strategySnapshotHash,
    managementPolicyVersion: idea.managementPolicyVersion,
    strategyImplementationVersion: idea.strategyImplementationVersion,
    strategyLifecycle: idea.strategyLifecycle,
    marketRegime: idea.marketRegime,
    indicatorSnapshot: idea.indicatorSnapshot,
    setupQualityScore: idea.setupQualityScore,
    expectation: idea.expectation,
    trigger: idea.trigger,
    contextVersion: idea.contextVersion,
    evidenceBreakdown: idea.evidenceBreakdown,
  );
}
