import 'package:shared_preferences/shared_preferences.dart';

import 'durable_guarded_auto_operational_store.dart';

/// Platform persistence for Guarded Auto stop-state evidence only.
/// No credentials, orders, exchange sessions, or execution authority live here.
final class PlatformGuardedAutoOperationalKeyValueStore
    implements GuardedAutoOperationalKeyValueStore {
  const PlatformGuardedAutoOperationalKeyValueStore();

  @override
  Future<String?> read(String key) => SharedPreferencesAsync().getString(key);

  @override
  Future<void> write(String key, String value) async {
    await SharedPreferencesAsync().setString(key, value);
  }
}
