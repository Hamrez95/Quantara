import 'dart:math' as math;

import '../../market_analysis/data/contextual_price_action_engine.dart';
import '../../market_analysis/data/technical_indicator_engine.dart';
import '../../market_analysis/domain/contextual_price_action_models.dart';
import '../../market_analysis/domain/market_chart_models.dart';
import '../../market_analysis/domain/market_regime_models.dart';
import '../domain/owner_alpha_models.dart';
import '../domain/regime_playbook_models.dart';
import 'professional_strategy_engine.dart';
import 'trade_idea_factory.dart';

abstract final class RegimePlaybookPortfolioEngine {
  static const version = 'regime-playbook-portfolio/1.0';
  static const Map<RegimePlaybookId, String> playbookVersions = {
    RegimePlaybookId.trendPullbackContinuation: 'trend-pullback-continuation/2.0',
    RegimePlaybookId.rangeEdgeSweepReclaim: 'range-edge-sweep-reclaim/2.0',
    RegimePlaybookId.breakoutAcceptanceRetest:
        'breakout-acceptance-retest/2.0',
    RegimePlaybookId.failedBreakoutReversal: 'failed-breakout-reversal/1.0',
    RegimePlaybookId.momentumExpansionScalp: 'momentum-expansion-scalp/1.0',
  };

  static RegimePlaybookPortfolioSnapshot evaluate({
    required TimeframeChartAnalysis analysis,
    required double capital,
    required double riskPercent,
    required String languageCode,
    required SignalCadence cadence,
    required RegimePlaybookRuntimeContext runtime,
    RegimePlaybookFeatureFlags flags = const RegimePlaybookFeatureFlags(),
    ProfessionalStrategyContext? professionalContext,
  }) {
    if (!runtime.valid) {
      throw ArgumentError('Playbook runtime context is invalid.');
    }
    if (!_closedCandleGate(analysis, runtime.evaluatedAtUtc)) {
      throw StateError('Playbooks may only evaluate fully closed candles.');
    }
    final indicators = TechnicalIndicatorEngine.analyze(analysis.candles);
    final contextual = ContextualPriceActionEngine.analyze(
      analysis: analysis,
      indicators: indicators,
    );
    final effectiveContext =
        professionalContext ??
        ProfessionalStrategyContext(evaluatedAt: runtime.evaluatedAtUtc);
    final confluence = <String, ChartDirection>{
      analysis.timeframe: analysis.direction,
      if (_parentTimeframe(analysis.timeframe) case final parent?)
        if (runtime.higherTimeframeDirection case final direction?)
          parent: direction,
    };

    final evaluations = <RegimePlaybookEvaluation>[
      _trendPullback(
        analysis: analysis,
        contextual: contextual,
        capital: capital,
        riskPercent: riskPercent,
        languageCode: languageCode,
        cadence: cadence,
        runtime: runtime,
        enabled: flags.enabled(RegimePlaybookId.trendPullbackContinuation),
        confluence: confluence,
        context: effectiveContext,
      ),
      _rangeSweep(
        analysis: analysis,
        contextual: contextual,
        capital: capital,
        riskPercent: riskPercent,
        languageCode: languageCode,
        cadence: cadence,
        runtime: runtime,
        enabled: flags.enabled(RegimePlaybookId.rangeEdgeSweepReclaim),
        confluence: confluence,
        context: effectiveContext,
      ),
      _breakoutRetest(
        analysis: analysis,
        contextual: contextual,
        capital: capital,
        riskPercent: riskPercent,
        languageCode: languageCode,
        cadence: cadence,
        runtime: runtime,
        enabled: flags.enabled(RegimePlaybookId.breakoutAcceptanceRetest),
        confluence: confluence,
        context: effectiveContext,
      ),
      _failedBreakout(
        analysis: analysis,
        indicators: indicators,
        contextual: contextual,
        capital: capital,
        riskPercent: riskPercent,
        languageCode: languageCode,
        runtime: runtime,
        enabled: flags.enabled(RegimePlaybookId.failedBreakoutReversal),
        context: effectiveContext,
      ),
      _momentumScalp(
        analysis: analysis,
        indicators: indicators,
        contextual: contextual,
        capital: capital,
        riskPercent: riskPercent,
        languageCode: languageCode,
        runtime: runtime,
        enabled: flags.enabled(RegimePlaybookId.momentumExpansionScalp),
        context: effectiveContext,
      ),
    ];

    final resolution = _resolve(evaluations);
    return RegimePlaybookPortfolioSnapshot(
      evaluations: evaluations,
      contextual: contextual,
      conflictOutcome: resolution.outcome,
      selected: resolution.selected,
      coverageGaps: _coverageGaps(contextual.regime, flags),
    );
  }

