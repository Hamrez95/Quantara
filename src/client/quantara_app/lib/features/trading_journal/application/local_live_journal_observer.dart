import 'dart:math' as math;

import '../../auto_trade/domain/auto_trade_models.dart';
import '../../auto_trade/domain/local_live_trade_models.dart';
import '../../auto_trade/domain/trading_pnl_projection.dart';
import '../../owner_alpha/domain/owner_alpha_models.dart';
import '../data/trading_journal_store.dart';
import '../domain/trading_journal_models.dart';

final class LocalLiveJournalObserver {
  LocalLiveJournalObserver({TradingJournalStore? store})
    : _store = store ?? SharedPreferencesTradingJournalStore();

  final TradingJournalStore _store;

  static String journalTradeId(String positionId) =>
      'local-live:${positionId.trim()}';

  Future<void> recordProtectedPosition({
    required TradeIdea idea,
    required LocalLiveManagedPosition managed,
    required AutoTradeAccountSnapshot account,
    required double riskPercent,
  }) async {
    final id = journalTradeId(managed.positionId);
    final riskPerUnit = (managed.entryPrice - managed.originalStopLoss).abs();
    final expectedR = managed.targets
        .map(
          (target) => riskPerUnit <= 0
              ? 0.0
              : (target - managed.entryPrice).abs() / riskPerUnit,
        )
        .toList(growable: false);
    final plan = TradingJournalPlan(
      journalTradeId: id,
      setupId: managed.setupId,
      analysisVersion: idea.strategyVersion,
      symbol: managed.symbol,
      market: 'USDT_PERPETUAL',
      timeframe: managed.timeframe,
      direction: _direction(managed.direction),
      strategy: idea.strategy.name,
      cadence: 'local-live',
      source: TradingJournalSource.localLive,
      decidedAt: idea.createdAt.toUtc(),
      decisionPrice: managed.entryPrice,
      entryLower: idea.entryLower ?? managed.entryPrice,
      entryUpper: idea.entryUpper ?? managed.entryPrice,
      plannedEntry: managed.entryPrice,
      originalStopLoss: managed.originalStopLoss,
      targets: List.unmodifiable(managed.targets),
      expectedRMultiples: List.unmodifiable(expectedR),
      confidencePercent: idea.confidencePercent.toDouble(),
      confluence: List.unmodifiable(idea.reasons),
      regime: idea.marketRegime.name,
      rationale: idea.summary,
      invalidation: idea.invalidation,
      accountEquity: account.estimatedEquity,
      riskPercent: riskPercent,
      riskBudget: account.estimatedEquity * riskPercent / 100,
      leverage: managed.leverage,
      expectedMargin:
          managed.initialQuantity * managed.entryPrice / managed.leverage,
      passedGates: const [
        'isolated-margin',
        'fresh-account-projection',
        'confirmed-entry-fill',
        'confirmed-full-stop',
        'confirmed-three-target-ladder',
      ],
      blockedGates: const [],
      appVersion: '1.2.0-rc.2+121',
      strategyRulesVersion: idea.strategyVersion,
      positionId: managed.positionId,
      entryOrderId: managed.entryOrderId,
      clientId: managed.clientId,
    );
    if (!await _appendPlan(plan)) return;

    final now = DateTime.now().toUtc();
    await _append(
      TradingJournalEvent(
        eventId: 'signal:${managed.setupId}',
        journalTradeId: id,
        type: TradingJournalEventType.signalCreated,
        occurredAt: idea.createdAt.toUtc(),
        recordedAt: now,
        source: TradingJournalFactSource.quantara,
        quality: TradingJournalFactQuality.calculated,
        scope: TradingJournalScope.signal,
        currency: account.marginCoin,
        asOf: idea.createdAt.toUtc(),
        exchangeEventId: null,
        positionId: managed.positionId,
        details: {
          'confidencePercent': idea.confidencePercent,
          'regime': idea.marketRegime.name,
          'strategy': idea.strategy.name,
        },
      ),
    );
    await _append(
      TradingJournalEvent(
        eventId: 'entry:${managed.entryOrderId}',
        journalTradeId: id,
        type: TradingJournalEventType.entryFilled,
        occurredAt: managed.openedAt.toUtc(),
        recordedAt: now,
        source: TradingJournalFactSource.exchange,
        quality: TradingJournalFactQuality.confirmed,
        scope: TradingJournalScope.position,
        currency: account.marginCoin,
        asOf: managed.openedAt.toUtc(),
        exchangeEventId: 'entry-order:${managed.entryOrderId}',
        positionId: managed.positionId,
        orderId: managed.entryOrderId,
        clientId: managed.clientId,
        quantity: managed.initialQuantity,
        price: managed.entryPrice,
        remainingQuantity: managed.initialQuantity,
        details: {'marginMode': 'ISOLATION', 'leverage': managed.leverage},
      ),
    );
    final stopId = managed.stopOrderId;
    if (stopId != null && stopId.trim().isNotEmpty) {
      await _append(
        TradingJournalEvent(
          eventId: 'stop:$stopId',
          journalTradeId: id,
          type: TradingJournalEventType.stopConfirmed,
          occurredAt: now,
          recordedAt: now,
          source: TradingJournalFactSource.exchange,
          quality: TradingJournalFactQuality.confirmed,
          scope: TradingJournalScope.position,
          currency: account.marginCoin,
          asOf: now,
          exchangeEventId: 'stop-order:$stopId',
          positionId: managed.positionId,
          orderId: stopId,
          quantity: managed.initialQuantity,
          price: managed.originalStopLoss,
        ),
      );
    }
    for (var index = 0; index < managed.targetOrderIds.length; index++) {
      final orderId = managed.targetOrderIds[index];
      final quantity = managed.targetQuantities[index];
      if (orderId.trim().isEmpty || quantity <= 0) continue;
      await _append(
        TradingJournalEvent(
          eventId: 'tp-confirmed:$orderId',
          journalTradeId: id,
          type: TradingJournalEventType.takeProfitConfirmed,
          occurredAt: now,
          recordedAt: now,
          source: TradingJournalFactSource.exchange,
          quality: TradingJournalFactQuality.confirmed,
          scope: TradingJournalScope.position,
          currency: account.marginCoin,
          asOf: now,
          exchangeEventId: 'tp-order:$orderId',
          positionId: managed.positionId,
          orderId: orderId,
          quantity: quantity,
          price: managed.targets[index],
          details: {'targetIndex': index + 1},
        ),
      );
    }
  }

