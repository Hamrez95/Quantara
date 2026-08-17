import 'dart:async';

import '../data/portfolio_risk_ledger_store.dart';
import '../domain/capital_guardian.dart';
import '../domain/portfolio_risk_models.dart';

final class PortfolioReservationOutcome {
  const PortfolioReservationOutcome({
    required this.decision,
    required this.ledger,
    required this.snapshot,
    this.guardianDecision,
  });

  final PortfolioEntryDecision decision;
  final PortfolioRiskLedger ledger;
  final PortfolioRiskSnapshot snapshot;
  final CapitalGuardianDecision? guardianDecision;
}

final class PortfolioRiskCoordinator {
  PortfolioRiskCoordinator({
    required this.store,
    this.policy = const PortfolioRiskPolicy(),
    this.guardianPolicy = const CapitalGuardianPolicy(),
    this.defaultDailyRiskLimit = 10,
    this.timezoneOffsetMinutes = 0,
  });

  final PortfolioRiskLedgerStore store;
  final PortfolioRiskPolicy policy;
  final CapitalGuardianPolicy guardianPolicy;
  final double defaultDailyRiskLimit;
  final int timezoneOffsetMinutes;
  Future<void> _operationTail = Future<void>.value();
  CapitalGuardianState? _fallbackGuardianState;

