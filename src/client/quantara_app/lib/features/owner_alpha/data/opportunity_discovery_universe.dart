import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../auto_trade/data/local_live_preferences_store.dart';
import '../../market_analysis/data/chart_structure_analyzer.dart';
import '../../market_analysis/domain/market_chart_models.dart';
import '../domain/bitunix_public_stream_models.dart';
import '../domain/owner_alpha_models.dart';
import '../domain/realtime_candidate_models.dart';
import '../domain/realtime_candle_pipeline_models.dart';
import '../domain/realtime_market_event_models.dart';
import '../domain/realtime_market_runtime_models.dart';
import '../domain/regime_playbook_models.dart';
import 'bitunix_candle_backfill_source.dart';
import 'durable_candidate_audit_store.dart';
import 'realtime_candidate_coordinator.dart';
import 'realtime_candidate_registry.dart';
import 'realtime_contextual_market_analysis.dart';
import 'realtime_market_application.dart';
import 'realtime_production_runtime.dart';
import 'regime_playbook_portfolio_engine.dart';

enum OpportunityUniverseRejectionReason {
  nonUsdtQuote,
  marketClosed,
  apiUnsupported,
  missingTicker,
  invalidTicker,
  insufficientLiquidity,
  spreadUnavailable,
  spreadTooWide,
}

@immutable
final class OpportunityUniverseSnapshot {
  OpportunityUniverseSnapshot({
    required Iterable<String> symbols,
    required Map<OpportunityUniverseRejectionReason, int> rejections,
    required this.generatedAtUtc,
  }) : symbols = List.unmodifiable(symbols),
       rejections = Map.unmodifiable(rejections) {
    if (!generatedAtUtc.isUtc) {
      throw ArgumentError.value(generatedAtUtc, 'generatedAtUtc');
    }
    if (this.symbols.isEmpty) {
      throw ArgumentError(
        'At least one eligible discovery symbol is required.',
      );
    }
  }

  final List<String> symbols;
  final Map<OpportunityUniverseRejectionReason, int> rejections;
  final DateTime generatedAtUtc;

  int get rejectedTotal =>
      rejections.values.fold(0, (sum, value) => sum + value);

  String get fingerprint => symbols.join(',');
}

final class OpportunityUniversePolicy {
  const OpportunityUniversePolicy({
    this.targetSymbolCount = 100,
    this.probePoolSize = 140,
    this.minimumQuoteVolume = 10000,
    this.maximumSpreadBps = 35,
  });

  final int targetSymbolCount;
  final int probePoolSize;
  final double minimumQuoteVolume;
  final double maximumSpreadBps;

  void validate() {
    if (targetSymbolCount < 100 || targetSymbolCount > 200) {
      throw ArgumentError.value(targetSymbolCount, 'targetSymbolCount');
    }
    if (probePoolSize < targetSymbolCount || probePoolSize > 250) {
      throw ArgumentError.value(probePoolSize, 'probePoolSize');
    }
    if (!minimumQuoteVolume.isFinite || minimumQuoteVolume < 0) {
      throw ArgumentError.value(minimumQuoteVolume, 'minimumQuoteVolume');
    }
    if (!maximumSpreadBps.isFinite ||
        maximumSpreadBps <= 0 ||
        maximumSpreadBps > 500) {
      throw ArgumentError.value(maximumSpreadBps, 'maximumSpreadBps');
    }
  }
}

abstract interface class OpportunityDiscoveryUniverseSource {
  Future<OpportunityUniverseSnapshot> load();
}

