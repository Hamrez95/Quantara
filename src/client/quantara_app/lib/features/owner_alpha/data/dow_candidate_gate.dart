import '../../market_analysis/data/dow_structure_engine.dart';
import '../../market_analysis/domain/dow_structure_models.dart';
import '../../market_analysis/domain/market_chart_models.dart';
import '../domain/owner_alpha_models.dart';

abstract final class DowCandidateGate {
  static TradeIdea evaluate({
    required TradeIdea idea,
    required TimeframeChartAnalysis analysis,
    required Map<String, ChartDirection> confluence,
    DowStructureRollout rollout = const DowStructureRollout.disabled(),
  }) {
    if (!rollout.enabled || !idea.isActionable) return idea;
    rollout.config.validate();

    final snapshot = DowStructureEngine.analyze(
      analysis: analysis,
      config: rollout.config,
    );
    final direction = switch (idea.direction) {
      TradeDirection.long => ChartDirection.bullish,
      TradeDirection.short => ChartDirection.bearish,
      TradeDirection.wait => ChartDirection.sideways,
    };
    final rangeCompatible =
        idea.strategyVersion.startsWith('rangeReversal/') ||
        idea.marketRegime.name == 'range';
    final trendContinuation = !rangeCompatible;
    final parent = _parentTimeframe(analysis.timeframe);
    final parentDirection = parent == null ? null : confluence[parent];
    final entry = idea.direction == TradeDirection.long
        ? idea.entryUpper!
        : idea.entryLower!;
    final alignment = DowStructuralAlignmentEngine.evaluate(
      snapshot: snapshot,
      candidateDirection: direction,
      trendContinuation: trendContinuation,
      rangeCompatible: rangeCompatible,
      entryPrice: entry,
      invalidationPrice: idea.stopLoss!,
      firstTargetPrice: idea.targets.isEmpty ? null : idea.targets.first,
      parentDirection: parentDirection,
      cap: rollout.config.scoreCap,
    );

    final enriched = _copy(
      idea,
      reasons: <String>[
        ...idea.reasons,
        'Dow Structural Alignment ${alignment.cappedScore.toStringAsFixed(1)}/${alignment.cap.toStringAsFixed(0)} — ${alignment.version}.',
        'dow:config:${snapshot.version}:${snapshot.configFingerprint}',
        'dow:alignment-version:${alignment.version}',
        ...alignment.reasonCodes,
        if (snapshot.external.latestHigh case final pivot?) pivot.reasonCode,
        if (snapshot.external.latestLow case final pivot?) pivot.reasonCode,
      ],
      contextVersion: idea.contextVersion.isEmpty
          ? '${snapshot.version}|${alignment.version}'
          : '${idea.contextVersion}|${snapshot.version}|${alignment.version}',
      evidenceBreakdown: <String, double>{
        ...idea.evidenceBreakdown,
        'dowStructuralAlignment': alignment.cappedScore,
      },
    );

    // Shadow records the same evidence without changing admission authority.
    if (!rollout.mayRejectNewCandidate || alignment.allowed) return enriched;

    final dataFailure = !snapshot.valid;
    return _copy(
      enriched,
      direction: TradeDirection.wait,
      confidencePercent: 35,
      entryLower: null,
      entryUpper: null,
      stopLoss: null,
      targets: const <double>[],
      riskReward: null,
      positionSize: null,
      notionalValue: null,
      recommendedLeverage: null,
      maximumSafeLeverage: null,
      requiredMargin: null,
      estimatedRoundTripCosts: 0,
      setupId: '${idea.setupId}|dow-blocked|${snapshot.version}',
      summary: dataFailure
          ? 'Dow structure evidence is stale, gapped or otherwise untrusted; no new entry is allowed.'
          : 'Dow structure does not align with this playbook; no new entry is allowed.',
      invalidation:
          'Re-evaluate only after a new closed candle produces trusted, playbook-compatible structural evidence.',
      rejectionReason: dataFailure
          ? SetupRejectionReason.dataUnavailable
          : SetupRejectionReason.weakDirection,
    );
  }

