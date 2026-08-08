enum TradingJournalDirection { long, short, wait }

enum TradingJournalSource {
  signalOnly,
  userMarkedTaken,
  localLive,
  paper,
  importedExchange,
  manual,
}

enum TradingJournalFactSource { exchange, quantara, user, imported }

enum TradingJournalFactQuality {
  confirmed,
  calculated,
  userEntered,
  stale,
  unverified,
}

enum TradingJournalScope { signal, position, account, session, journal }

enum TradingJournalIntegrity { verified, recovered, unverified }

enum TradingJournalEventType {
  signalCreated,
  signalUpdated,
  signalExpired,
  entrySubmitted,
  entryPartiallyFilled,
  entryFilled,
  entryCancelled,
  entryRejected,
  stopSubmitted,
  stopConfirmed,
  stopRejected,
  takeProfitSubmitted,
  takeProfitConfirmed,
  takeProfitFilled,
  stopMoveRequested,
  stopMoveConfirmed,
  stopMoveRejected,
  serviceStopped,
  staleDetected,
  reconciliationStarted,
  reconciliationRecovered,
  appRestarted,
  fundingApplied,
  positionPartiallyClosed,
  positionClosed,
  liquidation,
  manualNote,
  counterfactualResolved,
}

enum TradingJournalTradeState {
  planned,
  open,
  closed,
  missed,
  simulated,
  unverified,
}

enum TradingJournalCloseReason {
  takeProfit1,
  takeProfit2,
  takeProfit3,
  stop,
  breakEven,
  runner,
  emergency,
  manual,
  exchange,
  liquidation,
  expired,
  notTaken,
  unknown,
}

enum TradingJournalCounterfactualClassification {
  wouldWin,
  wouldLose,
  breakEven,
  unresolved,
}

final class TradingJournalPlan {
  const TradingJournalPlan({
    required this.journalTradeId,
    required this.setupId,
    required this.analysisVersion,
    required this.symbol,
    required this.market,
    required this.timeframe,
    required this.direction,
    required this.strategy,
    required this.cadence,
    required this.source,
    required this.decidedAt,
    required this.decisionPrice,
    required this.entryLower,
    required this.entryUpper,
    required this.plannedEntry,
    required this.originalStopLoss,
    required this.targets,
    required this.expectedRMultiples,
    required this.confidencePercent,
    required this.confluence,
    required this.regime,
    required this.rationale,
    required this.invalidation,
    required this.accountEquity,
    required this.riskPercent,
    required this.riskBudget,
    required this.leverage,
    required this.expectedMargin,
    required this.passedGates,
    required this.blockedGates,
    required this.appVersion,
    required this.strategyRulesVersion,
    this.positionId,
    this.entryOrderId,
    this.clientId,
    this.notes,
  });

  final String journalTradeId;
  final String setupId;
  final String analysisVersion;
  final String symbol;
  final String market;
  final String timeframe;
  final TradingJournalDirection direction;
  final String strategy;
  final String cadence;
  final TradingJournalSource source;
  final DateTime decidedAt;
  final double decisionPrice;
  final double entryLower;
  final double entryUpper;
  final double plannedEntry;
  final double originalStopLoss;
  final List<double> targets;
  final List<double> expectedRMultiples;
  final double confidencePercent;
  final List<String> confluence;
  final String regime;
  final String rationale;
  final String invalidation;
  final double accountEquity;
  final double riskPercent;
  final double riskBudget;
  final int leverage;
  final double expectedMargin;
  final List<String> passedGates;
  final List<String> blockedGates;
  final String appVersion;
  final String strategyRulesVersion;
  final String? positionId;
  final String? entryOrderId;
  final String? clientId;
  final String? notes;

  Map<String, Object?> toJson() => {
    'journalTradeId': journalTradeId,
    'setupId': setupId,
    'analysisVersion': analysisVersion,
    'symbol': symbol,
    'market': market,
    'timeframe': timeframe,
    'direction': direction.name,
    'strategy': strategy,
    'cadence': cadence,
    'source': source.name,
    'decidedAt': decidedAt.toUtc().toIso8601String(),
    'decisionPrice': decisionPrice,
    'entryLower': entryLower,
    'entryUpper': entryUpper,
    'plannedEntry': plannedEntry,
    'originalStopLoss': originalStopLoss,
    'targets': targets,
    'expectedRMultiples': expectedRMultiples,
    'confidencePercent': confidencePercent,
    'confluence': confluence,
    'regime': regime,
    'rationale': rationale,
    'invalidation': invalidation,
    'accountEquity': accountEquity,
    'riskPercent': riskPercent,
    'riskBudget': riskBudget,
    'leverage': leverage,
    'expectedMargin': expectedMargin,
    'passedGates': passedGates,
    'blockedGates': blockedGates,
    'appVersion': appVersion,
    'strategyRulesVersion': strategyRulesVersion,
    'positionId': positionId,
    'entryOrderId': entryOrderId,
    'clientId': clientId,
    'notes': notes,
  };

