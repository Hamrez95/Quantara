import 'package:shared_preferences/shared_preferences.dart';

import '../domain/local_live_execution_mode.dart';

abstract interface class LocalLiveExecutionModeStore {
  Future<LocalLiveExecutionMode> load();

  Future<void> save(LocalLiveExecutionMode mode);
}

final class SharedPreferencesLocalLiveExecutionModeStore
    implements LocalLiveExecutionModeStore {
  const SharedPreferencesLocalLiveExecutionModeStore();

  static const _key = 'quantara.local-live.execution-mode.v1';

  @override
  Future<LocalLiveExecutionMode> load() async {
    final preferences = await SharedPreferences.getInstance();
    return LocalLiveExecutionModeJson.parse(preferences.getString(_key));
  }

  @override
  Future<void> save(LocalLiveExecutionMode mode) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(_key, mode.wireName);
    if (!saved) {
      throw StateError('Execution mode preference could not be saved.');
    }
  }
}
