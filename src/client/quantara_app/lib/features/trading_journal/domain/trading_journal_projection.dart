import 'dart:math' as math;

import 'trading_journal_models.dart';

final class TradingJournalProjection {
  const TradingJournalProjection({
    required this.journalTradeId,
    required this.symbol,
    required this.timeframe,
    required this.strategy,
    required this.direction,
    required this.source,
    required this.state,
    required this.timeline,
    required this.decidedAt,
    required this.integrity,
    this.plan,
    this.positionId,
    this.entryPrice,
    this.initialQuantity,
    this.remainingQuantity,
    this.highestTargetReached = 0,
    this.grossPnl,
    this.fees,
    this.funding,
    this.netPnl,
    this.realizedR,
    this.returnOnMarginPercent,
    this.returnOnEquityPercent,
    this.priceMovePercent,
    this.mfe,
    this.mae,
    this.maximumOpenProfit,
    this.maximumOpenLoss,
    this.holdingDuration,
    this.closeReason,
    this.closedAt,
    this.profitLockConfirmed = false,
    this.counterfactualOutcome,
    this.warning,
  });

  factory TradingJournalProjection.fixture({
    required String journalTradeId,
    required String symbol,
    required String timeframe,
    required String strategy,
    required TradingJournalDirection direction,
    required TradingJournalSource source,
    required TradingJournalTradeState state,
    required DateTime decidedAt,
    List<TradingJournalEvent> timeline = const [],
    double? netPnl,
    double? realizedR,
    TradingJournalCloseReason? closeReason,
    DateTime? closedAt,
    TradingJournalCounterfactualOutcome? counterfactualOutcome,
  }) => TradingJournalProjection(
    journalTradeId: journalTradeId,
    symbol: symbol,
    timeframe: timeframe,
    strategy: strategy,
    direction: direction,
    source: source,
    state: state,
    timeline: List.unmodifiable(timeline),
    decidedAt: decidedAt,
    integrity: TradingJournalIntegrity.verified,
    netPnl: netPnl,
    realizedR: realizedR,
    closeReason: closeReason,
    closedAt: closedAt,
    counterfactualOutcome: counterfactualOutcome,
  );

  final String journalTradeId;
  final String symbol;
  final String timeframe;
  final String strategy;
  final TradingJournalDirection direction;
  final TradingJournalSource source;
  final TradingJournalTradeState state;
  final List<TradingJournalEvent> timeline;
  final DateTime decidedAt;
  final TradingJournalIntegrity integrity;
  final TradingJournalPlan? plan;
  final String? positionId;

  bool get economicsPending =>
      state == TradingJournalTradeState.closed &&
      netPnl == null &&
      timeline.any(
        (event) =>
            event.type == TradingJournalEventType.positionClosed &&
            event.details['economicsPending'] == true,
      );
  final double? entryPrice;
  final double? initialQuantity;
  final double? remainingQuantity;
  final int highestTargetReached;
  final double? grossPnl;
  final double? fees;
  final double? funding;
  final double? netPnl;
  final double? realizedR;
  final double? returnOnMarginPercent;
  final double? returnOnEquityPercent;
  final double? priceMovePercent;
  final double? mfe;
  final double? mae;
  final double? maximumOpenProfit;
  final double? maximumOpenLoss;
  final Duration? holdingDuration;
  final TradingJournalCloseReason? closeReason;
  final DateTime? closedAt;
  final bool profitLockConfirmed;
  final TradingJournalCounterfactualOutcome? counterfactualOutcome;
  final String? warning;
}

