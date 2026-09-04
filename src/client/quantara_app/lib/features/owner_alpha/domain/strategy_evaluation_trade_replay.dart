enum StrategyEvaluationReplayEventType {
  signalDetected,
  plannedEntryLower,
  plannedEntryUpper,
  actualFill,
  initialStop,
  takeProfit1,
  takeProfit2,
  takeProfit3,
  partialExit,
  finalClose,
}

final class StrategyEvaluationReplayEvent {
  const StrategyEvaluationReplayEvent({
    required this.type,
    required this.timestampUtc,
    required this.price,
    this.quantity,
    this.reasonCode,
  });

  final StrategyEvaluationReplayEventType type;
  final DateTime timestampUtc;
  final double price;
  final double? quantity;
  final String? reasonCode;

  void validate() {
    if (!price.isFinite || price <= 0) {
      throw ArgumentError.value(price, 'price');
    }
    if (quantity != null && (!quantity!.isFinite || quantity! <= 0)) {
      throw ArgumentError.value(quantity, 'quantity');
    }
    if (reasonCode != null && reasonCode!.trim().isEmpty) {
      throw ArgumentError.value(reasonCode, 'reasonCode');
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'type': type.name,
    'timestampUtc': timestampUtc.toUtc().toIso8601String(),
    'price': price,
    if (quantity != null) 'quantity': quantity,
    if (reasonCode != null) 'reasonCode': reasonCode,
  };
}

/// Compact immutable facts needed to render one historical trade. Candles are
/// deliberately not persisted here; they are fetched/cached lazily by the UI.
final class StrategyEvaluationTradeReplay {
  StrategyEvaluationTradeReplay({
    required this.evaluationRunId,
    required this.tradeId,
    required this.strategyId,
    required this.strategyVersion,
    required this.snapshotHash,
    required this.symbol,
    required this.timeframe,
    required Iterable<StrategyEvaluationReplayEvent> events,
  }) : events = List<StrategyEvaluationReplayEvent>.unmodifiable(
         events.toList()..sort((a, b) => a.timestampUtc.compareTo(b.timestampUtc)),
       ) {
    _requireText(evaluationRunId, 'evaluationRunId');
    _requireText(tradeId, 'tradeId');
    _requireText(strategyId, 'strategyId');
    _requireText(strategyVersion, 'strategyVersion');
    _requireText(snapshotHash, 'snapshotHash');
    _requireText(symbol, 'symbol');
    _requireText(timeframe, 'timeframe');
    if (this.events.isEmpty) throw ArgumentError('events must not be empty');
    for (final event in this.events) {
      event.validate();
    }
  }

  final String evaluationRunId;
  final String tradeId;
  final String strategyId;
  final String strategyVersion;
  final String snapshotHash;
  final String symbol;
  final String timeframe;
  final List<StrategyEvaluationReplayEvent> events;

  bool get grantsLocalLiveAuthority => false;

  DateTime get firstEventUtc => events.first.timestampUtc;
  DateTime get lastEventUtc => events.last.timestampUtc;

  List<StrategyEvaluationReplayEvent> visibleEvents({
    required bool revealOutcome,
  }) {
    if (revealOutcome) return events;
    final entryIndex = events.indexWhere(
      (event) => event.type == StrategyEvaluationReplayEventType.actualFill,
    );
    if (entryIndex < 0) {
      return List<StrategyEvaluationReplayEvent>.unmodifiable(
        events.where(
          (event) =>
              event.type == StrategyEvaluationReplayEventType.signalDetected ||
              event.type ==
                  StrategyEvaluationReplayEventType.plannedEntryLower ||
              event.type ==
                  StrategyEvaluationReplayEventType.plannedEntryUpper ||
              event.type == StrategyEvaluationReplayEventType.initialStop ||
              event.type == StrategyEvaluationReplayEventType.takeProfit1 ||
              event.type == StrategyEvaluationReplayEventType.takeProfit2 ||
              event.type == StrategyEvaluationReplayEventType.takeProfit3,
        ),
      );
    }
    final cutoff = events[entryIndex].timestampUtc;
    return List<StrategyEvaluationReplayEvent>.unmodifiable(
      events.where((event) => !event.timestampUtc.isAfter(cutoff)),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'evaluationRunId': evaluationRunId,
    'tradeId': tradeId,
    'strategyId': strategyId,
    'strategyVersion': strategyVersion,
    'snapshotHash': snapshotHash,
    'symbol': symbol,
    'timeframe': timeframe,
    'events': events.map((event) => event.toJson()).toList(growable: false),
    'grantsLocalLiveAuthority': false,
  };
}

final class StrategyEvaluationReplayCandleCoverage {
  const StrategyEvaluationReplayCandleCoverage._({
    required this.succeeded,
    required this.requestedStartUtc,
    required this.requestedEndUtc,
    this.coveredStartUtc,
    this.coveredEndUtc,
    this.failureReason,
  });

  factory StrategyEvaluationReplayCandleCoverage.success({
    required DateTime requestedStartUtc,
    required DateTime requestedEndUtc,
    required DateTime coveredStartUtc,
    required DateTime coveredEndUtc,
  }) => StrategyEvaluationReplayCandleCoverage._(
    succeeded: true,
    requestedStartUtc: requestedStartUtc,
    requestedEndUtc: requestedEndUtc,
    coveredStartUtc: coveredStartUtc,
    coveredEndUtc: coveredEndUtc,
  );

  factory StrategyEvaluationReplayCandleCoverage.failure({
    required DateTime requestedStartUtc,
    required DateTime requestedEndUtc,
    required String reason,
  }) {
    _requireText(reason, 'reason');
    return StrategyEvaluationReplayCandleCoverage._(
      succeeded: false,
      requestedStartUtc: requestedStartUtc,
      requestedEndUtc: requestedEndUtc,
      failureReason: reason,
    );
  }

  final bool succeeded;
  final DateTime requestedStartUtc;
  final DateTime requestedEndUtc;
  final DateTime? coveredStartUtc;
  final DateTime? coveredEndUtc;
  final String? failureReason;

  bool get fullyCovered =>
      succeeded &&
      coveredStartUtc != null &&
      coveredEndUtc != null &&
      !coveredStartUtc!.isAfter(requestedStartUtc) &&
      !coveredEndUtc!.isBefore(requestedEndUtc);
}

void _requireText(String value, String name) {
  if (value.trim().isEmpty) throw ArgumentError.value(value, name);
}
