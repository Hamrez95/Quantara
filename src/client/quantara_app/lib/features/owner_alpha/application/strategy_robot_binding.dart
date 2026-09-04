import '../data/strategy_registry.dart';
import '../domain/owner_alpha_models.dart';

/// Immutable bridge between an evaluated setup and the robot.
///
/// This object grants no exchange authority. It only preserves the exact
/// strategy snapshot that was evaluated so live/runtime code can fail closed
/// before any execution overlay is considered.
final class StrategyRobotBinding {
  const StrategyRobotBinding({
    required this.evaluationRunId,
    required this.setupId,
    required this.strategyId,
    required this.strategyVersion,
    required this.parameterSchemaVersion,
    required this.normalizedParameters,
    required this.snapshotHash,
    required this.managementPolicyVersion,
    required this.implementationVersion,
    required this.symbol,
    required this.timeframe,
  });

  final String evaluationRunId;
  final String setupId;
  final String strategyId;
  final String strategyVersion;
  final int parameterSchemaVersion;
  final Map<String, Object?> normalizedParameters;
  final String snapshotHash;
  final String managementPolicyVersion;
  final String implementationVersion;
  final String symbol;
  final String timeframe;

  static StrategyRobotBinding? fromEvaluatedIdea({
    required String evaluationRunId,
    required TradeIdea idea,
  }) {
    if (evaluationRunId.trim().isEmpty ||
        idea.setupId.trim().isEmpty ||
        idea.registryStrategyId.trim().isEmpty ||
        idea.registryStrategyVersion.trim().isEmpty ||
        idea.strategyParameterSchemaVersion < 1 ||
        idea.strategySnapshotHash.trim().isEmpty ||
        idea.managementPolicyVersion.trim().isEmpty ||
        idea.strategyImplementationVersion.trim().isEmpty ||
        idea.symbol.trim().isEmpty ||
        idea.timeframe.trim().isEmpty) {
      return null;
    }
    return StrategyRobotBinding(
      evaluationRunId: evaluationRunId.trim(),
      setupId: idea.setupId,
      strategyId: idea.registryStrategyId,
      strategyVersion: idea.registryStrategyVersion,
      parameterSchemaVersion: idea.strategyParameterSchemaVersion,
      normalizedParameters: Map.unmodifiable(
        Map<String, Object?>.from(idea.normalizedStrategyParameters),
      ),
      snapshotHash: idea.strategySnapshotHash,
      managementPolicyVersion: idea.managementPolicyVersion,
      implementationVersion: idea.strategyImplementationVersion,
      symbol: idea.symbol,
      timeframe: idea.timeframe,
    );
  }

  /// Resolves only the exact historical strategy version and proves that the
  /// persisted normalized parameters still produce the same immutable hash.
  /// Unknown, removed, changed, or incompatible snapshots fail closed.
  StrategyResolution? resolveExact(StrategyRegistry registry) {
    final module = registry.historical(
      strategyId: strategyId,
      strategyVersion: strategyVersion,
    );
    if (module == null ||
        module.parameterSchemaVersion != parameterSchemaVersion ||
        module.managementPolicyVersion != managementPolicyVersion ||
        module.implementationVersion != implementationVersion ||
        !module.supports(symbol: symbol, timeframe: timeframe)) {
      return null;
    }
    final snapshot = module.snapshot(normalizedParameters);
    if (snapshot == null || snapshot.snapshotHash != snapshotHash) {
      return null;
    }
    return StrategyResolution(module: module, snapshot: snapshot);
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'evaluationRunId': evaluationRunId,
    'setupId': setupId,
    'strategyId': strategyId,
    'strategyVersion': strategyVersion,
    'parameterSchemaVersion': parameterSchemaVersion,
    'normalizedParameters': normalizedParameters,
    'snapshotHash': snapshotHash,
    'managementPolicyVersion': managementPolicyVersion,
    'implementationVersion': implementationVersion,
    'symbol': symbol,
    'timeframe': timeframe,
  };

  static StrategyRobotBinding? tryFromJson(Map<String, Object?> value) {
    try {
      final rawParameters = value['normalizedParameters'];
      if (rawParameters is! Map<Object?, Object?>) return null;
      final parameters = <String, Object?>{};
      for (final entry in rawParameters.entries) {
        if (entry.key is! String) return null;
        parameters[entry.key! as String] = entry.value;
      }
      final binding = StrategyRobotBinding(
        evaluationRunId: value['evaluationRunId'] as String,
        setupId: value['setupId'] as String,
        strategyId: value['strategyId'] as String,
        strategyVersion: value['strategyVersion'] as String,
        parameterSchemaVersion: value['parameterSchemaVersion'] as int,
        normalizedParameters: Map.unmodifiable(parameters),
        snapshotHash: value['snapshotHash'] as String,
        managementPolicyVersion: value['managementPolicyVersion'] as String,
        implementationVersion: value['implementationVersion'] as String,
        symbol: value['symbol'] as String,
        timeframe: value['timeframe'] as String,
      );
      if (binding.evaluationRunId.trim().isEmpty ||
          binding.setupId.trim().isEmpty ||
          binding.strategyId.trim().isEmpty ||
          binding.strategyVersion.trim().isEmpty ||
          binding.parameterSchemaVersion < 1 ||
          binding.snapshotHash.trim().isEmpty ||
          binding.managementPolicyVersion.trim().isEmpty ||
          binding.implementationVersion.trim().isEmpty ||
          binding.symbol.trim().isEmpty ||
          binding.timeframe.trim().isEmpty) {
        return null;
      }
      return binding;
    } on Object {
      return null;
    }
  }
}
