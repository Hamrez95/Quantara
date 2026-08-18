import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/autonomy/domain/autonomy_certification.dart';
import 'package:quantara_app/features/autonomy/domain/autonomy_soak_certification.dart';

void main() {
  const versions = AutonomyCertificationVersions(
    buildCommit: 'abc123',
    strategyVersion: 'strategy/1',
    rankingVersion: 'ranking/1',
    riskVersion: 'risk/1',
    allocatorVersion: 'allocator/1',
    executionVersion: 'execution/1',
    adapterVersion: 'exchange-adapter/1',
  );
  const reconciled = AutonomyReconciliationEvidence(
    accountReconciled: true,
    ordersReconciled: true,
    positionsReconciled: true,
    journalReconciled: true,
  );

  AutonomyCertificationResult certification({
    required String faultCode,
    bool passed = true,
  }) {
    final observations = <AutonomyInvariantObservation>[];
    for (final invariant in AutonomyStopShipInvariant.values) {
      final failed =
          !passed && invariant == AutonomyStopShipInvariant.duplicateLiveOrder;
      observations.add(
        AutonomyInvariantObservation(
          invariant: invariant,
          passed: !failed,
          evidenceIds: failed ? ['invariant:$faultCode'] : const [],
        ),
      );
    }
    return AutonomyCertificationGate.evaluate(
      scenario: AutonomyFaultScenario(
        version: 'fault/1',
        seed: faultCode.length,
        category: AutonomyFaultCategory.privateExecution,
        faultCode: faultCode,
      ),
      observations: observations,
    );
  }

  AutonomySoakMetrics metrics({required AutonomySoakPhase phase}) {
    final paper = phase == AutonomySoakPhase.paper;
    return AutonomySoakMetrics(
      elapsedSeconds: 3600,
      eventSamples: 10000,
      candidateSamples: 120,
      tradeSamples: paper ? 20 : 0,
      faultSamples: 2,
      executionQualitySamples: paper ? 20 : 0,
      meanAbsSlippageBps: paper ? 3 : 0,
      latencyP50Ms: 5,
      latencyP95Ms: 12,
      latencyP99Ms: 20,
      maxQueueDepth: 8,
      reconnectCount: 4,
    );
  }

  AutonomySoakRunEvidence run({
    required String id,
    required AutonomySoakPhase phase,
    bool invariantFailure = false,
    AutonomyReconciliationEvidence? reconciliation,
    bool cleanupPassed = true,
    bool rollbackPassed = true,
    int supervisorAnomalyCount = 0,
    List<String> evidenceIds = const [],
  }) {
    return AutonomySoakRunEvidence(
      runId: id,
      phase: phase,
      versions: versions,
      faultScheduleVersion: 'fault-schedule/1',
      seed: phase.index,
      regimeSampleCounts: const {'trend': 40, 'range': 40, 'volatile': 40},
      metrics: metrics(phase: phase),
      invariantResults: [
        certification(faultCode: '$id-a'),
        certification(faultCode: '$id-b', passed: !invariantFailure),
      ],
      reconciliation: reconciliation ?? reconciled,
      cleanupPassed: cleanupPassed,
      rollbackPassed: rollbackPassed,
      supervisorAnomalyCount: supervisorAnomalyCount,
      supervisorEvidenceIds: evidenceIds,
    );
  }

  List<AutonomySoakRunEvidence> prerequisiteRuns() {
    return [
      run(id: 'fixture-1', phase: AutonomySoakPhase.deterministicFixture),
      run(id: 'replay-1', phase: AutonomySoakPhase.acceleratedReplay),
      run(id: 'shadow-1', phase: AutonomySoakPhase.shadow),
      run(id: 'paper-1', phase: AutonomySoakPhase.paper),
    ];
  }

  test('all pre-canary phases unlock promotion only when evidence is safe', () {
    final result = AutonomySoakCertificationGate.evaluate(
      runs: prerequisiteRuns(),
    );

    expect(result.prerequisitePhasesPresent, isTrue);
    expect(result.stopShip, isFalse);
    expect(result.promotionEligible, isTrue);
    expect(result.cappedAutoLocked, isFalse);
    expect(result.failedRunIds, isEmpty);
  });

  test('reconciliation failure keeps Capped Auto locked with evidence IDs', () {
    const failedReconciliation = AutonomyReconciliationEvidence(
      accountReconciled: true,
      ordersReconciled: false,
      positionsReconciled: true,
      journalReconciled: true,
    );
    final runs = prerequisiteRuns();
    runs[3] = run(
      id: 'paper-1',
      phase: AutonomySoakPhase.paper,
      reconciliation: failedReconciliation,
      evidenceIds: const ['supervisor:reconciliation-drift'],
    );

    final result = AutonomySoakCertificationGate.evaluate(runs: runs);

    expect(result.stopShip, isTrue);
    expect(result.promotionEligible, isFalse);
    expect(result.cappedAutoLocked, isTrue);
    expect(result.failedRunIds, ['paper-1']);
  });

  test('stop-ship run without Supervisor evidence is rejected', () {
    final invalid = run(
      id: 'paper-failed',
      phase: AutonomySoakPhase.paper,
      invariantFailure: true,
    );

    expect(invalid.validate, throwsFormatException);
  });

  test('Supervisor anomaly requires evidence even when invariants pass', () {
    final invalid = run(
      id: 'shadow-anomaly',
      phase: AutonomySoakPhase.shadow,
      supervisorAnomalyCount: 1,
    );

    expect(invalid.validate, throwsFormatException);
  });

  test('certification requires all four pre-canary phases', () {
    final incomplete = prerequisiteRuns()..removeAt(2);

    expect(
      () => AutonomySoakCertificationGate.evaluate(runs: incomplete),
      throwsStateError,
    );
  });

  test('duplicate run IDs are rejected', () {
    expect(
      () => AutonomySoakCertificationGate.evaluate(
        runs: [
          run(id: 'same-id', phase: AutonomySoakPhase.deterministicFixture),
          run(id: 'same-id', phase: AutonomySoakPhase.acceleratedReplay),
          run(id: 'shadow-1', phase: AutonomySoakPhase.shadow),
          run(id: 'paper-1', phase: AutonomySoakPhase.paper),
        ],
      ),
      throwsStateError,
    );
  });

  test('Paper evidence requires execution and quality samples', () {
    const invalid = AutonomySoakMetrics(
      elapsedSeconds: 60,
      eventSamples: 100,
      candidateSamples: 10,
      tradeSamples: 0,
      faultSamples: 2,
      executionQualitySamples: 0,
      meanAbsSlippageBps: 0,
      latencyP50Ms: 1,
      latencyP95Ms: 2,
      latencyP99Ms: 3,
      maxQueueDepth: 1,
      reconnectCount: 0,
    );

    expect(
      () => invalid.validate(phase: AutonomySoakPhase.paper),
      throwsFormatException,
    );
  });

  test('latency evidence must be finite and percentile ordered', () {
    const invalid = AutonomySoakMetrics(
      elapsedSeconds: 60,
      eventSamples: 100,
      candidateSamples: 10,
      tradeSamples: 1,
      faultSamples: 2,
      executionQualitySamples: 1,
      meanAbsSlippageBps: 1,
      latencyP50Ms: 5,
      latencyP95Ms: 4,
      latencyP99Ms: 3,
      maxQueueDepth: 1,
      reconnectCount: 0,
    );

    expect(
      () => invalid.validate(phase: AutonomySoakPhase.paper),
      throwsFormatException,
    );
  });

  test('every regime requires a positive sample count', () {
    final invalid = AutonomySoakRunEvidence(
      runId: 'shadow-invalid-regime',
      phase: AutonomySoakPhase.shadow,
      versions: versions,
      faultScheduleVersion: 'fault-schedule/1',
      seed: 1,
      regimeSampleCounts: const {'trend': 0},
      metrics: metrics(phase: AutonomySoakPhase.shadow),
      invariantResults: [
        certification(faultCode: 'a'),
        certification(faultCode: 'b'),
      ],
      reconciliation: reconciled,
      cleanupPassed: true,
      rollbackPassed: true,
      supervisorAnomalyCount: 0,
    );

    expect(invalid.validate, throwsFormatException);
  });

  test('fault sample count must match machine-asserted invariant results', () {
    final invalid = AutonomySoakRunEvidence(
      runId: 'shadow-missing-invariant-result',
      phase: AutonomySoakPhase.shadow,
      versions: versions,
      faultScheduleVersion: 'fault-schedule/1',
      seed: 1,
      regimeSampleCounts: const {'trend': 10},
      metrics: metrics(phase: AutonomySoakPhase.shadow),
      invariantResults: [certification(faultCode: 'only-one')],
      reconciliation: reconciled,
      cleanupPassed: true,
      rollbackPassed: true,
      supervisorAnomalyCount: 0,
    );

    expect(invalid.validate, throwsFormatException);
  });

  test('all certification version fields are mandatory', () {
    const invalid = AutonomyCertificationVersions(
      buildCommit: '',
      strategyVersion: 'strategy/1',
      rankingVersion: 'ranking/1',
      riskVersion: 'risk/1',
      allocatorVersion: 'allocator/1',
      executionVersion: 'execution/1',
      adapterVersion: 'exchange-adapter/1',
    );

    expect(invalid.validate, throwsFormatException);
  });
}