  static RegimePlaybookEvaluation _trendPullback({
    required TimeframeChartAnalysis analysis,
    required ContextualPriceActionAssessment contextual,
    required double capital,
    required double riskPercent,
    required String languageCode,
    required SignalCadence cadence,
    required RegimePlaybookRuntimeContext runtime,
    required bool enabled,
    required Map<String, ChartDirection> confluence,
    required ProfessionalStrategyContext context,
  }) {
    const id = RegimePlaybookId.trendPullbackContinuation;
    if (!enabled) return _disabled(id, contextual);
    final contextValid =
        contextual.regime == MarketRegime.directionalTrend &&
        contextual.structure.bias != ChartDirection.sideways;
    final resetEvidence =
        contextual.volume.pullbackContraction ||
        contextual.volume.reExpansion ||
        contextual.momentum.rsiReset;
    final higherAligned = _higherAligned(contextual.structure.bias, runtime);
    final quality = _quality(
      contextual,
      bonuses: [if (resetEvidence) 7, if (higherAligned) 7],
      penalties: [if (!higherAligned) 15],
    );
    final forming = contextValid && quality >= 50;
    final idea = forming
        ? TradeIdeaFactory.create(
            analysis: analysis,
            capital: capital,
            riskPercent: riskPercent,
            confluence: confluence,
            languageCode: languageCode,
            strategy: AnalysisStrategy.trendPullback,
            cadence: cadence,
            professionalContext: context,
          )
        : null;
    final armed =
        forming &&
        higherAligned &&
        resetEvidence &&
        quality >= 62 &&
        idea != null &&
        idea.isActionable;
    return _evaluation(
      id: id,
      contextual: contextual,
      state: armed
          ? PlaybookCandidateState.armed
          : forming
          ? PlaybookCandidateState.forming
          : PlaybookCandidateState.inactive,
      quality: quality,
      idea: armed ? _versionIdea(idea, id, contextual) : null,
      direction: contextual.structure.bias,
      management: PlaybookManagementPolicy.trendRunner,
      context:
          'Directional structure + higher-timeframe alignment + pullback into value.',
      trigger:
          'Closed-candle rejection after pullback with volume contraction/re-expansion or momentum reset.',
      invalidation:
          'Protected trend swing or structural stop fails on a closed candle.',
      targets: armed ? idea!.targets : const [],
      reasons: [
        'regime:${contextual.regime.name}',
        'higherTimeframeAligned:$higherAligned',
        'resetEvidence:$resetEvidence',
      ],
    );
  }