  factory TradingJournalPlan.fromJson(Map<String, Object?> json) =>
      TradingJournalPlan(
        journalTradeId: _string(json['journalTradeId']),
        setupId: _string(json['setupId']),
        analysisVersion: _string(json['analysisVersion']),
        symbol: _string(json['symbol']),
        market: _string(json['market']),
        timeframe: _string(json['timeframe']),
        direction: _enumValue(
          TradingJournalDirection.values,
          json['direction'],
          TradingJournalDirection.wait,
        ),
        strategy: _string(json['strategy']),
        cadence: _string(json['cadence']),
        source: _enumValue(
          TradingJournalSource.values,
          json['source'],
          TradingJournalSource.manual,
        ),
        decidedAt: _date(json['decidedAt']),
        decisionPrice: _double(json['decisionPrice']),
        entryLower: _double(json['entryLower']),
        entryUpper: _double(json['entryUpper']),
        plannedEntry: _double(json['plannedEntry']),
        originalStopLoss: _double(json['originalStopLoss']),
        targets: List.unmodifiable(_doubleList(json['targets'])),
        expectedRMultiples: List.unmodifiable(
          _doubleList(json['expectedRMultiples']),
        ),
        confidencePercent: _double(json['confidencePercent']),
        confluence: List.unmodifiable(_stringList(json['confluence'])),
        regime: _string(json['regime']),
        rationale: _string(json['rationale']),
        invalidation: _string(json['invalidation']),
        accountEquity: _double(json['accountEquity']),
        riskPercent: _double(json['riskPercent']),
        riskBudget: _double(json['riskBudget']),
        leverage: _int(json['leverage']),
        expectedMargin: _double(json['expectedMargin']),
        passedGates: List.unmodifiable(_stringList(json['passedGates'])),
        blockedGates: List.unmodifiable(_stringList(json['blockedGates'])),
        appVersion: _string(json['appVersion']),
        strategyRulesVersion: _string(json['strategyRulesVersion']),
        positionId: _nullableString(json['positionId']),
        entryOrderId: _nullableString(json['entryOrderId']),
        clientId: _nullableString(json['clientId']),
        notes: _nullableString(json['notes']),
      );
}

final class TradingJournalEvent {
  const TradingJournalEvent({
    required this.eventId,
    required this.journalTradeId,
    required this.type,
    required this.occurredAt,
    required this.recordedAt,
    required this.source,
    required this.quality,
    required this.scope,
    required this.currency,
    required this.asOf,
    this.exchangeEventId,
    this.positionId,
    this.orderId,
    this.clientId,
    this.tradeId,
    this.quantity,
    this.price,
    this.grossPnl,
    this.fee,
    this.funding,
    this.remainingQuantity,
    this.details = const {},
  });

  final String eventId;
  final String journalTradeId;
  final TradingJournalEventType type;
  final DateTime occurredAt;
  final DateTime recordedAt;
  final TradingJournalFactSource source;
  final TradingJournalFactQuality quality;
  final TradingJournalScope scope;
  final String currency;
  final DateTime asOf;
  final String? exchangeEventId;
  final String? positionId;
  final String? orderId;
  final String? clientId;
  final String? tradeId;
  final double? quantity;
  final double? price;
  final double? grossPnl;
  final double? fee;
  final double? funding;
  final double? remainingQuantity;
  final Map<String, Object?> details;

  String get economicIdentity {
    final exchange = exchangeEventId?.trim();
    if (exchange != null && exchange.isNotEmpty) return 'exchange:$exchange';
    final trade = tradeId?.trim();
    if (trade != null && trade.isNotEmpty) return 'trade:$trade';
    return 'event:$eventId';
  }

