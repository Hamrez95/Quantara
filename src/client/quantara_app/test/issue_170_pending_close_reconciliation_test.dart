import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_models.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_projection.dart';

void main() {
  test(
    'repeated exchange-closed observation is idempotent across restart time',
    () {
      final initial = TradingJournalLedger.empty()
          .appendPlan(_plan())
          .appendEvent(_entry());
      final first = initial.appendEvent(
        _pendingClose(
          DateTime.utc(2026, 8, 7, 15, 30),
          historyAvailable: false,
        ),
      );
      final replay = first.appendEvent(
        _pendingClose(DateTime.utc(2026, 8, 7, 15, 31), historyAvailable: true),
      );

      expect(first.integrity, TradingJournalIntegrity.verified);
      expect(replay.integrity, TradingJournalIntegrity.verified);
      expect(replay.events.length, first.events.length);
      expect(replay.generation, first.generation);
      final projected = TradingJournalProjector.project(
        ledger: replay,
        journalTradeId: 'local-live:sol-position',
      );
      expect(projected.state, TradingJournalTradeState.closed);
      expect(projected.netPnl, isNull);
      expect(projected.closeReason, TradingJournalCloseReason.unknown);
    },
  );

  test(
    'verified older stop fill supersedes later pending close observation',
    () {
      final pending = TradingJournalLedger.empty()
          .appendPlan(_plan())
          .appendEvent(_entry())
          .appendEvent(
            _pendingClose(
              DateTime.utc(2026, 8, 7, 15, 30),
              historyAvailable: false,
            ),
          );
      final authoritativeClose = TradingJournalEvent(
        eventId: 'fill:sol-stop-fill',
        journalTradeId: 'local-live:sol-position',
        type: TradingJournalEventType.positionClosed,
        occurredAt: DateTime.utc(2026, 8, 7, 15, 25),
        recordedAt: DateTime.utc(2026, 8, 7, 15, 32),
        source: TradingJournalFactSource.exchange,
        quality: TradingJournalFactQuality.confirmed,
        scope: TradingJournalScope.position,
        currency: 'USDT',
        asOf: DateTime.utc(2026, 8, 7, 15, 32),
        exchangeEventId: 'sol-stop-fill',
        positionId: 'sol-position',
        orderId: 'sol-stop-order',
        tradeId: 'sol-stop-fill',
        quantity: 0.23,
        price: 73.62,
        grossPnl: -0.0874,
        fee: 0.02037156,
        remainingQuantity: 0,
        details: const {'closeReason': 'stop'},
      );
      final reconciled = pending
          .appendEvent(authoritativeClose)
          .appendEvent(
            TradingJournalEvent(
              eventId: 'funding:sol-position:1',
              journalTradeId: 'local-live:sol-position',
              type: TradingJournalEventType.fundingApplied,
              occurredAt: DateTime.utc(2026, 8, 7, 15, 25),
              recordedAt: DateTime.utc(2026, 8, 7, 15, 32),
              source: TradingJournalFactSource.exchange,
              quality: TradingJournalFactQuality.confirmed,
              scope: TradingJournalScope.position,
              currency: 'USDT',
              asOf: DateTime.utc(2026, 8, 7, 15, 32),
              exchangeEventId: 'funding:sol-position:1',
              positionId: 'sol-position',
              funding: 0,
            ),
          );
      final replay = reconciled.appendEvent(authoritativeClose);
      final projected = TradingJournalProjector.project(
        ledger: replay,
        journalTradeId: 'local-live:sol-position',
      );

      expect(replay.integrity, TradingJournalIntegrity.verified);
      expect(replay.events.length, reconciled.events.length);
      expect(projected.state, TradingJournalTradeState.closed);
      expect(projected.closeReason, TradingJournalCloseReason.stop);
      expect(projected.closedAt, DateTime.utc(2026, 8, 7, 15, 25));
      expect(projected.holdingDuration, const Duration(minutes: 25));
      expect(projected.netPnl, closeTo(-0.10777156, 0.00000001));
      expect(projected.priceMovePercent, closeTo(-0.5135135, 0.000001));
    },
  );
}

TradingJournalEvent _pendingClose(
  DateTime at, {
  required bool historyAvailable,
}) => TradingJournalEvent(
  eventId: 'exchange-close-observed:sol-position',
  journalTradeId: 'local-live:sol-position',
  type: TradingJournalEventType.positionClosed,
  occurredAt: at,
  recordedAt: at,
  source: TradingJournalFactSource.exchange,
  quality: TradingJournalFactQuality.confirmed,
  scope: TradingJournalScope.position,
  currency: 'USDT',
  asOf: at,
  exchangeEventId: 'exchange-close-observed:sol-position',
  positionId: 'sol-position',
  remainingQuantity: 0,
  details: {
    'closeReason': 'unknown',
    'economicsPending': true,
    'closedHistoryAvailable': historyAvailable,
  },
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
  decisionPrice: 74,
  entryLower: 74,
  entryUpper: 74,
  plannedEntry: 74,
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
  exchangeEventId: 'entry-order:sol-entry-order',
  positionId: 'sol-position',
  orderId: 'sol-entry-order',
  quantity: 0.23,
  price: 74,
  remainingQuantity: 0.23,
);
