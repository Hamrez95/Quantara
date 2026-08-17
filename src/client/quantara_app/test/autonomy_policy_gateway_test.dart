import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/autonomy/domain/autonomy_policy_gateway.dart';

void main() {
  const gateway = AutonomyPolicyGateway();

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
  }) => input(
    mode: mode,
    promotionState: promotionState,
    strategyEvidenceApproved: true,
    faultCertificationCurrent: true,
    buildIdentityApproved: true,
    strategyIdentityApproved: true,
    capitalRiskCapsConfigured: true,
    durableWorkerCertified: true,
    persistentCredentialBoundaryReady: true,
  );

  test('capability matrix keeps authority explicit per mode', () {
    final readOnly =
        AutonomyPolicyGateway.capabilityMatrix[AutonomyExecutionMode.readOnly]!;
    final approval = AutonomyPolicyGateway
        .capabilityMatrix[AutonomyExecutionMode.approvalRequired]!;
    final guarded = AutonomyPolicyGateway
        .capabilityMatrix[AutonomyExecutionMode.guardedAuto]!;
    final capped = AutonomyPolicyGateway
        .capabilityMatrix[AutonomyExecutionMode.cappedAuto]!;
    final autonomous = AutonomyPolicyGateway
        .capabilityMatrix[AutonomyExecutionMode.autonomous]!;

    expect(readOnly.canRequestEntry, isFalse);
    expect(readOnly.canAutoSubmitEntry, isFalse);
    expect(approval.requiresUserApproval, isTrue);
    expect(approval.canAutoSubmitEntry, isFalse);
    expect(guarded.requiresExplicitSession, isTrue);
    expect(guarded.requiresDurableWorker, isFalse);
    expect(capped.requiresDurableWorker, isTrue);
    expect(autonomous.requiresDurableWorker, isTrue);
  });

  test('read-only mode never authorizes a new entry', () {
    final decision = gateway.evaluate(
      input(mode: AutonomyExecutionMode.readOnly),
    );

    expect(decision.newEntryAuthorized, isFalse);
    expect(decision.blockReason, AutonomyPolicyBlockReason.readOnlyMode);
    expect(decision.authorizes(AutonomyOperation.observe), isTrue);
    expect(decision.authorizes(AutonomyOperation.protectedNewEntry), isFalse);
  });

  test('approval-required needs explicit approval after common gates', () {
    final blocked = gateway.evaluate(
      input(
        mode: AutonomyExecutionMode.approvalRequired,
        explicitSessionStarted: false,
      ),
    );
    final approved = gateway.evaluate(
      input(
        mode: AutonomyExecutionMode.approvalRequired,
        userApproved: true,
        explicitSessionStarted: false,
      ),
    );

    expect(blocked.blockReason, AutonomyPolicyBlockReason.userApprovalRequired);
    expect(approved.newEntryAuthorized, isTrue);
  });

  test('guarded auto requires an explicit local session start', () {
    final blocked = gateway.evaluate(
      input(
        mode: AutonomyExecutionMode.guardedAuto,
        explicitSessionStarted: false,
      ),
    );
    final started = gateway.evaluate(
      input(mode: AutonomyExecutionMode.guardedAuto),
    );

    expect(
      blocked.blockReason,
      AutonomyPolicyBlockReason.explicitSessionRequired,
    );
    expect(started.newEntryAuthorized, isTrue);
  });

  test(
    'every live entry still requires canonical Risk and Allocation gates',
    () {
      expect(
        gateway.evaluate(input(canonicalDecisionEligible: false)).blockReason,
        AutonomyPolicyBlockReason.canonicalDecisionRejected,
      );
      expect(
        gateway.evaluate(input(riskDecisionAllowed: false)).blockReason,
        AutonomyPolicyBlockReason.riskDecisionRejected,
      );
      expect(
        gateway.evaluate(input(allocationSelected: false)).blockReason,
        AutonomyPolicyBlockReason.allocationDecisionRejected,
      );
    },
  );

  test('critical deterministic health failure blocks new entries', () {
    final decision = gateway.evaluate(input(criticalHealthClear: false));

    expect(decision.newEntryAuthorized, isFalse);
    expect(
      decision.blockReason,
      AutonomyPolicyBlockReason.criticalHealthUnhealthy,
    );
  });

  test('capped auto stays locked before canary promotion', () {
    final decision = gateway.evaluate(
      input(
        mode: AutonomyExecutionMode.cappedAuto,
        promotionState: AutonomyPromotionState.paperEligible,
      ),
    );

    expect(decision.newEntryAuthorized, isFalse);
    expect(
      decision.blockReason,
      AutonomyPolicyBlockReason.promotionInsufficient,
    );
  });

  test('capped auto requires configured capital and risk caps', () {
    final decision = gateway.evaluate(
      input(
        mode: AutonomyExecutionMode.cappedAuto,
        promotionState: AutonomyPromotionState.cappedCanaryEligible,
        strategyEvidenceApproved: true,
        faultCertificationCurrent: true,
        buildIdentityApproved: true,
        strategyIdentityApproved: true,
        durableWorkerCertified: true,
        persistentCredentialBoundaryReady: true,
      ),
    );

    expect(decision.newEntryAuthorized, isFalse);
    expect(
      decision.blockReason,
      AutonomyPolicyBlockReason.capitalRiskCapsMissing,
    );
  });

  test(
    'capped auto requires a certified durable worker and credential boundary',
    () {
      final missingWorker = gateway.evaluate(
        input(
          mode: AutonomyExecutionMode.cappedAuto,
          promotionState: AutonomyPromotionState.cappedCanaryEligible,
          strategyEvidenceApproved: true,
          faultCertificationCurrent: true,
          buildIdentityApproved: true,
          strategyIdentityApproved: true,
          capitalRiskCapsConfigured: true,
          persistentCredentialBoundaryReady: true,
        ),
      );
      final eligible = gateway.evaluate(durableInput());

      expect(
        missingWorker.blockReason,
        AutonomyPolicyBlockReason.durableWorkerUncertified,
      );
      expect(eligible.newEntryAuthorized, isTrue);
    },
  );

  test(
    'autonomous mode requires autonomous promotion even with all infrastructure',
    () {
      final canaryOnly = gateway.evaluate(
        durableInput(mode: AutonomyExecutionMode.autonomous),
      );
      final eligible = gateway.evaluate(
        durableInput(
          mode: AutonomyExecutionMode.autonomous,
          promotionState: AutonomyPromotionState.autonomousEligible,
        ),
      );

      expect(
        canaryOnly.blockReason,
        AutonomyPolicyBlockReason.promotionInsufficient,
      );
      expect(eligible.newEntryAuthorized, isTrue);
    },
  );

  test(
    'health failure blocks entry but keeps existing reduce-only management',
    () {
      final decision = gateway.evaluate(
        input(privateTruthHealthy: false, hasManagedExposure: true),
      );

      expect(decision.newEntryAuthorized, isFalse);
      expect(
        decision.blockReason,
        AutonomyPolicyBlockReason.privateTruthUnhealthy,
      );
      expect(decision.reduceOnlyManagementAuthorized, isTrue);
      expect(
        decision.authorizes(AutonomyOperation.reduceOnlyExistingExposure),
        isTrue,
      );
    },
  );

  test('suspended promotion blocks entry before mode-specific authority', () {
    final decision = gateway.evaluate(
      input(
        mode: AutonomyExecutionMode.guardedAuto,
        promotionState: AutonomyPromotionState.suspended,
      ),
    );

    expect(decision.blockReason, AutonomyPolicyBlockReason.promotionSuspended);
    expect(decision.newEntryAuthorized, isFalse);
  });

  test(
    'forbidden financial authorities are unreachable even in autonomous mode',
    () {
      final decision = gateway.evaluate(
        durableInput(
          mode: AutonomyExecutionMode.autonomous,
          promotionState: AutonomyPromotionState.autonomousEligible,
        ),
      );

      expect(decision.newEntryAuthorized, isTrue);
      for (final operation in [
        AutonomyOperation.addToExistingExposure,
        AutonomyOperation.averagingDown,
        AutonomyOperation.martingale,
        AutonomyOperation.widenStop,
        AutonomyOperation.removeStop,
        AutonomyOperation.withdrawal,
        AutonomyOperation.transfer,
        AutonomyOperation.crossMargin,
      ]) {
        expect(decision.authorizes(operation), isFalse, reason: operation.name);
      }
    },
  );

  test('decision evidence includes elevated-mode prerequisites', () {
    final decision = gateway.evaluate(durableInput());

    expect(decision.evidence, contains('capitalRiskCaps:true'));
    expect(decision.evidence, contains('durableWorker:true'));
    expect(decision.evidence, contains('credentialBoundary:true'));
    expect(decision.evidence, contains('criticalHealth:true'));
  });

  test('empty policy version fails closed', () {
    const invalidGateway = AutonomyPolicyGateway(version: '   ');
    expect(() => invalidGateway.evaluate(input()), throwsFormatException);
  });
}
