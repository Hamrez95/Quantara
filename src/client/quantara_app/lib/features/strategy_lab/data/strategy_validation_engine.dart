import 'dart:math' as math;

import '../domain/strategy_validation_models.dart';

abstract final class StrategyValidationEngine {
  static const minimumCalibrationSamples = 100;

  static ({List<StrategyValidationWindow> folds, LockedHoldoutWindow holdout})
  purgedWalkForwardPlan({
    required DateTime startedAtUtc,
    required DateTime endedAtUtc,
    int foldCount = 4,
    Duration purge = const Duration(hours: 4),
    Duration embargo = const Duration(hours: 4),
    double holdoutFraction = 0.2,
  }) {
    if (!startedAtUtc.isUtc ||
        !endedAtUtc.isUtc ||
        !startedAtUtc.isBefore(endedAtUtc) ||
        foldCount < 2 ||
        foldCount > 8 ||
        purge.isNegative ||
        embargo.isNegative ||
        !holdoutFraction.isFinite ||
        holdoutFraction <= 0 ||
        holdoutFraction >= 0.5) {
      throw ArgumentError('Invalid walk-forward validation plan.');
    }

    final totalMicros = endedAtUtc.difference(startedAtUtc).inMicroseconds;
    final holdoutMicros = math.max(1, (totalMicros * holdoutFraction).round());
    final holdoutStart = endedAtUtc.subtract(
      Duration(microseconds: holdoutMicros),
    );
    final developmentMicros = holdoutStart
        .difference(startedAtUtc)
        .inMicroseconds;
    final validationWidth = developmentMicros ~/ (foldCount + 1);
    if (validationWidth <= purge.inMicroseconds + embargo.inMicroseconds + 2) {
      throw ArgumentError('Validation history is too short for purge/embargo.');
    }

    final folds = <StrategyValidationWindow>[];
    for (var index = 0; index < foldCount; index++) {
      final validationStart = startedAtUtc.add(
        Duration(microseconds: validationWidth * (index + 1)),
      );
      final validationEnd = index == foldCount - 1
          ? holdoutStart.subtract(embargo)
          : startedAtUtc
                .add(Duration(microseconds: validationWidth * (index + 2)))
                .subtract(embargo);
      final purgeStart = validationStart.subtract(purge);
      final trainingEnd = purgeStart;
      final embargoStart = validationEnd;
      final embargoEnd = validationEnd.add(embargo);
      if (!startedAtUtc.isBefore(trainingEnd) ||
          !validationStart.isBefore(validationEnd) ||
          embargoEnd.isAfter(holdoutStart)) {
        continue;
      }
      folds.add(
        StrategyValidationWindow(
          foldIndex: index + 1,
          trainingStartedAt: startedAtUtc,
          trainingEndedAt: trainingEnd,
          purgeStartedAt: purgeStart,
          purgeEndedAt: validationStart,
          validationStartedAt: validationStart,
          validationEndedAt: validationEnd,
          embargoStartedAt: embargoStart,
          embargoEndedAt: embargoEnd,
        ),
      );
    }
    if (folds.length < 2) {
      throw ArgumentError(
        'At least two purged walk-forward folds are required.',
      );
    }
    return (
      folds: List.unmodifiable(folds),
      holdout: LockedHoldoutWindow(
        startedAt: holdoutStart,
        endedAt: endedAtUtc,
      ),
    );
  }