  Future<bool> recordRecoveredPosition({
    required LocalLiveManagedPosition managed,
    required AutoTradeAccountSnapshot account,
  }) async {
    final id = journalTradeId(managed.positionId);
    final riskPerUnit = (managed.entryPrice - managed.originalStopLoss).abs();
    final expectedR = managed.targets
        .map(
          (target) => riskPerUnit <= 0
              ? 0.0
              : (target - managed.entryPrice).abs() / riskPerUnit,
        )
        .toList(growable: false);
    final riskBudget =
        riskPerUnit * managed.initialQuantity +
        managed.entryPrice * managed.initialQuantity * 0.0017;
    final riskPercent = account.estimatedEquity <= 0
        ? 0.0
        : riskBudget / account.estimatedEquity * 100;
    final plan = TradingJournalPlan(
      journalTradeId: id,
      setupId: managed.setupId,
      analysisVersion: 'exchange-recovery-v1',
      symbol: managed.symbol,
      market: 'USDT_PERPETUAL',
      timeframe: managed.timeframe,
      direction: _direction(managed.direction),
      strategy: 'recovered-local-live',
      cadence: 'recovered-after-reinstall',
      source: TradingJournalSource.localLive,
      decidedAt: managed.openedAt.toUtc(),
      decisionPrice: managed.entryPrice,
      entryLower: managed.entryPrice,
      entryUpper: managed.entryPrice,
      plannedEntry: managed.entryPrice,
      originalStopLoss: managed.originalStopLoss,
      targets: List.unmodifiable(managed.targets),
      expectedRMultiples: List.unmodifiable(expectedR),
      confidencePercent: 0,
      confluence: const [
        'verified-q-local-entry-order',
        'verified-open-position-id',
        'confirmed-full-stop',
        'confirmed-three-target-ladder',
      ],
      regime: 'recovered-exchange-truth',
      rationale:
          'Recovered from verified Bitunix position, fill and protection facts after device-local state was removed.',
      invalidation:
          'Original signal metadata was unavailable after reinstall; no value was fabricated.',
      accountEquity: account.estimatedEquity,
      riskPercent: riskPercent,
      riskBudget: riskBudget,
      leverage: managed.leverage,
      expectedMargin:
          managed.initialQuantity * managed.entryPrice / managed.leverage,
      passedGates: const [
        'isolated-margin',
        'verified-q-local-entry-order',
        'confirmed-full-stop',
        'confirmed-three-target-ladder',
        'no-confirmed-partial-exit',
      ],
      blockedGates: const [],
      appVersion: '1.2.0-rc.2+121',
      strategyRulesVersion: 'exchange-recovery-v1',
      positionId: managed.positionId,
      entryOrderId: managed.entryOrderId,
      clientId: managed.clientId,
      notes:
          'Recovered after app reinstall. Original signal confidence and timeframe were not reconstructed.',
    );
    if (!await _appendPlan(plan)) return false;

    final now = DateTime.now().toUtc();
    await _append(
      TradingJournalEvent(
        eventId: 'recovered-entry:${managed.entryOrderId}',
        journalTradeId: id,
        type: TradingJournalEventType.entryFilled,
        occurredAt: managed.openedAt.toUtc(),
        recordedAt: now,
        source: TradingJournalFactSource.exchange,
        quality: TradingJournalFactQuality.confirmed,
        scope: TradingJournalScope.position,
        currency: account.marginCoin,
        asOf: account.syncedAt.toUtc(),
        exchangeEventId: 'entry-order:${managed.entryOrderId}',
        positionId: managed.positionId,
        orderId: managed.entryOrderId,
        clientId: managed.clientId,
        quantity: managed.initialQuantity,
        price: managed.entryPrice,
        remainingQuantity: managed.initialQuantity,
        details: const {
          'marginMode': 'ISOLATION',
          'recoveredAfterReinstall': true,
        },
      ),
    );
    await _append(
      TradingJournalEvent(
        eventId: 'recovered-stop:${managed.stopOrderId}',
        journalTradeId: id,
        type: TradingJournalEventType.stopConfirmed,
        occurredAt: now,
        recordedAt: now,
        source: TradingJournalFactSource.exchange,
        quality: TradingJournalFactQuality.confirmed,
        scope: TradingJournalScope.position,
        currency: account.marginCoin,
        asOf: account.syncedAt.toUtc(),
        exchangeEventId: 'stop-order:${managed.stopOrderId}',
        positionId: managed.positionId,
        orderId: managed.stopOrderId,
        quantity: managed.initialQuantity,
        price: managed.originalStopLoss,
      ),
    );
    for (var index = 0; index < managed.targetOrderIds.length; index++) {
      final orderId = managed.targetOrderIds[index];
      final quantity = managed.targetQuantities[index];
      if (orderId.trim().isEmpty || quantity <= 0) continue;
      await _append(
        TradingJournalEvent(
          eventId: 'recovered-tp:$orderId',
          journalTradeId: id,
          type: TradingJournalEventType.takeProfitConfirmed,
          occurredAt: now,
          recordedAt: now,
          source: TradingJournalFactSource.exchange,
          quality: TradingJournalFactQuality.confirmed,
          scope: TradingJournalScope.position,
          currency: account.marginCoin,
          asOf: account.syncedAt.toUtc(),
          exchangeEventId: 'tp-order:$orderId',
          positionId: managed.positionId,
          orderId: orderId,
          quantity: quantity,
          price: managed.targets[index],
          details: {'targetIndex': index + 1},
        ),
      );
    }
    await _append(
      TradingJournalEvent(
        eventId: 'recovered:${managed.positionId}',
        journalTradeId: id,
        type: TradingJournalEventType.reconciliationRecovered,
        occurredAt: now,
        recordedAt: now,
        source: TradingJournalFactSource.quantara,
        quality: TradingJournalFactQuality.confirmed,
        scope: TradingJournalScope.position,
        currency: account.marginCoin,
        asOf: account.syncedAt.toUtc(),
        exchangeEventId: 'recovered-position:${managed.positionId}',
        positionId: managed.positionId,
        details: const {
          'message':
              'Device-local ownership was reconstructed from verified exchange truth after reinstall.',
        },
      ),
    );
    return true;
  }

