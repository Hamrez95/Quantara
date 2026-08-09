import '../../owner_alpha/domain/owner_alpha_models.dart';

const tradingLabSchemaVersion = 1;
const tradingLabMaximumEvents = 20000;
const tradingLabMaximumProcessedDecisions = 50000;

enum TradingLabRunStatus { running, stopped }

enum TradingLabEventKind {
  heartbeat,
  candidateObserved,
  candidateRejected,
  candidatePending,
  positionOpened,
  targetFilled,
  stopPromoted,
  stopFilled,
  positionClosed,
  anomaly,
}

final class TradingLabRunManifest {
  TradingLabRunManifest({
    required this.runId,
    required this.startedAtUtc,
    required this.startingEquity,
    required this.riskPercent,
    required this.maximumConcurrentPositions,
    required this.leverage,
    required Iterable<String> symbols,
    required Iterable<String> timeframes,
    required Iterable<String> strategies,
    this.feeRateBps = 6,
    this.slippageBps = 2,
    this.fundingRatePerEightHours = 0,
    this.notes = '',
  }) : symbols = List.unmodifiable(
         symbols
             .map((item) => item.trim().toUpperCase())
             .where((item) => item.isNotEmpty)
             .toSet(),
       ),
       timeframes = List.unmodifiable(
         timeframes.map((item) => item.trim()).where((item) => item.isNotEmpty).toSet(),
       ),
       strategies = List.unmodifiable(
         strategies.map((item) => item.trim()).where((item) => item.isNotEmpty).toSet(),
       ) {
    validate();
  }

  final String runId;
  final DateTime startedAtUtc;
  final double startingEquity;
  final double riskPercent;
  final int maximumConcurrentPositions;
  final int leverage;
  final List<String> symbols;
  final List<String> timeframes;
  final List<String> strategies;
  final double feeRateBps;
  final double slippageBps;
  final double fundingRatePerEightHours;
  final String notes;

  void validate() {
    if (runId.trim().isEmpty || !startedAtUtc.isUtc) {
      throw const FormatException('Trading Lab run id and UTC start time are required.');
    }
    if (!startingEquity.isFinite || startingEquity < 50) {
      throw const FormatException('Trading Lab starting equity must be at least 50 USDT.');
    }
    if (!riskPercent.isFinite || riskPercent < 0.05 || riskPercent > 2) {
      throw const FormatException('Trading Lab risk must be between 0.05% and 2%.');
    }
    if (maximumConcurrentPositions < 1 || maximumConcurrentPositions > 3) {
      throw const FormatException('Trading Lab supports one to three concurrent positions.');
    }
    if (leverage < 1 || leverage > TradeIdea.maximumManualLeverage) {
      throw const FormatException('Trading Lab leverage must be between 1x and 125x.');
    }
    if (symbols.isEmpty || symbols.length > 30 || timeframes.isEmpty || strategies.isEmpty) {
      throw const FormatException('Trading Lab requires symbols, timeframes and strategy versions.');
    }
    if ([feeRateBps, slippageBps].any((value) => !value.isFinite || value < 0 || value > 200)) {
      throw const FormatException('Trading Lab execution costs are outside the supported range.');
    }
    if (!fundingRatePerEightHours.isFinite || fundingRatePerEightHours.abs() > 0.05) {
      throw const FormatException('Trading Lab funding model is outside the supported range.');
    }
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': tradingLabSchemaVersion,
    'runId': runId,
    'startedAtUtc': startedAtUtc.toIso8601String(),
    'startingEquity': startingEquity,
    'riskPercent': riskPercent,
    'maximumConcurrentPositions': maximumConcurrentPositions,
    'leverage': leverage,
    'symbols': symbols,
    'timeframes': timeframes,
    'strategies': strategies,
    'feeRateBps': feeRateBps,
    'slippageBps': slippageBps,
    'fundingRatePerEightHours': fundingRatePerEightHours,
    'notes': notes,
  };

