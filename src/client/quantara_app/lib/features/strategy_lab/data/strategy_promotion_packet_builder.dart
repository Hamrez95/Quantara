import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../domain/strategy_promotion_models.dart';
import '../domain/strategy_validation_models.dart';

abstract final class StrategyPromotionPacketBuilder {
  static String reproducibleConfigHash(Map<String, Object?> config) {
    final canonical = _canonicalize(config);
    return sha256.convert(utf8.encode(jsonEncode(canonical))).toString();
  }

  static StrategyPromotionPacket build({
    required CalibrationIdentity identity,
    required ValidationCandidateRole role,
    required String datasetId,
    required String datasetVersion,
    required DateTime generatedAtUtc,
    required DateTime universeAsOfUtc,
    required bool survivorshipBiasControlled,
    required Map<String, Object?> config,
    required String sourceBuild,
    required ValidationExecutionAssumptions executionAssumptions,
    required OpportunityFunnelMetrics funnel,
    required Iterable<StrategyValidationWindow> walkForwardFolds,
    required LockedHoldoutWindow lockedHoldout,
    required StrategyCalibrationReport calibration,
    required BootstrapExpectancySummary bootstrap,
    required ParameterStabilityReport parameterStability,
    required ValidationDriftSnapshot drift,
    required DateTime shadowStartedAtUtc,
    required DateTime shadowEndedAtUtc,
    required int shadowTerminalSamples,
    required double holdoutExpectancyR,
    required double netExpectancyR,
    required bool featureFlagEnabled,
    required ChampionChallengerSlot strategySlot,
    required ChampionChallengerSlot managementPolicySlot,
    Iterable<String> baselineIds = const [
      'current-engine',
      'same-risk-random-timing',
      'buy-hold-context',
      'simple-trend',
    ],
    Iterable<String> stressScenarioIds = const [
      'fee-spread-slippage-up',
      'latency-partial-fill-stress',
      'trade-order-bootstrap',
    ],
  }) {
    if (!generatedAtUtc.isUtc ||
        !universeAsOfUtc.isUtc ||
        !shadowStartedAtUtc.isUtc ||
        !shadowEndedAtUtc.isUtc ||
        shadowEndedAtUtc.isBefore(shadowStartedAtUtc) ||
        shadowTerminalSamples < 0 ||
        !holdoutExpectancyR.isFinite ||
        !netExpectancyR.isFinite) {
      throw ArgumentError(
        'Promotion packet timestamps or metrics are invalid.',
      );
    }
    return StrategyPromotionPacket(
      identity: identity,
      role: role,
      provenance: ValidationDatasetProvenance(
        datasetId: datasetId,
        datasetVersion: datasetVersion,
        configHash: reproducibleConfigHash(config),
        sourceBuild: sourceBuild,
        generatedAtUtc: generatedAtUtc,
        universeAsOfUtc: universeAsOfUtc,
        survivorshipBiasControlled: survivorshipBiasControlled,
      ),
      executionAssumptions: executionAssumptions,
      funnel: funnel,
      walkForwardFolds: walkForwardFolds,
      lockedHoldout: lockedHoldout,
      calibration: calibration,
      bootstrap: bootstrap,
      parameterStability: parameterStability,
      drift: drift,
      shadowStartedAtUtc: shadowStartedAtUtc,
      shadowEndedAtUtc: shadowEndedAtUtc,
      shadowTerminalSamples: shadowTerminalSamples,
      holdoutExpectancyR: holdoutExpectancyR,
      netExpectancyR: netExpectancyR,
      featureFlagEnabled: featureFlagEnabled,
      strategySlot: strategySlot,
      managementPolicySlot: managementPolicySlot,
      baselineIds: baselineIds,
      stressScenarioIds: stressScenarioIds,
    );
  }

