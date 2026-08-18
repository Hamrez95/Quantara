import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/core/persistence/quantara_durable_database.dart';
import 'package:quantara_app/features/portfolio_risk/application/portfolio_risk_coordinator.dart';
import 'package:quantara_app/features/portfolio_risk/data/portfolio_risk_ledger_store.dart';
import 'package:quantara_app/features/portfolio_risk/domain/portfolio_risk_models.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  test(
    'randomized concurrent reservations never overbook durable daily risk',
    () async {
      final random = Random(106);

      for (var round = 0; round < 12; round++) {
        final factory = databaseFactoryMemory;
        final path = 'portfolio-risk-stress-$round.db';
        final databases = List.generate(
          4,
          (_) => SembastQuantaraDurableDatabase(factory: factory, path: path),
        );
        await Future.wait(databases.map((database) => database.initialize()));

        final coordinators = databases
            .map(
              (database) => PortfolioRiskCoordinator(
                store: DatabasePortfolioRiskLedgerStore(
                  databaseFactory: () async => database,
                ),
                policy: const PortfolioRiskPolicy(
                  maximumDirectionRiskFraction: 1,
                ),
                defaultDailyRiskLimit: 10,
              ),
            )
            .toList(growable: false);
        final now = DateTime.utc(2026, 8, 18, 12, round);
        final account = _account(now);

        final outcomes = await Future.wait(
          List.generate(32, (index) {
            final plannedRisk = 0.25 + random.nextDouble() * 2.75;
            return coordinators[index % coordinators.length].reserve(
              candidate: _candidate(
                id: 'r$round-$index',
                symbol: 'ASSET${round}_${index}USDT',
                stopPrice: 100 - plannedRisk,
              ),
              account: account,
              now: now,
            );
          }),
        );

        final persisted = await coordinators.first.load(now: now);
        final acceptedRisk = outcomes
            .where((outcome) => outcome.decision.allowed)
            .fold<double>(
              0,
              (sum, outcome) => sum + outcome.decision.maximumLoss,
            );
        final activeIds = persisted.activeReservations
            .map((reservation) => reservation.reservationId)
            .toSet();

        expect(persisted.dailyRisk.pendingRisk, lessThanOrEqualTo(10 + 1e-9));
        expect(persisted.dailyRisk.available, greaterThanOrEqualTo(0));
        expect(acceptedRisk, closeTo(persisted.dailyRisk.pendingRisk, 1e-9));
        expect(activeIds, hasLength(persisted.activeReservations.length));
        expect(
          outcomes.where((outcome) => outcome.decision.allowed).length,
          persisted.activeReservations.length,
        );

        await Future.wait(databases.map((database) => database.close()));
      }
    },
  );

  test(
    'gap repricing and flash slippage exhaust risk before another entry',
    () async {
      final normalRisk = PortfolioRiskMath.maximumLoss(
        side: PortfolioSide.long,
        entryPrice: 100,
        stopPrice: 95,
        quantity: 1,
        contractMultiplier: 1,
        entryFeeRate: 0,
        exitFeeRate: 0,
        slippageRate: 0.001,
        fundingReserve: 0,
      );
      final flashRisk = PortfolioRiskMath.maximumLoss(
        side: PortfolioSide.long,
        entryPrice: 100,
        stopPrice: 95,
        quantity: 1,
        contractMultiplier: 1,
        entryFeeRate: 0,
        exitFeeRate: 0,
        slippageRate: 0.05,
        fundingReserve: 0,
      );
      expect(flashRisk, greaterThan(normalRisk));
      expect(normalRisk, closeTo(5.1, 1e-9));
      expect(flashRisk, closeTo(10, 1e-9));

      final database = SembastQuantaraDurableDatabase(
        factory: databaseFactoryMemory,
        path: 'portfolio-gap-slippage.db',
      );
      await database.initialize();
      final coordinator = PortfolioRiskCoordinator(
        store: DatabasePortfolioRiskLedgerStore(
          databaseFactory: () async => database,
        ),
        policy: const PortfolioRiskPolicy(maximumDirectionRiskFraction: 1),
        defaultDailyRiskLimit: 10,
      );
      final now = DateTime.utc(2026, 8, 18, 13);
      final account = _account(now);

      final initial = await coordinator.reserve(
        candidate: _candidate(
          id: 'gap-source',
          symbol: 'BTCUSDT',
          stopPrice: 97,
          slippageRate: 0.005,
        ),
        account: account,
        now: now,
      );
      expect(initial.decision.allowed, isTrue);
      expect(initial.decision.maximumLoss, closeTo(3.5, 1e-9));

      await coordinator.applyPartialFill(
        reservationId: 'reservation-gap-source',
        eventId: 'fill-gap-source',
        entryOrderId: 'order-gap-source',
        positionId: 'position-gap-source',
        fillQuantity: 1,
        now: now,
      );
      final shocked = await coordinator.confirmStop(
        positionId: 'position-gap-source',
        eventId: 'stop-gap-source',
        confirmedStop: 90,
        now: now,
      );

      expect(shocked.dailyRisk.openRisk, closeTo(10.5, 1e-9));
      expect(shocked.dailyRisk.available, 0);

      final next = await coordinator.reserve(
        candidate: _candidate(
          id: 'after-gap',
          symbol: 'ETHUSDT',
          stopPrice: 99,
        ),
        account: account,
        now: now,
      );
      expect(next.decision.allowed, isFalse);
      expect(
        next.decision.reason,
        PortfolioEntryBlockReason.riskBudgetInsufficient,
      );
      expect(next.ledger.activeReservations, hasLength(1));

      await database.close();
    },
  );
}

PortfolioAccountTruth _account(DateTime now) => PortfolioAccountTruth(
  asOf: now,
  fresh: true,
  allOpenPositionsProtected: true,
  marginMode: 'isolated',
  freeMargin: 1000,
  usedMargin: 0,
  maintenanceMargin: 0,
  pendingMarginReservations: 0,
  safetyBuffer: 0,
  feeReserve: 0,
);

PortfolioEntryCandidate _candidate({
  required String id,
  required String symbol,
  required double stopPrice,
  double slippageRate = 0,
}) => PortfolioEntryCandidate(
  reservationId: 'reservation-$id',
  journalTradeId: 'trade-$id',
  candidateId: 'candidate-$id',
  symbol: symbol,
  assetGroup: 'crypto-stress',
  side: PortfolioSide.long,
  strategy: 'portfolio-risk-stress',
  plannedQuantity: 1,
  entryPrice: 100,
  stopPrice: stopPrice,
  contractMultiplier: 1,
  entryFeeRate: 0,
  exitFeeRate: 0,
  slippageRate: slippageRate,
  fundingReserve: 0,
  requiredMargin: 1,
  leverage: 10,
  minimumQuantity: 0.001,
  minimumNotional: 1,
);