  Future<void> reconcilePosition({
    required LocalLiveManagedPosition managed,
    required PositionPnlProjection positionPnl,
    required bool positionClosed,
  }) async {
    final id = journalTradeId(managed.positionId);
    if (!positionPnl.isVerified) {
      final asOf = positionPnl.asOf.toUtc();
      await _append(
        TradingJournalEvent(
          eventId:
              'pnl-deferred:${managed.positionId}:${asOf.millisecondsSinceEpoch}',
          journalTradeId: id,
          type: TradingJournalEventType.staleDetected,
          occurredAt: asOf,
          recordedAt: DateTime.now().toUtc(),
          source: TradingJournalFactSource.quantara,
          quality: TradingJournalFactQuality.stale,
          scope: TradingJournalScope.position,
          currency: positionPnl.realizedGross.currency,
          asOf: asOf,
          positionId: managed.positionId,
          details: const {
            'message':
                'Authoritative exchange PnL was not verified; economic journal facts were deferred.',
          },
        ),
      );
      return;
    }
    final fills = [...positionPnl.fills]
      ..sort((left, right) => left.occurredAt.compareTo(right.occurredAt));
    final exitFills = fills
        .where((fill) => _isExitFill(managed: managed, fill: fill))
        .toList();
    final finalExitTradeId = positionClosed && exitFills.isNotEmpty
        ? exitFills.last.tradeId
        : null;
    var cumulativeExitQuantity = 0.0;
    for (final fill in fills) {
      final isExit = _isExitFill(managed: managed, fill: fill);
      if (isExit) cumulativeExitQuantity += fill.quantity;
      final targetIndex = managed.targetOrderIds.indexOf(fill.orderId);
      final isTarget = targetIndex >= 0;
      final isFinalExit = isExit && fill.tradeId == finalExitTradeId;
      final remaining = math
          .max(0, managed.initialQuantity - cumulativeExitQuantity)
          .toDouble();
      await _append(
        TradingJournalEvent(
          eventId: 'fill:${fill.tradeId}',
          journalTradeId: id,
          type: !isExit
              ? TradingJournalEventType.entryPartiallyFilled
              : isTarget
              ? TradingJournalEventType.takeProfitFilled
              : isFinalExit
              ? TradingJournalEventType.positionClosed
              : TradingJournalEventType.positionPartiallyClosed,
          occurredAt: fill.occurredAt.toUtc(),
          recordedAt: DateTime.now().toUtc(),
          source: TradingJournalFactSource.exchange,
          quality: TradingJournalFactQuality.confirmed,
          scope: TradingJournalScope.position,
          currency: positionPnl.realizedGross.currency,
          asOf: positionPnl.asOf.toUtc(),
          exchangeEventId: fill.tradeId,
          positionId: managed.positionId,
          orderId: fill.orderId,
          clientId: fill.clientId,
          tradeId: fill.tradeId,
          quantity: fill.quantity,
          price: fill.price,
          grossPnl: fill.realizedPnl,
          fee: fill.fee,
          remainingQuantity: remaining,
          details: {
            if (isTarget) 'targetIndex': targetIndex + 1,
            if (!isTarget)
              'closeReason': _closeReasonForFill(
                managed: managed,
                fill: fill,
              ).name,
          },
        ),
      );
    }
    final finalExit = exitFills.isEmpty ? null : exitFills.last;
    final finalExitTargetIndex = finalExit == null
        ? -1
        : managed.targetOrderIds.indexOf(finalExit.orderId);
    final needsSyntheticClose =
        positionClosed && (finalExit == null || finalExitTargetIndex >= 0);
    if (needsSyntheticClose) {
      final highestTarget = exitFills
          .map((fill) => managed.targetOrderIds.indexOf(fill.orderId) + 1)
          .where((index) => index > 0)
          .fold<int>(0, math.max);
      final closureTarget = finalExitTargetIndex >= 0
          ? finalExitTargetIndex + 1
          : highestTarget;
      final closedAt =
          (positionPnl.settlement?.closedAt ??
                  finalExit?.occurredAt ??
                  (fills.isEmpty
                      ? DateTime.now().toUtc()
                      : fills.last.occurredAt))
              .toUtc();
      await _append(
        TradingJournalEvent(
          eventId:
              'position-closed:${managed.positionId}:${closedAt.millisecondsSinceEpoch}',
          journalTradeId: id,
          type: TradingJournalEventType.positionClosed,
          occurredAt: closedAt,
          recordedAt: DateTime.now().toUtc(),
          source: TradingJournalFactSource.exchange,
          quality: TradingJournalFactQuality.confirmed,
          scope: TradingJournalScope.position,
          currency: positionPnl.realizedGross.currency,
          asOf: positionPnl.asOf.toUtc(),
          exchangeEventId:
              'position-closed:${managed.positionId}:${closedAt.millisecondsSinceEpoch}',
          positionId: managed.positionId,
          remainingQuantity: 0,
          details: {
            'closeReason': closureTarget >= 3
                ? TradingJournalCloseReason.takeProfit3.name
                : closureTarget == 2
                ? TradingJournalCloseReason.takeProfit2.name
                : closureTarget == 1
                ? TradingJournalCloseReason.takeProfit1.name
                : TradingJournalCloseReason.exchange.name,
          },
        ),
      );
    }
    final settlement = positionPnl.settlement;
    if (settlement != null && settlement.funding != null) {
      await _append(
        TradingJournalEvent(
          eventId:
              'funding:${managed.positionId}:${settlement.closedAt.millisecondsSinceEpoch}',
          journalTradeId: id,
          type: TradingJournalEventType.fundingApplied,
          occurredAt: settlement.closedAt.toUtc(),
          recordedAt: DateTime.now().toUtc(),
          source: TradingJournalFactSource.exchange,
          quality: TradingJournalFactQuality.confirmed,
          scope: TradingJournalScope.position,
          currency: positionPnl.funding.currency,
          asOf: positionPnl.asOf.toUtc(),
          exchangeEventId:
              'funding:${managed.positionId}:${settlement.closedAt.millisecondsSinceEpoch}',
          positionId: managed.positionId,
          funding: settlement.funding,
        ),
      );
    }
  }

