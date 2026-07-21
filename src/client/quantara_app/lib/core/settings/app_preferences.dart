import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  const PlatformAppPreferencesStore({
    MethodChannel channel = const MethodChannel('quantara/settings'),
  }) : _channel = channel;

  final MethodChannel _channel;

  @override
  Future<AppPreferences?> load() async {
    try {
      final value = await _channel.invokeMapMethod<String, Object?>(
        'loadAppPreferences',
      );
      if (value == null) {
        return null;
      }
      final languageCode = value['languageCode'];
      final themeMode = value['themeMode'];
      if (languageCode is! String || themeMode is! String) {
        return null;
      }
      if (languageCode != 'fa' && languageCode != 'en') {
        return null;
      }
      return AppPreferences(
        languageCode: languageCode,
        themeMode: themeMode == 'light' ? ThemeMode.light : ThemeMode.dark,
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<void> save(AppPreferences preferences) async {
    try {
      await _channel.invokeMethod<void>('saveAppPreferences', {
        'languageCode': preferences.languageCode,
        'themeMode': preferences.themeMode.name,
      });
    } on PlatformException {
      // A persistence failure must not block language or theme changes.
    } on MissingPluginException {
      // Widget tests and non-Android previews intentionally have no channel.
    }
  }
}
