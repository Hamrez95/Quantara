import 'dart:collection';

enum ValidationSegment { training, purge, validation, embargo, lockedHoldout }

final class StrategyValidationWindow {
  const StrategyValidationWindow({
    required this.foldIndex,
    required this.trainingStartedAt,
    required this.trainingEndedAt,
    required this.purgeStartedAt,
    required this.purgeEndedAt,
    required this.validationStartedAt,
    required this.validationEndedAt,
    required this.embargoStartedAt,
    required this.embargoEndedAt,
  });

  final int foldIndex;
  final DateTime trainingStartedAt;
  final DateTime trainingEndedAt;
  final DateTime purgeStartedAt;
  final DateTime purgeEndedAt;
  final DateTime validationStartedAt;
  final DateTime validationEndedAt;
  final DateTime embargoStartedAt;
  final DateTime embargoEndedAt;

  bool get chronological =>
      !trainingEndedAt.isAfter(purgeStartedAt) &&
      !purgeEndedAt.isAfter(validationStartedAt) &&
      !validationEndedAt.isAfter(embargoStartedAt);
}

final class LockedHoldoutWindow {
  const LockedHoldoutWindow({required this.startedAt, required this.endedAt});

  final DateTime startedAt;
  final DateTime endedAt;

  bool get isValid => startedAt.isBefore(endedAt);
}

final class ProbabilityCalibrationObservation {
  const ProbabilityCalibrationObservation({
    required this.predictedProbability,
    required this.outcome,
    required this.atUtc,
  });

  final double predictedProbability;
  final bool outcome;
  final DateTime atUtc;

  bool get isValid =>
      predictedProbability.isFinite &&
      predictedProbability >= 0 &&
      predictedProbability <= 1 &&
      atUtc.isUtc;
}

final class CalibrationBucket {
  const CalibrationBucket({
    required this.lowerBound,
    required this.upperBound,
    required this.sampleSize,
    required this.meanPredictedProbability,
    required this.observedFrequency,
  });

  final double lowerBound;
  final double upperBound;
  final int sampleSize;
  final double meanPredictedProbability;
  final double observedFrequency;
}

final class StrategyCalibrationReport {
  StrategyCalibrationReport({
    required this.sampleSize,
    required this.brierScore,
    required this.expectedCalibrationError,
    required Iterable<CalibrationBucket> buckets,
    required this.minimumSamplesForProbability,
  }) : buckets = UnmodifiableListView(buckets.toList(growable: false));

  final int sampleSize;
  final double brierScore;
  final double expectedCalibrationError;
  final UnmodifiableListView<CalibrationBucket> buckets;
  final int minimumSamplesForProbability;

  bool get probabilityEnabled => sampleSize >= minimumSamplesForProbability;
}

final class BootstrapExpectancySummary {
  const BootstrapExpectancySummary({
    required this.sampleSize,
    required this.iterations,
    required this.seed,
    required this.meanR,
    required this.p05R,
    required this.medianR,
    required this.p95R,
    required this.probabilityPositiveExpectancy,
  });

  final int sampleSize;
  final int iterations;
  final int seed;
  final double meanR;
  final double p05R;
  final double medianR;
  final double p95R;
  final double probabilityPositiveExpectancy;
}

final class TradeOrderMonteCarloSummary {
  const TradeOrderMonteCarloSummary({
    required this.sampleSize,
    required this.iterations,
    required this.seed,
    required this.medianMaximumDrawdownR,
    required this.p95MaximumDrawdownR,
    required this.worstMaximumDrawdownR,
  });

  final int sampleSize;
  final int iterations;
  final int seed;
  final double medianMaximumDrawdownR;
  final double p95MaximumDrawdownR;
  final double worstMaximumDrawdownR;
}

final class ValidationStressScenario {
  const ValidationStressScenario({
    required this.id,
    this.extraCostRPerTrade = 0,
    this.partialFillRatio = 1,
    this.missedFillRate = 0,
  });