  Future<void> recordStopMove({
    required LocalLiveManagedPosition managed,
    required int stage,
    required double previousStop,
    required double proposedStop,
    required bool confirmed,
    required String reason,
    String? orderId,
    String? warning,
  }) => _append(
    TradingJournalEvent(
      eventId:
          'stop-move:${managed.positionId}:$stage:${confirmed ? 'confirmed' : 'requested'}',
      journalTradeId: journalTradeId(managed.positionId),
      type: confirmed
          ? TradingJournalEventType.stopMoveConfirmed
          : TradingJournalEventType.stopMoveRequested,
      occurredAt: DateTime.now().toUtc(),
      recordedAt: DateTime.now().toUtc(),
      source: confirmed
          ? TradingJournalFactSource.exchange
          : TradingJournalFactSource.quantara,
      quality: confirmed
          ? TradingJournalFactQuality.confirmed
          : TradingJournalFactQuality.calculated,
      scope: TradingJournalScope.position,
      currency: 'USDT',
      asOf: DateTime.now().toUtc(),
      exchangeEventId: confirmed && orderId != null
          ? 'stop-promotion:${managed.positionId}:$stage:$orderId'
          : 'promotion-request:${managed.positionId}:$stage',
      positionId: managed.positionId,
      orderId: orderId,
      price: proposedStop,
      details: {
        'stage': stage,
        'reason': reason,
        'previousStop': previousStop,
        'newStop': proposedStop,
        'warning': warning,
      },
    ),
  );