  factory TradingLabRunManifest.fromJson(Map<String, Object?> json) => TradingLabRunManifest(
    runId: json['runId']?.toString() ?? '',
    startedAtUtc: _date(json['startedAtUtc']),
    startingEquity: _double(json['startingEquity']),
    riskPercent: _double(json['riskPercent']),
    maximumConcurrentPositions: _int(json['maximumConcurrentPositions']),
    leverage: _int(json['leverage']),
    symbols: _strings(json['symbols']),
    timeframes: _strings(json['timeframes']),
    strategies: _strings(json['strategies']),
    feeRateBps: _double(json['feeRateBps'], fallback: 6),
    slippageBps: _double(json['slippageBps'], fallback: 2),
    fundingRatePerEightHours: _double(json['fundingRatePerEightHours']),
    notes: json['notes']?.toString() ?? '',
  );
}

final class TradingLabEvent {
  TradingLabEvent({
    required this.eventId,
    required this.atUtc,
    required this.kind,
    required this.cycleId,
    required this.reason,
    this.setupId,
    this.symbol,
    this.timeframe,
    this.strategy,
    this.strategyVersion,
    Map<String, double> metrics = const {},
    Map<String, String> attributes = const {},
  }) : metrics = Map.unmodifiable(metrics),
       attributes = Map.unmodifiable(attributes) {
    if (eventId.trim().isEmpty || !atUtc.isUtc || cycleId < 0 || reason.trim().isEmpty) {
      throw const FormatException('Invalid Trading Lab event.');
    }
  }

  final String eventId;
  final DateTime atUtc;
  final TradingLabEventKind kind;
  final int cycleId;
  final String reason;
  final String? setupId;
  final String? symbol;
  final String? timeframe;
  final String? strategy;
  final String? strategyVersion;
  final Map<String, double> metrics;
  final Map<String, String> attributes;

  Map<String, Object?> toJson() => {
    'eventId': eventId,
    'atUtc': atUtc.toIso8601String(),
    'kind': kind.name,
    'cycleId': cycleId,
    'reason': reason,
    'setupId': setupId,
    'symbol': symbol,
    'timeframe': timeframe,
    'strategy': strategy,
    'strategyVersion': strategyVersion,
    'metrics': metrics,
    'attributes': attributes,
  };

  factory TradingLabEvent.fromJson(Map<String, Object?> json) => TradingLabEvent(
    eventId: json['eventId']?.toString() ?? '',
    atUtc: _date(json['atUtc']),
    kind: TradingLabEventKind.values.firstWhere(
      (item) => item.name == json['kind'],
      orElse: () => TradingLabEventKind.anomaly,
    ),
    cycleId: _int(json['cycleId']),
    reason: json['reason']?.toString() ?? 'unknown',
    setupId: _nullableString(json['setupId']),
    symbol: _nullableString(json['symbol']),
    timeframe: _nullableString(json['timeframe']),
    strategy: _nullableString(json['strategy']),
    strategyVersion: _nullableString(json['strategyVersion']),
    metrics: _doubleMap(json['metrics']),
    attributes: _stringMap(json['attributes']),
  );
}

final class TradingLabPendingCandidate {
  TradingLabPendingCandidate({
    required this.decisionKey,
    required this.setupId,
    required this.symbol,
    required this.timeframe,
    required this.direction,
    required this.strategy,
    required this.strategyVersion,
    required this.marketRegime,
    required this.confidencePercent,
    required this.riskReward,
    required this.entryLower,
    required this.entryUpper,
    required this.stopLoss,
    required Iterable<double> targets,
    required this.recommendedLeverage,
    required this.maximumSafeLeverage,
    required this.observedAtUtc,
    required this.validUntilUtc,
    required this.signalCandleOpenTimeUtc,
    required Map<String, double> indicatorSnapshot,
  }) : targets = List.unmodifiable(targets),
       indicatorSnapshot = Map.unmodifiable(indicatorSnapshot) {
    if (decisionKey.trim().isEmpty || setupId.trim().isEmpty || symbol.trim().isEmpty || timeframe.trim().isEmpty) {
      throw const FormatException('Invalid Trading Lab candidate identity.');
    }
    if (!observedAtUtc.isUtc || !validUntilUtc.isUtc || !signalCandleOpenTimeUtc.isUtc) {
      throw const FormatException('Trading Lab candidate timestamps must be UTC.');
    }
    if (direction == TradeDirection.wait ||
        entryLower <= 0 ||
        entryUpper < entryLower ||
        stopLoss <= 0 ||
        targets.isEmpty ||
        targets.any((value) => !value.isFinite || value <= 0)) {
      throw const FormatException('Invalid Trading Lab candidate plan.');
    }
  }

