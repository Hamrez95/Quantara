import '../../market_analysis/domain/market_chart_models.dart';

enum TradeDirection { long, short, wait }

enum AnalysisStrategy { structureZones, trendPullback, momentumContinuation }

enum SignalCadence { conservative, balanced, active }

enum SignalLifecycle { fresh, expiring, expired, taken, closed }

enum SignalOutcome {
  pendingEntry,
  active,
  expiredUntriggered,
  stopped,
  tp1,
  tp2,
  tp3,
}

enum SetupRejectionReason {
  none,
  weakDirection,
  invalidZones,
  insufficientRiskReward,
  dataUnavailable,
}

final class ScanDiagnostics {
  const ScanDiagnostics({
    this.elapsed = Duration.zero,
    this.networkRequests = 0,
    this.cacheHits = 0,
    this.requestedAnalyses = 0,
    this.rejections = const {},
  });

  final Duration elapsed;
  final int networkRequests;
  final int cacheHits;
  final int requestedAnalyses;
  final Map<SetupRejectionReason, int> rejections;

  int get completedAnalyses =>
      requestedAnalyses -
      (rejections[SetupRejectionReason.dataUnavailable] ?? 0);
}

final class AlphaMarketQuote {
  const AlphaMarketQuote({
    required this.symbol,
    required this.displayName,
    required this.lastPrice,
    required this.changePercent,
    required this.high24h,
    required this.low24h,
    required this.observedAt,
  });

  final String symbol;
  final String displayName;
  final double lastPrice;
  final double changePercent;
  final double high24h;
  final double low24h;
  final DateTime observedAt;
}

final class TradeIdea {
  const TradeIdea({
    required this.symbol,
    required this.timeframe,
    required this.direction,
    required this.confidencePercent,
    required this.entryLower,
    required this.entryUpper,
    required this.stopLoss,
    required this.targets,
    required this.riskReward,
    required this.maximumLoss,
    required this.positionSize,
    required this.notionalValue,
    required this.recommendedLeverage,
    required this.maximumSafeLeverage,
    required this.requiredMargin,
    required this.estimatedRoundTripCosts,
    required this.setupId,
    required this.candleClosedAt,
    required this.summary,
    required this.invalidation,
    required this.reasons,
    this.rejectionReason = SetupRejectionReason.none,
    this.strategy = AnalysisStrategy.structureZones,
    this.strategyVersion = '1.1',
  });

  final String symbol;
  final String timeframe;
  final TradeDirection direction;
  final int confidencePercent;
  final double? entryLower;
  final double? entryUpper;
  final double? stopLoss;
  final List<double> targets;
  final double? riskReward;
  final double maximumLoss;
  final double? positionSize;
  final double? notionalValue;
  final int? recommendedLeverage;
  final int? maximumSafeLeverage;
  final double? requiredMargin;
  final double estimatedRoundTripCosts;
  final String setupId;
  final DateTime candleClosedAt;
  final String summary;
  final String invalidation;
  final List<String> reasons;
  final SetupRejectionReason rejectionReason;
  final AnalysisStrategy strategy;
  final String strategyVersion;

  DateTime get createdAt => candleClosedAt;

  Duration get validityWindow => switch (timeframe) {
    '15m' => const Duration(minutes: 45),
    '1h' => const Duration(hours: 3),
    '4h' => const Duration(hours: 12),
    '1D' => const Duration(days: 3),
    _ => Duration.zero,
  };

  DateTime get validUntil => candleClosedAt.add(validityWindow);

  bool isExpiredAt(DateTime now) =>
      isActionable && !now.toUtc().isBefore(validUntil);

  bool isExpiringAt(DateTime now) {
    if (!isActionable || isExpiredAt(now)) {
      return false;
    }
    final remaining = validUntil.difference(now.toUtc());
    return remaining.inMilliseconds <= validityWindow.inMilliseconds ~/ 3;
  }

  bool get isActionable => direction != TradeDirection.wait;

  double? marginAt(int leverage) {
    if (!isActionable ||
        notionalValue == null ||
        leverage < 1 ||
        leverage > (maximumSafeLeverage ?? 1)) {
      return null;
    }
    return notionalValue! / leverage;
  }

