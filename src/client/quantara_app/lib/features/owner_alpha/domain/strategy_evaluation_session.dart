import 'dart:collection';

import 'strategy_evaluation_run.dart';

enum StrategyEvaluationCapitalSource { manualSetting }

/// User-configured evaluation baseline. It is intentionally independent from
/// exchange wallet history and cannot grant execution authority.
final class StrategyEvaluationBaseline {
  const StrategyEvaluationBaseline({
    required this.startingCapital,
    this.source = StrategyEvaluationCapitalSource.manualSetting,
  });

  final double startingCapital;
  final StrategyEvaluationCapitalSource source;

  void validate() {
    if (!startingCapital.isFinite || startingCapital <= 0) {
      throw ArgumentError.value(startingCapital, 'startingCapital');
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'startingCapital': startingCapital,
    'source': source.name,
  };
}

/// Immutable aggregate for one completed evaluation run.
final class StrategyEvaluationArchive {
  StrategyEvaluationArchive({
    required this.run,
    required this.baseline,
    required this.archivedAtUtc,
  }) {
    baseline.validate();
    if (!archivedAtUtc.isUtc) {
      throw ArgumentError.value(archivedAtUtc, 'archivedAtUtc');
    }
  }

  final StrategyEvaluationRun run;
  final StrategyEvaluationBaseline baseline;
  final DateTime archivedAtUtc;

  double get currentEvaluationEquity =>
      baseline.startingCapital + run.scorecard.totalNetPnl;

  double get roiPercent =>
      run.scorecard.totalNetPnl / baseline.startingCapital * 100;

  Map<String, Object?> toJson() => <String, Object?>{
    'run': run.toJson(),
    'baseline': baseline.toJson(),
    'archivedAtUtc': archivedAtUtc.toIso8601String(),
    'currentEvaluationEquity': currentEvaluationEquity,
    'roiPercent': roiPercent,
  };
}

/// Tracks the active evaluation plus preserved archived summaries.
///
/// Restart never mutates or deletes prior evidence. The caller must supply a
/// newly constructed run with a new run id and the desired manual baseline.
final class StrategyEvaluationSession {
  StrategyEvaluationSession({
    required this.activeRun,
    required this.baseline,
    Iterable<StrategyEvaluationArchive> archivedRuns = const [],
  }) : archivedRuns = UnmodifiableListView<StrategyEvaluationArchive>(
         List<StrategyEvaluationArchive>.of(archivedRuns),
       ) {
    baseline.validate();
    _validateArchiveIdentity();
  }

  final StrategyEvaluationRun activeRun;
  final StrategyEvaluationBaseline baseline;
  final List<StrategyEvaluationArchive> archivedRuns;

  double get currentEvaluationEquity =>
      baseline.startingCapital + activeRun.scorecard.totalNetPnl;

  double get roiPercent =>
      activeRun.scorecard.totalNetPnl / baseline.startingCapital * 100;

  bool get grantsLocalLiveAuthority => false;

  StrategyEvaluationSession startNewEvaluation({
    required StrategyEvaluationRun nextRun,
    required StrategyEvaluationBaseline nextBaseline,
    required DateTime archivedAtUtc,
  }) {
    nextBaseline.validate();
    if (!archivedAtUtc.isUtc) {
      throw ArgumentError.value(archivedAtUtc, 'archivedAtUtc');
    }
    if (nextRun.runId == activeRun.runId) {
      throw ArgumentError.value(
        nextRun.runId,
        'nextRun.runId',
        'A new evaluation requires a new run id.',
      );
    }
    if (!_sameStrategyIdentity(activeRun, nextRun)) {
      throw ArgumentError(
        'A restarted evaluation must preserve the exact strategy snapshot.',
      );
    }
    final archived = StrategyEvaluationArchive(
      run: activeRun,
      baseline: baseline,
      archivedAtUtc: archivedAtUtc,
    );
    return StrategyEvaluationSession(
      activeRun: nextRun,
      baseline: nextBaseline,
      archivedRuns: <StrategyEvaluationArchive>[...archivedRuns, archived],
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'activeRun': activeRun.toJson(),
    'baseline': baseline.toJson(),
    'currentEvaluationEquity': currentEvaluationEquity,
    'roiPercent': roiPercent,
    'archivedRuns': archivedRuns
        .map((archive) => archive.toJson())
        .toList(growable: false),
  };

  void _validateArchiveIdentity() {
    for (final archive in archivedRuns) {
      if (!_sameStrategyIdentity(activeRun, archive.run)) {
        throw ArgumentError(
          'Archived evaluations must belong to the same strategy snapshot.',
        );
      }
    }
  }
}

bool _sameStrategyIdentity(
  StrategyEvaluationRun left,
  StrategyEvaluationRun right,
) =>
    left.setupId == right.setupId &&
    left.identity.strategyId == right.identity.strategyId &&
    left.identity.strategyVersion == right.identity.strategyVersion &&
    left.identity.snapshotHash == right.identity.snapshotHash &&
    left.identity.parameterSchemaVersion ==
        right.identity.parameterSchemaVersion &&
    left.identity.managementPolicyVersion ==
        right.identity.managementPolicyVersion &&
    left.identity.implementationVersion == right.identity.implementationVersion;
