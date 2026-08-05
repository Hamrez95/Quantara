import '../../auto_trade/domain/trading_pnl_projection.dart';
import '../domain/trading_journal_models.dart';
import '../domain/trading_journal_projection.dart';

final class TradingJournalExchangeBackfillResult {
  const TradingJournalExchangeBackfillResult({
    required this.ledger,
    required this.closedTradeIds,
  });

  final TradingJournalLedger ledger;
  final List<String> closedTradeIds;

  bool get changed => closedTradeIds.isNotEmpty;
}

abstract final class TradingJournalExchangeBackfill {
  static TradingJournalExchangeBackfillResult reconcileVerifiedClosures({
    required TradingJournalLedger ledger,
    required TradingPnlProjection pnlProjection,
    required Set<String> openPositionIds,
    required DateTime recordedAt,
  }) {
    if (ledger.integrity == TradingJournalIntegrity.unverified ||
        !pnlProjection.isVerified ||
        !pnlProjection.fillsAvailable ||
        !pnlProjection.settlementsAvailable) {
      return TradingJournalExchangeBackfillResult(
        ledger: ledger,
        closedTradeIds: const [],
      );
    }

    final normalizedOpenIds = openPositionIds
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
    var next = ledger;
    final closedTradeIds = <String>[];
    final projections = TradingJournalProjector.projectAll(ledger);
    final plansById = {
      for (final plan in ledger.plans) plan.journalTradeId: plan,
    };

    for (final journal in projections) {
      final plan = plansById[journal.journalTradeId];
      if (plan == null ||
          plan.source != TradingJournalSource.localLive ||
          journal.state != TradingJournalTradeState.open) {
        continue;
      }
      final positionId = (journal.positionId ?? plan.positionId ?? '').trim();
      if (positionId.isEmpty || normalizedOpenIds.contains(positionId)) {
        continue;
      }
      final position = pnlProjection.forPositionId(positionId);
      if (!_isVerifiedClosedPosition(position, plan)) continue;

      final exits = [...position!.exitFills]
        ..sort((left, right) => left.occurredAt.compareTo(right.occurredAt));
      final latest = exits.last;
      final totalQuantity = exits.fold<double>(
        0,
        (sum, fill) => sum + fill.quantity.abs(),
      );
      final weightedNotional = exits.fold<double>(
        0,
        (sum, fill) => sum + fill.quantity.abs() * fill.price,
      );
      final closePrice = totalQuantity > 0
          ? weightedNotional / totalQuantity
          : latest.price;
      final closeReason = _inferCloseReason(plan, latest.price);
      final settlement = position.settlement!;
      final eventId =
          'verified-history-close:$positionId:${settlement.closedAt.toUtc().microsecondsSinceEpoch}';
      final event = TradingJournalEvent(
        eventId: eventId,
        journalTradeId: plan.journalTradeId,
        type: TradingJournalEventType.positionClosed,
        occurredAt: settlement.closedAt.toUtc(),
        recordedAt: recordedAt.toUtc(),
        source: TradingJournalFactSource.exchange,
        quality: TradingJournalFactQuality.confirmed,
        scope: TradingJournalScope.position,
        currency: pnlProjection.currency,
        asOf: position.asOf.toUtc(),
        positionId: positionId,
        orderId: latest.orderId.trim().isEmpty ? null : latest.orderId.trim(),
        quantity: totalQuantity > 0 ? totalQuantity : null,
        price: closePrice.isFinite && closePrice > 0 ? closePrice : null,
        grossPnl: _economicDelta(
          authoritative: position.realizedGross.value,
          journalValue: journal.grossPnl,
        ),
        fee: _economicDelta(
          authoritative: position.fees.value,
          journalValue: journal.fees,
        ),
        funding: _economicDelta(
          authoritative: position.funding.value,
          journalValue: journal.funding,
        ),
        remainingQuantity: 0,
        details: {
          'closeReason': closeReason.name,
          'backfilledFromVerifiedHistory': true,
          'exchangeTradeIds': exits
              .map((item) => item.tradeId)
              .where((item) => item.trim().isNotEmpty)
              .toList(growable: false),
          'latestExchangeTradeId': latest.tradeId,
          'authoritativeGrossPnl': position.realizedGross.value,
          'authoritativeFee': position.fees.value,
          'authoritativeFunding': position.funding.value,
        },
      );
      final appended = next.appendEvent(event);
      if (appended.generation == next.generation) continue;
      if (appended.integrity == TradingJournalIntegrity.unverified) {
        return TradingJournalExchangeBackfillResult(
          ledger: ledger,
          closedTradeIds: const [],
        );
      }
      next = appended;
      closedTradeIds.add(plan.journalTradeId);
    }

    return TradingJournalExchangeBackfillResult(
      ledger: next,
      closedTradeIds: List.unmodifiable(closedTradeIds),
    );
  }

  static bool _isVerifiedClosedPosition(
    PositionPnlProjection? position,
    TradingJournalPlan plan,
  ) {
    if (position == null ||
        !position.isVerified ||
        position.settlement == null ||
        position.exitFills.isEmpty ||
        !position.realizedGross.isFinal ||
        !position.fees.isFinal ||
        !position.funding.isFinal) {
      return false;
    }
    final settlement = position.settlement!;
    if (settlement.closedAt.toUtc().isBefore(plan.decidedAt.toUtc())) {
      return false;
    }
    if (position.symbol.trim().toUpperCase() !=
        plan.symbol.trim().toUpperCase()) {
      return false;
    }
    return position.exitFills.every(
      (fill) =>
          fill.reduceOnly &&
          fill.positionId.trim() == position.positionId.trim() &&
          fill.tradeId.trim().isNotEmpty &&
          fill.quantity.isFinite &&
          fill.quantity > 0 &&
          fill.price.isFinite &&
          fill.price > 0,
    );
  }

  static double _economicDelta({
    required double? authoritative,
    required double? journalValue,
  }) {
    final value = (authoritative ?? 0) - (journalValue ?? 0);
    return value.abs() < 0.00000001 ? 0 : value;
  }

  static TradingJournalCloseReason _inferCloseReason(
    TradingJournalPlan plan,
    double finalPrice,
  ) {
    if (!finalPrice.isFinite || finalPrice <= 0) {
      return TradingJournalCloseReason.exchange;
    }
    final stop = plan.originalStopLoss;
    if (stop.isFinite && stop > 0) {
      final stopTolerance = stop.abs() * 0.003;
      final stopLike = switch (plan.direction) {
        TradingJournalDirection.long => finalPrice <= stop + stopTolerance,
        TradingJournalDirection.short => finalPrice >= stop - stopTolerance,
        TradingJournalDirection.wait => false,
      };
      if (stopLike) return TradingJournalCloseReason.stop;
    }

    var highestTarget = 0;
    for (var index = 0; index < plan.targets.length && index < 3; index++) {
      final target = plan.targets[index];
      if (!target.isFinite || target <= 0) continue;
      final tolerance = target.abs() * 0.003;
      final reached = switch (plan.direction) {
        TradingJournalDirection.long => finalPrice + tolerance >= target,
        TradingJournalDirection.short => finalPrice - tolerance <= target,
        TradingJournalDirection.wait => false,
      };
      if (reached) highestTarget = index + 1;
    }
    return switch (highestTarget) {
      1 => TradingJournalCloseReason.takeProfit1,
      2 => TradingJournalCloseReason.takeProfit2,
      3 => TradingJournalCloseReason.takeProfit3,
      _ => TradingJournalCloseReason.exchange,
    };
  }
}
