import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/capital_allocator/domain/portfolio_capital_allocator.dart';
import 'package:quantara_app/features/decision_core/domain/economic_opportunity_models.dart';
import 'package:quantara_app/features/portfolio_risk/domain/portfolio_correlation_policy.dart';
import 'package:quantara_app/features/portfolio_risk/domain/portfolio_risk_models.dart';

void main() {
  final now = DateTime.utc(2026, 8, 17, 8);

  OpportunityUtility utility(String id, double score) => OpportunityUtility(
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
    componentBreakdown: {'testScore': score},
    unknownFields: const [],
    fingerprint: 'fingerprint-$id',
  );

  PortfolioEntryCandidate candidate(
    String id, {
    required String symbol,
    double quantity = 1,
  }) => PortfolioEntryCandidate(
    reservationId: 'reservation-$id',
    journalTradeId: 'trade-$id',
    candidateId: id,
    symbol: symbol,
    assetGroup: 'crypto',
    side: PortfolioSide.long,
    strategy: 'test',
    plannedQuantity: quantity,
    entryPrice: 100,
    stopPrice: 99,
    contractMultiplier: 1,
    entryFeeRate: 0,
    exitFeeRate: 0,
    slippageRate: 0,
    fundingReserve: 0,
    requiredMargin: 2,
    leverage: 10,
    minimumQuantity: 0.001,
    minimumNotional: 1,
  );

  PortfolioEntryDecision riskDecision({
    bool allowed = true,
    double risk = 2,
    double margin = 2,
  }) => PortfolioEntryDecision(
    allowed: allowed,
    liveExecutionAllowed: false,
    reason: allowed
        ? PortfolioEntryBlockReason.none
        : PortfolioEntryBlockReason.riskBudgetInsufficient,
    maximumLoss: risk,
    requiredMargin: margin,
    availableRiskBefore: 10,
    availableRiskAfter: allowed ? 10 - risk : 10,
    availableMarginAfter: allowed ? 20 - margin : 20,
  );

  PortfolioAllocationProposal proposal(
    String id, {
    required String symbol,
    required double score,
    bool allowed = true,
    double risk = 2,
    double margin = 2,
  }) => PortfolioAllocationProposal(
    utility: utility(id, score),
    candidate: candidate(id, symbol: symbol),
    riskDecision: riskDecision(allowed: allowed, risk: risk, margin: margin),
    evidenceAsOfUtc: now,
  );

  PortfolioRiskLedger emptyLedger({double dailyRiskLimit = 10}) =>
      PortfolioRiskLedger.initial(
        tradingDay: TradingDayId.start(
          now: now,
          timezoneOffsetMinutes: 0,
        ),
        dailyRiskLimit: dailyRiskLimit,
      );

  const correlationPolicy = PortfolioCorrelationPolicy(
    maximumBucketRiskFraction: 0.6,
    bucketBySymbol: {
      'BTCUSDT': 'majors',
      'ETHUSDT': 'majors',
      'XRPUSDT': 'alts',
    },
  );

  test('selection is deterministic by economic utility, not input order', () {
    const allocator = PortfolioCapitalAllocator(
      configuration: PortfolioAllocationConfiguration(
        maximumSelections: 2,
        riskReserveFraction: 0,
        marginReserveFraction: 0,
      ),
    );
    final low = proposal('low', symbol: 'SOLUSDT', score: 2);
    final high = proposal('high', symbol: 'BTCUSDT', score: 9);

    final decision = allocator.allocate(
      proposals: [low, high],
      budget: const PortfolioAllocationBudget(
        availableRisk: 10,
        availableMargin: 20,
      ),
      nowUtc: now,
    );

    expect(decision.items.first.proposalId, 'high');
    expect(decision.selected.map((item) => item.proposalId), ['high', 'low']);
  });

  test('hard Risk rejection is never overridden by allocator ranking', () {
    const allocator = PortfolioCapitalAllocator(
      configuration: PortfolioAllocationConfiguration(
        riskReserveFraction: 0,
        marginReserveFraction: 0,
      ),
    );

    final decision = allocator.allocate(
      proposals: [
        proposal(
          'unsafe-high-score',
          symbol: 'BTCUSDT',
          score: 100,
          allowed: false,
        ),
        proposal('safe-lower-score', symbol: 'ETHUSDT', score: 10),
      ],
      budget: const PortfolioAllocationBudget(
        availableRisk: 10,
        availableMargin: 20,
      ),
      nowUtc: now,
    );

    expect(decision.selected.single.proposalId, 'safe-lower-score');
    expect(
      decision.items
          .firstWhere((item) => item.proposalId == 'unsafe-high-score')
          .reason,
      PortfolioAllocationReason.hardRiskRejected,
    );
  });

  test('reserve capacity can intentionally leave a free slot unused', () {
    const allocator = PortfolioCapitalAllocator(
      configuration: PortfolioAllocationConfiguration(
        maximumSelections: 3,
        riskReserveFraction: 0.4,
        marginReserveFraction: 0,
      ),
    );

    final decision = allocator.allocate(
      proposals: [
        proposal('a', symbol: 'BTCUSDT', score: 9, risk: 4),
        proposal('b', symbol: 'ETHUSDT', score: 8, risk: 3),
      ],
      budget: const PortfolioAllocationBudget(
        availableRisk: 10,
        availableMargin: 20,
      ),
      nowUtc: now,
    );

    expect(decision.selected.map((item) => item.proposalId), ['a']);
    expect(decision.riskHeldInReserve, 4);
    expect(
      decision.items.firstWhere((item) => item.proposalId == 'b').reason,
      PortfolioAllocationReason.riskReserveProtected,
    );
  });

  test('same-symbol lower-ranked duplicate is rejected', () {
    const allocator = PortfolioCapitalAllocator(
      configuration: PortfolioAllocationConfiguration(
        maximumSelections: 3,
        riskReserveFraction: 0,
        marginReserveFraction: 0,
      ),
    );

    final decision = allocator.allocate(
      proposals: [
        proposal('btc-a', symbol: 'BTCUSDT', score: 9),
        proposal('btc-b', symbol: 'btcusdt', score: 8),
      ],
      budget: const PortfolioAllocationBudget(
        availableRisk: 10,
        availableMargin: 20,
      ),
      nowUtc: now,
    );

    expect(decision.selected.single.proposalId, 'btc-a');
    expect(
      decision.items.firstWhere((item) => item.proposalId == 'btc-b').reason,
      PortfolioAllocationReason.duplicateSymbol,
    );
  });

  test('weak opportunity set can deterministically choose zero positions', () {
    const allocator = PortfolioCapitalAllocator(
      configuration: PortfolioAllocationConfiguration(
        minimumUtilityScore: 5,
        riskReserveFraction: 0,
        marginReserveFraction: 0,
      ),
    );

    final decision = allocator.allocate(
      proposals: [
        proposal('weak-a', symbol: 'BTCUSDT', score: 4),
        proposal('weak-b', symbol: 'ETHUSDT', score: 3),
      ],
      budget: const PortfolioAllocationBudget(
        availableRisk: 10,
        availableMargin: 20,
      ),
      nowUtc: now,
    );

    expect(decision.selected, isEmpty);
    expect(
      decision.items.every(
        (item) =>
            item.reason == PortfolioAllocationReason.utilityBelowThreshold,
      ),
      isTrue,
    );
  });

  test('margin reserve is protected independently of risk capacity', () {
    const allocator = PortfolioCapitalAllocator(
      configuration: PortfolioAllocationConfiguration(
        maximumSelections: 3,
        riskReserveFraction: 0,
        marginReserveFraction: 0.5,
      ),
    );

    final decision = allocator.allocate(
      proposals: [
        proposal('a', symbol: 'BTCUSDT', score: 9, risk: 1, margin: 6),
        proposal('b', symbol: 'ETHUSDT', score: 8, risk: 1, margin: 5),
      ],
      budget: const PortfolioAllocationBudget(
        availableRisk: 10,
        availableMargin: 20,
      ),
      nowUtc: now,
    );

    expect(decision.selected.single.proposalId, 'a');
    expect(decision.marginHeldInReserve, 10);
    expect(
      decision.items.firstWhere((item) => item.proposalId == 'b').reason,
      PortfolioAllocationReason.marginReserveProtected,
    );
  });

  test('slot ceiling is a hard ceiling and never a target', () {
    const allocator = PortfolioCapitalAllocator(
      configuration: PortfolioAllocationConfiguration(
        maximumSelections: 1,
        riskReserveFraction: 0,
        marginReserveFraction: 0,
      ),
    );

    final decision = allocator.allocate(
      proposals: [
        proposal('a', symbol: 'BTCUSDT', score: 9),
        proposal('b', symbol: 'ETHUSDT', score: 8),
      ],
      budget: const PortfolioAllocationBudget(
        availableRisk: 10,
        availableMargin: 20,
      ),
      nowUtc: now,
    );

    expect(decision.selected.single.proposalId, 'a');
    expect(
      decision.items.firstWhere((item) => item.proposalId == 'b').reason,
      PortfolioAllocationReason.slotCeiling,
    );
  });

  test(
    'correlation-aware marginal selection skips correlated candidate and admits independent lower rank',
    () {
      const allocator = PortfolioCapitalAllocator(
        configuration: PortfolioAllocationConfiguration(
          maximumSelections: 2,
          riskReserveFraction: 0,
          marginReserveFraction: 0,
        ),
      );

      final decision = allocator.allocate(
        proposals: [
          proposal('btc', symbol: 'BTCUSDT', score: 9, risk: 4),
          proposal('eth', symbol: 'ETHUSDT', score: 8, risk: 4),
          proposal('xrp', symbol: 'XRPUSDT', score: 7, risk: 4),
        ],
        budget: const PortfolioAllocationBudget(
          availableRisk: 20,
          availableMargin: 20,
        ),
        nowUtc: now,
        correlation: PortfolioAllocationCorrelationContext(
          ledger: emptyLedger(),
          policy: correlationPolicy,
        ),
      );

      expect(decision.selected.map((item) => item.proposalId), ['btc', 'xrp']);
      final eth = decision.items.firstWhere(
        (item) => item.proposalId == 'eth',
      );
      expect(eth.reason, PortfolioAllocationReason.correlationBucketLimit);
      expect(eth.correlationBucket, 'majors');
      expect(eth.correlationRiskBefore, 4);
      expect(eth.correlationRiskAfter, 8);
      expect(eth.correlationRiskLimit, 6);
    },
  );

  test('correlation context includes existing active reservation exposure', () {
    const allocator = PortfolioCapitalAllocator(
      configuration: PortfolioAllocationConfiguration(
        maximumSelections: 2,
        riskReserveFraction: 0,
        marginReserveFraction: 0,
      ),
    );
    final existing = candidate('existing-btc', symbol: 'BTCUSDT');
    final ledger = emptyLedger().reserve(
      candidate: existing,
      decision: riskDecision(risk: 4),
      createdAt: now,
    );

    final decision = allocator.allocate(
      proposals: [
        proposal('eth', symbol: 'ETHUSDT', score: 9, risk: 3),
        proposal('xrp', symbol: 'XRPUSDT', score: 8, risk: 3),
      ],
      budget: const PortfolioAllocationBudget(
        availableRisk: 20,
        availableMargin: 20,
      ),
      nowUtc: now,
      correlation: PortfolioAllocationCorrelationContext(
        ledger: ledger,
        policy: correlationPolicy,
      ),
    );

    expect(decision.selected.single.proposalId, 'xrp');
    final eth = decision.items.firstWhere((item) => item.proposalId == 'eth');
    expect(eth.reason, PortfolioAllocationReason.correlationBucketLimit);
    expect(eth.correlationRiskBefore, 4);
    expect(eth.correlationRiskAfter, 7);
    expect(eth.correlationRiskLimit, 6);
  });
}
