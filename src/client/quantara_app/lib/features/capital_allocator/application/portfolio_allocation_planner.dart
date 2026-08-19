import '../../decision_core/domain/economic_opportunity_models.dart';
import '../../portfolio_risk/application/portfolio_risk_coordinator.dart';
import '../../portfolio_risk/domain/portfolio_correlation_policy.dart';
import '../../portfolio_risk/domain/portfolio_risk_models.dart';
import '../domain/portfolio_allocation_evidence.dart';
import '../domain/portfolio_capital_allocator.dart';

typedef PortfolioAllocationRiskPreview =
    Future<PortfolioReservationOutcome> Function(PortfolioEntryCandidate candidate);

final class PortfolioAllocationPlannerInput {
  const PortfolioAllocationPlannerInput({
    required this.utility,
    required this.candidate,
    required this.evidenceAsOfUtc,
  });

  final OpportunityUtility utility;
  final PortfolioEntryCandidate candidate;
  final DateTime evidenceAsOfUtc;

  void validate() {
    if (!evidenceAsOfUtc.isUtc ||
        utility.setupId.trim().isEmpty ||
        utility.setupId.trim() != candidate.candidateId.trim()) {
      throw const FormatException(
        'Allocation planner input must bind utility and risk candidate identity.',
      );
    }
  }
}

final class PortfolioAllocationPlan {
  const PortfolioAllocationPlan({
    required this.decision,
    required this.evidence,
    required this.riskLedgerRevision,
    required this.tradingDayId,
  });

  final PortfolioAllocationDecision decision;
  final PortfolioAllocationEvidenceSnapshot evidence;
  final int riskLedgerRevision;
  final String tradingDayId;

  List<String> get selectedCandidateIds => evidence.selectedProposalIds;
}

final class PortfolioAllocationPlanner {
  const PortfolioAllocationPlanner({
    this.configuration = const PortfolioAllocationConfiguration(),
    this.correlationPolicy = const PortfolioCorrelationPolicy(),
  });

  final PortfolioAllocationConfiguration configuration;
  final PortfolioCorrelationPolicy correlationPolicy;

  Future<PortfolioAllocationPlan> plan({
    required Iterable<PortfolioAllocationPlannerInput> inputs,
    required PortfolioAllocationRiskPreview previewRisk,
    required PortfolioAllocationBudget budget,
    required DateTime nowUtc,
  }) async {
    if (!nowUtc.isUtc || !configuration.valid || !budget.valid) {
      throw const FormatException('Allocation planner configuration is invalid.');
    }

    final orderedInputs = inputs.toList(growable: false);
    final ids = <String>{};
    for (final input in orderedInputs) {
      input.validate();
      if (!ids.add(input.candidate.candidateId.trim())) {
        throw const FormatException(
          'Allocation planner candidate identities must be unique.',
        );
      }
    }

    if (orderedInputs.isEmpty) {
      final decision = PortfolioCapitalAllocator(
        configuration: configuration,
      ).allocate(proposals: const [], budget: budget, nowUtc: nowUtc);
      return PortfolioAllocationPlan(
        decision: decision,
        evidence: PortfolioAllocationEvidenceBuilder.build(
          decision: decision,
          proposals: const [],
        ),
        riskLedgerRevision: 0,
        tradingDayId: '',
      );
    }

    final proposals = <PortfolioAllocationProposal>[];
    PortfolioRiskLedger? commonLedger;
    for (final input in orderedInputs) {
      final preview = await previewRisk(input.candidate);
      final ledger = preview.ledger;
      final baseline = commonLedger;
      if (baseline == null) {
        commonLedger = ledger;
      } else if (baseline.revision != ledger.revision ||
          baseline.tradingDay.value != ledger.tradingDay.value) {
        throw StateError(
          'Portfolio allocation risk truth changed during preview; recompute from one current snapshot.',
        );
      }
      proposals.add(
        PortfolioAllocationProposal(
          utility: input.utility,
          candidate: input.candidate,
          riskDecision: preview.decision,
          evidenceAsOfUtc: input.evidenceAsOfUtc,
        ),
      );
    }

    final ledger = commonLedger!;
    final decision = PortfolioCapitalAllocator(
      configuration: configuration,
    ).allocate(
      proposals: proposals,
      budget: budget,
      nowUtc: nowUtc,
      correlation: PortfolioAllocationCorrelationContext(
        ledger: ledger,
        policy: correlationPolicy,
      ),
    );
    final evidence = PortfolioAllocationEvidenceBuilder.build(
      decision: decision,
      proposals: proposals,
    );
    return PortfolioAllocationPlan(
      decision: decision,
      evidence: evidence,
      riskLedgerRevision: ledger.revision,
      tradingDayId: ledger.tradingDay.value,
    );
  }
}
