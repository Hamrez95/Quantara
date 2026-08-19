import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/capital_allocator/application/portfolio_allocation_policy_replay.dart';
import 'package:quantara_app/features/capital_allocator/domain/portfolio_capital_allocator.dart';
import 'package:quantara_app/features/decision_core/domain/economic_opportunity_models.dart';
import 'package:quantara_app/features/portfolio_risk/domain/portfolio_correlation_policy.dart';
import 'package:quantara_app/features/portfolio_risk/domain/portfolio_risk_models.dart';

void main() {
  final now = DateTime.utc(2026, 8, 19, 16);

  test('same replay stream produces stable fingerprints for every policy', () {
    final frames = [
      frame(
        'f1',
        now,
        proposals: [
          proposal('a', symbol: 'BTCUSDT', score: 9, assetGroup: 'major'),
          proposal('b', symbol: 'SOLUSDT', score: 7, assetGroup: 'alt'),
        ],
        outcomes: [
          outcome('a', realizedNetR: 1.2),
          outcome('b', realizedNetR: -0.5),
        ],
      ),
      frame(
        'f2',
        now.add(const Duration(minutes: 1)),
        proposals: [
          proposal('c', symbol: 'XRPUSDT', score: 8, assetGroup: 'alt-2'),
        ],
        outcomes: [outcome('c', realizedNetR: 0.8)],
      ),
    ];

    final first = PortfolioAllocationPolicyReplay.compare(frames: frames);
    final second = PortfolioAllocationPolicyReplay.compare(frames: frames);

    expect(
      first.map((value) => value.fingerprint),
      second.map((value) => value.fingerprint),
    );
    expect(
      first.map((value) => value.policy).toSet(),
      PortfolioAllocationReplayPolicy.values.toSet(),
    );
  });

  test(
    'equal-risk and utility-weighted policies size the same safe set differently',
    () {
      final replayFrame = frame(
        'sizing',
        now,
        proposals: [
          proposal(
            'high',
            symbol: 'BTCUSDT',
            score: 9,
            risk: 10,
            margin: 20,
            assetGroup: 'major',
          ),
          proposal(
            'low',
            symbol: 'SOLUSDT',
            score: 3,
            risk: 10,
            margin: 20,
            assetGroup: 'alt',
          ),
        ],
        outcomes: [outcome('high'), outcome('low')],
      );
      const configuration = PortfolioAllocationReplayConfiguration(
        totalRiskBudget: 10,
        totalMarginBudget: 100,
        maximumSelections: 2,
        correlationPolicy: PortfolioCorrelationPolicy(
          maximumBucketRiskFraction: 1,
        ),
      );

      final equal = PortfolioAllocationPolicyReplay.run(
        policy: PortfolioAllocationReplayPolicy.conservativeEqualRisk,
        frames: [replayFrame],
        configuration: configuration,
      );
      final weighted = PortfolioAllocationPolicyReplay.run(
        policy: PortfolioAllocationReplayPolicy.utilityWeightedFixedRisk,
        frames: [replayFrame],
        configuration: configuration,
      );

      expect(equal.frames.single.selected.map((value) => value.allocatedRisk), [
        5,
        5,
      ]);
      expect(
        weighted.frames.single.selected.map((value) => value.allocatedRisk),
        [7.5, 2.5],
      );
      expect(equal.metrics.riskTurnover, 10);
      expect(weighted.metrics.riskTurnover, 10);
    },
  );

  test('correlation policy can prefer a lower-ranked independent setup', () {
    final replayFrame = frame(
      'correlation',
      now,
      proposals: [
        proposal('btc', symbol: 'BTCUSDT', score: 10, risk: 4),
        proposal('eth', symbol: 'ETHUSDT', score: 9, risk: 4),
        proposal('xrp', symbol: 'XRPUSDT', score: 8, risk: 4),
      ],
      outcomes: [outcome('btc'), outcome('eth'), outcome('xrp')],
    );
    const configuration = PortfolioAllocationReplayConfiguration(
      totalRiskBudget: 10,
      totalMarginBudget: 100,
      maximumSelections: 3,
      correlationPolicy: PortfolioCorrelationPolicy(
        maximumBucketRiskFraction: 0.6,
        bucketBySymbol: {
          'BTCUSDT': 'majors',
          'ETHUSDT': 'majors',
          'XRPUSDT': 'alts',
        },
      ),
    );

    final result = PortfolioAllocationPolicyReplay.run(
      policy: PortfolioAllocationReplayPolicy.correlationAwareMarginalUtility,
      frames: [replayFrame],
      configuration: configuration,
    );

    expect(result.frames.single.selected.map((value) => value.proposalId), [
      'btc',
      'xrp',
    ]);
    expect(result.metrics.maximumConcentrationFraction, 0.4);
  });

  test('reserve-capacity policy intentionally keeps risk available', () {
    final replayFrame = frame(
      'reserve',
      now,
      proposals: [
        proposal(
          'first',
          symbol: 'BTCUSDT',
          score: 9,
          risk: 4,
          assetGroup: 'a',
        ),
        proposal(
          'second',
          symbol: 'SOLUSDT',
          score: 8,
          risk: 4,
          assetGroup: 'b',
        ),
      ],
      outcomes: [outcome('first'), outcome('second')],
    );
    const configuration = PortfolioAllocationReplayConfiguration(
      totalRiskBudget: 10,
      totalMarginBudget: 100,
      maximumSelections: 2,
      reserveRiskFraction: 0.4,
      reserveMarginFraction: 0,
      correlationPolicy: PortfolioCorrelationPolicy(
        maximumBucketRiskFraction: 1,
      ),
    );

    final result = PortfolioAllocationPolicyReplay.run(
      policy: PortfolioAllocationReplayPolicy.reserveCapacity,
      frames: [replayFrame],
      configuration: configuration,
    );

    expect(result.frames.single.selected.single.proposalId, 'first');
    expect(result.frames.single.lockedRiskAfterSelection, 4);
    expect(result.metrics.averageIdleRisk, 6);
  });

  test('hard Risk rejection is never selected by any replay policy', () {
    final replayFrame = frame(
      'hard-risk',
      now,
      proposals: [
        proposal(
          'unsafe',
          symbol: 'BTCUSDT',
          score: 100,
          allowed: false,
          assetGroup: 'major',
        ),
        proposal('safe', symbol: 'SOLUSDT', score: 5, assetGroup: 'alt'),
      ],
      outcomes: [outcome('unsafe'), outcome('safe')],
    );
    const configuration = PortfolioAllocationReplayConfiguration(
      correlationPolicy: PortfolioCorrelationPolicy(
        maximumBucketRiskFraction: 1,
      ),
    );

    for (final policy in PortfolioAllocationReplayPolicy.values) {
      final result = PortfolioAllocationPolicyReplay.run(
        policy: policy,
        frames: [replayFrame],
        configuration: configuration,
      );
      expect(
        result.frames.single.selected.map((value) => value.proposalId),
        isNot(contains('unsafe')),
      );
    }
  });

  test(
    'later stronger setup records regret while earlier capital remains locked',
    () {
      final frames = [
        frame(
          'early',
          now,
          proposals: [
            proposal(
              'early-low',
              symbol: 'BTCUSDT',
              score: 4,
              risk: 6,
              margin: 60,
              assetGroup: 'first',
            ),
          ],
          outcomes: [outcome('early-low', holdingFrames: 2)],
        ),
        frame(
          'later',
          now.add(const Duration(minutes: 1)),
          proposals: [
            proposal(
              'later-high',
              symbol: 'SOLUSDT',
              score: 10,
              risk: 6,
              margin: 60,
              assetGroup: 'second',
            ),
          ],
          outcomes: [outcome('later-high')],
        ),
      ];
      const configuration = PortfolioAllocationReplayConfiguration(
        totalRiskBudget: 6,
        totalMarginBudget: 60,
        maximumSelections: 1,
        correlationPolicy: PortfolioCorrelationPolicy(
          maximumBucketRiskFraction: 1,
        ),
      );

      final result = PortfolioAllocationPolicyReplay.run(
        policy: PortfolioAllocationReplayPolicy.correlationAwareMarginalUtility,
        frames: frames,
        configuration: configuration,
      );

      expect(result.frames.first.selected.single.proposalId, 'early-low');
      expect(result.frames.last.selected, isEmpty);
      expect(result.frames.last.opportunityRegret, 6);
      expect(result.metrics.opportunityRegret, 6);
    },
  );

  test('outcome coverage is fail closed', () {
    expect(
      () => PortfolioAllocationReplayFrame(
        frameId: 'invalid',
        occurredAtUtc: now,
        proposals: [proposal('a', symbol: 'BTCUSDT', score: 1)],
        outcomes: const [],
      ),
      throwsFormatException,
    );
  });
}

