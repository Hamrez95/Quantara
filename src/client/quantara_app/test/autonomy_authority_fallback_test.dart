import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/autonomy/domain/autonomy_authority_fallback.dart';
import 'package:quantara_app/features/autonomy/domain/autonomy_policy_gateway.dart';

void main() {
  const gateway = AutonomyPolicyGateway();
  const resolver = AutonomyAuthorityResolver();

  AutonomyPolicyInput input({
    AutonomyExecutionMode mode = AutonomyExecutionMode.guardedAuto,
    AutonomyPromotionState promotionState =
        AutonomyPromotionState.paperEligible,
    bool canonicalDecisionEligible = true,
    bool riskDecisionAllowed = true,
    bool allocationSelected = true,
    bool marketTruthHealthy = true,
    bool privateTruthHealthy = true,
    bool protectionHealthy = true,
    bool riskAccountConsistent = true,
    bool riskBreakersClear = true,
    bool executionQualityHealthy = true,
    bool strategyDriftHealthy = true,
    bool criticalHealthClear = true,
    bool userApproved = false,
    bool explicitSessionStarted = true,
    bool strategyEvidenceApproved = false,
    bool faultCertificationCurrent = false,
    bool buildIdentityApproved = false,
    bool strategyIdentityApproved = false,
    bool capitalRiskCapsConfigured = false,
    bool durableWorkerCertified = false,
    bool persistentCredentialBoundaryReady = false,
    bool hasManagedExposure = false,
  }) => AutonomyPolicyInput(
    mode: mode,
    promotionState: promotionState,
    canonicalDecisionEligible: canonicalDecisionEligible,
    riskDecisionAllowed: riskDecisionAllowed,
    allocationSelected: allocationSelected,
    marketTruthHealthy: marketTruthHealthy,
    privateTruthHealthy: privateTruthHealthy,
    protectionHealthy: protectionHealthy,
    riskAccountConsistent: riskAccountConsistent,
    riskBreakersClear: riskBreakersClear,
    executionQualityHealthy: executionQualityHealthy,
    strategyDriftHealthy: strategyDriftHealthy,
    criticalHealthClear: criticalHealthClear,
    userApproved: userApproved,
    explicitSessionStarted: explicitSessionStarted,
    strategyEvidenceApproved: strategyEvidenceApproved,
    faultCertificationCurrent: faultCertificationCurrent,
    buildIdentityApproved: buildIdentityApproved,
    strategyIdentityApproved: strategyIdentityApproved,
    capitalRiskCapsConfigured: capitalRiskCapsConfigured,
    durableWorkerCertified: durableWorkerCertified,
    persistentCredentialBoundaryReady: persistentCredentialBoundaryReady,
    hasManagedExposure: hasManagedExposure,
  );

  AutonomyPolicyInput durableInput({
    AutonomyExecutionMode mode = AutonomyExecutionMode.cappedAuto,
    AutonomyPromotionState promotionState =
        AutonomyPromotionState.cappedCanaryEligible,
    bool faultCertificationCurrent = true,
    bool buildIdentityApproved = true,
    bool hasManagedExposure = false,
  }) => input(
    mode: mode,
    promotionState: promotionState,
    strategyEvidenceApproved: true,
    faultCertificationCurrent: faultCertificationCurrent,
    buildIdentityApproved: buildIdentityApproved,
    strategyIdentityApproved: true,
    capitalRiskCapsConfigured: true,
    durableWorkerCertified: true,
    persistentCredentialBoundaryReady: true,
    hasManagedExposure: hasManagedExposure,
  );

  AutonomyAuthoritySnapshot resolve(AutonomyPolicyInput value) =>
      resolver.resolve(gateway.evaluate(value));

  test('healthy guarded session retains guarded-auto authority', () {
    final snapshot = resolve(input());

    expect(snapshot.effectiveAuthority, AutonomyEffectiveAuthority.guardedAuto);
    expect(snapshot.fallbackClass, AutonomyFallbackClass.none);
    expect(snapshot.automaticallyFellBack, isFalse);
    expect(snapshot.newEntryAuthorized, isTrue);
  });

  test('runtime truth failure falls back to reduce-only with exposure', () {
    final snapshot = resolve(
      input(privateTruthHealthy: false, hasManagedExposure: true),
    );

    expect(
      snapshot.blockReason,
      AutonomyPolicyBlockReason.privateTruthUnhealthy,
    );
    expect(snapshot.effectiveAuthority, AutonomyEffectiveAuthority.reduceOnly);
    expect(snapshot.fallbackClass, AutonomyFallbackClass.runtimeSafety);
    expect(snapshot.automaticallyFellBack, isTrue);
    expect(snapshot.newEntryAuthorized, isFalse);
    expect(snapshot.reduceOnlyManagementAuthorized, isTrue);
  });

  test('execution degradation falls back to observe-only without exposure', () {
    final snapshot = resolve(input(executionQualityHealthy: false));

    expect(
      snapshot.blockReason,
      AutonomyPolicyBlockReason.executionQualityUnhealthy,
    );
    expect(snapshot.effectiveAuthority, AutonomyEffectiveAuthority.observeOnly);
    expect(snapshot.fallbackClass, AutonomyFallbackClass.runtimeSafety);
  });

  test(
    'expired capped certification is an automatic certification fallback',
    () {
      final snapshot = resolve(durableInput(faultCertificationCurrent: false));

      expect(
        snapshot.blockReason,
        AutonomyPolicyBlockReason.faultCertificationMissing,
      );
      expect(
        snapshot.effectiveAuthority,
        AutonomyEffectiveAuthority.observeOnly,
      );
      expect(snapshot.fallbackClass, AutonomyFallbackClass.certification);
    },
  );

  test('unapproved autonomous build keeps managed exposure reduce-only', () {
    final snapshot = resolve(
      durableInput(
        mode: AutonomyExecutionMode.autonomous,
        promotionState: AutonomyPromotionState.autonomousEligible,
        buildIdentityApproved: false,
        hasManagedExposure: true,
      ),
    );

    expect(
      snapshot.blockReason,
      AutonomyPolicyBlockReason.buildIdentityUnapproved,
    );
    expect(snapshot.effectiveAuthority, AutonomyEffectiveAuthority.reduceOnly);
    expect(snapshot.fallbackClass, AutonomyFallbackClass.identity);
  });

  test(
    'pending approval is not mislabeled as an automatic safety fallback',
    () {
      final snapshot = resolve(
        input(
          mode: AutonomyExecutionMode.approvalRequired,
          explicitSessionStarted: false,
        ),
      );

      expect(
        snapshot.blockReason,
        AutonomyPolicyBlockReason.userApprovalRequired,
      );
      expect(
        snapshot.effectiveAuthority,
        AutonomyEffectiveAuthority.observeOnly,
      );
      expect(snapshot.fallbackClass, AutonomyFallbackClass.none);
      expect(snapshot.automaticallyFellBack, isFalse);
    },
  );

  test('per-trade risk rejection does not masquerade as mode degradation', () {
    final snapshot = resolve(input(riskDecisionAllowed: false));

    expect(
      snapshot.blockReason,
      AutonomyPolicyBlockReason.riskDecisionRejected,
    );
    expect(snapshot.effectiveAuthority, AutonomyEffectiveAuthority.observeOnly);
    expect(snapshot.fallbackClass, AutonomyFallbackClass.none);
  });

  test('snapshot is machine-readable for audit and supervisor evidence', () {
    final snapshot = resolve(
      input(strategyDriftHealthy: false, hasManagedExposure: true),
    );

    expect(snapshot.toJson(), {
      'requestedMode': 'guardedAuto',
      'effectiveAuthority': 'reduceOnly',
      'fallbackClass': 'runtimeSafety',
      'blockReason': 'strategyDriftUnhealthy',
      'newEntryAuthorized': false,
      'reduceOnlyManagementAuthorized': true,
    });
  });
}