  static TradeIdea wait({
    required String symbol,
    required String timeframe,
    required int confidencePercent,
    required double maximumLoss,
    required String summary,
    required String invalidation,
    required List<String> reasons,
    required SetupRejectionReason rejectionReason,
  }) {
    return TradeIdea(
      symbol: symbol,
      timeframe: timeframe,
      direction: TradeDirection.wait,
      confidencePercent: confidencePercent,
      entryLower: null,
      entryUpper: null,
      stopLoss: null,
      targets: const [],
      riskReward: null,
      maximumLoss: maximumLoss,
      positionSize: null,
      notionalValue: null,
      recommendedLeverage: null,
      maximumSafeLeverage: null,
      requiredMargin: null,
      estimatedRoundTripCosts: 0,
      setupId: '$symbol|$timeframe|wait',
      candleClosedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      summary: summary,
      invalidation: invalidation,
      reasons: List.unmodifiable(reasons),
      rejectionReason: rejectionReason,
    );
  }
}

final class SymbolRadarResult {
  SymbolRadarResult({
    required this.quote,
    required this.idea,
    required this.analysis,
    Map<String, TradeIdea>? ideasByTimeframe,
    Map<String, TimeframeChartAnalysis>? analysesByTimeframe,
  }) : ideasByTimeframe = Map.unmodifiable(
         ideasByTimeframe ?? {idea.timeframe: idea},
       ),
       analysesByTimeframe = Map.unmodifiable(
         analysesByTimeframe ?? {analysis.timeframe: analysis},
       );

  final AlphaMarketQuote quote;
  final TradeIdea idea;
  final TimeframeChartAnalysis analysis;
  final Map<String, TradeIdea> ideasByTimeframe;
  final Map<String, TimeframeChartAnalysis> analysesByTimeframe;
}

final class OwnerAlphaSnapshot {
  OwnerAlphaSnapshot({
    required Iterable<SymbolRadarResult> radar,
    required this.selectedSymbol,
    required this.selectedTimeframe,
    required this.selectedAnalysis,
    required this.selectedIdea,
    required Map<String, ChartDirection> timeframeDirections,
    Map<String, String> scanFailures = const {},
    ScanDiagnostics diagnostics = const ScanDiagnostics(),
    required this.generatedAt,
  }) : radar = List.unmodifiable(radar),
       timeframeDirections = Map.unmodifiable(timeframeDirections),
       scanFailures = Map.unmodifiable(scanFailures),
       diagnostics = ScanDiagnostics(
         elapsed: diagnostics.elapsed,
         networkRequests: diagnostics.networkRequests,
         cacheHits: diagnostics.cacheHits,
         requestedAnalyses: diagnostics.requestedAnalyses,
         rejections: Map.unmodifiable(diagnostics.rejections),
       ) {
    if (this.radar.isEmpty) {
      throw ArgumentError('Radar results must not be empty.');
    }
    if (!generatedAt.isUtc) {
      throw ArgumentError('Snapshot time must be UTC.');
    }
  }

  final List<SymbolRadarResult> radar;
  final String selectedSymbol;
  final String selectedTimeframe;
  final TimeframeChartAnalysis selectedAnalysis;
  final TradeIdea selectedIdea;
  final Map<String, ChartDirection> timeframeDirections;
  final Map<String, String> scanFailures;
  final ScanDiagnostics diagnostics;
  final DateTime generatedAt;

  List<TradeIdea> get opportunities {
    final result = radar
        .expand((item) => item.ideasByTimeframe.values)
        .where((idea) => idea.isActionable)
        .toList(growable: false);
    result.sort(
      (left, right) =>
          right.confidencePercent.compareTo(left.confidencePercent),
    );
    return result;
  }

  AlphaMarketQuote quoteFor(String symbol) {
    return radar.firstWhere((item) => item.quote.symbol == symbol).quote;
  }
}

abstract interface class OwnerAlphaRepository {
  Future<OwnerAlphaSnapshot> scan({
    required List<String> symbols,
    required String selectedSymbol,
    required String selectedTimeframe,
    required double capital,
    required double riskPercent,
    required String languageCode,
  });
}

final class OwnerAlphaSettings {
  const OwnerAlphaSettings({
    required this.symbols,
    required this.capital,
    required this.riskPercent,
    this.strategy = AnalysisStrategy.structureZones,
    this.cadence = SignalCadence.balanced,
  });