  Future<PortfolioRiskLedger> load({DateTime? now}) {
    final timestamp = (now ?? DateTime.now()).toUtc();
    final combined = _atomicGuardianStore;
    if (combined != null) {
      return combined.mutateRiskAndGuardian<PortfolioRiskLedger>(
        (current, guardian) async {
          final ledger = _normalize(current, timestamp);
          final nextGuardian = _normalizeGuardian(guardian, ledger, timestamp);
          return PortfolioRiskAndGuardianMutation(
            value: ledger,
            nextLedger: ledger,
            nextGuardian: nextGuardian,
          );
        },
      );
    }
    final atomic = _atomicStore;
    if (atomic != null) {
      return atomic.mutate<PortfolioRiskLedger>((current) async {
        final ledger = _normalize(current, timestamp);
        _fallbackGuardianState = _normalizeGuardian(
          _fallbackGuardianState,
          ledger,
          timestamp,
        );
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
    final combined = _atomicGuardianStore;
    if (combined != null) {
      return combined.mutateRiskAndGuardian<PortfolioReservationOutcome>(
        (current, guardian) async {
          var ledger = _normalize(current, timestamp);
          final guardianState = _normalizeGuardian(
            guardian,
            ledger,
            timestamp,
          );
          final baseDecision = policy.evaluate(
            ledger: ledger,
            candidate: candidate,
            account: _withLedgerReservations(account, ledger),
          );
          final guardianDecision = guardianPolicy.evaluate(
            state: guardianState,
            ledger: ledger,
            baseDecision: baseDecision,
            now: timestamp,
          );
          final decision = _applyGuardianDecision(
            baseDecision,
            guardianDecision,
          );
          if (decision.allowed) {
            ledger = ledger.reserve(
              candidate: candidate,
              decision: decision,
              createdAt: timestamp,
            );
          }
          return PortfolioRiskAndGuardianMutation(
            value: PortfolioReservationOutcome(
              decision: decision,
              ledger: ledger,
              snapshot: ledger.snapshot(account),
              guardianDecision: guardianDecision,
            ),
            nextLedger: ledger,
            nextGuardian: guardianState,
          );
        },
      );
    }

    final atomic = _atomicStore;
    if (atomic != null) {
      return atomic.mutate<PortfolioReservationOutcome>((current) async {
        var ledger = _normalize(current, timestamp);
        final guardianState = _normalizeGuardian(
          _fallbackGuardianState,
          ledger,
          timestamp,
        );
        _fallbackGuardianState = guardianState;
        final baseDecision = policy.evaluate(
          ledger: ledger,
          candidate: candidate,
          account: _withLedgerReservations(account, ledger),
        );
        final guardianDecision = guardianPolicy.evaluate(
          state: guardianState,
          ledger: ledger,
          baseDecision: baseDecision,
          now: timestamp,
        );
        final decision = _applyGuardianDecision(
          baseDecision,
          guardianDecision,
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
            guardianDecision: guardianDecision,
          ),
          nextLedger: ledger,
        );
      });
    }

    return _serialValue(() async {
      var ledger = await _loadUnlocked(timestamp);
      final guardianState = _normalizeGuardian(
        _fallbackGuardianState,
        ledger,
        timestamp,
      );
      _fallbackGuardianState = guardianState;
      final baseDecision = policy.evaluate(
        ledger: ledger,
        candidate: candidate,
        account: _withLedgerReservations(account, ledger),
      );
      final guardianDecision = guardianPolicy.evaluate(
        state: guardianState,
        ledger: ledger,
        baseDecision: baseDecision,
        now: timestamp,
      );
      final decision = _applyGuardianDecision(
        baseDecision,
        guardianDecision,
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
        guardianDecision: guardianDecision,
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
  }) {
    final timestamp = (now ?? DateTime.now()).toUtc();
    final combined = _atomicGuardianStore;
    if (combined != null) {
      return combined.mutateRiskAndGuardian<PortfolioRiskLedger>(
        (current, guardian) async {
          final ledger = _normalize(current, timestamp);
          final guardianState = _normalizeGuardian(
            guardian,
            ledger,
            timestamp,
          );
          final shouldRecord =
              !ledger.processedEventIds.contains(eventId) &&
              ledger.reservations.any(
                (item) => item.open && item.positionId == positionId,
              );
          final nextLedger = ledger.closePosition(
            positionId: positionId,
            eventId: eventId,
            exchangeConfirmedNetPnl: exchangeConfirmedNetPnl,
          );
          final nextGuardian = shouldRecord
              ? guardianState.recordClose(
                  exchangeConfirmedNetPnl: exchangeConfirmedNetPnl,
                  now: timestamp,
                  timezoneOffsetMinutes:
                      ledger.tradingDay.timezoneOffsetMinutes,
                  policy: guardianPolicy,
                )
              : guardianState;
          return PortfolioRiskAndGuardianMutation(
            value: nextLedger,
            nextLedger: nextLedger,
            nextGuardian: nextGuardian,
          );
        },
      );
    }

    return _mutate(
      now: timestamp,
      mutation: (ledger) {
        final guardianState = _normalizeGuardian(
          _fallbackGuardianState,
          ledger,
          timestamp,
        );
        final shouldRecord =
            !ledger.processedEventIds.contains(eventId) &&
            ledger.reservations.any(
              (item) => item.open && item.positionId == positionId,
            );
        final next = ledger.closePosition(
          positionId: positionId,
          eventId: eventId,
          exchangeConfirmedNetPnl: exchangeConfirmedNetPnl,
        );
        _fallbackGuardianState = shouldRecord
            ? guardianState.recordClose(
                exchangeConfirmedNetPnl: exchangeConfirmedNetPnl,
                now: timestamp,
                timezoneOffsetMinutes: ledger.tradingDay.timezoneOffsetMinutes,
                policy: guardianPolicy,
              )
            : guardianState;
        return next;
      },
    );
  }

  Future<CapitalGuardianState> updateCapitalGuardianEnvironment({
    required double drawdownFraction,
    required bool abnormalVolatility,
    DateTime? now,
  }) {
    final timestamp = (now ?? DateTime.now()).toUtc();
    final combined = _atomicGuardianStore;
    if (combined != null) {
      return combined.mutateRiskAndGuardian<CapitalGuardianState>(
        (current, guardian) async {
          final ledger = _normalize(current, timestamp);
          final base = _normalizeGuardian(guardian, ledger, timestamp);
          final next = base.recordEnvironment(
            drawdownFraction: drawdownFraction,
            abnormalVolatility: abnormalVolatility,
            now: timestamp,
            timezoneOffsetMinutes: ledger.tradingDay.timezoneOffsetMinutes,
            policy: guardianPolicy,
          );
          return PortfolioRiskAndGuardianMutation(
            value: next,
            nextLedger: ledger,
            nextGuardian: next,
          );
        },
      );
    }
    return _serialValue(() async {
      final ledger = await _loadUnlocked(timestamp);
      final base = _normalizeGuardian(
        _fallbackGuardianState,
        ledger,
        timestamp,
      );
      final next = base.recordEnvironment(
        drawdownFraction: drawdownFraction,
        abnormalVolatility: abnormalVolatility,
        now: timestamp,
        timezoneOffsetMinutes: ledger.tradingDay.timezoneOffsetMinutes,
        policy: guardianPolicy,
      );
      _fallbackGuardianState = next;
      return next;
    });
  }

  Future<CapitalGuardianState> guardianState({DateTime? now}) async {
    final timestamp = (now ?? DateTime.now()).toUtc();
    final combined = _atomicGuardianStore;
    if (combined != null) {
      return combined.mutateRiskAndGuardian<CapitalGuardianState>(
        (current, guardian) async {
          final ledger = _normalize(current, timestamp);
          final next = _normalizeGuardian(guardian, ledger, timestamp);
          return PortfolioRiskAndGuardianMutation(
            value: next,
            nextLedger: ledger,
            nextGuardian: next,
          );
        },
      );
    }
    final ledger = await load(now: timestamp);
    final next = _normalizeGuardian(
      _fallbackGuardianState,
      ledger,
      timestamp,
    );
    _fallbackGuardianState = next;
    return next;
  }

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
    _fallbackGuardianState = _normalizeGuardian(
      _fallbackGuardianState,
      normalized,
      now,
    );
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

  CapitalGuardianState _normalizeGuardian(
    CapitalGuardianState? current,
    PortfolioRiskLedger ledger,
    DateTime now,
  ) {
    final state = current ??
        CapitalGuardianState.initial(
          now: now,
          timezoneOffsetMinutes: ledger.tradingDay.timezoneOffsetMinutes,
        );
    return state.normalized(
      now: now,
      timezoneOffsetMinutes: ledger.tradingDay.timezoneOffsetMinutes,
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

  AtomicPortfolioRiskAndGuardianStore? get _atomicGuardianStore =>
      store is AtomicPortfolioRiskAndGuardianStore
      ? store as AtomicPortfolioRiskAndGuardianStore
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

  static PortfolioEntryDecision _applyGuardianDecision(
    PortfolioEntryDecision base,
    CapitalGuardianDecision guardian,
  ) {
    if (!base.allowed || guardian.allowed) return base;
    return PortfolioEntryDecision(
      allowed: false,
      liveExecutionAllowed: false,
      reason: PortfolioEntryBlockReason.riskBudgetInsufficient,
      maximumLoss: base.maximumLoss,
      requiredMargin: base.requiredMargin,
      availableRiskBefore: base.availableRiskBefore,
      availableRiskAfter: base.availableRiskBefore,
      availableMarginAfter: base.availableMarginAfter,
    );
  }

  Future<T> _serialValue<T>(Future<T> Function() operation) {
    final result = _operationTail.then<T>((_) => operation());
    _operationTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }
}
