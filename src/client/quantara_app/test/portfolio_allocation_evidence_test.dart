import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/capital_allocator/domain/portfolio_allocation_evidence.dart';
import 'package:quantara_app/features/capital_allocator/domain/portfolio_capital_allocator.dart';
import 'package:quantara_app/features/decision_core/domain/economic_opportunity_models.dart';
import 'package:quantara_app/features/portfolio_risk/domain/portfolio_risk_models.dart';

void main() {
  final now = DateTime.utc(2026, 8, 18, 8);

  PortfolioAllocationProposal proposal(
    String id, {
    required String symbol,
    required double score,
    required DateTime evidenceAsOfUtc,
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
      componentBreakdown: {'testScore': score},
      unknownFields: const [],
      fingerprint: 'fingerprint-$id',
    );
    final candidate = PortfolioEntryCandidate(
      reservationId: 'reservation-$id',
      journalTradeId: 'trade-$id',
      candidateId: id,
      symbol: symbol,
      assetGroup: 'crypto',
      side: PortfolioSide.long,
      strategy: 'test',
      plannedQuantity: 1,
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
    const riskDecision = PortfolioEntryDecision(
      allowed: true,
      liveExecutionAllowed: false,
      reason: PortfolioEntryBlockReason.none,
      maximumLoss: 2,
      requiredMargin: 2,
      availableRiskBefore: 10,
      availableRiskAfter: 8,
      availableMarginAfter: 18,
    );
    return PortfolioAllocationProposal(
      utility: utility,
      candidate: candidate,
      riskDecision: riskDecision,
      evidenceAsOfUtc: evidenceAsOfUtc,
    );
  }

  PortfolioAllocationItemDecision item({
    required String proposalId,
    required String symbol,
  }) => PortfolioAllocationItemDecision(
    proposalId: proposalId,
    symbol: symbol,
    utilityScore: 1,
    reason: PortfolioAllocationReason.selected,
    requestedRisk: 2,
    allocatedRisk: 2,
    requestedMargin: 2,
    allocatedMargin: 2,
    requestedQuantity: 1,
    allocatedQuantity: 1,
  );

  PortfolioAllocationDecision decisionWith(
    Iterable<PortfolioAllocationItemDecision> items,
  ) => PortfolioAllocationDecision(
    version: 'portfolio-allocator/1.1',
    generatedAtUtc: now,
    items: items,
    riskConsumed: 0,
    marginConsumed: 0,
    riskHeldInReserve: 0,
    marginHeldInReserve: 0,
    riskRemainingOutsideReserve: 0,
    marginRemainingOutsideReserve: 0,
  );

  test('snapshot preserves ranked considered IDs and evidence timestamps', () {
    const allocator = PortfolioCapitalAllocator(
      configuration: PortfolioAllocationConfiguration(
        maximumSelections: 2,
        riskReserveFraction: 0,
        marginReserveFraction: 0,
      ),
    );
    final highEvidence = now.subtract(const Duration(seconds: 2));
    final lowEvidence = now.subtract(const Duration(seconds: 1));
    final high = proposal(
      'high',
      symbol: 'BTCUSDT',
      score: 9,
      evidenceAsOfUtc: highEvidence,
    );
    final low = proposal(
      'low',
      symbol: 'ETHUSDT',
      score: 8,
      evidenceAsOfUtc: lowEvidence,
    );
    final decision = allocator.allocate(
      proposals: [low, high],
      budget: const PortfolioAllocationBudget(
        availableRisk: 10,
        availableMargin: 20,
      ),
      nowUtc: now,
    );

    final snapshot = PortfolioAllocationEvidenceBuilder.build(
      decision: decision,
      proposals: [low, high],
    );

    expect(snapshot.rankedProposalIds, ['high', 'low']);
    expect(snapshot.selectedProposalIds, ['high', 'low']);
    expect(snapshot.items.first.evidenceAsOfUtc, highEvidence);
    expect(snapshot.items.last.evidenceAsOfUtc, lowEvidence);
    expect(snapshot.allocatorVersion, decision.version);
  });

  test('missing proposal evidence fails closed', () {
    const allocator = PortfolioCapitalAllocator(
      configuration: PortfolioAllocationConfiguration(
        riskReserveFraction: 0,
        marginReserveFraction: 0,
      ),
    );
    final first = proposal(
      'first',
      symbol: 'BTCUSDT',
      score: 9,
      evidenceAsOfUtc: now,
    );
    final second = proposal(
      'second',
      symbol: 'ETHUSDT',
      score: 8,
      evidenceAsOfUtc: now,
    );
    final decision = allocator.allocate(
      proposals: [first, second],
      budget: const PortfolioAllocationBudget(
        availableRisk: 10,
        availableMargin: 20,
      ),
      nowUtc: now,
    );

    expect(
      () => PortfolioAllocationEvidenceBuilder.build(
        decision: decision,
        proposals: [first],
      ),
      throwsStateError,
    );
  });

  test('duplicate proposal IDs are rejected before evidence is emitted', () {
    final first = proposal(
      'same',
      symbol: 'BTCUSDT',
      score: 9,
      evidenceAsOfUtc: now,
    );
    final duplicate = proposal(
      'same',
      symbol: 'ETHUSDT',
      score: 8,
      evidenceAsOfUtc: now,
    );

    expect(
      () => PortfolioAllocationEvidenceBuilder.build(
        decision: decisionWith(const []),
        proposals: [first, duplicate],
      ),
      throwsFormatException,
    );
  });

  test('duplicate decision item cannot hide an omitted proposal', () {
    final first = proposal(
      'first',
      symbol: 'BTCUSDT',
      score: 9,
      evidenceAsOfUtc: now,
    );
    final second = proposal(
      'second',
      symbol: 'ETHUSDT',
      score: 8,
      evidenceAsOfUtc: now,
    );

    expect(
      () => PortfolioAllocationEvidenceBuilder.build(
        decision: decisionWith([
          item(proposalId: 'first', symbol: 'BTCUSDT'),
          item(proposalId: 'first', symbol: 'BTCUSDT'),
        ]),
        proposals: [first, second],
      ),
      throwsStateError,
    );
  });

  test('decision symbol must match the proposal evidence identity', () {
    final first = proposal(
      'first',
      symbol: 'BTCUSDT',
      score: 9,
      evidenceAsOfUtc: now,
    );

    expect(
      () => PortfolioAllocationEvidenceBuilder.build(
        decision: decisionWith([item(proposalId: 'first', symbol: 'ETHUSDT')]),
        proposals: [first],
      ),
      throwsStateError,
    );
  });
}