abstract final class TradingJournalProjector {
  static TradingJournalProjection project({
    required TradingJournalLedger ledger,
    required String journalTradeId,
  }) {
    final plan = ledger.plans
        .where((item) => item.journalTradeId == journalTradeId)
        .firstOrNull;
    if (plan == null) {
      throw StateError('Missing journal plan $journalTradeId.');
    }

    final timeline =
        ledger.events
            .where((item) => item.journalTradeId == journalTradeId)
            .toList(growable: false)
          ..sort(_compareEvents);
    final confirmedEntries = timeline.where(
      (item) => item.type == TradingJournalEventType.entryFilled,
    );
    final partialEntries = timeline.where(
      (item) => item.type == TradingJournalEventType.entryPartiallyFilled,
    );
    final entry = confirmedEntries.isNotEmpty
        ? confirmedEntries.first
        : partialEntries.isEmpty
        ? null
        : partialEntries.first;
    final closed = timeline
        .where(
          (item) =>
              item.type == TradingJournalEventType.positionClosed ||
              item.type == TradingJournalEventType.liquidation,
        )
        .toList(growable: false);
    final authoritativeClosed = closed
        .where((item) => item.details['economicsPending'] != true)
        .toList(growable: false);
    final close = authoritativeClosed.isNotEmpty
        ? authoritativeClosed.last
        : closed.isEmpty
        ? null
        : closed.last;

    final grossValues = timeline
        .map((item) => item.grossPnl)
        .whereType<double>()
        .toList(growable: false);
    final feeValues = timeline
        .map((item) => item.fee)
        .whereType<double>()
        .map((item) => item.abs())
        .toList(growable: false);
    final fundingValues = timeline
        .map((item) => item.funding)
        .whereType<double>()
        .toList(growable: false);
    final hasPnl = grossValues.isNotEmpty;
    final gross = hasPnl ? grossValues.fold<double>(0, (a, b) => a + b) : null;
    final fees = feeValues.isNotEmpty
        ? feeValues.fold<double>(0, (a, b) => a + b)
        : null;
    final funding = fundingValues.isNotEmpty
        ? fundingValues.fold<double>(0, (a, b) => a + b)
        : null;
    final net = gross == null || fees == null || funding == null
        ? null
        : gross - fees + funding;

    var highestTarget = 0;
    for (final event in timeline) {
      if (event.type != TradingJournalEventType.takeProfitFilled) continue;
      final index = _integer(event.details['targetIndex']);
      if (index > highestTarget) highestTarget = index;
    }

    final unrealizedSamples = timeline
        .map((item) => _number(item.details['unrealizedPnl']))
        .whereType<double>()
        .toList(growable: false);
    final priceSamples = timeline
        .map((item) => _number(item.details['markPrice']) ?? item.price)
        .whereType<double>()
        .toList(growable: false);
    final entryPrice = entry?.price ?? plan.plannedEntry;
    final directionSign = plan.direction == TradingJournalDirection.short
        ? -1.0
        : 1.0;
    final priceMoves = priceSamples
        .where((price) => entryPrice > 0)
        .map((price) => (price - entryPrice) / entryPrice * 100 * directionSign)
        .toList(growable: false);
    final closePrice = close?.price;
    final priceMove = closePrice == null || entryPrice <= 0
        ? null
        : (closePrice - entryPrice) / entryPrice * 100 * directionSign;

    final counterfactualEvent = timeline
        .where(
          (item) => item.type == TradingJournalEventType.counterfactualResolved,
        )
        .lastOrNull;
    final counterfactual = counterfactualEvent == null
        ? null
        : TradingJournalCounterfactualOutcome.fromJson(
            counterfactualEvent.details,
          );

    final state = _state(
      ledger: ledger,
      plan: plan,
      timeline: timeline,
      hasEntry: entry != null,
      hasClose: close != null,
      counterfactual: counterfactual,
    );
    final initialQuantity = entry?.quantity;
    final remaining = timeline
        .map((item) => item.remainingQuantity)
        .whereType<double>()
        .lastOrNull;
    final positionId =
        timeline
            .map((item) => item.positionId)
            .whereType<String>()
            .where((item) => item.trim().isNotEmpty)
            .lastOrNull ??
        plan.positionId;
    final realizedR = net == null || plan.riskBudget <= 0
        ? null
        : net / plan.riskBudget;
    final margin = plan.expectedMargin;
    final returnOnMargin = net == null || margin <= 0
        ? null
        : net / margin * 100;
    final returnOnEquity = net == null || plan.accountEquity <= 0
        ? null
        : net / plan.accountEquity * 100;
    final entryAt = entry?.occurredAt;
    final closedAt = close?.occurredAt;
    final duration = entryAt == null || closedAt == null
        ? null
        : closedAt.difference(entryAt);
    final integrity =
        ledger.integrity == TradingJournalIntegrity.unverified ||
            timeline.any(
              (item) => item.quality == TradingJournalFactQuality.unverified,
            )
        ? TradingJournalIntegrity.unverified
        : ledger.integrity;

    return TradingJournalProjection(
      journalTradeId: journalTradeId,
      symbol: plan.symbol,
      timeframe: plan.timeframe,
      strategy: plan.strategy,
      direction: plan.direction,
      source: plan.source,
      state: state,
      timeline: List.unmodifiable(timeline),
      decidedAt: plan.decidedAt,
      integrity: integrity,
      plan: plan,
      positionId: positionId,
      entryPrice: entryPrice,
      initialQuantity: initialQuantity,
      remainingQuantity: close != null ? 0 : remaining,
      highestTargetReached: highestTarget,
      grossPnl: gross,
      fees: fees,
      funding: funding,
      netPnl: net,
      realizedR: realizedR,
      returnOnMarginPercent: returnOnMargin,
      returnOnEquityPercent: returnOnEquity,
      priceMovePercent: priceMove,
      mfe: priceMoves.isEmpty ? null : priceMoves.reduce(math.max),
      mae: priceMoves.isEmpty ? null : priceMoves.reduce(math.min),
      maximumOpenProfit: unrealizedSamples.isEmpty
          ? null
          : unrealizedSamples.reduce(math.max),
      maximumOpenLoss: unrealizedSamples.isEmpty
          ? null
          : unrealizedSamples.reduce(math.min),
      holdingDuration: duration,
      closeReason: _closeReason(close),
      closedAt: closedAt,
      profitLockConfirmed: timeline.any(
        (item) => item.type == TradingJournalEventType.stopMoveConfirmed,
      ),
      counterfactualOutcome: counterfactual,
      warning: ledger.warnings.isEmpty ? null : ledger.warnings.join(' '),
    );
  }

