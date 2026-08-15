import 'dart:collection';

import 'strategy_validation_models.dart';

enum SetupQualityPresentationMode { scoreOnly, calibratedProbability }

enum ValidationDowngradeReason {
  insufficientCalibrationSamples,
  calibrationDrift,
  coverageCollapse,
  executionCostDrift,
  latencySloBreach,
  holdoutNotPositive,
  shadowDurationTooShort,
  shadowSampleTooSmall,
  survivorshipBiasUncontrolled,
}

enum ValidationCandidateRole { champion, challenger }

final class CalibrationIdentity {
  const CalibrationIdentity({
    required this.playbook,
    required this.playbookVersion,
    required this.regime,
    required this.timeframe,
  });

  final String playbook;
  final String playbookVersion;
  final String regime;
  final String timeframe;

  String get key => '$playbook@$playbookVersion|$regime|$timeframe';
}

final class ValidationDatasetProvenance {
  const ValidationDatasetProvenance({
    required this.datasetId,
    required this.datasetVersion,
    required this.configHash,
    required this.sourceBuild,
    required this.generatedAtUtc,
    required this.universeAsOfUtc,
    required this.survivorshipBiasControlled,
  });

  final String datasetId;
  final String datasetVersion;
  final String configHash;
  final String sourceBuild;
  final DateTime generatedAtUtc;
  final DateTime universeAsOfUtc;
  final bool survivorshipBiasControlled;

  bool get valid =>
      datasetId.trim().isNotEmpty &&
      datasetVersion.trim().isNotEmpty &&
      configHash.trim().isNotEmpty &&
      sourceBuild.trim().isNotEmpty &&
      generatedAtUtc.isUtc &&
      universeAsOfUtc.isUtc &&
      !universeAsOfUtc.isAfter(generatedAtUtc);
}

final class ValidationExecutionAssumptions {
  const ValidationExecutionAssumptions({
    required this.feeBpsPerSide,
    required this.spreadBpsRoundTrip,
    required this.slippageBpsPerSide,
    required this.fundingBpsPerEightHours,
    required this.latencyPenaltyBps,
    required this.partialFillRatio,
  });

  final double feeBpsPerSide;
  final double spreadBpsRoundTrip;
  final double slippageBpsPerSide;
  final double fundingBpsPerEightHours;
  final double latencyPenaltyBps;
  final double partialFillRatio;

  bool get valid =>
      [
        feeBpsPerSide,
        spreadBpsRoundTrip,
        slippageBpsPerSide,
        fundingBpsPerEightHours,
        latencyPenaltyBps,
        partialFillRatio,
      ].every((value) => value.isFinite) &&
      feeBpsPerSide >= 0 &&
      spreadBpsRoundTrip >= 0 &&
      slippageBpsPerSide >= 0 &&
      latencyPenaltyBps >= 0 &&
      partialFillRatio > 0 &&
      partialFillRatio <= 1;
}

final class OpportunityFunnelMetrics {
  const OpportunityFunnelMetrics({
    required this.discovered,
    required this.forming,
    required this.armed,
    required this.triggered,
    required this.missed,
    required this.rejected,
    required this.period,
  });

  final int discovered;
  final int forming;
  final int armed;
  final int triggered;
  final int missed;
  final int rejected;
  final Duration period;

  bool get valid =>
      discovered >= 0 &&
      forming >= 0 &&
      armed >= 0 &&
      triggered >= 0 &&
      missed >= 0 &&
      rejected >= 0 &&
      period > Duration.zero &&
      forming <= discovered &&
      armed <= forming &&
      triggered <= armed;

  double get signalsPerWeek =>
      period.inSeconds <= 0 ? 0 : triggered * 604800 / period.inSeconds;

  double get missedOpportunityRate => armed == 0 ? 0 : missed / armed;
}

final class ValidationDriftSnapshot {
  const ValidationDriftSnapshot({
    required this.baselineBrierScore,
    required this.currentBrierScore,
    required this.baselineCoverage,
    required this.currentCoverage,
    required this.baselineExecutionCostBps,
    required this.currentExecutionCostBps,
    required this.triggerLatencyP95,
    required this.triggerLatencySlo,
  });

  final double baselineBrierScore;
  final double currentBrierScore;
  final double baselineCoverage;
  final double currentCoverage;
  final double baselineExecutionCostBps;
  final double currentExecutionCostBps;
  final Duration triggerLatencyP95;
  final Duration triggerLatencySlo;

