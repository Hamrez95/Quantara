import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../market_analysis/data/chart_structure_analyzer.dart';
import '../../market_analysis/domain/market_chart_models.dart';
import '../application/owner_alpha_controller.dart';
import '../domain/bitunix_public_stream_models.dart';
import '../domain/owner_alpha_models.dart';
import '../domain/realtime_candidate_models.dart';
import '../domain/realtime_candle_pipeline_models.dart';
import '../domain/realtime_market_event_models.dart';
import '../domain/realtime_market_runtime_models.dart';
import 'bitunix_candle_backfill_source.dart';
import 'durable_candidate_audit_store.dart';
import 'realtime_candidate_coordinator.dart';
import 'realtime_candidate_registry.dart';
import 'realtime_contextual_market_analysis.dart';
import 'realtime_market_application.dart';
import 'trade_idea_factory.dart';

final class RealtimeMarketMonitorSnapshot {
  const RealtimeMarketMonitorSnapshot({
    required this.health,
    required this.error,
    required this.foregroundOnly,
    this.candidates = const [],
    this.candidateRevision = 0,
  });

  const RealtimeMarketMonitorSnapshot.initial()
    : health = null,
      error = null,
      foregroundOnly = true,
      candidates = const [],
      candidateRevision = 0;

  final RealtimeMarketHealthSnapshot? health;
  final String? error;
  final bool foregroundOnly;
  final List<RealtimeOpportunityCandidate> candidates;
  final int candidateRevision;

  bool get operational => health?.operational == true && error == null;

  bool get healthy => health?.discoveryHealthy == true && error == null;
}

abstract interface class RealtimeMarketRuntimeLifecycle {
  RealtimeMarketRuntimeState get state;
  RealtimeMarketHealthSnapshot get health;
  int get candidateSnapshotRevision;
  List<RealtimeOpportunityCandidate> get radarCandidates;
  Future<void> start();
  Future<void> resume();
  Future<void> pause();
  Future<void> stop();
}

final class RealtimeMarketApplicationLifecycle
    implements RealtimeMarketRuntimeLifecycle {
  const RealtimeMarketApplicationLifecycle(this.application);

  final RealtimeMarketApplication application;

  @override
  RealtimeMarketRuntimeState get state => application.state;

  @override
  RealtimeMarketHealthSnapshot get health => application.health;

  @override
  int get candidateSnapshotRevision => application.candidateSnapshotRevision;

  @override
  List<RealtimeOpportunityCandidate> get radarCandidates =>
      application.radarCandidates;

  @override
  Future<void> start() => application.start();

  @override
  Future<void> resume() => application.resume();

  @override
  Future<void> pause() => application.pause();

  @override
  Future<void> stop() => application.stop();
}