  bool sameEconomicEvent(TradingJournalEvent other) {
    final replayableProtectionConfirmation =
        type == other.type &&
        (type == TradingJournalEventType.stopConfirmed ||
            type == TradingJournalEventType.takeProfitConfirmed);
    final replayableExchangeClosureObservation =
        type == TradingJournalEventType.positionClosed &&
        other.type == TradingJournalEventType.positionClosed &&
        exchangeEventId != null &&
        exchangeEventId!.startsWith('exchange-close-observed:') &&
        exchangeEventId == other.exchangeEventId &&
        journalTradeId == other.journalTradeId &&
        source == other.source &&
        quality == other.quality &&
        scope == other.scope &&
        currency == other.currency &&
        positionId == other.positionId &&
        remainingQuantity == 0 &&
        other.remainingQuantity == 0 &&
        details['economicsPending'] == true &&
        other.details['economicsPending'] == true;
    if (replayableExchangeClosureObservation) return true;
    return journalTradeId == other.journalTradeId &&
        type == other.type &&
        (replayableProtectionConfirmation ||
            occurredAt.toUtc() == other.occurredAt.toUtc()) &&
        source == other.source &&
        quality == other.quality &&
        scope == other.scope &&
        currency == other.currency &&
        exchangeEventId == other.exchangeEventId &&
        positionId == other.positionId &&
        orderId == other.orderId &&
        clientId == other.clientId &&
        tradeId == other.tradeId &&
        quantity == other.quantity &&
        price == other.price &&
        grossPnl == other.grossPnl &&
        fee == other.fee &&
        funding == other.funding &&
        remainingQuantity == other.remainingQuantity &&
        _deepEquals(details, other.details);
  }

  TradingJournalEvent copyWith({String? eventId}) => TradingJournalEvent(
    eventId: eventId ?? this.eventId,
    journalTradeId: journalTradeId,
    type: type,
    occurredAt: occurredAt,
    recordedAt: recordedAt,
    source: source,
    quality: quality,
    scope: scope,
    currency: currency,
    asOf: asOf,
    exchangeEventId: exchangeEventId,
    positionId: positionId,
    orderId: orderId,
    clientId: clientId,
    tradeId: tradeId,
    quantity: quantity,
    price: price,
    grossPnl: grossPnl,
    fee: fee,
    funding: funding,
    remainingQuantity: remainingQuantity,
    details: details,
  );

  Map<String, Object?> toJson() => {
    'eventId': eventId,
    'journalTradeId': journalTradeId,
    'type': type.name,
    'occurredAt': occurredAt.toUtc().toIso8601String(),
    'recordedAt': recordedAt.toUtc().toIso8601String(),
    'source': source.name,
    'quality': quality.name,
    'scope': scope.name,
    'currency': currency,
    'asOf': asOf.toUtc().toIso8601String(),
    'exchangeEventId': exchangeEventId,
    'positionId': positionId,
    'orderId': orderId,
    'clientId': clientId,
    'tradeId': tradeId,
    'quantity': quantity,
    'price': price,
    'grossPnl': grossPnl,
    'fee': fee,
    'funding': funding,
    'remainingQuantity': remainingQuantity,
    'details': details,
  };

  factory TradingJournalEvent.fromJson(Map<String, Object?> json) =>
      TradingJournalEvent(
        eventId: _string(json['eventId']),
        journalTradeId: _string(json['journalTradeId']),
        type: _enumValue(
          TradingJournalEventType.values,
          json['type'],
          TradingJournalEventType.manualNote,
        ),
        occurredAt: _date(json['occurredAt']),
        recordedAt: _date(json['recordedAt']),
        source: _enumValue(
          TradingJournalFactSource.values,
          json['source'],
          TradingJournalFactSource.imported,
        ),
        quality: _enumValue(
          TradingJournalFactQuality.values,
          json['quality'],
          TradingJournalFactQuality.unverified,
        ),
        scope: _enumValue(
          TradingJournalScope.values,
          json['scope'],
          TradingJournalScope.journal,
        ),
        currency: _string(json['currency'], fallback: 'USDT'),
        asOf: _date(json['asOf']),
        exchangeEventId: _nullableString(json['exchangeEventId']),
        positionId: _nullableString(json['positionId']),
        orderId: _nullableString(json['orderId']),
        clientId: _nullableString(json['clientId']),
        tradeId: _nullableString(json['tradeId']),
        quantity: _nullableDouble(json['quantity']),
        price: _nullableDouble(json['price']),
        grossPnl: _nullableDouble(json['grossPnl']),
        fee: _nullableDouble(json['fee']),
        funding: _nullableDouble(json['funding']),
        remainingQuantity: _nullableDouble(json['remainingQuantity']),
        details: _objectMap(json['details']),
      );
}

