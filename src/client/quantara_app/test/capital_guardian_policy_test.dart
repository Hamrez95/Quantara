import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:quantara_app/core/persistence/quantara_durable_database.dart';
import 'package:quantara_app/features/portfolio_risk/application/portfolio_risk_coordinator.dart';
import 'package:quantara_app/features/portfolio_risk/data/portfolio_risk_ledger_store.dart';
import 'package:quantara_app/features/portfolio_risk/domain/capital_guardian.dart';
import 'package:quantara_app/features/portfolio_risk/domain/portfolio_risk_models.dart';

void main() {
  final monday = DateTime.utc(2026, 8, 3, 10);
  const guardianPolicy = CapitalGuardianPolicy();
  const basePolicy = PortfolioRiskPolicy(maximumDirectionRiskFraction: 1);

  PortfolioRiskLedger ledger({
    DateTime? now,
    double dailyLimit = 10,
    List<PositionRiskReservation> reservations = const [],
  }) => PortfolioRiskLedger(
    schemaVersion: 1,
    revision: 0,
    tradingDay: TradingDayId.start(
      now: now ?? monday,
      timezoneOffsetMinutes: 0,
    ),
    dailyRiskLimit: dailyLimit,
    realizedLoss: 0,
    realizedProfit: 0,
    reservations: reservations,
    processedEventIds: const {},
  );

  PortfolioAccountTruth account() => PortfolioAccountTruth(
    asOf: monday,
    fresh: true,
    allOpenPositionsProtected: true,
    marginMode: 'isolated',
    freeMargin: 1000,
    usedMargin: 0,
    maintenanceMargin: 0,
    pendingMarginReservations: 0,
    safetyBuffer: 10,
    feeReserve: 1,
  );

  PortfolioEntryCandidate candidate(String id, double risk) =>
      PortfolioEntryCandidate(
        reservationId: 'reservation-$id',
        journalTradeId: 'trade-$id',
        candidateId: 'candidate-$id',
        symbol: '${id.toUpperCase()}USDT',
        assetGroup: 'crypto',
        side: PortfolioSide.long,
        strategy: 'guardian-test',
        plannedQuantity: risk,
        entryPrice: 100,
        stopPrice: 99,
        contractMultiplier: 1,
        entryFeeRate: 0,
        exitFeeRate: 0,
        slippageRate: 0,
        fundingReserve: 0,
        requiredMargin: risk * 2,
        leverage: 10,
        minimumQuantity: 0.001,
        minimumNotional: 1,
      );

  PositionRiskReservation openPosition(String id, {double risk = 1}) =>
      PositionRiskReservation(
        reservationId: 'open-$id',
        journalTradeId: 'trade-$id',
        candidateId: 'candidate-$id',
        symbol: '${id.toUpperCase()}USDT',
        assetGroup: 'crypto',
        side: PortfolioSide.long,
        strategy: 'guardian-test',
        entryOrderId: 'entry-$id',
        positionId: 'position-$id',
        plannedQuantity: 1,
        filledQuantity: 1,
        entryPrice: 100,
        currentExchangeConfirmedStop: 99,
        contractMultiplier: 1,
        estimatedEntryFee: 0,
        estimatedExitFee: 0,
        slippageReserve: 0,
        fundingReserve: 0,
        maximumLoss: risk,
        reservedMargin: 2,
        createdAt: monday,
        tradingDayId: TradingDayId.start(
          now: monday,
          timezoneOffsetMinutes: 0,
        ).value,
        lifecycle: PortfolioReservationLifecycle.open,
        verification: PortfolioVerificationState.exchangeConfirmed,
        revision: 1,
      );

  PortfolioEntryDecision baseDecision(
    PortfolioRiskLedger source,
    PortfolioEntryCandidate value,
  ) => basePolicy.evaluate(
    ledger: source,
    candidate: value,
    account: account(),
  );

  test('weekly realized loss survives daily rollover inside the same week', () {
    var state = CapitalGuardianState.initial(
      now: monday,
      timezoneOffsetMinutes: 0,
    );
    state = state.recordClose(
      exchangeConfirmedNetPnl: -7,
      now: monday,
      timezoneOffsetMinutes: 0,
      policy: guardianPolicy,
    );

    final tuesday = DateTime.utc(2026, 8, 4, 10);
    final normalized = state.normalized(
      now: tuesday,
      timezoneOffsetMinutes: 0,
    );

    expect(normalized.weekId, state.weekId);
    expect(normalized.weeklyRealizedLoss, 7);
  });

  test('weekly cap blocks new entries and resets only on the next week', () {
    var state = CapitalGuardianState.initial(
      now: monday,
      timezoneOffsetMinutes: 0,
    );
    state = state.recordClose(
      exchangeConfirmedNetPnl: -30,
      now: monday,
      timezoneOffsetMinutes: 0,
      policy: guardianPolicy,
    );
    final source = ledger();
    final value = candidate('btc', 1);
    final blocked = guardianPolicy.evaluate(
      state: state,
      ledger: source,
      baseDecision: baseDecision(source, value),
      now: monday,
    );

    expect(blocked.allowed, isFalse);
    expect(blocked.reason, CapitalGuardianBreakerReason.weeklyLossCap);

    final nextMonday = DateTime.utc(2026, 8, 10, 10);
    final reset = state.normalized(
      now: nextMonday,
      timezoneOffsetMinutes: 0,
    );
    expect(reset.weeklyRealizedLoss, 0);
    expect(reset.weekId, isNot(state.weekId));
  });

  test('consecutive losses trigger a durable cooldown', () {
    var state = CapitalGuardianState.initial(
      now: monday,
      timezoneOffsetMinutes: 0,
    );
    for (var index = 0; index < 3; index++) {
      state = state.recordClose(
        exchangeConfirmedNetPnl: -1,
        now: monday.add(Duration(minutes: index)),
        timezoneOffsetMinutes: 0,
        policy: guardianPolicy,
      );
    }
    final source = ledger();
    final value = candidate('btc', 1);
    final blocked = guardianPolicy.evaluate(
      state: state,
      ledger: source,
      baseDecision: baseDecision(source, value),
      now: monday.add(const Duration(minutes: 3)),
    );

    expect(state.consecutiveLosses, 3);
    expect(state.lossStreakCooldownUntilUtc, isNotNull);
    expect(blocked.allowed, isFalse);
    expect(blocked.reason, CapitalGuardianBreakerReason.lossStreakCooldown);
  });

  test('hard drawdown steps down through recovery before normal risk', () {
    var state = CapitalGuardianState.initial(
      now: monday,
      timezoneOffsetMinutes: 0,
    );
    state = state.recordEnvironment(
      drawdownFraction: 0.11,
      abnormalVolatility: false,
      now: monday,
      timezoneOffsetMinutes: 0,
      policy: guardianPolicy,
    );
    expect(state.drawdownTier, CapitalGuardianDrawdownTier.hardStop);
    expect(state.riskMultiplier(guardianPolicy), 0);

    state = state.recordEnvironment(
      drawdownFraction: 0.06,
      abnormalVolatility: false,
      now: monday.add(const Duration(minutes: 1)),
      timezoneOffsetMinutes: 0,
      policy: guardianPolicy,
    );
    expect(state.drawdownTier, CapitalGuardianDrawdownTier.recovery);
    expect(state.riskMultiplier(guardianPolicy), inInclusiveRange(0, 1));

    state = state.recordEnvironment(
      drawdownFraction: 0.02,
      abnormalVolatility: false,
      now: monday.add(const Duration(minutes: 2)),
      timezoneOffsetMinutes: 0,
      policy: guardianPolicy,
    );
    expect(state.drawdownTier, CapitalGuardianDrawdownTier.normal);
    expect(state.riskMultiplier(guardianPolicy), 1);
  });

  test('soft drawdown reduces maximum entry risk instead of expanding it', () {
    final source = ledger();
    final value = candidate('btc', 6);
    final base = baseDecision(source, value);
    expect(base.allowed, isTrue);

    final state = CapitalGuardianState.initial(
      now: monday,
      timezoneOffsetMinutes: 0,
    ).recordEnvironment(
      drawdownFraction: 0.06,
      abnormalVolatility: false,
      now: monday,
      timezoneOffsetMinutes: 0,
      policy: guardianPolicy,
    );
    final guarded = guardianPolicy.evaluate(
      state: state,
      ledger: source,
      baseDecision: base,
      now: monday,
    );

    expect(state.riskMultiplier(guardianPolicy), lessThanOrEqualTo(1));
    expect(guarded.allowed, isFalse);
    expect(guarded.reason, CapitalGuardianBreakerReason.reducedRiskAllowance);
    expect(guarded.maximumAllowedEntryRisk, 5);
  });

  test('abnormal volatility breaker remains closed until cooldown expires', () {
    final state = CapitalGuardianState.initial(
      now: monday,
      timezoneOffsetMinutes: 0,
    ).recordEnvironment(
      drawdownFraction: 0,
      abnormalVolatility: true,
      now: monday,
      timezoneOffsetMinutes: 0,
      policy: guardianPolicy,
    );
    final source = ledger();
    final value = candidate('btc', 1);
    final base = baseDecision(source, value);

    final blocked = guardianPolicy.evaluate(
      state: state,
      ledger: source,
      baseDecision: base,
      now: monday.add(const Duration(minutes: 30)),
    );
    expect(blocked.allowed, isFalse);
    expect(blocked.reason, CapitalGuardianBreakerReason.abnormalVolatility);

    final normalized = state.normalized(
      now: monday.add(const Duration(hours: 1, seconds: 1)),
      timezoneOffsetMinutes: 0,
    );
    final allowed = guardianPolicy.evaluate(
      state: normalized,
      ledger: source,
      baseDecision: base,
      now: monday.add(const Duration(hours: 1, seconds: 1)),
    );
    expect(allowed.allowed, isTrue);
  });

  test('guardian state JSON round-trip preserves safety fields', () {
    final source = CapitalGuardianState.initial(
      now: monday,
      timezoneOffsetMinutes: 0,
    ).recordClose(
      exchangeConfirmedNetPnl: -2,
      now: monday,
      timezoneOffsetMinutes: 0,
      policy: guardianPolicy,
    ).recordEnvironment(
      drawdownFraction: 0.06,
      abnormalVolatility: true,
      now: monday,
      timezoneOffsetMinutes: 0,
      policy: guardianPolicy,
    );

    final restored = CapitalGuardianState.fromJson(source.toJson());
    expect(restored.weeklyRealizedLoss, 2);
    expect(restored.consecutiveLosses, 1);
    expect(restored.drawdownTier, CapitalGuardianDrawdownTier.soft);
    expect(restored.volatilityBreakerUntilUtc, isNotNull);
  });

  test('coordinator restart keeps confirmed-loss guardian state', () async {
    final database = SembastQuantaraDurableDatabase(
      factory: databaseFactoryMemory,
      path: 'capital-guardian-restart.db',
    );
    await database.initialize();
    final store = DatabasePortfolioRiskLedgerStore(
      databaseFactory: () async => database,
    );
    await store.save(
      ledger(reservations: [openPosition('btc')]),
    );
    final first = PortfolioRiskCoordinator(
      store: store,
      policy: basePolicy,
      guardianPolicy: guardianPolicy,
      defaultDailyRiskLimit: 10,
    );
    await first.closePosition(
      positionId: 'position-btc',
      eventId: 'close-btc',
      exchangeConfirmedNetPnl: -4,
      now: monday,
    );

    final restarted = PortfolioRiskCoordinator(
      store: DatabasePortfolioRiskLedgerStore(
        databaseFactory: () async => database,
      ),
      policy: basePolicy,
      guardianPolicy: guardianPolicy,
      defaultDailyRiskLimit: 10,
    );
    final restored = await restarted.guardianState(now: monday);

    expect(restored.weeklyRealizedLoss, 4);
    expect(restored.consecutiveLosses, 1);
  });

  test('risk-ledger save does not erase persisted guardian state', () async {
    final database = SembastQuantaraDurableDatabase(
      factory: databaseFactoryMemory,
      path: 'capital-guardian-preserve.db',
    );
    await database.initialize();
    final store = DatabasePortfolioRiskLedgerStore(
      databaseFactory: () async => database,
    );
    final coordinator = PortfolioRiskCoordinator(
      store: store,
      policy: basePolicy,
      guardianPolicy: guardianPolicy,
      defaultDailyRiskLimit: 10,
    );
    await coordinator.updateCapitalGuardianEnvironment(
      drawdownFraction: 0.11,
      abnormalVolatility: false,
      now: monday,
    );

    final loaded = await store.load();
    await store.save(loaded!);
    final guardian = await store.loadCapitalGuardian();

    expect(guardian, isNotNull);
    expect(guardian!.drawdownTier, CapitalGuardianDrawdownTier.hardStop);
  });
}
