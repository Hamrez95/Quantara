import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

import '../domain/economic_opportunity_models.dart';

abstract final class EconomicOpportunityRanker {
  static List<RankedOpportunity> rank({
    required Iterable<OpportunityRankingCandidate> candidates,
    required DateTime evaluatedAtUtc,
    OpportunityRankingPolicy policy = OpportunityRankingPolicy.economicUtility,
    OpportunityRankingConfiguration config =
        const OpportunityRankingConfiguration(),
  }) {
    if (!evaluatedAtUtc.isUtc || !config.valid) {
      throw const FormatException('Opportunity ranking context is invalid.');
    }
    final evaluated = candidates
        .where((candidate) => evaluatedAtUtc.isBefore(candidate.validUntilUtc))
        .map(
          (candidate) => (
            candidate: candidate,
            utility: _evaluate(
              candidate: candidate,
              evaluatedAtUtc: evaluatedAtUtc,
              policy: policy,
              config: config,
            ),
          ),
        )
        .toList(growable: false);
    evaluated.sort((left, right) {
      final score = right.utility.score.compareTo(left.utility.score);
      if (score != 0) return score;
      return left.candidate.setupId.compareTo(right.candidate.setupId);
    });
    return List.unmodifiable([
      for (var index = 0; index < evaluated.length; index++)
        RankedOpportunity(
          rank: index + 1,
          candidate: evaluated[index].candidate,
          utility: evaluated[index].utility,
        ),
    ]);
  }

