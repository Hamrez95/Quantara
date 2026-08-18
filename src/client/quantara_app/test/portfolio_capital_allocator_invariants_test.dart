import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/capital_allocator/domain/portfolio_capital_allocator.dart';
import 'package:quantara_app/features/decision_core/domain/economic_opportunity_models.dart';
import 'package:quantara_app/features/portfolio_risk/domain/portfolio_risk_models.dart';

void main() {
  final now = DateTime.utc(2026, 8, 18, 9);

  test('duplicate proposal identity fails closed before evidence is ambiguous', () {
    const allocator = PortfolioCapitalAllocator(
      configuration: PortfolioAllocationConfiguration(
        riskReserveFraction: 0,
        marginReserveFraction: 0,
      ),
    );

    expect(
      () => allocator.allocate(
        proposals: [
          _proposal(
            id: 'same-id',
            symbol: 'BTCUSDT',
            score: 9,
            risk: 1,
            margin: 1,
            now: now,
          ),
          _proposal(
            id: 'same-id',
            symbol: 'ETHUSDT',
            score: 8,
            risk: 1,
            margin: 1,
            now: now,
          ),
        ],
        budget: const PortfolioAllocationBudget(
          availableRisk: 10,
          availableMargin: 20,
        ),
        nowUtc: now,
      ),
      throwsFormatException,
    );
  });

  test('randomized allocations preserve aggregate risk and margin ceilings', () {
    final random = Random(194);

    for (var round = 0; round < 64; round++) {
      const riskReserveFraction = 0.2;
      const marginReserveFraction = 0.25;
      const maximumSelections = 4;
      const allocator = PortfolioCapitalAllocator(
        configuration: PortfolioAllocationConfiguration(
          maximumSelections: maximumSelections,
          minimumUtilityScore: 0,
          riskReserveFraction: riskReserveFraction,
          marginReserveFraction: marginReserveFraction,
        ),
      );
      final availableRisk = 5 + random.nextDouble() * 25;
      final availableMargin = 10 + random.nextDouble() * 60;
      final proposals = List.generate(40, (index) {
        final allowed = random.nextDouble() > 0.15;
        return _proposal(
          id: 'r$round-$index',
          symbol: 'ASSET${round}_${index}USDT',
          score: random.nextDouble() * 20 - 2,
          risk: 0.1 + random.nextDouble() * 5,
          margin: 0.1 + random.nextDouble() * 12,
          now: now,
          allowed: allowed,
        );
      });

      final decision = allocator.allocate(
        proposals: proposals,
        budget: PortfolioAllocationBudget(
          availableRisk: availableRisk,
          availableMargin: availableMargin,
        ),
        nowUtc: now,
      );
      final allocatableRisk = availableRisk * (1 - riskReserveFraction);
      final allocatableMargin = availableMargin * (1 - marginReserveFraction);
      final selected = decision.selected;
      final selectedIds = selected.map((item) => item.proposalId).toSet();
      final selectedSymbols = selected.map((item) => item.symbol).toSet();
      final selectedRisk = selected.fold<double>(
        0,
        (sum, item) => sum + item.allocatedRisk,
      );
      final selectedMargin = selected.fold<double>(
        0,
        (sum, item) => sum + item.allocatedMargin,
      );

      expect(selected.length, lessThanOrEqualTo(maximumSelections));
      expect(selectedIds, hasLength(selected.length));
      expect(selectedSymbols, hasLength(selected.length));
      expect(decision.riskConsumed, lessThanOrEqualTo(allocatableRisk + 1e-9));
      expect(
        decision.marginConsumed,
        lessThanOrEqualTo(allocatableMargin + 1e-9),
      );
      expect(decision.riskConsumed, closeTo(selectedRisk, 1e-9));
      expect(decision.marginConsumed, closeTo(selectedMargin, 1e-9));
      expect(
        decision.riskConsumed + decision.riskRemainingOutsideReserve,
        closeTo(allocatableRisk, 1e-9),
      );
      expect(
        decision.marginConsumed + decision.marginRemainingOutsideReserve,
        closeTo(allocatableMargin, 1e-9),
      );
      expect(
        decision.items.where((item) => !item.selected).every(
          (item) => item.allocatedRisk == 0 && item.allocatedMargin == 0,
        ),
        isTrue,
      );
    }
  });
}

PortfolioAllocationProposal _proposal({
  required String id,
  required String symbol,
  required double score,
  required double risk,
  required double margin,
  required DateTime now,
  bool allowed = true,
}) => PortfolioAllocationProposal(
  utility: OpportunityUtility(
    policy: OpportunityRankingPolicy.economicUtility,
    version: 'economic-opportunity/1.0',
    setupId: 'setup-$id',
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
    componentBreakdown: {'score': score},
    unknownFields: const [],
    fingerprint: 'fingerprint-$id',
  ),
  candidate: PortfolioEntryCandidate(
    reservationId: 'reservation-$id',
    journalTradeId: 'trade-$id',
    candidateId: id,
    symbol: symbol,
    assetGroup: 'crypto-stress',
    side: PortfolioSide.long,
    strategy: 'allocator-stress',
    plannedQuantity: 1,
    entryPrice: 100,
    stopPrice: 99,
    contractMultiplier: 1,
    entryFeeRate: 0,
    exitFeeRate: 0,
    slippageRate: 0,
    fundingReserve: 0,
    requiredMargin: margin,
    leverage: 10,
    minimumQuantity: 0.001,
    minimumNotional: 1,
  ),
  riskDecision: PortfolioEntryDecision(
    allowed: allowed,
    liveExecutionAllowed: false,
    reason: allowed
        ? PortfolioEntryBlockReason.none
        : PortfolioEntryBlockReason.riskBudgetInsufficient,
    maximumLoss: risk,
    requiredMargin: margin,
    availableRiskBefore: 100,
    availableRiskAfter: allowed ? 100 - risk : 100,
    availableMarginAfter: allowed ? 100 - margin : 100,
  ),
  evidenceAsOfUtc: now,
);