  static RegimePlaybookEvaluation _rangeSweep({
    required TimeframeChartAnalysis analysis,
    required ContextualPriceActionAssessment contextual,
    required double capital,
    required double riskPercent,
    required String languageCode,
    required SignalCadence cadence,
    required RegimePlaybookRuntimeContext runtime,
    required bool enabled,
    required Map<String, ChartDirection> confluence,
    required ProfessionalStrategyContext context,
  }) {
    const id = RegimePlaybookId.rangeEdgeSweepReclaim;
    if (!enabled) return _disabled(id, contextual);
    final latest = analysis.latestCandle;
    final zone = contextual.zone.zone;
    final atEdge =
        zone != null &&
        (latest.low <= zone.upper || latest.high >= zone.lower) &&
        contextual.zone.roomToTarget >= 0.25;
    final reclaim =
        contextual.candle.reclaim ||
        contextual.candle.rejectionStrength >= 0.45 ||
        contextual.candle.absorption;
    final rangeContext =
        contextual.regime == MarketRegime.range ||
        analysis.direction == ChartDirection.sideways;
    final quality = _quality(
      contextual,
      bonuses: [if (atEdge) 9, if (reclaim) 8],
      penalties: [if (!atEdge) 22],
    );
    final forming = rangeContext && atEdge && quality >= 48;
    final idea = forming
        ? TradeIdeaFactory.create(
            analysis: analysis,
            capital: capital,
            riskPercent: riskPercent,
            confluence: confluence,
            languageCode: languageCode,
            strategy: AnalysisStrategy.structureZones,
            cadence: cadence,
            professionalContext: context,
          )
        : null;
    final armed =
        forming &&
        reclaim &&
        quality >= 60 &&
        idea != null &&
        idea.isActionable &&
        idea.strategyVersion.contains('rangeReversal');
    final ChartDirection direction = armed
        ? switch (idea!.direction) {
            TradeDirection.long => ChartDirection.bullish,
            TradeDirection.short => ChartDirection.bearish,
            TradeDirection.wait => ChartDirection.sideways,
          }
        : _rangeDirection(analysis, zone);
    return _evaluation(
      id: id,
      contextual: contextual,
      state: armed
          ? PlaybookCandidateState.armed
          : forming
          ? PlaybookCandidateState.forming
          : PlaybookCandidateState.inactive,
      quality: quality,
      idea: armed ? _versionIdea(idea!, id, contextual) : null,
      direction: direction,
      management: PlaybookManagementPolicy.rangeMeanThenOppositeEdge,
      context: 'Range edge only; middle-of-box entries are not eligible.',
      trigger: 'Liquidity sweep/rejection followed by a closed-candle reclaim.',
      invalidation:
          'Acceptance outside the swept range edge invalidates the reversal.',
      targets: armed ? idea!.targets : const [],
      reasons: [
        'atRangeEdge:$atEdge',
        'reclaimOrAbsorption:$reclaim',
        'roomToTarget:${contextual.zone.roomToTarget.toStringAsFixed(3)}',
      ],
    );
  }

  static RegimePlaybookEvaluation _breakoutRetest({
    required TimeframeChartAnalysis analysis,
    required ContextualPriceActionAssessment contextual,
    required double capital,
    required double riskPercent,
    required String languageCode,
    required SignalCadence cadence,
    required RegimePlaybookRuntimeContext runtime,
    required bool enabled,
    required Map<String, ChartDirection> confluence,
    required ProfessionalStrategyContext context,
  }) {
    const id = RegimePlaybookId.breakoutAcceptanceRetest;
    if (!enabled) return _disabled(id, contextual);
    final breakoutContext =
        contextual.regime == MarketRegime.breakoutExpansion ||
        contextual.structure.event == StructureEvent.breakOfStructure;
    final expansion =
        contextual.volume.breakoutExpansion && contextual.momentum.expansion;
    final acceptance =
        contextual.candle.acceptance ||
        contextual.candle.reclaim ||
        contextual.candle.followThrough;
    final compression = contextual.zone.compressionQuality >= 0.35;
    final quality = _quality(
      contextual,
      bonuses: [
        if (expansion) 9,
        if (acceptance) 7,
        if (compression) 5,
      ],
      penalties: [if (!acceptance) 12],
    );
    final forming =
        breakoutContext && (expansion || compression) && quality >= 52;
    final idea = forming
        ? TradeIdeaFactory.create(
            analysis: analysis,
            capital: capital,
            riskPercent: riskPercent,
            confluence: confluence,
            languageCode: languageCode,
            strategy: AnalysisStrategy.momentumContinuation,
            cadence: cadence,
            professionalContext: context,
          )
        : null;
    final armed =
        forming &&
        expansion &&
        acceptance &&
        quality >= 64 &&
        idea != null &&
        idea.isActionable;
    return _evaluation(
      id: id,
      contextual: contextual,
      state: armed
          ? PlaybookCandidateState.armed
          : forming
          ? PlaybookCandidateState.forming
          : PlaybookCandidateState.inactive,
      quality: quality,
      idea: armed ? _versionIdea(idea!, id, contextual) : null,
      direction: contextual.structure.bias,
      management: PlaybookManagementPolicy.breakoutRunner,
      context: 'Compression/build-up followed by structural expansion.',
      trigger:
          'Closed breakout acceptance or retest with volume and momentum expansion.',
      invalidation:
          'Failed acceptance back through the breakout structure invalidates continuation.',
      targets: armed ? idea!.targets : const [],
      reasons: [
        'expansion:$expansion',
        'acceptance:$acceptance',
        'compression:$compression',
      ],
    );
  }