  final String decisionKey;
  final String setupId;
  final String symbol;
  final String timeframe;
  final TradeDirection direction;
  final String strategy;
  final String strategyVersion;
  final String marketRegime;
  final int confidencePercent;
  final double riskReward;
  final double entryLower;
  final double entryUpper;
  final double stopLoss;
  final List<double> targets;
  final int recommendedLeverage;
  final int maximumSafeLeverage;
  final DateTime observedAtUtc;
  final DateTime validUntilUtc;
  final DateTime signalCandleOpenTimeUtc;
  final Map<String, double> indicatorSnapshot;

  Map<String, Object?> toJson() => {
    'decisionKey': decisionKey,
    'setupId': setupId,
    'symbol': symbol,
    'timeframe': timeframe,
    'direction': direction.name,
    'strategy': strategy,
    'strategyVersion': strategyVersion,
    'marketRegime': marketRegime,
    'confidencePercent': confidencePercent,
    'riskReward': riskReward,
    'entryLower': entryLower,
    'entryUpper': entryUpper,
    'stopLoss': stopLoss,
    'targets': targets,
    'recommendedLeverage': recommendedLeverage,
    'maximumSafeLeverage': maximumSafeLeverage,
    'observedAtUtc': observedAtUtc.toIso8601String(),
    'validUntilUtc': validUntilUtc.toIso8601String(),
    'signalCandleOpenTimeUtc': signalCandleOpenTimeUtc.toIso8601String(),
    'indicatorSnapshot': indicatorSnapshot,
  };

  factory TradingLabPendingCandidate.fromJson(Map<String, Object?> json) => TradingLabPendingCandidate(
    decisionKey: json['decisionKey']?.toString() ?? '',
    setupId: json['setupId']?.toString() ?? '',
    symbol: json['symbol']?.toString() ?? '',
    timeframe: json['timeframe']?.toString() ?? '',
    direction: TradeDirection.values.firstWhere(
      (item) => item.name == json['direction'],
      orElse: () => TradeDirection.wait,
    ),
    strategy: json['strategy']?.toString() ?? '',
    strategyVersion: json['strategyVersion']?.toString() ?? '',
    marketRegime: json['marketRegime']?.toString() ?? 'transition',
    confidencePercent: _int(json['confidencePercent']),
    riskReward: _double(json['riskReward']),
    entryLower: _double(json['entryLower']),
    entryUpper: _double(json['entryUpper']),
    stopLoss: _double(json['stopLoss']),
    targets: _doubles(json['targets']),
    recommendedLeverage: _int(json['recommendedLeverage'], fallback: 1),
    maximumSafeLeverage: _int(json['maximumSafeLeverage'], fallback: 1),
    observedAtUtc: _date(json['observedAtUtc']),
    validUntilUtc: _date(json['validUntilUtc']),
    signalCandleOpenTimeUtc: _date(json['signalCandleOpenTimeUtc']),
    indicatorSnapshot: _doubleMap(json['indicatorSnapshot']),
  );
}

final class TradingLabPosition {
  TradingLabPosition({
    required this.positionId,
    required this.decisionKey,
    required this.setupId,
    required this.symbol,
    required this.timeframe,
    required this.direction,
    required this.strategy,
    required this.strategyVersion,
    required this.marketRegime,
    required this.confidencePercent,
    required this.riskReward,
    required this.entryPrice,
    required this.originalStopLoss,
    required this.currentStopLoss,
    required Iterable<double> targets,
    required Iterable<double> targetFractions,
    required this.initialQuantity,
    required this.remainingQuantity,
    required this.leverage,
    required this.openedAtUtc,
    required this.lastEvaluatedCandleAtUtc,
    required this.marginReserved,
    required this.entryFee,
    this.realizedGrossPnl = 0,
    this.exitFees = 0,
    this.funding = 0,
    this.slippageCost = 0,
    this.maximumFavorablePrice,
    this.maximumAdversePrice,
    Iterable<int> filledTargetIndexes = const [],
    this.closedAtUtc,
    this.closeReason,
  }) : targets = List.unmodifiable(targets),
       targetFractions = List.unmodifiable(targetFractions),
       filledTargetIndexes = Set.of(filledTargetIndexes) {
    if (positionId.trim().isEmpty || initialQuantity <= 0 || remainingQuantity < 0 || remainingQuantity > initialQuantity) {
      throw const FormatException('Invalid Trading Lab paper position.');
    }
    if (!openedAtUtc.isUtc || !lastEvaluatedCandleAtUtc.isUtc || (closedAtUtc != null && !closedAtUtc!.isUtc)) {
      throw const FormatException('Trading Lab position timestamps must be UTC.');
    }
  }

