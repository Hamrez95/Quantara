import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'autonomy_certification.dart';

enum AutonomySoakPhase {
  deterministicFixture,
  acceleratedReplay,
  shadow,
  paper,
  cappedCanary,
}

@immutable
final class AutonomyCertificationVersions {
  const AutonomyCertificationVersions({
    required this.buildCommit,
    required this.strategyVersion,
    required this.rankingVersion,
    required this.riskVersion,
    required this.allocatorVersion,
    required this.executionVersion,
    required this.adapterVersion,
  });

  final String buildCommit;
  final String strategyVersion;
  final String rankingVersion;
  final String riskVersion;
  final String allocatorVersion;
  final String executionVersion;
  final String adapterVersion;

  void validate() {
    final values = [
      buildCommit,
      strategyVersion,
      rankingVersion,
      riskVersion,
      allocatorVersion,
      executionVersion,
      adapterVersion,
    ];
    if (values.any((value) => value.trim().isEmpty)) {
      throw const FormatException(
        'Certification version metadata cannot contain empty values.',
      );
    }
  }

  bool sameIdentityAs(AutonomyCertificationVersions other) {
    return buildCommit.trim() == other.buildCommit.trim() &&
        strategyVersion.trim() == other.strategyVersion.trim() &&
        rankingVersion.trim() == other.rankingVersion.trim() &&
        riskVersion.trim() == other.riskVersion.trim() &&
        allocatorVersion.trim() == other.allocatorVersion.trim() &&
        executionVersion.trim() == other.executionVersion.trim() &&
        adapterVersion.trim() == other.adapterVersion.trim();
  }

  Map<String, Object?> toJson() => {
    'buildCommit': buildCommit,
    'strategyVersion': strategyVersion,
    'rankingVersion': rankingVersion,
    'riskVersion': riskVersion,
    'allocatorVersion': allocatorVersion,
    'executionVersion': executionVersion,
    'adapterVersion': adapterVersion,
  };
}

@immutable
final class AutonomySoakMetrics {
  const AutonomySoakMetrics({
    required this.elapsedSeconds,
    required this.eventSamples,
    required this.candidateSamples,
    required this.tradeSamples,
    required this.faultSamples,
    required this.executionQualitySamples,
    required this.meanAbsSlippageBps,
    required this.latencyP50Ms,
    required this.latencyP95Ms,
    required this.latencyP99Ms,
    required this.maxQueueDepth,
    required this.reconnectCount,
  });

  final int elapsedSeconds;
  final int eventSamples;
  final int candidateSamples;
  final int tradeSamples;
  final int faultSamples;
  final int executionQualitySamples;
  final double meanAbsSlippageBps;
  final double latencyP50Ms;
  final double latencyP95Ms;
  final double latencyP99Ms;
  final int maxQueueDepth;
  final int reconnectCount;

  void validate({required AutonomySoakPhase phase}) {
    if (elapsedSeconds <= 0 ||
        eventSamples <= 0 ||
        candidateSamples <= 0 ||
        tradeSamples < 0 ||
        faultSamples <= 0 ||
        executionQualitySamples < 0 ||
        maxQueueDepth < 0 ||
        reconnectCount < 0) {
      throw const FormatException(
        'Soak metrics require positive coverage and non-negative counters.',
      );
    }
    if (phase == AutonomySoakPhase.paper &&
        (tradeSamples <= 0 || executionQualitySamples <= 0)) {
      throw const FormatException(
        'Paper certification requires execution and quality samples.',
      );
    }
    if (!meanAbsSlippageBps.isFinite || meanAbsSlippageBps < 0) {
      throw const FormatException(
        'Execution-quality slippage must be finite and non-negative.',
      );
    }
    if (!latencyP50Ms.isFinite ||
        !latencyP95Ms.isFinite ||
        !latencyP99Ms.isFinite ||
        latencyP50Ms < 0 ||
        latencyP95Ms < latencyP50Ms ||
        latencyP99Ms < latencyP95Ms) {
      throw const FormatException(
        'Latency metrics must be finite, non-negative, and ordered.',
      );
    }
  }