  static RegimePlaybookEvaluation _failedBreakout({
    required TimeframeChartAnalysis analysis,
    required TechnicalIndicatorSnapshot indicators,
    required ContextualPriceActionAssessment contextual,
    required double capital,
    required double riskPercent,
    required String languageCode,
    required RegimePlaybookRuntimeContext runtime,
    required bool enabled,
    required ProfessionalStrategyContext context,
  }) {
    const id = RegimePlaybookId.failedBreakoutReversal;
    if (!enabled) return _disabled(id, contextual);
    final failed =
        contextual.structure.event == StructureEvent.failedBreak ||
        contextual.candle.failedBreakout;
    final volumeConfirmation =
        contextual.volume.effortVsResult ||
        contextual.volume.climax ||
        contextual.volume.absorption;
    final reclaim =
        contextual.candle.reclaim ||
        contextual.candle.rejectionStrength >= 0.45;
    final direction = contextual.structure.bias;
    final quality = _quality(
      contextual,
      bonuses: [
        if (failed) 10,
        if (volumeConfirmation) 8,
        if (reclaim) 7,
      ],
      penalties: [if (!failed) 25],
    );
    final forming =
        failed && direction != ChartDirection.sideways && quality >= 50;
    final idea = forming && volumeConfirmation && reclaim
        ? _customIdea(
            id: id,
            analysis: analysis,
            indicators: indicators,
            contextual: contextual,
            capital: capital,
            riskPercent: riskPercent,
            languageCode: languageCode,
            context: context,
            direction: direction,
            minimumRiskReward: 1.65,
          )
        : null;
    final armed = idea != null && idea.isActionable && quality >= 63;
    return _evaluation(
      id: id,
      contextual: contextual,
      state: armed
          ? PlaybookCandidateState.armed
          : forming
          ? PlaybookCandidateState.forming
          : PlaybookCandidateState.inactive,
      quality: quality,
      idea: armed ? idea : null,
      direction: direction,
      management: PlaybookManagementPolicy.failedBreakScaleOut,
      context:
          'Level penetration without follow-through, followed by reversal evidence.',
      trigger:
          'Closed-candle reclaim plus effort-vs-result, climax or absorption confirmation.',
      invalidation:
          'Renewed acceptance beyond the swept extreme invalidates the reversal.',
      targets: armed ? idea!.targets : const [],
      reasons: [
        'failedBreak:$failed',
        'volumeConfirmation:$volumeConfirmation',
        'reclaim:$reclaim',
      ],
    );
  }

