import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/capital_allocator/application/portfolio_allocation_planner.dart';
import 'package:quantara_app/features/capital_allocator/domain/portfolio_capital_allocator.dart';
import 'package:quantara_app/features/decision_core/domain/economic_opportunity_models.dart';
import 'package:quantara_app/features/portfolio_risk/application/portfolio_risk_coordinator.dart';
import 'package:quantara_app/features/portfolio_risk/domain/portfolio_risk_models.dart';

void main() {
  final now = DateTime.utc(2026, 8, 19, 12);

  test('planner preserves hard Risk rejection while selecting safe utility', () async {
    final ledger = _ledger(now);
    final safe = _input('safe', symbol: 'SOLUSDT', score: 8);
    final unsafe = _input('unsafe', symbol: 'BTCUSDT', score: 100);
    const planner = PortfolioAllocationPlanner(
      configuration: PortfolioAllocationConfiguration(
        maximumSelections: 2,
        riskReserveFraction: 0,
        marginReserveFraction: 0,
      ),
    );

    final plan = await planner.plan(
      inputs: [unsafe, safe],
      previewRisk: (candidate) async => _outcome(
        ledger: ledger,
        decision: _riskDecision(allowed: candidate.candidateId != 'unsafe'),
        now: now,
      ),
      budget: const PortfolioAllocationBudget(
        availableRisk: 10,
        availableMargin: 100,
      ),
      nowUtc: now,
    );

    expect(plan.selectedCandidateIds, ['safe']);
    expect(plan.riskLedgerRevision, ledger.revision);
    expect(plan.tradingDayId, ledger.tradingDay.value);
    expect(
      plan.decision.items
          .firstWhere((item) => item.proposalId == 'unsafe')
          .reason,
      PortfolioAllocationReason.hardRiskRejected,
    );
  });

  test('planner fails closed when risk ledger changes during previews', () async {
    final firstLedger = _ledger(now);
    final secondLedger = PortfolioRiskLedger(
      schemaVersion: firstLedger.schemaVersion,
      revision: firstLedger.revision + 1,
      tradingDay: firstLedger.tradingDay,
      dailyRiskLimit: firstLedger.dailyRiskLimit,
      realizedLoss: firstLedger.realizedLoss,
      realizedProfit: firstLedger.realizedProfit,
      reservations: firstLedger.reservations,
      processedEventIds: firstLedger.processedEventIds,
    );
    final inputs = [
      _input('first', symbol: 'BTCUSDT', score: 9),
      _input('second', symbol: 'SOLUSDT', score: 8),
    ];
    var calls = 0;

    await expectLater(
      const PortfolioAllocationPlanner().plan(
        inputs: inputs,
        previewRisk: (candidate) async {
          calls += 1;
          return _outcome(
            ledger: calls == 1 ? firstLedger : secondLedger,
            decision: _riskDecision(),
            now: now,
          );
        },
        budget: const PortfolioAllocationBudget(
          availableRisk: 10,
          availableMargin: 100,
        ),
        nowUtc: now,
      ),
      throwsStateError,
    );
  });

  test('utility and risk candidate must share one stable identity', () async {
    final candidate = _candidate('candidate', symbol: 'BTCUSDT');
    final mismatched = PortfolioAllocationPlannerInput(
      utility: _utility('different', 10),
      candidate: candidate,
      evidenceAsOfUtc: now,
    );

    await expectLater(
      const PortfolioAllocationPlanner().plan(
        inputs: [mismatched],
        previewRisk: (candidate) async => _outcome(
          ledger: _ledger(now),
          decision: _riskDecision(),
          now: now,
        ),
        budget: const PortfolioAllocationBudget(
          availableRisk: 10,
          availableMargin: 100,
        ),
        nowUtc: now,
      ),
      throwsFormatException,
    );
  });
}

PortfolioAllocationPlannerInput _input(
  String id, {
  required String symbol,
  required double score,
}) => PortfolioAllocationPlannerInput(
  utility: _utility(id, score),
  candidate: _candidate(id, symbol: symbol),
  evidenceAsOfUtc: DateTime.utc(2026, 8, 19, 12),
);

OpportunityUtility _utility(String id, double score) => OpportunityUtility(
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

PortfolioEntryCandidate _candidate(String id, {required String symbol}) =>
    PortfolioEntryCandidate(
      reservationId: 'reservation-$id',
      journalTradeId: 'trade-$id',
      candidateId: id,
      symbol: symbol,
      assetGroup: symbol.startsWith('BTC') ? 'crypto-major' : 'crypto-alt',
      side: PortfolioSide.long,
      strategy: 'planner-test',
      plannedQuantity: 1,
      entryPrice: 100,
      stopPrice: 98,
      contractMultiplier: 1,
      entryFeeRate: 0,
      exitFeeRate: 0,
      slippageRate: 0,
      fundingReserve: 0,
      requiredMargin: 10,
      leverage: 3,
      minimumQuantity: 0.001,
      minimumNotional: 1,
    );

PortfolioEntryDecision _riskDecision({bool allowed = true}) =>
    PortfolioEntryDecision(
      allowed: allowed,
      liveExecutionAllowed: allowed,
      reason: allowed
          ? PortfolioEntryBlockReason.none
          : PortfolioEntryBlockReason.riskBudgetInsufficient,
      maximumLoss: 2,
      requiredMargin: 10,
      availableRiskBefore: 10,
      availableRiskAfter: allowed ? 8 : 10,
      availableMarginAfter: allowed ? 90 : 100,
    );

PortfolioRiskLedger _ledger(DateTime now) => PortfolioRiskLedger.initial(
  tradingDay: TradingDayId.start(now: now, timezoneOffsetMinutes: 0),
  dailyRiskLimit: 10,
);

PortfolioReservationOutcome _outcome({
  required PortfolioRiskLedger ledger,
  required PortfolioEntryDecision decision,
  required DateTime now,
}) {
  final account = PortfolioAccountTruth(
    asOf: now,
    fresh: true,
    allOpenPositionsProtected: true,
    marginMode: 'isolated',
    freeMargin: 100,
    usedMargin: 0,
    maintenanceMargin: 0,
    pendingMarginReservations: 0,
    safetyBuffer: 0,
    feeReserve: 0,
  );
  return PortfolioReservationOutcome(
    decision: decision,
    ledger: ledger,
    snapshot: ledger.snapshot(account),
  );
}
