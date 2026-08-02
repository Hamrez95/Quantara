import 'package:shared_preferences/shared_preferences.dart';

import 'durable_candidate_audit_store.dart';

final class SharedPreferencesCandidateAuditKeyValueStore
    implements CandidateAuditKeyValueStore {
  SharedPreferencesCandidateAuditKeyValueStore({
    SharedPreferencesAsync? preferences,
  }) : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  @override
  Future<String?> read(String key) => _preferences.getString(key);

  @override
  Future<void> write(String key, String value) =>
      _preferences.setString(key, value);
}