final class BitunixOpportunityDiscoveryUniverseSource
    implements OpportunityDiscoveryUniverseSource {
  BitunixOpportunityDiscoveryUniverseSource({
    required this._client,
    this.policy = const OpportunityUniversePolicy(),
    this.timeout = const Duration(seconds: 10),
    this.depthBatchSize = 5,
    this.depthBatchSpacing = const Duration(milliseconds: 550),
    DateTime Function()? now,
    Future<void> Function(Duration)? delay,
  }) : _now = now ?? DateTime.now,
       _delay = delay ?? Future<void>.delayed {
    policy.validate();
    if (timeout <= Duration.zero || timeout > const Duration(seconds: 30)) {
      throw ArgumentError.value(timeout, 'timeout');
    }
    if (depthBatchSize < 1 || depthBatchSize > 5) {
      throw ArgumentError.value(depthBatchSize, 'depthBatchSize');
    }
    if (depthBatchSpacing < const Duration(milliseconds: 500)) {
      throw ArgumentError.value(depthBatchSpacing, 'depthBatchSpacing');
    }
  }

  static const _origin = 'https://fapi.bitunix.com';
  static const _maximumResponseBytes = 2 * 1024 * 1024;

  final http.Client _client;
  final OpportunityUniversePolicy policy;
  final Duration timeout;
  final int depthBatchSize;
  final Duration depthBatchSpacing;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _delay;

  @override
  Future<OpportunityUniverseSnapshot> load() async {
    final pairRoot = await _getJson(
      Uri.parse('$_origin/api/v1/futures/market/trading_pairs'),
    );
    final tickerRoot = await _getJson(
      Uri.parse('$_origin/api/v1/futures/market/tickers'),
    );
    final pairData = pairRoot['data'];
    final tickerData = tickerRoot['data'];
    if (pairData is! List<Object?> || tickerData is! List<Object?>) {
      throw const FormatException(
        'Bitunix universe payload must contain lists.',
      );
    }

    final rejectionCounts = <OpportunityUniverseRejectionReason, int>{};
    void reject(OpportunityUniverseRejectionReason reason) {
      rejectionCounts.update(reason, (value) => value + 1, ifAbsent: () => 1);
    }

    final tickers = <String, _UniverseTicker>{};
    for (final raw in tickerData) {
      final item = _object(raw);
      final symbol = _string(item['symbol']).trim().toUpperCase();
      if (!_validSymbol(symbol)) continue;
      final last = _tryPositiveNumber(item['lastPrice'] ?? item['last']);
      final quoteVolume = _tryNonNegativeNumber(item['quoteVol']);
      if (last == null || quoteVolume == null) continue;
      tickers[symbol] = _UniverseTicker(
        symbol: symbol,
        lastPrice: last,
        quoteVolume: quoteVolume,
      );
    }

    final candidates = <_UniverseTicker>[];
    for (final raw in pairData) {
      final item = _object(raw);
      final symbol = _string(item['symbol']).trim().toUpperCase();
      if (!_validSymbol(symbol)) continue;
      final quote = _string(item['quote']).trim().toUpperCase();
      if (quote != 'USDT') {
        reject(OpportunityUniverseRejectionReason.nonUsdtQuote);
        continue;
      }
      if (_string(item['symbolStatus']).trim().toUpperCase() != 'OPEN') {
        reject(OpportunityUniverseRejectionReason.marketClosed);
        continue;
      }
      if (item['isApiSupported'] != true) {
        reject(OpportunityUniverseRejectionReason.apiUnsupported);
        continue;
      }
      final ticker = tickers[symbol];
      if (ticker == null) {
        reject(OpportunityUniverseRejectionReason.missingTicker);
        continue;
      }
      if (!ticker.lastPrice.isFinite || ticker.lastPrice <= 0) {
        reject(OpportunityUniverseRejectionReason.invalidTicker);
        continue;
      }
      if (ticker.quoteVolume < policy.minimumQuoteVolume) {
        reject(OpportunityUniverseRejectionReason.insufficientLiquidity);
        continue;
      }
      candidates.add(ticker);
    }
    candidates.sort((left, right) {
      final volume = right.quoteVolume.compareTo(left.quoteVolume);
      return volume != 0 ? volume : left.symbol.compareTo(right.symbol);
    });

    final pool = candidates.take(policy.probePoolSize).toList(growable: false);
    final eligible = <String>[];
    for (
      var offset = 0;
      offset < pool.length && eligible.length < policy.targetSymbolCount;
      offset += depthBatchSize
    ) {
      final proposedEnd = offset + depthBatchSize;
      final end = proposedEnd < pool.length ? proposedEnd : pool.length;
      final batch = pool.sublist(offset, end);
      final spreads = await Future.wait(
        batch.map((ticker) => _tryLoadSpreadBps(ticker.symbol)),
      );
      for (
        var index = 0;
        index < batch.length && eligible.length < policy.targetSymbolCount;
        index++
      ) {
        final spread = spreads[index];
        if (spread == null) {
          reject(OpportunityUniverseRejectionReason.spreadUnavailable);
          continue;
        }
        if (spread > policy.maximumSpreadBps) {
          reject(OpportunityUniverseRejectionReason.spreadTooWide);
          continue;
        }
        eligible.add(batch[index].symbol);
      }
      if (end < pool.length && eligible.length < policy.targetSymbolCount) {
        await _delay(depthBatchSpacing);
      }
    }

    if (eligible.length < policy.targetSymbolCount) {
      throw StateError(
        'Only ${eligible.length}/${policy.targetSymbolCount} Bitunix Futures symbols passed discovery eligibility.',
      );
    }
    return OpportunityUniverseSnapshot(
      symbols: eligible,
      rejections: rejectionCounts,
      generatedAtUtc: _now().toUtc(),
    );
  }

  Future<double?> _tryLoadSpreadBps(String symbol) async {
    try {
      final root = await _getJson(
        Uri.parse(
          '$_origin/api/v1/futures/market/depth',
        ).replace(queryParameters: {'symbol': symbol, 'limit': '1'}),
      );
      final data = _object(root['data']);
      final bids = data['bids'];
      final asks = data['asks'];
      if (bids is! List<Object?> ||
          asks is! List<Object?> ||
          bids.isEmpty ||
          asks.isEmpty) {
        return null;
      }
      final bestBid = _depthPrice(bids.first);
      final bestAsk = _depthPrice(asks.first);
      if (bestBid == null || bestAsk == null || bestAsk < bestBid) return null;
      final mid = (bestBid + bestAsk) / 2;
      if (!mid.isFinite || mid <= 0) return null;
      return (bestAsk - bestBid) / mid * 10000;
    } on Object {
      return null;
    }
  }

  Future<Map<String, Object?>> _getJson(Uri uri) async {
    if (uri.scheme != 'https' || uri.host != 'fapi.bitunix.com') {
      throw StateError('Untrusted Bitunix discovery endpoint.');
    }
    final response = await _client
        .get(uri, headers: const {'Accept': 'application/json'})
        .timeout(timeout);
    if (response.statusCode != 200) {
      throw StateError(
        'Bitunix discovery returned HTTP ${response.statusCode}.',
      );
    }
    if (response.bodyBytes.length > _maximumResponseBytes) {
      throw const FormatException('Bitunix discovery response is too large.');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final root = _object(decoded);
    if (_integer(root['code']) != 0) {
      throw StateError('Bitunix discovery rejected the request.');
    }
    return root;
  }

  static double? _depthPrice(Object? value) {
    if (value is List<Object?> && value.isNotEmpty) {
      return _tryPositiveNumber(value.first);
    }
    if (value is Map<Object?, Object?>) {
      return _tryPositiveNumber(value['price']);
    }
    return null;
  }

  static bool _validSymbol(String value) =>
      RegExp(r'^[A-Z0-9]{5,24}$').hasMatch(value);

  static Map<String, Object?> _object(Object? value) {
    if (value is! Map<Object?, Object?>) {
      throw const FormatException('Expected a JSON object.');
    }
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  static String _string(Object? value) => value is String ? value : '';

  static int _integer(Object? value) {
    if (value is int) return value;
    if (value is num && value.isFinite && value == value.roundToDouble()) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? -1;
  }

  static double? _tryPositiveNumber(Object? value) {
    final number = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '');
    if (number == null || !number.isFinite || number <= 0) return null;
    return number;
  }

  static double? _tryNonNegativeNumber(Object? value) {
    final number = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '');
    if (number == null || !number.isFinite || number < 0) return null;
    return number;
  }
}

