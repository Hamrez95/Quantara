import 'dart:convert';

import '../application/guarded_auto_operational_state.dart';

abstract interface class GuardedAutoOperationalKeyValueStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);
}

/// Crash/restart durable stop-state store. Missing or corrupt data is restored
/// as paused unknown state, never as an enabled execution state.
final class DurableGuardedAutoOperationalStore {
  DurableGuardedAutoOperationalStore({
    required this.keyValueStore,
    this.storageKey = 'quantara.guarded-auto-operational-v1',
  });

  final GuardedAutoOperationalKeyValueStore keyValueStore;
  final String storageKey;
  Future<void> _writeTail = Future.value();

  Future<GuardedAutoOperationalState> load({required DateTime nowUtc}) async {
    final raw = await keyValueStore.read(storageKey);
    if (raw == null || raw.trim().isEmpty) {
      return GuardedAutoOperationalState.paused(
        cause: GuardedAutoPauseCause.restoredUnknownState,
        atUtc: nowUtc,
        operatorAction: 'Review state and explicitly recover to disarmed.',
      );
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<Object?, Object?>) {
        final json = <String, Object?>{};
        for (final entry in decoded.entries) {
          if (entry.key is! String) return _unknown(nowUtc);
          json[entry.key! as String] = entry.value;
        }
        return GuardedAutoOperationalState.tryFromJson(json) ?? _unknown(nowUtc);
      }
    } on Object {
      // Deliberately fail closed below.
    }
    return _unknown(nowUtc);
  }

  Future<void> save(GuardedAutoOperationalState state) {
    final operation = _writeTail.then(
      (_) => keyValueStore.write(storageKey, jsonEncode(state.toJson())),
    );
    _writeTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  GuardedAutoOperationalState _unknown(DateTime nowUtc) =>
      GuardedAutoOperationalState.paused(
        cause: GuardedAutoPauseCause.restoredUnknownState,
        atUtc: nowUtc,
        operatorAction: 'Review state and explicitly recover to disarmed.',
      );
}