  final String id;
  final double extraCostRPerTrade;
  final double partialFillRatio;
  final double missedFillRate;

  bool get valid =>
      id.trim().isNotEmpty &&
      extraCostRPerTrade.isFinite &&
      extraCostRPerTrade >= 0 &&
      partialFillRatio.isFinite &&
      partialFillRatio > 0 &&
      partialFillRatio <= 1 &&
      missedFillRate.isFinite &&
      missedFillRate >= 0 &&
      missedFillRate < 1;
}

final class ValidationStressResult {
  const ValidationStressResult({
    required this.scenarioId,
    required this.sampleSize,
    required this.effectiveTradeCount,
    required this.stressedExpectancyR,
    required this.stressedNetR,
  });

  final String scenarioId;
  final int sampleSize;
  final int effectiveTradeCount;
  final double stressedExpectancyR;
  final double stressedNetR;
}

final class ValidationBaselineEvidence {
  const ValidationBaselineEvidence({
    required this.currentEngineExpectancyR,
    required this.sameRiskRandomTimingExpectancyR,
    required this.buyHoldReturnPercent,
    required this.simpleTrendReturnPercent,
    required this.seed,
  });

  final double currentEngineExpectancyR;
  final double sameRiskRandomTimingExpectancyR;
  final double buyHoldReturnPercent;
  final double simpleTrendReturnPercent;
  final int seed;
}

final class ParameterTrial {
  const ParameterTrial({required this.parameterValue, required this.objective});

  final double parameterValue;
  final double objective;
}

final class ParameterStabilityReport {
  const ParameterStabilityReport({
    required this.bestParameter,
    required this.bestObjective,
    required this.nearBestCount,
    required this.totalTrials,
    required this.sharpOptimum,
  });

  final double bestParameter;
  final double bestObjective;
  final int nearBestCount;
  final int totalTrials;
  final bool sharpOptimum;
}

final class StrategyPromotionEvidence {
  StrategyPromotionEvidence({
    required this.datasetId,
    required this.datasetVersion,
    required this.configHash,
    required this.sourceBuild,
    required Iterable<StrategyValidationWindow> folds,
    required this.lockedHoldout,
    required this.calibration,
    required this.bootstrap,
    required this.parameterStability,
    required this.shadowDuration,
    required this.shadowTerminalSamples,
    required this.holdoutExpectancyR,
    required this.leakageDetected,
    Iterable<String> warnings = const [],
  }) : folds = UnmodifiableListView(folds.toList(growable: false)),
       warnings = UnmodifiableListView(warnings.toList(growable: false));

  final String datasetId;
  final String datasetVersion;
  final String configHash;
  final String sourceBuild;
  final UnmodifiableListView<StrategyValidationWindow> folds;
  final LockedHoldoutWindow lockedHoldout;
  final StrategyCalibrationReport calibration;
  final BootstrapExpectancySummary bootstrap;
  final ParameterStabilityReport parameterStability;
  final Duration shadowDuration;
  final int shadowTerminalSamples;
  final double holdoutExpectancyR;
  final bool leakageDetected;
  final UnmodifiableListView<String> warnings;

  bool get evidenceComplete =>
      datasetId.trim().isNotEmpty &&
      datasetVersion.trim().isNotEmpty &&
      configHash.trim().isNotEmpty &&
      sourceBuild.trim().isNotEmpty &&
      folds.isNotEmpty &&
      folds.every((fold) => fold.chronological) &&
      lockedHoldout.isValid;

  bool get eligibleForPromotionEvidence =>
      evidenceComplete &&
      !leakageDetected &&
      !parameterStability.sharpOptimum &&
      calibration.probabilityEnabled &&
      bootstrap.p05R > 0 &&
      holdoutExpectancyR > 0 &&
      shadowDuration >= const Duration(days: 14) &&
      shadowTerminalSamples >= calibration.minimumSamplesForProbability;
}
