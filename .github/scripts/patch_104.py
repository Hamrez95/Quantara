from pathlib import Path
import re

# TradeIdea metadata copy helper.
models = Path('src/client/quantara_app/lib/features/owner_alpha/domain/owner_alpha_models.dart')
text = models.read_text()
helper = '''  TradeIdea copyWithPlaybookMetadata({
    required String strategyVersion,
    required int setupQualityScore,
    required String expectation,
    required String trigger,
    required String contextVersion,
    required Map<String, double> evidenceBreakdown,
  }) => TradeIdea(
    symbol: symbol,
    timeframe: timeframe,
    direction: direction,
    confidencePercent: confidencePercent,
    entryLower: entryLower,
    entryUpper: entryUpper,
    stopLoss: stopLoss,
    targets: targets,
    riskReward: riskReward,
    maximumLoss: maximumLoss,
    positionSize: positionSize,
    notionalValue: notionalValue,
    recommendedLeverage: recommendedLeverage,
    maximumSafeLeverage: maximumSafeLeverage,
    requiredMargin: requiredMargin,
    estimatedRoundTripCosts: estimatedRoundTripCosts,
    setupId: '$setupId|$strategyVersion',
    candleClosedAt: candleClosedAt,
    summary: summary,
    invalidation: invalidation,
    reasons: reasons,
    rejectionReason: rejectionReason,
    strategy: strategy,
    strategyVersion: strategyVersion,
    marketRegime: marketRegime,
    indicatorSnapshot: indicatorSnapshot,
    setupQualityScore: setupQualityScore,
    expectation: expectation,
    trigger: trigger,
    contextVersion: contextVersion,
    evidenceBreakdown: evidenceBreakdown,
  );

'''
marker = '  static TradeIdea wait({\n'
if helper not in text:
    assert marker in text
    text = text.replace(marker, helper + marker, 1)
models.write_text(text)

# Playbook engine refinements.
engine = Path('src/client/quantara_app/lib/features/owner_alpha/data/regime_playbook_portfolio_engine.dart')
text = engine.read_text()
resolver_import = "import 'regime_playbook_conflict_resolver.dart';\n"
if resolver_import not in text:
    text = text.replace(
        "import 'professional_strategy_engine.dart';\n",
        "import 'professional_strategy_engine.dart';\n" + resolver_import,
        1,
    )
text = text.replace(
    '    final resolution = _resolve(evaluations);',
    '    final resolution = RegimePlaybookConflictResolver.resolve(evaluations);',
    1,
)
for needle in (
    '        runtime: runtime,\n        enabled: flags.enabled(RegimePlaybookId.rangeEdgeSweepReclaim),',
    '        runtime: runtime,\n        enabled: flags.enabled(RegimePlaybookId.breakoutAcceptanceRetest),',
    '        runtime: runtime,\n        enabled: flags.enabled(RegimePlaybookId.failedBreakoutReversal),',
):
    text = text.replace(needle, needle.replace('        runtime: runtime,\n', ''), 1)
