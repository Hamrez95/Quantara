import 'dart:collection';

import '../../market_analysis/domain/market_regime_models.dart';
import '../../owner_alpha/domain/owner_alpha_models.dart';

enum OpportunityRankingPolicy {
  setupQuality,
  deterministicRandom,
  expectancyOnly,
  economicUtility,
}

enum OpportunityRankingOutcome {
  ranked,
  duplicateSkipped,
  staleOrIncomplete,
  canonicalRejected,
  portfolioRejected,
  executionAttempted,
  entered,
  executionFailed,
}

final class OpportunityCalibrationEvidence {
  const OpportunityCalibrationEvidence({
    required this.identity,
    required this.probability,
    required this.sampleCount,
    required this.brierScore,
    required this.calibrationError,
  });

  final String identity;
  final double probability;
  final int sampleCount;
  final double brierScore;
  final double calibrationError;

  bool usableFor(OpportunityRankingConfiguration config) =>
      identity.trim().isNotEmpty &&
      probability.isFinite &&
      probability >= 0 &&
      probability <= 1 &&
      sampleCount >= config.minimumCalibrationSamples &&
      brierScore.isFinite &&
      brierScore >= 0 &&
      brierScore <= config.maximumBrierScore &&
      calibrationError.isFinite &&
      calibrationError >= 0 &&
      calibrationError <= config.maximumCalibrationError;

  Map<String, Object?> toJson() => {
    'identity': identity,
    'probability': probability,
    'sampleCount': sampleCount,
    'brierScore': brierScore,
    'calibrationError': calibrationError,
  };
}

final class OpportunityExecutionCostEvidence {
  const OpportunityExecutionCostEvidence({
    this.feeR,
    this.fundingR,
    this.spreadR,
    this.slippageR,
    this.latencyR,
    this.aggregateCostR,
  });

  final double? feeR;
  final double? fundingR;
  final double? spreadR;
  final double? slippageR;
  final double? latencyR;
  final double? aggregateCostR;

  double get knownComponentTotalR =>
      [feeR, fundingR, spreadR, slippageR, latencyR]
          .whereType<double>()
          .where((value) => value.isFinite && value >= 0)
          .fold(0, (sum, value) => sum + value);

  double get totalR {
    final aggregate = aggregateCostR;
    if (aggregate != null && aggregate.isFinite && aggregate >= 0) {
      return aggregate;
    }
    return knownComponentTotalR;
  }

  List<String> get unknownComponents => List.unmodifiable([
    if (feeR == null) 'fees',
    if (fundingR == null) 'funding',
    if (spreadR == null) 'spread',
    if (slippageR == null) 'slippage',
    if (latencyR == null) 'latency',
  ]);

  bool get valid => [
    feeR,
    fundingR,
    spreadR,
    slippageR,
    latencyR,
    aggregateCostR,
  ].whereType<double>().every((value) => value.isFinite && value >= 0);

  Map<String, Object?> toJson() => {
    'feeR': feeR,
    'fundingR': fundingR,
    'spreadR': spreadR,
    'slippageR': slippageR,
    'latencyR': latencyR,
    'aggregateCostR': aggregateCostR,
    'totalR': totalR,
    'unknownComponents': unknownComponents,
  };
}

final class OpportunityRankingCandidate {
  OpportunityRankingCandidate({
    required this.setupId,
    required this.symbol,
    required this.timeframe,
    required this.direction,
    required this.strategy,
    required this.strategyVersion,
    required this.marketRegime,
    required this.createdAtUtc,
    required this.validUntilUtc,
    required this.setupQualityScore,
    required this.riskReward,
    required this.riskBudget,
    required this.requiredMargin,
    required this.currentPrice,
    required this.entryLower,
    required this.entryUpper,
    required this.stopLoss,
    required this.costs,
    this.expectedHoldingHours,
    this.liquidityScore,
    this.fillProbability,
    this.correlationPenalty = 0,
    this.concentrationPenalty = 0,
    this.tailRiskPenalty = 0,
    this.calibration,
    Iterable<String> evidenceTags = const [],
  }) : evidenceTags = UnmodifiableListView(
         evidenceTags.toList(growable: false),
       ) {
    if (setupId.trim().isEmpty ||
        symbol.trim().isEmpty ||
        timeframe.trim().isEmpty ||
        strategy.trim().isEmpty ||
        strategyVersion.trim().isEmpty ||
        !createdAtUtc.isUtc ||
        !validUntilUtc.isUtc ||
        setupQualityScore < 0 ||
        setupQualityScore > 100 ||
        !riskReward.isFinite ||
        riskReward <= 0 ||
        !riskBudget.isFinite ||
        riskBudget <= 0 ||
        !currentPrice.isFinite ||
        currentPrice <= 0 ||
        !entryLower.isFinite ||
        !entryUpper.isFinite ||
        entryLower <= 0 ||
        entryUpper < entryLower ||
        !stopLoss.isFinite ||
        stopLoss <= 0 ||
        !costs.valid) {
      throw const FormatException('Economic opportunity candidate is invalid.');
    }
  }

