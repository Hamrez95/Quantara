import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/strategy_lab/domain/strategy_promotion_models.dart';
import 'package:quantara_app/features/strategy_lab/domain/strategy_validation_models.dart';
import 'package:quantara_app/features/strategy_lab/domain/strategy_validation_stage_policy.dart';

void main() {
  test('tiny-risk canary requires system start and Capital Guardian', () {
    final packet = _healthyPacket();

    final startBlocked = StrategyValidationStagePolicy.evaluate(
      requestedStage: StrategyValidationStage.tinyRiskCanary,
      packet: packet,
      replayPassed: true,
      shadowPassed: true,
      paperPassed: true,
      systemStartEnabled: false,
      capitalGuardianAllowsNewRisk: true,
    );
    expect(startBlocked.allowed, isFalse);
    expect(
      startBlocked.blocks,
      contains(StrategyValidationStageBlock.systemStartDisabled),
    );

    final guardianBlocked = StrategyValidationStagePolicy.evaluate(
      requestedStage: StrategyValidationStage.tinyRiskCanary,
      packet: packet,
      replayPassed: true,
      shadowPassed: true,
      paperPassed: true,
      systemStartEnabled: true,
      capitalGuardianAllowsNewRisk: false,
    );
    expect(guardianBlocked.allowed, isFalse);
    expect(
      guardianBlocked.blocks,
      contains(StrategyValidationStageBlock.capitalGuardianBlocked),
    );
  });

  test('stages cannot skip replay, shadow or paper evidence', () {
    final packet = _healthyPacket();

    final decision = StrategyValidationStagePolicy.evaluate(
      requestedStage: StrategyValidationStage.tinyRiskCanary,
      packet: packet,
      replayPassed: false,
      shadowPassed: false,
      paperPassed: false,
      systemStartEnabled: true,
      capitalGuardianAllowsNewRisk: true,
    );

    expect(decision.allowed, isFalse);
    expect(
      decision.blocks,
      contains(StrategyValidationStageBlock.replayNotPassed),
    );
    expect(
      decision.blocks,
      contains(StrategyValidationStageBlock.shadowNotPassed),
    );
    expect(
      decision.blocks,
      contains(StrategyValidationStageBlock.paperNotPassed),
    );
  });

  test(
    'healthy evidence can become promotion-eligible without executing anything',
    () {
      final decision = StrategyValidationStagePolicy.evaluate(
        requestedStage: StrategyValidationStage.promotionEligible,
        packet: _healthyPacket(),
        replayPassed: true,
        shadowPassed: true,
        paperPassed: true,
        systemStartEnabled: true,
        capitalGuardianAllowsNewRisk: true,
      );

      expect(decision.allowed, isTrue);
      expect(decision.blocks, isEmpty);
    },
  );
}

StrategyPromotionPacket _healthyPacket() {
  final start = DateTime.utc(2026, 1, 1);
  final fold = StrategyValidationWindow(
    foldIndex: 1,
    trainingStartedAt: start,
    trainingEndedAt: DateTime.utc(2026, 2, 1),
    purgeStartedAt: DateTime.utc(2026, 2, 1),
    purgeEndedAt: DateTime.utc(2026, 2, 2),
    validationStartedAt: DateTime.utc(2026, 2, 2),
    validationEndedAt: DateTime.utc(2026, 3, 1),
    embargoStartedAt: DateTime.utc(2026, 3, 1),
    embargoEndedAt: DateTime.utc(2026, 3, 2),
  );
  return StrategyPromotionPacket(
    identity: const CalibrationIdentity(
      playbook: 'trend-pullback',
      playbookVersion: '2.0',
      regime: 'directionalTrend',
      timeframe: '1h',
    ),
    role: ValidationCandidateRole.challenger,
    provenance: ValidationDatasetProvenance(
      datasetId: 'point-in-time-bitunix',
      datasetVersion: '2026-06',
      configHash: 'abc123',
      sourceBuild: 'build-110',
      generatedAtUtc: DateTime.utc(2026, 7, 20),
      universeAsOfUtc: DateTime.utc(2026, 6, 30),
      survivorshipBiasControlled: true,
    ),
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
      forming: 250,
      armed: 150,
      triggered: 120,
      missed: 10,
      rejected: 20,
      period: Duration(days: 28),
    ),
    walkForwardFolds: [fold],
    lockedHoldout: LockedHoldoutWindow(
      startedAt: DateTime.utc(2026, 6, 1),
      endedAt: DateTime.utc(2026, 7, 1),
    ),
    calibration: StrategyCalibrationReport(
      sampleSize: 120,
      brierScore: 0.12,
      expectedCalibrationError: 0.03,
      buckets: const [],
      minimumSamplesForProbability: 100,
    ),
    bootstrap: const BootstrapExpectancySummary(
      sampleSize: 120,
      iterations: 2000,
      seed: 110,
      meanR: 0.3,
      p05R: 0.05,
      medianR: 0.3,
      p95R: 0.55,
      probabilityPositiveExpectancy: 0.97,
    ),
    parameterStability: const ParameterStabilityReport(
      bestParameter: 1,
      bestObjective: 1,
      nearBestCount: 3,
      totalTrials: 5,
      sharpOptimum: false,
    ),
    drift: const ValidationDriftSnapshot(
      baselineBrierScore: 0.12,
      currentBrierScore: 0.13,
      baselineCoverage: 0.8,
      currentCoverage: 0.78,
      baselineExecutionCostBps: 10,
      currentExecutionCostBps: 11,
      triggerLatencyP95: Duration(milliseconds: 300),
      triggerLatencySlo: Duration(milliseconds: 750),
    ),
    shadowStartedAtUtc: DateTime.utc(2026, 7, 1),
    shadowEndedAtUtc: DateTime.utc(2026, 7, 20),
    shadowTerminalSamples: 120,
    holdoutExpectancyR: 0.2,
    netExpectancyR: 0.3,
    featureFlagEnabled: true,
    strategySlot: const ChampionChallengerSlot(
      familyId: 'trend-pullback',
      championVersion: '1.0',
      challengerVersion: '2.0',
    ),
    managementPolicySlot: const ChampionChallengerSlot(
      familyId: 'trend-runner',
      championVersion: '1.0',
      challengerVersion: '1.1',
    ),
    baselineIds: const [
      'current-engine',
      'same-risk-random-timing',
      'buy-hold-context',
      'simple-trend',
    ],
    stressScenarioIds: const ['execution-cost-stress'],
  );
}