text = text.replace(
    '    required RegimePlaybookRuntimeContext runtime,\n    required bool enabled,\n    required Map<String, ChartDirection> confluence,\n    required ProfessionalStrategyContext context,\n  }) {\n    const id = RegimePlaybookId.rangeEdgeSweepReclaim;',
    '    required bool enabled,\n    required Map<String, ChartDirection> confluence,\n    required ProfessionalStrategyContext context,\n  }) {\n    const id = RegimePlaybookId.rangeEdgeSweepReclaim;',
    1,
)
text = text.replace(
    '    required RegimePlaybookRuntimeContext runtime,\n    required bool enabled,\n    required Map<String, ChartDirection> confluence,\n    required ProfessionalStrategyContext context,\n  }) {\n    const id = RegimePlaybookId.breakoutAcceptanceRetest;',
    '    required bool enabled,\n    required Map<String, ChartDirection> confluence,\n    required ProfessionalStrategyContext context,\n  }) {\n    const id = RegimePlaybookId.breakoutAcceptanceRetest;',
    1,
)
text = text.replace(
    '    required RegimePlaybookRuntimeContext runtime,\n    required bool enabled,\n    required ProfessionalStrategyContext context,\n  }) {\n    const id = RegimePlaybookId.failedBreakoutReversal;',
    '    required bool enabled,\n    required ProfessionalStrategyContext context,\n  }) {\n    const id = RegimePlaybookId.failedBreakoutReversal;',
    1,
)
text = text.replace(
    '    final higherAligned = _higherAligned(contextual.structure.bias, runtime);',
    '''    final higherAligned = _higherAligned(
      contextual.structure.bias,
      runtime,
      parentRequired: _parentTimeframe(analysis.timeframe) != null,
    );''',
    1,
)
text = text.replace(
    '    final higherAligned = _higherAligned(direction, runtime);',
    '''    final higherAligned = _higherAligned(
      direction,
      runtime,
      parentRequired: true,
    );''',
    1,
)
text = text.replace(
    '            minimumRiskReward: 1.35,\n            validityOverride: const Duration(minutes: 10),\n',
    '            minimumRiskReward: 1.35,\n',
    1,
)
text = text.replace(
    '    required double minimumRiskReward,\n    Duration? validityOverride,\n  }) {',
    '    required double minimumRiskReward,\n  }) {',
    1,
)
text = text.replace('    final validity = validityOverride ?? _validityFor(analysis.timeframe);\n', '', 1)
text = text.replace(
    '      evidenceBreakdown: contextual.scoreBreakdown,\n      validityOverride: validity,\n',
    '      evidenceBreakdown: contextual.scoreBreakdown,\n',
    1,
)
target_marker = '''    final target3 = long
        ? conservativeEntry + riskPerUnit * (minimumRiskReward + 1.35)
        : conservativeEntry - riskPerUnit * (minimumRiskReward + 1.35);
'''
target_guard = target_marker + '''    if ([target1, target2, target3].any((value) => !value.isFinite || value <= 0)) {
      return null;
    }
'''
if target_guard not in text:
    assert target_marker in text
    text = text.replace(target_marker, target_guard, 1)
text = re.sub(
    r'\n  static _Resolution _resolve\(List<RegimePlaybookEvaluation> evaluations\) \{.*?\n  \}\n\n  static List<String> _coverageGaps',
    '\n  static List<String> _coverageGaps',
    text,
    count=1,
    flags=re.S,
)
text = re.sub(
    r'  static bool _higherAligned\(\n    ChartDirection direction,\n    RegimePlaybookRuntimeContext runtime,\n  \) \{.*?\n  \}\n\n  static bool _parentRequired\(RegimePlaybookRuntimeContext runtime\) =>\n      runtime\.higherTimeframeDirection != null \|\| runtime\.higherTimeframeFresh;',
    '''  static bool _higherAligned(
    ChartDirection direction,
    RegimePlaybookRuntimeContext runtime, {
    required bool parentRequired,
  }) {
    if (direction == ChartDirection.sideways) return false;
    if (parentRequired && !runtime.higherTimeframeFresh) return false;
    final higher = runtime.higherTimeframeDirection;
    if (parentRequired && higher == null) return false;
    return higher == null || higher == direction;
  }''',
    text,
    count=1,
    flags=re.S,
)
text = re.sub(
    r'\n  static Duration _validityFor\(String timeframe\) => switch \(timeframe\) \{.*?\n  \};\n',
    '\n',
    text,
    count=1,
    flags=re.S,
)
text = re.sub(r'\nfinal class _Resolution \{.*?\n\}\n?$', '\n', text, count=1, flags=re.S)
engine.write_text(text)

# Candidate lifecycle uses Setup Quality when available.
candidate = Path('src/client/quantara_app/lib/features/owner_alpha/domain/realtime_candidate_models.dart')
text = candidate.read_text()
text = text.replace(
    "    if (idea.confidencePercent < 0 || idea.confidencePercent > 100) {\n      throw ArgumentError.value(idea.confidencePercent, 'confidencePercent');\n    }",
    "    if (idea.displayQualityScore < 0 || idea.displayQualityScore > 100) {\n      throw ArgumentError.value(idea.displayQualityScore, 'displayQualityScore');\n    }",
    1,
)
text = text.replace('      qualityScore: idea.confidencePercent,', '      qualityScore: idea.displayQualityScore,', 1)
candidate.write_text(text)

# Broad discovery integration.
discovery = Path('src/client/quantara_app/lib/features/owner_alpha/data/opportunity_discovery_universe.dart')
text = discovery.read_text()
if "import '../domain/regime_playbook_models.dart';\n" not in text:
    text = text.replace(
        "import '../domain/realtime_market_runtime_models.dart';\n",
        "import '../domain/realtime_market_runtime_models.dart';\nimport '../domain/regime_playbook_models.dart';\n",
        1,
    )
