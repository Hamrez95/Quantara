import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/core/persistence/quantara_durable_database.dart';
import 'package:quantara_app/features/portfolio_risk/application/portfolio_risk_coordinator.dart';
import 'package:quantara_app/features/portfolio_risk/data/portfolio_risk_ledger_store.dart';
import 'package:quantara_app/features/portfolio_risk/domain/portfolio_risk_models.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  test('two runtimes cannot double-spend durable daily risk', () async {
    final factory = databaseFactoryMemory;
    final firstDatabase = SembastQuantaraDurableDatabase(
      factory: factory,
      path: 'portfolio-atomic.db',
    );
    final secondDatabase = SembastQuantaraDurableDatabase(
      factory: factory,
      path: 'portfolio-atomic.db',
    );
    await firstDatabase.initialize();
    await secondDatabase.initialize();

    final firstCoordinator = PortfolioRiskCoordinator(
      store: DatabasePortfolioRiskLedgerStore(
        databaseFactory: () async => firstDatabase,
      ),
      policy: const PortfolioRiskPolicy(maximumDirectionRiskFraction: 1),
      defaultDailyRiskLimit: 10,
    );
    final secondCoordinator = PortfolioRiskCoordinator(
      store: DatabasePortfolioRiskLedgerStore(
        databaseFactory: () async => secondDatabase,
      ),
      policy: const PortfolioRiskPolicy(maximumDirectionRiskFraction: 1),
      defaultDailyRiskLimit: 10,
    );
    final now = DateTime.utc(2026, 8, 4, 1);
    final account = PortfolioAccountTruth(
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

    final outcomes = await Future.wait([
      firstCoordinator.reserve(
        candidate: _candidate(
          reservationId: 'reservation-btc',
          journalTradeId: 'trade-btc',
          candidateId: 'candidate-btc',
          symbol: 'BTCUSDT',
        ),
        account: account,
        now: now,
      ),
      secondCoordinator.reserve(
        candidate: _candidate(
          reservationId: 'reservation-eth',
          journalTradeId: 'trade-eth',
          candidateId: 'candidate-eth',
          symbol: 'ETHUSDT',
        ),
        account: account,
        now: now,
      ),
    ]);

    expect(outcomes.where((item) => item.decision.allowed), hasLength(1));
    expect(
      outcomes.where(
        (item) =>
            !item.decision.allowed &&
            item.decision.reason ==
                PortfolioEntryBlockReason.riskBudgetInsufficient,
      ),
      hasLength(1),
    );

    final persisted = await firstCoordinator.load(now: now);
    expect(persisted.activeReservations, hasLength(1));
    expect(persisted.dailyRisk.pendingRisk, 6);
    expect(persisted.dailyRisk.available, 4);

    await firstDatabase.close();
    await secondDatabase.close();
  });
}

PortfolioEntryCandidate _candidate({
  required String reservationId,
  required String journalTradeId,
  required String candidateId,
  required String symbol,
}) => PortfolioEntryCandidate(
  reservationId: reservationId,
  journalTradeId: journalTradeId,
  candidateId: candidateId,
  symbol: symbol,
  assetGroup: 'crypto-major',
  side: PortfolioSide.long,
  strategy: 'atomic-concurrency-test',
  plannedQuantity: 1,
  entryPrice: 100,
  stopPrice: 94,
  contractMultiplier: 1,
  entryFeeRate: 0,
  exitFeeRate: 0,
  slippageRate: 0,
  fundingReserve: 0,
  requiredMargin: 10,
  leverage: 10,
  minimumQuantity: 0.001,
  minimumNotional: 1,
);
