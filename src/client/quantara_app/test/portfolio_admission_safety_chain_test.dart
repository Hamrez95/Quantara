import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/portfolio_risk/domain/capital_guardian.dart';
import 'package:quantara_app/features/portfolio_risk/domain/portfolio_admission_safety_chain.dart';
import 'package:quantara_app/features/portfolio_risk/domain/portfolio_correlation_policy.dart';
import 'package:quantara_app/features/portfolio_risk/domain/portfolio_liquidation_policy.dart';
import 'package:quantara_app/features/portfolio_risk/domain/portfolio_risk_models.dart';

void main() {
  PortfolioEntryDecision base({
    bool allowed = true,
    bool live = true,
    PortfolioEntryBlockReason reason = PortfolioEntryBlockReason.none,
  }) => PortfolioEntryDecision(
    allowed: allowed,
    liveExecutionAllowed: live,
    reason: reason,
    maximumLoss: 2,
    requiredMargin: 5,
    availableRiskBefore: 10,
    availableRiskAfter: allowed ? 8 : 10,
    availableMarginAfter: allowed ? 45 : 50,
  );

  CapitalGuardianDecision guardian({
    bool allowed = true,
    CapitalGuardianBreakerReason reason = CapitalGuardianBreakerReason.none,
  }) => CapitalGuardianDecision(
    allowed: allowed,
    reason: reason,
    drawdownTier: CapitalGuardianDrawdownTier.normal,
    riskMultiplier: 1,
    weeklyLossLimit: 30,
    weeklyLossRemaining: 25,
    maximumAllowedEntryRisk: 10,
  );

  PortfolioCorrelationDecision correlation({
    bool allowed = true,
    PortfolioCorrelationReason reason = PortfolioCorrelationReason.allowed,
  }) => PortfolioCorrelationDecision(
    allowed: allowed,
    reason: reason,
    bucket: 'large-cap-beta',
    bucketRiskLimit: 6,
    bucketRiskBefore: 2,
    bucketRiskAfter: 4,
  );

  PortfolioLiquidationDecision liquidation({
    bool allowed = true,
    PortfolioLiquidationReason reason = PortfolioLiquidationReason.allowed,
  }) => PortfolioLiquidationDecision(
    allowed: allowed,
    reason: reason,
    liquidationCushionFraction: 0.05,
    minimumLiquidationCushionFraction: 0.015,
    marginHeadroomAfterEntry: 20,
    minimumMarginHeadroom: 1.25,
  );

  test('all safety stages must allow before live admission is approved', () {
    final decision = PortfolioAdmissionSafetyChain.compose(
      baseRisk: base(),
      guardian: guardian(),
      correlation: correlation(),
      liquidation: liquidation(),
    );

    expect(decision.status, PortfolioAdmissionStatus.approved);
    expect(decision.blockingStage, PortfolioAdmissionStage.complete);
    expect(decision.reasonCodes, ['admission:approved']);
  });

  test('a rejected base Risk decision can never be overridden downstream', () {
    final decision = PortfolioAdmissionSafetyChain.compose(
      baseRisk: base(
        allowed: false,
        reason: PortfolioEntryBlockReason.riskBudgetInsufficient,
      ),
      guardian: guardian(),
      correlation: correlation(),
      liquidation: liquidation(),
    );

    expect(decision.status, PortfolioAdmissionStatus.rejected);
    expect(decision.blockingStage, PortfolioAdmissionStage.baseRisk);
    expect(decision.reasonCodes, ['base:riskBudgetInsufficient']);
  });

  test('stale account truth is deferred instead of treated as safe', () {
    final decision = PortfolioAdmissionSafetyChain.compose(
      baseRisk: base(
        allowed: false,
        reason: PortfolioEntryBlockReason.staleAccount,
      ),
      guardian: guardian(),
      correlation: correlation(),
      liquidation: liquidation(),
    );

    expect(decision.status, PortfolioAdmissionStatus.deferred);
    expect(decision.blockingStage, PortfolioAdmissionStage.baseRisk);
  });

  test('loss-streak cooldown is a deferred Guardian gate', () {
    final decision = PortfolioAdmissionSafetyChain.compose(
      baseRisk: base(),
      guardian: guardian(
        allowed: false,
        reason: CapitalGuardianBreakerReason.lossStreakCooldown,
      ),
      correlation: correlation(),
      liquidation: liquidation(),
    );

    expect(decision.status, PortfolioAdmissionStatus.deferred);
    expect(decision.blockingStage, PortfolioAdmissionStage.capitalGuardian);
    expect(decision.reasonCodes, ['guardian:lossStreakCooldown']);
  });

  test('hard correlation bucket ceiling rejects regardless of later safety', () {
    final decision = PortfolioAdmissionSafetyChain.compose(
      baseRisk: base(),
      guardian: guardian(),
      correlation: correlation(
        allowed: false,
        reason: PortfolioCorrelationReason.correlationBucketLimit,
      ),
      liquidation: liquidation(),
    );

    expect(decision.status, PortfolioAdmissionStatus.rejected);
    expect(decision.blockingStage, PortfolioAdmissionStage.correlation);
    expect(decision.reasonCodes, ['correlation:correlationBucketLimit']);
  });

  test('stale liquidation evidence defers rather than approving blindly', () {
    final decision = PortfolioAdmissionSafetyChain.compose(
      baseRisk: base(),
      guardian: guardian(),
      correlation: correlation(),
      liquidation: liquidation(
        allowed: false,
        reason: PortfolioLiquidationReason.staleEvidence,
      ),
    );

    expect(decision.status, PortfolioAdmissionStatus.deferred);
    expect(decision.blockingStage, PortfolioAdmissionStage.liquidation);
    expect(decision.reasonCodes, ['liquidation:staleEvidence']);
  });

  test('invalid liquidation policy and inputs are hard rejections', () {
    for (final reason in [
      PortfolioLiquidationReason.invalidPolicy,
      PortfolioLiquidationReason.invalidCandidateInputs,
      PortfolioLiquidationReason.invalidAccountInputs,
    ]) {
      final decision = PortfolioAdmissionSafetyChain.compose(
        baseRisk: base(),
        guardian: guardian(),
        correlation: correlation(),
        liquidation: liquidation(allowed: false, reason: reason),
      );

      expect(decision.status, PortfolioAdmissionStatus.rejected);
      expect(decision.blockingStage, PortfolioAdmissionStage.liquidation);
      expect(decision.reasonCodes, ['liquidation:${reason.name}']);
    }
  });

  test('unsafe liquidation geometry is a hard rejection', () {
    final decision = PortfolioAdmissionSafetyChain.compose(
      baseRisk: base(),
      guardian: guardian(),
      correlation: correlation(),
      liquidation: liquidation(
        allowed: false,
        reason: PortfolioLiquidationReason.invalidLiquidationGeometry,
      ),
    );

    expect(decision.status, PortfolioAdmissionStatus.rejected);
    expect(decision.blockingStage, PortfolioAdmissionStage.liquidation);
  });

  test('paper-safe decision without live authority remains deferred', () {
    final decision = PortfolioAdmissionSafetyChain.compose(
      baseRisk: base(live: false),
      guardian: guardian(),
      correlation: correlation(),
      liquidation: liquidation(),
    );

    expect(decision.status, PortfolioAdmissionStatus.deferred);
    expect(decision.blockingStage, PortfolioAdmissionStage.liveExecution);
    expect(decision.reasonCodes, ['live:execution-not-allowed']);
  });

  test('decision breakdown keeps risk, correlation and liquidation evidence', () {
    final json = PortfolioAdmissionSafetyChain.compose(
      baseRisk: base(),
      guardian: guardian(),
      correlation: correlation(),
      liquidation: liquidation(),
    ).toJson();

    expect(json['proposedMaximumLoss'], 2);
    expect(json['requiredMargin'], 5);
    expect(
      (json['correlation'] as Map<String, Object?>)['bucket'],
      'large-cap-beta',
    );
    expect(
      (json['liquidation'] as Map<String, Object?>)['cushionFraction'],
      0.05,
    );
  });
}