  Future<void> recordLifecycle({
    required LocalLiveManagedPosition managed,
    required TradingJournalEventType type,
    required String identity,
    required String message,
    TradingJournalFactQuality quality = TradingJournalFactQuality.confirmed,
  }) {
    final effectiveType =
        type == TradingJournalEventType.positionClosed &&
            identity.startsWith('emergency-close-request:')
        ? TradingJournalEventType.reconciliationStarted
        : type;
    return _append(
      TradingJournalEvent(
        eventId: '$identity:${managed.positionId}',
        journalTradeId: journalTradeId(managed.positionId),
        type: effectiveType,
        occurredAt: DateTime.now().toUtc(),
        recordedAt: DateTime.now().toUtc(),
        source: TradingJournalFactSource.quantara,
        quality: quality,
        scope: TradingJournalScope.position,
        currency: 'USDT',
        asOf: DateTime.now().toUtc(),
        exchangeEventId: identity,
        positionId: managed.positionId,
        details: {'message': message, 'requestedType': type.name},
      ),
    );
  }

  Future<bool> _appendPlan(TradingJournalPlan plan) async {
    try {
      await _store.appendPlan(plan);
      return true;
    } on Object {
      // The journal is observer-only. A persistence failure must never change
      // exchange order management or trigger a compensating trade action.
      return false;
    }
  }

