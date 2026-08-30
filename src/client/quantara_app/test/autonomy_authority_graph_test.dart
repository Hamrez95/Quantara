import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/autonomy/domain/autonomy_authority_graph.dart';

void main() {
  test('canonical authority graph preserves the full mutation chain', () {
    expect(AutonomyAuthorityGraph.validate, returnsNormally);
    expect(AutonomyAuthorityGraph.requiredAuthorityChain, const [
      AutonomyAuthorityStage.marketStrategyEvidence,
      AutonomyAuthorityStage.versionedTradeIntent,
      AutonomyAuthorityStage.economicRanking,
      AutonomyAuthorityStage.riskEngine,
      AutonomyAuthorityStage.portfolioAllocator,
      AutonomyAuthorityStage.autonomyPolicyGateway,
      AutonomyAuthorityStage.typedExchangeExecutor,
      AutonomyAuthorityStage.exchangeMutation,
    ]);
  });

  test('AI advisory and user approval never carry mutation authority', () {
    expect(
      AutonomyAuthorityGraph.carriesMutationAuthority(
        AutonomyAuthorityStage.aiAdvisoryEvidence,
      ),
      isFalse,
    );
    expect(
      AutonomyAuthorityGraph.carriesMutationAuthority(
        AutonomyAuthorityStage.userApprovalEvidence,
      ),
      isFalse,
    );
  });

  test('direct AI to executor authority is rejected', () {
    final malformed = [
      ...AutonomyAuthorityGraph.edges,
      const AutonomyAuthorityEdge(
        from: AutonomyAuthorityStage.aiAdvisoryEvidence,
        to: AutonomyAuthorityStage.typedExchangeExecutor,
        kind: AutonomyAuthorityEdgeKind.authority,
      ),
    ];

    expect(
      () => AutonomyAuthorityGraph.validateEdges(malformed),
      throwsStateError,
    );
  });

  test('skipping Risk Engine is rejected even if later gates remain', () {
    final malformed =
        AutonomyAuthorityGraph.edges
            .where(
              (edge) =>
                  !(edge.kind == AutonomyAuthorityEdgeKind.authority &&
                      edge.from == AutonomyAuthorityStage.economicRanking),
            )
            .toList()
          ..add(
            const AutonomyAuthorityEdge(
              from: AutonomyAuthorityStage.economicRanking,
              to: AutonomyAuthorityStage.portfolioAllocator,
              kind: AutonomyAuthorityEdgeKind.authority,
            ),
          );

    expect(
      () => AutonomyAuthorityGraph.validateEdges(malformed),
      throwsStateError,
    );
  });

  test(
    'only typed executor can be the authority edge into exchange mutation',
    () {
      final malformed =
          AutonomyAuthorityGraph.edges
              .where(
                (edge) =>
                    !(edge.kind == AutonomyAuthorityEdgeKind.authority &&
                        edge.to == AutonomyAuthorityStage.exchangeMutation),
              )
              .toList()
            ..add(
              const AutonomyAuthorityEdge(
                from: AutonomyAuthorityStage.autonomyPolicyGateway,
                to: AutonomyAuthorityStage.exchangeMutation,
                kind: AutonomyAuthorityEdgeKind.authority,
              ),
            );

      expect(
        () => AutonomyAuthorityGraph.validateEdges(malformed),
        throwsStateError,
      );
    },
  );
}
