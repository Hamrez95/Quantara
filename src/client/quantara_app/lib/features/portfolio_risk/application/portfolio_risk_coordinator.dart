import 'dart:async';

import '../data/portfolio_risk_ledger_store.dart';
import '../domain/portfolio_risk_models.dart';

final class PortfolioReservationOutcome {
  const PortfolioReservationOutcome({
    required this.decision,
    required this.ledger,
    required this.snapshot,
  });

  final PortfolioEntryDecision decision;
  final PortfolioRiskLedger ledger;
  final PortfolioRiskSnapshot snapshot;
}

final class PortfolioRiskCoordinator {
  PortfolioRiskCoordinator({
    required PortfolioRiskLedgerStore store,
    PortfolioRiskPolicy policy = const PortfolioRiskPolicy(),
    this.defaultDailyRiskLimit = 10,
    this.timezoneOffsetMinutes = 0,
  }) : _store = store,
       _policy = policy;

  final PortfolioRiskLedgerStore _store;
  final PortfolioRiskPolicy _policy;
  final double defaultDailyRiskLimit;
  final int timezoneOffsetMinutes;
  static Future<void> _globalTail = Future<void>.value();

  Future<PortfolioRiskLedger> load({DateTime? now}) => _serialValue(() async {
    final timestamp = (now ?? DateTime.now()).toUtc();
    final current = await _store.load();
    if (current == null) {
      final initial = PortfolioRiskLedger.initial(
        tradingDay: TradingDayId.start(
          now: timestamp,
          timezoneOffsetMinutes: timezoneOffsetMinutes,
        ),
        dailyRiskLimit: defaultDailyRiskLimit,
      );
      await _store.save(initial);
      return initial;
    }
    final rolled = current.rollTradingDay(
      now: timestamp,
      nextDailyRiskLimit: defaultDailyRiskLimit,
    );
    if (rolled.revision != current.revision) await _store.save(rolled);
    return rolled;
  });

  Future<PortfolioReservationOutcome> reserve({
    required PortfolioEntryCandidate candidate,
    required PortfolioAccountTruth account,
    DateTime? now,
  }) => _serialValue(() async {
    final timestamp = (now ?? DateTime.now()).toUtc();
    var ledger = await _loadUnlocked(timestamp);
    final effectiveAccount = _withLedgerReservations(account, ledger);
    final decision = _policy.evaluate(
      ledger: ledger,
      candidate: candidate,
      account: effectiveAccount,
    );
    if (decision.allowed) {
      ledger = ledger.reserve(
        candidate: candidate,
        decision: decision,
        createdAt: timestamp,
      );
      await _store.save(ledger);
    }
    return PortfolioReservationOutcome(
      decision: decision,
      ledger: ledger,
      snapshot: ledger.snapshot(_withLedgerReservations(account, ledger)),
    );
  });

  Future<PortfolioRiskLedger> release({
    required String reservationId,
    required String eventId,
    DateTime? now,
  }) => _mutate(
    now: now,
    mutation: (ledger) =>
        ledger.release(reservationId: reservationId, eventId: eventId),
  );

  Future<PortfolioRiskLedger> markAmbiguous({
    required String reservationId,
    required String eventId,
    DateTime? now,
  }) => _mutate(
    now: now,
    mutation: (ledger) =>
        ledger.markAmbiguous(reservationId: reservationId, eventId: eventId),
  );

  Future<PortfolioRiskLedger> applyPartialFill({
    required String reservationId,
    required String eventId,
    required String entryOrderId,
    required String positionId,
    required double fillQuantity,
    DateTime? now,
  }) => _mutate(
    now: now,
    mutation: (ledger) => ledger.applyPartialFill(
      reservationId: reservationId,
      eventId: eventId,
      entryOrderId: entryOrderId,
      positionId: positionId,
      fillQuantity: fillQuantity,
    ),
  );

  Future<PortfolioRiskLedger> confirmStop({
    required String positionId,
    required String eventId,
    required double confirmedStop,
    DateTime? now,
  }) => _mutate(
    now: now,
    mutation: (ledger) => ledger.confirmStop(
      positionId: positionId,
      eventId: eventId,
      confirmedStop: confirmedStop,
    ),
  );

  Future<PortfolioRiskLedger> closePosition({
    required String positionId,
    required String eventId,
    required double exchangeConfirmedNetPnl,
    DateTime? now,
  }) => _mutate(
    now: now,
    mutation: (ledger) => ledger.closePosition(
      positionId: positionId,
      eventId: eventId,
      exchangeConfirmedNetPnl: exchangeConfirmedNetPnl,
    ),
  );

  Future<PortfolioRiskSnapshot> snapshot({
    required PortfolioAccountTruth account,
    DateTime? now,
  }) => _serialValue(() async {
    final ledger = await _loadUnlocked((now ?? DateTime.now()).toUtc());
    return ledger.snapshot(_withLedgerReservations(account, ledger));
  });

  Future<PortfolioRiskLedger> resetSimulation({
    required DateTime now,
    double? dailyRiskLimit,
  }) => _serialValue(() async {
    final current = await _store.load();
    final initial = PortfolioRiskLedger(
      schemaVersion: 1,
      revision: (current?.revision ?? 0) + 1,
      tradingDay: TradingDayId.start(
        now: now,
        timezoneOffsetMinutes:
            current?.tradingDay.timezoneOffsetMinutes ?? timezoneOffsetMinutes,
      ),
      dailyRiskLimit: dailyRiskLimit ?? defaultDailyRiskLimit,
      realizedLoss: 0,
      realizedProfit: 0,
      reservations: const [],
      processedEventIds: const {},
    );
    await _store.save(initial);
    return initial;
  });

  Future<PortfolioRiskLedger> _mutate({
    required PortfolioRiskLedger Function(PortfolioRiskLedger ledger) mutation,
    DateTime? now,
  }) => _serialValue(() async {
    final current = await _loadUnlocked((now ?? DateTime.now()).toUtc());
    final next = mutation(current);
    if (next.revision != current.revision ||
        next.processedEventIds.length != current.processedEventIds.length) {
      await _store.save(next);
    }
    return next;
  });

  Future<PortfolioRiskLedger> _loadUnlocked(DateTime now) async {
    final current = await _store.load();
    if (current == null) {
      final initial = PortfolioRiskLedger.initial(
        tradingDay: TradingDayId.start(
          now: now,
          timezoneOffsetMinutes: timezoneOffsetMinutes,
        ),
        dailyRiskLimit: defaultDailyRiskLimit,
      );
      await _store.save(initial);
      return initial;
    }
    final rolled = current.rollTradingDay(
      now: now,
      nextDailyRiskLimit: defaultDailyRiskLimit,
    );
    if (rolled.revision != current.revision) await _store.save(rolled);
    return rolled;
  }

  PortfolioAccountTruth _withLedgerReservations(
    PortfolioAccountTruth account,
    PortfolioRiskLedger ledger,
  ) => PortfolioAccountTruth(
    asOf: account.asOf,
    fresh: account.fresh,
    allOpenPositionsProtected: account.allOpenPositionsProtected,
    marginMode: account.marginMode,
    freeMargin: account.freeMargin,
    usedMargin: account.usedMargin,
    maintenanceMargin: account.maintenanceMargin,
    pendingMarginReservations:
        account.pendingMarginReservations + ledger.reservedMargin,
    safetyBuffer: account.safetyBuffer,
    feeReserve: account.feeReserve,
  );

  Future<T> _serialValue<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    final next = _globalTail.then((_) async {
      try {
        completer.complete(await operation());
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    _globalTail = next.catchError((Object _) {});
    return completer.future;
  }
}