  factory OpportunityRankingCandidate.fromTradeIdea({
    required TradeIdea idea,
    required double currentPrice,
    OpportunityExecutionCostEvidence? costs,
    double? expectedHoldingHours,
    double? liquidityScore,
    double? fillProbability,
    double correlationPenalty = 0,
    double concentrationPenalty = 0,
    double tailRiskPenalty = 0,
    OpportunityCalibrationEvidence? calibration,
    Iterable<String> evidenceTags = const [],
  }) {
    if (!idea.isActionable ||
        idea.entryLower == null ||
        idea.entryUpper == null ||
        idea.stopLoss == null ||
        idea.riskReward == null ||
        idea.maximumLoss <= 0) {
      throw const FormatException('Trade idea is not rankable.');
    }
    final aggregateR = idea.estimatedRoundTripCosts <= 0
        ? 0.0
        : idea.estimatedRoundTripCosts / idea.maximumLoss;
    return OpportunityRankingCandidate(
      setupId: idea.setupId,
      symbol: idea.symbol.trim().toUpperCase(),
      timeframe: idea.timeframe,
      direction: idea.direction,
      strategy: idea.strategy.name,
      strategyVersion: idea.strategyVersion,
      marketRegime: idea.marketRegime,
      createdAtUtc: idea.createdAt.toUtc(),
      validUntilUtc: idea.validUntil.toUtc(),
      setupQualityScore: idea.displayQualityScore,
      riskReward: idea.riskReward!,
      riskBudget: idea.maximumLoss,
      requiredMargin: idea.requiredMargin,
      currentPrice: currentPrice,
      entryLower: idea.entryLower!,
      entryUpper: idea.entryUpper!,
      stopLoss: idea.stopLoss!,
      costs:
          costs ?? OpportunityExecutionCostEvidence(aggregateCostR: aggregateR),
      expectedHoldingHours: expectedHoldingHours,
      liquidityScore: liquidityScore,
      fillProbability: fillProbability,
      correlationPenalty: correlationPenalty,
      concentrationPenalty: concentrationPenalty,
      tailRiskPenalty: tailRiskPenalty,
      calibration: calibration,
      evidenceTags: evidenceTags,
    );
  }

  final String setupId;
  final String symbol;
  final String timeframe;
  final TradeDirection direction;
  final String strategy;
  final String strategyVersion;
  final MarketRegime marketRegime;
  final DateTime createdAtUtc;
  final DateTime validUntilUtc;
  final int setupQualityScore;
  final double riskReward;
  final double riskBudget;
  final double? requiredMargin;
  final double currentPrice;
  final double entryLower;
  final double entryUpper;
  final double stopLoss;
  final OpportunityExecutionCostEvidence costs;
  final double? expectedHoldingHours;
  final double? liquidityScore;
  final double? fillProbability;
  final double correlationPenalty;
  final double concentrationPenalty;
  final double tailRiskPenalty;
  final OpportunityCalibrationEvidence? calibration;
  final UnmodifiableListView<String> evidenceTags;

  double get referenceEntry => (entryLower + entryUpper) / 2;

  double get chaseDistanceFraction {
    final band = (entryUpper - entryLower).abs();
    if (currentPrice >= entryLower && currentPrice <= entryUpper) return 0;
    final distance = currentPrice < entryLower
        ? entryLower - currentPrice
        : currentPrice - entryUpper;
    final normalizer = band > 0 ? band : referenceEntry * 0.001;
    return distance / normalizer;
  }
}

