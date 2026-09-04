import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/owner_alpha/application/global_pause_background_gate.dart';
import 'package:quantara_app/features/owner_alpha/application/global_pause_runtime_policy.dart';
import 'package:quantara_app/features/owner_alpha/data/durable_global_pause_runtime_store.dart';

void main() {
  test('running durable state allows background scanning', () async {
    final memory = _MemoryStore();
    final store = DurableGlobalPauseRuntimeStore(keyValueStore: memory);
    await store.persist(
      mode: GlobalPauseRuntimeMode.running,
      pauseFullyWhenFlat: false,
    );

    final allowed = await GlobalPauseBackgroundGate(
      store: store,
    ).allowsNewScanning();

    expect(allowed, isTrue);
  });

  test('offline pause blocks background scanning after restart', () async {
    final memory = _MemoryStore();
    final store = DurableGlobalPauseRuntimeStore(keyValueStore: memory);
    await store.persist(
      mode: GlobalPauseRuntimeMode.pausedOffline,
      pauseFullyWhenFlat: false,
    );

    final restoredStore = DurableGlobalPauseRuntimeStore(keyValueStore: memory);
    final allowed = await GlobalPauseBackgroundGate(
      store: restoredStore,
    ).allowsNewScanning();

    expect(allowed, isFalse);
  });

  test('safe pause and interrupted resume both block background scanning', () async {
    for (final mode in <GlobalPauseRuntimeMode>[
      GlobalPauseRuntimeMode.safePausedManagingExisting,
      GlobalPauseRuntimeMode.resuming,
    ]) {
      final memory = _MemoryStore();
      final store = DurableGlobalPauseRuntimeStore(keyValueStore: memory);
      await store.persist(mode: mode, pauseFullyWhenFlat: true);

      final allowed = await GlobalPauseBackgroundGate(
        store: DurableGlobalPauseRuntimeStore(keyValueStore: memory),
      ).allowsNewScanning();

      expect(allowed, isFalse, reason: mode.name);
    }
  });

  test('corrupt durable state fails closed', () async {
    final memory = _MemoryStore()..value = '{broken';
    final allowed = await GlobalPauseBackgroundGate(
      store: DurableGlobalPauseRuntimeStore(keyValueStore: memory),
    ).allowsNewScanning();

    expect(allowed, isFalse);
  });

  test('storage read failure fails closed', () async {
    final allowed = await GlobalPauseBackgroundGate(
      store: DurableGlobalPauseRuntimeStore(keyValueStore: _ThrowingStore()),
    ).allowsNewScanning();

    expect(allowed, isFalse);
  });
}

final class _MemoryStore implements GlobalPauseRuntimeKeyValueStore {
  String? value;

  @override
  Future<String?> read(String key) async => value;

  @override
  Future<void> write(String key, String value) async {
    this.value = value;
  }
}

final class _ThrowingStore implements GlobalPauseRuntimeKeyValueStore {
  @override
  Future<String?> read(String key) => Future<String?>.error(StateError('read'));

  @override
  Future<void> write(String key, String value) async {}
}