final class _UniverseTicker {
  const _UniverseTicker({
    required this.symbol,
    required this.lastPrice,
    required this.quoteVolume,
  });

  final String symbol;
  final double lastPrice;
  final double quoteVolume;
}

abstract final class OpportunityDiscoveryRealtimeUniverse {
  static const intervals = <BitunixKlineInterval>[
    BitunixKlineInterval.fiveMinutes,
    BitunixKlineInterval.fifteenMinutes,
    BitunixKlineInterval.oneHour,
    BitunixKlineInterval.fourHours,
    BitunixKlineInterval.oneDay,
  ];

  static RealtimeMarketUniverse build(OpportunityUniverseSnapshot snapshot) {
    return RealtimeMarketUniverse([
      for (final symbol in snapshot.symbols)
        for (final interval in intervals)
          RealtimeCandleStreamKey(symbol: symbol, interval: interval),
    ], maximumStreams: 1000);
  }
}

@immutable
final class OpportunityDiscoveryCoverageSnapshot {
  const OpportunityDiscoveryCoverageSnapshot({
    this.eligibleSymbols = 0,
    this.configuredStreams = 0,
    this.symbolsScanned = 0,
    this.streamsAnalyzed = 0,
    this.forming = 0,
    this.armed = 0,
    this.triggered = 0,
    this.missed = 0,
    this.expired = 0,
    this.invalidated = 0,
    this.rejected = 0,
    this.universeRejections = const {},
    this.updatedAtUtc,
  });