final class OpportunityRankingConfiguration {
  const OpportunityRankingConfiguration({
    this.version = 'economic-opportunity/1.0',
    this.minimumCalibrationSamples = 100,
    this.maximumBrierScore = 0.22,
    this.maximumCalibrationError = 0.12,
    this.qualityWeight = 1,
    this.netEdgeWeight = 1,
    this.riskHourWeight = 0.8,
    this.capitalHourWeight = 0.6,
    this.liquidityWeight = 0.25,
    this.fillWeight = 0.2,
    this.freshnessWeight = 0.25,
    this.chasePenaltyWeight = 0.35,
    this.correlationPenaltyWeight = 0.35,
    this.concentrationPenaltyWeight = 0.35,
    this.tailRiskPenaltyWeight = 0.3,
    this.uncertaintyPenaltyWeight = 0.35,
    this.maximumChaseDistanceBands = 2,
  });

  final String version;
  final int minimumCalibrationSamples;
  final double maximumBrierScore;
  final double maximumCalibrationError;
  final double qualityWeight;
  final double netEdgeWeight;
  final double riskHourWeight;
  final double capitalHourWeight;
  final double liquidityWeight;
  final double fillWeight;
  final double freshnessWeight;
  final double chasePenaltyWeight;
  final double correlationPenaltyWeight;
  final double concentrationPenaltyWeight;
  final double tailRiskPenaltyWeight;
  final double uncertaintyPenaltyWeight;
  final double maximumChaseDistanceBands;

  bool get valid =>
      version.trim().isNotEmpty &&
      minimumCalibrationSamples >= 20 &&
      maximumBrierScore.isFinite &&
      maximumBrierScore > 0 &&
      maximumBrierScore <= 1 &&
      maximumCalibrationError.isFinite &&
      maximumCalibrationError >= 0 &&
      maximumCalibrationError <= 1 &&
      maximumChaseDistanceBands.isFinite &&
      maximumChaseDistanceBands > 0 &&
      _weights.every((value) => value.isFinite && value >= 0 && value <= 5);

  List<double> get _weights => [
    qualityWeight,
    netEdgeWeight,
    riskHourWeight,
    capitalHourWeight,
    liquidityWeight,
    fillWeight,
    freshnessWeight,
    chasePenaltyWeight,
    correlationPenaltyWeight,
    concentrationPenaltyWeight,
    tailRiskPenaltyWeight,
    uncertaintyPenaltyWeight,
  ];

  OpportunityRankingConfiguration copyWith({
    double? qualityWeight,
    double? netEdgeWeight,
    double? riskHourWeight,
    double? capitalHourWeight,
    double? liquidityWeight,
    double? fillWeight,
    double? freshnessWeight,
    double? chasePenaltyWeight,
    double? correlationPenaltyWeight,
    double? concentrationPenaltyWeight,
    double? tailRiskPenaltyWeight,
    double? uncertaintyPenaltyWeight,
  }) => OpportunityRankingConfiguration(
    version: version,
    minimumCalibrationSamples: minimumCalibrationSamples,
    maximumBrierScore: maximumBrierScore,
    maximumCalibrationError: maximumCalibrationError,
    qualityWeight: qualityWeight ?? this.qualityWeight,
    netEdgeWeight: netEdgeWeight ?? this.netEdgeWeight,
    riskHourWeight: riskHourWeight ?? this.riskHourWeight,
    capitalHourWeight: capitalHourWeight ?? this.capitalHourWeight,
    liquidityWeight: liquidityWeight ?? this.liquidityWeight,
    fillWeight: fillWeight ?? this.fillWeight,
    freshnessWeight: freshnessWeight ?? this.freshnessWeight,
    chasePenaltyWeight: chasePenaltyWeight ?? this.chasePenaltyWeight,
    correlationPenaltyWeight:
        correlationPenaltyWeight ?? this.correlationPenaltyWeight,
    concentrationPenaltyWeight:
        concentrationPenaltyWeight ?? this.concentrationPenaltyWeight,
    tailRiskPenaltyWeight: tailRiskPenaltyWeight ?? this.tailRiskPenaltyWeight,
    uncertaintyPenaltyWeight:
        uncertaintyPenaltyWeight ?? this.uncertaintyPenaltyWeight,
    maximumChaseDistanceBands: maximumChaseDistanceBands,
  );

