import 'dart:async';

import 'package:quantara_app/features/cockpit/data/mock_cockpit_repository.dart';
import 'package:quantara_app/core/settings/app_preferences.dart';
import 'package:quantara_app/features/cockpit/domain/cockpit_models.dart';
import 'package:quantara_app/features/market_analysis/data/demo_market_chart_factory.dart';
import 'package:quantara_app/features/market_analysis/domain/market_chart_models.dart';
import 'package:quantara_app/features/owner_alpha/data/trade_idea_factory.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';

final class FakeOwnerAlphaRepository implements OwnerAlphaRepository {
  const FakeOwnerAlphaRepository();

  @override
  Future<OwnerAlphaSnapshot> scan({
    required List<String> symbols,
    required String selectedSymbol,
    required String selectedTimeframe,
    required double capital,
    required double riskPercent,
    required String languageCode,
  }) async {
    final generatedAt = DateTime.now().toUtc();
    final analyses = <String, TimeframeChartAnalysis>{};
    for (final timeframe in const ['15m', '1h', '4h', '1D']) {
      analyses[timeframe] = DemoMarketChartFactory.create(
        quote: _legacyQuote(selectedSymbol),
        timeframe: timeframe,
      );
    }
    final directions = <String, ChartDirection>{
      for (final entry in analyses.entries) entry.key: entry.value.direction,
    };
    final radar = <SymbolRadarResult>[];
    for (final symbol in symbols) {
      final legacy = _legacyQuote(symbol);
      final analysis = DemoMarketChartFactory.create(
        quote: legacy,
        timeframe: '1h',
      );
      final symbolAnalyses = <String, TimeframeChartAnalysis>{
        for (final timeframe in const ['15m', '1h', '4h'])
          timeframe: DemoMarketChartFactory.create(
            quote: legacy,
            timeframe: timeframe,
          ),
      };
      final symbolDirections = <String, ChartDirection>{
        for (final entry in symbolAnalyses.entries)
          entry.key: entry.value.direction,
      };
      radar.add(
        SymbolRadarResult(
          quote: AlphaMarketQuote(
            symbol: symbol,
            displayName: legacy.displayName,
            lastPrice: legacy.price,
            changePercent: legacy.changePercent,
            high24h: legacy.price * 1.02,
            low24h: legacy.price * 0.98,
            observedAt: generatedAt,
          ),
          analysis: analysis,
          idea: TradeIdeaFactory.create(
            analysis: analysis,
            capital: capital,
            riskPercent: riskPercent,
            languageCode: languageCode,
            confluence: symbolDirections,
          ),
          analysesByTimeframe: symbolAnalyses,
          ideasByTimeframe: {
            for (final entry in symbolAnalyses.entries)
              entry.key: TradeIdeaFactory.create(
                analysis: entry.value,
                capital: capital,
                riskPercent: riskPercent,
                languageCode: languageCode,
                confluence: symbolDirections,
              ),
          },
        ),
      );
    }
    final selected = analyses[selectedTimeframe]!;
    return OwnerAlphaSnapshot(
      radar: radar,
      selectedSymbol: selectedSymbol,
      selectedTimeframe: selectedTimeframe,
      selectedAnalysis: selected,
      selectedIdea: TradeIdeaFactory.create(
        analysis: selected,
        capital: capital,
        riskPercent: riskPercent,
        confluence: directions,
        languageCode: languageCode,
      ),
      timeframeDirections: directions,
      generatedAt: generatedAt,
    );
  }

  static MarketQuote _legacyQuote(String symbol) {
    MarketQuote? existing;
    for (final quote in MockCockpitRepository.demoSnapshot.watchlist) {
      if (quote.symbol == symbol) {
        existing = quote;
        break;
      }
    }
    if (existing != null) {
      return existing;
    }
    final base = MockCockpitRepository.demoSnapshot.watchlist.first;
    return MarketQuote(
      symbol: symbol,
      displayName: symbol.replaceAll('USDT', ''),
      price: base.price,
      changePercent: base.changePercent,
      spreadBps: base.spreadBps,
      freshness: base.freshness,
      sparkline: base.sparkline,
    );
  }
}

final class MemoryOwnerAlphaSettingsStore implements OwnerAlphaSettingsStore {
  OwnerAlphaSettings? value;

  @override
  Future<OwnerAlphaSettings?> load() async => value;

  @override
  Future<void> save(OwnerAlphaSettings settings) async {
    value = settings;
  }
}

final class MemoryAppPreferencesStore implements AppPreferencesStore {
  MemoryAppPreferencesStore([this.value]);

  AppPreferences? value;

  @override
  Future<AppPreferences?> load() async => value;

  @override
  Future<void> save(AppPreferences preferences) async {
    value = preferences;
  }
}

final class MemoryOpportunityStateStore implements OpportunityStateStore {
  OpportunityState value = const OpportunityState();

  @override
  Future<OpportunityState> load() async => value;

  @override
  Future<void> save(OpportunityState state) async {
    value = state;
  }
}

final class RecordingSetupNotificationGateway
    implements SetupNotificationGateway {
  RecordingSetupNotificationGateway({this.launchSetupId});

  bool permissionGranted = true;
  final shown = <String>[];
  String? launchSetupId;
  final StreamController<String> _opened = StreamController.broadcast();

  @override
  Stream<String> get openedSetupIds => _opened.stream;

  @override
  Future<String?> initialSetupId() async {
    final value = launchSetupId;
    launchSetupId = null;
    return value;
  }

  void open(String setupId) => _opened.add(setupId);

  Future<void> dispose() => _opened.close();

  @override
  Future<bool> requestPermission() async => permissionGranted;

  @override
  Future<void> openBackgroundSettings() async {}

  @override
  Future<void> show(TradeIdea idea, {required String languageCode}) async {
    shown.add(idea.setupId);
  }
}
