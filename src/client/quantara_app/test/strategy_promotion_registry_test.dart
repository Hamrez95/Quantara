import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/strategy_lab/data/platform_strategy_promotion_registry_store.dart';
import 'package:quantara_app/features/strategy_lab/data/strategy_promotion_packet_builder.dart';
import 'package:quantara_app/features/strategy_lab/data/strategy_validation_engine.dart';
import 'package:quantara_app/features/strategy_lab/domain/strategy_promotion_models.dart';
import 'package:quantara_app/features/strategy_lab/domain/strategy_promotion_registry.dart';
import 'package:quantara_app/features/strategy_lab/domain/strategy_validation_models.dart';

void main() {
  test('AI can propose a challenger but cannot promote it', () {
    final registry = StrategyPromotionRegistry.empty();
    final candidate = _identity('2.0');

    registry.proposeChallenger(
      eventId: 'proposal-1',
      challenger: candidate,
      evidenceIds: const ['evidence:research-1'],
      recordedAtUtc: DateTime.utc(2026, 8, 20),
    );

    final snapshot = registry.snapshot(candidate.slotId);
    expect(snapshot.champion, isNull);
    expect(snapshot.challenger?.key, candidate.key);
    expect(snapshot.liveEntriesAllowed, isFalse);
    expect(
      () => registry.promote(
        eventId: 'promotion-ai',
        candidate: candidate,
        evidence: _packet('2.0', calibrationSamples: 120),
        targetStage: StrategyPromotionStage.shadowEligible,
        evidenceIds: const ['evidence:validation-1'],
        recordedAtUtc: DateTime.utc(2026, 8, 21),
        actor: StrategyPromotionActor.aiAdvisor,
      ),
      throwsStateError,
    );
  });

  test('small-sample evidence cannot promote beyond Shadow', () {
    final registry = StrategyPromotionRegistry.empty();
    final candidate = _identity('2.0');
    registry.proposeChallenger(
      eventId: 'proposal-1',
      challenger: candidate,
      evidenceIds: const ['evidence:research-1'],
      recordedAtUtc: DateTime.utc(2026, 8, 20),
      actor: StrategyPromotionActor.deterministicPolicy,
    );

    registry.promote(
      eventId: 'shadow-1',
      candidate: candidate,
      evidence: _packet('2.0', calibrationSamples: 40),
      targetStage: StrategyPromotionStage.shadowEligible,
      evidenceIds: const ['evidence:walk-forward-1'],
      recordedAtUtc: DateTime.utc(2026, 8, 21),
    );

    expect(
      () => registry.promote(
        eventId: 'paper-1',
        candidate: candidate,
        evidence: _packet('2.0', calibrationSamples: 40),
        targetStage: StrategyPromotionStage.paperEligible,
        evidenceIds: const ['evidence:tiny-sample'],
        recordedAtUtc: DateTime.utc(2026, 8, 22),
      ),
      throwsStateError,
    );
    expect(registry.snapshot(candidate.slotId).liveEntriesAllowed, isFalse);
  });

  test('healthy evidence promotes stepwise and never skips a stage', () {
    final registry = StrategyPromotionRegistry.empty();
    final candidate = _identity('1.0');
    final packet = _packet('1.0', calibrationSamples: 120);

    expect(
      () => registry.promote(
        eventId: 'skip-paper',
        candidate: candidate,
        evidence: packet,
        targetStage: StrategyPromotionStage.paperEligible,
        evidenceIds: const ['evidence:complete'],
        recordedAtUtc: DateTime.utc(2026, 8, 20),
      ),
      throwsStateError,
    );

    _promoteToCapped(registry, candidate, packet);

    final snapshot = registry.snapshot(candidate.slotId);
    expect(snapshot.champion?.key, candidate.key);
    expect(snapshot.championStage, StrategyPromotionStage.cappedCanaryEligible);
    expect(snapshot.liveEntriesAllowed, isTrue);
  });

  test(
    'live drift quarantines new entries without changing champion identity',
    () {
      final registry = StrategyPromotionRegistry.empty();
      final candidate = _identity('1.0');
      _promoteToCapped(
        registry,
        candidate,
        _packet('1.0', calibrationSamples: 120),
      );

      registry.recordDrift(
        eventId: 'drift-1',
        slotId: candidate.slotId,
        reasons: const [ValidationDowngradeReason.calibrationDrift],
        evidenceIds: const ['evidence:drift-1'],
        recordedAtUtc: DateTime.utc(2026, 8, 24),
      );

      final quarantined = registry.snapshot(candidate.slotId);
      expect(quarantined.champion?.key, candidate.key);
      expect(quarantined.driftAction, StrategyDriftAction.shadowOnly);
      expect(quarantined.liveEntriesAllowed, isFalse);
      expect(
        quarantined.toExplanationJson()['reasonCode'],
        contains('calibrationDrift'),
      );
    },
  );

  test('prior certified champion rolls back deterministically', () {
    final registry = StrategyPromotionRegistry.empty();
    final v1 = _identity('1.0');
    _promoteToCapped(registry, v1, _packet('1.0', calibrationSamples: 120));

    final v2 = _identity('2.0');
    registry.proposeChallenger(
      eventId: 'proposal-v2',
      challenger: v2,
      evidenceIds: const ['evidence:v2-research'],
      recordedAtUtc: DateTime.utc(2026, 8, 24, 1),
      actor: StrategyPromotionActor.deterministicPolicy,
    );
    registry.promote(
      eventId: 'autonomous-v2',
      candidate: v2,
      evidence: _packet('2.0', calibrationSamples: 120),
      targetStage: StrategyPromotionStage.autonomousEligible,
      evidenceIds: const ['evidence:v2-certified'],
      recordedAtUtc: DateTime.utc(2026, 8, 24, 2),
    );

    expect(registry.snapshot(v1.slotId).champion?.key, v2.key);

    registry.rollback(
      eventId: 'rollback-v1',
      slotId: v1.slotId,
      evidenceIds: const ['evidence:rollback-anomaly'],
      recordedAtUtc: DateTime.utc(2026, 8, 24, 3),
    );

    final rolledBack = registry.snapshot(v1.slotId);
    expect(rolledBack.champion?.key, v1.key);
    expect(
      rolledBack.championStage,
      StrategyPromotionStage.cappedCanaryEligible,
    );
    expect(rolledBack.liveEntriesAllowed, isTrue);
  });

  test('versioned durable payload restores identical append-only history', () {
    final registry = StrategyPromotionRegistry.empty();
    final candidate = _identity('1.0');
    _promoteToCapped(
      registry,
      candidate,
      _packet('1.0', calibrationSamples: 120),
    );
    registry.recordDrift(
      eventId: 'drift-1',
      slotId: candidate.slotId,
      reasons: const [ValidationDowngradeReason.executionCostDrift],
      evidenceIds: const ['evidence:execution-cost'],
      recordedAtUtc: DateTime.utc(2026, 8, 24),
    );

    final payload = StrategyPromotionRegistryCodec.encode(registry);
    final restored = StrategyPromotionRegistryCodec.decode(payload);

    expect(restored.events.length, registry.events.length);
    expect(
      restored.events.map((event) => event.eventId),
      registry.events.map((event) => event.eventId),
    );
    expect(
      restored.snapshot(candidate.slotId).toExplanationJson(),
      registry.snapshot(candidate.slotId).toExplanationJson(),
    );
  });

  test('duplicate append identity and backwards time fail closed', () {
    final registry = StrategyPromotionRegistry.empty();
    final candidate = _identity('1.0');
    registry.proposeChallenger(
      eventId: 'proposal-1',
      challenger: candidate,
      evidenceIds: const ['evidence:one'],
      recordedAtUtc: DateTime.utc(2026, 8, 20),
    );

    expect(
      () => registry.proposeChallenger(
        eventId: 'proposal-1',
        challenger: candidate,
        evidenceIds: const ['evidence:two'],
        recordedAtUtc: DateTime.utc(2026, 8, 21),
      ),
      throwsStateError,
    );
    expect(
      () => registry.proposeChallenger(
        eventId: 'proposal-2',
        challenger: candidate,
        evidenceIds: const ['evidence:two'],
        recordedAtUtc: DateTime.utc(2026, 8, 19),
      ),
      throwsStateError,
    );
  });
}

