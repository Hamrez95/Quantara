import 'dart:collection';

import 'portfolio_capital_allocator.dart';

final class PortfolioAllocationEvidenceItem {
  const PortfolioAllocationEvidenceItem({
    required this.proposalId,
    required this.symbol,
    required this.evidenceAsOfUtc,
    required this.utilityScore,
    required this.reason,
    required this.selected,
  });

  final String proposalId;
  final String symbol;
  final DateTime evidenceAsOfUtc;
  final double utilityScore;
  final PortfolioAllocationReason reason;
  final bool selected;

  Map<String, Object?> toJson() => {
    'proposalId': proposalId,
    'symbol': symbol,
    'evidenceAsOfUtc': evidenceAsOfUtc.toIso8601String(),
    'utilityScore': utilityScore,
    'reason': reason.name,
    'selected': selected,
  };
}

final class PortfolioAllocationEvidenceSnapshot {
  PortfolioAllocationEvidenceSnapshot({
    required this.allocatorVersion,
    required this.generatedAtUtc,
    required Iterable<String> rankedProposalIds,
    required Iterable<PortfolioAllocationEvidenceItem> items,
  }) : rankedProposalIds = UnmodifiableListView(
         rankedProposalIds.toList(growable: false),
       ),
       items = UnmodifiableListView(items.toList(growable: false));

  final String allocatorVersion;
  final DateTime generatedAtUtc;
  final UnmodifiableListView<String> rankedProposalIds;
  final UnmodifiableListView<PortfolioAllocationEvidenceItem> items;

  List<String> get selectedProposalIds => List.unmodifiable(
    items.where((item) => item.selected).map((item) => item.proposalId),
  );

  Map<String, Object?> toJson() => {
    'allocatorVersion': allocatorVersion,
    'generatedAtUtc': generatedAtUtc.toIso8601String(),
    'rankedProposalIds': rankedProposalIds.toList(growable: false),
    'items': items.map((item) => item.toJson()).toList(growable: false),
  };
}

abstract final class PortfolioAllocationEvidenceBuilder {
  static PortfolioAllocationEvidenceSnapshot build({
    required PortfolioAllocationDecision decision,
    required Iterable<PortfolioAllocationProposal> proposals,
  }) {
    if (decision.version.trim().isEmpty || !decision.generatedAtUtc.isUtc) {
      throw const FormatException('Allocation decision identity is invalid.');
    }

    final proposalById = <String, PortfolioAllocationProposal>{};
    for (final proposal in proposals) {
      final id = proposal.id.trim();
      if (id.isEmpty || proposalById.containsKey(id)) {
        throw const FormatException(
          'Allocation evidence proposals must have unique non-empty IDs.',
        );
      }
      if (!proposal.evidenceAsOfUtc.isUtc) {
        throw const FormatException(
          'Allocation evidence timestamps must be UTC.',
        );
      }
      proposalById[id] = proposal;
    }

    final evidenceItems = <PortfolioAllocationEvidenceItem>[];
    final rankedIds = <String>[];
    final decisionIds = <String>{};
    for (final item in decision.items) {
      final proposalId = item.proposalId.trim();
      final proposal = proposalById[proposalId];
      if (proposal == null) {
        throw StateError(
          'Allocation decision references a proposal without evidence.',
        );
      }
      if (!decisionIds.add(proposalId)) {
        throw StateError(
          'Allocation decision references the same proposal more than once.',
        );
      }
      if (item.symbol.trim().toUpperCase() !=
          proposal.symbol.trim().toUpperCase()) {
        throw StateError(
          'Allocation decision symbol does not match proposal evidence.',
        );
      }
      rankedIds.add(proposalId);
      evidenceItems.add(
        PortfolioAllocationEvidenceItem(
          proposalId: proposalId,
          symbol: item.symbol,
          evidenceAsOfUtc: proposal.evidenceAsOfUtc,
          utilityScore: item.utilityScore,
          reason: item.reason,
          selected: item.selected,
        ),
      );
    }

    if (decisionIds.length != proposalById.length ||
        !decisionIds.containsAll(proposalById.keys)) {
      throw StateError(
        'Allocation evidence must cover every considered proposal exactly once.',
      );
    }

    return PortfolioAllocationEvidenceSnapshot(
      allocatorVersion: decision.version,
      generatedAtUtc: decision.generatedAtUtc,
      rankedProposalIds: rankedIds,
      items: evidenceItems,
    );
  }
}