  final int eligibleSymbols;
  final int configuredStreams;
  final int symbolsScanned;
  final int streamsAnalyzed;
  final int forming;
  final int armed;
  final int triggered;
  final int missed;
  final int expired;
  final int invalidated;
  final int rejected;
  final Map<OpportunityUniverseRejectionReason, int> universeRejections;
  final DateTime? updatedAtUtc;
}

final class OpportunityDiscoveryCoverageTracker
    extends ValueNotifier<OpportunityDiscoveryCoverageSnapshot> {
  OpportunityDiscoveryCoverageTracker(OpportunityUniverseSnapshot universe)
    : _universe = universe,
      super(
        OpportunityDiscoveryCoverageSnapshot(
          eligibleSymbols: universe.symbols.length,
          configuredStreams:
              universe.symbols.length *
              OpportunityDiscoveryRealtimeUniverse.intervals.length,
          universeRejections: universe.rejections,
          updatedAtUtc: universe.generatedAtUtc,
        ),
      );

  final OpportunityUniverseSnapshot _universe;
  final Set<String> _symbolsScanned = {};
  final Set<String> _streamsAnalyzed = {};
  final Set<String> _rejectionKeys = {};
  final Map<String, OpportunityStage> _latestStages = {};

  static const liquidityEvidenceMaximumAge = Duration(minutes: 30);

  bool liquidityEligibilityVerified(String symbol, DateTime evaluatedAtUtc) {
    if (!evaluatedAtUtc.isUtc) return false;
    final normalized = symbol.trim().toUpperCase();
    if (!_universe.symbols.contains(normalized)) return false;
    final age = evaluatedAtUtc.difference(_universe.generatedAtUtc);
    return !age.isNegative && age <= liquidityEvidenceMaximumAge;
  }

  void recordAnalysis(RealtimeCandleAnalysisContext context) {
    final changed =
        _symbolsScanned.add(context.key.symbol) |
        _streamsAnalyzed.add(context.key.id);
    if (changed) _publish(context.processedAtUtc);
  }

  void recordRejection({
    required RealtimeCandleAnalysisContext context,
    required AnalysisStrategy strategy,
    required SetupRejectionReason reason,
  }) {
    if (reason == SetupRejectionReason.none) return;
    final candle = context.closedCandles.isEmpty
        ? 'none'
        : context.closedCandles.last.openTime.toUtc().toIso8601String();
    final key = '${context.key.id}|${strategy.name}|$candle|${reason.name}';
    if (_rejectionKeys.add(key)) _publish(context.processedAtUtc);
  }

  void recordCandidate(RealtimeOpportunityCandidate candidate) {
    final previous = _latestStages[candidate.setupId];
    if (previous == candidate.stage) return;
    _latestStages[candidate.setupId] = candidate.stage;
    _publish(candidate.lastUpdatedAtUtc);
  }

  void _publish(DateTime updatedAtUtc) {
    int count(OpportunityStage stage) =>
        _latestStages.values.where((value) => value == stage).length;
    value = OpportunityDiscoveryCoverageSnapshot(
      eligibleSymbols: _universe.symbols.length,
      configuredStreams:
          _universe.symbols.length *
          OpportunityDiscoveryRealtimeUniverse.intervals.length,
      symbolsScanned: _symbolsScanned.length,
      streamsAnalyzed: _streamsAnalyzed.length,
      forming:
          count(OpportunityStage.detected) + count(OpportunityStage.forming),
      armed: count(OpportunityStage.armed),
      triggered: count(OpportunityStage.triggered),
      missed: count(OpportunityStage.missed),
      expired: count(OpportunityStage.expired),
      invalidated: count(OpportunityStage.invalidated),
      rejected: _rejectionKeys.length + _universe.rejectedTotal,
      universeRejections: _universe.rejections,
      updatedAtUtc: updatedAtUtc.toUtc(),
    );
  }
}

