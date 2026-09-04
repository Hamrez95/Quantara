import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/market_analysis/domain/market_regime_models.dart';
import 'package:quantara_app/features/owner_alpha/application/strategy_robot_binding_controller.dart';
import 'package:quantara_app/features/owner_alpha/data/durable_strategy_robot_binding_store.dart';
import 'package:quantara_app/features/owner_alpha/data/professional_strategy_engine.dart';
import 'package:quantara_app/features/owner_alpha/data/strategy_registry.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';
import 'package:quantara_app/features/owner_alpha/presentation/strategy_robot_handoff_card.dart';

void main() {
  StrategyModule module() => StrategyModule(
    selection: AnalysisStrategy.structureZones,
    strategyId: 'structure_zones',
    humanName: 'Structure Zones',
    strategyVersion: '1.0.0',
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

  testWidgets('Use in Robot confirms exact version before persisting', (
    tester,
  ) async {
    final strategy = module();
    final snapshot = strategy.snapshot(const <String, Object?>{
      'cadence': 'balanced',
    })!;
    final controller = StrategyRobotBindingController(
      store: DurableStrategyRobotBindingStore(
        keyValueStore: _MemoryKeyValueStore(),
      ),
      registry: StrategyRegistry(<StrategyModule>[strategy]),
    );
    var setupOpens = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StrategyRobotHandoffCard(
            controller: controller,
            runtimeState: StrategyRobotBindingRuntimeState.disarmed,
            evaluationRunId: 'evaluation-43',
            idea: idea(snapshot),
            persian: false,
            onOpenRobotSetup: () => setupOpens += 1,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('use-in-robot-action')));
    await tester.pumpAndSettle();

    expect(controller.binding, isNull);
    expect(setupOpens, 0);
    expect(find.text('Use this exact version?'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('strategy-robot-confirmation-summary')),
      findsOneWidget,
    );
    expect(find.textContaining('structure_zones v1.0.0'), findsOneWidget);
    expect(find.textContaining('BTCUSDT/15m'), findsOneWidget);
    expect(find.textContaining('evaluation-43'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('strategy-robot-confirm-action')),
    );
    await tester.pumpAndSettle();

    expect(setupOpens, 1);
    expect(controller.binding, isNotNull);
    expect(controller.binding!.strategyId, 'structure_zones');
    expect(controller.binding!.strategyVersion, '1.0.0');
    expect(controller.binding!.evaluationRunId, 'evaluation-43');
    expect(find.textContaining('structure_zones v1.0.0'), findsWidgets);
  });

  testWidgets('cancel leaves the exact robot binding unchanged', (tester) async {
    final strategy = module();
    final snapshot = strategy.snapshot(const <String, Object?>{
      'cadence': 'balanced',
    })!;
    final controller = StrategyRobotBindingController(
      store: DurableStrategyRobotBindingStore(
        keyValueStore: _MemoryKeyValueStore(),
      ),
      registry: StrategyRegistry(<StrategyModule>[strategy]),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StrategyRobotHandoffCard(
            controller: controller,
            runtimeState: StrategyRobotBindingRuntimeState.disarmed,
            evaluationRunId: 'evaluation-43',
            idea: idea(snapshot),
            persian: false,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('use-in-robot-action')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('strategy-robot-cancel-action')),
    );
    await tester.pumpAndSettle();

    expect(controller.binding, isNull);
    expect(find.text('Use this exact version?'), findsNothing);
  });

  testWidgets('running runtime disables handoff and clear mutation', (
    tester,
  ) async {
    final strategy = module();
    final snapshot = strategy.snapshot(const <String, Object?>{
      'cadence': 'balanced',
    })!;
    final controller = StrategyRobotBindingController(
      store: DurableStrategyRobotBindingStore(
        keyValueStore: _MemoryKeyValueStore(),
      ),
      registry: StrategyRegistry(<StrategyModule>[strategy]),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StrategyRobotHandoffCard(
            controller: controller,
            runtimeState: StrategyRobotBindingRuntimeState.running,
            evaluationRunId: 'evaluation-43',
            idea: idea(snapshot),
            persian: false,
          ),
        ),
      ),
    );

    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('use-in-robot-action')),
    );
    expect(button.onPressed, isNull);
    expect(controller.binding, isNull);
  });
}

final class _MemoryKeyValueStore implements StrategyRobotBindingKeyValueStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}