final class TradingJournalLedger {
  const TradingJournalLedger._({
    required this.schemaVersion,
    required this.generation,
    required this.plans,
    required this.events,
    required this.integrity,
    required this.warnings,
  });

  factory TradingJournalLedger.empty() => const TradingJournalLedger._(
    schemaVersion: 1,
    generation: 0,
    plans: [],
    events: [],
    integrity: TradingJournalIntegrity.verified,
    warnings: [],
  );

  final int schemaVersion;
  final int generation;
  final List<TradingJournalPlan> plans;
  final List<TradingJournalEvent> events;
  final TradingJournalIntegrity integrity;
  final List<String> warnings;

  TradingJournalLedger appendPlan(TradingJournalPlan plan) {
    final existing = plans.where(
      (item) => item.journalTradeId == plan.journalTradeId,
    );
    if (existing.isEmpty) {
      return _copy(generation: generation + 1, plans: [...plans, plan]);
    }
    if (_deepEquals(existing.first.toJson(), plan.toJson())) return this;
    return _copy(
      integrity: TradingJournalIntegrity.unverified,
      warnings: [
        ...warnings,
        'Conflicting immutable plan for ${plan.journalTradeId}.',
      ],
    );
  }

  TradingJournalLedger appendEvent(TradingJournalEvent event) {
    final identity = event.economicIdentity;
    final existing = events.where(
      (item) =>
          item.journalTradeId == event.journalTradeId &&
          item.economicIdentity == identity,
    );
    if (existing.isEmpty) {
      return _copy(generation: generation + 1, events: [...events, event]);
    }
    if (existing.first.sameEconomicEvent(event)) return this;
    return _copy(
      integrity: TradingJournalIntegrity.unverified,
      warnings: [...warnings, 'Conflicting journal event identity $identity.'],
    );
  }

  TradingJournalLedger repairKnownProtectionReplayConflicts() {
    if (warnings.isEmpty) return this;
    final remainingWarnings = <String>[];
    var repaired = false;
    const prefix = 'Conflicting journal event identity ';
    for (final warning in warnings) {
      if (!warning.startsWith(prefix)) {
        remainingWarnings.add(warning);
        continue;
      }
      var identity = warning.substring(prefix.length).trim();
      if (identity.endsWith('.')) {
        identity = identity.substring(0, identity.length - 1);
      }
      final protectionIdentity =
          identity.startsWith('exchange:tp-order:') ||
          identity.startsWith('exchange:stop-order:');
      final matching = events.where(
        (event) =>
            event.economicIdentity == identity &&
            (event.type == TradingJournalEventType.takeProfitConfirmed ||
                event.type == TradingJournalEventType.stopConfirmed),
      );
      if (protectionIdentity && matching.length == 1) {
        repaired = true;
      } else {
        remainingWarnings.add(warning);
      }
    }
    if (!repaired) return this;
    return _copy(
      generation: generation + 1,
      integrity: remainingWarnings.isEmpty
          ? TradingJournalIntegrity.verified
          : TradingJournalIntegrity.unverified,
      warnings: remainingWarnings,
    );
  }

  TradingJournalLedger withRecoveryWarning(String warning) => _copy(
    integrity: integrity == TradingJournalIntegrity.unverified
        ? integrity
        : TradingJournalIntegrity.recovered,
    warnings: [...warnings, warning],
  );

  TradingJournalLedger withIntegrityWarning(String warning) => _copy(
    integrity: TradingJournalIntegrity.unverified,
    warnings: [...warnings, warning],
  );

  TradingJournalLedger withGeneration(int next) => _copy(generation: next);