  double holdingHoursFor(String timeframe) => switch (timeframe) {
    '5m' => 0.5,
    '15m' => 1.5,
    '1h' => 6,
    '4h' => 24,
    '1D' => 72,
    _ => 24,
  };
}

final class OpportunityUtility {
  OpportunityUtility({
    required this.policy,
    required this.version,
    required this.setupId,
    required this.score,
    required this.qualityRewardProxyR,
    required this.calibratedProbability,
    required this.expectedGrossR,
    required this.expectedNetR,
    required this.executionCostR,
    required this.expectedHoldingHours,
    required this.riskHours,
    required this.capitalHours,
    required this.riskAdjustedEdgePerHour,
    required this.returnPerCapitalHour,
    required this.freshnessScore,
    required this.chasePenalty,
    required this.liquidityScore,
    required this.fillScore,
    required this.correlationPenalty,
    required this.concentrationPenalty,
    required this.tailRiskPenalty,
    required this.uncertaintyPenalty,
    required Map<String, double> componentBreakdown,
    required Iterable<String> unknownFields,
    required this.fingerprint,
  }) : componentBreakdown = Map.unmodifiable(componentBreakdown),
       unknownFields = UnmodifiableListView(
         unknownFields.toList(growable: false),
       );

  final OpportunityRankingPolicy policy;
  final String version;
  final String setupId;
  final double score;
  final double qualityRewardProxyR;
  final double? calibratedProbability;
  final double? expectedGrossR;
  final double? expectedNetR;
  final double executionCostR;
  final double expectedHoldingHours;
  final double riskHours;
  final double capitalHours;
  final double riskAdjustedEdgePerHour;
  final double returnPerCapitalHour;
  final double freshnessScore;
  final double chasePenalty;
  final double liquidityScore;
  final double fillScore;
  final double correlationPenalty;
  final double concentrationPenalty;
  final double tailRiskPenalty;
  final double uncertaintyPenalty;
  final Map<String, double> componentBreakdown;
  final UnmodifiableListView<String> unknownFields;
  final String fingerprint;

  Map<String, Object?> toJson() => {
    'policy': policy.name,
    'version': version,
    'setupId': setupId,
    'score': score,
    'qualityRewardProxyR': qualityRewardProxyR,
    'calibratedProbability': calibratedProbability,
    'expectedGrossR': expectedGrossR,
    'expectedNetR': expectedNetR,
    'executionCostR': executionCostR,
    'expectedHoldingHours': expectedHoldingHours,
    'riskHours': riskHours,
    'capitalHours': capitalHours,
    'riskAdjustedEdgePerHour': riskAdjustedEdgePerHour,
    'returnPerCapitalHour': returnPerCapitalHour,
    'freshnessScore': freshnessScore,
    'chasePenalty': chasePenalty,
    'liquidityScore': liquidityScore,
    'fillScore': fillScore,
    'correlationPenalty': correlationPenalty,
    'concentrationPenalty': concentrationPenalty,
    'tailRiskPenalty': tailRiskPenalty,
    'uncertaintyPenalty': uncertaintyPenalty,
    'componentBreakdown': componentBreakdown,
    'unknownFields': unknownFields,
    'fingerprint': fingerprint,
  };
}

final class RankedOpportunity {
  const RankedOpportunity({
    required this.rank,
    required this.candidate,
    required this.utility,
  });

  final int rank;
  final OpportunityRankingCandidate candidate;
  final OpportunityUtility utility;
}

final class OpportunityRankingJournalRecord {
  OpportunityRankingJournalRecord({
    required this.recordedAtUtc,
    required this.rank,
    required this.setupId,
    required this.symbol,
    required this.policy,
    required this.version,
    required this.outcome,
    required this.reason,
    required this.utilityFingerprint,
    required this.score,
    required Map<String, double> componentBreakdown,
    required Iterable<String> unknownFields,
  }) : componentBreakdown = Map.unmodifiable(componentBreakdown),
       unknownFields = UnmodifiableListView(
         unknownFields.toList(growable: false),
       ) {
    if (!recordedAtUtc.isUtc ||
        rank < 1 ||
        setupId.trim().isEmpty ||
        symbol.trim().isEmpty ||
        version.trim().isEmpty ||
        utilityFingerprint.trim().isEmpty ||
        !score.isFinite) {
      throw const FormatException('Ranking journal record is invalid.');
    }
  }

