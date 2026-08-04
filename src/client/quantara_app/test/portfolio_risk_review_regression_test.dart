import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/core/persistence/quantara_durable_database.dart';
import 'package:quantara_app/features/portfolio_risk/application/portfolio_risk_coordinator.dart';
import 'package:quantara_app/features/portfolio_risk/data/portfolio_risk_ledger_store.dart';
import 'package:quantara_app/features/portfolio_risk/domain/portfolio_risk_models.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  final now = DateTime.utc(2026, 8, 4, 2);
  const policy = PortfolioRiskPolicy(maximumDirectionRiskFraction: 1);

  test('wrong-side stop fails closed without throwing', () {
    final decision = policy.evaluate(
      ledger: PortfolioRiskLedger.initial(
        tradingDay: TradingDayId.start(now: now, timezoneOffsetMinutes: 0),
        dailyRiskLimit: 10,
      ),
      candidate: PortfolioEntryCandidate(
        reservationId: 'reservation-invalid-stop',
        journalTradeId: 'trade-invalid-stop',
        candidateId: 'candidate-invalid-stop',
        symbol: 'BTCUSDT',
        assetGroup: 'crypto-major',
        side: PortfolioSide.long,
        strategy: 'review-regression',
        plannedQuantity: 1,
        entryPrice: 100,
        stopPrice: 101,
        contractMultiplier: 1,
        entryFeeRate: 0,
        exitFeeRate: 0,
        slippageRate: 0,
        fundingReserve: 0,
        requiredMargin: 10,
        leverage: 10,
        minimumQuantity: 0.001,
        minimumNotional: 1,
      ),
      account: _account(now),
    );

    expect(decision.allowed, isFalse);
    expect(decision.reason, PortfolioEntryBlockReason.invalidInput);
    expect(decision.liveExecutionAllowed, isFalse);
  });

  test(
    'snapshot counts exchange and ledger margin reservations once',
    () async {
      final database = SembastQuantaraDurableDatabase(
        factory: databaseFactoryMemory,
        path: 'portfolio-margin-review.db',
      );
      await database.initialize();
      final coordinator = PortfolioRiskCoordinator(
        store: DatabasePortfolioRiskLedgerStore(
          databaseFactory: () async => database,
        ),
        policy: policy,
        defaultDailyRiskLimit: 10,
      );
      final account = _account(now, pendingMarginReservations: 2);

      final outcome = await coordinator.reserve(
        candidate: PortfolioEntryCandidate(
          reservationId: 'reservation-btc',
          journalTradeId: 'trade-btc',
          candidateId: 'candidate-btc',
          symbol: 'BTCUSDT',
          assetGroup: 'crypto-major',
          side: PortfolioSide.long,
          strategy: 'review-regression',
          plannedQuantity: 3,
          entryPrice: 100,
          stopPrice: 99,
          contractMultiplier: 1,
          entryFeeRate: 0,
          exitFeeRate: 0,
          slippageRate: 0,
          fundingReserve: 0,
          requiredMargin: 6,
          leverage: 10,
          minimumQuantity: 0.001,
          minimumNotional: 1,
        ),
        account: account,
        now: now,
      );

      expect(outcome.decision.allowed, isTrue);
      expect(outcome.snapshot.margin.reservedMargin, 8);
      final refreshed = await coordinator.snapshot(account: account, now: now);
      expect(refreshed.margin.reservedMargin, 8);
      expect(refreshed.margin.spendable, 92);

      await database.close();
    },
  );

  test('fallback queues are isolated between coordinator instances', () async {
    final blockedStore = _BlockingPortfolioRiskStore();
    final blockedCoordinator = PortfolioRiskCoordinator(
      store: blockedStore,
      defaultDailyRiskLimit: 10,
    );
    final independentCoordinator = PortfolioRiskCoordinator(
      store: _MemoryPortfolioRiskStore(),
      defaultDailyRiskLimit: 10,
    );

    final blockedLoad = blockedCoordinator.load(now: now);
    await blockedStore.started.future;

    final independent = await independentCoordinator
        .load(now: now)
        .timeout(const Duration(seconds: 1));
    expect(independent.dailyRisk.limit, 10);

    blockedStore.release.complete();
    final released = await blockedLoad.timeout(const Duration(seconds: 1));
    expect(released.dailyRisk.limit, 10);
  });
}

PortfolioAccountTruth _account(
  DateTime now, {
  double pendingMarginReservations = 0,
}) => PortfolioAccountTruth(
  asOf: now,
  fresh: true,
  allOpenPositionsProtected: true,
  marginMode: 'isolated',
  freeMargin: 100,
  usedMargin: 0,
  maintenanceMargin: 0,
  pendingMarginReservations: pendingMarginReservations,
  safetyBuffer: 0,
  feeReserve: 0,
);

final class _BlockingPortfolioRiskStore implements PortfolioRiskLedgerStore {
  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();
  PortfolioRiskLedger? _ledger;

  @override
  Future<PortfolioRiskLedger?> load() async {
    if (!started.isCompleted) started.complete();
    await release.future;
    return _ledger;
  }

  @override
  Future<void> save(PortfolioRiskLedger ledger) async {
    _ledger = PortfolioRiskLedger.fromJson(ledger.toJson());
  }
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