final class RealtimeMarketHost
    extends ValueNotifier<RealtimeMarketMonitorSnapshot>
    with WidgetsBindingObserver {
  RealtimeMarketHost({
    required this.runtime,
    this.onLanguageChanged,
    this.onDispose,
    this.pollInterval = const Duration(seconds: 1),
    this.backgroundPauseGrace = const Duration(seconds: 3),
    this.degradedRetryInterval = const Duration(minutes: 5),
  }) : super(const RealtimeMarketMonitorSnapshot.initial()) {
    if (pollInterval < const Duration(milliseconds: 250)) {
      throw ArgumentError.value(pollInterval, 'pollInterval');
    }
    if (backgroundPauseGrace < Duration.zero ||
        backgroundPauseGrace > const Duration(seconds: 30)) {
      throw ArgumentError.value(backgroundPauseGrace, 'backgroundPauseGrace');
    }
    if (degradedRetryInterval <= Duration.zero ||
        degradedRetryInterval > const Duration(hours: 1)) {
      throw ArgumentError.value(degradedRetryInterval, 'degradedRetryInterval');
    }
  }

  final RealtimeMarketRuntimeLifecycle runtime;
  final ValueChanged<String>? onLanguageChanged;
  final VoidCallback? onDispose;
  final Duration pollInterval;
  final Duration backgroundPauseGrace;
  final Duration degradedRetryInterval;
  Timer? _timer;
  Timer? _backgroundPauseTimer;
  Future<void> _operationTail = Future.value();
  DateTime? _degradedSinceUtc;
  bool _degradedRecoveryScheduled = false;
  bool _initialized = false;
  bool _disposed = false;
  var _candidateRevision = -1;
  List<RealtimeOpportunityCandidate> _candidates = const [];

  Future<void> initialize() => _serialize(() async {
    if (_disposed || _initialized) return;
    _initialized = true;
    WidgetsBinding.instance.addObserver(this);
    try {
      await runtime.start();
      _publish();
      _timer = Timer.periodic(pollInterval, (_) => _publish());
    } on Object catch (error) {
      _publish(error: error.toString());
    }
  });

  void setLanguage(String languageCode) {
    if (languageCode != 'fa' && languageCode != 'en') return;
    onLanguageChanged?.call(languageCode);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _backgroundPauseTimer?.cancel();
        _backgroundPauseTimer = null;
        unawaited(_serialize(_resume));
        return;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        return;
      case AppLifecycleState.paused:
        _scheduleBackgroundPause();
        return;
      case AppLifecycleState.detached:
        _backgroundPauseTimer?.cancel();
        _backgroundPauseTimer = null;
        unawaited(_serialize(_pause));
        return;
    }
  }

  void _scheduleBackgroundPause() {
    if (_disposed || !_initialized) return;
    _backgroundPauseTimer?.cancel();
    _backgroundPauseTimer = Timer(backgroundPauseGrace, () {
      _backgroundPauseTimer = null;
      unawaited(_serialize(_pause));
    });
  }

  Future<void> _resume() async {
    if (_disposed || !_initialized) return;
    try {
      if (runtime.state == RealtimeMarketRuntimeState.paused) {
        await runtime.resume();
      } else if (runtime.state == RealtimeMarketRuntimeState.idle) {
        await runtime.start();
      }
      _publish();
    } on Object catch (error) {
      _publish(error: error.toString());
    }
  }

  Future<void> _pause() async {
    if (_disposed || !_initialized) return;
    final state = runtime.state;
    if (state == RealtimeMarketRuntimeState.paused ||
        state == RealtimeMarketRuntimeState.idle ||
        state == RealtimeMarketRuntimeState.stopped) {
      return;
    }
    try {
      await runtime.pause();
      _degradedSinceUtc = null;
      _publish();
    } on Object catch (error) {
      _publish(error: error.toString());
    }
  }

  void _publish({String? error}) {
    if (_disposed) return;
    RealtimeMarketHealthSnapshot? health;
    try {
      health = runtime.health;
    } on Object {
      health = null;
    }
    try {
      final revision = runtime.candidateSnapshotRevision;
      if (revision != _candidateRevision) {
        _candidates = runtime.radarCandidates;
        _candidateRevision = revision;
      }
    } on Object {
      _candidates = const [];
      _candidateRevision = -1;
    }
    value = RealtimeMarketMonitorSnapshot(
      health: health,
      error: error,
      foregroundOnly: true,
      candidates: _candidates,
      candidateRevision: _candidateRevision,
    );
    _maybeRecoverDegraded(health, error: error);
  }

  void _maybeRecoverDegraded(
    RealtimeMarketHealthSnapshot? health, {
    required String? error,
  }) {
    if (_disposed ||
        error != null ||
        health?.degraded != true ||
        runtime.state != RealtimeMarketRuntimeState.live) {
      _degradedSinceUtc = null;
      return;
    }
    final now = DateTime.now().toUtc();
    final degradedSince = _degradedSinceUtc;
    if (degradedSince == null) {
      _degradedSinceUtc = now;
      return;
    }
    if (_degradedRecoveryScheduled ||
        now.difference(degradedSince) < degradedRetryInterval) {
      return;
    }

    _degradedRecoveryScheduled = true;
    _degradedSinceUtc = now;
    unawaited(
      _serialize(() async {
        try {
          if (!_disposed &&
              runtime.state == RealtimeMarketRuntimeState.live &&
              runtime.health.degraded) {
            await runtime.pause();
            await runtime.resume();
          }
          _publish();
        } on Object catch (recoveryError) {
          _publish(error: recoveryError.toString());
        } finally {
          _degradedRecoveryScheduled = false;
        }
      }),
    );
  }

  Future<void> _serialize(Future<void> Function() operation) {
    final result = _operationTail.then((_) => operation());
    _operationTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _backgroundPauseTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(runtime.stop().catchError((Object _) {}));
    onDispose?.call();
    super.dispose();
  }
}

abstract final class RealtimeSettingsUniverse {
  static const intervals = [
    BitunixKlineInterval.fiveMinutes,
    BitunixKlineInterval.fifteenMinutes,
    BitunixKlineInterval.thirtyMinutes,
    BitunixKlineInterval.oneHour,
    BitunixKlineInterval.fourHours,
  ];

