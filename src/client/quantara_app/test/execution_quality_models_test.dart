import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/domain/execution_quality_models.dart';

void main() {
  final now = DateTime.utc(2026, 8, 17, 8);

  test('long slippage is positive when the fill is worse', () {
    expect(
      ExecutionQualityMath.signedSlippageBps(
        side: ExecutionSide.long,
        referencePrice: 100,
        fillPrice: 101,
      ),
      closeTo(100, 1e-9),
    );
    expect(
      ExecutionQualityMath.signedSlippageBps(
        side: ExecutionSide.long,
        referencePrice: 100,
        fillPrice: 99,
      ),
      closeTo(-100, 1e-9),
    );
  });

  test('short slippage is positive when the fill is worse', () {
    expect(
      ExecutionQualityMath.signedSlippageBps(
        side: ExecutionSide.short,
        referencePrice: 100,
        fillPrice: 99,
      ),
      closeTo(100, 1e-9),
    );
    expect(
      ExecutionQualityMath.signedSlippageBps(
        side: ExecutionSide.short,
        referencePrice: 100,
        fillPrice: 101,
      ),
      closeTo(-100, 1e-9),
    );
  });

  test('fill ratio represents partial fills and rejects overfill', () {
    expect(
      ExecutionQualityMath.fillRatio(
        plannedQuantity: 10,
        filledQuantity: 4,
      ),
      0.4,
    );
    expect(
      () => ExecutionQualityMath.fillRatio(
        plannedQuantity: 10,
        filledQuantity: 10.1,
      ),
      throwsFormatException,
    );
  });

  test('no-chase blocks adverse long and short price movement', () {
    const policy = NoChasePolicy();

    final longDecision = policy.evaluate(
      side: ExecutionSide.long,
      executablePrice: 101.1,
      worstAcceptablePrice: 101,
      evaluatedAtUtc: now,
      validUntilUtc: now.add(const Duration(minutes: 1)),
    );
    final shortDecision = policy.evaluate(
      side: ExecutionSide.short,
      executablePrice: 98.9,
      worstAcceptablePrice: 99,
      evaluatedAtUtc: now,
      validUntilUtc: now.add(const Duration(minutes: 1)),
    );

    expect(longDecision.allowed, isFalse);
    expect(
      longDecision.reason,
      NoChaseDecisionReason.priceBeyondBoundary,
    );
    expect(shortDecision.allowed, isFalse);
    expect(
      shortDecision.reason,
      NoChaseDecisionReason.priceBeyondBoundary,
    );
  });

  test('no-chase accepts favorable prices inside the validity window', () {
    const policy = NoChasePolicy();

    expect(
      policy
          .evaluate(
            side: ExecutionSide.long,
            executablePrice: 99,
            worstAcceptablePrice: 101,
            evaluatedAtUtc: now,
            validUntilUtc: now.add(const Duration(minutes: 1)),
          )
          .allowed,
      isTrue,
    );
    expect(
      policy
          .evaluate(
            side: ExecutionSide.short,
            executablePrice: 101,
            worstAcceptablePrice: 99,
            evaluatedAtUtc: now,
            validUntilUtc: now.add(const Duration(minutes: 1)),
          )
          .allowed,
      isTrue,
    );
  });

  test('stale intent is rejected before price boundary evaluation', () {
    const policy = NoChasePolicy();
    final decision = policy.evaluate(
      side: ExecutionSide.long,
      executablePrice: 100,
      worstAcceptablePrice: 101,
      evaluatedAtUtc: now.add(const Duration(seconds: 61)),
      validUntilUtc: now.add(const Duration(seconds: 60)),
    );

    expect(decision.allowed, isFalse);
    expect(decision.reason, NoChaseDecisionReason.staleIntent);
  });

  test('planned estimated and confirmed costs remain distinct types', () {
    const planned = PlannedExecutionCosts(
      fees: 1,
      funding: 2,
      spread: 3,
      slippage: 4,
      latency: 5,
    );
    final estimated = EstimatedExecutionCosts(
      modelVersion: 'execution-quality/1.0',
      asOfUtc: now,
      evidenceQuality: ExecutionEvidenceQuality.conservative,
      fees: 1,
      funding: 2,
      spread: 3,
      slippage: 4,
      latency: 5,
    );
    const confirmed = ConfirmedExecutionCosts(
      entryFees: 1,
      exitFees: 1,
      funding: 2,
      spread: 3,
      slippage: 4,
    );

    planned.validate();
    estimated.validate();
    confirmed.validate();
    expect(planned.total, 15);
    expect(estimated.total, 15);
    expect(confirmed.total, 11);
  });

  test('execution lifecycle enforces UTC ordering with stable correlation id', () {
    final valid = ExecutionLifecycleTiming(
      correlationId: 'setup-1:attempt-1',
      decisionAtUtc: now,
      submitAtUtc: now.add(const Duration(milliseconds: 20)),
      acknowledgedAtUtc: now.add(const Duration(milliseconds: 40)),
      firstFillAtUtc: now.add(const Duration(milliseconds: 50)),
      finalFillAtUtc: now.add(const Duration(milliseconds: 80)),
    );
    valid.validate();

    final invalid = ExecutionLifecycleTiming(
      correlationId: 'setup-1:attempt-2',
      decisionAtUtc: now,
      submitAtUtc: now.add(const Duration(milliseconds: 50)),
      acknowledgedAtUtc: now.add(const Duration(milliseconds: 40)),
    );
    expect(invalid.validate, throwsFormatException);
  });
}