  final List<String> symbols;
  final double capital;
  final double riskPercent;
  final AnalysisStrategy strategy;
  final SignalCadence cadence;
}

abstract interface class OwnerAlphaSettingsStore {
  Future<OwnerAlphaSettings?> load();

  Future<void> save(OwnerAlphaSettings settings);
}

final class SignalJournalEntry {
  const SignalJournalEntry({
    required this.setupId,
    required this.symbol,
    required this.timeframe,
    required this.direction,
    required this.strategy,
    required this.strategyVersion,
    required this.createdAt,
    required this.validUntil,
    required this.entryLower,
    required this.entryUpper,
    required this.stopLoss,
    required this.targets,
    required this.maximumLoss,
    required this.positionSize,
    required this.notionalValue,
    required this.estimatedRoundTripCosts,
    required this.recommendedLeverage,
    required this.maximumSafeLeverage,
    required this.selectedLeverage,
    required this.summary,
    required this.invalidation,
    this.outcome = SignalOutcome.pendingEntry,
    this.highestTargetHit = 0,
    this.activatedAt,
    this.resolvedAt,
    this.priceChangePercent,
    this.simulatedPnl,
    this.marginReturnPercent,
    this.note = '',
    this.closed = false,
  });

  factory SignalJournalEntry.fromIdea(TradeIdea idea) => SignalJournalEntry(
    setupId: idea.setupId,
    symbol: idea.symbol,
    timeframe: idea.timeframe,
    direction: idea.direction,
    strategy: idea.strategy,
    strategyVersion: idea.strategyVersion,
    createdAt: idea.createdAt,
    validUntil: idea.validUntil,
    entryLower: idea.entryLower,
    entryUpper: idea.entryUpper,
    stopLoss: idea.stopLoss,
    targets: idea.targets,
    maximumLoss: idea.maximumLoss,
    positionSize: idea.positionSize!,
    notionalValue: idea.notionalValue!,
    estimatedRoundTripCosts: idea.estimatedRoundTripCosts,
    recommendedLeverage: idea.recommendedLeverage!,
    maximumSafeLeverage: idea.maximumSafeLeverage!,
    selectedLeverage: idea.recommendedLeverage!,
    summary: idea.summary,
    invalidation: idea.invalidation,
  );

  final String setupId;
  final String symbol;
  final String timeframe;
  final TradeDirection direction;
  final AnalysisStrategy strategy;
  final String strategyVersion;
  final DateTime createdAt;
  final DateTime validUntil;
  final double? entryLower;
  final double? entryUpper;
  final double? stopLoss;
  final List<double> targets;
  final double maximumLoss;
  final double positionSize;
  final double notionalValue;
  final double estimatedRoundTripCosts;
  final int recommendedLeverage;
  final int maximumSafeLeverage;
  final int selectedLeverage;
  final String summary;
  final String invalidation;
  final SignalOutcome outcome;
  final int highestTargetHit;
  final DateTime? activatedAt;
  final DateTime? resolvedAt;
  final double? priceChangePercent;
  final double? simulatedPnl;
  final double? marginReturnPercent;
  final String note;
  final bool closed;

  double get selectedMargin => notionalValue / selectedLeverage;

  bool get hasTerminalOutcome =>
      outcome == SignalOutcome.expiredUntriggered ||
      outcome == SignalOutcome.stopped ||
      outcome == SignalOutcome.tp3;

  SignalLifecycle lifecycle(DateTime now, {required bool taken}) {
    if (closed || hasTerminalOutcome) return SignalLifecycle.closed;
    if (taken) return SignalLifecycle.taken;
    if (outcome == SignalOutcome.active ||
        outcome == SignalOutcome.tp1 ||
        outcome == SignalOutcome.tp2) {
      return SignalLifecycle.fresh;
    }
    if (!now.toUtc().isBefore(validUntil)) return SignalLifecycle.expired;
    final total = validUntil.difference(createdAt);
    final remaining = validUntil.difference(now.toUtc());
    return remaining.inMilliseconds <= total.inMilliseconds ~/ 3
        ? SignalLifecycle.expiring
        : SignalLifecycle.fresh;
  }