  static RealtimeMarketUniverse build(OwnerAlphaSettings settings) {
    final symbols = settings.symbols
        .map((value) => value.trim().toUpperCase())
        .where((value) => RegExp(r'^[A-Z0-9]{5,24}$').hasMatch(value))
        .toSet()
        .take(12)
        .toList(growable: false);
    if (symbols.isEmpty) {
      throw StateError('Realtime settings contain no valid symbols.');
    }
    return RealtimeMarketUniverse([
      for (final symbol in symbols)
        for (final interval in intervals)
          RealtimeCandleStreamKey(symbol: symbol, interval: interval),
    ], maximumStreams: 48);
  }
}

final class SharedPreferencesCandidateAuditKeyValueStore
    implements CandidateAuditKeyValueStore {
  const SharedPreferencesCandidateAuditKeyValueStore();

  @override
  Future<String?> read(String key) => SharedPreferencesAsync().getString(key);

  @override
  Future<void> write(String key, String value) =>
      SharedPreferencesAsync().setString(key, value);
}

final class RealtimeIdeaCatalog {
  final Map<String, TradeIdea> _bySetup = {};
  final Map<String, String> _setupByStream = {};

  void remember(TradeIdea idea) {
    if (!idea.isActionable) return;
    _bySetup[idea.setupId] = idea;
    _setupByStream['${idea.symbol}|${idea.timeframe}'] = idea.setupId;
    while (_bySetup.length > 2000) {
      final oldest = _bySetup.keys.first;
      _bySetup.remove(oldest);
      _setupByStream.removeWhere((_, setupId) => setupId == oldest);
    }
  }

  TradeIdea? ideaFor(String setupId) => _bySetup[setupId];

  TradeIdea? currentFor(RealtimeCandleStreamKey key) {
    final setupId = _setupByStream[key.id];
    return setupId == null ? null : _bySetup[setupId];
  }
}

final class ProductionRealtimeContextualAnalyzer
    implements RealtimeContextualMarketAnalyzer {
  ProductionRealtimeContextualAnalyzer({
    required this.settings,
    required this.catalog,
    String languageCode = 'fa',
  }) : _languageCode = _normalizeLanguage(languageCode);

  final OwnerAlphaSettings settings;
  final RealtimeIdeaCatalog catalog;
  String _languageCode;

  static String _normalizeLanguage(String languageCode) =>
      languageCode == 'en' ? 'en' : 'fa';

  void setLanguage(String languageCode) {
    if (languageCode == 'fa' || languageCode == 'en') {
      _languageCode = languageCode;
    }
  }

  @override
  Future<RealtimeCandidateAnalysisBatch> analyze(
    RealtimeCandleAnalysisContext context,
  ) async {
    if (context.closedCandles.length < 30) {
      return RealtimeCandidateAnalysisBatch();
    }
    final structure = ChartStructureAnalyzer.analyze(context.closedCandles);
    final latestClosed = context.closedCandles.last;
    final analysis = TimeframeChartAnalysis(
      symbol: context.key.symbol,
      timeframe: context.key.interval.timeframe,
      candles: context.closedCandles,
      zones: structure.zones,
      direction: structure.direction,
      directionStrength: structure.directionStrength,
      volatilityPercent: structure.volatilityPercent,
      summary: _languageCode == 'en'
          ? 'Closed-candle realtime structure analysis.'
          : 'تحلیل بلادرنگ بر پایه کندل‌های بسته‌شده.',
      generatedAt: context.processedAtUtc,
      fingerprint:
          '${context.key.id}|${context.closedCandles.first.openTime.microsecondsSinceEpoch}|${latestClosed.openTime.microsecondsSinceEpoch}|${latestClosed.close}',
    );
    final generated = TradeIdeaFactory.create(
      analysis: analysis,
      capital: settings.capital,
      riskPercent: settings.riskPercent,
      confluence: {analysis.timeframe: analysis.direction},
      languageCode: _languageCode,
      strategy: settings.strategy,
      cadence: settings.cadence,
    );
    TradeIdea? tracked;
    final candidates = <RealtimeOpportunityCandidate>[];
    if (generated.isActionable) {
      catalog.remember(generated);
      tracked = generated;
      candidates.add(
        RealtimeOpportunityCandidate.fromIdea(
          generated,
          detectedAtUtc: generated.createdAt.toUtc(),
          playbookId: generated.strategyVersion,
        ),
      );
    } else {
      tracked = catalog.currentFor(context.key);
    }
    if (tracked == null) {
      return RealtimeCandidateAnalysisBatch(candidates: candidates);
    }

    final triggerPrice = context.triggersClosedCandleAnalysis
        ? latestClosed.close
        : context.workingCandle?.close ?? latestClosed.close;
    final entryLower = tracked.entryLower!;
    final entryUpper = tracked.entryUpper!;
    final triggerConfirmed =
        context.triggersClosedCandleAnalysis &&
        triggerPrice >= entryLower &&
        triggerPrice <= entryUpper;
    final structureValid = switch (tracked.direction) {
      TradeDirection.long => triggerPrice > tracked.stopLoss!,
      TradeDirection.short => triggerPrice < tracked.stopLoss!,
      TradeDirection.wait => false,
    };
    final eventId =
        '${context.key.id}|${context.disposition.name}|${context.exchangeTimestampUtc.microsecondsSinceEpoch}|${triggerPrice.toStringAsPrecision(12)}';
    final observation = RealtimeObservationEnvelope(
      eventId: eventId,
      setupId: tracked.setupId,
      symbol: tracked.symbol,
      timeframe: tracked.timeframe,
      observation: RealtimeMarketObservation(
        exchangeTimestampUtc: context.exchangeTimestampUtc,
        receivedAtUtc: context.receivedAtUtc,
        evaluatedAtUtc: context.processedAtUtc,
        lastPrice: triggerPrice,
        qualityScore: tracked.confidencePercent,
        structureValid: structureValid,
        triggerConfirmed: triggerConfirmed,
        triggerCandleClosed: context.triggersClosedCandleAnalysis,
      ),
    );
    return RealtimeCandidateAnalysisBatch(
      candidates: candidates,
      observations: [observation],
    );
  }
}