final class _DirectionEvidence {
  const _DirectionEvidence({
    required this.direction,
    required this.evaluatedAtUtc,
  });

  final ChartDirection direction;
  final DateTime evaluatedAtUtc;

  bool isFreshAt(DateTime nowUtc, {required Duration maximumAge}) {
    if (!nowUtc.isUtc || !evaluatedAtUtc.isUtc || maximumAge <= Duration.zero) {
      return false;
    }
    final age = nowUtc.difference(evaluatedAtUtc);
    return !age.isNegative && age <= maximumAge;
  }
}

final class _DiscoveryIdeaCatalog {
  final Map<String, TradeIdea> _bySetup = {};
  final Map<String, String> _setupByStreamPlaybook = {};

  void remember(TradeIdea idea, {required RegimePlaybookId playbook}) {
    if (!idea.isActionable) return;
    _bySetup[idea.setupId] = idea;
    _setupByStreamPlaybook[_key(idea.symbol, idea.timeframe, playbook)] =
        idea.setupId;
    while (_bySetup.length > 4000) {
      final oldest = _bySetup.keys.first;
      _bySetup.remove(oldest);
      _setupByStreamPlaybook.removeWhere((_, setupId) => setupId == oldest);
    }
  }

  TradeIdea? currentFor(
    RealtimeCandleStreamKey key,
    RegimePlaybookId playbook,
  ) {
    final setupId =
        _setupByStreamPlaybook[_key(key.symbol, key.timeframe, playbook)];
    return setupId == null ? null : _bySetup[setupId];
  }

  static String _key(
    String symbol,
    String timeframe,
    RegimePlaybookId playbook,
  ) => '$symbol|$timeframe|${playbook.name}';
}