text = text.replace(
    "import 'realtime_production_runtime.dart';\nimport 'trade_idea_factory.dart';\n",
    "import 'realtime_production_runtime.dart';\nimport 'regime_playbook_portfolio_engine.dart';\n",
    1,
)
catalog_pattern = re.compile(r'final class _DiscoveryIdeaCatalog \{.*?\n\}\n\nfinal class _OpportunityDiscoveryRealtimeAnalyzer', re.S)
catalog_replacement = '''final class _DiscoveryIdeaCatalog {
  final Map<String, TradeIdea> _bySetup = {};
  final Map<String, String> _setupByStreamPlaybook = {};

  void remember(TradeIdea idea, {required RegimePlaybookId playbook}) {
    if (!idea.isActionable) return;
    _bySetup[idea.setupId] = idea;
    _setupByStreamPlaybook[_key(idea.symbol, idea.timeframe, playbook)] = idea.setupId;
    while (_bySetup.length > 4000) {
      final oldest = _bySetup.keys.first;
      _bySetup.remove(oldest);
      _setupByStreamPlaybook.removeWhere((_, setupId) => setupId == oldest);
    }
  }

  TradeIdea? currentFor(RealtimeCandleStreamKey key, RegimePlaybookId playbook) {
    final setupId = _setupByStreamPlaybook[_key(key.symbol, key.timeframe, playbook)];
    return setupId == null ? null : _bySetup[setupId];
  }

  static String _key(String symbol, String timeframe, RegimePlaybookId playbook) =>
      '$symbol|$timeframe|${playbook.name}';
}

final class _OpportunityDiscoveryRealtimeAnalyzer'''
text, count = catalog_pattern.subn(catalog_replacement, text, count=1)
assert count == 1, f'catalog patch count={count}'
field_marker = '''  String _languageCode;

  void setLanguage(String languageCode) {
'''
field_replacement = '''  String _languageCode;
  final Map<String, Map<String, ChartDirection>> _directionsBySymbol = {};

  RegimePlaybookFeatureFlags get _effectivePlaybookFlags {
    final environment = RegimePlaybookFeatureFlags.fromEnvironment();
    return RegimePlaybookFeatureFlags(
      trendPullbackContinuation: environment.trendPullbackContinuation && strategies.contains(AnalysisStrategy.trendPullback),
      rangeEdgeSweepReclaim: environment.rangeEdgeSweepReclaim && strategies.contains(AnalysisStrategy.structureZones),
      breakoutAcceptanceRetest: environment.breakoutAcceptanceRetest && strategies.contains(AnalysisStrategy.momentumContinuation),
      failedBreakoutReversal: environment.failedBreakoutReversal && strategies.contains(AnalysisStrategy.structureZones),
      momentumExpansionScalp: environment.momentumExpansionScalp && strategies.contains(AnalysisStrategy.momentumContinuation),
    );
  }

  void setLanguage(String languageCode) {
'''
if field_replacement not in text:
    assert field_marker in text
    text = text.replace(field_marker, field_replacement, 1)