PortfolioAllocationReplayFrame frame(
  String id,
  DateTime at, {
  required List<PortfolioAllocationProposal> proposals,
  required List<PortfolioAllocationReplayOutcome> outcomes,
}) => PortfolioAllocationReplayFrame(
  frameId: id,
  occurredAtUtc: at,
  proposals: proposals,
  outcomes: outcomes,
);

PortfolioAllocationReplayOutcome outcome(
  String id, {
  double realizedNetR = 1,
  int holdingFrames = 1,
}) => PortfolioAllocationReplayOutcome(
  proposalId: id,
  realizedNetR: realizedNetR,
  riskHours: 1,
  capitalHours: 1,
  executionCostR: 0.05,
  holdingFrames: holdingFrames,
);

PortfolioAllocationProposal proposal(
  String id, {
  required String symbol,
  required double score,
  double risk = 2,
  double margin = 10,
  bool allowed = true,
  String assetGroup = 'crypto',
}) {
  final utility = OpportunityUtility(
    policy: OpportunityRankingPolicy.economicUtility,
    version: 'economic-opportunity/1.0',
    setupId: id,
    score: score,
    qualityRewardProxyR: 1,
    calibratedProbability: null,
    expectedGrossR: null,
    expectedNetR: null,
    executionCostR: 0,
    expectedHoldingHours: 1,
    riskHours: 1,
    capitalHours: 1,
    riskAdjustedEdgePerHour: score,
    returnPerCapitalHour: score,
    freshnessScore: 1,
    chasePenalty: 0,
    liquidityScore: 1,
    fillScore: 1,
    correlationPenalty: 0,
    concentrationPenalty: 0,
    tailRiskPenalty: 0,
    uncertaintyPenalty: 0,
    componentBreakdown: {'test': score},
    unknownFields: const [],
    fingerprint: 'fingerprint-$id',
  );
  final candidate = PortfolioEntryCandidate(
    reservationId: 'reservation-$id',
    journalTradeId: 'trade-$id',
    candidateId: id,
    symbol: symbol,
    assetGroup: assetGroup,
    side: PortfolioSide.long,
    strategy: 'replay-test',
    plannedQuantity: 1,
    entryPrice: 100,
    stopPrice: 99,
    contractMultiplier: 1,
    entryFeeRate: 0,
    exitFeeRate: 0,
    slippageRate: 0,
    fundingReserve: 0,
    requiredMargin: margin,
    leverage: 3,
    minimumQuantity: 0.001,
    minimumNotional: 1,
  );
  final decision = PortfolioEntryDecision(
    allowed: allowed,
    liveExecutionAllowed: false,
    reason: allowed
        ? PortfolioEntryBlockReason.none
        : PortfolioEntryBlockReason.riskBudgetInsufficient,
    maximumLoss: risk,
    requiredMargin: margin,
    availableRiskBefore: 10,
    availableRiskAfter: allowed ? 10 - risk : 10,
    availableMarginAfter: allowed ? 100 - margin : 100,
  );
  return PortfolioAllocationProposal(
    utility: utility,
    candidate: candidate,
    riskDecision: decision,
    evidenceAsOfUtc: DateTime.utc(2026, 8, 19, 16),
  );
}
