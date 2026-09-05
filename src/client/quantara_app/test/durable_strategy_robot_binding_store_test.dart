import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/owner_alpha/application/strategy_robot_binding.dart';
import 'package:quantara_app/features/owner_alpha/data/durable_strategy_robot_binding_store.dart';

void main() {
  StrategyRobotBinding binding() => const StrategyRobotBinding(
    evaluationRunId: 'evaluation-43',
    setupId: 'setup-43',
    strategyId: 'structure_zones',
    strategyVersion: '1.0.0',
    parameterSchemaVersion: 1,
    normalizedParameters: <String, Object?>{'cadence': 'balanced'},
    snapshotHash: 'abc123',
    managementPolicyVersion: 'structure-zones-management/1.0',
    implementationVersion: 'professional-strategy/1.0',
    symbol: 'BTCUSDT',
    timeframe: '15m',
  );

  test('persists and restores the exact tested robot binding', () async {
    final keyValue = _MemoryKeyValueStore();
    final store = DurableStrategyRobotBindingStore(keyValueStore: keyValue);

    await store.save(binding());
    final restored = await store.load();

    expect(restored, isNotNull);
    expect(restored!.evaluationRunId, 'evaluation-43');
    expect(restored.strategyId, 'structure_zones');
    expect(restored.strategyVersion, '1.0.0');
    expect(restored.snapshotHash, 'abc123');
    expect(restored.normalizedParameters, <String, Object?>{
      'cadence': 'balanced',
    });
  });

  test('corrupted persisted data fails closed instead of restoring', () async {
    final keyValue = _MemoryKeyValueStore();
    final store = DurableStrategyRobotBindingStore(keyValueStore: keyValue);
    await keyValue.write(store.storageKey, '{not-json');

    expect(await store.load(), isNull);
  });

  test('clear removes armed strategy identity', () async {
    final keyValue = _MemoryKeyValueStore();
    final store = DurableStrategyRobotBindingStore(keyValueStore: keyValue);
    await store.save(binding());

    await store.clear();

    expect(await store.load(), isNull);
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
