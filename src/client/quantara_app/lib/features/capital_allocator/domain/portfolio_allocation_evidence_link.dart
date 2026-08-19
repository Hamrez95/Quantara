import '../../ai_supervisor/domain/supervisor_system_evidence.dart';
import 'portfolio_capital_allocator.dart';

final class PortfolioAllocationEvidenceLink {
  const PortfolioAllocationEvidenceLink({
    required this.proposalId,
    required this.journalTradeId,
    required this.supervisorEvidenceId,
    required this.supervisorCorrelationId,
    required this.utilityFingerprint,
    required this.supervisorObservedAtUtc,
    required this.proposalEvidenceAsOfUtc,
  });

  final String proposalId;
  final String journalTradeId;
  final String supervisorEvidenceId;
  final String supervisorCorrelationId;
  final String utilityFingerprint;
  final DateTime supervisorObservedAtUtc;
  final DateTime proposalEvidenceAsOfUtc;

  Map<String, Object?> toJson() => {
    'proposalId': proposalId,
    'journalTradeId': journalTradeId,
    'supervisorEvidenceId': supervisorEvidenceId,
    'supervisorCorrelationId': supervisorCorrelationId,
    'utilityFingerprint': utilityFingerprint,
    'supervisorObservedAtUtc': supervisorObservedAtUtc.toIso8601String(),
    'proposalEvidenceAsOfUtc': proposalEvidenceAsOfUtc.toIso8601String(),
  };
}

abstract final class PortfolioAllocationEvidenceLinkBuilder {
  static PortfolioAllocationEvidenceLink build({
    required PortfolioAllocationProposal proposal,
    required SupervisorSystemEvidence supervisorEvidence,
    required DateTime allocationAtUtc,
  }) {
    final proposalId = proposal.id.trim();
    final journalTradeId = proposal.candidate.journalTradeId.trim();
    final supervisorEvidenceId = supervisorEvidence.evidenceId.trim();
    final supervisorCorrelationId =
        supervisorEvidence.correlationId?.trim() ?? '';
    final utilityFingerprint = proposal.utility.fingerprint.trim();
    final supervisorObservedAtUtc = supervisorEvidence.observedAtUtc.toUtc();
    final proposalEvidenceAsOfUtc = proposal.evidenceAsOfUtc.toUtc();

    if (!allocationAtUtc.isUtc ||
        proposalId.isEmpty ||
        journalTradeId.isEmpty ||
        supervisorEvidenceId.isEmpty ||
        supervisorCorrelationId.isEmpty ||
        utilityFingerprint.isEmpty ||
        !supervisorEvidence.observedAtUtc.isUtc ||
        !proposal.evidenceAsOfUtc.isUtc ||
        supervisorCorrelationId != journalTradeId ||
        supervisorObservedAtUtc.isAfter(allocationAtUtc) ||
        proposalEvidenceAsOfUtc.isAfter(allocationAtUtc)) {
      throw const FormatException(
        'Allocation evidence must bind one current Journal trade to canonical Supervisor evidence.',
      );
    }

    return PortfolioAllocationEvidenceLink(
      proposalId: proposalId,
      journalTradeId: journalTradeId,
      supervisorEvidenceId: supervisorEvidenceId,
      supervisorCorrelationId: supervisorCorrelationId,
      utilityFingerprint: utilityFingerprint,
      supervisorObservedAtUtc: supervisorObservedAtUtc,
      proposalEvidenceAsOfUtc: proposalEvidenceAsOfUtc,
    );
  }
}
