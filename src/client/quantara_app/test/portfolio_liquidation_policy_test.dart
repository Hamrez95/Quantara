import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/portfolio_risk/domain/portfolio_liquidation_policy.dart';
import 'package:quantara_app/features/portfolio_risk/domain/portfolio_risk_models.dart';

void main() {
  final now = DateTime.utc(2026, 8, 17, 8);

  PortfolioEntryCandidate candidate({
    PortfolioSide side = PortfolioSide.long,
    double entry = 100,
    double stop = 95,
  }) => PortfolioEntryCandidate(
    reservationId: 'reservation-1',
    journalTradeId: 'trade-1',
    candidateId: 'candidate-1',
    symbol: 'BTCUSDT',
    assetGroup: 'crypto',
    side: side,
    strategy: 'test',
    plannedQuantity: 1,
    entryPrice: entry,
    stopPrice: stop,
    contractMultiplier: 1,
    entryFeeRate: 0,
    exitFeeRate: 0,
    slippageRate: 0,
    fundingReserve: 0,
    requiredMargin: 8,
    leverage: 10,
    minimumQuantity: 0.001,
    minimumNotional: 1,
  );

  PortfolioAccountTruth account({
    double freeMargin = 100,
    double maintenanceMargin = 0,
    double safetyBuffer = 10,
    double feeReserve = 1,
  }) => PortfolioAccountTruth(
    asOf: now,
    fresh: true,
    allOpenPositionsProtected: true,
    marginMode: 'isolated',
    freeMargin: freeMargin,
    usedMargin: 0,
    maintenanceMargin: maintenanceMargin,
    pendingMarginReservations: 0,
    safetyBuffer: safetyBuffer,
    feeReserve: feeReserve,
  );

  PortfolioEntryDecision allowed({double requiredMargin = 8}) =>
      PortfolioEntryDecision(
        allowed: true,
        liveExecutionAllowed: false,
        reason: PortfolioEntryBlockReason.none,
        maximumLoss: 5,
        requiredMargin: requiredMargin,
        availableRiskBefore: 10,
        availableRiskAfter: 5,
        availableMarginAfter: 90,
      );

  PortfolioLiquidationEvidence evidence(
    double liquidationPrice, {
    DateTime? asOf,
  }) => PortfolioLiquidationEvidence(
    asOfUtc: asOf ?? now,
    estimatedLiquidationPrice: liquidationPrice,
    source: 'bitunix-private-account-v1',
  );

  test('long stop must keep a minimum cushion above liquidation', () {
    const policy = PortfolioLiquidationPolicy(
      minimumLiquidationCushionFraction: 0.04,
    );
    final decision = policy.evaluate(
      candidate: candidate(),
      account: account(),
      baseDecision: allowed(),
      evidence: evidence(90),
      nowUtc: now,
    );

    expect(decision.allowed, isTrue);
    expect(decision.liquidationCushionFraction, closeTo(0.05, 1e-9));
  });

  test('short stop uses the symmetric liquidation cushion sign', () {
    const policy = PortfolioLiquidationPolicy(
      minimumLiquidationCushionFraction: 0.04,
    );
    final decision = policy.evaluate(
      candidate: candidate(side: PortfolioSide.short, stop: 105),
      account: account(),
      baseDecision: allowed(),
      evidence: evidence(110),
      nowUtc: now,
    );

    expect(decision.allowed, isTrue);
    expect(decision.liquidationCushionFraction, closeTo(0.05, 1e-9));
  });

  test('invalid policy configuration fails closed at runtime', () {
    const invalidAge = PortfolioLiquidationPolicy(
      maximumEvidenceAge: Duration.zero,
    );
    const invalidCushion = PortfolioLiquidationPolicy(
      minimumLiquidationCushionFraction: double.nan,
    );
    const invalidHeadroom = PortfolioLiquidationPolicy(
      minimumPostEntryMarginHeadroomFraction: double.nan,
    );

    for (final policy in [invalidAge, invalidCushion, invalidHeadroom]) {
      final decision = policy.evaluate(
        candidate: candidate(),
        account: account(),
        baseDecision: allowed(),
        evidence: evidence(90),
        nowUtc: now,
      );
      expect(decision.allowed, isFalse);
      expect(decision.reason, PortfolioLiquidationReason.invalidPolicy);
    }
  });

  test('nonfinite candidate geometry fails closed before comparison', () {
    const policy = PortfolioLiquidationPolicy();
    final decision = policy.evaluate(
      candidate: candidate(entry: double.nan),
      account: account(),
      baseDecision: allowed(),
      evidence: evidence(90),
      nowUtc: now,
    );

    expect(decision.allowed, isFalse);
    expect(decision.reason, PortfolioLiquidationReason.invalidCandidateInputs);
  });

  test('nonfinite account or required-margin inputs fail closed', () {
    const policy = PortfolioLiquidationPolicy();
    final invalidAccount = policy.evaluate(
      candidate: candidate(),
      account: account(freeMargin: double.nan),
      baseDecision: allowed(),
      evidence: evidence(90),
      nowUtc: now,
    );
    final invalidMargin = policy.evaluate(
      candidate: candidate(),
      account: account(),
      baseDecision: allowed(requiredMargin: double.nan),
      evidence: evidence(90),
      nowUtc: now,
    );

    expect(invalidAccount.allowed, isFalse);
    expect(
      invalidAccount.reason,
      PortfolioLiquidationReason.invalidAccountInputs,
    );
    expect(invalidMargin.allowed, isFalse);
    expect(
      invalidMargin.reason,
      PortfolioLiquidationReason.invalidAccountInputs,
    );
  });

  test('liquidation price on the wrong side of stop fails closed', () {
    const policy = PortfolioLiquidationPolicy();
    final decision = policy.evaluate(
      candidate: candidate(),
      account: account(),
      baseDecision: allowed(),
      evidence: evidence(96),
      nowUtc: now,
    );

    expect(decision.allowed, isFalse);
    expect(
      decision.reason,
      PortfolioLiquidationReason.invalidLiquidationGeometry,
    );
  });

  test('freshness expiry rejects otherwise safe liquidation evidence', () {
    const policy = PortfolioLiquidationPolicy(
      maximumEvidenceAge: Duration(seconds: 5),
    );
    final decision = policy.evaluate(
      candidate: candidate(),
      account: account(),
      baseDecision: allowed(),
      evidence: evidence(90, asOf: now.subtract(const Duration(seconds: 6))),
      nowUtc: now,
    );

    expect(decision.allowed, isFalse);
    expect(decision.reason, PortfolioLiquidationReason.staleEvidence);
  });

  test('future-dated liquidation evidence fails closed', () {
    const policy = PortfolioLiquidationPolicy();
    final decision = policy.evaluate(
      candidate: candidate(),
      account: account(),
      baseDecision: allowed(),
      evidence: evidence(90, asOf: now.add(const Duration(milliseconds: 1))),
      nowUtc: now,
    );

    expect(decision.allowed, isFalse);
    expect(decision.reason, PortfolioLiquidationReason.invalidEvidence);
  });

  test('small liquidation cushion blocks a new entry', () {
    const policy = PortfolioLiquidationPolicy(
      minimumLiquidationCushionFraction: 0.02,
    );
    final decision = policy.evaluate(
      candidate: candidate(),
      account: account(),
      baseDecision: allowed(),
      evidence: evidence(94),
      nowUtc: now,
    );

    expect(decision.allowed, isFalse);
    expect(
      decision.reason,
      PortfolioLiquidationReason.insufficientLiquidationCushion,
    );
    expect(decision.liquidationCushionFraction, closeTo(0.01, 1e-9));
  });

  test('entry must leave margin headroom beyond existing safety reserves', () {
    const policy = PortfolioLiquidationPolicy(
      minimumPostEntryMarginHeadroomFraction: 0.25,
    );
    final decision = policy.evaluate(
      candidate: candidate(),
      account: account(freeMargin: 20),
      baseDecision: allowed(requiredMargin: 8),
      evidence: evidence(90),
      nowUtc: now,
    );

    expect(decision.allowed, isFalse);
    expect(
      decision.reason,
      PortfolioLiquidationReason.insufficientMarginHeadroom,
    );
    expect(decision.marginHeadroomAfterEntry, 1);
    expect(decision.minimumMarginHeadroom, 2);
  });

  test('liquidation policy never overrides a rejected base decision', () {
    const policy = PortfolioLiquidationPolicy();
    final blocked = PortfolioEntryDecision(
      allowed: false,
      liveExecutionAllowed: false,
      reason: PortfolioEntryBlockReason.marginInsufficient,
      maximumLoss: 5,
      requiredMargin: 8,
      availableRiskBefore: 10,
      availableRiskAfter: 10,
      availableMarginAfter: 1,
    );

    final decision = policy.evaluate(
      candidate: candidate(),
      account: account(),
      baseDecision: blocked,
      evidence: evidence(90),
      nowUtc: now,
    );

    expect(decision.allowed, isFalse);
    expect(decision.reason, PortfolioLiquidationReason.baseDecisionRejected);
  });
}
