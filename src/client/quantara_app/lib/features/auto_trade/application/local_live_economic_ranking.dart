import '../../decision_core/application/economic_opportunity_ranker.dart';
import '../../decision_core/domain/economic_opportunity_models.dart';
import '../../market_analysis/domain/market_regime_models.dart';
import '../../owner_alpha/domain/owner_alpha_models.dart';
import '../domain/execution_quality_models.dart';

final class LocalLiveRankedIdea {
  const LocalLiveRankedIdea({required this.idea, required this.ranked});

  final TradeIdea idea;
  final RankedOpportunity ranked;
}

abstract final class LocalLiveEconomicRanking {
  static List<LocalLiveRankedIdea> rank({
    required Iterable<TradeIdea> ideas,
    required Map<String, double> lastPrices,
    required DateTime evaluatedAtUtc,
    Map<String, OpportunityCalibrationEvidence> calibrationBySetupId = const {},
    Map<String, double> concentrationPenaltyBySymbol = const {},
    Map<String, EstimatedExecutionCosts> executionCostsBySetupId = const {},
    Duration maximumExecutionEstimateAge = const Duration(seconds: 30),
    OpportunityRankingConfiguration config =
        const OpportunityRankingConfiguration(),
  }) {
    if (!evaluatedAtUtc.isUtc || maximumExecutionEstimateAge <= Duration.zero) {
      throw const FormatException('Local Live ranking time is invalid.');
    }
    final primary = _resolveConflictAndPreferredTimeframe(ideas);
    final bySetupId = {for (final idea in primary) idea.setupId: idea};
    final candidates = <OpportunityRankingCandidate>[];
    for (final idea in primary) {
      final price = lastPrices[idea.symbol.trim().toUpperCase()];
      if (price == null || !price.isFinite || price <= 0) continue;
      final relativeVolume = idea.indicatorSnapshot['relativeVolume20'];
      final liquidityProxy = relativeVolume == null || !relativeVolume.isFinite
          ? null
          : (relativeVolume / 2).clamp(0.0, 1.0);
      final executionEvidence = _rankingExecutionCosts(
        estimate: executionCostsBySetupId[idea.setupId],
        maximumLoss: idea.maximumLoss,
        evaluatedAtUtc: evaluatedAtUtc,
        maximumAge: maximumExecutionEstimateAge,
      );
      candidates.add(
        OpportunityRankingCandidate.fromTradeIdea(
          idea: idea,
          currentPrice: price,
          costs: executionEvidence.costs,
          expectedHoldingHours: config.holdingHoursFor(idea.timeframe),
          liquidityScore: liquidityProxy,
          concentrationPenalty:
              concentrationPenaltyBySymbol[idea.symbol.trim().toUpperCase()] ??
              0,
          tailRiskPenalty: _tailRiskPenalty(idea.marketRegime),
          calibration: calibrationBySetupId[idea.setupId],
          evidenceTags: [
            'holding:timeframe-prior-v1',
            if (liquidityProxy != null) 'liquidity:relative-volume-proxy',
            executionEvidence.tag,
            'correlation:unknown',
          ],
        ),
      );
    }
    final ranked = EconomicOpportunityRanker.rank(
      candidates: candidates,
      evaluatedAtUtc: evaluatedAtUtc,
      policy: OpportunityRankingPolicy.economicUtility,
      config: config,
    );
    return List.unmodifiable([
      for (final item in ranked)
        if (bySetupId[item.candidate.setupId] case final idea?)
          LocalLiveRankedIdea(idea: idea, ranked: item),
    ]);
  }

  static _ExecutionRankingEvidence _rankingExecutionCosts({
    required EstimatedExecutionCosts? estimate,
    required double maximumLoss,
    required DateTime evaluatedAtUtc,
    required Duration maximumAge,
  }) {
    if (estimate == null) {
      return const _ExecutionRankingEvidence(
        costs: null,
        tag: 'cost:trade-idea-aggregate',
      );
    }
    try {
      estimate.validate();
    } on FormatException {
      return const _ExecutionRankingEvidence(
        costs: null,
        tag: 'cost:execution-quality-invalid-fallback',
      );
    }
    if (estimate.evidenceQuality == ExecutionEvidenceQuality.insufficient) {
      return const _ExecutionRankingEvidence(
        costs: null,
        tag: 'cost:execution-quality-insufficient-fallback',
      );
    }
    final age = evaluatedAtUtc.difference(estimate.asOfUtc);
    if (age.isNegative || age > maximumAge || maximumLoss <= 0) {
      return const _ExecutionRankingEvidence(
        costs: null,
        tag: 'cost:execution-quality-stale-fallback',
      );
    }
    return _ExecutionRankingEvidence(
      costs: OpportunityExecutionCostEvidence(
        feeR: estimate.fees / maximumLoss,
        fundingR: estimate.funding / maximumLoss,
        spreadR: estimate.spread / maximumLoss,
        slippageR: estimate.slippage / maximumLoss,
        latencyR: estimate.latency / maximumLoss,
      ),
      tag: 'cost:execution-quality:${estimate.modelVersion}',
    );
  }

  static List<TradeIdea> _resolveConflictAndPreferredTimeframe(
    Iterable<TradeIdea> ideas,
  ) {
    final grouped = <String, List<TradeIdea>>{};
    for (final idea in ideas) {
      final key = '${idea.symbol.trim().toUpperCase()}|${idea.strategy.name}';
      grouped.putIfAbsent(key, () => []).add(idea);
    }
    final candidates = <TradeIdea>[];
    for (final group in grouped.values) {
      if (group.map((item) => item.direction).toSet().length != 1) continue;
      final timeframes = group.map((item) => item.timeframe).toSet();
      final preferred = timeframes.contains('4h') && timeframes.contains('1h')
          ? '1h'
          : timeframes.contains('4h')
          ? '4h'
          : timeframes.contains('1h')
          ? '1h'
          : timeframes.contains('15m')
          ? '15m'
          : '5m';
      final sameTimeframe =
          group
              .where((item) => item.timeframe == preferred)
              .toList(growable: false)
            ..sort((left, right) {
              final quality = right.displayQualityScore.compareTo(
                left.displayQualityScore,
              );
              if (quality != 0) return quality;
              return left.setupId.compareTo(right.setupId);
            });
      if (sameTimeframe.isNotEmpty) candidates.add(sameTimeframe.first);
    }
    return List.unmodifiable(candidates);
  }

  static double _tailRiskPenalty(MarketRegime regime) => switch (regime) {
    MarketRegime.directionalTrend => 0.05,
    MarketRegime.range => 0.1,
    MarketRegime.breakoutExpansion => 0.15,
    MarketRegime.transition => 0.35,
    MarketRegime.disorder => 0.7,
  };
}

final class _ExecutionRankingEvidence {
  const _ExecutionRankingEvidence({required this.costs, required this.tag});

  final OpportunityExecutionCostEvidence? costs;
  final String tag;
}