  final String positionId;
  final String decisionKey;
  final String setupId;
  final String symbol;
  final String timeframe;
  final TradeDirection direction;
  final String strategy;
  final String strategyVersion;
  final String marketRegime;
  final int confidencePercent;
  final double riskReward;
  final double entryPrice;
  final double originalStopLoss;
  double currentStopLoss;
  final List<double> targets;
  final List<double> targetFractions;
  final double initialQuantity;
  double remainingQuantity;
  final int leverage;
  final DateTime openedAtUtc;
  DateTime lastEvaluatedCandleAtUtc;
  final double marginReserved;
  final double entryFee;
  double realizedGrossPnl;
  double exitFees;
  double funding;
  double slippageCost;
  double? maximumFavorablePrice;
  double? maximumAdversePrice;
  final Set<int> filledTargetIndexes;
  DateTime? closedAtUtc;
  String? closeReason;

  bool get isOpen => closedAtUtc == null && remainingQuantity > 0;
  double get netRealizedPnl => realizedGrossPnl - entryFee - exitFees - funding;
  double get initialRisk => (entryPrice - originalStopLoss).abs() * initialQuantity;
  double get realizedR => initialRisk <= 0 ? 0 : netRealizedPnl / initialRisk;

  Map<String, Object?> toJson() => {
    'positionId': positionId,
    'decisionKey': decisionKey,
    'setupId': setupId,
    'symbol': symbol,
    'timeframe': timeframe,
    'direction': direction.name,
    'strategy': strategy,
    'strategyVersion': strategyVersion,
    'marketRegime': marketRegime,
    'confidencePercent': confidencePercent,
    'riskReward': riskReward,
    'entryPrice': entryPrice,
    'originalStopLoss': originalStopLoss,
    'currentStopLoss': currentStopLoss,
    'targets': targets,
    'targetFractions': targetFractions,
    'initialQuantity': initialQuantity,
    'remainingQuantity': remainingQuantity,
    'leverage': leverage,
    'openedAtUtc': openedAtUtc.toIso8601String(),
    'lastEvaluatedCandleAtUtc': lastEvaluatedCandleAtUtc.toIso8601String(),
    'marginReserved': marginReserved,
    'entryFee': entryFee,
    'realizedGrossPnl': realizedGrossPnl,
    'exitFees': exitFees,
    'funding': funding,
    'slippageCost': slippageCost,
    'maximumFavorablePrice': maximumFavorablePrice,
    'maximumAdversePrice': maximumAdversePrice,
    'filledTargetIndexes': filledTargetIndexes.toList()..sort(),
    'closedAtUtc': closedAtUtc?.toIso8601String(),
    'closeReason': closeReason,
  };

  factory TradingLabPosition.fromJson(Map<String, Object?> json) => TradingLabPosition(
    positionId: json['positionId']?.toString() ?? '',
    decisionKey: json['decisionKey']?.toString() ?? '',
    setupId: json['setupId']?.toString() ?? '',
    symbol: json['symbol']?.toString() ?? '',
    timeframe: json['timeframe']?.toString() ?? '',
    direction: TradeDirection.values.firstWhere(
      (item) => item.name == json['direction'],
      orElse: () => TradeDirection.wait,
    ),
    strategy: json['strategy']?.toString() ?? '',
    strategyVersion: json['strategyVersion']?.toString() ?? '',
    marketRegime: json['marketRegime']?.toString() ?? 'transition',
    confidencePercent: _int(json['confidencePercent']),
    riskReward: _double(json['riskReward']),
    entryPrice: _double(json['entryPrice']),
    originalStopLoss: _double(json['originalStopLoss']),
    currentStopLoss: _double(json['currentStopLoss']),
    targets: _doubles(json['targets']),
    targetFractions: _doubles(json['targetFractions']),
    initialQuantity: _double(json['initialQuantity']),
    remainingQuantity: _double(json['remainingQuantity']),
    leverage: _int(json['leverage'], fallback: 1),
    openedAtUtc: _date(json['openedAtUtc']),
    lastEvaluatedCandleAtUtc: _date(json['lastEvaluatedCandleAtUtc']),
    marginReserved: _double(json['marginReserved']),
    entryFee: _double(json['entryFee']),
    realizedGrossPnl: _double(json['realizedGrossPnl']),
    exitFees: _double(json['exitFees']),
    funding: _double(json['funding']),
    slippageCost: _double(json['slippageCost']),
    maximumFavorablePrice: _nullableDouble(json['maximumFavorablePrice']),
    maximumAdversePrice: _nullableDouble(json['maximumAdversePrice']),
    filledTargetIndexes: (json['filledTargetIndexes'] as List<Object?>? ?? const []).whereType<num>().map((item) => item.toInt()),
    closedAtUtc: _nullableDate(json['closedAtUtc']),
    closeReason: _nullableString(json['closeReason']),
  );
}