  Future<void> _append(TradingJournalEvent event) async {
    try {
      await _store.appendEvent(event);
    } on Object {
      // The journal is observer-only. A persistence failure must never change
      // exchange order management or trigger a compensating trade action.
    }
  }

  static bool _isExitFill({
    required LocalLiveManagedPosition managed,
    required ExchangePnlFill fill,
  }) {
    if (fill.reduceOnly) return true;
    if (managed.targetOrderIds.contains(fill.orderId)) return true;
    if (managed.stopOrderId != null && fill.orderId == managed.stopOrderId) {
      return true;
    }
    final side = fill.side.trim().toUpperCase();
    return switch (managed.direction) {
      TradeDirection.long => side == 'SELL',
      TradeDirection.short => side == 'BUY',
      TradeDirection.wait => false,
    };
  }

  Future<void> recordExchangeClosureObserved({
    required LocalLiveManagedPosition managed,
    required bool closedHistoryAvailable,
    DateTime? observedAt,
  }) {
    final at = (observedAt ?? DateTime.now()).toUtc();
    return _append(
      TradingJournalEvent(
        eventId: 'exchange-close-observed:${managed.positionId}',
        journalTradeId: journalTradeId(managed.positionId),
        type: TradingJournalEventType.positionClosed,
        occurredAt: at,
        recordedAt: at,
        source: TradingJournalFactSource.exchange,
        quality: TradingJournalFactQuality.confirmed,
        scope: TradingJournalScope.position,
        currency: 'USDT',
        asOf: at,
        exchangeEventId: 'exchange-close-observed:${managed.positionId}',
        positionId: managed.positionId,
        remainingQuantity: 0,
        details: {
          'closeReason': TradingJournalCloseReason.unknown.name,
          'economicsPending': true,
          'closedHistoryAvailable': closedHistoryAvailable,
          'message':
              'Bitunix no longer reports this position as open. Final fill-level economics and close classification are being reconciled.',
        },
      ),
    );
  }

  static TradingJournalCloseReason _closeReasonForFill({
    required LocalLiveManagedPosition managed,
    required ExchangePnlFill fill,
  }) {
    if (fill.clientId.endsWith('-emergency-close')) {
      return TradingJournalCloseReason.emergency;
    }
    if (fill.orderId == managed.stopOrderId) {
      return TradingJournalCloseReason.stop;
    }
    final stop = managed.originalStopLoss;
    final price = fill.price;
    if (stop.isFinite && stop > 0 && price.isFinite && price > 0) {
      final tolerance = stop.abs() * 0.003;
      final stopLike = switch (managed.direction) {
        TradeDirection.long => price <= stop + tolerance,
        TradeDirection.short => price >= stop - tolerance,
        TradeDirection.wait => false,
      };
      if (stopLike) return TradingJournalCloseReason.stop;
    }
    return TradingJournalCloseReason.exchange;
  }

  static TradingJournalDirection _direction(TradeDirection direction) =>
      switch (direction) {
        TradeDirection.long => TradingJournalDirection.long,
        TradeDirection.short => TradingJournalDirection.short,
        TradeDirection.wait => TradingJournalDirection.wait,
      };
}
