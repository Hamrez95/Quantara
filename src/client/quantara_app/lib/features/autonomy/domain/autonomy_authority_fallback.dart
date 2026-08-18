import 'autonomy_policy_gateway.dart';

enum AutonomyEffectiveAuthority {
  observeOnly,
  reduceOnly,
  approvalRequired,
  guardedAuto,
  cappedAuto,
  autonomous,
}

enum AutonomyFallbackClass {
  none,
  runtimeSafety,
  promotion,
  certification,
  identity,
  infrastructure,
}

final class AutonomyAuthoritySnapshot {
  const AutonomyAuthoritySnapshot({
    required this.requestedMode,
    required this.effectiveAuthority,
    required this.fallbackClass,
    required this.blockReason,
    required this.newEntryAuthorized,
    required this.reduceOnlyManagementAuthorized,
  });

  final AutonomyExecutionMode requestedMode;
  final AutonomyEffectiveAuthority effectiveAuthority;
  final AutonomyFallbackClass fallbackClass;
  final AutonomyPolicyBlockReason blockReason;
  final bool newEntryAuthorized;
  final bool reduceOnlyManagementAuthorized;

  bool get automaticallyFellBack => fallbackClass != AutonomyFallbackClass.none;

  Map<String, Object?> toJson() => {
    'requestedMode': requestedMode.name,
    'effectiveAuthority': effectiveAuthority.name,
    'fallbackClass': fallbackClass.name,
    'blockReason': blockReason.name,
    'newEntryAuthorized': newEntryAuthorized,
    'reduceOnlyManagementAuthorized': reduceOnlyManagementAuthorized,
  };
}

/// Converts a policy decision into the authority that is actually usable now.
///
/// This is intentionally pure and contains no executor, network or persistence
/// behavior. A runtime/certification failure can only reduce authority: managed
/// exposure remains reduce-only, while a session with no managed exposure falls
/// back to observation only.
final class AutonomyAuthorityResolver {
  const AutonomyAuthorityResolver();

  AutonomyAuthoritySnapshot resolve(AutonomyPolicyDecision decision) {
    final fallbackClass = _fallbackClass(decision.blockReason);
    return AutonomyAuthoritySnapshot(
      requestedMode: decision.mode,
      effectiveAuthority: _effectiveAuthority(decision),
      fallbackClass: fallbackClass,
      blockReason: decision.blockReason,
      newEntryAuthorized: decision.newEntryAuthorized,
      reduceOnlyManagementAuthorized: decision.reduceOnlyManagementAuthorized,
    );
  }

  AutonomyEffectiveAuthority _effectiveAuthority(
    AutonomyPolicyDecision decision,
  ) {
    if (!decision.newEntryAuthorized) {
      return decision.reduceOnlyManagementAuthorized
          ? AutonomyEffectiveAuthority.reduceOnly
          : AutonomyEffectiveAuthority.observeOnly;
    }

    return switch (decision.mode) {
      AutonomyExecutionMode.readOnly => AutonomyEffectiveAuthority.observeOnly,
      AutonomyExecutionMode.approvalRequired =>
        AutonomyEffectiveAuthority.approvalRequired,
      AutonomyExecutionMode.guardedAuto =>
        AutonomyEffectiveAuthority.guardedAuto,
      AutonomyExecutionMode.cappedAuto => AutonomyEffectiveAuthority.cappedAuto,
      AutonomyExecutionMode.autonomous => AutonomyEffectiveAuthority.autonomous,
    };
  }

  AutonomyFallbackClass _fallbackClass(AutonomyPolicyBlockReason reason) {
    return switch (reason) {
      AutonomyPolicyBlockReason.marketTruthUnhealthy ||
      AutonomyPolicyBlockReason.privateTruthUnhealthy ||
      AutonomyPolicyBlockReason.protectionUnhealthy ||
      AutonomyPolicyBlockReason.riskAccountMismatch ||
      AutonomyPolicyBlockReason.riskBreakerTripped ||
      AutonomyPolicyBlockReason.executionQualityUnhealthy ||
      AutonomyPolicyBlockReason.strategyDriftUnhealthy ||
      AutonomyPolicyBlockReason.criticalHealthUnhealthy =>
        AutonomyFallbackClass.runtimeSafety,
      AutonomyPolicyBlockReason.promotionSuspended ||
      AutonomyPolicyBlockReason.promotionInsufficient =>
        AutonomyFallbackClass.promotion,
      AutonomyPolicyBlockReason.strategyEvidenceMissing ||
      AutonomyPolicyBlockReason.faultCertificationMissing =>
        AutonomyFallbackClass.certification,
      AutonomyPolicyBlockReason.buildIdentityUnapproved ||
      AutonomyPolicyBlockReason.strategyIdentityUnapproved =>
        AutonomyFallbackClass.identity,
      AutonomyPolicyBlockReason.capitalRiskCapsMissing ||
      AutonomyPolicyBlockReason.durableWorkerUncertified ||
      AutonomyPolicyBlockReason.persistentCredentialBoundaryUnready =>
        AutonomyFallbackClass.infrastructure,
      AutonomyPolicyBlockReason.none ||
      AutonomyPolicyBlockReason.readOnlyMode ||
      AutonomyPolicyBlockReason.canonicalDecisionRejected ||
      AutonomyPolicyBlockReason.riskDecisionRejected ||
      AutonomyPolicyBlockReason.allocationDecisionRejected ||
      AutonomyPolicyBlockReason.userApprovalRequired ||
      AutonomyPolicyBlockReason.explicitSessionRequired =>
        AutonomyFallbackClass.none,
    };
  }
}