final class TradingLabRun {
  TradingLabRun({
    required this.manifest,
    this.status = TradingLabRunStatus.running,
    double? balance,
    double? currentEquity,
    double? peakEquity,
    this.maximumDrawdownPercent = 0,
    Iterable<TradingLabPendingCandidate> pendingCandidates = const [],
    Iterable<TradingLabPosition> openPositions = const [],
    Iterable<TradingLabPosition> closedPositions = const [],
    Iterable<TradingLabEvent> events = const [],
    Iterable<String> processedDecisionKeys = const [],
    this.lastSnapshotAtUtc,
    this.cycleId = 0,
    this.lastWhyNoTrade = 'Run created; waiting for the first market snapshot.',
  }) : balance = balance ?? manifest.startingEquity,
       currentEquity = currentEquity ?? manifest.startingEquity,
       peakEquity = peakEquity ?? manifest.startingEquity,
       pendingCandidates = List.of(pendingCandidates),
       openPositions = List.of(openPositions),
       closedPositions = List.of(closedPositions),
       events = List.of(events),
       processedDecisionKeys = Set.of(processedDecisionKeys) {
    if (this.balance < 0 || this.currentEquity < 0 || this.peakEquity <= 0 || cycleId < 0) {
      throw const FormatException('Invalid Trading Lab run accounting.');
    }
  }

  final TradingLabRunManifest manifest;
  TradingLabRunStatus status;
  double balance;
  double currentEquity;
  double peakEquity;
  double maximumDrawdownPercent;
  final List<TradingLabPendingCandidate> pendingCandidates;
  final List<TradingLabPosition> openPositions;
  final List<TradingLabPosition> closedPositions;
  final List<TradingLabEvent> events;
  final Set<String> processedDecisionKeys;
  DateTime? lastSnapshotAtUtc;
  int cycleId;
  String lastWhyNoTrade;

  bool get isRunning => status == TradingLabRunStatus.running;
  int get tradeCount => closedPositions.length;
  int get wins => closedPositions.where((item) => item.netRealizedPnl > 0).length;
  int get losses => closedPositions.where((item) => item.netRealizedPnl < 0).length;
  double get netRealizedPnl => closedPositions.fold<double>(0, (sum, item) => sum + item.netRealizedPnl) + openPositions.fold<double>(0, (sum, item) => sum - item.entryFee);
  double get returnPercent => manifest.startingEquity <= 0 ? 0 : (currentEquity / manifest.startingEquity - 1) * 100;
  double get winRatePercent => tradeCount == 0 ? 0 : wins / tradeCount * 100;
  double get averageR => tradeCount == 0 ? 0 : closedPositions.fold<double>(0, (sum, item) => sum + item.realizedR) / tradeCount;
  double get grossProfit => closedPositions.where((item) => item.netRealizedPnl > 0).fold<double>(0, (sum, item) => sum + item.netRealizedPnl);
  double get grossLoss => closedPositions.where((item) => item.netRealizedPnl < 0).fold<double>(0, (sum, item) => sum + item.netRealizedPnl.abs());
  double? get profitFactor => grossLoss <= 0 ? (grossProfit > 0 ? double.infinity : null) : grossProfit / grossLoss;

  void appendEvent(TradingLabEvent event) {
    events.add(event);
    if (events.length > tradingLabMaximumEvents) {
      events.removeRange(0, events.length - tradingLabMaximumEvents);
    }
  }

