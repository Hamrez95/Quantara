import '../../ai_supervisor/domain/supervisor_system_evidence.dart';
import '../../decision_core/domain/economic_opportunity_models.dart';
import '../../portfolio_risk/application/portfolio_risk_coordinator.dart';
import '../../portfolio_risk/domain/portfolio_correlation_policy.dart';
import '../../portfolio_risk/domain/portfolio_risk_models.dart';
import '../domain/portfolio_allocation_evidence.dart';
import '../domain/portfolio_allocation_evidence_link.dart';
import '../domain/portfolio_capital_allocator.dart';

typedef PortfolioAllocationRiskPreview =
    Future<PortfolioReservationOutcome> Function(
      PortfolioEntryCandidate candidate,
    );

final class PortfolioAllocationPlannerInput {
  const PortfolioAllocationPlannerInput({
    required this.utility,
    required this.candidate,
    required this.evidenceAsOfUtc,
    required this.supervisorEvidence,
  });

  final OpportunityUtility utility;
  final PortfolioEntryCandidate candidate;
  final DateTime evidenceAsOfUtc;
  final SupervisorSystemEvidence supervisorEvidence;

  void validate() {
    final journalTradeId = candidate.journalTradeId.trim();
    final supervisorEvidenceId = supervisorEvidence.evidenceId.trim();
    final supervisorCorrelationId =
        supervisorEvidence.correlationId?.trim() ?? '';
    if (!evidenceAsOfUtc.isUtc ||
        utility.setupId.trim().isEmpty ||
        utility.setupId.trim() != candidate.candidateId.trim() ||
        journalTradeId.isEmpty ||
        supervisorEvidenceId.isEmpty ||
        supervisorCorrelationId != journalTradeId ||
        !supervisorEvidence.observedAtUtc.isUtc) {
      throw const FormatException(
        'Allocation planner input must bind utility, Journal and Supervisor evidence identity.',
      );
    }
  }
}

final class PortfolioAllocationPlan {
  PortfolioAllocationPlan({
    required this.decision,
    required this.evidence,
    required Iterable<PortfolioAllocationEvidenceLink> evidenceLinks,
    required this.riskLedgerRevision,
    required this.tradingDayId,
  }) : evidenceLinks = List.unmodifiable(evidenceLinks);

  final PortfolioAllocationDecision decision;
  final PortfolioAllocationEvidenceSnapshot evidence;
  final List<PortfolioAllocationEvidenceLink> evidenceLinks;
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
      throw const FormatException(
        'Allocation planner configuration is invalid.',
      );
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
        evidenceLinks: const [],
        riskLedgerRevision: 0,
        tradingDayId: '',
      );
    }

    final proposals = <PortfolioAllocationProposal>[];
    final evidenceLinkByProposalId =
        <String, PortfolioAllocationEvidenceLink>{};
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
      final proposal = PortfolioAllocationProposal(
        utility: input.utility,
        candidate: input.candidate,
        riskDecision: preview.decision,
        evidenceAsOfUtc: input.evidenceAsOfUtc,
      );
      proposals.add(proposal);
      evidenceLinkByProposalId[proposal.id] =
          PortfolioAllocationEvidenceLinkBuilder.build(
            proposal: proposal,
            supervisorEvidence: input.supervisorEvidence,
            allocationAtUtc: nowUtc,
          );
    }

    final ledger = commonLedger!;
    final decision = PortfolioCapitalAllocator(configuration: configuration)
        .allocate(
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
    final evidenceLinks = decision.items
        .map((item) {
          final link = evidenceLinkByProposalId[item.proposalId];
          if (link == null) {
            throw StateError(
              'Allocation decision is missing its Journal/Supervisor evidence link.',
            );
          }
          return link;
        })
        .toList(growable: false);
    if (evidenceLinks.length != evidenceLinkByProposalId.length) {
      throw StateError(
        'Allocation evidence links must cover every considered proposal exactly once.',
      );
    }
    return PortfolioAllocationPlan(
      decision: decision,
      evidence: evidence,
      evidenceLinks: evidenceLinks,
      riskLedgerRevision: ledger.revision,
      tradingDayId: ledger.tradingDay.value,
    );
  }
}