  static RegimePlaybookEvaluation _momentumScalp({
    required TimeframeChartAnalysis analysis,
    required TechnicalIndicatorSnapshot indicators,
    required ContextualPriceActionAssessment contextual,
    required double capital,
    required double riskPercent,
    required String languageCode,
    required RegimePlaybookRuntimeContext runtime,
    required bool enabled,
    required ProfessionalStrategyContext context,
  }) {
    const id = RegimePlaybookId.momentumExpansionScalp;
    if (!enabled) return _disabled(id, contextual);
    final isFiveMinute = analysis.timeframe == '5m';
    final direction = contextual.structure.bias;
    final higherAligned = _higherAligned(direction, runtime);
    final hardRuntimeGate =
        isFiveMinute &&
        runtime.higherTimeframeFresh &&
        higherAligned &&
        runtime.liquidityVerified &&
        runtime.latencyHealthy;
    final expansion =
        contextual.momentum.expansion &&
        (contextual.volume.reExpansion ||
            contextual.volume.breakoutExpansion) &&
        indicators.atrExpansionRatio >= 1.08;
    final quality = _quality(
      contextual,
      bonuses: [if (expansion) 10, if (hardRuntimeGate) 8],
      penalties: [if (!hardRuntimeGate) 30],
    );
    final forming = hardRuntimeGate && expansion && quality >= 55;
    final idea = forming
        ? _customIdea(
            id: id,
            analysis: analysis,
            indicators: indicators,
            contextual: contextual,
            capital: capital,
            riskPercent: riskPercent,
            languageCode: languageCode,
            context: context,
            direction: direction,
            minimumRiskReward: 1.35,
            validityOverride: const Duration(minutes: 10),
          )
        : null;
    final armed = idea != null && idea.isActionable && quality >= 68;
    return _evaluation(
      id: id,
      contextual: contextual,
      state: armed
          ? PlaybookCandidateState.armed
          : forming
          ? PlaybookCandidateState.forming
          : PlaybookCandidateState.inactive,
      quality: quality,
      idea: armed ? idea : null,
      direction: direction,
      management: PlaybookManagementPolicy.momentumQuickExit,
      context:
          '5m expansion only with fresh higher-timeframe, liquidity and latency gates.',
      trigger:
          'Closed 5m expansion candle with volume re-expansion and directional momentum.',
      invalidation:
          'Momentum loss, stale context or structural stop invalidates the scalp immediately.',
      targets: armed ? idea!.targets : const [],
      reasons: [
        'fiveMinute:$isFiveMinute',
        'higherTimeframeFresh:${runtime.higherTimeframeFresh}',
        'higherTimeframeAligned:$higherAligned',
        'liquidityVerified:${runtime.liquidityVerified}',
        'latencyHealthy:${runtime.latencyHealthy}',
        'expansion:$expansion',
      ],
    );
  }

