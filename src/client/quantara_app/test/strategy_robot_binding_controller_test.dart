import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/market_analysis/domain/market_regime_models.dart';
import 'package:quantara_app/features/owner_alpha/application/strategy_robot_binding_controller.dart';
import 'package:quantara_app/features/owner_alpha/data/durable_strategy_robot_binding_store.dart';
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

  test(
    'Use in Robot persists exact identity but grants no execution state',
    () async {
      final strategy = module();
      final snapshot = strategy.snapshot(const <String, Object?>{
        'cadence': 'balanced',
      })!;
      final memory = _MemoryKeyValueStore();
      final controller = StrategyRobotBindingController(
        store: DurableStrategyRobotBindingStore(keyValueStore: memory),
        registry: StrategyRegistry(<StrategyModule>[strategy]),
      );

      expect(
        await controller.useInRobot(
          evaluationRunId: 'evaluation-43',
          idea: idea(snapshot),
          runtimeState: StrategyRobotBindingRuntimeState.disarmed,
        ),
        isTrue,
      );
      expect(controller.hasResolvableBinding, isTrue);
      expect(controller.binding!.snapshotHash, snapshot.snapshotHash);

      final restarted = StrategyRobotBindingController(
        store: DurableStrategyRobotBindingStore(keyValueStore: memory),
        registry: StrategyRegistry(<StrategyModule>[strategy]),
      );
      await restarted.initialize();
      expect(restarted.hasResolvableBinding, isTrue);
      expect(restarted.binding!.evaluationRunId, 'evaluation-43');
    },
  );

  test('running and unknown runtime states reject binding without mutation', () async {
    final strategy = module();
    final snapshot = strategy.snapshot(const <String, Object?>{
      'cadence': 'balanced',
    })!;
    final memory = _MemoryKeyValueStore();
    final store = DurableStrategyRobotBindingStore(keyValueStore: memory);
    final controller = StrategyRobotBindingController(
      store: store,
      registry: StrategyRegistry(<StrategyModule>[strategy]),
    );

    for (final runtimeState in <StrategyRobotBindingRuntimeState>[
      StrategyRobotBindingRuntimeState.running,
      StrategyRobotBindingRuntimeState.unknown,
    ]) {
      expect(
        await controller.useInRobot(
          evaluationRunId: 'evaluation-43',
          idea: idea(snapshot),
          runtimeState: runtimeState,
        ),
        isFalse,
      );
    }

    expect(controller.binding, isNull);
    expect(await store.load(), isNull);
  });

  test('catalog drift restores evidence but fails closed', () async {
    final evaluated = module();
    final snapshot = evaluated.snapshot(const <String, Object?>{
      'cadence': 'balanced',
    })!;
    final memory = _MemoryKeyValueStore();
    final original = StrategyRobotBindingController(
      store: DurableStrategyRobotBindingStore(keyValueStore: memory),
      registry: StrategyRegistry(<StrategyModule>[evaluated]),
    );
    await original.useInRobot(
      evaluationRunId: 'evaluation-43',
      idea: idea(snapshot),
      runtimeState: StrategyRobotBindingRuntimeState.disarmed,
    );

    final restarted = StrategyRobotBindingController(
      store: DurableStrategyRobotBindingStore(keyValueStore: memory),
      registry: StrategyRegistry(<StrategyModule>[module(version: '2.0.0')]),
    );
    await restarted.initialize();

    expect(restarted.binding, isNotNull);
    expect(restarted.resolution, isNull);
    expect(restarted.hasResolvableBinding, isFalse);
  });

  test('clear rejects a running runtime and succeeds only when disarmed', () async {
    final strategy = module();
    final snapshot = strategy.snapshot(const <String, Object?>{
      'cadence': 'balanced',
    })!;
    final memory = _MemoryKeyValueStore();
    final controller = StrategyRobotBindingController(
      store: DurableStrategyRobotBindingStore(keyValueStore: memory),
      registry: StrategyRegistry(<StrategyModule>[strategy]),
    );
    await controller.useInRobot(
      evaluationRunId: 'evaluation-43',
      idea: idea(snapshot),
      runtimeState: StrategyRobotBindingRuntimeState.disarmed,
    );

    expect(
      await controller.clear(
        runtimeState: StrategyRobotBindingRuntimeState.running,
      ),
      isFalse,
    );
    expect(controller.binding, isNotNull);
    expect(
      await controller.clear(
        runtimeState: StrategyRobotBindingRuntimeState.disarmed,
      ),
      isTrue,
    );

    final restarted = StrategyRobotBindingController(
      store: DurableStrategyRobotBindingStore(keyValueStore: memory),
      registry: StrategyRegistry(<StrategyModule>[strategy]),
    );
    await restarted.initialize();
    expect(restarted.binding, isNull);
    expect(restarted.hasResolvableBinding, isFalse);
  });
}

final class _MemoryKeyValueStore implements StrategyRobotBindingKeyValueStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}