  SignalJournalEntry copyWith({
    String? note,
    bool? closed,
    int? selectedLeverage,
    SignalOutcome? outcome,
    int? highestTargetHit,
    DateTime? activatedAt,
    DateTime? resolvedAt,
    double? priceChangePercent,
    double? simulatedPnl,
    double? marginReturnPercent,
  }) =>
      SignalJournalEntry(
        setupId: setupId,
        symbol: symbol,
        timeframe: timeframe,
        direction: direction,
        strategy: strategy,
        strategyVersion: strategyVersion,
        createdAt: createdAt,
        validUntil: validUntil,
        entryLower: entryLower,
        entryUpper: entryUpper,
        stopLoss: stopLoss,
        targets: targets,
        maximumLoss: maximumLoss,
        positionSize: positionSize,
        notionalValue: notionalValue,
        estimatedRoundTripCosts: estimatedRoundTripCosts,
        recommendedLeverage: recommendedLeverage,
        maximumSafeLeverage: maximumSafeLeverage,
        selectedLeverage: selectedLeverage ?? this.selectedLeverage,
        summary: summary,
        invalidation: invalidation,
        outcome: outcome ?? this.outcome,
        highestTargetHit: highestTargetHit ?? this.highestTargetHit,
        activatedAt: activatedAt ?? this.activatedAt,
        resolvedAt: resolvedAt ?? this.resolvedAt,
        priceChangePercent:
            priceChangePercent ?? this.priceChangePercent,
        simulatedPnl: simulatedPnl ?? this.simulatedPnl,
        marginReturnPercent:
            marginReturnPercent ?? this.marginReturnPercent,
        note: note ?? this.note,
        closed: closed ?? this.closed,
      );

  Map<String, Object?> toJson() => {
    'setupId': setupId,
    'symbol': symbol,
    'timeframe': timeframe,
    'direction': direction.name,
    'strategy': strategy.name,
    'strategyVersion': strategyVersion,
    'createdAt': createdAt.toIso8601String(),
    'validUntil': validUntil.toIso8601String(),
    'entryLower': entryLower,
    'entryUpper': entryUpper,
    'stopLoss': stopLoss,
    'targets': targets,
    'maximumLoss': maximumLoss,
    'positionSize': positionSize,
    'notionalValue': notionalValue,
    'estimatedRoundTripCosts': estimatedRoundTripCosts,
    'recommendedLeverage': recommendedLeverage,
    'maximumSafeLeverage': maximumSafeLeverage,
    'selectedLeverage': selectedLeverage,
    'summary': summary,
    'invalidation': invalidation,
    'outcome': outcome.name,
    'highestTargetHit': highestTargetHit,
    'activatedAt': activatedAt?.toIso8601String(),
    'resolvedAt': resolvedAt?.toIso8601String(),
    'priceChangePercent': priceChangePercent,
    'simulatedPnl': simulatedPnl,
    'marginReturnPercent': marginReturnPercent,
    'note': note,
    'closed': closed,
  };

