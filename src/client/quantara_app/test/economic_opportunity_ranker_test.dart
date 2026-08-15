import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/decision_core/application/economic_opportunity_ranker.dart';
import 'package:quantara_app/features/decision_core/domain/economic_opportunity_models.dart';
import 'package:quantara_app/features/market_analysis/domain/market_regime_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';

void main() {
  final now = DateTime.utc(2026, 8, 15, 12);

  OpportunityRankingCandidate candidate({
    required String id,
    int quality = 80,
    double rr = 2,
    String timeframe = '1h',
    double currentPrice = 100,
    double entryLower = 99.5,
    double entryUpper = 100.5,
    OpportunityExecutionCostEvidence costs = const OpportunityExecutionCostEvidence(
      aggregateCostR: 0.1,
    ),
    double? holdingHours = 6,
    double? liquidity = 0.8,
    double? fill = 0.9,
    double correlation = 0,
    double concentration = 0,
    double tail = 0.05,
    OpportunityCalibrationEvidence? calibration,
    DateTime? createdAt,
    DateTime? validUntil,
  }) => OpportunityRankingCandidate(
    setupId: id,
    symbol: '${id.toUpperCase()}USDT',
    timeframe: timeframe,
    direction: TradeDirection.long,
    strategy: 'trendPullback',
    strategyVersion: 'trendPullback/1.0',
    marketRegime: MarketRegime.directionalTrend,
    createdAtUtc: createdAt ?? now.subtract(const Duration(hours: 1)),
    validUntilUtc: validUntil ?? now.add(const Duration(hours: 2)),
    setupQualityScore: quality,
    riskReward: rr,
    riskBudget: 10,
    requiredMargin: 50,
    currentPrice: currentPrice,
    entryLower: entryLower,
    entryUpper: entryUpper,
    stopLoss: 97,
    costs: costs,
    expectedHoldingHours: holdingHours,
    liquidityScore: liquidity,
    fillProbability: fill,
    correlationPenalty: correlation,
    concentrationPenalty: concentration,
    tailRiskPenalty: tail,
    calibration: calibration,
  );

  test('same inputs produce deterministic ordering and fingerprints', () {
    final inputs = [candidate(id: 'a'), candidate(id: 'b', quality: 83)];
    final first = EconomicOpportunityRanker.rank(
      candidates: inputs,
      evaluatedAtUtc: now,
    );
    final second = EconomicOpportunityRanker.rank(
      candidates: inputs.reversed,
      evaluatedAtUtc: now,
    );

    expect(first.map((item) => item.candidate.setupId), ['b', 'a']);
    expect(
      second.map((item) => item.candidate.setupId),
      first.map((item) => item.candidate.setupId),
    );
    expect(second.first.utility.fingerprint, first.first.utility.fingerprint);
  });

  test('lower setup quality can win on lower costs and shorter capital-time', () {
    final expensive = candidate(
      id: 'expensive',
      quality: 92,
      costs: const OpportunityExecutionCostEvidence(aggregateCostR: 0.65),
      holdingHours: 24,
      liquidity: 0.6,
      fill: 0.7,
    );
    final efficient = candidate(
      id: 'efficient',
      quality: 82,
      costs: const OpportunityExecutionCostEvidence(aggregateCostR: 0.05),
      holdingHours: 1.5,
      liquidity: 0.9,
      fill: 0.95,
    );

    final ranked = EconomicOpportunityRanker.rank(
      candidates: [expensive, efficient],
      evaluatedAtUtc: now,
    );

    expect(ranked.first.candidate.setupId, 'efficient');
    expect(
      ranked.first.utility.riskAdjustedEdgePerHour,
      greaterThan(ranked.last.utility.riskAdjustedEdgePerHour),
    );
  });

  test('fee funding spread slippage and latency are explicit rank costs', () {
    OpportunityExecutionCostEvidence cost({
      double? fee,
      double? funding,
      double? spread,
      double? slippage,
      double? latency,
    }) => OpportunityExecutionCostEvidence(
      feeR: fee ?? 0,
      fundingR: funding ?? 0,
      spreadR: spread ?? 0,
      slippageR: slippage ?? 0,
      latencyR: latency ?? 0,
    );

    for (final expensiveCost in [
      cost(fee: 0.5),
      cost(funding: 0.5),
      cost(spread: 0.5),
      cost(slippage: 0.5),
      cost(latency: 0.5),
    ]) {
      final ranked = EconomicOpportunityRanker.rank(
        candidates: [
          candidate(id: 'high-cost', quality: 85, costs: expensiveCost),
          candidate(id: 'low-cost', quality: 84, costs: cost(fee: 0.01)),
        ],
        evaluatedAtUtc: now,
      );
      expect(ranked.first.candidate.setupId, 'low-cost');
    }
  });

  test('correlation and concentration penalties can reorder candidates', () {
    final ranked = EconomicOpportunityRanker.rank(
      candidates: [
        candidate(
          id: 'crowded',
          quality: 88,
          correlation: 0.8,
          concentration: 0.8,
        ),
        candidate(id: 'diverse', quality: 84),
      ],
      evaluatedAtUtc: now,
    );

    expect(ranked.first.candidate.setupId, 'diverse');
    expect(ranked.last.utility.correlationPenalty, 0.8);
  });

  test('insufficient calibration never becomes a probability', () {
    final ranked = EconomicOpportunityRanker.rank(
      candidates: [
        candidate(
          id: 'uncalibrated',
          calibration: const OpportunityCalibrationEvidence(
            identity: 'trend/1h/v1',
            probability: 0.72,
            sampleCount: 20,
            brierScore: 0.15,
            calibrationError: 0.05,
          ),
        ),
      ],
      evaluatedAtUtc: now,
    );

    expect(ranked.single.utility.calibratedProbability, isNull);
    expect(ranked.single.utility.expectedNetR, isNull);
    expect(
      ranked.single.utility.unknownFields,
      contains('calibratedProbability'),
    );
  });

  test('healthy sufficiently sampled calibration enables expected net R', () {
    final ranked = EconomicOpportunityRanker.rank(
      candidates: [
        candidate(
          id: 'calibrated',
          calibration: const OpportunityCalibrationEvidence(
            identity: 'trend/1h/v1',
            probability: 0.72,
            sampleCount: 240,
            brierScore: 0.15,
            calibrationError: 0.05,
          ),
        ),
      ],
      evaluatedAtUtc: now,
    );

    expect(ranked.single.utility.calibratedProbability, 0.72);
    expect(ranked.single.utility.expectedNetR, isNotNull);
    expect(
      ranked.single.utility.unknownFields,
      isNot(contains('calibratedProbability')),
    );
  });

  test('freshness and chase distance can demote a higher quality setup', () {
    final ranked = EconomicOpportunityRanker.rank(
      candidates: [
        candidate(
          id: 'late-chase',
          quality: 90,
          currentPrice: 103,
          createdAt: now.subtract(const Duration(hours: 5)),
          validUntil: now.add(const Duration(minutes: 10)),
        ),
        candidate(id: 'fresh', quality: 84),
      ],
      evaluatedAtUtc: now,
    );

    expect(ranked.first.candidate.setupId, 'fresh');
    expect(ranked.last.utility.chasePenalty, greaterThan(1));
  });

  test('sensitivity reports stable plateau for an obvious winner', () {
    final result = OpportunityRankingSensitivity.evaluate(
      candidates: [
        candidate(id: 'winner', quality: 90, rr: 2.5, holdingHours: 1.5),
        candidate(
          id: 'loser',
          quality: 60,
          rr: 1.2,
          costs: const OpportunityExecutionCostEvidence(aggregateCostR: 0.5),
          holdingHours: 24,
        ),
      ],
      evaluatedAtUtc: now,
    );

    expect(result.scenarioCount, 8);
    expect(result.baselineTopSetupId, 'winner');
    expect(result.sharpOptimum, isFalse);
  });

  test('ranking journal preserves full component breakdown and outcome', () {
    final ranked = EconomicOpportunityRanker.rank(
      candidates: [candidate(id: 'journal')],
      evaluatedAtUtc: now,
    ).single;
    final record = OpportunityRankingJournalRecord(
      recordedAtUtc: now,
      rank: ranked.rank,
      setupId: ranked.candidate.setupId,
      symbol: ranked.candidate.symbol,
      policy: ranked.utility.policy,
      version: ranked.utility.version,
      outcome: OpportunityRankingOutcome.canonicalRejected,
      reason: 'test rejection',
      utilityFingerprint: ranked.utility.fingerprint,
      score: ranked.utility.score,
      componentBreakdown: ranked.utility.componentBreakdown,
      unknownFields: ranked.utility.unknownFields,
    );

    final restored = OpportunityRankingJournalRecord.fromJson(record.toJson());
    expect(restored.outcome, OpportunityRankingOutcome.canonicalRejected);
    expect(restored.componentBreakdown, ranked.utility.componentBreakdown);
    expect(restored.utilityFingerprint, ranked.utility.fingerprint);
  });

  test('policy metrics include drawdown cost and capital-time', () {
    final metrics = OpportunityRankingPolicyComparator.summarize(
      policy: OpportunityRankingPolicy.economicUtility,
      outcomes: const [
        OpportunityPolicyTradeOutcome(
          setupId: 'a',
          realizedNetR: 1,
          riskHours: 2,
          capitalHours: 10,
          executionCostR: 0.1,
        ),
        OpportunityPolicyTradeOutcome(
          setupId: 'b',
          realizedNetR: -0.5,
          riskHours: 1,
          capitalHours: 5,
          executionCostR: 0.08,
          missedOpportunityR: 0.4,
        ),
      ],
    );

    expect(metrics.netR, 0.5);
    expect(metrics.maximumDrawdownR, 0.5);
    expect(metrics.executionCostR, closeTo(0.18, 1e-9));
    expect(metrics.netRPerRiskHour, closeTo(1 / 6, 1e-9));
    expect(metrics.missedOpportunityR, 0.4);
  });
}
