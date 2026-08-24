import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/autonomy/domain/autonomy_command_authorization.dart';
import 'package:quantara_app/features/autonomy/domain/autonomy_policy_gateway.dart';

void main() {
  test('authorized command carries exact deterministic policy provenance', () {
    final decision = _decision(AutonomyExecutionMode.guardedAuto);
    final authorizedAt = DateTime.utc(2026, 8, 18, 14);

    final authorization = _authorization(
      decision: decision,
      runtime: AutonomyCommandRuntime.localAndroid,
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
    expect(
      json['riskDecisionObservedAtUtc'],
      authorizedAt.subtract(const Duration(seconds: 10)).toIso8601String(),
    );
    expect(
      json['allocationDecisionObservedAtUtc'],
      authorizedAt.subtract(const Duration(seconds: 5)).toIso8601String(),
    );
    expect(authorization.policyEvidence, contains('risk:true'));
    expect(authorization.policyEvidence, contains('allocation:true'));
  });

  test('blocked autonomy decision cannot mint live command provenance', () {
    final decision = _decision(AutonomyExecutionMode.readOnly);

    expect(
      () => _authorization(
        decision: decision,
        runtime: AutonomyCommandRuntime.localAndroid,
        authorizedAtUtc: DateTime.utc(2026, 8, 18, 14),
      ),
      throwsStateError,
    );
  });

  test('authorization fails closed on incomplete identity or non-UTC time', () {
    final decision = _decision(AutonomyExecutionMode.guardedAuto);
    final authorizedAt = DateTime.utc(2026, 8, 18, 14);

    expect(
      () => AutonomyCommandAuthorization.fromPolicyDecision(
        decision: decision,
        runtime: AutonomyCommandRuntime.localAndroid,
        idempotencyKey: ' ',
        clientId: 'q-live-setup-42-v7',
        policyDecisionId: 'policy-decision-42',
        canonicalDecisionId: 'canonical-42',
        riskDecisionId: 'risk-42',
        riskDecisionObservedAtUtc: authorizedAt,
        allocationDecisionId: 'allocation-42',
        allocationDecisionObservedAtUtc: authorizedAt,
        authorizedAtUtc: authorizedAt,
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
        riskDecisionObservedAtUtc: authorizedAt,
        allocationDecisionId: 'allocation-42',
        allocationDecisionObservedAtUtc: authorizedAt,
        authorizedAtUtc: DateTime(2026, 8, 18, 14),
      ),
      throwsFormatException,
    );
  });

  test('stale Risk decision cannot mint live command provenance', () {
    final authorizedAt = DateTime.utc(2026, 8, 18, 14);

    expect(
      () => _authorization(
        decision: _decision(AutonomyExecutionMode.guardedAuto),
        runtime: AutonomyCommandRuntime.localAndroid,
        authorizedAtUtc: authorizedAt,
        riskObservedAtUtc: authorizedAt.subtract(const Duration(seconds: 31)),
      ),
      throwsStateError,
    );
  });

  test('stale Allocation decision cannot mint live command provenance', () {
    final authorizedAt = DateTime.utc(2026, 8, 18, 14);

    expect(
      () => _authorization(
        decision: _decision(AutonomyExecutionMode.guardedAuto),
        runtime: AutonomyCommandRuntime.localAndroid,
        authorizedAtUtc: authorizedAt,
        allocationObservedAtUtc: authorizedAt.subtract(
          const Duration(seconds: 31),
        ),
      ),
      throwsStateError,
    );
  });

  test('future Risk or Allocation evidence fails closed', () {
    final authorizedAt = DateTime.utc(2026, 8, 18, 14);

    expect(
      () => _authorization(
        decision: _decision(AutonomyExecutionMode.guardedAuto),
        runtime: AutonomyCommandRuntime.localAndroid,
        authorizedAtUtc: authorizedAt,
        riskObservedAtUtc: authorizedAt.add(const Duration(seconds: 1)),
      ),
      throwsStateError,
    );
    expect(
      () => _authorization(
        decision: _decision(AutonomyExecutionMode.guardedAuto),
        runtime: AutonomyCommandRuntime.localAndroid,
        authorizedAtUtc: authorizedAt,
        allocationObservedAtUtc: authorizedAt.add(const Duration(seconds: 1)),
      ),
      throwsStateError,
    );
  });

  test('persistent autonomy cannot mint a command on local Android', () {
    final decision = _durableDecision(AutonomyExecutionMode.cappedAuto);

    expect(
      () => _authorization(
        decision: decision,
        runtime: AutonomyCommandRuntime.localAndroid,
        authorizedAtUtc: DateTime.utc(2026, 8, 18, 14),
      ),
      throwsStateError,
    );
  });

  test('persistent autonomy records a certified durable runtime', () {
    final authorization = _authorization(
      decision: _durableDecision(AutonomyExecutionMode.autonomous),
      runtime: AutonomyCommandRuntime.durableService,
      authorizedAtUtc: DateTime.utc(2026, 8, 18, 14),
    );

    expect(authorization.runtime, AutonomyCommandRuntime.durableService);
    expect(authorization.toJson()['runtime'], 'durableService');
  });
}

AutonomyCommandAuthorization _authorization({
  required AutonomyPolicyDecision decision,
  required AutonomyCommandRuntime runtime,
  required DateTime authorizedAtUtc,
  DateTime? riskObservedAtUtc,
  DateTime? allocationObservedAtUtc,
}) => AutonomyCommandAuthorization.fromPolicyDecision(
  decision: decision,
  runtime: runtime,
  idempotencyKey: 'account-a:setup-42:v7',
  clientId: 'q-live-setup-42-v7',
  policyDecisionId: 'policy-decision-42',
  canonicalDecisionId: 'canonical-42',
  riskDecisionId: 'risk-42',
  riskDecisionObservedAtUtc:
      riskObservedAtUtc ??
      authorizedAtUtc.subtract(const Duration(seconds: 10)),
  allocationDecisionId: 'allocation-42',
  allocationDecisionObservedAtUtc:
      allocationObservedAtUtc ??
      authorizedAtUtc.subtract(const Duration(seconds: 5)),
  authorizedAtUtc: authorizedAtUtc,
);

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
