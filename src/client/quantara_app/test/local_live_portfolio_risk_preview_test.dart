import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/core/persistence/quantara_durable_database.dart';
import 'package:quantara_app/features/auto_trade/application/local_live_portfolio_risk_runtime.dart';
import 'package:quantara_app/features/portfolio_risk/data/portfolio_risk_ledger_store.dart';
import 'package:quantara_app/features/portfolio_risk/domain/portfolio_risk_models.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  test('risk preview evaluates live gates without consuming budget', () async {
    final database = SembastQuantaraDurableDatabase(
      factory: databaseFactoryMemory,
      path: 'local-live-risk-preview.db',
    );
    await database.initialize();
    final store = DatabasePortfolioRiskLedgerStore(
      databaseFactory: () async => database,
      recordKey: 'preview-ledger',
    );
    final runtime = LocalLivePortfolioRiskRuntime(
      dailyRiskLimit: 10,
      store: store,
      maximumAssetGroupRiskFraction: 1,
    );
    final now = DateTime.utc(2026, 8, 19);
    final candidate = _candidate(id: 'btc', symbol: 'BTCUSDT', riskDistance: 4);

    final preview = await runtime.preview(
      candidate: candidate,
      account: _account(now),
      now: now,
    );

    expect(preview.decision.allowed, isTrue);
    expect(preview.ledger.activeReservations, isEmpty);
    expect(await store.load(), isNull);

    final reserved = await runtime.reserve(
      candidate: candidate,
      account: _account(now),
      now: now,
    );

    expect(reserved.decision.allowed, isTrue);
    expect((await store.load())?.activeReservations, hasLength(1));
    await database.close();
  });

  test(
    'atomic reserve rechecks truth after an earlier allowed preview',
    () async {
      final database = SembastQuantaraDurableDatabase(
        factory: databaseFactoryMemory,
        path: 'local-live-risk-preview-race.db',
      );
      await database.initialize();
      final runtime = LocalLivePortfolioRiskRuntime(
        dailyRiskLimit: 6,
        store: DatabasePortfolioRiskLedgerStore(
          databaseFactory: () async => database,
          recordKey: 'preview-race-ledger',
        ),
        maximumAssetGroupRiskFraction: 1,
      );
      final now = DateTime.utc(2026, 8, 19);
      final first = _candidate(id: 'btc', symbol: 'BTCUSDT', riskDistance: 4);
      final second = _candidate(id: 'sol', symbol: 'SOLUSDT', riskDistance: 4);

      expect(
        (await runtime.preview(
          candidate: first,
          account: _account(now),
          now: now,
        )).decision.allowed,
        isTrue,
      );
      expect(
        (await runtime.preview(
          candidate: second,
          account: _account(now),
          now: now,
        )).decision.allowed,
        isTrue,
      );

      final firstReservation = await runtime.reserve(
        candidate: first,
        account: _account(now),
        now: now,
      );
      expect(firstReservation.decision.allowed, isTrue);

      final staleSecondReservation = await runtime.reserve(
        candidate: second,
        account: _account(now),
        now: now,
      );
      expect(staleSecondReservation.decision.allowed, isFalse);
      expect(
        staleSecondReservation.decision.reason,
        PortfolioEntryBlockReason.riskBudgetInsufficient,
      );
      expect(staleSecondReservation.ledger.activeReservations, hasLength(1));
      await database.close();
    },
  );
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
  required double riskDistance,
}) => PortfolioEntryCandidate(
  reservationId: 'reservation-$id',
  journalTradeId: 'trade-$id',
  candidateId: 'candidate-$id',
  symbol: symbol,
  assetGroup: symbol.startsWith('BTC') ? 'crypto-major' : 'crypto-alt',
  side: PortfolioSide.long,
  strategy: 'allocation-preview-test',
  plannedQuantity: 1,
  entryPrice: 100,
  stopPrice: 100 - riskDistance,
  contractMultiplier: 1,
  entryFeeRate: 0,
  exitFeeRate: 0,
  slippageRate: 0,
  fundingReserve: 0,
  requiredMargin: 10,
  leverage: 3,
  minimumQuantity: 0.001,
  minimumNotional: 1,
);
