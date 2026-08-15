import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;

import '../core/settings/app_preferences.dart';
import '../core/theme/quantara_theme.dart';
import '../features/auto_trade/data/local_live_preferences_store.dart';
import '../features/owner_alpha/application/owner_alpha_controller.dart';
import '../features/owner_alpha/data/background_opportunity_scanner.dart';
import '../features/owner_alpha/data/bitunix_owner_alpha_repository.dart';
import '../features/owner_alpha/data/local_live_realtime_universe.dart';
import '../features/owner_alpha/data/platform_owner_alpha_settings_store.dart';
import '../features/owner_alpha/data/platform_opportunity_services.dart';
import '../features/owner_alpha/data/realtime_production_runtime.dart';
import '../features/owner_alpha/domain/owner_alpha_models.dart';
import '../features/owner_alpha/domain/realtime_market_runtime_models.dart';
import '../features/owner_alpha/presentation/owner_alpha_page.dart';
import '../features/portfolio_risk/presentation/portfolio_risk_panel.dart';

class QuantaraApp extends StatefulWidget {
  const QuantaraApp({
    super.key,
    this.repository,
    this.settingsStore,
    this.preferencesStore,
    this.opportunityStateStore,
    this.notificationGateway,
    this.backgroundScanGateway,
    this.realtimeMarketHost,
    this.initialThemeMode = ThemeMode.dark,
    this.initialLocale = const Locale('fa'),
  });

  final OwnerAlphaRepository? repository;
  final OwnerAlphaSettingsStore? settingsStore;
  final AppPreferencesStore? preferencesStore;
  final OpportunityStateStore? opportunityStateStore;
  final SetupNotificationGateway? notificationGateway;
  final BackgroundScanGateway? backgroundScanGateway;
  final RealtimeMarketHost? realtimeMarketHost;
  final ThemeMode initialThemeMode;
  final Locale initialLocale;

  @override
  State<QuantaraApp> createState() => _QuantaraAppState();
}

class _QuantaraAppState extends State<QuantaraApp> {
  late ThemeMode _themeMode = widget.initialThemeMode;
  late Locale _locale = widget.initialLocale;
  http.Client? _ownedClient;
  RealtimeMarketHost? _realtimeMarketHost;
  StreamSubscription<LocalLivePreferences>? _localLivePreferencesSubscription;
  Future<void> _realtimeTransitionTail = Future<void>.value();
  String? _realtimeUniverseFingerprint;
  int _preferencesRevision = 0;
  late final OwnerAlphaRepository _repository;
  late final OwnerAlphaSettingsStore _settingsStore =
      widget.settingsStore ?? const PlatformOwnerAlphaSettingsStore();
  late final AppPreferencesStore _preferencesStore =
      widget.preferencesStore ?? const PlatformAppPreferencesStore();
  late final OpportunityStateStore _opportunityStateStore =
      widget.opportunityStateStore ?? const PlatformOpportunityStateStore();
  late final LocalLivePreferencesStore _localLivePreferencesStore =
      const SharedPreferencesLocalLivePreferencesStore();

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
    final injectedHost = widget.realtimeMarketHost;
    if (injectedHost != null) {
      _realtimeMarketHost = injectedHost;
      unawaited(injectedHost.initialize());
    } else if (widget.repository == null) {
      _localLivePreferencesSubscription =
          SharedPreferencesLocalLivePreferencesStore.changes.listen(
            (preferences) => _scheduleRealtimeReplacement(preferences),
          );
      _scheduleRealtimeReplacement();
    }
  }

  @override
  void dispose() {
    unawaited(_localLivePreferencesSubscription?.cancel());
    _realtimeMarketHost?.dispose();
    _ownedClient?.close();
    super.dispose();
  }

  void _scheduleRealtimeReplacement([LocalLivePreferences? preferences]) {
    final next = _realtimeTransitionTail.then(
      (_) => _replaceRealtimeHost(preferences),
    );
    _realtimeTransitionTail = next.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
  }

  Future<void> _replaceRealtimeHost(
    LocalLivePreferences? preferenceRevision,
  ) async {
    if (!mounted ||
        widget.repository != null ||
        widget.realtimeMarketHost != null) {
      return;
    }
    final ownerSettings =
        await _settingsStore.load() ??
        const OwnerAlphaSettings(
          symbols: OwnerAlphaController.defaultSymbols,
          capital: 10000,
          riskPercent: 0.5,
        );
    final localPreferences =
        preferenceRevision ??
        await _localLivePreferencesStore.load(
          availableSymbols: ownerSettings.symbols,
        );
    final fingerprint = LocalLiveRealtimeUniverse.fingerprint(localPreferences);
    if (_realtimeMarketHost != null &&
        fingerprint == _realtimeUniverseFingerprint) {
      return;
    }

    final replacement = await PlatformLocalLiveRealtimeMarketHostFactory.create(
      ownerSettings: ownerSettings,
      localLivePreferences: localPreferences,
      opportunityStateStore: _opportunityStateStore,
      languageCode: _locale.languageCode,
    );
    if (!mounted) {
      replacement.dispose();
      return;
    }

    final previous = _realtimeMarketHost;
    if (previous != null) {
      try {
        final state = previous.runtime.state;
        if (state != RealtimeMarketRuntimeState.idle &&
            state != RealtimeMarketRuntimeState.paused &&
            state != RealtimeMarketRuntimeState.stopped) {
          await previous.runtime.pause();
        }
        await previous.runtime.stop();
      } on Object {
        replacement.dispose();
        rethrow;
      }
      previous.dispose();
    }
    if (!mounted) {
      replacement.dispose();
      return;
    }
    setState(() {
      _realtimeMarketHost = replacement;
      _realtimeUniverseFingerprint = fingerprint;
    });
    await replacement.initialize();
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
    _realtimeMarketHost?.setLanguage(locale.languageCode);
    unawaited(_savePreferences());
  }

  Future<void> _savePreferences() {
    return _preferencesStore.save(
      AppPreferences(languageCode: _locale.languageCode, themeMode: _themeMode),
    );
  }

  Future<void> _showPortfolioRisk(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.94,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
          child: const PortfolioRiskPanel(),
        ),
      ),
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
      home: Builder(
        builder: (homeContext) => OwnerAlphaPage(
          repository: _repository,
          settingsStore: _settingsStore,
          opportunityStateStore: _opportunityStateStore,
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
          onOpenPortfolioRisk: () => _showPortfolioRisk(homeContext),
          realtimeMonitor: _realtimeMarketHost,
        ),
      ),
    );
  }
}
