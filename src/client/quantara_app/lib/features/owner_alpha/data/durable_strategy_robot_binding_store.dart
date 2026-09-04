import 'dart:convert';

import '../application/strategy_robot_binding.dart';

abstract interface class StrategyRobotBindingKeyValueStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

/// Persists the exact tested strategy identity selected for the robot.
///
/// The store intentionally contains no execution authority. Runtime code must
/// still resolve [StrategyRobotBinding.resolveExact] against the registry and
/// pass every execution/safety overlay before any entry can be enabled.
final class DurableStrategyRobotBindingStore {
  DurableStrategyRobotBindingStore({
    required this.keyValueStore,
    this.storageKey = 'quantara.robot-strategy-binding-v1',
  }) {
    if (storageKey.trim().isEmpty) {
      throw ArgumentError.value(storageKey, 'storageKey');
    }
  }

  final StrategyRobotBindingKeyValueStore keyValueStore;
  final String storageKey;
  Future<void> _writeTail = Future.value();

  Future<StrategyRobotBinding?> load() async {
    final raw = await keyValueStore.read(storageKey);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<Object?, Object?>) return null;
      final json = <String, Object?>{};
      for (final entry in decoded.entries) {
        if (entry.key is! String) return null;
        json[entry.key! as String] = entry.value;
      }
      return StrategyRobotBinding.tryFromJson(json);
    } on Object {
      return null;
    }
  }

  Future<void> save(StrategyRobotBinding binding) {
    final operation = _writeTail.then(
      (_) => keyValueStore.write(storageKey, jsonEncode(binding.toJson())),
    );
    _writeTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<void> clear() {
    final operation = _writeTail.then((_) => keyValueStore.delete(storageKey));
    _writeTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }
}