  static TradeIdea? _customIdea({
    required RegimePlaybookId id,
    required TimeframeChartAnalysis analysis,
    required TechnicalIndicatorSnapshot indicators,
    required ContextualPriceActionAssessment contextual,
    required double capital,
    required double riskPercent,
    required String languageCode,
    required ProfessionalStrategyContext context,
    required ChartDirection direction,
    required double minimumRiskReward,
    Duration? validityOverride,
  }) {
    if (direction == ChartDirection.sideways || !context.valid) return null;
    final long = direction == ChartDirection.bullish;
    final latest = analysis.latestCandle;
    final atr = indicators.atr14;
    if (!atr.isFinite || atr <= 0) return null;
    final stop = long
        ? math.min(latest.low, indicators.recentSwingLow) - atr * 0.10
        : math.max(latest.high, indicators.recentSwingHigh) + atr * 0.10;
    if ((long && stop >= latest.close) || (!long && stop <= latest.close)) {
      return null;
    }
    final entryBand = math.max(latest.close * 0.0003, atr * 0.08);
    final entryLower = latest.close - entryBand;
    final entryUpper = latest.close + entryBand;
    final conservativeEntry = long ? entryUpper : entryLower;
    final stopDistance = (conservativeEntry - stop).abs();
    final costRate =
        context.entryFeeRate +
        context.exitFeeRate +
        context.slippageRate +
        context.fundingReserveRate;
    final costPerUnit = conservativeEntry * costRate;
    final riskPerUnit = stopDistance + costPerUnit;
    final maximumLoss = capital * riskPercent / 100;
    if (!riskPerUnit.isFinite || riskPerUnit <= 0 || maximumLoss <= 0) {
      return null;
    }
    final quantity = _roundDown(maximumLoss / riskPerUnit, 6);
    final notional = quantity * conservativeEntry;
    if (quantity < context.minimumQuantity ||
        notional < context.minimumNotional) {
      return null;
    }
    final stopPercent = stopDistance / conservativeEntry;
    final leverage = (0.30 / math.max(0.01, stopPercent))
        .floor()
        .clamp(1, context.maximumLeverage)
        .toInt();
    final requiredMargin = notional / leverage;
    if (requiredMargin > capital * TradeIdeaFactory.targetMarginFraction) {
      return null;
    }
    final target1 = long
        ? conservativeEntry + riskPerUnit * minimumRiskReward
        : conservativeEntry - riskPerUnit * minimumRiskReward;
    final target2 = long
        ? conservativeEntry + riskPerUnit * (minimumRiskReward + 0.65)
        : conservativeEntry - riskPerUnit * (minimumRiskReward + 0.65);
    final target3 = long
        ? conservativeEntry + riskPerUnit * (minimumRiskReward + 1.35)
        : conservativeEntry - riskPerUnit * (minimumRiskReward + 1.35);
    final closedAt = latest.openTime.add(_durationFor(analysis.timeframe));
    final validity = validityOverride ?? _validityFor(analysis.timeframe);
    final setupId = [
      analysis.symbol,
      analysis.timeframe,
      id.name,
      closedAt.toUtc().microsecondsSinceEpoch,
      long ? 'long' : 'short',
    ].join('|');
    final fa = languageCode != 'en';
    return TradeIdea(
      symbol: analysis.symbol,
      timeframe: analysis.timeframe,
      direction: long ? TradeDirection.long : TradeDirection.short,
      confidencePercent: contextual.setupQualityScore,
      entryLower: entryLower,
      entryUpper: entryUpper,
      stopLoss: stop,
      targets: [target1, target2, target3],
      riskReward: minimumRiskReward,
      maximumLoss: maximumLoss,
      positionSize: quantity,
      notionalValue: notional,
      recommendedLeverage: leverage,
      maximumSafeLeverage: leverage,
      requiredMargin: requiredMargin,
      estimatedRoundTripCosts: quantity * costPerUnit,
      setupId: setupId,
      candleClosedAt: closedAt,
      summary: fa
          ? 'Playbook ${id.name} با Evidence مستقل و کندل بسته Armed شده است.'
          : 'Playbook ${id.name} is armed with independent evidence on a closed candle.',
      invalidation: fa
          ? 'با شکست Stop ساختاری یا منقضی‌شدن Evidence، ستاپ باطل است.'
          : 'The setup is invalid after the structural stop fails or evidence expires.',
      reasons: [
        'playbook:${id.name}',
        'portfolio:$version',
        ...contextual.evidenceReasons.take(5),
      ],
      strategy: id == RegimePlaybookId.momentumExpansionScalp
          ? AnalysisStrategy.momentumContinuation
          : AnalysisStrategy.structureZones,
      strategyVersion: playbookVersions[id]!,
      marketRegime: contextual.regime,
      indicatorSnapshot: const {},
      setupQualityScore: contextual.setupQualityScore,
      expectation: contextual.expectation,
      trigger: contextual.trigger,
      contextVersion: contextual.version,
      evidenceBreakdown: contextual.scoreBreakdown,
      validityOverride: validity,
    );
  }

  static TradeIdea _versionIdea(
    TradeIdea source,
    RegimePlaybookId id,
    ContextualPriceActionAssessment contextual,
  ) => source.copyWithPlaybookMetadata(
    strategyVersion: playbookVersions[id]!,
    setupQualityScore: contextual.setupQualityScore,
    expectation: contextual.expectation,
    trigger: contextual.trigger,
    contextVersion: contextual.version,
    evidenceBreakdown: contextual.scoreBreakdown,
  );

