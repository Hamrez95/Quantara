import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/market_analysis/domain/market_regime_models.dart';
import 'package:quantara_app/features/owner_alpha/data/professional_strategy_engine.dart';
import 'package:quantara_app/features/owner_alpha/data/strategy_registry.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';

void main() {
  StrategyModule module({
    required AnalysisStrategy selection,
    required String id,
    String version = '1.0.0',
    StrategyLifecycle lifecycle = StrategyLifecycle.active,
  }) => StrategyModule(
    selection: selection,
    strategyId: id,
    humanName: id,
    strategyVersion: version,
    parameterSchemaVersion: 1,
    parameterDefaults: const <String, Object?>{
      'alpha': 1,
      'beta': 2,
      'cadence': 'balanced',
    },
    supportedTimeframes: const <String>{'15m'},
    capabilities: const <String>{'deterministic_entry'},
    entrySemantics: 'deterministic',
    initialStopSemantics: 'deterministic',
    targetPlan: 'deterministic',
    invalidationRules: 'deterministic',
    managementPolicyVersion: 'management/1.0',
    implementationVersion: ProfessionalStrategyEngine.version,
    lifecycle: lifecycle,
  );

  test('two strategies resolve through one canonical new-run contract', () {
    final registry = StrategyRegistry.standard();

    final structure = registry.resolveForNewRun(
      selection: AnalysisStrategy.structureZones,
      symbol: 'BTCUSDT',
      timeframe: '15m',
      parameters: const <String, Object?>{'cadence': 'balanced'},
    );
    final pullback = registry.resolveForNewRun(
      selection: AnalysisStrategy.trendPullback,
      symbol: 'ETHUSDT',
      timeframe: '15m',
      parameters: const <String, Object?>{'cadence': 'balanced'},
    );

    expect(structure, isNotNull);
    expect(pullback, isNotNull);
    expect(structure!.snapshot.strategyId, 'structure_zones');
    expect(pullback!.snapshot.strategyId, 'trend_pullback');
    expect(structure.module.evaluate, isA<Function>());
    expect(pullback.module.evaluate, isA<Function>());
  });

  test('parameter ordering normalizes to the same snapshot hash', () {
    final strategy = module(
      selection: AnalysisStrategy.structureZones,
      id: 'ordered',
    );

    final first = strategy.snapshot(const <String, Object?>{
      'alpha': 4,
      'beta': 7,
      'cadence': 'active',
    });
    final second = strategy.snapshot(const <String, Object?>{
      'cadence': 'active',
      'beta': 7,
      'alpha': 4,
    });

    expect(first, isNotNull);
    expect(second, isNotNull);
    expect(first!.normalizedParameters, second!.normalizedParameters);
    expect(first.snapshotHash, second.snapshotHash);
  });

  test('version change changes immutable identity and hash', () {
    final v1 = module(
      selection: AnalysisStrategy.structureZones,
      id: 'versioned',
      version: '1.0.0',
    ).snapshot(const <String, Object?>{'cadence': 'balanced'});
    final v2 = module(
      selection: AnalysisStrategy.structureZones,
      id: 'versioned',
      version: '2.0.0',
    ).snapshot(const <String, Object?>{'cadence': 'balanced'});

    expect(v1, isNotNull);
    expect(v2, isNotNull);
    expect(v1!.strategyVersion, isNot(v2!.strategyVersion));
    expect(v1.snapshotHash, isNot(v2.snapshotHash));
  });

  test('disabled strategy remains historically readable but cannot start', () {
    final disabled = module(
      selection: AnalysisStrategy.structureZones,
      id: 'disabled',
      lifecycle: StrategyLifecycle.disabledForNewRuns,
    );
    final registry = StrategyRegistry(<StrategyModule>[disabled]);

    final newRun = registry.resolveForNewRun(
      selection: AnalysisStrategy.structureZones,
      symbol: 'BTCUSDT',
      timeframe: '15m',
      parameters: const <String, Object?>{'cadence': 'balanced'},
    );
    final historical = registry.historical(
      strategyId: 'disabled',
      strategyVersion: '1.0.0',
    );

    expect(newRun, isNull);
    expect(historical, same(disabled));
  });

  test('unknown requested live version fails closed', () {
    final registry = StrategyRegistry(<StrategyModule>[
      module(selection: AnalysisStrategy.structureZones, id: 'known'),
    ]);

    final resolution = registry.resolveForNewRun(
      selection: AnalysisStrategy.structureZones,
      symbol: 'BTCUSDT',
      timeframe: '15m',
      parameters: const <String, Object?>{'cadence': 'balanced'},
      requiredVersion: '9.9.9',
    );

    expect(resolution, isNull);
  });

  test('archived snapshot remains readable without a registered module', () {
    final snapshot = module(
      selection: AnalysisStrategy.structureZones,
      id: 'removed-later',
    ).snapshot(const <String, Object?>{'cadence': 'balanced'});
    expect(snapshot, isNotNull);

    final restored = StrategySnapshotIdentity.tryFromJson(snapshot!.toJson());
    final emptyRegistry = StrategyRegistry(const <StrategyModule>[]);

    expect(restored, isNotNull);
    expect(restored!.strategyId, 'removed-later');
    expect(restored.snapshotHash, snapshot.snapshotHash);
    expect(
      emptyRegistry.historical(
        strategyId: restored.strategyId,
        strategyVersion: restored.strategyVersion,
      ),
      isNull,
    );
  });

  test('journal round-trip preserves immutable strategy attribution', () {
    final idea = TradeIdea(
      symbol: 'BTCUSDT',
      timeframe: '15m',
      direction: TradeDirection.long,
      confidencePercent: 75,
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
      setupId: 'setup-1',
      candleClosedAt: DateTime.utc(2026, 9, 4),
      summary: 'test',
      invalidation: 'test',
      reasons: const <String>['test'],
      strategy: AnalysisStrategy.structureZones,
      strategyVersion: 'rangeReversal/1.0',
      registryStrategyId: 'structure_zones',
      registryStrategyVersion: '1.0.0',
      strategyParameterSchemaVersion: 1,
      normalizedStrategyParameters: const <String, Object?>{
        'cadence': 'balanced',
      },
      strategySnapshotHash: 'snapshot-hash',
      managementPolicyVersion: 'management/1.0',
      strategyImplementationVersion: ProfessionalStrategyEngine.version,
      strategyLifecycle: StrategyLifecycle.active.name,
      marketRegime: MarketRegime.range,
    );

    final persisted = SignalJournalEntry.fromIdea(idea).toJson();
    final restored = SignalJournalEntry.tryFromJson(persisted);

    expect(restored, isNotNull);
    expect(restored!.strategyVersion, 'rangeReversal/1.0');
    expect(restored.registryStrategyId, 'structure_zones');
    expect(restored.registryStrategyVersion, '1.0.0');
    expect(restored.strategyParameterSchemaVersion, 1);
    expect(restored.normalizedStrategyParameters['cadence'], 'balanced');
    expect(restored.strategySnapshotHash, 'snapshot-hash');
    expect(restored.managementPolicyVersion, 'management/1.0');
    expect(
      restored.strategyImplementationVersion,
      ProfessionalStrategyEngine.version,
    );
  });
}
