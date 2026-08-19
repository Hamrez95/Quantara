import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/autonomy/domain/autonomy_certification.dart';
import 'package:quantara_app/features/autonomy/domain/autonomy_soak_certification.dart';
import 'package:quantara_app/features/release_acceptance/domain/release_certification.dart';

void main() {
  const versions = AutonomyCertificationVersions(
    buildCommit: 'abc123',
    strategyVersion: 'strategy/1',
    rankingVersion: 'ranking/1',
    riskVersion: 'risk/1',
    allocatorVersion: 'allocator/1',
    executionVersion: 'execution/1',
    adapterVersion: 'adapter/1',
  );
  const reconciliation = AutonomyReconciliationEvidence(
    accountReconciled: true,
    ordersReconciled: true,
    positionsReconciled: true,
    journalReconciled: true,
  );

  AutonomyCertificationResult invariantResult({
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

  AutonomySoakRunEvidence soakRun({
    required String id,
    required AutonomySoakPhase phase,
    required int elapsedSeconds,
    bool stopShip = false,
  }) {
    final paper = phase == AutonomySoakPhase.paper;
    return AutonomySoakRunEvidence(
      runId: id,
      phase: phase,
      versions: versions,
      faultScheduleVersion: 'fault-schedule/1',
      seed: phase.index,
      regimeSampleCounts: const {'trend': 10},
      metrics: AutonomySoakMetrics(
        elapsedSeconds: elapsedSeconds,
        eventSamples: 100,
        candidateSamples: 10,
        tradeSamples: paper ? 2 : 0,
        faultSamples: 1,
        executionQualitySamples: paper ? 2 : 0,
        meanAbsSlippageBps: paper ? 2 : 0,
        latencyP50Ms: 1,
        latencyP95Ms: 2,
        latencyP99Ms: 3,
        maxQueueDepth: 2,
        reconnectCount: 1,
      ),
      invariantResults: [invariantResult(faultCode: id, passed: !stopShip)],
      reconciliation: reconciliation,
      cleanupPassed: true,
      rollbackPassed: true,
      supervisorAnomalyCount: 0,
      supervisorEvidenceIds: stopShip ? ['supervisor:$id'] : const [],
    );
  }

  AutonomySoakCertificationResult soak({
    bool longShadow = true,
    bool stopShip = false,
  }) {
    final shadowSeconds = longShadow
        ? ReleaseCertificationArtifact.requiredRealtimeShadow.inSeconds
        : const Duration(days: 1).inSeconds;
    return AutonomySoakCertificationGate.evaluate(
      runs: [
        soakRun(
          id: 'fixture',
          phase: AutonomySoakPhase.deterministicFixture,
          elapsedSeconds: 60,
        ),
        soakRun(
          id: 'replay',
          phase: AutonomySoakPhase.acceleratedReplay,
          elapsedSeconds: 60,
        ),
        soakRun(
          id: 'shadow',
          phase: AutonomySoakPhase.shadow,
          elapsedSeconds: shadowSeconds,
        ),
        soakRun(
          id: 'paper',
          phase: AutonomySoakPhase.paper,
          elapsedSeconds: 60,
          stopShip: stopShip,
        ),
      ],
    );
  }

  List<ReleaseGateEvidence> allPassedGates() {
    return ReleaseGateCode.values
        .map(
          (code) => ReleaseGateEvidence(
            code: code,
            status: ReleaseGateStatus.passed,
            evidenceIds: ['evidence:${code.name}'],
          ),
        )
        .toList(growable: true);
  }

  test('Stable is eligible only with complete green evidence', () {
    final artifact = ReleaseCertificationGate.evaluate(
      buildCommit: 'abc123',
      releaseVersion: '1.2.0',
      autonomySoak: soak(),
      gates: allPassedGates(),
    );

    expect(artifact.stopShip, isFalse);
    expect(artifact.shadowDurationSatisfied, isTrue);
    expect(artifact.physicalEvidenceComplete, isTrue);
    expect(artifact.stableEligible, isTrue);
    expect(artifact.pendingGates, isEmpty);
    expect(artifact.failedGates, isEmpty);
  });

  test('release build must match the build certified by soak evidence', () {
    expect(
      () => ReleaseCertificationGate.evaluate(
        buildCommit: 'different-build',
        releaseVersion: '1.2.0',
        autonomySoak: soak(),
        gates: allPassedGates(),
      ),
      throwsStateError,
    );
  });

  test(
    'pending physical evidence blocks Stable without fabricating failure',
    () {
      final gates = allPassedGates();
      gates[ReleaseGateCode.samsungPhysicalQa.index] = ReleaseGateEvidence(
        code: ReleaseGateCode.samsungPhysicalQa,
        status: ReleaseGateStatus.pending,
      );

      final artifact = ReleaseCertificationGate.evaluate(
        buildCommit: 'abc123',
        releaseVersion: '1.2.0',
        autonomySoak: soak(),
        gates: gates,
      );

      expect(artifact.stopShip, isFalse);
      expect(artifact.physicalEvidenceComplete, isFalse);
      expect(artifact.stableEligible, isFalse);
      expect(artifact.pendingGates, [ReleaseGateCode.samsungPhysicalQa]);
    },
  );

  test('failed release gate is stop-ship', () {
    final gates = allPassedGates();
    gates[ReleaseGateCode.performanceSlo.index] = ReleaseGateEvidence(
      code: ReleaseGateCode.performanceSlo,
      status: ReleaseGateStatus.failed,
      evidenceIds: const ['benchmark:p99-regression'],
    );

    final artifact = ReleaseCertificationGate.evaluate(
      buildCommit: 'abc123',
      releaseVersion: '1.2.0',
      autonomySoak: soak(),
      gates: gates,
    );

    expect(artifact.stopShip, isTrue);
    expect(artifact.stableEligible, isFalse);
    expect(artifact.failedGates, [ReleaseGateCode.performanceSlo]);
  });

  test('autonomy stop-ship propagates into release certification', () {
    final artifact = ReleaseCertificationGate.evaluate(
      buildCommit: 'abc123',
      releaseVersion: '1.2.0',
      autonomySoak: soak(stopShip: true),
      gates: allPassedGates(),
    );

    expect(artifact.autonomySoak.stopShip, isTrue);
    expect(artifact.stopShip, isTrue);
    expect(artifact.stableEligible, isFalse);
  });

  test('tiny-risk canary cannot pass before permanent signing', () {
    final gates = allPassedGates();
    gates[ReleaseGateCode.permanentSigning.index] = ReleaseGateEvidence(
      code: ReleaseGateCode.permanentSigning,
      status: ReleaseGateStatus.pending,
    );

    expect(
      () => ReleaseCertificationGate.evaluate(
        buildCommit: 'abc123',
        releaseVersion: '1.2.0',
        autonomySoak: soak(),
        gates: gates,
      ),
      throwsStateError,
    );
  });

  test('tiny-risk canary cannot pass before 14-day Shadow evidence', () {
    expect(
      () => ReleaseCertificationGate.evaluate(
        buildCommit: 'abc123',
        releaseVersion: '1.2.0',
        autonomySoak: soak(longShadow: false),
        gates: allPassedGates(),
      ),
      throwsStateError,
    );
  });

  test('missing release gate cannot produce a green report', () {
    final incomplete = allPassedGates()..removeLast();

    expect(
      () => ReleaseCertificationGate.evaluate(
        buildCommit: 'abc123',
        releaseVersion: '1.2.0',
        autonomySoak: soak(),
        gates: incomplete,
      ),
      throwsStateError,
    );
  });

  test('duplicate release gate is rejected', () {
    final duplicate = allPassedGates();
    duplicate.add(
      ReleaseGateEvidence(
        code: ReleaseGateCode.flutterQuality,
        status: ReleaseGateStatus.passed,
        evidenceIds: const ['ci:duplicate'],
      ),
    );

    expect(
      () => ReleaseCertificationGate.evaluate(
        buildCommit: 'abc123',
        releaseVersion: '1.2.0',
        autonomySoak: soak(),
        gates: duplicate,
      ),
      throwsStateError,
    );
  });

  test('passed and failed gates require evidence IDs', () {
    expect(
      () => ReleaseGateEvidence(
        code: ReleaseGateCode.flutterQuality,
        status: ReleaseGateStatus.passed,
      ),
      throwsFormatException,
    );
    expect(
      () => ReleaseGateEvidence(
        code: ReleaseGateCode.performanceSlo,
        status: ReleaseGateStatus.failed,
      ),
      throwsFormatException,
    );
  });

  test('release evidence IDs are normalized and cannot be blank', () {
    final evidence = ReleaseGateEvidence(
      code: ReleaseGateCode.flutterQuality,
      status: ReleaseGateStatus.passed,
      evidenceIds: const ['  ci:flutter-123  '],
    );

    expect(evidence.evidenceIds, ['ci:flutter-123']);
    expect(
      () => ReleaseGateEvidence(
        code: ReleaseGateCode.flutterQuality,
        status: ReleaseGateStatus.passed,
        evidenceIds: const ['   '],
      ),
      throwsFormatException,
    );
  });

  test('release artifact ordering is deterministic', () {
    final reversed = allPassedGates().reversed;
    final artifact = ReleaseCertificationGate.evaluate(
      buildCommit: 'abc123',
      releaseVersion: '1.2.0',
      autonomySoak: soak(),
      gates: reversed,
    );

    expect(artifact.gates.map((gate) => gate.code), ReleaseGateCode.values);
  });

  test('release build and version metadata are mandatory', () {
    expect(
      () => ReleaseCertificationGate.evaluate(
        buildCommit: ' ',
        releaseVersion: '',
        autonomySoak: soak(),
        gates: allPassedGates(),
      ),
      throwsFormatException,
    );
  });
}
