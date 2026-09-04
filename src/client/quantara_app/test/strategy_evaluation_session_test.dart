import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/owner_alpha/domain/strategy_evaluation_run.dart';
import 'package:quantara_app/features/owner_alpha/domain/strategy_evaluation_session.dart';

void main() {
  StrategyEvaluationRun run({
    required String runId,
    required double grossPnl,
    required double cost,
  }) => StrategyEvaluationRun(
    runId: runId,
    setupId: 'setup-1',
    identity: StrategyEvaluationIdentity(
      strategyId: 'structure_zones',
      strategyVersion: '1.0.0',
      implementationVersion: 'professional-strategy-engine/1.0',
      managementPolicyVersion: 'structure-zones-management/1.0',
      parameterSchemaVersion: 1,
      normalizedParameters: const <String, Object?>{'cadence': 'balanced'},
      snapshotHash: 'snapshot-hash',
    ),
    symbol: 'BTCUSDT',
    market: 'crypto',
    timeframe: '15m',
    rangeStartUtc: DateTime.utc(2026, 9, 1),
    rangeEndUtc: DateTime.utc(2026, 9, 2),
    createdAtUtc: DateTime.utc(2026, 9, 1),
    costModel: const StrategyEvaluationCostModel(
      version: 'cost-v1',
      takerFeeBps: 6,
      slippageBps: 2,
    ),
    trades: <StrategyEvaluationTrade>[
      StrategyEvaluationTrade(
        tradeId: '$runId-trade',
        openedAtUtc: DateTime.utc(2026, 9, 1, 1),
        closedAtUtc: DateTime.utc(2026, 9, 1, 2),
        grossPnl: grossPnl,
        cost: cost,
        maximumFavorableExcursion: grossPnl > 0 ? grossPnl : 0,
        maximumAdverseExcursion: grossPnl < 0 ? grossPnl.abs() : 0,
      ),
    ],
  );

  test('manual baseline drives evaluation equity and ROI only', () {
    final session = StrategyEvaluationSession(
      activeRun: run(runId: 'run-1', grossPnl: 120, cost: 20),
      baseline: const StrategyEvaluationBaseline(startingCapital: 1000),
    );

    expect(session.currentEvaluationEquity, 1100);
    expect(session.roiPercent, 10);
    expect(
      session.baseline.source,
      StrategyEvaluationCapitalSource.manualSetting,
    );
    expect(session.grantsLocalLiveAuthority, isFalse);
  });

  test('Start new evaluation archives prior facts and resets baseline', () {
    final first = StrategyEvaluationSession(
      activeRun: run(runId: 'run-1', grossPnl: 120, cost: 20),
      baseline: const StrategyEvaluationBaseline(startingCapital: 1000),
    );

    final restarted = first.startNewEvaluation(
      nextRun: run(runId: 'run-2', grossPnl: 0, cost: 0),
      nextBaseline: const StrategyEvaluationBaseline(startingCapital: 800),
      archivedAtUtc: DateTime.utc(2026, 9, 3),
    );

    expect(restarted.activeRun.runId, 'run-2');
    expect(restarted.baseline.startingCapital, 800);
    expect(restarted.archivedRuns, hasLength(1));
    expect(restarted.archivedRuns.single.run.runId, 'run-1');
    expect(restarted.archivedRuns.single.currentEvaluationEquity, 1100);
    expect(restarted.archivedRuns.single.roiPercent, 10);
    expect(first.archivedRuns, isEmpty);
  });

  test('restart rejects reused run id and silent strategy remap', () {
    final first = StrategyEvaluationSession(
      activeRun: run(runId: 'run-1', grossPnl: 10, cost: 1),
      baseline: const StrategyEvaluationBaseline(startingCapital: 1000),
    );

    expect(
      () => first.startNewEvaluation(
        nextRun: run(runId: 'run-1', grossPnl: 0, cost: 0),
        nextBaseline: const StrategyEvaluationBaseline(startingCapital: 1000),
        archivedAtUtc: DateTime.utc(2026, 9, 3),
      ),
      throwsArgumentError,
    );

    final remapped = StrategyEvaluationRun(
      runId: 'run-2',
      setupId: 'setup-1',
      identity: StrategyEvaluationIdentity(
        strategyId: 'structure_zones',
        strategyVersion: '2.0.0',
        implementationVersion: 'professional-strategy-engine/2.0',
        managementPolicyVersion: 'structure-zones-management/2.0',
        parameterSchemaVersion: 2,
        normalizedParameters: const <String, Object?>{'cadence': 'balanced'},
        snapshotHash: 'different-snapshot',
      ),
      symbol: 'BTCUSDT',
      market: 'crypto',
      timeframe: '15m',
      rangeStartUtc: DateTime.utc(2026, 9, 3),
      rangeEndUtc: DateTime.utc(2026, 9, 4),
      createdAtUtc: DateTime.utc(2026, 9, 3),
      costModel: const StrategyEvaluationCostModel(
        version: 'cost-v1',
        takerFeeBps: 6,
        slippageBps: 2,
      ),
      trades: const <StrategyEvaluationTrade>[],
    );

    expect(
      () => first.startNewEvaluation(
        nextRun: remapped,
        nextBaseline: const StrategyEvaluationBaseline(startingCapital: 1000),
        archivedAtUtc: DateTime.utc(2026, 9, 4),
      ),
      throwsArgumentError,
    );
  });

  test('invalid manual evaluation capital fails closed', () {
    StrategyEvaluationSession createInvalidSession() =>
        StrategyEvaluationSession(
          activeRun: run(runId: 'run-1', grossPnl: 0, cost: 0),
          baseline: const StrategyEvaluationBaseline(startingCapital: 0),
        );

    expect(createInvalidSession, throwsArgumentError);
  });
}