final class _OpportunityDiscoveryRealtimeAnalyzer
    implements RealtimeContextualMarketAnalyzer {
  _OpportunityDiscoveryRealtimeAnalyzer({
    required this.settings,
    required Iterable<AnalysisStrategy> strategies,
    required this.catalog,
    required this.projectionCatalog,
    required this.coverage,
    String languageCode = 'fa',
  }) : strategies = List.unmodifiable(strategies.toSet()),
       _languageCode = languageCode == 'en' ? 'en' : 'fa' {
    if (this.strategies.isEmpty) {
      throw ArgumentError('At least one discovery strategy is required.');
    }
  }

  final OwnerAlphaSettings settings;
  final List<AnalysisStrategy> strategies;
  final _DiscoveryIdeaCatalog catalog;
  final RealtimeIdeaCatalog projectionCatalog;
  final OpportunityDiscoveryCoverageTracker coverage;
  String _languageCode;
  final Map<String, Map<String, _DirectionEvidence>> _directionsBySymbol = {};

  RegimePlaybookFeatureFlags get _effectivePlaybookFlags {
    final environment = RegimePlaybookFeatureFlags.fromEnvironment();
    return RegimePlaybookFeatureFlags(
      trendPullbackContinuation:
          environment.trendPullbackContinuation &&
          strategies.contains(AnalysisStrategy.trendPullback),
      rangeEdgeSweepReclaim:
          environment.rangeEdgeSweepReclaim &&
          strategies.contains(AnalysisStrategy.structureZones),
      breakoutAcceptanceRetest:
          environment.breakoutAcceptanceRetest &&
          strategies.contains(AnalysisStrategy.momentumContinuation),
      failedBreakoutReversal:
          environment.failedBreakoutReversal &&
          strategies.contains(AnalysisStrategy.structureZones),
      momentumExpansionScalp:
          environment.momentumExpansionScalp &&
          strategies.contains(AnalysisStrategy.momentumContinuation),
    );
  }

  static Duration _maximumParentEvidenceAge(String timeframe) =>
      switch (timeframe) {
        '15m' => const Duration(minutes: 45),
        '1h' => const Duration(hours: 3),
        '4h' => const Duration(hours: 12),
        '1D' => const Duration(days: 3),
        _ => Duration.zero,
      };

  void setLanguage(String languageCode) {
    if (languageCode == 'fa' || languageCode == 'en') {
      _languageCode = languageCode;
    }
  }

  @override
  Future<RealtimeCandidateAnalysisBatch> analyze(
    RealtimeCandleAnalysisContext context,
  ) async {
    coverage.recordAnalysis(context);
    if (context.closedCandles.length < 60) {
      return RealtimeCandidateAnalysisBatch();
    }
    final structure = ChartStructureAnalyzer.analyze(context.closedCandles);
    final latestClosed = context.closedCandles.last;
    final analysis = TimeframeChartAnalysis(
      symbol: context.key.symbol,
      timeframe: context.key.timeframe,
      candles: context.closedCandles,
      zones: structure.zones,
      direction: structure.direction,
      directionStrength: structure.directionStrength,
      volatilityPercent: structure.volatilityPercent,
      summary: _languageCode == 'en'
          ? 'Closed-candle regime playbook portfolio analysis.'
          : 'تحلیل پرتفوی Playbook بر پایه کندل بسته.',
      generatedAt: context.processedAtUtc,
      fingerprint:
          '${context.key.id}|${context.closedCandles.first.openTime.microsecondsSinceEpoch}|${latestClosed.openTime.microsecondsSinceEpoch}|${latestClosed.close}',
    );
    final directions = _directionsBySymbol.putIfAbsent(
      context.key.symbol,
      () => <String, _DirectionEvidence>{},
    );
    directions[analysis.timeframe] = _DirectionEvidence(
      direction: analysis.direction,
      evaluatedAtUtc: context.processedAtUtc,
    );
    final parent = switch (analysis.timeframe) {
      '5m' => '15m',
      '15m' => '1h',
      '1h' => '4h',
      '4h' => '1D',
      _ => null,
    };
    final parentEvidence = parent == null ? null : directions[parent];
    final parentFresh =
        parent == null ||
        (parentEvidence?.isFreshAt(
              context.processedAtUtc,
              maximumAge: _maximumParentEvidenceAge(parent),
            ) ??
            false);
    final liquidityVerified = coverage.liquidityEligibilityVerified(
      context.key.symbol,
      context.processedAtUtc,
    );
    final latency = context.processedAtUtc.difference(context.receivedAtUtc);
    final safeLatency = latency.isNegative ? Duration.zero : latency;
    final portfolio = RegimePlaybookPortfolioEngine.evaluate(
      analysis: analysis,
      capital: settings.capital,
      riskPercent: settings.riskPercent,
      languageCode: _languageCode,
      cadence: settings.cadence,
      flags: _effectivePlaybookFlags,
      runtime: RegimePlaybookRuntimeContext(
        evaluatedAtUtc: context.processedAtUtc,
        higherTimeframeDirection: parentEvidence?.direction,
        higherTimeframeFresh: parentFresh,
        liquidityVerified: liquidityVerified,
        processingLatency: safeLatency,
      ),
    );

    final candidates = <RealtimeOpportunityCandidate>[];
    final observations = <RealtimeObservationEnvelope>[];
    final selected = portfolio.selected;
    if (selected?.idea case final selectedIdea?) {
      catalog.remember(selectedIdea, playbook: selected!.playbook);
      projectionCatalog.remember(selectedIdea);
      candidates.add(
        RealtimeOpportunityCandidate.fromIdea(
          selectedIdea,
          detectedAtUtc: selectedIdea.createdAt.toUtc(),
          playbookId: '${selected.playbook.name}@${selected.version}',
        ),
      );
    }

    final conflict =
        portfolio.conflictOutcome ==
        PlaybookConflictOutcome.ambiguousOpposingSignals;
    for (final evaluation in portfolio.evaluations) {
      final tracked =
          evaluation.idea ??
          catalog.currentFor(context.key, evaluation.playbook);
      if (tracked == null) continue;
      final triggerPrice = context.triggersClosedCandleAnalysis
          ? latestClosed.close
          : context.workingCandle?.close ?? latestClosed.close;
      final selectedNow = selected?.playbook == evaluation.playbook;
      final triggerConfirmed =
          selectedNow &&
          context.triggersClosedCandleAnalysis &&
          triggerPrice >= tracked.entryLower! &&
          triggerPrice <= tracked.entryUpper!;
      final structureValid =
          !conflict &&
          switch (tracked.direction) {
            TradeDirection.long => triggerPrice > tracked.stopLoss!,
            TradeDirection.short => triggerPrice < tracked.stopLoss!,
            TradeDirection.wait => false,
          };
      observations.add(
        RealtimeObservationEnvelope(
          eventId:
              '${context.key.id}|${evaluation.playbook.name}|${context.disposition.name}|${context.exchangeTimestampUtc.microsecondsSinceEpoch}|${triggerPrice.toStringAsPrecision(12)}',
          setupId: tracked.setupId,
          symbol: tracked.symbol,
          timeframe: tracked.timeframe,
          observation: RealtimeMarketObservation(
            exchangeTimestampUtc: context.exchangeTimestampUtc,
            receivedAtUtc: context.receivedAtUtc,
            evaluatedAtUtc: context.processedAtUtc,
            lastPrice: triggerPrice,
            qualityScore: evaluation.qualityScore > 0
                ? evaluation.qualityScore
                : tracked.displayQualityScore,
            structureValid: structureValid,
            triggerConfirmed: triggerConfirmed,
            triggerCandleClosed: context.triggersClosedCandleAnalysis,
          ),
        ),
      );
    }
    return RealtimeCandidateAnalysisBatch(
      candidates: candidates,
      observations: observations,
    );
  }
}