  Map<String, Object?> toJson() => {
    'elapsedSeconds': elapsedSeconds,
    'eventSamples': eventSamples,
    'candidateSamples': candidateSamples,
    'tradeSamples': tradeSamples,
    'faultSamples': faultSamples,
    'executionQualitySamples': executionQualitySamples,
    'meanAbsSlippageBps': meanAbsSlippageBps,
    'latencyP50Ms': latencyP50Ms,
    'latencyP95Ms': latencyP95Ms,
    'latencyP99Ms': latencyP99Ms,
    'maxQueueDepth': maxQueueDepth,
    'reconnectCount': reconnectCount,
  };
}

@immutable
final class AutonomyReconciliationEvidence {
  const AutonomyReconciliationEvidence({
    required this.accountReconciled,
    required this.ordersReconciled,
    required this.positionsReconciled,
    required this.journalReconciled,
  });

  final bool accountReconciled;
  final bool ordersReconciled;
  final bool positionsReconciled;
  final bool journalReconciled;

  bool get passed =>
      accountReconciled &&
      ordersReconciled &&
      positionsReconciled &&
      journalReconciled;

  Map<String, Object?> toJson() => {
    'accountReconciled': accountReconciled,
    'ordersReconciled': ordersReconciled,
    'positionsReconciled': positionsReconciled,
    'journalReconciled': journalReconciled,
    'passed': passed,
  };
}

@immutable
final class AutonomySoakRunEvidence {
  AutonomySoakRunEvidence({
    required this.runId,
    required this.phase,
    required this.versions,
    required this.faultScheduleVersion,
    required this.seed,
    required Map<String, int> regimeSampleCounts,
    required this.metrics,
    required Iterable<AutonomyCertificationResult> invariantResults,
    required this.reconciliation,
    required this.cleanupPassed,
    required this.rollbackPassed,
    required this.supervisorAnomalyCount,
    Iterable<String> supervisorEvidenceIds = const [],
  }) : regimeSampleCounts = UnmodifiableMapView(
         Map<String, int>.from(regimeSampleCounts),
       ),
       invariantResults = UnmodifiableListView(
         invariantResults.toList(growable: false),
       ),
       supervisorEvidenceIds = UnmodifiableListView(
         supervisorEvidenceIds
             .map((value) => value.trim())
             .toList(growable: false),
       );

  final String runId;
  final AutonomySoakPhase phase;
  final AutonomyCertificationVersions versions;
  final String faultScheduleVersion;
  final int seed;
  final UnmodifiableMapView<String, int> regimeSampleCounts;
  final AutonomySoakMetrics metrics;
  final UnmodifiableListView<AutonomyCertificationResult> invariantResults;
  final AutonomyReconciliationEvidence reconciliation;
  final bool cleanupPassed;
  final bool rollbackPassed;
  final int supervisorAnomalyCount;
  final UnmodifiableListView<String> supervisorEvidenceIds;

  bool get stopShip =>
      invariantResults.any((result) => result.stopShip) ||
      !reconciliation.passed ||
      !cleanupPassed ||
      !rollbackPassed;

  void validate() {
    versions.validate();
    metrics.validate(phase: phase);
    if (runId.trim().isEmpty ||
        faultScheduleVersion.trim().isEmpty ||
        seed < 0) {
      throw const FormatException(
        'Soak evidence requires a run ID, fault schedule, and non-negative seed.',
      );
    }
    if (regimeSampleCounts.isEmpty ||
        regimeSampleCounts.entries.any(
          (entry) => entry.key.trim().isEmpty || entry.value <= 0,
        )) {
      throw const FormatException(
        'Every soak regime requires a non-empty name and positive sample count.',
      );
    }
    if (invariantResults.isEmpty ||
        metrics.faultSamples != invariantResults.length) {
      throw const FormatException(
        'Every recorded fault sample requires machine-asserted invariant results.',
      );
    }
    if (supervisorAnomalyCount < 0 ||
        supervisorEvidenceIds.any((value) => value.isEmpty)) {
      throw const FormatException(
        'Supervisor anomaly counts and evidence IDs must be valid.',
      );
    }
    if ((stopShip || supervisorAnomalyCount > 0) &&
        supervisorEvidenceIds.isEmpty) {
      throw const FormatException(
        'Failures and Supervisor anomalies require evidence IDs.',
      );
    }
  }

