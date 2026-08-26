import 'package:shared_preferences/shared_preferences.dart';

import '../domain/app_update_models.dart';

abstract interface class AppUpdateChannelStore {
  Future<AppReleaseChannel?> load();

  Future<void> save(AppReleaseChannel channel);
}

final class PlatformAppUpdateChannelStore implements AppUpdateChannelStore {
  const PlatformAppUpdateChannelStore();

  static const _key = 'quantara.app-update.channel-v1';

  @override
  Future<AppReleaseChannel?> load() async {
    final preferences = SharedPreferencesAsync();
    final raw = await preferences.getString(_key);
    if (raw == null) return null;
    for (final channel in AppReleaseChannel.values) {
      if (channel.name == raw) return channel;
    }
    throw const FormatException('Saved update channel is invalid.');
  }

  @override
  Future<void> save(AppReleaseChannel channel) async {
    final preferences = SharedPreferencesAsync();
    await preferences.setString(_key, channel.name);
  }
}
