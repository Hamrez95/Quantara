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
    required this.store,
    this.policy = const PortfolioRiskPolicy(),
    this.defaultDailyRiskLimit = 10,
    this.timezoneOffsetMinutes = 0,
  });

  final PortfolioRiskLedgerStore store;
  final PortfolioRiskPolicy policy;
  final double defaultDailyRiskLimit;
  final int timezoneOffsetMinutes;
  Future<void> _operationTail = Future<void>.value();

  Future<PortfolioRiskLedger> load({DateTime? now}) {
    final timestamp = (now ?? DateTime.now()).toUtc();
    final atomic = _atomicStore;
    if (atomic != null) {
      return atomic.mutate<PortfolioRiskLedger>((current) async {
        final ledger = _normalize(current, timestamp);
        return PortfolioRiskLedgerMutation(value: ledger, nextLedger: ledger);
      });
    }
    return _serialValue(() => _loadUnlocked(timestamp));
  }

  Future<PortfolioReservationOutcome> reserve({
    required PortfolioEntryCandidate candidate,
    required PortfolioAccountTruth account,
    DateTime? now,
  }) {
    final timestamp = (now ?? DateTime.now()).toUtc();
    final atomic = _atomicStore;
    if (atomic != null) {
      return atomic.mutate<PortfolioReservationOutcome>((current) async {
        var ledger = _normalize(current, timestamp);
        final decision = policy.evaluate(
          ledger: ledger,
          candidate: candidate,
          account: _withLedgerReservations(account, ledger),
        );
        if (decision.allowed) {
          ledger = ledger.reserve(
            candidate: candidate,
            decision: decision,
            createdAt: timestamp,
          );
        }
        return PortfolioRiskLedgerMutation(
          value: PortfolioReservationOutcome(
            decision: decision,
            ledger: ledger,
            snapshot: ledger.snapshot(account),
          ),
          nextLedger: ledger,
        );
      });
    }
    return _serialValue(() async {
      var ledger = await _loadUnlocked(timestamp);
      final decision = policy.evaluate(
        ledger: ledger,
        candidate: candidate,
        account: _withLedgerReservations(account, ledger),
      );
      if (decision.allowed) {
        ledger = ledger.reserve(
          candidate: candidate,
          decision: decision,
          createdAt: timestamp,
        );
        await store.save(ledger);
      }
      return PortfolioReservationOutcome(
        decision: decision,
        ledger: ledger,
        snapshot: ledger.snapshot(account),
      );
    });
  }

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
  }) async {
    final ledger = await load(now: now);
    return ledger.snapshot(account);
  }

  Future<PortfolioRiskLedger> resetSimulation({
    required DateTime now,
    double? dailyRiskLimit,
  }) {
    final atomic = _atomicStore;
    if (atomic != null) {
      return atomic.mutate<PortfolioRiskLedger>((current) async {
        final initial = _resetLedger(
          current: current,
          now: now,
          dailyRiskLimit: dailyRiskLimit,
        );
        return PortfolioRiskLedgerMutation(value: initial, nextLedger: initial);
      });
    }
    return _serialValue(() async {
      final initial = _resetLedger(
        current: await store.load(),
        now: now,
        dailyRiskLimit: dailyRiskLimit,
      );
      await store.save(initial);
      return initial;
    });
  }

  Future<PortfolioRiskLedger> _mutate({
    required PortfolioRiskLedger Function(PortfolioRiskLedger ledger) mutation,
    DateTime? now,
  }) {
    final timestamp = (now ?? DateTime.now()).toUtc();
    final atomic = _atomicStore;
    if (atomic != null) {
      return atomic.mutate<PortfolioRiskLedger>((current) async {
        final next = mutation(_normalize(current, timestamp));
        return PortfolioRiskLedgerMutation(value: next, nextLedger: next);
      });
    }
    return _serialValue(() async {
      final current = await _loadUnlocked(timestamp);
      final next = mutation(current);
      if (next.revision != current.revision ||
          next.processedEventIds.length != current.processedEventIds.length) {
        await store.save(next);
      }
      return next;
    });
  }

  Future<PortfolioRiskLedger> _loadUnlocked(DateTime now) async {
    final current = await store.load();
    final normalized = _normalize(current, now);
    if (current == null || normalized.revision != current.revision) {
      await store.save(normalized);
    }
    return normalized;
  }

  PortfolioRiskLedger _normalize(PortfolioRiskLedger? current, DateTime now) {
    if (current == null) {
      return PortfolioRiskLedger.initial(
        tradingDay: TradingDayId.start(
          now: now,
          timezoneOffsetMinutes: timezoneOffsetMinutes,
        ),
        dailyRiskLimit: defaultDailyRiskLimit,
      );
    }
    return current.rollTradingDay(
      now: now,
      nextDailyRiskLimit: defaultDailyRiskLimit,
    );
  }

  PortfolioRiskLedger _resetLedger({
    required PortfolioRiskLedger? current,
    required DateTime now,
    required double? dailyRiskLimit,
  }) => PortfolioRiskLedger(
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

  AtomicPortfolioRiskLedgerStore? get _atomicStore =>
      store is AtomicPortfolioRiskLedgerStore
      ? store as AtomicPortfolioRiskLedgerStore
      : null;

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
    final result = _operationTail.then<T>((_) => operation());
    _operationTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }
}