method_pattern = re.compile(
    r'  @override\n  Future<RealtimeCandidateAnalysisBatch> analyze\(\n    RealtimeCandleAnalysisContext context,\n  \) async \{.*?\n  \}\n\}\n\nfinal class OpportunityDiscoveryCoverageProjection',
    re.S,
)
method_replacement = '''  @override
  Future<RealtimeCandidateAnalysisBatch> analyze(
    RealtimeCandleAnalysisContext context,
  ) async {
    coverage.recordAnalysis(context);
    if (context.closedCandles.length < 60) {
      return RealtimeCandidateAnalysisBatch();
    }
    final structure = ChartStructureAnalyzer.analyze(context.closedCandles);
    final latestClosed = context.closedCandles.last;
    final analysis = TimeframeChartAnalysis(
      symbol: context.key.symbol,
      timeframe: context.key.timeframe,
      candles: context.closedCandles,
      zones: structure.zones,
      direction: structure.direction,
      directionStrength: structure.directionStrength,
      volatilityPercent: structure.volatilityPercent,
      summary: _languageCode == 'en'
          ? 'Closed-candle regime playbook portfolio analysis.'
          : 'تحلیل پرتفوی Playbook بر پایه کندل بسته.',
      generatedAt: context.processedAtUtc,
      fingerprint:
          '${context.key.id}|${context.closedCandles.first.openTime.microsecondsSinceEpoch}|${latestClosed.openTime.microsecondsSinceEpoch}|${latestClosed.close}',
    );
    final directions = _directionsBySymbol.putIfAbsent(
      context.key.symbol,
      () => <String, ChartDirection>{},
    );
    directions[analysis.timeframe] = analysis.direction;
    final parent = switch (analysis.timeframe) {
      '5m' => '15m',
      '15m' => '1h',
      '1h' => '4h',
      '4h' => '1D',
      _ => null,
    };
    final latency = context.processedAtUtc.difference(context.receivedAtUtc);
    final safeLatency = latency.isNegative ? Duration.zero : latency;
    final portfolio = RegimePlaybookPortfolioEngine.evaluate(
      analysis: analysis,
      capital: settings.capital,
      riskPercent: settings.riskPercent,
      languageCode: _languageCode,
      cadence: settings.cadence,
      flags: _effectivePlaybookFlags,
      runtime: RegimePlaybookRuntimeContext(
        evaluatedAtUtc: context.processedAtUtc,
        higherTimeframeDirection: parent == null ? null : directions[parent],
        higherTimeframeFresh: parent == null || directions.containsKey(parent),
        liquidityVerified: true,
        processingLatency: safeLatency,
      ),
    );

    final candidates = <RealtimeOpportunityCandidate>[];
    final observations = <RealtimeObservationEnvelope>[];
    final selected = portfolio.selected;
    if (selected?.idea case final selectedIdea?) {
      catalog.remember(selectedIdea, playbook: selected!.playbook);
      projectionCatalog.remember(selectedIdea);
      candidates.add(
        RealtimeOpportunityCandidate.fromIdea(
          selectedIdea,
          detectedAtUtc: selectedIdea.createdAt.toUtc(),
          playbookId: '${selected.playbook.name}@${selected.version}',
        ),
      );
    }

    final conflict =
        portfolio.conflictOutcome == PlaybookConflictOutcome.ambiguousOpposingSignals;
    for (final evaluation in portfolio.evaluations) {
      final tracked = evaluation.idea ?? catalog.currentFor(context.key, evaluation.playbook);
      if (tracked == null) continue;
      final triggerPrice = context.triggersClosedCandleAnalysis
          ? latestClosed.close
          : context.workingCandle?.close ?? latestClosed.close;
      final selectedNow = selected?.playbook == evaluation.playbook;
      final triggerConfirmed =
          selectedNow &&
          context.triggersClosedCandleAnalysis &&
          triggerPrice >= tracked.entryLower! &&
          triggerPrice <= tracked.entryUpper!;
      final structureValid = !conflict &&
          switch (tracked.direction) {
            TradeDirection.long => triggerPrice > tracked.stopLoss!,
            TradeDirection.short => triggerPrice < tracked.stopLoss!,
            TradeDirection.wait => false,
          };
      observations.add(
        RealtimeObservationEnvelope(
          eventId:
              '${context.key.id}|${evaluation.playbook.name}|${context.disposition.name}|${context.exchangeTimestampUtc.microsecondsSinceEpoch}|${triggerPrice.toStringAsPrecision(12)}',
          setupId: tracked.setupId,
          symbol: tracked.symbol,
          timeframe: tracked.timeframe,
          observation: RealtimeMarketObservation(
            exchangeTimestampUtc: context.exchangeTimestampUtc,
            receivedAtUtc: context.receivedAtUtc,
            evaluatedAtUtc: context.processedAtUtc,
            lastPrice: triggerPrice,
            qualityScore: evaluation.qualityScore > 0
                ? evaluation.qualityScore
                : tracked.displayQualityScore,
            structureValid: structureValid,
            triggerConfirmed: triggerConfirmed,
            triggerCandleClosed: context.triggersClosedCandleAnalysis,
          ),
        ),
      );
    }
    return RealtimeCandidateAnalysisBatch(
      candidates: candidates,
      observations: observations,
    );
  }
}

final class OpportunityDiscoveryCoverageProjection'''
text, count = method_pattern.subn(method_replacement, text, count=1)
assert count == 1, f'analyzer method patch count={count}'
discovery.write_text(text)
