import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/domain/trading_pnl_projection.dart';
import 'package:quantara_app/features/trading_journal/application/trading_journal_exchange_backfill.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_models.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_projection.dart';

void main() {
  test('repairs the historical GRAM stop from verified exchange history', () {
    final ledger = TradingJournalLedger.empty()
        .appendPlan(_plan())
        .appendEvent(_entry());
    final pnl = _verifiedPnl();

    final result = TradingJournalExchangeBackfill.reconcileVerifiedClosures(
      ledger: ledger,
      pnlProjection: pnl,
      openPositionIds: const {},
      recordedAt: DateTime.utc(2026, 8, 5, 5),
    );
    final projection = TradingJournalProjector.project(
      ledger: result.ledger,
      journalTradeId: 'local-live:gram-position',
    );

    expect(result.closedTradeIds, ['local-live:gram-position']);
    expect(projection.state, TradingJournalTradeState.closed);
    expect(projection.closeReason, TradingJournalCloseReason.stop);
    expect(projection.remainingQuantity, 0);
    expect(projection.grossPnl, closeTo(-0.2574, 0.00000001));
    expect(projection.fees, closeTo(0.03575286, 0.00000001));
    expect(projection.funding, 0);
    expect(projection.netPnl, closeTo(-0.29315286, 0.00000001));
    final close = projection.timeline.last;
    expect(close.quantity, 42.9);
    expect(close.price, 1.389);
    expect(close.details['backfilledFromVerifiedHistory'], isTrue);
  });

  test('historical closure repair is idempotent', () {
    final first = TradingJournalExchangeBackfill.reconcileVerifiedClosures(
      ledger: TradingJournalLedger.empty()
          .appendPlan(_plan())
          .appendEvent(_entry()),
      pnlProjection: _verifiedPnl(),
      openPositionIds: const {},
      recordedAt: DateTime.utc(2026, 8, 5, 5),
    );
    final second = TradingJournalExchangeBackfill.reconcileVerifiedClosures(
      ledger: first.ledger,
      pnlProjection: _verifiedPnl(),
      openPositionIds: const {},
      recordedAt: DateTime.utc(2026, 8, 5, 5, 1),
    );

    expect(second.changed, isFalse);
    expect(second.ledger.events, hasLength(first.ledger.events.length));
    expect(second.ledger.integrity, isNot(TradingJournalIntegrity.unverified));
  });

  test(
    'does not close a journal trade while exchange position remains open',
    () {
      final ledger = TradingJournalLedger.empty()
          .appendPlan(_plan())
          .appendEvent(_entry());
      final result = TradingJournalExchangeBackfill.reconcileVerifiedClosures(
        ledger: ledger,
        pnlProjection: _verifiedPnl(),
        openPositionIds: const {'gram-position'},
        recordedAt: DateTime.utc(2026, 8, 5, 5),
      );

      expect(result.changed, isFalse);
      expect(result.ledger.generation, ledger.generation);
    },
  );

  test('does not mutate journal from unverified exchange truth', () {
    final ledger = TradingJournalLedger.empty()
        .appendPlan(_plan())
        .appendEvent(_entry());
    final unverified = TradingPnlProjection.unavailable(
      currency: 'USDT',
      asOf: DateTime.utc(2026, 8, 5, 5),
      warning: 'ambiguous',
    );
    final result = TradingJournalExchangeBackfill.reconcileVerifiedClosures(
      ledger: ledger,
      pnlProjection: unverified,
      openPositionIds: const {},
      recordedAt: DateTime.utc(2026, 8, 5, 5),
    );

    expect(result.changed, isFalse);
    expect(result.ledger.generation, ledger.generation);
  });
}

TradingPnlProjection _verifiedPnl() => TradingPnlProjection.reconcile(
  currency: 'USDT',
  asOf: DateTime.utc(2026, 8, 5, 3, 20),
  unrealizedByPosition: const {},
  fills: [
    ExchangePnlFill(
      tradeId: '2795413522294203930',
      orderId: '7352379888826528074',
      positionId: 'gram-position',
      symbol: 'GRAMUSDT',
      quantity: 42.9,
      price: 1.389,
      realizedPnl: -0.2574,
      fee: 0.03575286,
      reduceOnly: true,
      occurredAt: DateTime.utc(2026, 8, 5, 3, 19, 14),
      side: 'SELL',
    ),
  ],
  settlements: [
    ExchangePositionSettlement(
      positionId: 'gram-position',
      symbol: 'GRAMUSDT',
      funding: 0,
      openedAt: DateTime.utc(2026, 8, 5, 2),
      closedAt: DateTime.utc(2026, 8, 5, 3, 19, 14),
      realizedPnl: -0.2574,
      fee: 0.03575286,
    ),
  ],
);

TradingJournalPlan _plan() => TradingJournalPlan(
  journalTradeId: 'local-live:gram-position',
  setupId: 'gram-setup',
  analysisVersion: 'v1',
  symbol: 'GRAMUSDT',
  market: 'USDT_PERPETUAL',
  timeframe: '15m',
  direction: TradingJournalDirection.long,
  strategy: 'structureZones',
  cadence: 'local-live',
  source: TradingJournalSource.localLive,
  decidedAt: DateTime.utc(2026, 8, 5, 2),
  decisionPrice: 1.40,
  entryLower: 1.40,
  entryUpper: 1.40,
  plannedEntry: 1.40,
  originalStopLoss: 1.39,
  targets: const [1.4191578119874324, 1.4100541342999584, 1.4282614896749064],
  expectedRMultiples: const [1, 2, 3],
  confidencePercent: 70,
  confluence: const ['15m'],
  regime: 'transition',
  rationale: 'physical canary',
  invalidation: 'stop',
  accountEquity: 29.81,
  riskPercent: 0.1,
  riskBudget: 0.02981,
  leverage: 10,
  expectedMargin: 6.006,
  passedGates: const ['isolated-margin'],
  blockedGates: const [],
  appVersion: '1.2.0-rc.2',
  strategyRulesVersion: 'v1',
  positionId: 'gram-position',
  entryOrderId: 'entry-order',
  clientId: 'q-local-gram',
);

TradingJournalEvent _entry() => TradingJournalEvent(
  eventId: 'entry',
  journalTradeId: 'local-live:gram-position',
  type: TradingJournalEventType.entryFilled,
  occurredAt: DateTime.utc(2026, 8, 5, 2),
  recordedAt: DateTime.utc(2026, 8, 5, 2),
  source: TradingJournalFactSource.exchange,
  quality: TradingJournalFactQuality.confirmed,
  scope: TradingJournalScope.position,
  currency: 'USDT',
  asOf: DateTime.utc(2026, 8, 5, 2),
  positionId: 'gram-position',
  orderId: 'entry-order',
  quantity: 42.9,
  price: 1.40,
  remainingQuantity: 42.9,
);
