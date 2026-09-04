import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/application/local_live_observability.dart';
import 'package:quantara_app/features/owner_alpha/application/strategy_evaluation_observability.dart';

void main() {
  test('evaluation lifecycle scorecard cleanup and replay export stable IDs', () {
    final now = DateTime.utc(2026, 9, 4);
    final events = <LocalLiveObservabilityEvent>[
      StrategyEvaluationObservability.runLifecycle(
        timestampUtc: now,
        sessionId: 'session-1',
        eventName: 'evaluation_run_created',
        evaluationRunId: 'run-1',
        strategyId: 'structure_zones',
        strategyVersion: '1.2.3',
        parameterSchemaVersion: 3,
        snapshotHash: 'sha256-snapshot',
        startingCapital: 1000,
      ),
      StrategyEvaluationObservability.scorecard(
        timestampUtc: now.add(const Duration(seconds: 1)),
        sessionId: 'session-1',
        evaluationRunId: 'run-1',
        strategyId: 'structure_zones',
        strategyVersion: '1.2.3',
        snapshotHash: 'sha256-snapshot',
        version: 1,
        values: const <String, Object?>{'netPnl': 5, 'fees': 1.7},
      ),
      StrategyEvaluationObservability.cleanup(
        timestampUtc: now.add(const Duration(seconds: 2)),
        sessionId: 'session-1',
        evaluationRunId: 'run-1',
        phase: 'completed',
        dataClass: 'replayDetail',
        itemCount: 3,
        bytes: 1200,
      ),
      StrategyEvaluationObservability.replayOpened(
        timestampUtc: now.add(const Duration(seconds: 3)),
        sessionId: 'session-1',
        evaluationRunId: 'run-1',
        tradeId: 'trade-1',
        candleFetchSucceeded: false,
        failureReason: 'historical_candles_unavailable',
      ),
    ];

    final export = LocalLiveObservabilityExport.build(events);
    final rows = export['events']! as List<Object?>;
    final json = rows.cast<Map<String, Object?>>();

    expect(json.map((row) => row['eventName']), <String>[
      'evaluation_run_created',
      'evaluation_scorecard_recalculated',
      'evaluation_history_cleanup_completed',
      'evaluation_chart_replay_opened',
    ]);
    expect(
      json.every((row) => row['evaluationRunId'] == 'run-1'),
      isTrue,
    );
    expect(
      (json.first['details']! as Map<Object?, Object?>)['startingCapitalSource'],
      'manualSetting',
    );
    expect(json.last['tradeId'], 'trade-1');
    expect(json.last['reasonCode'], 'historical_candles_unavailable');
  });
}
