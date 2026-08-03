import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../persistence/quantara_database_provider.dart';
import '../persistence/quantara_durable_database.dart';

final class AppPreferences {
  const AppPreferences({required this.languageCode, required this.themeMode});

  final String languageCode;
  final ThemeMode themeMode;
}

abstract interface class AppPreferencesStore {
  Future<AppPreferences?> load();

  Future<void> save(AppPreferences preferences);
}

final class PlatformAppPreferencesStore implements AppPreferencesStore {
  const PlatformAppPreferencesStore();

  static const _recordKey = 'app-preferences';
  static const _languageKey = 'quantara.preferences.language';
  static const _themeKey = 'quantara.preferences.theme';

  @override
  Future<AppPreferences?> load() async {
    try {
      final database = await QuantaraDatabaseProvider.instance;
      final record = await database.read(
        QuantaraDurableCategory.settings,
        _recordKey,
      );
      final durable = record == null ? null : _decode(record.payload);
      if (durable != null) return durable;

      final legacy = SharedPreferencesAsync();
      final migrated = _decode({
        'languageCode': await legacy.getString(_languageKey),
        'themeMode': await legacy.getString(_themeKey),
      });
      if (migrated != null) await _saveDatabase(database, migrated);
      return migrated;
    } on Object {
      return null;
    }
  }

  @override
  Future<void> save(AppPreferences preferences) async {
    try {
      final database = await QuantaraDatabaseProvider.instance;
      await _saveDatabase(database, preferences);
    } on Object {
      // A persistence failure must not block language or theme changes.
    }
  }

  static AppPreferences? _decode(Map<String, Object?> payload) {
    final languageCode = payload['languageCode']?.toString();
    final themeMode = payload['themeMode']?.toString();
    if (languageCode != 'fa' && languageCode != 'en') return null;
    if (themeMode != 'light' && themeMode != 'dark') return null;
    return AppPreferences(
      languageCode: languageCode!,
      themeMode: themeMode == 'light' ? ThemeMode.light : ThemeMode.dark,
    );
  }

  static Future<void> _saveDatabase(
    QuantaraDurableDatabase database,
    AppPreferences preferences,
  ) async {
    final current = await database.read(
      QuantaraDurableCategory.settings,
      _recordKey,
    );
    await database.put(
      QuantaraDurableRecord(
        category: QuantaraDurableCategory.settings,
        key: _recordKey,
        schemaVersion: 1,
        revision: (current?.revision ?? 0) + 1,
        updatedAt: DateTime.now().toUtc(),
        payload: {
          'languageCode': preferences.languageCode,
          'themeMode': preferences.themeMode.name,
        },
      ),
    );
  }
}
