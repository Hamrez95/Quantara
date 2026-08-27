import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

abstract interface class AppUpdateRolloutStore {
  Future<int> loadOrCreateBucket();
}

final class PlatformAppUpdateRolloutStore implements AppUpdateRolloutStore {
  const PlatformAppUpdateRolloutStore();

  static const _key = 'quantara.app-update.rollout-bucket-v1';

  @override
  Future<int> loadOrCreateBucket() async {
    final preferences = SharedPreferencesAsync();
    final existing = await preferences.getInt(_key);
    if (existing != null) {
      if (existing < 0 || existing > 99) {
        throw const FormatException('Saved update rollout bucket is invalid.');
      }
      return existing;
    }

    final created = Random.secure().nextInt(100);
    await preferences.setInt(_key, created);
    return created;
  }
}