  static List<TradingJournalProjection> projectAll(
    TradingJournalLedger ledger,
  ) {
    final projections =
        ledger.plans
            .map(
              (plan) =>
                  project(ledger: ledger, journalTradeId: plan.journalTradeId),
            )
            .toList(growable: false)
          ..sort((left, right) => right.decidedAt.compareTo(left.decidedAt));
    return List.unmodifiable(projections);
  }

  static int _compareEvents(
    TradingJournalEvent left,
    TradingJournalEvent right,
  ) {
    final byTime = left.occurredAt.compareTo(right.occurredAt);
    if (byTime != 0) return byTime;
    final byRecorded = left.recordedAt.compareTo(right.recordedAt);
    if (byRecorded != 0) return byRecorded;
    return left.eventId.compareTo(right.eventId);
  }

  static TradingJournalTradeState _state({
    required TradingJournalLedger ledger,
    required TradingJournalPlan plan,
    required List<TradingJournalEvent> timeline,
    required bool hasEntry,
    required bool hasClose,
    required TradingJournalCounterfactualOutcome? counterfactual,
  }) {
    if (timeline.any(
      (item) => item.quality == TradingJournalFactQuality.unverified,
    )) {
      return TradingJournalTradeState.unverified;
    }
    if (hasClose) return TradingJournalTradeState.closed;
    if (hasEntry) return TradingJournalTradeState.open;
    if (ledger.integrity == TradingJournalIntegrity.unverified) {
      return TradingJournalTradeState.unverified;
    }
    if (plan.source == TradingJournalSource.paper) {
      return TradingJournalTradeState.simulated;
    }
    if (counterfactual != null ||
        timeline.any(
          (item) => item.type == TradingJournalEventType.signalExpired,
        )) {
      return TradingJournalTradeState.missed;
    }
    return TradingJournalTradeState.planned;
  }

  static TradingJournalCloseReason? _closeReason(TradingJournalEvent? close) {
    if (close == null) return null;
    if (close.type == TradingJournalEventType.liquidation) {
      return TradingJournalCloseReason.liquidation;
    }
    final raw = close.details['closeReason']?.toString();
    for (final value in TradingJournalCloseReason.values) {
      if (value.name == raw) return value;
    }
    return TradingJournalCloseReason.unknown;
  }

  static int _integer(Object? value) =>
      value is num ? value.toInt() : int.tryParse(value?.toString() ?? '') ?? 0;

  static double? _number(Object? value) {
    final parsed = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '');
    return parsed != null && parsed.isFinite ? parsed : null;
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }

  T? get lastOrNull {
    final iterator = this.iterator;
    T? result;
    var found = false;
    while (iterator.moveNext()) {
      result = iterator.current;
      found = true;
    }
    return found ? result : null;
  }
}
