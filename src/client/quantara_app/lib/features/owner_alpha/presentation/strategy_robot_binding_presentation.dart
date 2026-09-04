import '../application/strategy_robot_binding.dart';

/// Read-only presentation contract for proving which evaluated strategy
/// snapshot is selected for the robot.
///
/// This model intentionally has no arming or execution authority. It only
/// formats immutable binding evidence for confirmation/status UI.
final class StrategyRobotBindingPresentation {
  const StrategyRobotBindingPresentation({
    required this.strategyId,
    required this.strategyVersion,
    required this.snapshotHash,
    required this.evaluationRunId,
    required this.symbol,
    required this.timeframe,
  });

  final String strategyId;
  final String strategyVersion;
  final String snapshotHash;
  final String evaluationRunId;
  final String symbol;
  final String timeframe;

  factory StrategyRobotBindingPresentation.fromBinding(
    StrategyRobotBinding binding,
  ) => StrategyRobotBindingPresentation(
    strategyId: binding.strategyId,
    strategyVersion: binding.strategyVersion,
    snapshotHash: binding.snapshotHash,
    evaluationRunId: binding.evaluationRunId,
    symbol: binding.symbol,
    timeframe: binding.timeframe,
  );

  String get shortHash {
    final value = snapshotHash.trim();
    if (value.length <= 8) return value;
    return '${value.substring(0, 8)}…';
  }

  String confirmationSummary({required bool persian}) {
    if (persian) {
      return '$strategyId v$strategyVersion • هش $shortHash • $symbol/$timeframe • ارزیابی $evaluationRunId';
    }
    return '$strategyId v$strategyVersion • hash $shortHash • $symbol/$timeframe • evaluation $evaluationRunId';
  }

  String robotStatus({required bool persian}) {
    if (persian) {
      return 'ربات: $strategyId v$strategyVersion — همان نسخه ارزیابی $evaluationRunId';
    }
    return 'Robot: $strategyId v$strategyVersion — exact evaluation $evaluationRunId snapshot';
  }

  String useInRobotLabel({required bool persian}) =>
      persian ? 'استفاده در ربات' : 'Use in Robot';
}