final class OpportunityDiscoveryCoverageProjection
    implements RealtimeAuditedCandidateProjection {
  const OpportunityDiscoveryCoverageProjection({
    required this.delegate,
    required this.coverage,
  });

  final RealtimeAuditedCandidateProjection delegate;
  final OpportunityDiscoveryCoverageTracker coverage;

  @override
  Future<void> restore() => delegate.restore();

  @override
  Future<void> apply({
    required CandidateRegistryAuditEvent auditEvent,
    required RealtimeOpportunityCandidate? candidate,
    required CandidateCoordinationOutcome outcome,
    required CandidateAuditPersistenceDecision persistenceDecision,
  }) async {
    if (candidate != null &&
        outcome == CandidateCoordinationOutcome.committed) {
      coverage.recordCandidate(candidate);
    }
    await delegate.apply(
      auditEvent: auditEvent,
      candidate: candidate,
      outcome: outcome,
      persistenceDecision: persistenceDecision,
    );
  }
}

final class OpportunityDiscoveryRuntimeRevision {
  const OpportunityDiscoveryRuntimeRevision({
    required this.host,
    required this.coverage,
    required this.universe,
  });

  final RealtimeMarketHost host;
  final OpportunityDiscoveryCoverageTracker coverage;
  final OpportunityUniverseSnapshot universe;
}

