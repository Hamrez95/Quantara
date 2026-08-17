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

  test('all safety stages must allow before approval', () {
    final decision = PortfolioAdmissionSafetyChain.compose(
      baseRisk: base(),
      guardian: guardian(),
      correlation: correlation(),
      liquidation: liquidation(),
    );

    expect(decision.status, PortfolioAdmissionStatus.approved);
    expect(decision.blockingStage, PortfolioAdmissionStage.complete);
  });

  test('base rejection cannot be overridden downstream', () {
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
  });

  test('stale account and Guardian cooldown defer fail closed', () {
    final stale = PortfolioAdmissionSafetyChain.compose(
      baseRisk: base(
        allowed: false,
        reason: PortfolioEntryBlockReason.staleAccount,
      ),
      guardian: guardian(),
      correlation: correlation(),
      liquidation: liquidation(),
    );
    final cooldown = PortfolioAdmissionSafetyChain.compose(
      baseRisk: base(),
      guardian: guardian(
        allowed: false,
        reason: CapitalGuardianBreakerReason.lossStreakCooldown,
      ),
      correlation: correlation(),
      liquidation: liquidation(),
    );

    expect(stale.status, PortfolioAdmissionStatus.deferred);
    expect(cooldown.status, PortfolioAdmissionStatus.deferred);
  });

  test('correlation and invalid liquidation inputs are hard rejections', () {
    final correlated = PortfolioAdmissionSafetyChain.compose(
      baseRisk: base(),
      guardian: guardian(),
      correlation: correlation(
        allowed: false,
        reason: PortfolioCorrelationReason.correlationBucketLimit,
      ),
      liquidation: liquidation(),
    );
    final invalidLiquidation = PortfolioAdmissionSafetyChain.compose(
      baseRisk: base(),
      guardian: guardian(),
      correlation: correlation(),
      liquidation: liquidation(
        allowed: false,
        reason: PortfolioLiquidationReason.invalidCandidateInputs,
      ),
    );

    expect(correlated.status, PortfolioAdmissionStatus.rejected);
    expect(invalidLiquidation.status, PortfolioAdmissionStatus.rejected);
  });

  test('stale liquidation evidence and absent runtime authority defer', () {
    final staleEvidence = PortfolioAdmissionSafetyChain.compose(
      baseRisk: base(),
      guardian: guardian(),
      correlation: correlation(),
      liquidation: liquidation(
        allowed: false,
        reason: PortfolioLiquidationReason.staleEvidence,
      ),
    );
    final noRuntimeAuthority = PortfolioAdmissionSafetyChain.compose(
      baseRisk: base(live: false),
      guardian: guardian(),
      correlation: correlation(),
      liquidation: liquidation(),
    );

    expect(staleEvidence.status, PortfolioAdmissionStatus.deferred);
    expect(noRuntimeAuthority.status, PortfolioAdmissionStatus.deferred);
  });

  test('decision audit retains risk and safety evidence', () {
    final json = PortfolioAdmissionSafetyChain.compose(
      baseRisk: base(),
      guardian: guardian(),
      correlation: correlation(),
      liquidation: liquidation(),
    ).toJson();

    expect(json['proposedMaximumLoss'], 2);
    expect((json['correlation'] as Map<String, Object?>)['bucket'], 'large-cap-beta');
    expect(
      (json['liquidation'] as Map<String, Object?>)['cushionFraction'],
      0.05,
    );
  });
}
