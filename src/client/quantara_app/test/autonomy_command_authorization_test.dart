import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/autonomy/domain/autonomy_command_authorization.dart';
import 'package:quantara_app/features/autonomy/domain/autonomy_policy_gateway.dart';

void main() {
  test('authorized command carries exact deterministic policy provenance', () {
    final decision = _decision(AutonomyExecutionMode.guardedAuto);
    final authorizedAt = DateTime.utc(2026, 8, 18, 14);

    final authorization = AutonomyCommandAuthorization.fromPolicyDecision(
      decision: decision,
      runtime: AutonomyCommandRuntime.localAndroid,
      idempotencyKey: 'account-a:setup-42:v7',
      clientId: 'q-live-setup-42-v7',
      policyDecisionId: 'policy-decision-42',
      canonicalDecisionId: 'canonical-42',
      riskDecisionId: 'risk-42',
      allocationDecisionId: 'allocation-42',
      authorizedAtUtc: authorizedAt,
    );
    final json = authorization.toJson();

    expect(authorization.policyVersion, 'autonomy-policy/test');
    expect(authorization.mode, AutonomyExecutionMode.guardedAuto);
    expect(authorization.runtime, AutonomyCommandRuntime.localAndroid);
    expect(
      authorization.promotionState,
      AutonomyPromotionState.cappedCanaryEligible,
    );
    expect(json['idempotencyKey'], 'account-a:setup-42:v7');
    expect(json['clientId'], 'q-live-setup-42-v7');
    expect(json['policyDecisionId'], 'policy-decision-42');
    expect(json['canonicalDecisionId'], 'canonical-42');
    expect(json['riskDecisionId'], 'risk-42');
    expect(json['allocationDecisionId'], 'allocation-42');
    expect(json['runtime'], 'localAndroid');
    expect(json['authorizedAtUtc'], authorizedAt.toIso8601String());
    expect(authorization.policyEvidence, contains('risk:true'));
    expect(authorization.policyEvidence, contains('allocation:true'));
  });

  test('blocked autonomy decision cannot mint live command provenance', () {
    final decision = _decision(AutonomyExecutionMode.readOnly);

    expect(
      () => AutonomyCommandAuthorization.fromPolicyDecision(
        decision: decision,
        runtime: AutonomyCommandRuntime.localAndroid,
        idempotencyKey: 'account-a:setup-42:v7',
        clientId: 'q-live-setup-42-v7',
        policyDecisionId: 'policy-decision-42',
        canonicalDecisionId: 'canonical-42',
        riskDecisionId: 'risk-42',
        allocationDecisionId: 'allocation-42',
        authorizedAtUtc: DateTime.utc(2026, 8, 18, 14),
      ),
      throwsStateError,
    );
  });

  test('authorization fails closed on incomplete identity or non-UTC time', () {
    final decision = _decision(AutonomyExecutionMode.guardedAuto);

    expect(
      () => AutonomyCommandAuthorization.fromPolicyDecision(
        decision: decision,
        runtime: AutonomyCommandRuntime.localAndroid,
        idempotencyKey: ' ',
        clientId: 'q-live-setup-42-v7',
        policyDecisionId: 'policy-decision-42',
        canonicalDecisionId: 'canonical-42',
        riskDecisionId: 'risk-42',
        allocationDecisionId: 'allocation-42',
        authorizedAtUtc: DateTime.utc(2026, 8, 18, 14),
      ),
      throwsFormatException,
    );
    expect(
      () => AutonomyCommandAuthorization.fromPolicyDecision(
        decision: decision,
        runtime: AutonomyCommandRuntime.localAndroid,
        idempotencyKey: 'account-a:setup-42:v7',
        clientId: 'q-live-setup-42-v7',
        policyDecisionId: 'policy-decision-42',
        canonicalDecisionId: 'canonical-42',
        riskDecisionId: 'risk-42',
        allocationDecisionId: 'allocation-42',
        authorizedAtUtc: DateTime(2026, 8, 18, 14),
      ),
      throwsFormatException,
    );
  });

  test('persistent autonomy cannot mint a command on local Android', () {
    final decision = _durableDecision(AutonomyExecutionMode.cappedAuto);

    expect(
      () => AutonomyCommandAuthorization.fromPolicyDecision(
        decision: decision,
        runtime: AutonomyCommandRuntime.localAndroid,
        idempotencyKey: 'account-a:setup-42:v7',
        clientId: 'q-live-setup-42-v7',
        policyDecisionId: 'policy-decision-42',
        canonicalDecisionId: 'canonical-42',
        riskDecisionId: 'risk-42',
        allocationDecisionId: 'allocation-42',
        authorizedAtUtc: DateTime.utc(2026, 8, 18, 14),
      ),
      throwsStateError,
    );
  });

  test('persistent autonomy records a certified durable runtime', () {
    final decision = _durableDecision(AutonomyExecutionMode.autonomous);

    final authorization = AutonomyCommandAuthorization.fromPolicyDecision(
      decision: decision,
      runtime: AutonomyCommandRuntime.durableService,
      idempotencyKey: 'account-a:setup-42:v7',
      clientId: 'q-live-setup-42-v7',
      policyDecisionId: 'policy-decision-42',
      canonicalDecisionId: 'canonical-42',
      riskDecisionId: 'risk-42',
      allocationDecisionId: 'allocation-42',
      authorizedAtUtc: DateTime.utc(2026, 8, 18, 14),
    );

    expect(authorization.runtime, AutonomyCommandRuntime.durableService);
    expect(authorization.toJson()['runtime'], 'durableService');
  });
}

AutonomyPolicyDecision _decision(AutonomyExecutionMode mode) =>
    const AutonomyPolicyGateway(version: 'autonomy-policy/test').evaluate(
      AutonomyPolicyInput(
        mode: mode,
        promotionState: AutonomyPromotionState.cappedCanaryEligible,
        canonicalDecisionEligible: true,
        riskDecisionAllowed: true,
        allocationSelected: true,
        marketTruthHealthy: true,
        privateTruthHealthy: true,
        protectionHealthy: true,
        riskAccountConsistent: true,
        riskBreakersClear: true,
        executionQualityHealthy: true,
        strategyDriftHealthy: true,
        criticalHealthClear: true,
        explicitSessionStarted: true,
      ),
    );

AutonomyPolicyDecision _durableDecision(AutonomyExecutionMode mode) =>
    const AutonomyPolicyGateway(version: 'autonomy-policy/test').evaluate(
      AutonomyPolicyInput(
        mode: mode,
        promotionState: AutonomyPromotionState.autonomousEligible,
        canonicalDecisionEligible: true,
        riskDecisionAllowed: true,
        allocationSelected: true,
        marketTruthHealthy: true,
        privateTruthHealthy: true,
        protectionHealthy: true,
        riskAccountConsistent: true,
        riskBreakersClear: true,
        executionQualityHealthy: true,
        strategyDriftHealthy: true,
        criticalHealthClear: true,
        strategyEvidenceApproved: true,
        faultCertificationCurrent: true,
        buildIdentityApproved: true,
        strategyIdentityApproved: true,
        capitalRiskCapsConfigured: true,
        durableWorkerCertified: true,
        persistentCredentialBoundaryReady: true,
      ),
    );