  static RegimePlaybookEvaluation _evaluation({
    required RegimePlaybookId id,
    required ContextualPriceActionAssessment contextual,
    required PlaybookCandidateState state,
    required int quality,
    required TradeIdea? idea,
    required ChartDirection direction,
    required PlaybookManagementPolicy management,
    required String context,
    required String trigger,
    required String invalidation,
    required Iterable<double> targets,
    required Iterable<String> reasons,
  }) => RegimePlaybookEvaluation(
    playbook: id,
    version: playbookVersions[id]!,
    enabled: true,
    state: state,
    direction: _tradeDirection(direction),
    regime: contextual.regime,
    qualityScore: quality,
    context: context,
    trigger: trigger,
    invalidation: invalidation,
    targets: targets,
    managementPolicy: management,
    reasonCodes: ['playbook:${id.name}', ...reasons],
    idea: idea,
  );

  static RegimePlaybookEvaluation _disabled(
    RegimePlaybookId id,
    ContextualPriceActionAssessment contextual,
  ) => RegimePlaybookEvaluation(
    playbook: id,
    version: playbookVersions[id]!,
    enabled: false,
    state: PlaybookCandidateState.inactive,
    direction: TradeDirection.wait,
    regime: contextual.regime,
    qualityScore: 0,
    context: 'Feature flag disabled.',
    trigger: 'Disabled.',
    invalidation: 'Disabled.',
    targets: const [],
    managementPolicy: _management(id),
    reasonCodes: ['disabled:${id.name}'],
  );

  static _Resolution _resolve(List<RegimePlaybookEvaluation> evaluations) {
    final armed = evaluations.where((item) => item.isArmed).toList()
      ..sort((left, right) => right.qualityScore.compareTo(left.qualityScore));
    if (armed.isEmpty) {
      return const _Resolution(PlaybookConflictOutcome.none, null);
    }
    final directions = armed.map((item) => item.direction).toSet();
    if (directions.length <= 1) {
      return _Resolution(PlaybookConflictOutcome.none, armed.first);
    }
    final top = armed.first;
    final runnerUp = armed[1];
    if (top.qualityScore - runnerUp.qualityScore >= 10) {
      return _Resolution(
        PlaybookConflictOutcome.selectedHighestQuality,
        top,
      );
    }
    return const _Resolution(
      PlaybookConflictOutcome.ambiguousOpposingSignals,
      null,
    );
  }

  static List<String> _coverageGaps(
    MarketRegime regime,
    RegimePlaybookFeatureFlags flags,
  ) {
    final supported = switch (regime) {
      MarketRegime.directionalTrend => const [
        RegimePlaybookId.trendPullbackContinuation,
        RegimePlaybookId.momentumExpansionScalp,
      ],
      MarketRegime.range => const [
        RegimePlaybookId.rangeEdgeSweepReclaim,
        RegimePlaybookId.failedBreakoutReversal,
      ],
      MarketRegime.breakoutExpansion => const [
        RegimePlaybookId.breakoutAcceptanceRetest,
        RegimePlaybookId.momentumExpansionScalp,
      ],
      MarketRegime.transition => const <RegimePlaybookId>[],
      MarketRegime.disorder => const <RegimePlaybookId>[],
    };
    if (supported.isEmpty) {
      return [
        'regime:${regime.name}:observe-only-until-structure-resolves',
      ];
    }
    final enabledCount = supported.where(flags.enabled).length;
    return enabledCount >= 2
        ? const []
        : [
            'regime:${regime.name}:enabled-playbook-coverage=$enabledCount/2',
          ];
  }

