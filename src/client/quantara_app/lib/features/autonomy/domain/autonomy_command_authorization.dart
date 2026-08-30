import 'dart:collection';

import 'autonomy_policy_gateway.dart';

enum AutonomyCommandRuntime { localAndroid, durableService }

final class AutonomyCommandAuthorization {
  AutonomyCommandAuthorization._({
    required this.idempotencyKey,
    required this.clientId,
    required this.policyDecisionId,
    required this.policyVersion,
    required this.mode,
    required this.promotionState,
    required this.runtime,
    required this.canonicalDecisionId,
    required this.riskDecisionId,
    required this.riskDecisionObservedAtUtc,
    required this.allocationDecisionId,
    required this.allocationDecisionObservedAtUtc,
    required this.authorizedAtUtc,
    required Iterable<String> policyEvidence,
  }) : policyEvidence = UnmodifiableListView(
         policyEvidence.toList(growable: false),
       );

  static const defaultDecisionMaxAge = Duration(seconds: 30);

  factory AutonomyCommandAuthorization.fromPolicyDecision({
    required AutonomyPolicyDecision decision,
    required AutonomyCommandRuntime runtime,
    required String idempotencyKey,
    required String clientId,
    required String policyDecisionId,
    required String canonicalDecisionId,
    required String riskDecisionId,
    required DateTime riskDecisionObservedAtUtc,
    required String allocationDecisionId,
    required DateTime allocationDecisionObservedAtUtc,
    required DateTime authorizedAtUtc,
    Duration decisionMaxAge = defaultDecisionMaxAge,
  }) {
    if (!decision.authorizes(AutonomyOperation.protectedNewEntry) ||
        decision.blockReason != AutonomyPolicyBlockReason.none) {
      throw StateError(
        'A blocked autonomy decision cannot authorize a live command.',
      );
    }
    final durableMode =
        decision.mode == AutonomyExecutionMode.cappedAuto ||
        decision.mode == AutonomyExecutionMode.autonomous;
    if (durableMode && runtime != AutonomyCommandRuntime.durableService) {
      throw StateError(
        'Persistent autonomy requires a certified durable service runtime.',
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
        !riskDecisionObservedAtUtc.isUtc ||
        !allocationDecisionObservedAtUtc.isUtc ||
        decisionMaxAge <= Duration.zero ||
        decision.evidence.any((value) => value.trim().isEmpty)) {
      throw const FormatException(
        'Autonomy command authorization evidence is incomplete.',
      );
    }
    _requireCurrentDecision(
      label: 'Risk',
      observedAtUtc: riskDecisionObservedAtUtc,
      authorizedAtUtc: authorizedAtUtc,
      maxAge: decisionMaxAge,
    );
    _requireCurrentDecision(
      label: 'Allocation',
      observedAtUtc: allocationDecisionObservedAtUtc,
      authorizedAtUtc: authorizedAtUtc,
      maxAge: decisionMaxAge,
    );
    return AutonomyCommandAuthorization._(
      idempotencyKey: idempotencyKey.trim(),
      clientId: clientId.trim(),
      policyDecisionId: policyDecisionId.trim(),
      policyVersion: decision.version.trim(),
      mode: decision.mode,
      promotionState: decision.promotionState,
      runtime: runtime,
      canonicalDecisionId: canonicalDecisionId.trim(),
      riskDecisionId: riskDecisionId.trim(),
      riskDecisionObservedAtUtc: riskDecisionObservedAtUtc,
      allocationDecisionId: allocationDecisionId.trim(),
      allocationDecisionObservedAtUtc: allocationDecisionObservedAtUtc,
      authorizedAtUtc: authorizedAtUtc,
      policyEvidence: decision.evidence,
    );
  }

  static void _requireCurrentDecision({
    required String label,
    required DateTime observedAtUtc,
    required DateTime authorizedAtUtc,
    required Duration maxAge,
  }) {
    final age = authorizedAtUtc.difference(observedAtUtc);
    if (age.isNegative || age > maxAge) {
      throw StateError('$label decision evidence is not current.');
    }
  }

  final String idempotencyKey;
  final String clientId;
  final String policyDecisionId;
  final String policyVersion;
  final AutonomyExecutionMode mode;
  final AutonomyPromotionState promotionState;
  final AutonomyCommandRuntime runtime;
  final String canonicalDecisionId;
  final String riskDecisionId;
  final DateTime riskDecisionObservedAtUtc;
  final String allocationDecisionId;
  final DateTime allocationDecisionObservedAtUtc;
  final DateTime authorizedAtUtc;
  final UnmodifiableListView<String> policyEvidence;

  Map<String, Object?> toJson() => {
    'idempotencyKey': idempotencyKey,
    'clientId': clientId,
    'policyDecisionId': policyDecisionId,
    'policyVersion': policyVersion,
    'mode': mode.name,
    'promotionState': promotionState.name,
    'runtime': runtime.name,
    'canonicalDecisionId': canonicalDecisionId,
    'riskDecisionId': riskDecisionId,
    'riskDecisionObservedAtUtc': riskDecisionObservedAtUtc.toIso8601String(),
    'allocationDecisionId': allocationDecisionId,
    'allocationDecisionObservedAtUtc': allocationDecisionObservedAtUtc
        .toIso8601String(),
    'authorizedAtUtc': authorizedAtUtc.toIso8601String(),
    'policyEvidence': policyEvidence.toList(growable: false),
  };
}