  Map<String, Object?> toJson() => {
    'runId': runId,
    'phase': phase.name,
    'versions': versions.toJson(),
    'faultScheduleVersion': faultScheduleVersion,
    'seed': seed,
    'regimeSampleCounts': regimeSampleCounts,
    'metrics': metrics.toJson(),
    'invariantResults': invariantResults
        .map((result) => result.toJson())
        .toList(growable: false),
    'reconciliation': reconciliation.toJson(),
    'cleanupPassed': cleanupPassed,
    'rollbackPassed': rollbackPassed,
    'supervisorAnomalyCount': supervisorAnomalyCount,
    'supervisorEvidenceIds': supervisorEvidenceIds.toList(growable: false),
    'stopShip': stopShip,
  };
}

@immutable
final class AutonomySoakCertificationResult {
  AutonomySoakCertificationResult._({
    required Iterable<AutonomySoakRunEvidence> runs,
  }) : runs = UnmodifiableListView(runs.toList(growable: false));

  final UnmodifiableListView<AutonomySoakRunEvidence> runs;

  bool hasPhase(AutonomySoakPhase phase) {
    return runs.any((run) => run.phase == phase);
  }

  bool get prerequisitePhasesPresent =>
      hasPhase(AutonomySoakPhase.deterministicFixture) &&
      hasPhase(AutonomySoakPhase.acceleratedReplay) &&
      hasPhase(AutonomySoakPhase.shadow) &&
      hasPhase(AutonomySoakPhase.paper);

  bool get stopShip => runs.any((run) => run.stopShip);

  bool get promotionEligible => prerequisitePhasesPresent && !stopShip;

  bool get cappedAutoLocked => !promotionEligible;

  List<String> get failedRunIds => List.unmodifiable(
    runs.where((run) => run.stopShip).map((run) => run.runId),
  );

  Map<String, Object?> toJson() => {
    'prerequisitePhasesPresent': prerequisitePhasesPresent,
    'stopShip': stopShip,
    'promotionEligible': promotionEligible,
    'cappedAutoLocked': cappedAutoLocked,
    'failedRunIds': failedRunIds,
    'runs': runs.map((run) => run.toJson()).toList(growable: false),
  };
}

abstract final class AutonomySoakCertificationGate {
  static AutonomySoakCertificationResult evaluate({
    required Iterable<AutonomySoakRunEvidence> runs,
  }) {
    final byRunId = <String, AutonomySoakRunEvidence>{};
    for (final run in runs) {
      run.validate();
      final normalizedRunId = run.runId.trim();
      if (byRunId.containsKey(normalizedRunId)) {
        throw StateError('Soak certification run IDs must be unique.');
      }
      byRunId[normalizedRunId] = run;
    }

    final result = AutonomySoakCertificationResult._(runs: byRunId.values);
    if (!result.prerequisitePhasesPresent) {
      throw StateError(
        'Soak certification requires fixture, replay, Shadow, and Paper evidence.',
      );
    }

    final baseline = result.runs.first;
    final mixedIdentity = result.runs.any(
      (run) => !run.versions.sameIdentityAs(baseline.versions),
    );
    if (mixedIdentity) {
      throw StateError(
        'Soak certification cannot combine evidence from different build or policy versions.',
      );
    }

    final baselineFaultSchedule = baseline.faultScheduleVersion.trim();
    final mixedFaultSchedule = result.runs.any(
      (run) => run.faultScheduleVersion.trim() != baselineFaultSchedule,
    );
    if (mixedFaultSchedule) {
      throw StateError(
        'Soak certification cannot combine different fault-schedule versions.',
      );
    }
    return result;
  }
}
