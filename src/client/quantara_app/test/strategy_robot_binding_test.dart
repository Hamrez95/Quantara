import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/market_analysis/domain/market_regime_models.dart';
import 'package:quantara_app/features/owner_alpha/application/strategy_robot_binding.dart';
import 'package:quantara_app/features/owner_alpha/data/professional_strategy_engine.dart';
import 'package:quantara_app/features/owner_alpha/data/strategy_registry.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';

void main() {
  StrategyModule module({String version = '1.0.0'}) => StrategyModule(
    selection: AnalysisStrategy.structureZones,
    strategyId: 'structure_zones',
    humanName: 'Structure Zones',
    strategyVersion: version,
    parameterSchemaVersion: 1,
    parameterDefaults: const <String, Object?>{'cadence': 'balanced'},
    supportedTimeframes: const <String>{'15m'},
    capabilities: const <String>{'deterministic_entry'},
    entrySemantics: 'deterministic',
    initialStopSemantics: 'deterministic',
    targetPlan: 'deterministic',
    invalidationRules: 'deterministic',
    managementPolicyVersion: 'structure-zones-management/1.0',
    implementationVersion: ProfessionalStrategyEngine.version,
  );

  TradeIdea idea(StrategySnapshotIdentity snapshot) => TradeIdea(
    symbol: 'BTCUSDT',
    timeframe: '15m',
    direction: TradeDirection.long,
    confidencePercent: 80,
    entryLower: 100,
    entryUpper: 101,
    stopLoss: 98,
    targets: const <double>[103, 105],
    riskReward: 2,
    maximumLoss: 5,
    positionSize: 0.5,
    notionalValue: 50,
    recommendedLeverage: 2,
    maximumSafeLeverage: 4,
    requiredMargin: 25,
    estimatedRoundTripCosts: 0.1,
    setupId: 'setup-43',
    candleClosedAt: DateTime.utc(2026, 9, 4),
    summary: 'test',
    invalidation: 'test',
    reasons: const <String>['test'],
    strategy: AnalysisStrategy.structureZones,
    strategyVersion: 'rangeReversal/1.0',
    registryStrategyId: snapshot.strategyId,
    registryStrategyVersion: snapshot.strategyVersion,
    strategyParameterSchemaVersion: snapshot.parameterSchemaVersion,
    normalizedStrategyParameters: snapshot.normalizedParameters,
    strategySnapshotHash: snapshot.snapshotHash,
    managementPolicyVersion: snapshot.managementPolicyVersion,
    strategyImplementationVersion: snapshot.implementationVersion,
    strategyLifecycle: snapshot.lifecycle.name,
    marketRegime: MarketRegime.range,
  );

  test('Use in Robot binds exact evaluated snapshot and survives restart', () {
    final strategy = module();
    final snapshot = strategy.snapshot(
      const <String, Object?>{'cadence': 'balanced'},
    )!;
    final binding = StrategyRobotBinding.fromEvaluatedIdea(
      evaluationRunId: 'evaluation-43',
      idea: idea(snapshot),
    );

    expect(binding, isNotNull);
    final restored = StrategyRobotBinding.tryFromJson(binding!.toJson());
    expect(restored, isNotNull);
    expect(restored!.evaluationRunId, 'evaluation-43');
    expect(restored.snapshotHash, snapshot.snapshotHash);
    expect(restored.resolveExact(StrategyRegistry(<StrategyModule>[strategy])), isNotNull);
  });

  test('current-latest cannot silently replace the evaluated version', () {
    final evaluatedModule = module(version: '1.0.0');
    final snapshot = evaluatedModule.snapshot(
      const <String, Object?>{'cadence': 'balanced'},
    )!;
    final binding = StrategyRobotBinding.fromEvaluatedIdea(
      evaluationRunId: 'evaluation-43',
      idea: idea(snapshot),
    )!;

    final newerOnlyRegistry = StrategyRegistry(<StrategyModule>[
      module(version: '2.0.0'),
    ]);

    expect(binding.resolveExact(newerOnlyRegistry), isNull);
  });

  test('tampered parameter snapshot fails closed before robot execution', () {
    final strategy = module();
    final snapshot = strategy.snapshot(
      const <String, Object?>{'cadence': 'balanced'},
    )!;
    final persisted = StrategyRobotBinding.fromEvaluatedIdea(
      evaluationRunId: 'evaluation-43',
      idea: idea(snapshot),
    )!.toJson();
    persisted['normalizedParameters'] = <String, Object?>{'cadence': 'active'};

    final restored = StrategyRobotBinding.tryFromJson(persisted)!;
    expect(restored.resolveExact(StrategyRegistry(<StrategyModule>[strategy])), isNull);
  });

  test('legacy idea without registry identity cannot arm exact binding', () {
    final legacy = idea(
      module().snapshot(const <String, Object?>{'cadence': 'balanced'})!,
    ).copyWithRegistryIdentity(
      registryStrategyId: '',
      registryStrategyVersion: '',
      strategyParameterSchemaVersion: 0,
      normalizedStrategyParameters: const <String, Object?>{},
      strategySnapshotHash: '',
      managementPolicyVersion: '',
      strategyImplementationVersion: '',
      strategyLifecycle: '',
    );

    expect(
      StrategyRobotBinding.fromEvaluatedIdea(
        evaluationRunId: 'evaluation-legacy',
        idea: legacy,
      ),
      isNull,
    );
  });
}