abstract final class PlatformOpportunityDiscoveryMarketHostFactory {
  static Future<OpportunityDiscoveryRuntimeRevision> create({
    required OwnerAlphaSettings ownerSettings,
    required LocalLivePreferences localLivePreferences,
    required OpportunityStateStore opportunityStateStore,
    OpportunityUniversePolicy policy = const OpportunityUniversePolicy(),
    String languageCode = 'fa',
  }) async {
    final client = http.Client();
    try {
      final source = BitunixOpportunityDiscoveryUniverseSource(
        client: client,
        policy: policy,
      );
      final universeSnapshot = await source.load();
      final universe = OpportunityDiscoveryRealtimeUniverse.build(
        universeSnapshot,
      );
      final coverage = OpportunityDiscoveryCoverageTracker(universeSnapshot);
      final catalog = _DiscoveryIdeaCatalog();
      final projectionCatalog = RealtimeIdeaCatalog();
      final analyzer = _OpportunityDiscoveryRealtimeAnalyzer(
        settings: ownerSettings,
        strategies: localLivePreferences.strategies.isEmpty
            ? LocalLivePreferences.recommendedStrategies
            : localLivePreferences.strategies,
        catalog: catalog,
        projectionCatalog: projectionCatalog,
        coverage: coverage,
        languageCode: languageCode,
      );
      final analysisGateway = SnapshottingRealtimeMarketAnalysisGateway(
        analyzer: analyzer,
        maximumStreams: universe.maximumStreams,
        maximumClosedCandlesPerStream: 500,
      );
      final auditStore = DurableCandidateAuditStore(
        keyValueStore: const SharedPreferencesCandidateAuditKeyValueStore(),
        maximumRecords: 4000,
      );
      final coordinator = RealtimeCandidateCoordinator(
        registry: RealtimeCandidateRegistry(
          maximumCandidates: 4000,
          recentEventCapacity: 8192,
        ),
        auditStore: auditStore,
      );
      final projection = OpportunityDiscoveryCoverageProjection(
        delegate: PlatformRealtimeAuditedCandidateProjection(
          stateStore: opportunityStateStore,
          catalog: projectionCatalog,
          sizingCapital: ownerSettings.capital,
        ),
        coverage: coverage,
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
        maximumLatencySamples: 1024,
      );
      final host = RealtimeMarketHost(
        runtime: RealtimeMarketApplicationLifecycle(application),
        onLanguageChanged: analyzer.setLanguage,
        onDispose: client.close,
      );
      return OpportunityDiscoveryRuntimeRevision(
        host: host,
        coverage: coverage,
        universe: universeSnapshot,
      );
    } on Object {
      client.close();
      rethrow;
    }
  }
}
