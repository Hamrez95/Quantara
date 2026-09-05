import 'package:shared_preferences/shared_preferences.dart';

import 'durable_strategy_robot_binding_store.dart';

/// Platform persistence adapter for the selected Guarded Auto strategy identity.
///
/// Only serialized configuration evidence is stored here. No credential,
/// exchange session, order intent, or execution authority is persisted.
final class PlatformStrategyRobotBindingKeyValueStore
    implements StrategyRobotBindingKeyValueStore {
  const PlatformStrategyRobotBindingKeyValueStore();

  @override
  Future<void> delete(String key) async {
    await SharedPreferencesAsync().remove(key);
  }

  @override
  Future<String?> read(String key) => SharedPreferencesAsync().getString(key);

  @override
  Future<void> write(String key, String value) async {
    await SharedPreferencesAsync().setString(key, value);
  }
}
