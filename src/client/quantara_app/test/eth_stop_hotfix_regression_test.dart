import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/domain/trading_pnl_projection.dart';
import 'package:quantara_app/features/trading_journal/application/trading_journal_exchange_backfill.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_models.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_projection.dart';

void main() {
  test(
    'unassigned historical trade does not poison a verified ETH closure',
    () {
      final pnl = _positionScopedPnl();

      expect(pnl.isVerified, isTrue);
      expect(pnl.forPositionId('eth-position')?.isVerified, isTrue);
      expect(
        pnl.forPositionId('unassigned-trade:old-gram')?.isVerified,
        isFalse,
      );

      final result = TradingJournalExchangeBackfill.reconcileVerifiedClosures(
        ledger: TradingJournalLedger.empty()
            .appendPlan(_ethPlan())
            .appendEvent(_ethEntry()),
        pnlProjection: pnl,
        openPositionIds: const {},
        recordedAt: DateTime.utc(2026, 8, 5, 17),
      );
      final journal = TradingJournalProjector.project(
        ledger: result.ledger,
        journalTradeId: 'local-live:eth-position',
      );

      expect(result.closedTradeIds, ['local-live:eth-position']);
      expect(journal.state, TradingJournalTradeState.closed);
      expect(journal.closeReason, TradingJournalCloseReason.stop);
      expect(journal.remainingQuantity, 0);
      expect(journal.grossPnl, closeTo(-0.18645, 0.00000001));
      expect(journal.fees, closeTo(0.0132, 0.00000001));
      expect(journal.netPnl, closeTo(-0.19965, 0.00000001));
      expect(journal.timeline.last.quantity, 0.011);
      expect(journal.timeline.last.price, 1884.25);
    },
  );

  test('replayed protection confirmation is idempotent across timestamps', () {
    final first = _tpConfirmation(DateTime.utc(2026, 8, 5, 14, 30));
    final replay = _tpConfirmation(DateTime.utc(2026, 8, 5, 14, 31));
    final ledger = TradingJournalLedger.empty().appendEvent(first);
    final afterReplay = ledger.appendEvent(replay);

    expect(afterReplay.generation, ledger.generation);
    expect(afterReplay.integrity, TradingJournalIntegrity.verified);
    expect(afterReplay.warnings, isEmpty);
  });

  test('loads and repairs the legacy benign TP replay warning', () {
    final event = _tpConfirmation(DateTime.utc(2026, 8, 5, 14, 30));
    final json = TradingJournalLedger.empty().appendEvent(event).toJson()
      ..['integrity'] = TradingJournalIntegrity.unverified.name
      ..['warnings'] = [
        'Conflicting journal event identity exchange:tp-order:tp-2.',
      ];

    final repaired = TradingJournalLedger.fromJson(json);

    expect(repaired.integrity, TradingJournalIntegrity.verified);
    expect(repaired.warnings, isEmpty);
    expect(repaired.events, hasLength(1));
  });
}

TradingPnlProjection _positionScopedPnl() => TradingPnlProjection.reconcile(
  currency: 'USDT',
  asOf: DateTime.utc(2026, 8, 5, 16, 45),
  unrealizedByPosition: const {},
  fills: [
    ExchangePnlFill(
      tradeId: 'eth-stop-trade',
      orderId: 'eth-stop-order',
      positionId: 'eth-position',
      symbol: 'ETHUSDT',
      quantity: 0.011,
      price: 1884.25,
      realizedPnl: -0.18645,
      fee: 0.0132,
      reduceOnly: true,
      occurredAt: DateTime.utc(2026, 8, 5, 16, 40),
      side: 'BUY',
    ),
    ExchangePnlFill(
      tradeId: 'old-gram',
      orderId: 'old-gram-order',
      positionId: 'unassigned-trade:old-gram',
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
      positionId: 'eth-position',
      symbol: 'ETHUSDT',
      funding: 0,
      openedAt: DateTime.utc(2026, 8, 5, 14, 30),
      closedAt: DateTime.utc(2026, 8, 5, 16, 40),
      realizedPnl: -0.18645,
      fee: 0.0132,
    ),
  ],
  sourceVerified: true,
  warning: 'Trade old-gram could not be assigned to one exchange position.',
);

TradingJournalPlan _ethPlan() => TradingJournalPlan(
  journalTradeId: 'local-live:eth-position',
  setupId: 'eth-setup',
  analysisVersion: 'v1',
  symbol: 'ETHUSDT',
  market: 'USDT_PERPETUAL',
  timeframe: '1h',
  direction: TradingJournalDirection.short,
  strategy: 'structureZones',
  cadence: 'local-live',
  source: TradingJournalSource.localLive,
  decidedAt: DateTime.utc(2026, 8, 5, 14, 30),
  decisionPrice: 1867.3,
  entryLower: 1867.3,
  entryUpper: 1867.3,
  plannedEntry: 1867.3,
  originalStopLoss: 1884.25,
  targets: const [1807.539003938152, 1830.039844424859, 1845],
  expectedRMultiples: const [3, 2, 1],
  confidencePercent: 70,
  confluence: const ['1h'],
  regime: 'transition',
  rationale: 'physical ETH canary',
  invalidation: 'stop',
  accountEquity: 29.73,
  riskPercent: 0.1,
  riskBudget: 0.02973,
  leverage: 10,
  expectedMargin: 2.05403,
  passedGates: const ['isolated-margin'],
  blockedGates: const [],
  appVersion: '1.2.0-rc.2',
  strategyRulesVersion: 'v1',
  positionId: 'eth-position',
  entryOrderId: 'eth-entry-order',
  clientId: 'q-local-eth',
);

TradingJournalEvent _ethEntry() => TradingJournalEvent(
  eventId: 'eth-entry',
  journalTradeId: 'local-live:eth-position',
  type: TradingJournalEventType.entryFilled,
  occurredAt: DateTime.utc(2026, 8, 5, 14, 30),
  recordedAt: DateTime.utc(2026, 8, 5, 14, 30),
  source: TradingJournalFactSource.exchange,
  quality: TradingJournalFactQuality.confirmed,
  scope: TradingJournalScope.position,
  currency: 'USDT',
  asOf: DateTime.utc(2026, 8, 5, 14, 30),
  exchangeEventId: 'entry-order:eth-entry-order',
  positionId: 'eth-position',
  orderId: 'eth-entry-order',
  quantity: 0.011,
  price: 1867.3,
  remainingQuantity: 0.011,
);

TradingJournalEvent _tpConfirmation(DateTime occurredAt) => TradingJournalEvent(
  eventId: 'tp-confirmed:tp-2',
  journalTradeId: 'local-live:eth-position',
  type: TradingJournalEventType.takeProfitConfirmed,
  occurredAt: occurredAt,
  recordedAt: occurredAt,
  source: TradingJournalFactSource.exchange,
  quality: TradingJournalFactQuality.confirmed,
  scope: TradingJournalScope.position,
  currency: 'USDT',
  asOf: occurredAt,
  exchangeEventId: 'tp-order:tp-2',
  positionId: 'eth-position',
  orderId: 'tp-2',
  quantity: 0.011,
  price: 1830.039844424859,
  details: const {'targetIndex': 2},
);
