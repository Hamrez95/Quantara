import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/domain/bounded_execution_estimator.dart';
import 'package:quantara_app/features/auto_trade/domain/execution_quality_models.dart';

void main() {
  final now = DateTime.utc(2026, 8, 18, 8);

  ExecutionEstimatorObservation observation({
    required ExecutionOutcome outcome,
    double? slippageBps,
    int? ackMs,
    int? finalFillMs,
    int secondOffset = 0,
    bool finalized = true,
  }) => ExecutionEstimatorObservation(
    outcome: outcome,
    observedAtUtc: now.add(Duration(seconds: secondOffset)),
    signedSlippageBps: slippageBps,
    ackLatency: ackMs == null ? null : Duration(milliseconds: ackMs),
    finalFillLatency: finalFillMs == null
        ? null
        : Duration(milliseconds: finalFillMs),
    finalized: finalized,
  );

  test('tiny samples remain insufficient and do not invent probabilities', () {
    final estimator = BoundedExecutionEstimator(capacity: 8, minimumSamples: 4)
      ..add(
        observation(
          outcome: ExecutionOutcome.filled,
          slippageBps: 5,
          ackMs: 20,
          finalFillMs: 40,
        ),
      );

    final estimate = estimator.estimate(asOfUtc: now);

    expect(estimate.evidenceQuality, ExecutionEvidenceQuality.insufficient);
    expect(estimate.sampleCount, 1);
    expect(estimate.fullFillProbability, isNull);
    expect(estimate.anyFillProbability, isNull);
    expect(estimate.adverseSlippageP95Bps, isNull);
  });

  test('bounded window evicts oldest observations', () {
    final estimator = BoundedExecutionEstimator(capacity: 3, minimumSamples: 3);
    for (var index = 0; index < 4; index++) {
      estimator.add(
        observation(
          outcome: index == 0
              ? ExecutionOutcome.noFill
              : ExecutionOutcome.filled,
          slippageBps: index == 0 ? null : index.toDouble(),
          secondOffset: index,
        ),
      );
    }

    final estimate = estimator.estimate(asOfUtc: now);

    expect(estimator.sampleCount, 3);
    expect(estimate.sampleCount, 3);
    expect(estimate.fullFillProbability, 1);
    expect(estimate.anyFillProbability, 1);
  });

  test('observed estimate reports fill rates and bounded percentiles', () {
    final estimator = BoundedExecutionEstimator(capacity: 4, minimumSamples: 4)
      ..add(
        observation(
          outcome: ExecutionOutcome.filled,
          slippageBps: -2,
          ackMs: 10,
          finalFillMs: 30,
        ),
      )
      ..add(
        observation(
          outcome: ExecutionOutcome.partialFill,
          slippageBps: 4,
          ackMs: 20,
          finalFillMs: 40,
          secondOffset: 1,
        ),
      )
      ..add(
        observation(
          outcome: ExecutionOutcome.filled,
          slippageBps: 8,
          ackMs: 30,
          finalFillMs: 50,
          secondOffset: 2,
        ),
      )
      ..add(
        observation(
          outcome: ExecutionOutcome.noFill,
          ackMs: 40,
          secondOffset: 3,
        ),
      );

    final estimate = estimator.estimate(asOfUtc: now);

    expect(estimate.evidenceQuality, ExecutionEvidenceQuality.observed);
    expect(estimate.fullFillProbability, 0.5);
    expect(estimate.anyFillProbability, 0.75);
    expect(estimate.adverseSlippageP50Bps, 4);
    expect(estimate.adverseSlippageP95Bps, 8);
    expect(estimate.ackLatencyP50, const Duration(milliseconds: 20));
    expect(estimate.finalFillLatencyP95, const Duration(milliseconds: 50));
  });

  test('no-fill observations cannot carry fabricated slippage', () {
    expect(
      () => observation(
        outcome: ExecutionOutcome.noFill,
        slippageBps: 3,
      ).validate(),
      throwsFormatException,
    );
  });

  test('unresolved attempts cannot contaminate empirical fill rates', () {
    expect(
      () => observation(
        outcome: ExecutionOutcome.partialFill,
        slippageBps: 3,
        finalized: false,
      ).validate(),
      throwsFormatException,
    );
    expect(
      () => observation(
        outcome: ExecutionOutcome.planned,
        finalized: true,
      ).validate(),
      throwsFormatException,
    );
  });

  test('configuration rejects unbounded or impossible sample settings', () {
    expect(() => BoundedExecutionEstimator(capacity: 0), throwsFormatException);
    expect(
      () => BoundedExecutionEstimator(capacity: 4, minimumSamples: 5),
      throwsFormatException,
    );
  });
}