  static OpportunityUtility _evaluate({
    required OpportunityRankingCandidate candidate,
    required DateTime evaluatedAtUtc,
    required OpportunityRankingPolicy policy,
    required OpportunityRankingConfiguration config,
  }) {
    final calibration = candidate.calibration;
    final calibrated = calibration?.usableFor(config) ?? false;
    final probability = calibrated ? calibration!.probability : null;
    final quality = candidate.setupQualityScore / 100;
    final qualityRewardProxyR = quality * candidate.riskReward;
    final expectedGrossR = probability == null
        ? null
        : probability * candidate.riskReward - (1 - probability);
    final executionCostR = candidate.costs.totalR;
    final expectedNetR = expectedGrossR == null
        ? null
        : expectedGrossR - executionCostR;
    final proxyNetR = qualityRewardProxyR - executionCostR;
    final edgeBasis = expectedNetR ?? proxyNetR;
    final holdingHours = _positive(
      candidate.expectedHoldingHours,
      fallback: config.holdingHoursFor(candidate.timeframe),
    );
    final riskHours = holdingHours;
    final capitalBase = _positive(
      candidate.requiredMargin,
      fallback: candidate.riskBudget,
    );
    final capitalHours = capitalBase * holdingHours;
    final riskAdjustedEdgePerHour = edgeBasis / math.max(0.05, riskHours);
    final returnPerCapitalHour =
        edgeBasis * candidate.riskBudget / math.max(0.01, capitalHours);
    final totalValidity = candidate.validUntilUtc.difference(
      candidate.createdAtUtc,
    );
    final remaining = candidate.validUntilUtc.difference(evaluatedAtUtc);
    final freshness = totalValidity.inMilliseconds <= 0
        ? 0.0
        : (remaining.inMilliseconds / totalValidity.inMilliseconds).clamp(
            0.0,
            1.0,
          );
    final chase =
        (candidate.chaseDistanceFraction / config.maximumChaseDistanceBands)
            .clamp(0.0, 2.0);
    final liquidity = _bounded(candidate.liquidityScore, fallback: 0.5);
    final fill = _bounded(candidate.fillProbability, fallback: 0.5);
    final correlation = candidate.correlationPenalty.clamp(0.0, 1.0);
    final concentration = candidate.concentrationPenalty.clamp(0.0, 1.0);
    final tail = candidate.tailRiskPenalty.clamp(0.0, 1.0);
    final unknownFields = <String>[
      if (!calibrated) 'calibratedProbability',
      if (candidate.expectedHoldingHours == null) 'holdingTimeDistribution',
      if (candidate.liquidityScore == null) 'liquidityQuality',
      if (candidate.fillProbability == null) 'fillProbability',
      if (candidate.requiredMargin == null) 'capitalRequirement',
      ...candidate.costs.unknownComponents.map((item) => 'cost.$item'),
    ];
    final uncertainty = math.min(1.0, unknownFields.length / 10);

    final components = <String, double>{
      'qualityRewardProxyR': qualityRewardProxyR,
      'executionCostR': executionCostR,
      'edgeBasisR': edgeBasis,
      'expectedHoldingHours': holdingHours,
      'riskAdjustedEdgePerHour': riskAdjustedEdgePerHour,
      'returnPerCapitalHour': returnPerCapitalHour,
      'freshnessScore': freshness,
      'chasePenalty': chase,
      'liquidityScore': liquidity,
      'fillScore': fill,
      'correlationPenalty': correlation,
      'concentrationPenalty': concentration,
      'tailRiskPenalty': tail,
      'uncertaintyPenalty': uncertainty,
      'expectedGrossR': ?expectedGrossR,
      'expectedNetR': ?expectedNetR,
    };

    final score = switch (policy) {
      OpportunityRankingPolicy.setupQuality => quality,
      OpportunityRankingPolicy.deterministicRandom => _stableRandomScore(
        candidate.setupId,
        config.version,
      ),
      OpportunityRankingPolicy.expectancyOnly => edgeBasis - uncertainty * 0.25,
      OpportunityRankingPolicy.economicUtility =>
        quality * config.qualityWeight +
            edgeBasis * config.netEdgeWeight +
            riskAdjustedEdgePerHour * config.riskHourWeight +
            returnPerCapitalHour * config.capitalHourWeight +
            liquidity * config.liquidityWeight +
            fill * config.fillWeight +
            freshness * config.freshnessWeight -
            chase * config.chasePenaltyWeight -
            correlation * config.correlationPenaltyWeight -
            concentration * config.concentrationPenaltyWeight -
            tail * config.tailRiskPenaltyWeight -
            uncertainty * config.uncertaintyPenaltyWeight,
    };
    final fingerprint = _fingerprint(
      candidate: candidate,
      evaluatedAtUtc: evaluatedAtUtc,
      policy: policy,
      config: config,
      score: score,
      components: components,
      unknownFields: unknownFields,
    );
    return OpportunityUtility(
      policy: policy,
      version: config.version,
      setupId: candidate.setupId,
      score: score,
      qualityRewardProxyR: qualityRewardProxyR,
      calibratedProbability: probability,
      expectedGrossR: expectedGrossR,
      expectedNetR: expectedNetR,
      executionCostR: executionCostR,
      expectedHoldingHours: holdingHours,
      riskHours: riskHours,
      capitalHours: capitalHours,
      riskAdjustedEdgePerHour: riskAdjustedEdgePerHour,
      returnPerCapitalHour: returnPerCapitalHour,
      freshnessScore: freshness,
      chasePenalty: chase,
      liquidityScore: liquidity,
      fillScore: fill,
      correlationPenalty: correlation,
      concentrationPenalty: concentration,
      tailRiskPenalty: tail,
      uncertaintyPenalty: uncertainty,
      componentBreakdown: components,
      unknownFields: unknownFields,
      fingerprint: fingerprint,
    );
  }

  static double _positive(double? value, {required double fallback}) =>
      value != null && value.isFinite && value > 0 ? value : fallback;

  static double _bounded(double? value, {required double fallback}) =>
      value != null && value.isFinite ? value.clamp(0.0, 1.0) : fallback;

  static double _stableRandomScore(String setupId, String version) {
    final digest = sha256.convert(utf8.encode('$version|$setupId')).bytes;
    var value = 0;
    for (final byte in digest.take(6)) {
      value = (value << 8) | byte;
    }
    return value / 0x0000ffffffffffff;
  }