  static SignalJournalEntry? tryFromJson(Map<String, Object?> value) {
    try {
      final direction = TradeDirection.values.firstWhere(
        (item) => item.name == value['direction'],
      );
      final strategy = AnalysisStrategy.values.firstWhere(
        (item) => item.name == value['strategy'],
      );
      final targets = (value['targets'] as List<Object?>)
          .whereType<num>()
          .map((item) => item.toDouble())
          .toList(growable: false);
      final setupId = value['setupId'] as String;
      final symbol = value['symbol'] as String;
      if (setupId.isEmpty || setupId.length > 320 || symbol.isEmpty) {
        return null;
      }
      final recommendedLeverage =
          (value['recommendedLeverage'] as num?)?.toInt() ?? 1;
      final maximumSafeLeverage =
          (value['maximumSafeLeverage'] as num?)?.toInt() ??
          recommendedLeverage;
      final selectedLeverage =
          (value['selectedLeverage'] as num?)?.toInt() ??
          recommendedLeverage;
      final outcomeName = value['outcome'] as String?;
      final outcome = SignalOutcome.values.firstWhere(
        (item) => item.name == outcomeName,
        orElse: () => SignalOutcome.pendingEntry,
      );
      return SignalJournalEntry(
        setupId: setupId,
        symbol: symbol,
        timeframe: value['timeframe'] as String,
        direction: direction,
        strategy: strategy,
        strategyVersion: value['strategyVersion'] as String,
        createdAt: DateTime.parse(value['createdAt'] as String).toUtc(),
        validUntil: DateTime.parse(value['validUntil'] as String).toUtc(),
        entryLower: (value['entryLower'] as num?)?.toDouble(),
        entryUpper: (value['entryUpper'] as num?)?.toDouble(),
        stopLoss: (value['stopLoss'] as num?)?.toDouble(),
        targets: targets,
        maximumLoss: (value['maximumLoss'] as num?)?.toDouble() ?? 0,
        positionSize: (value['positionSize'] as num?)?.toDouble() ?? 0,
        notionalValue: (value['notionalValue'] as num?)?.toDouble() ?? 0,
        estimatedRoundTripCosts:
            (value['estimatedRoundTripCosts'] as num?)?.toDouble() ?? 0,
        recommendedLeverage: recommendedLeverage.clamp(1, 100).toInt(),
        maximumSafeLeverage: maximumSafeLeverage.clamp(1, 100).toInt(),
        selectedLeverage: selectedLeverage.clamp(
          1,
          maximumSafeLeverage.clamp(1, 100),
        ).toInt(),
        summary: value['summary'] as String,
        invalidation: value['invalidation'] as String,
        outcome: outcome,
        highestTargetHit:
            ((value['highestTargetHit'] as num?)?.toInt() ?? 0)
                .clamp(0, 3)
                .toInt(),
        activatedAt: _tryDate(value['activatedAt']),
        resolvedAt: _tryDate(value['resolvedAt']),
        priceChangePercent:
            (value['priceChangePercent'] as num?)?.toDouble(),
        simulatedPnl: (value['simulatedPnl'] as num?)?.toDouble(),
        marginReturnPercent:
            (value['marginReturnPercent'] as num?)?.toDouble(),
        note: (value['note'] as String?) ?? '',
        closed: value['closed'] == true,
      );
    } on Object {
      return null;
    }
  }

  static DateTime? _tryDate(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value)?.toUtc();
  }
}

final class OpportunityState {
  const OpportunityState({
    this.notificationsEnabled = false,
    this.takenSetupIds = const {},
    this.notifiedSetupIds = const {},
    this.journal = const [],
    this.lastBackgroundScanAt,
    this.lastBackgroundError,
  });

  final bool notificationsEnabled;
  final Set<String> takenSetupIds;
  final Set<String> notifiedSetupIds;
  final List<SignalJournalEntry> journal;
  final DateTime? lastBackgroundScanAt;
  final String? lastBackgroundError;

  OpportunityState copyWith({
    bool? notificationsEnabled,
    Set<String>? takenSetupIds,
    Set<String>? notifiedSetupIds,
    List<SignalJournalEntry>? journal,
    DateTime? lastBackgroundScanAt,
    String? lastBackgroundError,
  }) {
    return OpportunityState(
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      takenSetupIds: takenSetupIds ?? this.takenSetupIds,
      notifiedSetupIds: notifiedSetupIds ?? this.notifiedSetupIds,
      journal: journal ?? this.journal,
      lastBackgroundScanAt:
          lastBackgroundScanAt ?? this.lastBackgroundScanAt,
      lastBackgroundError:
          lastBackgroundError ?? this.lastBackgroundError,
    );
  }
}

abstract interface class OpportunityStateStore {
  Future<OpportunityState> load();

  Future<void> save(OpportunityState state);
}

abstract interface class BackgroundScanGateway {
  Future<void> configure({
    required bool enabled,
    required OwnerAlphaSettings settings,
    required String languageCode,
  });
}

final class NoopBackgroundScanGateway implements BackgroundScanGateway {
  const NoopBackgroundScanGateway();

  @override
  Future<void> configure({
    required bool enabled,
    required OwnerAlphaSettings settings,
    required String languageCode,
  }) async {}
}

abstract interface class SetupNotificationGateway {
  Future<bool> requestPermission();

  Future<void> show(TradeIdea idea, {required String languageCode});

  Future<void> openBackgroundSettings();
}

final class NoopSetupNotificationGateway implements SetupNotificationGateway {
  const NoopSetupNotificationGateway();

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> show(TradeIdea idea, {required String languageCode}) async {}

  @override
  Future<void> openBackgroundSettings() async {}
}