  static StrategyCalibrationReport calibration(
    Iterable<ProbabilityCalibrationObservation> observations, {
    int bucketCount = 10,
    int minimumSamplesForProbability = minimumCalibrationSamples,
  }) {
    if (bucketCount < 2 ||
        bucketCount > 20 ||
        minimumSamplesForProbability < 20) {
      throw ArgumentError('Invalid calibration policy.');
    }
    final values = observations.toList(growable: false);
    if (values.any((item) => !item.isValid)) {
      throw ArgumentError('Calibration observations are invalid.');
    }
    if (values.isEmpty) {
      return StrategyCalibrationReport(
        sampleSize: 0,
        brierScore: 1,
        expectedCalibrationError: 1,
        buckets: const [],
        minimumSamplesForProbability: minimumSamplesForProbability,
      );
    }

    var brier = 0.0;
    final grouped = List.generate(
      bucketCount,
      (_) => <ProbabilityCalibrationObservation>[],
    );
    for (final item in values) {
      final actual = item.outcome ? 1.0 : 0.0;
      final error = item.predictedProbability - actual;
      brier += error * error;
      final index = math.min(
        bucketCount - 1,
        (item.predictedProbability * bucketCount).floor(),
      );
      grouped[index].add(item);
    }

    final buckets = <CalibrationBucket>[];
    var weightedCalibrationError = 0.0;
    for (var index = 0; index < bucketCount; index++) {
      final bucket = grouped[index];
      if (bucket.isEmpty) continue;
      final predicted =
          bucket.fold<double>(
            0,
            (sum, item) => sum + item.predictedProbability,
          ) /
          bucket.length;
      final observed =
          bucket.where((item) => item.outcome).length / bucket.length;
      weightedCalibrationError +=
          (predicted - observed).abs() * bucket.length / values.length;
      buckets.add(
        CalibrationBucket(
          lowerBound: index / bucketCount,
          upperBound: (index + 1) / bucketCount,
          sampleSize: bucket.length,
          meanPredictedProbability: predicted,
          observedFrequency: observed,
        ),
      );
    }

    return StrategyCalibrationReport(
      sampleSize: values.length,
      brierScore: brier / values.length,
      expectedCalibrationError: weightedCalibrationError,
      buckets: buckets,
      minimumSamplesForProbability: minimumSamplesForProbability,
    );
  }

  static BootstrapExpectancySummary bootstrapExpectancy(
    Iterable<double> rMultiples, {
    int iterations = 2000,
    int seed = 110,
  }) {
    final samples = rMultiples.toList(growable: false);
    if (samples.isEmpty ||
        samples.any((item) => !item.isFinite) ||
        iterations < 200 ||
        iterations > 20000) {
      throw ArgumentError('Invalid bootstrap expectancy input.');
    }
    final random = math.Random(seed);
    final means = <double>[];
    for (var iteration = 0; iteration < iterations; iteration++) {
      var sum = 0.0;
      for (var index = 0; index < samples.length; index++) {
        sum += samples[random.nextInt(samples.length)];
      }
      means.add(sum / samples.length);
    }
    means.sort();
    double percentile(double p) {
      final rawIndex = ((means.length - 1) * p).round();
      return means[rawIndex.clamp(0, means.length - 1)];
    }

    final mean =
        samples.fold<double>(0, (sum, item) => sum + item) / samples.length;
    return BootstrapExpectancySummary(
      sampleSize: samples.length,
      iterations: iterations,
      seed: seed,
      meanR: mean,
      p05R: percentile(0.05),
      medianR: percentile(0.5),
      p95R: percentile(0.95),
      probabilityPositiveExpectancy:
          means.where((value) => value > 0).length / means.length,
    );
  }

  static ParameterStabilityReport parameterStability(
    Iterable<ParameterTrial> trials, {
    double nearBestFraction = 0.9,
  }) {
    final values = trials.toList(growable: false)
      ..sort(
        (left, right) => left.parameterValue.compareTo(right.parameterValue),
      );
    if (values.length < 3 ||
        values.any(
          (item) => !item.parameterValue.isFinite || !item.objective.isFinite,
        ) ||
        !nearBestFraction.isFinite ||
        nearBestFraction <= 0.5 ||
        nearBestFraction > 1) {
      throw ArgumentError('Invalid parameter stability trials.');
    }
    final best = values.reduce(
      (left, right) => left.objective >= right.objective ? left : right,
    );
    final threshold = best.objective >= 0
        ? best.objective * nearBestFraction
        : best.objective / nearBestFraction;
    final nearBest = values
        .where((item) => item.objective >= threshold)
        .toList(growable: false);
    final bestIndex = values.indexOf(best);
    final leftNear =
        bestIndex > 0 && values[bestIndex - 1].objective >= threshold;
    final rightNear =
        bestIndex < values.length - 1 &&
        values[bestIndex + 1].objective >= threshold;
    final sharp = nearBest.length == 1 || (!leftNear && !rightNear);
    return ParameterStabilityReport(
      bestParameter: best.parameterValue,
      bestObjective: best.objective,
      nearBestCount: nearBest.length,
      totalTrials: values.length,
      sharpOptimum: sharp,
    );
  }
}
