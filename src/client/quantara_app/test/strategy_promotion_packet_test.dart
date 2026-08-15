import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/strategy_lab/data/strategy_promotion_packet_builder.dart';
import 'package:quantara_app/features/strategy_lab/data/strategy_validation_engine.dart';
import 'package:quantara_app/features/strategy_lab/domain/strategy_promotion_models.dart';
import 'package:quantara_app/features/strategy_lab/domain/strategy_validation_models.dart';

void main() {
  test('config hash is order independent and reproducible', () {
    final first = StrategyPromotionPacketBuilder.reproducibleConfigHash({
      'risk': 0.5,
      'symbols': ['BTCUSDT', 'ETHUSDT'],
      'nested': {'b': 2, 'a': 1},
    });
    final second = StrategyPromotionPacketBuilder.reproducibleConfigHash({
      'nested': {'a': 1, 'b': 2},
      'symbols': ['BTCUSDT', 'ETHUSDT'],
      'risk': 0.5,
    });

    expect(first, second);
    expect(first, hasLength(64));
  });

  test('small calibration sample forces score-only presentation', () {
    final packet = _packet(calibrationSamples: 40);

    expect(packet.presentationMode, SetupQualityPresentationMode.scoreOnly);
    expect(
      packet.downgradeReasons,
      contains(ValidationDowngradeReason.insufficientCalibrationSamples),
    );
    expect(packet.promotionEvidenceComplete, isFalse);
  });

  test(
    'calibration drift automatically downgrades probability to score-only',
    () {
      final packet = _packet(
        calibrationSamples: 120,
        drift: const ValidationDriftSnapshot(
          baselineBrierScore: 0.12,
          currentBrierScore: 0.22,
          baselineCoverage: 0.8,
          currentCoverage: 0.8,
          baselineExecutionCostBps: 10,
          currentExecutionCostBps: 10,
          triggerLatencyP95: Duration(milliseconds: 300),
          triggerLatencySlo: Duration(milliseconds: 750),
        ),
      );

      expect(packet.presentationMode, SetupQualityPresentationMode.scoreOnly);
      expect(
        packet.downgradeReasons,
        contains(ValidationDowngradeReason.calibrationDrift),
      );
    },
  );

  test('healthy mature evidence can expose calibrated probability', () {
    final packet = _packet(calibrationSamples: 120);

    expect(
      packet.presentationMode,
      SetupQualityPresentationMode.calibratedProbability,
    );
    expect(packet.downgradeReasons, isEmpty);
    expect(packet.reproducible, isTrue);
    expect(packet.promotionEvidenceComplete, isTrue);
  });

  test('missing challenger does not fake promotion completeness', () {
    final packet = _packet(
      calibrationSamples: 120,
      strategySlot: const ChampionChallengerSlot(
        familyId: 'trend-pullback',
        championVersion: '1.0',
      ),
    );

    expect(packet.strategySlot.hasChampion, isTrue);
    expect(packet.strategySlot.hasChallenger, isFalse);
    // A challenger slot may be empty while gathering evidence; the packet must
    // never invent challenger performance or mutate the champion automatically.
    expect(packet.role, ValidationCandidateRole.challenger);
  });

  test(
    'reproducible json keeps dataset, funnel, baselines and downgrade chain',
    () {
      final packet = _packet(calibrationSamples: 120);
      final json = StrategyPromotionPacketBuilder.toReproducibleJson(packet);

      expect((json['provenance']! as Map)['datasetId'], 'bitunix-history');
      expect((json['funnel']! as Map)['signalsPerWeek'], greaterThan(0));
      expect(json['baselines'], hasLength(4));
      expect(json['stressScenarios'], isNotEmpty);
      expect(json['promotionEvidenceComplete'], isTrue);
    },
  );
}

StrategyPromotionPacket _packet({
  required int calibrationSamples,
  ValidationDriftSnapshot drift = const ValidationDriftSnapshot(
    baselineBrierScore: 0.12,
    currentBrierScore: 0.13,
    baselineCoverage: 0.8,
    currentCoverage: 0.78,
    baselineExecutionCostBps: 10,
    currentExecutionCostBps: 11,
    triggerLatencyP95: Duration(milliseconds: 300),
    triggerLatencySlo: Duration(milliseconds: 750),
  ),
  ChampionChallengerSlot strategySlot = const ChampionChallengerSlot(
    familyId: 'trend-pullback',
    championVersion: '1.0',
    challengerVersion: '2.0',
  ),
}) {
  final start = DateTime.utc(2026, 1, 1);
  final plan = StrategyValidationEngine.purgedWalkForwardPlan(
    startedAtUtc: start,
    endedAtUtc: DateTime.utc(2026, 7, 1),
    foldCount: 4,
    purge: const Duration(hours: 12),
    embargo: const Duration(hours: 12),
    holdoutFraction: 0.2,
  );
  final calibration = StrategyValidationEngine.calibration(
    List.generate(
      calibrationSamples,
      (index) => ProbabilityCalibrationObservation(
        predictedProbability: 0.7,
        outcome: index % 10 < 7,
        atUtc: start.add(Duration(hours: index)),
      ),
    ),
  );
  final bootstrap = StrategyValidationEngine.bootstrapExpectancy(
    List.generate(120, (index) => index % 5 == 0 ? -0.4 : 0.8),
    iterations: 500,
    seed: 110,
  );
  final stability = StrategyValidationEngine.parameterStability(const [
    ParameterTrial(parameterValue: 0.5, objective: 0.91),
    ParameterTrial(parameterValue: 1.0, objective: 1.0),
    ParameterTrial(parameterValue: 1.5, objective: 0.95),
    ParameterTrial(parameterValue: 2.0, objective: 0.8),
  ]);

  return StrategyPromotionPacketBuilder.build(
    identity: const CalibrationIdentity(
      playbook: 'trend-pullback',
      playbookVersion: '2.0',
      regime: 'directionalTrend',
      timeframe: '1h',
    ),
    role: ValidationCandidateRole.challenger,
    datasetId: 'bitunix-history',
    datasetVersion: '2026-07-01',
    generatedAtUtc: DateTime.utc(2026, 7, 20),
    universeAsOfUtc: DateTime.utc(2026, 7, 1),
    survivorshipBiasControlled: true,
    config: const {'risk': 0.5, 'playbook': 'trend-pullback', 'version': '2.0'},
    sourceBuild: 'build-abc123',
    executionAssumptions: const ValidationExecutionAssumptions(
      feeBpsPerSide: 6,
      spreadBpsRoundTrip: 1,
      slippageBpsPerSide: 2,
      fundingBpsPerEightHours: 1,
      latencyPenaltyBps: 1,
      partialFillRatio: 0.9,
    ),
    funnel: const OpportunityFunnelMetrics(
      discovered: 500,
      forming: 240,
      armed: 150,
      triggered: 120,
      missed: 10,
      rejected: 20,
      period: Duration(days: 28),
    ),
    walkForwardFolds: plan.folds,
    lockedHoldout: plan.holdout,
    calibration: calibration,
    bootstrap: bootstrap,
    parameterStability: stability,
    drift: drift,
    shadowStartedAtUtc: DateTime.utc(2026, 7, 1),
    shadowEndedAtUtc: DateTime.utc(2026, 7, 20),
    shadowTerminalSamples: 120,
    holdoutExpectancyR: 0.25,
    netExpectancyR: 0.3,
    featureFlagEnabled: true,
    strategySlot: strategySlot,
    managementPolicySlot: const ChampionChallengerSlot(
      familyId: 'trend-runner',
      championVersion: '1.0',
      challengerVersion: '1.1',
    ),
  );
}
