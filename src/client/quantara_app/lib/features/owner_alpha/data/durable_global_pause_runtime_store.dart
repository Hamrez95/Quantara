import 'dart:convert';

import '../application/global_pause_runtime_policy.dart';

abstract interface class GlobalPauseRuntimeKeyValueStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);
}

final class DurableGlobalPauseRuntimeSnapshot {
  const DurableGlobalPauseRuntimeSnapshot({
    required this.mode,
    required this.pauseFullyWhenFlat,
    required this.updatedAtUtc,
  });

  final GlobalPauseRuntimeMode mode;
  final bool pauseFullyWhenFlat;
  final DateTime updatedAtUtc;

  bool get allowsNewScanning => mode == GlobalPauseRuntimeMode.running;

  bool get requiresPrivateManagement =>
      mode == GlobalPauseRuntimeMode.safePausedManagingExisting;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'mode': mode.name,
    'pauseFullyWhenFlat': pauseFullyWhenFlat,
    'updatedAtUtc': updatedAtUtc.toUtc().toIso8601String(),
  };
}

/// Persists the canonical Global Pause intent across process death and updates.
///
/// A paused runtime is sticky: restore never upgrades a stored paused state to
/// running. A process that died while `resuming` is restored to Safe Pause so
/// private position/order management can continue until fresh exchange truth is
/// reconciled. Corrupt state also fails closed to Safe Pause rather than
/// silently enabling scanning or new-entry work.
final class DurableGlobalPauseRuntimeStore {
  DurableGlobalPauseRuntimeStore({
    required this.keyValueStore,
    this.storageKey = 'quantara.global-pause-runtime-v1',
  }) {
    if (storageKey.trim().isEmpty) {
      throw ArgumentError.value(storageKey, 'storageKey');
    }
  }

  final GlobalPauseRuntimeKeyValueStore keyValueStore;
  final String storageKey;
  Future<void> _writeTail = Future<void>.value();

  Future<DurableGlobalPauseRuntimeSnapshot> restore() async {
    final raw = await keyValueStore.read(storageKey);
    if (raw == null || raw.trim().isEmpty) {
      // Backward-compatible migration for installs that predate Global Pause.
      return DurableGlobalPauseRuntimeSnapshot(
        mode: GlobalPauseRuntimeMode.running,
        pauseFullyWhenFlat: false,
        updatedAtUtc: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<Object?, Object?>) return _failClosedSnapshot();
      if (decoded['schemaVersion'] != 1) return _failClosedSnapshot();
      final rawMode = decoded['mode'];
      final pauseFullyWhenFlat = decoded['pauseFullyWhenFlat'];
      final updatedAtUtc = decoded['updatedAtUtc'];
      if (rawMode is! String ||
          pauseFullyWhenFlat is! bool ||
          updatedAtUtc is! String) {
        return _failClosedSnapshot();
      }
      final parsedUpdatedAt = DateTime.tryParse(updatedAtUtc)?.toUtc();
      final persistedMode = _parseMode(rawMode);
      if (parsedUpdatedAt == null || persistedMode == null) {
        return _failClosedSnapshot();
      }

      final restoredMode = persistedMode == GlobalPauseRuntimeMode.resuming
          ? GlobalPauseRuntimeMode.safePausedManagingExisting
          : persistedMode;
      return DurableGlobalPauseRuntimeSnapshot(
        mode: restoredMode,
        pauseFullyWhenFlat: pauseFullyWhenFlat,
        updatedAtUtc: parsedUpdatedAt,
      );
    } on Object {
      return _failClosedSnapshot();
    }
  }

  Future<void> persist({
    required GlobalPauseRuntimeMode mode,
    required bool pauseFullyWhenFlat,
    DateTime? updatedAtUtc,
  }) {
    final snapshot = DurableGlobalPauseRuntimeSnapshot(
      mode: mode,
      pauseFullyWhenFlat: pauseFullyWhenFlat,
      updatedAtUtc: (updatedAtUtc ?? DateTime.now()).toUtc(),
    );
    return _enqueue(
      () => keyValueStore.write(storageKey, jsonEncode(snapshot.toJson())),
    );
  }

  DurableGlobalPauseRuntimeSnapshot _failClosedSnapshot() {
    return DurableGlobalPauseRuntimeSnapshot(
      mode: GlobalPauseRuntimeMode.safePausedManagingExisting,
      pauseFullyWhenFlat: true,
      updatedAtUtc: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  GlobalPauseRuntimeMode? _parseMode(String rawMode) {
    for (final candidate in GlobalPauseRuntimeMode.values) {
      if (candidate.name == rawMode) return candidate;
    }
    return null;
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final result = _writeTail.then((_) => operation());
    _writeTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }
}