  List<ValidationDowngradeReason> downgradeReasons({
    double maximumBrierIncrease = 0.05,
    double minimumCoverageRatio = 0.7,
    double maximumCostRatio = 1.5,
  }) {
    final reasons = <ValidationDowngradeReason>[];
    if (currentBrierScore > baselineBrierScore + maximumBrierIncrease) {
      reasons.add(ValidationDowngradeReason.calibrationDrift);
    }
    if (baselineCoverage > 0 &&
        currentCoverage / baselineCoverage < minimumCoverageRatio) {
      reasons.add(ValidationDowngradeReason.coverageCollapse);
    }
    if (baselineExecutionCostBps > 0 &&
        currentExecutionCostBps / baselineExecutionCostBps > maximumCostRatio) {
      reasons.add(ValidationDowngradeReason.executionCostDrift);
    }
    if (triggerLatencySlo > Duration.zero &&
        triggerLatencyP95 > triggerLatencySlo) {
      reasons.add(ValidationDowngradeReason.latencySloBreach);
    }
    return List.unmodifiable(reasons);
  }
}

final class ChampionChallengerSlot {
  const ChampionChallengerSlot({
    required this.familyId,
    required this.championVersion,
    this.challengerVersion,
  });

  final String familyId;
  final String championVersion;
  final String? challengerVersion;

  bool get hasChampion =>
      familyId.trim().isNotEmpty && championVersion.trim().isNotEmpty;
  bool get hasChallenger => challengerVersion?.trim().isNotEmpty ?? false;
}

final class StrategyPromotionPacket {
  StrategyPromotionPacket({
    required this.identity,
    required this.role,
    required this.provenance,
    required this.executionAssumptions,
    required this.funnel,
    required Iterable<StrategyValidationWindow> walkForwardFolds,
    required this.lockedHoldout,
    required this.calibration,
    required this.bootstrap,
    required this.parameterStability,
    required this.drift,
    required this.shadowStartedAtUtc,
    required this.shadowEndedAtUtc,
    required this.shadowTerminalSamples,
    required this.holdoutExpectancyR,
    required this.netExpectancyR,
    required this.featureFlagEnabled,
    required this.strategySlot,
    required this.managementPolicySlot,
    Iterable<String> baselineIds = const [],
    Iterable<String> stressScenarioIds = const [],
  }) : walkForwardFolds = UnmodifiableListView(
         walkForwardFolds.toList(growable: false),
       ),
       baselineIds = UnmodifiableListView(baselineIds.toList(growable: false)),
       stressScenarioIds = UnmodifiableListView(
         stressScenarioIds.toList(growable: false),
       );

  final CalibrationIdentity identity;
  final ValidationCandidateRole role;
  final ValidationDatasetProvenance provenance;
  final ValidationExecutionAssumptions executionAssumptions;
  final OpportunityFunnelMetrics funnel;
  final UnmodifiableListView<StrategyValidationWindow> walkForwardFolds;
  final LockedHoldoutWindow lockedHoldout;
  final StrategyCalibrationReport calibration;
  final BootstrapExpectancySummary bootstrap;
  final ParameterStabilityReport parameterStability;
  final ValidationDriftSnapshot drift;
  final DateTime shadowStartedAtUtc;
  final DateTime shadowEndedAtUtc;
  final int shadowTerminalSamples;
  final double holdoutExpectancyR;
  final double netExpectancyR;
  final bool featureFlagEnabled;
  final ChampionChallengerSlot strategySlot;
  final ChampionChallengerSlot managementPolicySlot;
  final UnmodifiableListView<String> baselineIds;
  final UnmodifiableListView<String> stressScenarioIds;

  Duration get shadowDuration =>
      shadowEndedAtUtc.difference(shadowStartedAtUtc);

  List<ValidationDowngradeReason> get downgradeReasons {
    final reasons = <ValidationDowngradeReason>[
      ...drift.downgradeReasons(),
      if (!calibration.probabilityEnabled)
        ValidationDowngradeReason.insufficientCalibrationSamples,
      if (holdoutExpectancyR <= 0) ValidationDowngradeReason.holdoutNotPositive,
      if (shadowDuration < const Duration(days: 14))
        ValidationDowngradeReason.shadowDurationTooShort,
      if (shadowTerminalSamples < calibration.minimumSamplesForProbability)
        ValidationDowngradeReason.shadowSampleTooSmall,
      if (!provenance.survivorshipBiasControlled)
        ValidationDowngradeReason.survivorshipBiasUncontrolled,
    ];
    return List.unmodifiable(reasons.toSet());
  }

  SetupQualityPresentationMode get presentationMode => downgradeReasons.isEmpty
      ? SetupQualityPresentationMode.calibratedProbability
      : SetupQualityPresentationMode.scoreOnly;

  bool get reproducible =>
      provenance.valid &&
      executionAssumptions.valid &&
      funnel.valid &&
      walkForwardFolds.isNotEmpty &&
      walkForwardFolds.every((fold) => fold.chronological) &&
      lockedHoldout.isValid;

  bool get promotionEvidenceComplete =>
      reproducible &&
      featureFlagEnabled &&
      strategySlot.hasChampion &&
      managementPolicySlot.hasChampion &&
      baselineIds.length >= 4 &&
      stressScenarioIds.isNotEmpty &&
      !parameterStability.sharpOptimum &&
      bootstrap.p05R > 0 &&
      netExpectancyR > 0 &&
      downgradeReasons.isEmpty;
}
