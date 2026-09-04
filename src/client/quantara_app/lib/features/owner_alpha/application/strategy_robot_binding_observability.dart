import '../../auto_trade/application/local_live_observability.dart';
import 'strategy_robot_binding.dart';

/// Canonical diagnostics for the evaluated-strategy → robot binding lifecycle.
///
/// These events describe configuration evidence only. They do not grant Local
/// Live authority and contain no credentials or exchange mutation capability.
abstract final class StrategyRobotBindingObservability {
  static const selectedEventName = 'strategy_robot_binding_selected';
  static const restoreFailedEventName = 'strategy_robot_binding_restore_failed';
  static const clearedEventName = 'strategy_robot_binding_cleared';

  static LocalLiveObservabilityEvent selected({
    required DateTime timestampUtc,
    required String sessionId,
    required StrategyRobotBinding binding,
  }) => _event(
    timestampUtc: timestampUtc,
    sessionId: sessionId,
    eventName: selectedEventName,
    binding: binding,
    decision: 'selected',
  );

  static LocalLiveObservabilityEvent restoreFailed({
    required DateTime timestampUtc,
    required String sessionId,
    required StrategyRobotBinding binding,
    required String reasonCode,
  }) => _event(
    timestampUtc: timestampUtc,
    sessionId: sessionId,
    eventName: restoreFailedEventName,
    binding: binding,
    decision: 'blocked',
    reasonCode: reasonCode,
  );

  static LocalLiveObservabilityEvent cleared({
    required DateTime timestampUtc,
    required String sessionId,
    StrategyRobotBinding? previousBinding,
  }) => LocalLiveObservabilityEvent(
    timestampUtc: timestampUtc.toUtc(),
    eventName: clearedEventName,
    family: LocalLiveObservabilityFamily.robot,
    sessionId: sessionId,
    evaluationRunId: previousBinding?.evaluationRunId,
    symbol: previousBinding?.symbol,
    timeframe: previousBinding?.timeframe,
    strategyId: previousBinding?.strategyId,
    strategyVersion: previousBinding?.strategyVersion,
    parameterSchemaVersion: previousBinding?.parameterSchemaVersion,
    snapshotHash: previousBinding?.snapshotHash,
    managementPolicyVersion: previousBinding?.managementPolicyVersion,
    decision: 'cleared',
    details: <String, Object?>{
      if (previousBinding != null) 'setupId': previousBinding.setupId,
      if (previousBinding != null)
        'implementationVersion': previousBinding.implementationVersion,
    },
  );

  static LocalLiveObservabilityEvent _event({
    required DateTime timestampUtc,
    required String sessionId,
    required String eventName,
    required StrategyRobotBinding binding,
    required String decision,
    String? reasonCode,
  }) => LocalLiveObservabilityEvent(
    timestampUtc: timestampUtc.toUtc(),
    eventName: eventName,
    family: LocalLiveObservabilityFamily.robot,
    sessionId: sessionId,
    evaluationRunId: binding.evaluationRunId,
    symbol: binding.symbol,
    timeframe: binding.timeframe,
    strategyId: binding.strategyId,
    strategyVersion: binding.strategyVersion,
    parameterSchemaVersion: binding.parameterSchemaVersion,
    snapshotHash: binding.snapshotHash,
    managementPolicyVersion: binding.managementPolicyVersion,
    decision: decision,
    reasonCode: reasonCode,
    details: <String, Object?>{
      'setupId': binding.setupId,
      'implementationVersion': binding.implementationVersion,
      'normalizedParameters': binding.normalizedParameters,
    },
  );
}