  void rememberDecision(String key) {
    processedDecisionKeys.add(key);
    if (processedDecisionKeys.length > tradingLabMaximumProcessedDecisions) {
      final overflow = processedDecisionKeys.length - tradingLabMaximumProcessedDecisions;
      processedDecisionKeys.removeAll(processedDecisionKeys.take(overflow).toList(growable: false));
    }
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': tradingLabSchemaVersion,
    'manifest': manifest.toJson(),
    'status': status.name,
    'balance': balance,
    'currentEquity': currentEquity,
    'peakEquity': peakEquity,
    'maximumDrawdownPercent': maximumDrawdownPercent,
    'pendingCandidates': pendingCandidates.map((item) => item.toJson()).toList(),
    'openPositions': openPositions.map((item) => item.toJson()).toList(),
    'closedPositions': closedPositions.map((item) => item.toJson()).toList(),
    'events': events.map((item) => item.toJson()).toList(),
    'processedDecisionKeys': processedDecisionKeys.toList()..sort(),
    'lastSnapshotAtUtc': lastSnapshotAtUtc?.toIso8601String(),
    'cycleId': cycleId,
    'lastWhyNoTrade': lastWhyNoTrade,
  };

  factory TradingLabRun.fromJson(Map<String, Object?> json) {
    final manifestJson = _objectMap(json['manifest']);
    return TradingLabRun(
      manifest: TradingLabRunManifest.fromJson(manifestJson),
      status: TradingLabRunStatus.values.firstWhere(
        (item) => item.name == json['status'],
        orElse: () => TradingLabRunStatus.stopped,
      ),
      balance: _double(json['balance']),
      currentEquity: _double(json['currentEquity']),
      peakEquity: _double(json['peakEquity']),
      maximumDrawdownPercent: _double(json['maximumDrawdownPercent']),
      pendingCandidates: _objectList(json['pendingCandidates']).map(TradingLabPendingCandidate.fromJson),
      openPositions: _objectList(json['openPositions']).map(TradingLabPosition.fromJson),
      closedPositions: _objectList(json['closedPositions']).map(TradingLabPosition.fromJson),
      events: _objectList(json['events']).map(TradingLabEvent.fromJson),
      processedDecisionKeys: _strings(json['processedDecisionKeys']),
      lastSnapshotAtUtc: _nullableDate(json['lastSnapshotAtUtc']),
      cycleId: _int(json['cycleId']),
      lastWhyNoTrade: json['lastWhyNoTrade']?.toString() ?? 'No diagnostic is available yet.',
    );
  }
}

Map<String, Object?> _objectMap(Object? value) {
  if (value is Map<Object?, Object?>) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return const {};
}

List<Map<String, Object?>> _objectList(Object? value) => (value as List<Object?>? ?? const [])
    .whereType<Map<Object?, Object?>>()
    .map((item) => item.map((key, value) => MapEntry(key.toString(), value)))
    .toList(growable: false);

List<String> _strings(Object? value) => (value as List<Object?>? ?? const []).map((item) => item.toString()).where((item) => item.trim().isNotEmpty).toList(growable: false);
List<double> _doubles(Object? value) => (value as List<Object?>? ?? const []).whereType<num>().map((item) => item.toDouble()).toList(growable: false);
Map<String, double> _doubleMap(Object? value) => _objectMap(value).map((key, item) => MapEntry(key, (item as num?)?.toDouble() ?? 0));
Map<String, String> _stringMap(Object? value) => _objectMap(value).map((key, item) => MapEntry(key, item?.toString() ?? ''));
int _int(Object? value, {int fallback = 0}) => (value as num?)?.toInt() ?? fallback;
double _double(Object? value, {double fallback = 0}) => (value as num?)?.toDouble() ?? fallback;
double? _nullableDouble(Object? value) => value is num ? value.toDouble() : null;
String? _nullableString(Object? value) {
  final result = value?.toString();
  return result == null || result.trim().isEmpty ? null : result;
}
DateTime _date(Object? value) => DateTime.tryParse(value?.toString() ?? '')?.toUtc() ?? (throw const FormatException('Invalid Trading Lab UTC timestamp.'));
DateTime? _nullableDate(Object? value) {
  final raw = value?.toString();
  if (raw == null || raw.isEmpty) return null;
  return DateTime.tryParse(raw)?.toUtc();
}