  final DateTime recordedAtUtc;
  final int rank;
  final String setupId;
  final String symbol;
  final OpportunityRankingPolicy policy;
  final String version;
  final OpportunityRankingOutcome outcome;
  final String reason;
  final String utilityFingerprint;
  final double score;
  final Map<String, double> componentBreakdown;
  final UnmodifiableListView<String> unknownFields;

  Map<String, Object?> toJson() => {
    'recordedAtUtc': recordedAtUtc.toIso8601String(),
    'rank': rank,
    'setupId': setupId,
    'symbol': symbol,
    'policy': policy.name,
    'version': version,
    'outcome': outcome.name,
    'reason': reason,
    'utilityFingerprint': utilityFingerprint,
    'score': score,
    'componentBreakdown': componentBreakdown,
    'unknownFields': unknownFields,
  };

  factory OpportunityRankingJournalRecord.fromJson(Map<String, Object?> json) {
    final rawBreakdown = json['componentBreakdown'];
    final breakdown = <String, double>{};
    if (rawBreakdown is Map<Object?, Object?>) {
      for (final entry in rawBreakdown.entries) {
        final value = entry.value;
        if (value is num && value.isFinite) {
          breakdown[entry.key.toString()] = value.toDouble();
        }
      }
    }
    final unknowns = json['unknownFields'];
    return OpportunityRankingJournalRecord(
      recordedAtUtc: DateTime.parse(json['recordedAtUtc']!.toString()).toUtc(),
      rank: (json['rank'] as num).toInt(),
      setupId: json['setupId']!.toString(),
      symbol: json['symbol']!.toString(),
      policy: OpportunityRankingPolicy.values.firstWhere(
        (value) => value.name == json['policy'],
      ),
      version: json['version']!.toString(),
      outcome: OpportunityRankingOutcome.values.firstWhere(
        (value) => value.name == json['outcome'],
      ),
      reason: json['reason']?.toString() ?? '',
      utilityFingerprint: json['utilityFingerprint']!.toString(),
      score: (json['score'] as num).toDouble(),
      componentBreakdown: breakdown,
      unknownFields: unknowns is List<Object?>
          ? unknowns.map((value) => value.toString())
          : const <String>[],
    );
  }
}

final class OpportunityRankingSensitivityResult {
  const OpportunityRankingSensitivityResult({
    required this.baselineTopSetupId,
    required this.scenarioCount,
    required this.topChoiceChanges,
  });

  final String baselineTopSetupId;
  final int scenarioCount;
  final int topChoiceChanges;

  double get stabilityRatio =>
      scenarioCount <= 0 ? 1 : 1 - topChoiceChanges / scenarioCount;

  bool get sharpOptimum => scenarioCount >= 4 && stabilityRatio < 0.75;
}

final class OpportunityPolicyTradeOutcome {
  const OpportunityPolicyTradeOutcome({
    required this.setupId,
    required this.realizedNetR,
    required this.riskHours,
    required this.capitalHours,
    required this.executionCostR,
    this.missedOpportunityR = 0,
  });

  final String setupId;
  final double realizedNetR;
  final double riskHours;
  final double capitalHours;
  final double executionCostR;
  final double missedOpportunityR;
}

final class OpportunityRankingPolicyMetrics {
  const OpportunityRankingPolicyMetrics({
    required this.policy,
    required this.trades,
    required this.netR,
    required this.netRPerRiskHour,
    required this.returnPerCapitalHour,
    required this.maximumDrawdownR,
    required this.turnover,
    required this.missedOpportunityR,
    required this.executionCostR,
  });

  final OpportunityRankingPolicy policy;
  final int trades;
  final double netR;
  final double netRPerRiskHour;
  final double returnPerCapitalHour;
  final double maximumDrawdownR;
  final double turnover;
  final double missedOpportunityR;
  final double executionCostR;
}
