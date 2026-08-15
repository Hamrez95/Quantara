import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/strategy_lab/data/strategy_validation_engine.dart';
import 'package:quantara_app/features/strategy_lab/domain/strategy_validation_models.dart';

void main() {
  test(
    'purged walk-forward plan keeps validation and locked holdout separated',
    () {
      final plan = StrategyValidationEngine.purgedWalkForwardPlan(
        startedAtUtc: DateTime.utc(2026, 1, 1),
        endedAtUtc: DateTime.utc(2026, 7, 1),
        foldCount: 4,
        purge: const Duration(hours: 12),
        embargo: const Duration(hours: 12),
        holdoutFraction: 0.2,
      );

      expect(plan.folds, hasLength(4));
      expect(plan.folds.every((fold) => fold.chronological), isTrue);
      for (final fold in plan.folds) {
        expect(fold.trainingEndedAt, fold.purgeStartedAt);
        expect(fold.purgeEndedAt, fold.validationStartedAt);
        expect(fold.validationEndedAt, fold.embargoStartedAt);
        expect(fold.embargoEndedAt.isAfter(plan.holdout.startedAt), isFalse);
      }
      expect(plan.holdout.isValid, isTrue);
    },
  );

  test(
    'calibration reports Brier score and keeps probability disabled on small samples',
    () {
      final observations = List.generate(
        40,
        (index) => ProbabilityCalibrationObservation(
          predictedProbability: index.isEven ? 0.8 : 0.2,
          outcome: index.isEven,
          atUtc: DateTime.utc(2026, 1, 1).add(Duration(hours: index)),
        ),
      );

      final report = StrategyValidationEngine.calibration(observations);

      expect(report.sampleSize, 40);
      expect(report.brierScore, closeTo(0.04, 0.000001));
      expect(report.expectedCalibrationError, closeTo(0.2, 0.000001));
      expect(report.probabilityEnabled, isFalse);
    },
  );

  test(
    'calibration enables probability only after the configured sample floor',
    () {
      final observations = List.generate(
        StrategyValidationEngine.minimumCalibrationSamples,
        (index) => ProbabilityCalibrationObservation(
          predictedProbability: 0.7,
          outcome: index < 70,
          atUtc: DateTime.utc(2026, 1, 1).add(Duration(hours: index)),
        ),
      );

      final report = StrategyValidationEngine.calibration(observations);

      expect(report.probabilityEnabled, isTrue);
      expect(report.brierScore, greaterThanOrEqualTo(0));
      expect(report.brierScore, lessThanOrEqualTo(1));
    },
  );

  test('bootstrap is deterministic for the same seed', () {
    const rMultiples = [1.2, -1.0, 2.1, 0.4, 1.5, -0.7, 0.8, 1.1];

    final first = StrategyValidationEngine.bootstrapExpectancy(
      rMultiples,
      iterations: 500,
      seed: 42,
    );
    final second = StrategyValidationEngine.bootstrapExpectancy(
      rMultiples,
      iterations: 500,
      seed: 42,
    );

    expect(first.p05R, second.p05R);
    expect(first.medianR, second.medianR);
    expect(first.p95R, second.p95R);
    expect(
      first.probabilityPositiveExpectancy,
      second.probabilityPositiveExpectancy,
    );
  });

  test('parameter stability rejects a sharp isolated optimum', () {
    final report = StrategyValidationEngine.parameterStability(const [
      ParameterTrial(parameterValue: 0.5, objective: 0.2),
      ParameterTrial(parameterValue: 1.0, objective: 1.0),
      ParameterTrial(parameterValue: 1.5, objective: 0.25),
      ParameterTrial(parameterValue: 2.0, objective: 0.22),
    ]);

    expect(report.bestParameter, 1.0);
    expect(report.sharpOptimum, isTrue);
  });

  test('parameter stability accepts a broad near-best plateau', () {
    final report = StrategyValidationEngine.parameterStability(const [
      ParameterTrial(parameterValue: 0.5, objective: 0.86),
      ParameterTrial(parameterValue: 1.0, objective: 0.95),
      ParameterTrial(parameterValue: 1.5, objective: 1.0),
      ParameterTrial(parameterValue: 2.0, objective: 0.94),
      ParameterTrial(parameterValue: 2.5, objective: 0.82),
    ]);

    expect(report.nearBestCount, 3);
    expect(report.sharpOptimum, isFalse);
  });
}
