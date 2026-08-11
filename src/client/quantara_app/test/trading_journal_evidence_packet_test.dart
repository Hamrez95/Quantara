import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_evidence_packet.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_models.dart';

void main() {
  test('evidence packet separates raw facts and derived SOL diagnostics', () {
    var ledger = TradingJournalLedger.empty().appendPlan(_plan());
    ledger = ledger
        .appendEvent(_entry())
        .appendEvent(_close())
        .appendEvent(_funding());
    final packet = TradingJournalEvidencePacketBuilder.buildAll(ledger).single;
    final indicator = packet['indicatorSnapshot']! as Map<String, Object?>;
    final post = packet['postTrade']! as Map<String, Object?>;
    final review = packet['reviewFacts']! as Map<String, Object?>;

    expect(packet['rawFacts'], isA<Map<String, Object?>>());
    expect(indicator['captured'], isFalse);
    expect((indicator['values']! as Map).isEmpty, isTrue);
    expect(post['closed'], isTrue);
    expect(post['closeReason'], 'stop');
    expect(post['netPnl'], closeTo(-0.10777156, 0.00000001));
    expect(post['durationSeconds'], 1500);
    expect(review['initialStopDistancePercent'], closeTo(0.4189189, 0.000001));
    expect(review['stopSlippagePercent'], closeTo(0.0949925363, 0.000001));
    expect(review['sampleSizeClaimMade'], isFalse);
  });
}

TradingJournalPlan _plan() => TradingJournalPlan(
  journalTradeId: 'local-live:sol-position',
  setupId: 'sol-5m',
  analysisVersion: 'v1',
  symbol: 'SOLUSDT',
  market: 'USDT_PERPETUAL',
  timeframe: '5m',
  direction: TradingJournalDirection.long,
  strategy: 'trendPullback',
  cadence: 'balanced',
  source: TradingJournalSource.localLive,
  decidedAt: DateTime.utc(2026, 8, 7, 15),
  decisionPrice: 74,
  entryLower: 74,
  entryUpper: 74,
  plannedEntry: 74,
  originalStopLoss: 73.69,
  targets: const [74.9022],
  expectedRMultiples: const [2.91],
  confidencePercent: 70,
  confluence: const ['Trend aligned', 'Pullback'],
  regime: 'trend',
  rationale: 'Trend aligned pullback',
  invalidation: 'Stop invalidates setup',
  accountEquity: 29.81,
  riskPercent: 0.1,
  riskBudget: 0.10,
  leverage: 10,
  expectedMargin: 1.702,
  passedGates: const ['isolated-margin', 'protection-ready'],
  blockedGates: const [],
  appVersion: '1.2.0-rc.2',
  strategyRulesVersion: '1.1',
  positionId: 'sol-position',
);

TradingJournalEvent _entry() => TradingJournalEvent(
  eventId: 'entry',
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
  quantity: 0.23,
  price: 74,
  remainingQuantity: 0.23,
);

TradingJournalEvent _close() => TradingJournalEvent(
  eventId: 'stop-fill',
  journalTradeId: 'local-live:sol-position',
  type: TradingJournalEventType.positionClosed,
  occurredAt: DateTime.utc(2026, 8, 7, 15, 25),
  recordedAt: DateTime.utc(2026, 8, 7, 15, 26),
  source: TradingJournalFactSource.exchange,
  quality: TradingJournalFactQuality.confirmed,
  scope: TradingJournalScope.position,
  currency: 'USDT',
  asOf: DateTime.utc(2026, 8, 7, 15, 26),
  exchangeEventId: 'stop-fill',
  positionId: 'sol-position',
  orderId: 'stop-order',
  tradeId: 'stop-fill',
  quantity: 0.23,
  price: 73.62,
  grossPnl: -0.0874,
  fee: 0.02037156,
  remainingQuantity: 0,
  details: const {'closeReason': 'stop'},
);

TradingJournalEvent _funding() => TradingJournalEvent(
  eventId: 'funding',
  journalTradeId: 'local-live:sol-position',
  type: TradingJournalEventType.fundingApplied,
  occurredAt: DateTime.utc(2026, 8, 7, 15, 25),
  recordedAt: DateTime.utc(2026, 8, 7, 15, 26),
  source: TradingJournalFactSource.exchange,
  quality: TradingJournalFactQuality.confirmed,
  scope: TradingJournalScope.position,
  currency: 'USDT',
  asOf: DateTime.utc(2026, 8, 7, 15, 26),
  exchangeEventId: 'funding',
  positionId: 'sol-position',
  funding: 0,
);