  TradingJournalLedger _copy({
    int? generation,
    List<TradingJournalPlan>? plans,
    List<TradingJournalEvent>? events,
    TradingJournalIntegrity? integrity,
    List<String>? warnings,
  }) => TradingJournalLedger._(
    schemaVersion: schemaVersion,
    generation: generation ?? this.generation,
    plans: List.unmodifiable(plans ?? this.plans),
    events: List.unmodifiable(events ?? this.events),
    integrity: integrity ?? this.integrity,
    warnings: List.unmodifiable(warnings ?? this.warnings),
  );

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'generation': generation,
    'plans': plans.map((item) => item.toJson()).toList(growable: false),
    'events': events.map((item) => item.toJson()).toList(growable: false),
    'integrity': integrity.name,
    'warnings': warnings,
  };

  factory TradingJournalLedger.fromJson(Map<String, Object?> json) {
    final ledger = TradingJournalLedger._(
      schemaVersion: _int(json['schemaVersion'], fallback: 1),
      generation: _int(json['generation']),
      plans: List.unmodifiable(
        _mapList(json['plans']).map(TradingJournalPlan.fromJson),
      ),
      events: List.unmodifiable(
        _mapList(json['events']).map(TradingJournalEvent.fromJson),
      ),
      integrity: _enumValue(
        TradingJournalIntegrity.values,
        json['integrity'],
        TradingJournalIntegrity.unverified,
      ),
      warnings: List.unmodifiable(_stringList(json['warnings'])),
    );
    return ledger.repairKnownProtectionReplayConflicts();
  }
}

final class TradingJournalCounterfactualOutcome {
  const TradingJournalCounterfactualOutcome({
    required this.classification,
    required this.highestTargetReached,
    required this.priceMovePercent,
    required this.realizedR,
  });

  final TradingJournalCounterfactualClassification classification;
  final int highestTargetReached;
  final double priceMovePercent;
  final double realizedR;

  Map<String, Object?> toJson() => {
    'classification': classification.name,
    'highestTargetReached': highestTargetReached,
    'priceMovePercent': priceMovePercent,
    'realizedR': realizedR,
  };

  factory TradingJournalCounterfactualOutcome.fromJson(
    Map<String, Object?> json,
  ) => TradingJournalCounterfactualOutcome(
    classification: _enumValue(
      TradingJournalCounterfactualClassification.values,
      json['classification'],
      TradingJournalCounterfactualClassification.unresolved,
    ),
    highestTargetReached: _int(json['highestTargetReached']),
    priceMovePercent: _double(json['priceMovePercent']),
    realizedR: _double(json['realizedR']),
  );
}

T _enumValue<T extends Enum>(List<T> values, Object? raw, T fallback) {
  final name = raw?.toString();
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}

String _string(Object? value, {String fallback = ''}) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

String? _nullableString(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

double _double(Object? value, {double fallback = 0}) =>
    _nullableDouble(value) ?? fallback;

double? _nullableDouble(Object? value) {
  final parsed = value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');
  return parsed != null && parsed.isFinite ? parsed : null;
}

int _int(Object? value, {int fallback = 0}) => value is num
    ? value.toInt()
    : int.tryParse(value?.toString() ?? '') ?? fallback;

DateTime _date(Object? value) =>
    DateTime.tryParse(value?.toString() ?? '')?.toUtc() ??
    DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

List<double> _doubleList(Object? value) => value is List<Object?>
    ? value.map(_nullableDouble).whereType<double>().toList(growable: false)
    : const [];

List<String> _stringList(Object? value) => value is List<Object?>
    ? value.map((item) => item.toString()).toList(growable: false)
    : const [];

Map<String, Object?> _objectMap(Object? value) {
  if (value is Map<String, Object?>) return Map.unmodifiable(value);
  if (value is Map<Object?, Object?>) {
    return Map.unmodifiable(
      value.map((key, item) => MapEntry(key.toString(), item)),
    );
  }
  return const {};
}

List<Map<String, Object?>> _mapList(Object? value) {
  if (value is! List<Object?>) return const [];
  return value
      .whereType<Map<Object?, Object?>>()
      .map(
        (item) =>
            item.map((key, itemValue) => MapEntry(key.toString(), itemValue)),
      )
      .toList(growable: false);
}

bool _deepEquals(Object? left, Object? right) {
  if (identical(left, right)) return true;
  if (left is num && right is num) return left.toDouble() == right.toDouble();
  if (left is List && right is List) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (!_deepEquals(left[index], right[index])) return false;
    }
    return true;
  }
  if (left is Map && right is Map) {
    if (left.length != right.length) return false;
    for (final key in left.keys) {
      if (!right.containsKey(key) || !_deepEquals(left[key], right[key])) {
        return false;
      }
    }
    return true;
  }
  return left == right;
}
