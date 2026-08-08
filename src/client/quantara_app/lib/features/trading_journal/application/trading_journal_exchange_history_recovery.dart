import '../../auto_trade/domain/trading_pnl_projection.dart';
import '../domain/trading_journal_models.dart';

final class TradingJournalExchangeHistoryRecoveryResult {
  const TradingJournalExchangeHistoryRecoveryResult({
    required this.ledger,
    required this.recoveredTradeIds,
  });

  final TradingJournalLedger ledger;
  final List<String> recoveredTradeIds;

  bool get changed => recoveredTradeIds.isNotEmpty;
}

abstract final class TradingJournalExchangeHistoryRecovery {
  static final RegExp _entryClientIdPattern = RegExp(
    r'^q-local-[0-9a-fA-F]{8}$',
  );

  static TradingJournalExchangeHistoryRecoveryResult recoverVerifiedHistory({
    required TradingJournalLedger ledger,
    required TradingPnlProjection pnlProjection,
    required DateTime recordedAt,
  }) {
    if (!pnlProjection.fillsAvailable || !pnlProjection.settlementsAvailable) {
      return TradingJournalExchangeHistoryRecoveryResult(
        ledger: ledger,
        recoveredTradeIds: const [],
      );
    }

    var next = ledger;
    final recovered = <String>[];
    final representedPositionIds = <String>{
      for (final plan in ledger.plans)
        if ((plan.positionId ?? '').trim().isNotEmpty) plan.positionId!.trim(),
      for (final event in ledger.events)
        if ((event.positionId ?? '').trim().isNotEmpty)
          event.positionId!.trim(),
    };

    for (final position in pnlProjection.positions) {
      final positionId = position.positionId.trim();
      final symbol = position.symbol.trim().toUpperCase();
      final settlement = position.settlement;
      if (positionId.isEmpty ||
          symbol.isEmpty ||
          representedPositionIds.contains(positionId) ||
          !position.isVerified ||
          settlement == null ||
          !position.realizedGross.isFinal ||
          !position.fees.isFinal ||
          !position.funding.isFinal) {
        continue;
      }

      final exactEntryClientIds = position.fills
          .map((fill) => fill.clientId.trim())
          .where((clientId) => _entryClientIdPattern.hasMatch(clientId))
          .toSet();
      if (exactEntryClientIds.length != 1) continue;
      final entryClientId = exactEntryClientIds.single;
      final entryFills =
          position.fills
              .where((fill) => fill.clientId.trim() == entryClientId)
              .toList(growable: false)
            ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
      if (entryFills.isEmpty || !_verifiedFillSet(entryFills, positionId)) {
        continue;
      }

      final entrySide = entryFills.first.side.trim().toUpperCase();
      final direction = switch (entrySide) {
        'BUY' => TradingJournalDirection.long,
        'SELL' => TradingJournalDirection.short,
        _ => TradingJournalDirection.wait,
      };
      if (direction == TradingJournalDirection.wait ||
          entryFills.any(
            (fill) => fill.side.trim().toUpperCase() != entrySide,
          )) {
        continue;
      }

      final exitSide = direction == TradingJournalDirection.long
          ? 'SELL'
          : 'BUY';
      final firstEntryAt = entryFills.first.occurredAt.toUtc();
      final exitFills =
          position.fills
              .where(
                (fill) =>
                    !fill.occurredAt.toUtc().isBefore(firstEntryAt) &&
                    (fill.reduceOnly ||
                        fill.side.trim().toUpperCase() == exitSide),
              )
              .where((fill) => fill.clientId.trim() != entryClientId)
              .toList(growable: false)
            ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
      if (exitFills.isEmpty || !_verifiedFillSet(exitFills, positionId)) {
        continue;
      }

      final entryQuantity = _totalQuantity(entryFills);
      final exitQuantity = _totalQuantity(exitFills);
      final tolerance = entryQuantity.abs() * 0.000001 + 0.00000001;
      if (entryQuantity <= 0 || exitQuantity + tolerance < entryQuantity) {
        continue;
      }
      final entryPrice = _weightedPrice(entryFills);
      final exitPrice = _weightedPrice(exitFills);
      if (entryPrice == null || exitPrice == null) continue;

      final journalTradeId = 'exchange-recovered:$positionId';
      final plan = TradingJournalPlan(
        journalTradeId: journalTradeId,
        setupId: 'recovered:$entryClientId',
        analysisVersion: 'not-captured',
        symbol: symbol,
        market: 'USDT_PERPETUAL',
        timeframe: 'unknown',
        direction: direction,
        strategy: 'not-captured',
        cadence: 'not-captured',
        source: TradingJournalSource.importedExchange,
        decidedAt: (settlement.openedAt ?? firstEntryAt).toUtc(),
        decisionPrice: entryPrice,
        entryLower: entryPrice,
        entryUpper: entryPrice,
        plannedEntry: entryPrice,
        originalStopLoss: 0,
        targets: const [],
        expectedRMultiples: const [],
        confidencePercent: 0,
        confluence: const [
          'verified Bitunix position history',
          'exact Quantara q-local entry clientId',
        ],
        regime: 'not-captured',
        rationale:
            'Recovered after reinstall from verified Bitunix history. Decision-time rationale was not persisted outside the previous app sandbox.',
        invalidation: 'not-captured',
        accountEquity: 0,
        riskPercent: 0,
        riskBudget: 0,
        leverage: 0,
        expectedMargin: 0,
        passedGates: const [
          'verified-exchange-history',
          'quantara-entry-client-id',
        ],
        blockedGates: const [],
        appVersion: 'recovered-from-exchange',
        strategyRulesVersion: 'not-captured',
        positionId: positionId,
        entryOrderId: entryFills.first.orderId,
        clientId: entryClientId,
        notes:
            'Exchange-recovered record: strategy, timeframe, original SL/TP, confidence and admission context were not available and were not fabricated.',
      );

      final entryEvent = TradingJournalEvent(
        eventId: 'exchange-recovered-entry:$positionId',
        journalTradeId: journalTradeId,
        type: TradingJournalEventType.entryFilled,
        occurredAt: firstEntryAt,
        recordedAt: recordedAt.toUtc(),
        source: TradingJournalFactSource.exchange,
        quality: TradingJournalFactQuality.confirmed,
        scope: TradingJournalScope.position,
        currency: pnlProjection.currency,
        asOf: position.asOf.toUtc(),
        exchangeEventId: 'exchange-recovered-entry:$positionId',
        positionId: positionId,
        orderId: entryFills.first.orderId,
        clientId: entryClientId,
        tradeId: entryFills.first.tradeId,
        quantity: entryQuantity,
        price: entryPrice,
        remainingQuantity: entryQuantity,
        details: {
          'recoveredAfterInstall': true,
          'exchangeTradeIds': entryFills.map((fill) => fill.tradeId).toList(),
          'decisionContextAvailable': false,
        },
      );

      final closeEvent = TradingJournalEvent(
        eventId: 'exchange-recovered-close:$positionId',
        journalTradeId: journalTradeId,
        type: TradingJournalEventType.positionClosed,
        occurredAt: settlement.closedAt.toUtc(),
        recordedAt: recordedAt.toUtc(),
        source: TradingJournalFactSource.exchange,
        quality: TradingJournalFactQuality.confirmed,
        scope: TradingJournalScope.position,
        currency: pnlProjection.currency,
        asOf: position.asOf.toUtc(),
        exchangeEventId: 'exchange-recovered-close:$positionId',
        positionId: positionId,
        orderId: exitFills.last.orderId,
        clientId: exitFills.last.clientId.trim().isEmpty
            ? null
            : exitFills.last.clientId.trim(),
        tradeId: exitFills.last.tradeId,
        quantity: exitQuantity,
        price: exitPrice,
        grossPnl: position.realizedGross.value,
        fee: position.fees.value,
        funding: position.funding.value,
        remainingQuantity: 0,
        details: {
          'closeReason': TradingJournalCloseReason.exchange.name,
          'recoveredAfterInstall': true,
          'backfilledFromVerifiedHistory': true,
          'exchangeTradeIds': exitFills.map((fill) => fill.tradeId).toList(),
          'decisionContextAvailable': false,
          'closeClassificationAvailable': false,
        },
      );

      final candidate = next
          .appendPlan(plan)
          .appendEvent(entryEvent)
          .appendEvent(closeEvent);
      if (candidate.integrity == TradingJournalIntegrity.unverified ||
          candidate.warnings.length > next.warnings.length) {
        continue;
      }
      next = candidate;
      representedPositionIds.add(positionId);
      recovered.add(journalTradeId);
    }

    return TradingJournalExchangeHistoryRecoveryResult(
      ledger: next,
      recoveredTradeIds: List.unmodifiable(recovered),
    );
  }

  static bool _verifiedFillSet(
    List<ExchangePnlFill> fills,
    String positionId,
  ) => fills.every(
    (fill) =>
        fill.positionId.trim() == positionId &&
        fill.tradeId.trim().isNotEmpty &&
        fill.orderId.trim().isNotEmpty &&
        fill.quantity.isFinite &&
        fill.quantity > 0 &&
        fill.price.isFinite &&
        fill.price > 0,
  );

  static double _totalQuantity(List<ExchangePnlFill> fills) =>
      fills.fold<double>(0, (sum, fill) => sum + fill.quantity.abs());

  static double? _weightedPrice(List<ExchangePnlFill> fills) {
    final quantity = _totalQuantity(fills);
    if (quantity <= 0) return null;
    final notional = fills.fold<double>(
      0,
      (sum, fill) => sum + fill.quantity.abs() * fill.price,
    );
    final value = notional / quantity;
    return value.isFinite && value > 0 ? value : null;
  }
}
