import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/application/local_live_observability.dart';
import 'package:quantara_app/features/owner_alpha/application/strategy_robot_binding.dart';
import 'package:quantara_app/features/owner_alpha/application/strategy_robot_binding_observability.dart';

void main() {
  StrategyRobotBinding binding() => const StrategyRobotBinding(
    evaluationRunId: 'evaluation-43',
    setupId: 'setup-43',
    strategyId: 'structure_zones',
    strategyVersion: '1.0.0',
    parameterSchemaVersion: 1,
    normalizedParameters: <String, Object?>{'cadence': 'balanced'},
    snapshotHash: 'snapshot-hash',
    managementPolicyVersion: 'structure-zones-management/1.0',
    implementationVersion: 'professional-strategy-engine/1.0',
    symbol: 'BTCUSDT',
    timeframe: '15m',
  );

  test('selected event carries exact evaluated strategy identity', () {
    final event = StrategyRobotBindingObservability.selected(
      timestampUtc: DateTime.utc(2026, 9, 4, 3),
      sessionId: 'session-1',
      binding: binding(),
    );

    expect(event.eventName, 'strategy_robot_binding_selected');
    expect(event.family, LocalLiveObservabilityFamily.robot);
    expect(event.evaluationRunId, 'evaluation-43');
    expect(event.strategyId, 'structure_zones');
    expect(event.strategyVersion, '1.0.0');
    expect(event.parameterSchemaVersion, 1);
    expect(event.snapshotHash, 'snapshot-hash');
    expect(event.managementPolicyVersion, 'structure-zones-management/1.0');
    expect(event.details['setupId'], 'setup-43');
    expect(event.decision, 'selected');
  });

  test('failed restore is explicit and fail-closed in diagnostics', () {
    final event = StrategyRobotBindingObservability.restoreFailed(
      timestampUtc: DateTime.utc(2026, 9, 4, 3),
      sessionId: 'session-1',
      binding: binding(),
      reasonCode: 'strategy_snapshot_unresolvable',
    );

    expect(event.eventName, 'strategy_robot_binding_restore_failed');
    expect(event.decision, 'blocked');
    expect(event.reasonCode, 'strategy_snapshot_unresolvable');
    expect(event.snapshotHash, 'snapshot-hash');
  });

  test('clear event preserves previous identity without execution authority', () {
    final event = StrategyRobotBindingObservability.cleared(
      timestampUtc: DateTime.utc(2026, 9, 4, 3),
      sessionId: 'session-1',
      previousBinding: binding(),
    );
    final exported = LocalLiveObservabilityExport.build(
      <LocalLiveObservabilityEvent>[event],
    );

    expect(event.eventName, 'strategy_robot_binding_cleared');
    expect(event.decision, 'cleared');
    expect(event.evaluationRunId, 'evaluation-43');
    expect(exported['events'], hasLength(1));
  });
}