  static int _quality(
    ContextualPriceActionAssessment contextual, {
    Iterable<int> bonuses = const [],
    Iterable<int> penalties = const [],
  }) {
    var value = contextual.setupQualityScore;
    for (final bonus in bonuses) value += bonus;
    for (final penalty in penalties) value -= penalty;
    return value.clamp(0, 100).toInt();
  }

  static bool _higherAligned(
    ChartDirection direction,
    RegimePlaybookRuntimeContext runtime,
  ) {
    if (direction == ChartDirection.sideways) return false;
    if (_parentRequired(runtime) && !runtime.higherTimeframeFresh) return false;
    final higher = runtime.higherTimeframeDirection;
    return higher == null || higher == direction;
  }

  static bool _parentRequired(RegimePlaybookRuntimeContext runtime) =>
      runtime.higherTimeframeDirection != null || runtime.higherTimeframeFresh;

  static TradeDirection _tradeDirection(ChartDirection value) => switch (value) {
    ChartDirection.bullish => TradeDirection.long,
    ChartDirection.bearish => TradeDirection.short,
    ChartDirection.sideways => TradeDirection.wait,
  };

  static ChartDirection _rangeDirection(
    TimeframeChartAnalysis analysis,
    ChartPriceZone? zone,
  ) {
    if (zone == null) return ChartDirection.sideways;
    return switch (zone.role) {
      ChartZoneRole.support => ChartDirection.bullish,
      ChartZoneRole.resistance => ChartDirection.bearish,
      ChartZoneRole.pivot => analysis.latestCandle.isBullish
          ? ChartDirection.bullish
          : ChartDirection.bearish,
    };
  }

  static PlaybookManagementPolicy _management(RegimePlaybookId id) =>
      switch (id) {
        RegimePlaybookId.trendPullbackContinuation =>
          PlaybookManagementPolicy.trendRunner,
        RegimePlaybookId.rangeEdgeSweepReclaim =>
          PlaybookManagementPolicy.rangeMeanThenOppositeEdge,
        RegimePlaybookId.breakoutAcceptanceRetest =>
          PlaybookManagementPolicy.breakoutRunner,
        RegimePlaybookId.failedBreakoutReversal =>
          PlaybookManagementPolicy.failedBreakScaleOut,
        RegimePlaybookId.momentumExpansionScalp =>
          PlaybookManagementPolicy.momentumQuickExit,
      };

  static bool _closedCandleGate(
    TimeframeChartAnalysis analysis,
    DateTime evaluatedAtUtc,
  ) {
    if (!evaluatedAtUtc.isUtc || analysis.candles.isEmpty) return false;
    final duration = _durationFor(analysis.timeframe);
    if (duration == Duration.zero) return false;
    return !analysis.latestCandle.openTime.add(duration).isAfter(evaluatedAtUtc);
  }

  static String? _parentTimeframe(String timeframe) => switch (timeframe) {
    '5m' => '15m',
    '15m' => '1h',
    '1h' => '4h',
    '4h' => '1D',
    _ => null,
  };

  static Duration _durationFor(String timeframe) => switch (timeframe) {
    '5m' => const Duration(minutes: 5),
    '15m' => const Duration(minutes: 15),
    '1h' => const Duration(hours: 1),
    '4h' => const Duration(hours: 4),
    '1D' => const Duration(days: 1),
    _ => Duration.zero,
  };

  static Duration _validityFor(String timeframe) => switch (timeframe) {
    '5m' => const Duration(minutes: 15),
    '15m' => const Duration(minutes: 45),
    '1h' => const Duration(hours: 3),
    '4h' => const Duration(hours: 12),
    '1D' => const Duration(days: 3),
    _ => Duration.zero,
  };

  static double _roundDown(double value, int decimals) {
    final factor = math.pow(10, decimals).toDouble();
    return (value * factor).floorToDouble() / factor;
  }
}

final class _Resolution {
  const _Resolution(this.outcome, this.selected);

  final PlaybookConflictOutcome outcome;
  final RegimePlaybookEvaluation? selected;
}