void _promoteToCapped(
  StrategyPromotionRegistry registry,
  StrategyRuntimeIdentity candidate,
  StrategyPromotionPacket packet,
) {
  final base = DateTime.utc(2026, 8, 20);
  registry.promote(
    eventId: '${candidate.strategyVersion}-shadow',
    candidate: candidate,
    evidence: packet,
    targetStage: StrategyPromotionStage.shadowEligible,
    evidenceIds: const ['evidence:walk-forward'],
    recordedAtUtc: base,
  );
  registry.promote(
    eventId: '${candidate.strategyVersion}-paper',
    candidate: candidate,
    evidence: packet,
    targetStage: StrategyPromotionStage.paperEligible,
    evidenceIds: const ['evidence:shadow'],
    recordedAtUtc: base.add(const Duration(hours: 1)),
  );
  registry.promote(
    eventId: '${candidate.strategyVersion}-capped',
    candidate: candidate,
    evidence: packet,
    targetStage: StrategyPromotionStage.cappedCanaryEligible,
    evidenceIds: const ['evidence:paper'],
    recordedAtUtc: base.add(const Duration(hours: 2)),
  );
}

StrategyRuntimeIdentity _identity(String version) {
  final configHash = StrategyPromotionPacketBuilder.reproducibleConfigHash({
    'risk': 0.5,
    'playbook': 'trend-pullback',
    'version': version,
  });
  return StrategyRuntimeIdentity(
    slotId: 'trend-pullback|directionalTrend',
    strategyId: 'trend-pullback',
    strategyVersion: version,
    featureSetVersion: 'features/3',
    regimeClassifierVersion: 'regime/2',
    rankingPolicyVersion: 'ranking/2',
    riskPolicyVersion: 'risk/3',
    allocatorPolicyVersion: 'allocator/2',
    configHash: configHash,
    sourceBuild: 'build-$version',
  );
}

