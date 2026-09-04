import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/owner_alpha/application/global_pause_runtime_policy.dart';
import 'package:quantara_app/features/owner_alpha/data/durable_global_pause_runtime_store.dart';

void main() {
  test('paused offline survives restart and never resumes implicitly', () async {
    final memory = _MemoryStore();
    final store = DurableGlobalPauseRuntimeStore(keyValueStore: memory);

    await store.persist(
      mode: GlobalPauseRuntimeMode.pausedOffline,
      pauseFullyWhenFlat: true,
      updatedAtUtc: DateTime.utc(2026, 9, 4, 6),
    );

    final restarted = DurableGlobalPauseRuntimeStore(keyValueStore: memory);
    final restored = await restarted.restore();

    expect(restored.mode, GlobalPauseRuntimeMode.pausedOffline);
    expect(restored.pauseFullyWhenFlat, isTrue);
    expect(restored.allowsNewScanning, isFalse);
    expect(restored.requiresPrivateManagement, isFalse);
  });

  test('safe pause survives restart and keeps private management', () async {
    final memory = _MemoryStore();
    final store = DurableGlobalPauseRuntimeStore(keyValueStore: memory);
    await store.persist(
      mode: GlobalPauseRuntimeMode.safePausedManagingExisting,
      pauseFullyWhenFlat: true,
    );

    final restored = await store.restore();

    expect(restored.mode, GlobalPauseRuntimeMode.safePausedManagingExisting);
    expect(restored.allowsNewScanning, isFalse);
    expect(restored.requiresPrivateManagement, isTrue);
  });

  test('resuming after process death degrades to safe pause', () async {
    final memory = _MemoryStore();
    final store = DurableGlobalPauseRuntimeStore(keyValueStore: memory);
    await store.persist(
      mode: GlobalPauseRuntimeMode.resuming,
      pauseFullyWhenFlat: false,
    );

    final restored = await store.restore();

    expect(restored.mode, GlobalPauseRuntimeMode.safePausedManagingExisting);
    expect(restored.allowsNewScanning, isFalse);
    expect(restored.requiresPrivateManagement, isTrue);
  });

  test('corrupt or unknown state fails closed instead of running', () async {
    final memory = _MemoryStore();
    memory.values['quantara.global-pause-runtime-v1'] = jsonEncode(
      <String, Object?>{
        'schemaVersion': 1,
        'mode': 'futureUnknownMode',
        'pauseFullyWhenFlat': false,
        'updatedAtUtc': DateTime.utc(2026, 9, 4).toIso8601String(),
      },
    );
    final store = DurableGlobalPauseRuntimeStore(keyValueStore: memory);

    final restored = await store.restore();

    expect(restored.mode, GlobalPauseRuntimeMode.safePausedManagingExisting);
    expect(restored.pauseFullyWhenFlat, isTrue);
    expect(restored.allowsNewScanning, isFalse);
  });

  test(
    'missing pre-feature state migrates without silently arming anything',
    () async {
      final store = DurableGlobalPauseRuntimeStore(
        keyValueStore: _MemoryStore(),
      );

      final restored = await store.restore();

      expect(restored.mode, GlobalPauseRuntimeMode.running);
      expect(restored.pauseFullyWhenFlat, isFalse);
    },
  );
}

final class _MemoryStore implements GlobalPauseRuntimeKeyValueStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}
