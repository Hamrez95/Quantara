import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  static const _languageKey = 'quantara.preferences.language';
  static const _themeKey = 'quantara.preferences.theme';

  @override
  Future<AppPreferences?> load() async {
    try {
      final preferences = SharedPreferencesAsync();
      final languageCode = await preferences.getString(_languageKey);
      final themeMode = await preferences.getString(_themeKey);
      if (languageCode == null || themeMode == null) {
        return null;
      }
      if (languageCode != 'fa' && languageCode != 'en') {
        return null;
      }
      if (themeMode != 'light' && themeMode != 'dark') {
        return null;
      }
      return AppPreferences(
        languageCode: languageCode,
        themeMode: themeMode == 'light' ? ThemeMode.light : ThemeMode.dark,
      );
    } on Object {
      return null;
    }
  }

  @override
  Future<void> save(AppPreferences preferences) async {
    try {
      final store = SharedPreferencesAsync();
      await store.setString(_languageKey, preferences.languageCode);
      await store.setString(_themeKey, preferences.themeMode.name);
    } on Object {
      // A persistence failure must not block language or theme changes.
    }
  }
}