StrategyPromotionPacket _packet(
  String version, {
  required int calibrationSamples,
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
    seed: 197,
  );
  final stability = StrategyValidationEngine.parameterStability(const [
    ParameterTrial(parameterValue: 0.5, objective: 0.91),
    ParameterTrial(parameterValue: 1.0, objective: 1.0),
    ParameterTrial(parameterValue: 1.5, objective: 0.95),
    ParameterTrial(parameterValue: 2.0, objective: 0.8),
  ]);
  final config = <String, Object?>{
    'risk': 0.5,
    'playbook': 'trend-pullback',
    'version': version,
  };

  return StrategyPromotionPacketBuilder.build(
    identity: CalibrationIdentity(
      playbook: 'trend-pullback',
      playbookVersion: version,
      regime: 'directionalTrend',
      timeframe: '1h',
    ),
    role: ValidationCandidateRole.challenger,
    datasetId: 'bitunix-history',
    datasetVersion: '2026-07-01',
    generatedAtUtc: DateTime.utc(2026, 7, 20),
    universeAsOfUtc: DateTime.utc(2026, 7, 1),
    survivorshipBiasControlled: true,
    config: config,
    sourceBuild: 'build-$version',
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
    shadowTerminalSamples: calibrationSamples,
    holdoutExpectancyR: 0.25,
    netExpectancyR: 0.3,
    featureFlagEnabled: true,
    strategySlot: ChampionChallengerSlot(
      familyId: 'trend-pullback',
      championVersion: '1.0',
      challengerVersion: version,
    ),
    managementPolicySlot: const ChampionChallengerSlot(
      familyId: 'trend-runner',
      championVersion: '1.0',
      challengerVersion: '1.1',
    ),
  );
}
