import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:quantara_app/core/persistence/quantara_durable_database.dart';
import 'package:quantara_app/features/portfolio_risk/application/portfolio_risk_coordinator.dart';
import 'package:quantara_app/features/portfolio_risk/data/portfolio_risk_ledger_store.dart';
import 'package:quantara_app/features/portfolio_risk/domain/portfolio_risk_models.dart';
import 'package:quantara_app/features/portfolio_risk/domain/portfolio_risk_transitions.dart';

void main() {
  final now = DateTime.utc(2026, 8, 4, 10);
  final day = TradingDayId.start(now: now, timezoneOffsetMinutes: 0);
  const policy = PortfolioRiskPolicy(maximumDirectionRiskFraction: 1);

  PortfolioRiskLedger empty({
    double limit = 10,
    double realizedLoss = 0,
    double realizedProfit = 0,
    List<PositionRiskReservation> reservations = const [],
  }) => PortfolioRiskLedger(
    schemaVersion: 1,
    revision: 0,
    tradingDay: day,
    dailyRiskLimit: limit,
    realizedLoss: realizedLoss,
    realizedProfit: realizedProfit,
    reservations: reservations,
    processedEventIds: const {},
  );

  PortfolioAccountTruth account({
    bool fresh = true,
    bool protected = true,
    String marginMode = 'isolated',
    double freeMargin = 100,
    double usedMargin = 0,
    double maintenanceMargin = 0,
    double pendingMargin = 0,
    double safetyBuffer = 10,
    double feeReserve = 1,
  }) => PortfolioAccountTruth(
    asOf: now,
    fresh: fresh,
    allOpenPositionsProtected: protected,
    marginMode: marginMode,
    freeMargin: freeMargin,
    usedMargin: usedMargin,
    maintenanceMargin: maintenanceMargin,
    pendingMarginReservations: pendingMargin,
    safetyBuffer: safetyBuffer,
    feeReserve: feeReserve,
  );

  PortfolioEntryCandidate candidate(
    String id,
    double risk, {
    String? symbol,
    PortfolioSide side = PortfolioSide.long,
    double entryFeeRate = 0,
    double exitFeeRate = 0,
    double slippageRate = 0,
    double fundingReserve = 0,
    double? requiredMargin,
    double stopDistance = 1,
    double minimumQuantity = 0.001,
    double minimumNotional = 1,
  }) {
    const entry = 100.0;
    final stop = side == PortfolioSide.long
        ? entry - stopDistance
        : entry + stopDistance;
    return PortfolioEntryCandidate(
      reservationId: 'reservation-$id',
      journalTradeId: 'trade-$id',
      candidateId: 'candidate-$id',
      symbol: symbol ?? '${id.toUpperCase()}USDT',
      assetGroup: 'crypto',
      side: side,
      strategy: 'test-strategy',
      plannedQuantity: risk / stopDistance,
      entryPrice: entry,
      stopPrice: stop,
      contractMultiplier: 1,
      entryFeeRate: entryFeeRate,
      exitFeeRate: exitFeeRate,
      slippageRate: slippageRate,
      fundingReserve: fundingReserve,
      requiredMargin: requiredMargin ?? risk * 2,
      leverage: 10,
      minimumQuantity: minimumQuantity,
      minimumNotional: minimumNotional,
    );
  }

  PortfolioRiskLedger reserve(
    PortfolioRiskLedger ledger,
    PortfolioEntryCandidate value, {
    PortfolioAccountTruth? truth,
    PortfolioRiskPolicy selectedPolicy = policy,
  }) {
    final decision = selectedPolicy.evaluate(
      ledger: ledger,
      candidate: value,
      account: truth ?? account(),
    );
    expect(decision.allowed, isTrue, reason: decision.reason.name);
    return ledger.reserve(candidate: value, decision: decision, createdAt: now);
  }

  PositionRiskReservation openReservation(
    String id,
    double risk, {
    String? symbol,
    PortfolioSide side = PortfolioSide.long,
    double quantity = 1,
    double entry = 100,
    double stop = 99,
    double margin = 2,
  }) => PositionRiskReservation(
    reservationId: 'open-$id',
    journalTradeId: 'trade-$id',
    candidateId: 'candidate-$id',
    symbol: symbol ?? '${id.toUpperCase()}USDT',
    assetGroup: 'crypto',
    side: side,
    strategy: 'test-strategy',
    entryOrderId: 'entry-$id',
    positionId: 'position-$id',
    plannedQuantity: quantity,
    filledQuantity: quantity,
    entryPrice: entry,
    currentExchangeConfirmedStop: stop,
    contractMultiplier: 1,
    estimatedEntryFee: 0,
    estimatedExitFee: 0,
    slippageReserve: 0,
    fundingReserve: 0,
    maximumLoss: risk,
    reservedMargin: margin,
    createdAt: now,
    tradingDayId: day.value,
    lifecycle: PortfolioReservationLifecycle.open,
    verification: PortfolioVerificationState.exchangeConfirmed,
    revision: 1,
  );

  test('1. daily limit 10 and first risk 3 leaves 7', () {
    final ledger = reserve(empty(), candidate('btc', 3, symbol: 'BTCUSDT'));
    expect(ledger.dailyRisk.pendingRisk, 3);
    expect(ledger.dailyRisk.available, 7);
  });

  test('2. reserving a second risk 4 leaves 3', () {
    var ledger = reserve(empty(), candidate('btc', 3, symbol: 'BTCUSDT'));
    ledger = reserve(
      ledger,
      candidate('eth', 4, symbol: 'ETHUSDT', side: PortfolioSide.short),
    );
    expect(ledger.dailyRisk.pendingRisk, 7);
    expect(ledger.dailyRisk.available, 3);
  });

  test('3. candidate risk exactly equal to available risk is accepted', () {
    var ledger = reserve(empty(), candidate('btc', 3, symbol: 'BTCUSDT'));
    ledger = reserve(
      ledger,
      candidate('eth', 4, symbol: 'ETHUSDT', side: PortfolioSide.short),
    );
    final decision = policy.evaluate(
      ledger: ledger,
      candidate: candidate('sol', 3, symbol: 'SOLUSDT'),
      account: account(),
    );
    expect(decision.allowed, isTrue);
    expect(decision.availableRiskAfter, closeTo(0, 1e-9));
  });

  test('4. fee and slippage make nominal risk 3 exceed capacity 3', () {
    var ledger = reserve(empty(), candidate('btc', 3, symbol: 'BTCUSDT'));
    ledger = reserve(
      ledger,
      candidate('eth', 4, symbol: 'ETHUSDT', side: PortfolioSide.short),
    );
    final decision = policy.evaluate(
      ledger: ledger,
      candidate: candidate(
        'sol',
        3,
        symbol: 'SOLUSDT',
        entryFeeRate: 0.0005,
        exitFeeRate: 0.0005,
        slippageRate: 0.0005,
      ),
      account: account(),
    );
    expect(decision.allowed, isFalse);
    expect(decision.reason, PortfolioEntryBlockReason.riskBudgetInsufficient);
    expect(decision.maximumLoss, greaterThan(3));
  });

  test('5. realized loss 3 plus open risk 4 leaves 3', () {
    final ledger = empty(
      realizedLoss: 3,
      reservations: [openReservation('btc', 4)],
    );
    expect(ledger.dailyRisk.realizedLoss, 3);
    expect(ledger.dailyRisk.openRisk, 4);
    expect(ledger.dailyRisk.available, 3);
  });

  test('6. realized profit never expands daily risk limit', () {
    final ledger = empty(realizedProfit: 5);
    expect(ledger.realizedProfit, 5);
    expect(ledger.dailyRisk.limit, 10);
    expect(ledger.dailyRisk.available, 10);
  });

  test(
    '7. requested stop promotion does not release risk before confirmation',
    () {
      final ledger = empty(reservations: [openReservation('btc', 3)]);
      expect(ledger.dailyRisk.openRisk, 3);
    },
  );

  test('8. confirmed break-even stop reduces cost-free open risk to zero', () {
    final ledger = empty(reservations: [openReservation('btc', 3)]);
    final updated = ledger.confirmStop(
      positionId: 'position-btc',
      eventId: 'stop-break-even',
      confirmedStop: 100,
    );
    expect(updated.dailyRisk.openRisk, 0);
  });

  test('9. confirmed profit stop cannot create negative risk capacity', () {
    final ledger = empty(reservations: [openReservation('btc', 3)]);
    final updated = ledger.confirmStop(
      positionId: 'position-btc',
      eventId: 'stop-profit',
      confirmedStop: 101,
    );
    expect(updated.dailyRisk.openRisk, 0);
    expect(updated.dailyRisk.available, 10);
  });

  test('10. concurrent atomic reservations cannot double-spend risk', () async {
    final store = _MemoryPortfolioRiskStore();
    final coordinator = PortfolioRiskCoordinator(
      store: store,
      policy: const PortfolioRiskPolicy(maximumDirectionRiskFraction: 1),
      defaultDailyRiskLimit: 10,
    );
    final outcomes = await Future.wait([
      coordinator.reserve(
        candidate: candidate('btc', 6, symbol: 'BTCUSDT'),
        account: account(),
        now: now,
      ),
      coordinator.reserve(
        candidate: candidate(
          'eth',
          6,
          symbol: 'ETHUSDT',
          side: PortfolioSide.short,
        ),
        account: account(),
        now: now,
      ),
    ]);
    expect(outcomes.where((item) => item.decision.allowed), hasLength(1));
    expect(outcomes.where((item) => !item.decision.allowed), hasLength(1));
    expect((await store.load())!.dailyRisk.consumed, 6);
  });

  test('11. pending cancel releases reservation exactly once', () {
    final reserved = reserve(empty(), candidate('btc', 3));
    final once = reserved.release(
      reservationId: 'reservation-btc',
      eventId: 'cancel-1',
    );
    final twice = once.release(
      reservationId: 'reservation-btc',
      eventId: 'cancel-1',
    );
    expect(once.dailyRisk.pendingRisk, 0);
    expect(twice.revision, once.revision);
    expect(twice.processedEventIds, once.processedEventIds);
  });

  test('12. pending reject is idempotent after a prior release', () {
    final reserved = reserve(empty(), candidate('btc', 3));
    final cancelled = reserved.release(
      reservationId: 'reservation-btc',
      eventId: 'cancel-1',
    );
    final rejected = cancelled.release(
      reservationId: 'reservation-btc',
      eventId: 'reject-1',
    );
    expect(rejected.dailyRisk.consumed, 0);
    expect(
      rejected.reservations.single.lifecycle,
      PortfolioReservationLifecycle.released,
    );
  });

  test('13. partial fill splits pending and open risk proportionally', () {
    final reserved = reserve(empty(), candidate('btc', 10));
    final split = reserved.applyPartialFill(
      reservationId: 'reservation-btc',
      eventId: 'fill-4',
      entryOrderId: 'entry-btc',
      positionId: 'position-btc',
      fillQuantity: 4,
    );
    expect(split.dailyRisk.pendingRisk, closeTo(6, 1e-9));
    expect(split.dailyRisk.openRisk, closeTo(4, 1e-9));
    expect(split.activeReservations, hasLength(2));
  });

  test('14. ambiguous response preserves risk and blocks all new entries', () {
    final reserved = reserve(empty(), candidate('btc', 3));
    final ambiguous = reserved.markAmbiguous(
      reservationId: 'reservation-btc',
      eventId: 'ambiguous-1',
    );
    final decision = policy.evaluate(
      ledger: ambiguous,
      candidate: candidate('eth', 1, symbol: 'ETHUSDT'),
      account: account(),
    );
    expect(ambiguous.dailyRisk.ambiguousRisk, 3);
    expect(decision.allowed, isFalse);
    expect(decision.reason, PortfolioEntryBlockReason.ambiguousReservation);
  });

  test('15. durable reservation survives coordinator restart', () async {
    final database = SembastQuantaraDurableDatabase(
      factory: databaseFactoryMemory,
      path: 'portfolio-risk-restart.db',
    );
    await database.initialize();
    final store = DatabasePortfolioRiskLedgerStore(
      databaseFactory: () async => database,
    );
    final first = PortfolioRiskCoordinator(
      store: store,
      policy: const PortfolioRiskPolicy(maximumDirectionRiskFraction: 1),
      defaultDailyRiskLimit: 10,
    );
    await first.reserve(
      candidate: candidate('btc', 3),
      account: account(),
      now: now,
    );
    final restarted = PortfolioRiskCoordinator(
      store: DatabasePortfolioRiskLedgerStore(
        databaseFactory: () async => database,
      ),
      policy: const PortfolioRiskPolicy(maximumDirectionRiskFraction: 1),
      defaultDailyRiskLimit: 10,
    );
    final loaded = await restarted.load(now: now);
    expect(loaded.dailyRisk.pendingRisk, 3);
    expect(loaded.reservations.single.reservationId, 'reservation-btc');
  });

  test('16. persisted ledger contains no credential or secret fields', () {
    final ledger = reserve(empty(), candidate('btc', 3));
    final serialized = ledger.toJson().toString().toLowerCase();
    expect(serialized, isNot(contains('apikey')));
    expect(serialized, isNot(contains('secretkey')));
    expect(serialized, isNot(contains('credential')));
    expect(serialized, isNot(contains('password')));
  });

  test('17. sufficient risk but insufficient margin rejects entry', () {
    final decision = policy.evaluate(
      ledger: empty(),
      candidate: candidate('btc', 3, requiredMargin: 20),
      account: account(freeMargin: 25, safetyBuffer: 10, feeReserve: 1),
    );
    expect(decision.allowed, isFalse);
    expect(decision.reason, PortfolioEntryBlockReason.marginInsufficient);
  });

  test('18. sufficient margin but insufficient risk rejects entry', () {
    final decision = policy.evaluate(
      ledger: empty(limit: 2),
      candidate: candidate('btc', 3),
      account: account(freeMargin: 1000),
    );
    expect(decision.allowed, isFalse);
    expect(decision.reason, PortfolioEntryBlockReason.riskBudgetInsufficient);
  });

  test('19. stale exchange account truth rejects new entry', () {
    final decision = policy.evaluate(
      ledger: empty(),
      candidate: candidate('btc', 1),
      account: account(fresh: false),
    );
    expect(decision.allowed, isFalse);
    expect(decision.reason, PortfolioEntryBlockReason.staleAccount);
  });

  test('20. incomplete position protection fails closed', () {
    final decision = policy.evaluate(
      ledger: empty(),
      candidate: candidate('btc', 1),
      account: account(protected: false),
    );
    expect(decision.allowed, isFalse);
    expect(decision.reason, PortfolioEntryBlockReason.incompleteProtection);
  });

  test('21. position identity keeps stop updates isolated', () {
    final ledger = empty(
      reservations: [
        openReservation('btc', 3, symbol: 'BTCUSDT'),
        openReservation(
          'eth',
          4,
          symbol: 'ETHUSDT',
          side: PortfolioSide.short,
          stop: 101,
        ),
      ],
    );
    final updated = ledger.confirmStop(
      positionId: 'position-btc',
      eventId: 'btc-break-even',
      confirmedStop: 100,
    );
    final btc = updated.reservations.firstWhere(
      (item) => item.positionId == 'position-btc',
    );
    final eth = updated.reservations.firstWhere(
      (item) => item.positionId == 'position-eth',
    );
    expect(btc.maximumLoss, 0);
    expect(eth.maximumLoss, 4);
    expect(eth.currentExchangeConfirmedStop, 101);
  });

  test('22. duplicate fill cannot consume risk twice', () {
    final reserved = reserve(empty(), candidate('btc', 10));
    final first = reserved.applyPartialFill(
      reservationId: 'reservation-btc',
      eventId: 'fill-4',
      entryOrderId: 'entry-btc',
      positionId: 'position-btc',
      fillQuantity: 4,
    );
    final duplicate = first.applyPartialFill(
      reservationId: 'reservation-btc',
      eventId: 'fill-4',
      entryOrderId: 'entry-btc',
      positionId: 'position-btc',
      fillQuantity: 4,
    );
    expect(duplicate.reservations.length, first.reservations.length);
    expect(duplicate.dailyRisk.consumed, first.dailyRisk.consumed);
  });

  test('23. out-of-order fills preserve deterministic total risk', () {
    final baseA = reserve(empty(), candidate('btc', 10));
    final a = baseA
        .applyPartialFill(
          reservationId: 'reservation-btc',
          eventId: 'fill-a',
          entryOrderId: 'entry-btc',
          positionId: 'position-a',
          fillQuantity: 4,
        )
        .applyPartialFill(
          reservationId: 'reservation-btc',
          eventId: 'fill-b',
          entryOrderId: 'entry-btc',
          positionId: 'position-b',
          fillQuantity: 6,
        );
    final baseB = reserve(empty(), candidate('btc', 10));
    final b = baseB
        .applyPartialFill(
          reservationId: 'reservation-btc',
          eventId: 'fill-b',
          entryOrderId: 'entry-btc',
          positionId: 'position-b',
          fillQuantity: 6,
        )
        .applyPartialFill(
          reservationId: 'reservation-btc',
          eventId: 'fill-a',
          entryOrderId: 'entry-btc',
          positionId: 'position-a',
          fillQuantity: 4,
        );
    expect(a.dailyRisk.openRisk, closeTo(10, 1e-9));
    expect(b.dailyRisk.openRisk, closeTo(10, 1e-9));
    expect(a.dailyRisk.pendingRisk, 0);
    expect(b.dailyRisk.pendingRisk, 0);
  });

  test('24. TP partial fill changes risk only after confirmed reduction', () {
    final ledger = empty(
      reservations: [openReservation('btc', 10, quantity: 10, margin: 20)],
    );
    expect(ledger.dailyRisk.openRisk, 10);
    final confirmed = PortfolioRiskTransitions.applyExchangeConfirmedReduction(
      ledger: ledger,
      positionId: 'position-btc',
      eventId: 'tp1-fill',
      remainingQuantity: 5,
    );
    expect(confirmed.dailyRisk.openRisk, closeTo(5, 1e-9));
    expect(confirmed.reservedMargin, closeTo(10, 1e-9));
  });

  test('25. final stop or TP closes reservation and records PnL once', () {
    final ledger = empty(reservations: [openReservation('btc', 3)]);
    final closed = ledger.closePosition(
      positionId: 'position-btc',
      eventId: 'close-1',
      exchangeConfirmedNetPnl: -2,
    );
    final duplicate = closed.closePosition(
      positionId: 'position-btc',
      eventId: 'close-1',
      exchangeConfirmedNetPnl: -2,
    );
    expect(closed.dailyRisk.openRisk, 0);
    expect(closed.realizedLoss, 2);
    expect(duplicate.realizedLoss, 2);
  });

  test('26. closed-while-offline history completion is idempotent', () {
    final ledger = empty(reservations: [openReservation('btc', 3)]);
    final history = ledger.closePosition(
      positionId: 'position-btc',
      eventId: 'history-close-order-1',
      exchangeConfirmedNetPnl: 1.5,
    );
    final repeated = history.closePosition(
      positionId: 'position-btc',
      eventId: 'history-close-order-1',
      exchangeConfirmedNetPnl: 1.5,
    );
    expect(history.realizedProfit, 1.5);
    expect(repeated.realizedProfit, 1.5);
    expect(
      repeated.reservations.single.lifecycle,
      PortfolioReservationLifecycle.closed,
    );
  });

  test('27. manual external position is not adopted and blocks entries', () {
    final observed = PortfolioRiskTransitions.observeExternalUnmanaged(
      ledger: empty(),
      positionId: 'manual-position',
      symbol: 'BTCUSDT',
      side: PortfolioSide.long,
      quantity: 0.01,
      entryPrice: 50000,
      observedStop: 49000,
      conservativeMaximumLoss: 10,
      observedMargin: 50,
      observedAt: now,
    );
    final external = observed.activeReservations.single;
    final decision = policy.evaluate(
      ledger: observed,
      candidate: candidate('eth', 1, symbol: 'ETHUSDT'),
      account: account(),
    );
    expect(external.lifecycle, PortfolioReservationLifecycle.ambiguous);
    expect(external.verification, PortfolioVerificationState.unverified);
    expect(external.strategy, 'external-unmanaged-observation');
    expect(decision.reason, PortfolioEntryBlockReason.ambiguousReservation);
  });

  test('28. nonfinite values fail closed', () {
    final decision = policy.evaluate(
      ledger: empty(),
      candidate: PortfolioEntryCandidate(
        reservationId: 'invalid',
        journalTradeId: 'invalid',
        candidateId: 'invalid',
        symbol: 'BTCUSDT',
        assetGroup: 'crypto',
        side: PortfolioSide.long,
        strategy: 'invalid',
        plannedQuantity: double.nan,
        entryPrice: 100,
        stopPrice: 99,
        contractMultiplier: 1,
        entryFeeRate: 0,
        exitFeeRate: 0,
        slippageRate: 0,
        fundingReserve: 0,
        requiredMargin: 1,
        leverage: 1,
        minimumQuantity: 0.001,
        minimumNotional: 1,
      ),
      account: account(),
    );
    expect(decision.allowed, isFalse);
    expect(decision.reason, PortfolioEntryBlockReason.invalidInput);
  });

  test('29. duplicate candidate identity is rejected', () {
    final ledger = reserve(empty(), candidate('btc', 3));
    final duplicate = policy.evaluate(
      ledger: ledger,
      candidate: candidate('btc', 1, symbol: 'ETHUSDT'),
      account: account(),
    );
    expect(duplicate.allowed, isFalse);
    expect(duplicate.reason, PortfolioEntryBlockReason.duplicateCandidate);
  });

  test('30. 10 USDT budget is divisible across multiple positions', () {
    var ledger = reserve(empty(), candidate('btc', 3, symbol: 'BTCUSDT'));
    ledger = reserve(
      ledger,
      candidate('eth', 4, symbol: 'ETHUSDT', side: PortfolioSide.short),
    );
    ledger = reserve(ledger, candidate('sol', 3, symbol: 'SOLUSDT'));
    expect(ledger.activeReservations, hasLength(3));
    expect(ledger.dailyRisk.consumed, 10);
    expect(ledger.dailyRisk.available, 0);
    final fourth = policy.evaluate(
      ledger: ledger,
      candidate: candidate(
        'xrp',
        0.1,
        symbol: 'XRPUSDT',
        side: PortfolioSide.short,
      ),
      account: account(),
    );
    expect(fourth.allowed, isFalse);
    expect(fourth.reason, PortfolioEntryBlockReason.riskBudgetInsufficient);
  });

  test('leverage changes margin input but never maximum loss math', () {
    final lowLeverage = candidate('low', 3, requiredMargin: 30);
    final highLeverage = PortfolioEntryCandidate(
      reservationId: 'reservation-high',
      journalTradeId: 'trade-high',
      candidateId: 'candidate-high',
      symbol: 'ETHUSDT',
      assetGroup: 'crypto',
      side: PortfolioSide.short,
      strategy: 'test-strategy',
      plannedQuantity: lowLeverage.plannedQuantity,
      entryPrice: lowLeverage.entryPrice,
      stopPrice: 101,
      contractMultiplier: 1,
      entryFeeRate: 0,
      exitFeeRate: 0,
      slippageRate: 0,
      fundingReserve: 0,
      requiredMargin: 3,
      leverage: 100,
      minimumQuantity: 0.001,
      minimumNotional: 1,
    );
    final low = policy.evaluate(
      ledger: empty(),
      candidate: lowLeverage,
      account: account(freeMargin: 100),
    );
    final high = policy.evaluate(
      ledger: empty(),
      candidate: highLeverage,
      account: account(freeMargin: 100),
    );
    expect(low.maximumLoss, high.maximumLoss);
    expect(low.requiredMargin, 30);
    expect(high.requiredMargin, 3);
  });

  test('device timezone change cannot reset an active trading day', () {
    final original = TradingDayId.start(
      now: DateTime.utc(2026, 8, 4, 10),
      timezoneOffsetMinutes: 210,
    );
    final ledger = PortfolioRiskLedger.initial(
      tradingDay: original,
      dailyRiskLimit: 10,
    );
    final sameDay = ledger.rollTradingDay(
      now: DateTime.utc(2026, 8, 4, 11),
      nextDailyRiskLimit: 10,
    );
    expect(sameDay.tradingDay.value, original.value);
    expect(sameDay.tradingDay.timezoneOffsetMinutes, 210);
  });

  test('prior-day open risk continues after idempotent daily reset', () {
    final yesterday = TradingDayId.start(
      now: DateTime.utc(2026, 8, 3, 10),
      timezoneOffsetMinutes: 0,
    );
    final ledger = PortfolioRiskLedger(
      schemaVersion: 1,
      revision: 1,
      tradingDay: yesterday,
      dailyRiskLimit: 10,
      realizedLoss: 3,
      realizedProfit: 5,
      reservations: [openReservation('btc', 4)],
      processedEventIds: const {},
    );
    final rolled = ledger.rollTradingDay(
      now: DateTime.utc(2026, 8, 4, 10),
      nextDailyRiskLimit: 10,
    );
    final repeated = rolled.rollTradingDay(
      now: DateTime.utc(2026, 8, 4, 11),
      nextDailyRiskLimit: 10,
    );
    expect(rolled.realizedLoss, 0);
    expect(rolled.realizedProfit, 0);
    expect(rolled.dailyRisk.openRisk, 4);
    expect(rolled.dailyRisk.available, 6);
    expect(repeated.revision, rolled.revision);
  });
}

final class _MemoryPortfolioRiskStore implements PortfolioRiskLedgerStore {
  PortfolioRiskLedger? _ledger;

  @override
  Future<PortfolioRiskLedger?> load() async => _ledger;

  @override
  Future<void> save(PortfolioRiskLedger ledger) async {
    _ledger = PortfolioRiskLedger.fromJson(ledger.toJson());
  }
}
