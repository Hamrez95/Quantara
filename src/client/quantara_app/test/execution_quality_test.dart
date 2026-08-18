import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/domain/execution_quality.dart';

void main() {
  group('ExecutionPlan no-chase boundary', () {
    test('long rejects a gap above the maximum entry bound', () {
      final plan = ExecutionPlan(
        correlationId: 'long-1',
        side: ExecutionSide.long,
        decisionAtUtc: DateTime.utc(2026, 8, 18),
        referencePrice: 100,
        noChaseBoundPrice: 101,
        requestedQuantity: 2,
      );

      expect(plan.isExecutablePriceWithinNoChase(101), isTrue);
      expect(plan.isExecutablePriceWithinNoChase(101.01), isFalse);
    });

    test('short rejects a gap below the minimum entry bound', () {
      final plan = ExecutionPlan(
        correlationId: 'short-1',
        side: ExecutionSide.short,
        decisionAtUtc: DateTime.utc(2026, 8, 18),
        referencePrice: 100,
        noChaseBoundPrice: 99,
        requestedQuantity: 2,
      );

      expect(plan.isExecutablePriceWithinNoChase(99), isTrue);
      expect(plan.isExecutablePriceWithinNoChase(98.99), isFalse);
    });
  });

  group('execution quality measurement', () {
    test('long adverse fill produces positive signed slippage and drag', () {
      final decisionAt = DateTime.utc(2026, 8, 18, 8);
      final plan = ExecutionPlan(
        correlationId: 'long-fill',
        side: ExecutionSide.long,
        decisionAtUtc: decisionAt,
        referencePrice: 100,
        noChaseBoundPrice: 102,
        requestedQuantity: 2,
      );
      final confirmed = ConfirmedExecutionCost(
        correlationId: 'long-fill',
        outcome: ExecutionFillOutcome.filled,
        acknowledgedAtUtc: decisionAt.add(const Duration(milliseconds: 40)),
        firstFillAtUtc: decisionAt.add(const Duration(milliseconds: 80)),
        finalFillAtUtc: decisionAt.add(const Duration(milliseconds: 120)),
        filledQuantity: 2,
        orderQuantity: 2,
        weightedAverageFillPrice: 101,
        feesUsdt: 0.2,
        fundingUsdt: 0.1,
        ambiguous: false,
      );

      final measurement = measureExecutionQuality(
        plan: plan,
        confirmed: confirmed,
        plannedRiskPerUnit: 5,
      );

      expect(measurement.signedSlippagePrice, 1);
      expect(measurement.signedSlippageBps, closeTo(100, 1e-9));
      expect(measurement.slippageUsdt, 2);
      expect(measurement.slippageR, 0.2);
      expect(measurement.totalConfirmedDragUsdt, closeTo(2.3, 1e-9));
      expect(measurement.decisionToAckLatency, const Duration(milliseconds: 40));
      expect(
        measurement.decisionToFirstFillLatency,
        const Duration(milliseconds: 80),
      );
      expect(
        measurement.decisionToFinalFillLatency,
        const Duration(milliseconds: 120),
      );
      expect(measurement.fillRatio, 1);
      expect(measurement.ambiguous, isFalse);
    });

    test('short adverse fill uses the opposite price sign convention', () {
      final plan = ExecutionPlan(
        correlationId: 'short-fill',
        side: ExecutionSide.short,
        decisionAtUtc: DateTime.utc(2026, 8, 18, 8),
        referencePrice: 100,
        noChaseBoundPrice: 98,
        requestedQuantity: 3,
      );
      final confirmed = ConfirmedExecutionCost(
        correlationId: 'short-fill',
        outcome: ExecutionFillOutcome.filled,
        acknowledgedAtUtc: null,
        firstFillAtUtc: null,
        finalFillAtUtc: null,
        filledQuantity: 3,
        orderQuantity: 3,
        weightedAverageFillPrice: 99,
        feesUsdt: 0,
        fundingUsdt: 0,
        ambiguous: false,
      );

      final measurement = measureExecutionQuality(
        plan: plan,
        confirmed: confirmed,
      );

      expect(measurement.signedSlippagePrice, 1);
      expect(measurement.signedSlippageBps, closeTo(100, 1e-9));
      expect(measurement.slippageUsdt, 3);
    });

    test('price improvement remains negative rather than hidden', () {
      final plan = ExecutionPlan(
        correlationId: 'improved',
        side: ExecutionSide.long,
        decisionAtUtc: DateTime.utc(2026, 8, 18, 8),
        referencePrice: 100,
        noChaseBoundPrice: 102,
        requestedQuantity: 1,
      );
      final confirmed = ConfirmedExecutionCost(
        correlationId: 'improved',
        outcome: ExecutionFillOutcome.filled,
        acknowledgedAtUtc: null,
        firstFillAtUtc: null,
        finalFillAtUtc: null,
        filledQuantity: 1,
        orderQuantity: 1,
        weightedAverageFillPrice: 99.5,
        feesUsdt: 0,
        fundingUsdt: 0,
        ambiguous: false,
      );

      final measurement = measureExecutionQuality(
        plan: plan,
        confirmed: confirmed,
      );

      expect(measurement.signedSlippagePrice, -0.5);
      expect(measurement.signedSlippageBps, closeTo(-50, 1e-9));
      expect(measurement.totalConfirmedDragUsdt, -0.5);
    });

    test('partial and no-fill outcomes remain explicit', () {
      const partial = ConfirmedExecutionCost(
        correlationId: 'partial',
        outcome: ExecutionFillOutcome.partial,
        acknowledgedAtUtc: null,
        firstFillAtUtc: null,
        finalFillAtUtc: null,
        filledQuantity: 1,
        orderQuantity: 4,
        weightedAverageFillPrice: 100,
        feesUsdt: 0,
        fundingUsdt: 0,
        ambiguous: false,
      );
      const noFill = ConfirmedExecutionCost(
        correlationId: 'none',
        outcome: ExecutionFillOutcome.noFill,
        acknowledgedAtUtc: null,
        firstFillAtUtc: null,
        finalFillAtUtc: null,
        filledQuantity: 0,
        orderQuantity: 4,
        weightedAverageFillPrice: null,
        feesUsdt: 0,
        fundingUsdt: 0,
        ambiguous: false,
      );

      expect(partial.fillRatio, 0.25);
      expect(noFill.fillRatio, 0);
      expect(noFill.outcome, ExecutionFillOutcome.noFill);
    });

    test('ambiguous or mismatched truth does not manufacture slippage', () {
      final plan = ExecutionPlan(
        correlationId: 'planned',
        side: ExecutionSide.long,
        decisionAtUtc: DateTime.utc(2026, 8, 18, 8),
        referencePrice: 100,
        noChaseBoundPrice: 101,
        requestedQuantity: 1,
      );
      const confirmed = ConfirmedExecutionCost(
        correlationId: 'other',
        outcome: ExecutionFillOutcome.filled,
        acknowledgedAtUtc: null,
        firstFillAtUtc: null,
        finalFillAtUtc: null,
        filledQuantity: 1,
        orderQuantity: 1,
        weightedAverageFillPrice: 101,
        feesUsdt: 0,
        fundingUsdt: 0,
        ambiguous: false,
      );

      final measurement = measureExecutionQuality(
        plan: plan,
        confirmed: confirmed,
      );

      expect(measurement.signedSlippagePrice, isNull);
      expect(measurement.totalConfirmedDragUsdt, isNull);
      expect(measurement.ambiguous, isTrue);
    });
  });

  test('estimated probability is unavailable when evidence is insufficient', () {
    final estimate = EstimatedExecutionCost(
      modelVersion: 'execution-cost-v1',
      estimatedAtUtc: DateTime.utc(2026, 8, 18),
      spreadBps: 2,
      slippageBps: 3,
      feeBps: 4,
      fundingBps: 1,
      fillProbability: null,
      insufficientEvidence: true,
    );

    expect(estimate.totalEstimatedDragBps, 10);
    expect(estimate.hasUsableFillProbability, isFalse);
  });
}
