import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/core/persistence/quantara_durable_database.dart';
import 'package:quantara_app/features/auto_trade/application/local_live_portfolio_risk_runtime.dart';
import 'package:quantara_app/features/portfolio_risk/data/portfolio_risk_ledger_store.dart';
import 'package:quantara_app/features/portfolio_risk/domain/capital_guardian.dart';
import 'package:quantara_app/features/portfolio_risk/domain/portfolio_risk_models.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  test('TP reduction releases risk and margin for another position', () async {
    final database = SembastQuantaraDurableDatabase(
      factory: databaseFactoryMemory,
      path: 'local-live-portfolio-runtime.db',
    );
    await database.initialize();
    final runtime = LocalLivePortfolioRiskRuntime(
      dailyRiskLimit: 10,
      store: DatabasePortfolioRiskLedgerStore(
        databaseFactory: () async => database,
        recordKey: 'local-live-test-ledger',
      ),
    );
    final now = DateTime.utc(2026, 8, 5);
    final account = _account(now);

    final first = await runtime.reserve(
      candidate: _candidate(
        id: 'btc',
        symbol: 'BTCUSDT',
        side: PortfolioSide.long,
        riskDistance: 6,
        requiredMargin: 30,
      ),
      account: account,
      now: now,
    );
    expect(first.decision.allowed, isTrue);

    await runtime.recordFill(
      reservationId: 'reservation-btc',
      eventId: 'fill-btc',
      entryOrderId: 'order-btc',
      positionId: 'position-btc',
      fillQuantity: 1,
      now: now,
    );
    await runtime.confirmStop(
      positionId: 'position-btc',
      eventId: 'stop-btc',
      confirmedStop: 94,
      now: now,
    );

    final blockedBeforeReduction = await runtime.reserve(
      candidate: _candidate(
        id: 'sol',
        symbol: 'SOLUSDT',
        side: PortfolioSide.short,
        riskDistance: 5,
        requiredMargin: 25,
      ),
      account: account,
      now: now,
    );
    expect(blockedBeforeReduction.decision.allowed, isFalse);
    expect(
      blockedBeforeReduction.decision.reason,
      PortfolioEntryBlockReason.riskBudgetInsufficient,
    );

    await runtime.reduce(
      positionId: 'position-btc',
      eventId: 'tp1-btc-remaining-25pct',
      remainingQuantity: 0.25,
      now: now,
    );

    final afterReduction = await runtime.reserve(
      candidate: _candidate(
        id: 'sol',
        symbol: 'SOLUSDT',
        side: PortfolioSide.short,
        riskDistance: 5,
        requiredMargin: 25,
      ),
      account: account,
      now: now,
    );
    expect(afterReduction.decision.allowed, isTrue);
    expect(afterReduction.ledger.dailyRisk.openRisk, closeTo(1.5, 1e-9));
    expect(afterReduction.ledger.reservedMargin, closeTo(32.5, 1e-9));

    await database.close();
  });

  test(
    'correlated asset group is capped even when total risk remains',
    () async {
      final database = SembastQuantaraDurableDatabase(
        factory: databaseFactoryMemory,
        path: 'local-live-correlation-runtime.db',
      );
      await database.initialize();
      final runtime = LocalLivePortfolioRiskRuntime(
        dailyRiskLimit: 10,
        store: DatabasePortfolioRiskLedgerStore(
          databaseFactory: () async => database,
          recordKey: 'local-live-correlation-ledger',
        ),
      );
      final now = DateTime.utc(2026, 8, 5);
      final account = _account(now);

      expect(
        (await runtime.reserve(
          candidate: _candidate(
            id: 'btc',
            symbol: 'BTCUSDT',
            side: PortfolioSide.long,
            riskDistance: 4,
            requiredMargin: 20,
          ),
          account: account,
          now: now,
        )).decision.allowed,
        isTrue,
      );

      final correlated = await runtime.reserve(
        candidate: _candidate(
          id: 'eth',
          symbol: 'ETHUSDT',
          side: PortfolioSide.short,
          riskDistance: 3,
          requiredMargin: 15,
        ),
        account: account,
        now: now,
      );
      expect(correlated.decision.allowed, isFalse);
      expect(
        correlated.decision.reason,
        PortfolioEntryBlockReason.directionConcentration,
      );

      await database.close();
    },
  );

  test('persisted Guardian hard stop blocks Local Live atomically', () async {
    final database = SembastQuantaraDurableDatabase(
      factory: databaseFactoryMemory,
      path: 'local-live-guardian-runtime.db',
    );
    await database.initialize();
    final store = DatabasePortfolioRiskLedgerStore(
      databaseFactory: () async => database,
      recordKey: 'local-live-guardian-ledger',
    );
    final runtime = LocalLivePortfolioRiskRuntime(
      dailyRiskLimit: 10,
      store: store,
    );
    final now = DateTime.utc(2026, 8, 5);
    await runtime.load(now: now);

    await store.mutateRiskAndGuardian<void>((ledger, guardian) async {
      final base =
          guardian ??
          CapitalGuardianState.initial(now: now, timezoneOffsetMinutes: 0);
      final hardStopped = base.recordEnvironment(
        drawdownFraction: 0.11,
        abnormalVolatility: false,
        now: now,
        timezoneOffsetMinutes: 0,
        policy: const CapitalGuardianPolicy(),
      );
      return PortfolioRiskAndGuardianMutation<void>(
        value: null,
        nextLedger: ledger,
        nextGuardian: hardStopped,
      );
    });

    final blocked = await runtime.reserve(
      candidate: _candidate(
        id: 'btc',
        symbol: 'BTCUSDT',
        side: PortfolioSide.long,
        riskDistance: 2,
        requiredMargin: 10,
      ),
      account: _account(now),
      now: now,
    );

    expect(blocked.decision.allowed, isFalse);
    expect(
      blocked.decision.reason,
      PortfolioEntryBlockReason.riskBudgetInsufficient,
    );
    expect(
      blocked.guardianDecision?.reason,
      CapitalGuardianBreakerReason.drawdownHardStop,
    );
    expect(blocked.ledger.activeReservations, isEmpty);
    expect(
      (await store.loadCapitalGuardian())?.drawdownTier,
      CapitalGuardianDrawdownTier.hardStop,
    );

    await database.close();
  });

  test('runtime ledger is isolated from the simulation ledger', () async {
    final database = SembastQuantaraDurableDatabase(
      factory: databaseFactoryMemory,
      path: 'local-live-ledger-isolation.db',
    );
    await database.initialize();
    final simulationStore = DatabasePortfolioRiskLedgerStore(
      databaseFactory: () async => database,
    );
    final liveStore = DatabasePortfolioRiskLedgerStore(
      databaseFactory: () async => database,
      recordKey: 'local-live-portfolio-risk-ledger-v1',
    );
    final runtime = LocalLivePortfolioRiskRuntime(
      dailyRiskLimit: 10,
      store: liveStore,
    );
    final now = DateTime.utc(2026, 8, 5);

    await runtime.reserve(
      candidate: _candidate(
        id: 'btc',
        symbol: 'BTCUSDT',
        side: PortfolioSide.long,
        riskDistance: 3,
        requiredMargin: 10,
      ),
      account: _account(now),
      now: now,
    );

    expect(await simulationStore.load(), isNull);
    expect((await liveStore.load())?.activeReservations, hasLength(1));
    await database.close();
  });
}