final class PlatformRealtimeAuditedCandidateProjection
    implements RealtimeAuditedCandidateProjection {
  PlatformRealtimeAuditedCandidateProjection({
    required this.stateStore,
    required this.catalog,
    required this.sizingCapital,
  });

  final OpportunityStateStore stateStore;
  final RealtimeIdeaCatalog catalog;
  final double sizingCapital;
  Future<void> _tail = Future.value();

  @override
  Future<void> restore() async {
    await stateStore.load();
  }

  @override
  Future<void> apply({
    required CandidateRegistryAuditEvent auditEvent,
    required RealtimeOpportunityCandidate? candidate,
    required CandidateCoordinationOutcome outcome,
    required CandidateAuditPersistenceDecision persistenceDecision,
  }) {
    final operation = _tail.then((_) => _applyInternal(candidate, outcome));
    _tail = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }

  Future<void> _applyInternal(
    RealtimeOpportunityCandidate? candidate,
    CandidateCoordinationOutcome outcome,
  ) async {
    if (candidate == null ||
        outcome != CandidateCoordinationOutcome.committed) {
      return;
    }
    final state = await stateStore.load();
    final journal = state.journal.toList(growable: true);
    var index = journal.indexWhere(
      (entry) => entry.setupId == candidate.setupId,
    );
    if (index < 0) {
      final idea = catalog.ideaFor(candidate.setupId);
      if (idea == null) return;
      journal.insert(
        0,
        SignalJournalEntry.fromIdea(idea, sizingCapital: sizingCapital),
      );
      if (journal.length > 100) journal.removeLast();
      index = 0;
    }
    final current = journal[index];
    final updated = switch (candidate.stage) {
      OpportunityStage.triggered => current.copyWith(
        outcome: SignalOutcome.active,
        activatedAt: candidate.triggeredAtUtc ?? candidate.lastUpdatedAtUtc,
      ),
      OpportunityStage.missed ||
      OpportunityStage.expired ||
      OpportunityStage.invalidated => current.copyWith(
        outcome: SignalOutcome.expiredUntriggered,
        resolvedAt: candidate.resolvedAtUtc ?? candidate.lastUpdatedAtUtc,
        closed: true,
      ),
      _ => current,
    };
    if (identical(updated, current)) return;
    journal[index] = updated;
    await stateStore.save(state.copyWith(journal: journal));
  }
}

abstract final class PlatformRealtimeMarketHostFactory {
  static Future<RealtimeMarketHost> create({
    required OwnerAlphaSettingsStore settingsStore,
    required OpportunityStateStore opportunityStateStore,
    String languageCode = 'fa',
  }) async {
    final settings =
        await settingsStore.load() ??
        const OwnerAlphaSettings(
          symbols: OwnerAlphaController.defaultSymbols,
          capital: 10000,
          riskPercent: 0.5,
        );
    final client = http.Client();
    final catalog = RealtimeIdeaCatalog();
    final analyzer = ProductionRealtimeContextualAnalyzer(
      settings: settings,
      catalog: catalog,
      languageCode: languageCode,
    );
    final analysisGateway = SnapshottingRealtimeMarketAnalysisGateway(
      analyzer: analyzer,
      maximumStreams: 48,
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
      sizingCapital: settings.capital,
    );
    final application = RealtimeMarketApplication(
      universe: RealtimeSettingsUniverse.build(settings),
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
