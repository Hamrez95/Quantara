import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/domain/trading_pnl_projection.dart';
import 'package:quantara_app/features/trading_journal/application/trading_journal_exchange_backfill.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_models.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_projection.dart';

void main() {
  test(
    'opposite-side Bitunix stop fill closes even when reduceOnly is false',
    () {
      final result = TradingJournalExchangeBackfill.reconcileVerifiedClosures(
        ledger: TradingJournalLedger.empty()
            .appendPlan(_plan())
            .appendEvent(_entry()),
        pnlProjection: _pnl(reduceOnly: false),
        openPositionIds: const {},
        recordedAt: DateTime.utc(2026, 8, 7, 15, 30),
      );
      final projection = TradingJournalProjector.project(
        ledger: result.ledger,
        journalTradeId: 'local-live:sol-position',
      );

      expect(result.closedTradeIds, ['local-live:sol-position']);
      expect(projection.state, TradingJournalTradeState.closed);
      expect(projection.closeReason, TradingJournalCloseReason.stop);
      expect(projection.netPnl, closeTo(-0.10777156, 0.00000001));
    },
  );

  test(
    'unrelated legacy journal warning cannot keep confirmed SOL close open',
    () {
      final ledger = TradingJournalLedger.empty()
          .appendPlan(_plan())
          .appendEvent(_entry())
          .withIntegrityWarning(
            'Legacy warning for an unrelated historical trade.',
          );
      final result = TradingJournalExchangeBackfill.reconcileVerifiedClosures(
        ledger: ledger,
        pnlProjection: _pnl(),
        openPositionIds: const {},
        recordedAt: DateTime.utc(2026, 8, 7, 15, 30),
      );
      final projection = TradingJournalProjector.project(
        ledger: result.ledger,
        journalTradeId: 'local-live:sol-position',
      );

      expect(result.closedTradeIds, ['local-live:sol-position']);
      expect(projection.state, TradingJournalTradeState.closed);
      expect(projection.integrity, TradingJournalIntegrity.unverified);
      expect(
        result.ledger.warnings,
        contains('Legacy warning for an unrelated historical trade.'),
      );
    },
  );
}

TradingPnlProjection _pnl({bool reduceOnly = true}) =>
    TradingPnlProjection.reconcile(
      currency: 'USDT',
      asOf: DateTime.utc(2026, 8, 7, 15, 25),
      unrealizedByPosition: const {},
      fills: [
        ExchangePnlFill(
          tradeId: 'sol-stop-fill',
          orderId: 'sol-stop-order',
          positionId: 'sol-position',
          symbol: 'SOLUSDT',
          quantity: 0.23,
          price: 73.62,
          realizedPnl: -0.0874,
          fee: 0.02037156,
          reduceOnly: reduceOnly,
          occurredAt: DateTime.utc(2026, 8, 7, 15, 25),
          side: 'SELL',
        ),
      ],
      settlements: [
        ExchangePositionSettlement(
          positionId: 'sol-position',
          symbol: 'SOLUSDT',
          funding: 0,
          openedAt: DateTime.utc(2026, 8, 7, 15),
          closedAt: DateTime.utc(2026, 8, 7, 15, 25),
          realizedPnl: -0.0874,
          fee: 0.02037156,
        ),
      ],
    );

TradingJournalPlan _plan() => TradingJournalPlan(
  journalTradeId: 'local-live:sol-position',
  setupId: 'sol-5m-trend-pullback',
  analysisVersion: 'v1',
  symbol: 'SOLUSDT',
  market: 'USDT_PERPETUAL',
  timeframe: '5m',
  direction: TradingJournalDirection.long,
  strategy: 'trendPullback',
  cadence: 'local-live',
  source: TradingJournalSource.localLive,
  decidedAt: DateTime.utc(2026, 8, 7, 15),
  decisionPrice: 74.00,
  entryLower: 74.00,
  entryUpper: 74.00,
  plannedEntry: 74.00,
  originalStopLoss: 73.69,
  targets: const [74.9022],
  expectedRMultiples: const [1],
  confidencePercent: 70,
  confluence: const ['trendPullback'],
  regime: 'trend',
  rationale: 'physical SOL canary',
  invalidation: 'planned stop',
  accountEquity: 29.81,
  riskPercent: 0.1,
  riskBudget: 0.10,
  leverage: 10,
  expectedMargin: 1.702,
  passedGates: const ['isolated-margin', 'protection-ready'],
  blockedGates: const [],
  appVersion: '1.2.0-rc.2',
  strategyRulesVersion: 'v1',
  positionId: 'sol-position',
  entryOrderId: 'sol-entry-order',
  clientId: 'q-local-sol',
);

TradingJournalEvent _entry() => TradingJournalEvent(
  eventId: 'sol-entry',
  journalTradeId: 'local-live:sol-position',
  type: TradingJournalEventType.entryFilled,
  occurredAt: DateTime.utc(2026, 8, 7, 15),
  recordedAt: DateTime.utc(2026, 8, 7, 15),
  source: TradingJournalFactSource.exchange,
  quality: TradingJournalFactQuality.confirmed,
  scope: TradingJournalScope.position,
  currency: 'USDT',
  asOf: DateTime.utc(2026, 8, 7, 15),
  positionId: 'sol-position',
  orderId: 'sol-entry-order',
  quantity: 0.23,
  price: 74.00,
  remainingQuantity: 0.23,
);