  static Map<String, Object?> toReproducibleJson(
    StrategyPromotionPacket packet,
  ) {
    return {
      'schemaVersion': 1,
      'identity': {
        'key': packet.identity.key,
        'playbook': packet.identity.playbook,
        'playbookVersion': packet.identity.playbookVersion,
        'regime': packet.identity.regime,
        'timeframe': packet.identity.timeframe,
      },
      'role': packet.role.name,
      'provenance': {
        'datasetId': packet.provenance.datasetId,
        'datasetVersion': packet.provenance.datasetVersion,
        'configHash': packet.provenance.configHash,
        'sourceBuild': packet.provenance.sourceBuild,
        'generatedAtUtc': packet.provenance.generatedAtUtc.toIso8601String(),
        'universeAsOfUtc': packet.provenance.universeAsOfUtc.toIso8601String(),
        'survivorshipBiasControlled':
            packet.provenance.survivorshipBiasControlled,
      },
      'executionAssumptions': {
        'feeBpsPerSide': packet.executionAssumptions.feeBpsPerSide,
        'spreadBpsRoundTrip': packet.executionAssumptions.spreadBpsRoundTrip,
        'slippageBpsPerSide': packet.executionAssumptions.slippageBpsPerSide,
        'fundingBpsPerEightHours':
            packet.executionAssumptions.fundingBpsPerEightHours,
        'latencyPenaltyBps': packet.executionAssumptions.latencyPenaltyBps,
        'partialFillRatio': packet.executionAssumptions.partialFillRatio,
      },
      'funnel': {
        'discovered': packet.funnel.discovered,
        'forming': packet.funnel.forming,
        'armed': packet.funnel.armed,
        'triggered': packet.funnel.triggered,
        'missed': packet.funnel.missed,
        'rejected': packet.funnel.rejected,
        'periodSeconds': packet.funnel.period.inSeconds,
        'signalsPerWeek': packet.funnel.signalsPerWeek,
        'missedOpportunityRate': packet.funnel.missedOpportunityRate,
      },
      'walkForward': packet.walkForwardFolds
          .map(
            (fold) => {
              'foldIndex': fold.foldIndex,
              'trainingStartedAt': fold.trainingStartedAt.toIso8601String(),
              'trainingEndedAt': fold.trainingEndedAt.toIso8601String(),
              'purgeStartedAt': fold.purgeStartedAt.toIso8601String(),
              'purgeEndedAt': fold.purgeEndedAt.toIso8601String(),
              'validationStartedAt': fold.validationStartedAt.toIso8601String(),
              'validationEndedAt': fold.validationEndedAt.toIso8601String(),
              'embargoStartedAt': fold.embargoStartedAt.toIso8601String(),
              'embargoEndedAt': fold.embargoEndedAt.toIso8601String(),
            },
          )
          .toList(growable: false),
      'lockedHoldout': {
        'startedAt': packet.lockedHoldout.startedAt.toIso8601String(),
        'endedAt': packet.lockedHoldout.endedAt.toIso8601String(),
        'expectancyR': packet.holdoutExpectancyR,
      },
      'shadow': {
        'startedAtUtc': packet.shadowStartedAtUtc.toIso8601String(),
        'endedAtUtc': packet.shadowEndedAtUtc.toIso8601String(),
        'terminalSamples': packet.shadowTerminalSamples,
      },
      'calibration': {
        'sampleSize': packet.calibration.sampleSize,
        'brierScore': packet.calibration.brierScore,
        'expectedCalibrationError': packet.calibration.expectedCalibrationError,
        'probabilityEnabled': packet.calibration.probabilityEnabled,
      },
      'bootstrap': {
        'sampleSize': packet.bootstrap.sampleSize,
        'iterations': packet.bootstrap.iterations,
        'seed': packet.bootstrap.seed,
        'meanR': packet.bootstrap.meanR,
        'p05R': packet.bootstrap.p05R,
        'medianR': packet.bootstrap.medianR,
        'p95R': packet.bootstrap.p95R,
        'probabilityPositiveExpectancy':
            packet.bootstrap.probabilityPositiveExpectancy,
      },
      'parameterStability': {
        'bestParameter': packet.parameterStability.bestParameter,
        'bestObjective': packet.parameterStability.bestObjective,
        'nearBestCount': packet.parameterStability.nearBestCount,
        'totalTrials': packet.parameterStability.totalTrials,
        'sharpOptimum': packet.parameterStability.sharpOptimum,
      },
      'presentationMode': packet.presentationMode.name,
      'downgradeReasons': packet.downgradeReasons
          .map((reason) => reason.name)
          .toList(growable: false),
      'netExpectancyR': packet.netExpectancyR,
      'featureFlagEnabled': packet.featureFlagEnabled,
      'strategySlot': {
        'familyId': packet.strategySlot.familyId,
        'championVersion': packet.strategySlot.championVersion,
        'challengerVersion': packet.strategySlot.challengerVersion,
      },
      'managementPolicySlot': {
        'familyId': packet.managementPolicySlot.familyId,
        'championVersion': packet.managementPolicySlot.championVersion,
        'challengerVersion': packet.managementPolicySlot.challengerVersion,
      },
      'baselines': packet.baselineIds.toList(growable: false),
      'stressScenarios': packet.stressScenarioIds.toList(growable: false),
      'promotionEvidenceComplete': packet.promotionEvidenceComplete,
    };
  }

  static Object? _canonicalize(Object? value) {
    if (value is Map) {
      final entries =
          value.entries
              .map((entry) => MapEntry(entry.key.toString(), entry.value))
              .toList(growable: false)
            ..sort((left, right) => left.key.compareTo(right.key));
      return {
        for (final entry in entries) entry.key: _canonicalize(entry.value),
      };
    }
    if (value is Iterable) {
      return value.map(_canonicalize).toList(growable: false);
    }
    if (value is DateTime) return value.toUtc().toIso8601String();
    if (value is Enum) return value.name;
    return value;
  }
}
