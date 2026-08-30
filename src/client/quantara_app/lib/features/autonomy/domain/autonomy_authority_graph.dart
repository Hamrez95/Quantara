enum AutonomyAuthorityStage {
  marketStrategyEvidence,
  versionedTradeIntent,
  economicRanking,
  riskEngine,
  portfolioAllocator,
  autonomyPolicyGateway,
  typedExchangeExecutor,
  exchangeMutation,
  aiAdvisoryEvidence,
  userApprovalEvidence,
  auditJournal,
}

enum AutonomyAuthorityEdgeKind { authority, advisory, audit }

final class AutonomyAuthorityEdge {
  const AutonomyAuthorityEdge({
    required this.from,
    required this.to,
    required this.kind,
  });

  final AutonomyAuthorityStage from;
  final AutonomyAuthorityStage to;
  final AutonomyAuthorityEdgeKind kind;
}

abstract final class AutonomyAuthorityGraph {
  static const requiredAuthorityChain = <AutonomyAuthorityStage>[
    AutonomyAuthorityStage.marketStrategyEvidence,
    AutonomyAuthorityStage.versionedTradeIntent,
    AutonomyAuthorityStage.economicRanking,
    AutonomyAuthorityStage.riskEngine,
    AutonomyAuthorityStage.portfolioAllocator,
    AutonomyAuthorityStage.autonomyPolicyGateway,
    AutonomyAuthorityStage.typedExchangeExecutor,
    AutonomyAuthorityStage.exchangeMutation,
  ];

  static const edges = <AutonomyAuthorityEdge>[
    AutonomyAuthorityEdge(
      from: AutonomyAuthorityStage.marketStrategyEvidence,
      to: AutonomyAuthorityStage.versionedTradeIntent,
      kind: AutonomyAuthorityEdgeKind.authority,
    ),
    AutonomyAuthorityEdge(
      from: AutonomyAuthorityStage.versionedTradeIntent,
      to: AutonomyAuthorityStage.economicRanking,
      kind: AutonomyAuthorityEdgeKind.authority,
    ),
    AutonomyAuthorityEdge(
      from: AutonomyAuthorityStage.economicRanking,
      to: AutonomyAuthorityStage.riskEngine,
      kind: AutonomyAuthorityEdgeKind.authority,
    ),
    AutonomyAuthorityEdge(
      from: AutonomyAuthorityStage.riskEngine,
      to: AutonomyAuthorityStage.portfolioAllocator,
      kind: AutonomyAuthorityEdgeKind.authority,
    ),
    AutonomyAuthorityEdge(
      from: AutonomyAuthorityStage.portfolioAllocator,
      to: AutonomyAuthorityStage.autonomyPolicyGateway,
      kind: AutonomyAuthorityEdgeKind.authority,
    ),
    AutonomyAuthorityEdge(
      from: AutonomyAuthorityStage.autonomyPolicyGateway,
      to: AutonomyAuthorityStage.typedExchangeExecutor,
      kind: AutonomyAuthorityEdgeKind.authority,
    ),
    AutonomyAuthorityEdge(
      from: AutonomyAuthorityStage.typedExchangeExecutor,
      to: AutonomyAuthorityStage.exchangeMutation,
      kind: AutonomyAuthorityEdgeKind.authority,
    ),
    AutonomyAuthorityEdge(
      from: AutonomyAuthorityStage.aiAdvisoryEvidence,
      to: AutonomyAuthorityStage.marketStrategyEvidence,
      kind: AutonomyAuthorityEdgeKind.advisory,
    ),
    AutonomyAuthorityEdge(
      from: AutonomyAuthorityStage.userApprovalEvidence,
      to: AutonomyAuthorityStage.autonomyPolicyGateway,
      kind: AutonomyAuthorityEdgeKind.advisory,
    ),
    AutonomyAuthorityEdge(
      from: AutonomyAuthorityStage.autonomyPolicyGateway,
      to: AutonomyAuthorityStage.auditJournal,
      kind: AutonomyAuthorityEdgeKind.audit,
    ),
    AutonomyAuthorityEdge(
      from: AutonomyAuthorityStage.typedExchangeExecutor,
      to: AutonomyAuthorityStage.auditJournal,
      kind: AutonomyAuthorityEdgeKind.audit,
    ),
  ];

  static void validate() => validateEdges(edges);

  static void validateEdges(Iterable<AutonomyAuthorityEdge> candidateEdges) {
    final allEdges = candidateEdges.toList(growable: false);
    final authorityEdges = allEdges
        .where((edge) => edge.kind == AutonomyAuthorityEdgeKind.authority)
        .toList(growable: false);

    for (var index = 0; index < requiredAuthorityChain.length - 1; index++) {
      final from = requiredAuthorityChain[index];
      final expectedTo = requiredAuthorityChain[index + 1];
      final outgoing = authorityEdges
          .where((edge) => edge.from == from)
          .toList(growable: false);
      if (outgoing.length != 1 || outgoing.single.to != expectedTo) {
        throw StateError(
          'Autonomy authority graph must preserve every required policy stage.',
        );
      }
    }

    final exchangeIncoming = authorityEdges
        .where((edge) => edge.to == AutonomyAuthorityStage.exchangeMutation)
        .toList(growable: false);
    if (exchangeIncoming.length != 1 ||
        exchangeIncoming.single.from !=
            AutonomyAuthorityStage.typedExchangeExecutor) {
      throw StateError(
        'Only the typed exchange executor may carry mutation authority.',
      );
    }

    const nonAuthoritySources = <AutonomyAuthorityStage>{
      AutonomyAuthorityStage.aiAdvisoryEvidence,
      AutonomyAuthorityStage.userApprovalEvidence,
      AutonomyAuthorityStage.auditJournal,
    };
    if (authorityEdges.any((edge) => nonAuthoritySources.contains(edge.from))) {
      throw StateError(
        'Advisory, UI approval, and audit nodes cannot carry mutation authority.',
      );
    }

    if (authorityEdges.any(
      (edge) => edge.from == AutonomyAuthorityStage.exchangeMutation,
    )) {
      throw StateError('Exchange mutation must be a terminal authority node.');
    }
  }

  static bool carriesMutationAuthority(AutonomyAuthorityStage stage) =>
      edges.any(
        (edge) =>
            edge.kind == AutonomyAuthorityEdgeKind.authority &&
            edge.from == stage,
      );
}
