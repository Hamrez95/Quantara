import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/trading_journal/data/database_trading_journal_store.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_models.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_projection.dart';

void main() {
  test('imports a newer foreground close event into durable journal', () {
    final plan = _plan();
    final entry = _event(
      eventId: 'entry',
      type: TradingJournalEventType.entryFilled,
      remainingQuantity: 42.9,
      price: 1.40,
    );
    final close = _event(
      eventId: 'stop-close',
      type: TradingJournalEventType.positionClosed,
      remainingQuantity: 0,
      price: 1.389,
      grossPnl: -0.2574,
      fee: 0.03575286,
      details: const {'closeReason': 'stop'},
    );
    final durable = TradingJournalLedger.empty()
        .appendPlan(plan)
        .appendEvent(entry);
    final foreground = durable.appendEvent(close);

    final merged = mergeTradingJournalLedgers(durable, foreground);
    final projection = TradingJournalProjector.project(
      ledger: merged,
      journalTradeId: plan.journalTradeId,
    );

    expect(
      merged.events.where((item) => item.eventId == 'stop-close'),
      hasLength(1),
    );
    expect(projection.state, TradingJournalTradeState.closed);
    expect(projection.closeReason, TradingJournalCloseReason.stop);
    expect(projection.remainingQuantity, 0);
    expect(projection.grossPnl, -0.2574);
    expect(projection.fees, 0.03575286);
  });
}

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
  targets: const [1.419, 1.41005, 1.42826],
  expectedRMultiples: const [1, 2, 3],
  confidencePercent: 70,
  confluence: const ['test'],
  regime: 'transition',
  rationale: 'physical canary regression',
  invalidation: 'stop',
  accountEquity: 29.81,
  riskPercent: 0.1,
  riskBudget: 0.02981,
  leverage: 10,
  expectedMargin: 6.006,
  passedGates: const ['isolated-margin'],
  blockedGates: const [],
  appVersion: 'test',
  strategyRulesVersion: 'v1',
  positionId: 'gram-position',
  entryOrderId: 'entry-order',
  clientId: 'q-local-gram',
);

TradingJournalEvent _event({
  required String eventId,
  required TradingJournalEventType type,
  required double remainingQuantity,
  required double price,
  double? grossPnl,
  double? fee,
  Map<String, Object?> details = const {},
}) => TradingJournalEvent(
  eventId: eventId,
  journalTradeId: 'local-live:gram-position',
  type: type,
  occurredAt: type == TradingJournalEventType.positionClosed
      ? DateTime.utc(2026, 8, 5, 3, 19, 14)
      : DateTime.utc(2026, 8, 5, 2),
  recordedAt: DateTime.utc(2026, 8, 5, 3, 20),
  source: TradingJournalFactSource.exchange,
  quality: TradingJournalFactQuality.confirmed,
  scope: TradingJournalScope.position,
  currency: 'USDT',
  asOf: DateTime.utc(2026, 8, 5, 3, 20),
  exchangeEventId: eventId,
  positionId: 'gram-position',
  orderId: eventId,
  tradeId: eventId,
  quantity: 42.9,
  price: price,
  grossPnl: grossPnl,
  fee: fee,
  funding: type == TradingJournalEventType.positionClosed ? 0 : null,
  remainingQuantity: remainingQuantity,
  details: details,
);
