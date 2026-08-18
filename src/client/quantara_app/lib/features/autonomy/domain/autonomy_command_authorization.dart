import 'dart:collection';

import 'autonomy_policy_gateway.dart';

final class AutonomyCommandAuthorization {
  AutonomyCommandAuthorization._({
    required this.idempotencyKey,
    required this.clientId,
    required this.policyDecisionId,
    required this.policyVersion,
    required this.mode,
    required this.promotionState,
    required this.canonicalDecisionId,
    required this.riskDecisionId,
    required this.allocationDecisionId,
    required this.authorizedAtUtc,
    required Iterable<String> policyEvidence,
  }) : policyEvidence = UnmodifiableListView(
         policyEvidence.toList(growable: false),
       );

  factory AutonomyCommandAuthorization.fromPolicyDecision({
    required AutonomyPolicyDecision decision,
    required String idempotencyKey,
    required String clientId,
    required String policyDecisionId,
    required String canonicalDecisionId,
    required String riskDecisionId,
    required String allocationDecisionId,
    required DateTime authorizedAtUtc,
  }) {
    if (!decision.authorizes(AutonomyOperation.protectedNewEntry) ||
        decision.blockReason != AutonomyPolicyBlockReason.none) {
      throw StateError(
        'A blocked autonomy decision cannot authorize a live command.',
      );
    }
    final identifiers = [
      idempotencyKey,
      clientId,
      policyDecisionId,
      canonicalDecisionId,
      riskDecisionId,
      allocationDecisionId,
      decision.version,
    ];
    if (identifiers.any((value) => value.trim().isEmpty) ||
        !authorizedAtUtc.isUtc ||
        decision.evidence.any((value) => value.trim().isEmpty)) {
      throw const FormatException(
        'Autonomy command authorization evidence is incomplete.',
      );
    }
    return AutonomyCommandAuthorization._(
      idempotencyKey: idempotencyKey.trim(),
      clientId: clientId.trim(),
      policyDecisionId: policyDecisionId.trim(),
      policyVersion: decision.version.trim(),
      mode: decision.mode,
      promotionState: decision.promotionState,
      canonicalDecisionId: canonicalDecisionId.trim(),
      riskDecisionId: riskDecisionId.trim(),
      allocationDecisionId: allocationDecisionId.trim(),
      authorizedAtUtc: authorizedAtUtc,
      policyEvidence: decision.evidence,
    );
  }

  final String idempotencyKey;
  final String clientId;
  final String policyDecisionId;
  final String policyVersion;
  final AutonomyExecutionMode mode;
  final AutonomyPromotionState promotionState;
  final String canonicalDecisionId;
  final String riskDecisionId;
  final String allocationDecisionId;
  final DateTime authorizedAtUtc;
  final UnmodifiableListView<String> policyEvidence;

  Map<String, Object?> toJson() => {
    'idempotencyKey': idempotencyKey,
    'clientId': clientId,
    'policyDecisionId': policyDecisionId,
    'policyVersion': policyVersion,
    'mode': mode.name,
    'promotionState': promotionState.name,
    'canonicalDecisionId': canonicalDecisionId,
    'riskDecisionId': riskDecisionId,
    'allocationDecisionId': allocationDecisionId,
    'authorizedAtUtc': authorizedAtUtc.toIso8601String(),
    'policyEvidence': policyEvidence.toList(growable: false),
  };
}