  static String _fingerprint({
    required OpportunityRankingCandidate candidate,
    required DateTime evaluatedAtUtc,
    required OpportunityRankingPolicy policy,
    required OpportunityRankingConfiguration config,
    required double score,
    required Map<String, double> components,
    required List<String> unknownFields,
  }) {
    final canonical = jsonEncode({
      'version': config.version,
      'policy': policy.name,
      'evaluatedAtUtc': evaluatedAtUtc.toIso8601String(),
      'setupId': candidate.setupId,
      'symbol': candidate.symbol,
      'timeframe': candidate.timeframe,
      'strategy': candidate.strategy,
      'strategyVersion': candidate.strategyVersion,
      'regime': candidate.marketRegime.name,
      'quality': candidate.setupQualityScore,
      'riskReward': candidate.riskReward,
      'currentPrice': candidate.currentPrice,
      'entryLower': candidate.entryLower,
      'entryUpper': candidate.entryUpper,
      'stopLoss': candidate.stopLoss,
      'score': score.toStringAsPrecision(16),
      'components': {
        for (final key in components.keys.toList()..sort())
          key: components[key]!.toStringAsPrecision(16),
      },
      'unknownFields': [...unknownFields]..sort(),
    });
    return sha256.convert(utf8.encode(canonical)).toString();
  }
}

abstract final class OpportunityRankingSensitivity {
  static OpportunityRankingSensitivityResult evaluate({
    required Iterable<OpportunityRankingCandidate> candidates,
    required DateTime evaluatedAtUtc,
    OpportunityRankingConfiguration config =
        const OpportunityRankingConfiguration(),
  }) {
    final values = candidates.toList(growable: false);
    final baseline = EconomicOpportunityRanker.rank(
      candidates: values,
      evaluatedAtUtc: evaluatedAtUtc,
      config: config,
    );
    if (baseline.isEmpty) {
      return const OpportunityRankingSensitivityResult(
        baselineTopSetupId: '',
        scenarioCount: 0,
        topChoiceChanges: 0,
      );
    }
    final scenarios = <OpportunityRankingConfiguration>[
      config.copyWith(netEdgeWeight: config.netEdgeWeight * 0.9),
      config.copyWith(netEdgeWeight: config.netEdgeWeight * 1.1),
      config.copyWith(riskHourWeight: config.riskHourWeight * 0.9),
      config.copyWith(riskHourWeight: config.riskHourWeight * 1.1),
      config.copyWith(chasePenaltyWeight: config.chasePenaltyWeight * 0.9),
      config.copyWith(chasePenaltyWeight: config.chasePenaltyWeight * 1.1),
      config.copyWith(
        uncertaintyPenaltyWeight: config.uncertaintyPenaltyWeight * 0.9,
      ),
      config.copyWith(
        uncertaintyPenaltyWeight: config.uncertaintyPenaltyWeight * 1.1,
      ),
    ];
    var changes = 0;
    for (final scenario in scenarios) {
      final ranked = EconomicOpportunityRanker.rank(
        candidates: values,
        evaluatedAtUtc: evaluatedAtUtc,
        config: scenario,
      );
      if (ranked.isNotEmpty &&
          ranked.first.candidate.setupId != baseline.first.candidate.setupId) {
        changes++;
      }
    }
    return OpportunityRankingSensitivityResult(
      baselineTopSetupId: baseline.first.candidate.setupId,
      scenarioCount: scenarios.length,
      topChoiceChanges: changes,
    );
  }
}

abstract final class OpportunityRankingPolicyComparator {
  static OpportunityRankingPolicyMetrics summarize({
    required OpportunityRankingPolicy policy,
    required Iterable<OpportunityPolicyTradeOutcome> outcomes,
  }) {
    final values = outcomes.toList(growable: false);
    var cumulative = 0.0;
    var peak = 0.0;
    var maximumDrawdown = 0.0;
    var riskHours = 0.0;
    var capitalHours = 0.0;
    var costs = 0.0;
    var missed = 0.0;
    for (final outcome in values) {
      cumulative += outcome.realizedNetR;
      peak = math.max(peak, cumulative);
      maximumDrawdown = math.max(maximumDrawdown, peak - cumulative);
      riskHours += math.max(0, outcome.riskHours);
      capitalHours += math.max(0, outcome.capitalHours);
      costs += math.max(0, outcome.executionCostR);
      missed += math.max(0, outcome.missedOpportunityR);
    }
    return OpportunityRankingPolicyMetrics(
      policy: policy,
      trades: values.length,
      netR: cumulative,
      netRPerRiskHour: riskHours <= 0 ? 0 : cumulative / riskHours,
      returnPerCapitalHour: capitalHours <= 0 ? 0 : cumulative / capitalHours,
      maximumDrawdownR: maximumDrawdown,
      turnover: values.length.toDouble(),
      missedOpportunityR: missed,
      executionCostR: costs,
    );
  }
}
