import 'package:http/http.dart' as http;

import '../../auto_trade/data/local_live_preferences_store.dart';
import '../domain/bitunix_public_stream_models.dart';
import '../domain/owner_alpha_models.dart';
import '../domain/realtime_candle_pipeline_models.dart';
import '../domain/realtime_market_runtime_models.dart';
import 'bitunix_candle_backfill_source.dart';
import 'durable_candidate_audit_store.dart';
import 'realtime_candidate_coordinator.dart';
import 'realtime_candidate_registry.dart';
import 'realtime_contextual_market_analysis.dart';
import 'realtime_market_application.dart';
import 'realtime_production_runtime.dart';

/// The public realtime universe used while guarded Local Live is configured.
///
/// Symbols and timeframes come from the same persisted Local Live preferences
/// that are later used to build [LocalLiveTradeConfiguration]. This prevents
/// the execution allow-list and the public monitoring universe from drifting.
abstract final class LocalLiveRealtimeUniverse {
  static const _intervalByTimeframe = <String, BitunixKlineInterval>{
    '5m': BitunixKlineInterval.fiveMinutes,
    '15m': BitunixKlineInterval.fifteenMinutes,
    '1h': BitunixKlineInterval.oneHour,
    '4h': BitunixKlineInterval.fourHours,
  };

  static RealtimeMarketUniverse build(LocalLivePreferences preferences) {
    final symbols =
        preferences.symbols
            .map((value) => value.trim().toUpperCase())
            .where((value) => RegExp(r'^[A-Z0-9]{5,24}$').hasMatch(value))
            .toSet()
            .take(LocalLivePreferences.maximumSymbolCount)
            .toList(growable: false)
          ..sort();
    final timeframes =
        preferences.timeframes
            .where(_intervalByTimeframe.containsKey)
            .toSet()
            .toList(growable: false)
          ..sort();
    if (symbols.isEmpty) {
      throw StateError('Local Live realtime universe has no valid symbols.');
    }
    if (timeframes.isEmpty) {
      throw StateError('Local Live realtime universe has no valid timeframes.');
    }
    return RealtimeMarketUniverse(
      [
        for (final symbol in symbols)
          for (final timeframe in timeframes)
            RealtimeCandleStreamKey(
              symbol: symbol,
              interval: _intervalByTimeframe[timeframe]!,
            ),
      ],
      maximumStreams:
          LocalLivePreferences.maximumSymbolCount * _intervalByTimeframe.length,
    );
  }

  static String fingerprint(LocalLivePreferences preferences) {
    final symbols =
        preferences.symbols
            .map((value) => value.trim().toUpperCase())
            .toSet()
            .toList(growable: false)
          ..sort();
    final timeframes = preferences.timeframes.toList(growable: false)..sort();
    return '${symbols.join(',')}|${timeframes.join(',')}';
  }
}

/// Builds the production realtime host from one immutable Local Live universe
/// revision. Reconfiguration is intentionally owned by the application shell:
/// the old host is stopped before a host for the next revision is initialized.
abstract final class PlatformLocalLiveRealtimeMarketHostFactory {
  static Future<RealtimeMarketHost> create({
    required OwnerAlphaSettings ownerSettings,
    required LocalLivePreferences localLivePreferences,
    required OpportunityStateStore opportunityStateStore,
    String languageCode = 'fa',
  }) async {
    final universe = LocalLiveRealtimeUniverse.build(localLivePreferences);
    final client = http.Client();
    final catalog = RealtimeIdeaCatalog();
    final analyzer = ProductionRealtimeContextualAnalyzer(
      settings: ownerSettings,
      catalog: catalog,
      languageCode: languageCode,
    );
    final analysisGateway = SnapshottingRealtimeMarketAnalysisGateway(
      analyzer: analyzer,
      maximumStreams: universe.maximumStreams,
      maximumClosedCandlesPerStream: 500,
    );
    final auditStore = DurableCandidateAuditStore(
      keyValueStore: const SharedPreferencesCandidateAuditKeyValueStore(),
    );
    final coordinator = RealtimeCandidateCoordinator(
      registry: RealtimeCandidateRegistry(
        maximumCandidates: 2000,
        recentEventCapacity: 4096,
      ),
      auditStore: auditStore,
    );
    final projection = PlatformRealtimeAuditedCandidateProjection(
      stateStore: opportunityStateStore,
      catalog: catalog,
      sizingCapital: ownerSettings.capital,
    );
    final application = RealtimeMarketApplication(
      universe: universe,
      backfillSource: BitunixCandleBackfillSource(
        client: client,
        maximumMalformedRecentRows: 8,
      ),
      fleetFactory: const BitunixRealtimePublicStreamFleetFactory(),
      analysisGateway: analysisGateway,
      candidateCoordinator: coordinator,
      projection: projection,
      closedCandleLimit: 64,
      bootstrapSpacing: const Duration(milliseconds: 120),
      maximumPendingEventsPerStream: 64,
      maximumLatencySamples: 512,
    );
    return RealtimeMarketHost(
      runtime: RealtimeMarketApplicationLifecycle(application),
      onLanguageChanged: analyzer.setLanguage,
      onDispose: client.close,
    );
  }
}