PortfolioAccountTruth _account(DateTime now) => PortfolioAccountTruth(
  asOf: now,
  fresh: true,
  allOpenPositionsProtected: true,
  marginMode: 'isolated',
  freeMargin: 100,
  usedMargin: 0,
  maintenanceMargin: 0,
  pendingMarginReservations: 0,
  safetyBuffer: 0,
  feeReserve: 0,
);

PortfolioEntryCandidate _candidate({
  required String id,
  required String symbol,
  required PortfolioSide side,
  required double riskDistance,
  required double requiredMargin,
}) {
  final long = side == PortfolioSide.long;
  return PortfolioEntryCandidate(
    reservationId: 'reservation-$id',
    journalTradeId: 'trade-$id',
    candidateId: 'candidate-$id',
    symbol: symbol,
    assetGroup: symbol.startsWith('BTC') || symbol.startsWith('ETH')
        ? 'crypto-major'
        : 'crypto-alt',
    side: side,
    strategy: 'runtime-test',
    plannedQuantity: 1,
    entryPrice: 100,
    stopPrice: long ? 100 - riskDistance : 100 + riskDistance,
    contractMultiplier: 1,
    entryFeeRate: 0,
    exitFeeRate: 0,
    slippageRate: 0,
    fundingReserve: 0,
    requiredMargin: requiredMargin,
    leverage: 3,
    minimumQuantity: 0.001,
    minimumNotional: 1,
  );
}