  static String? _parentTimeframe(String timeframe) => switch (timeframe) {
    '5m' => '15m',
    '15m' || '30m' => '1h',
    '1h' => '4h',
    '4h' => '1D',
    '1D' => null,
    _ => null,
  };

  static TradeIdea _copy(
    TradeIdea source, {
    TradeDirection? direction,
    int? confidencePercent,
    Object? entryLower = _sentinel,
    Object? entryUpper = _sentinel,
    Object? stopLoss = _sentinel,
    List<double>? targets,
    Object? riskReward = _sentinel,
    Object? positionSize = _sentinel,
    Object? notionalValue = _sentinel,
    Object? recommendedLeverage = _sentinel,
    Object? maximumSafeLeverage = _sentinel,
    Object? requiredMargin = _sentinel,
    double? estimatedRoundTripCosts,
    String? setupId,
    String? summary,
    String? invalidation,
    List<String>? reasons,
    SetupRejectionReason? rejectionReason,
    String? contextVersion,
    Map<String, double>? evidenceBreakdown,
  }) => TradeIdea(
    symbol: source.symbol,
    timeframe: source.timeframe,
    direction: direction ?? source.direction,
    confidencePercent: confidencePercent ?? source.confidencePercent,
    entryLower: identical(entryLower, _sentinel)
        ? source.entryLower
        : entryLower as double?,
    entryUpper: identical(entryUpper, _sentinel)
        ? source.entryUpper
        : entryUpper as double?,
    stopLoss: identical(stopLoss, _sentinel)
        ? source.stopLoss
        : stopLoss as double?,
    targets: targets ?? source.targets,
    riskReward: identical(riskReward, _sentinel)
        ? source.riskReward
        : riskReward as double?,
    maximumLoss: source.maximumLoss,
    positionSize: identical(positionSize, _sentinel)
        ? source.positionSize
        : positionSize as double?,
    notionalValue: identical(notionalValue, _sentinel)
        ? source.notionalValue
        : notionalValue as double?,
    recommendedLeverage: identical(recommendedLeverage, _sentinel)
        ? source.recommendedLeverage
        : recommendedLeverage as int?,
    maximumSafeLeverage: identical(maximumSafeLeverage, _sentinel)
        ? source.maximumSafeLeverage
        : maximumSafeLeverage as int?,
    requiredMargin: identical(requiredMargin, _sentinel)
        ? source.requiredMargin
        : requiredMargin as double?,
    estimatedRoundTripCosts:
        estimatedRoundTripCosts ?? source.estimatedRoundTripCosts,
    setupId: setupId ?? source.setupId,
    candleClosedAt: source.candleClosedAt,
    summary: summary ?? source.summary,
    invalidation: invalidation ?? source.invalidation,
    reasons: List.unmodifiable(reasons ?? source.reasons),
    rejectionReason: rejectionReason ?? source.rejectionReason,
    strategy: source.strategy,
    strategyVersion: source.strategyVersion,
    registryStrategyId: source.registryStrategyId,
    registryStrategyVersion: source.registryStrategyVersion,
    strategyParameterSchemaVersion: source.strategyParameterSchemaVersion,
    normalizedStrategyParameters: source.normalizedStrategyParameters,
    strategySnapshotHash: source.strategySnapshotHash,
    managementPolicyVersion: source.managementPolicyVersion,
    strategyImplementationVersion: source.strategyImplementationVersion,
    strategyLifecycle: source.strategyLifecycle,
    marketRegime: source.marketRegime,
    indicatorSnapshot: source.indicatorSnapshot,
    setupQualityScore: source.setupQualityScore,
    expectation: source.expectation,
    trigger: source.trigger,
    contextVersion: contextVersion ?? source.contextVersion,
    evidenceBreakdown: Map.unmodifiable(
      evidenceBreakdown ?? source.evidenceBreakdown,
    ),
  );

  static const Object _sentinel = Object();
}
