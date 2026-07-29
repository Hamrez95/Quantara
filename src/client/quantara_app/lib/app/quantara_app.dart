import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;

import '../core/settings/app_preferences.dart';
import '../core/theme/quantara_theme.dart';
import '../features/owner_alpha/data/background_opportunity_scanner.dart';
import '../features/owner_alpha/data/bitunix_owner_alpha_repository.dart';
import '../features/owner_alpha/data/platform_owner_alpha_settings_store.dart';
import '../features/owner_alpha/data/platform_opportunity_services.dart';
import '../features/owner_alpha/domain/owner_alpha_models.dart';
import '../features/owner_alpha/presentation/owner_alpha_page.dart';

class QuantaraApp extends StatefulWidget {
  const QuantaraApp({
    super.key,
    this.repository,
    this.settingsStore,
    this.preferencesStore,
    this.opportunityStateStore,
    this.notificationGateway,
    this.backgroundScanGateway,
    this.initialThemeMode = ThemeMode.dark,
    this.initialLocale = const Locale('fa'),
  });

  final OwnerAlphaRepository? repository;
  final OwnerAlphaSettingsStore? settingsStore;
  final AppPreferencesStore? preferencesStore;
  final OpportunityStateStore? opportunityStateStore;
  final SetupNotificationGateway? notificationGateway;
  final BackgroundScanGateway? backgroundScanGateway;
  final ThemeMode initialThemeMode;
  final Locale initialLocale;

  @override
  State<QuantaraApp> createState() => _QuantaraAppState();
}

class _QuantaraAppState extends State<QuantaraApp> {
  late ThemeMode _themeMode = widget.initialThemeMode;
  late Locale _locale = widget.initialLocale;
  http.Client? _ownedClient;
  int _preferencesRevision = 0;
  late final OwnerAlphaRepository _repository;
  late final OwnerAlphaSettingsStore _settingsStore =
      widget.settingsStore ?? const PlatformOwnerAlphaSettingsStore();
  late final AppPreferencesStore _preferencesStore =
      widget.preferencesStore ?? const PlatformAppPreferencesStore();

  @override
  void initState() {
    super.initState();
    final repository = widget.repository;
    if (repository != null) {
      _repository = repository;
    } else {
      final client = http.Client();
      _ownedClient = client;
      _repository = BitunixOwnerAlphaRepository(client: client);
    }
    unawaited(_loadPreferences());
  }

  @override
  void dispose() {
    _ownedClient?.close();
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    final revision = _preferencesRevision;
    final preferences = await _preferencesStore.load();
    if (!mounted || preferences == null || revision != _preferencesRevision) {
      return;
    }
    setState(() {
      _locale = Locale(preferences.languageCode);
      _themeMode = preferences.themeMode;
    });
  }

  void _toggleTheme() {
    _preferencesRevision++;
    setState(() {
      _themeMode = _themeMode == ThemeMode.dark
          ? ThemeMode.light
          : ThemeMode.dark;
    });
    unawaited(_savePreferences());
  }

  void _setLocale(Locale locale) {
    if (locale == _locale ||
        !const ['fa', 'en'].contains(locale.languageCode)) {
      return;
    }
    _preferencesRevision++;
    setState(() => _locale = locale);
    unawaited(_savePreferences());
  }

  Future<void> _savePreferences() {
    return _preferencesStore.save(
      AppPreferences(languageCode: _locale.languageCode, themeMode: _themeMode),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Quantara',
      debugShowCheckedModeBanner: false,
      locale: _locale,
      supportedLocales: const [Locale('fa'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: QuantaraTheme.light(),
      darkTheme: QuantaraTheme.dark(),
      themeMode: _themeMode,
      themeAnimationDuration: const Duration(milliseconds: 220),
      themeAnimationCurve: Curves.easeOutCubic,
      home: OwnerAlphaPage(
        repository: _repository,
        settingsStore: _settingsStore,
        opportunityStateStore:
            widget.opportunityStateStore ??
            const PlatformOpportunityStateStore(),
        notificationGateway:
            widget.notificationGateway ??
            const PlatformSetupNotificationGateway(),
        backgroundScanGateway:
            widget.backgroundScanGateway ??
            (widget.repository == null
                ? const WorkmanagerBackgroundScanGateway()
                : const NoopBackgroundScanGateway()),
        themeMode: _themeMode,
        locale: _locale,
        onToggleTheme: _toggleTheme,
        onLocaleChanged: _setLocale,
      ),
    );
  }
}
