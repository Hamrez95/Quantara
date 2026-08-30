import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_models.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_projection.dart';

void main() {
  final at = DateTime.utc(2026, 8, 3, 10);

  TradingJournalPlan xrpPlan() => TradingJournalPlan(
    journalTradeId: 'journal-xrp-20260803',
    setupId: 'setup-xrp-short',
    analysisVersion: 'owner-alpha-v1.2.0-rc.2',
    symbol: 'XRPUSDT',
    market: 'USDT_PERPETUAL',
    timeframe: '15m',
    direction: TradingJournalDirection.short,
    strategy: 'structureZones',
    cadence: 'balanced',
    source: TradingJournalSource.localLive,
    decidedAt: at,
    decisionPrice: 1.0665,
    entryLower: 1.0660,
    entryUpper: 1.0670,
    plannedEntry: 1.0665,
    originalStopLoss: 1.0691,
    targets: const [1.0603, 1.0567, 1.0531],
    expectedRMultiples: const [2.38, 3.77, 5.15],
    confidencePercent: 82,
    confluence: const ['15m structure', '1h bearish agreement'],
    regime: 'directionalTrend',
    rationale: 'Short rejection from structure resistance.',
    invalidation: '15m close above 1.0691.',
    accountEquity: 100,
    riskPercent: 0.5,
    riskBudget: 0.5,
    leverage: 10,
    expectedMargin: 2.2823,
    passedGates: const ['isolated', 'fresh-account', 'full-protection'],
    blockedGates: const [],
    appVersion: '1.2.0-rc.2+121',
    strategyRulesVersion: 'profit-lock-v2',
  );

  TradingJournalEvent event({
    required String eventId,
    required TradingJournalEventType type,
    required DateTime occurredAt,
    String? exchangeEventId,
    String? orderId,
    String? tradeId,
    double? quantity,
    double? price,
    double? grossPnl,
    double? fee,
    double? funding,
    double? remainingQuantity,
    Map<String, Object?> details = const {},
  }) => TradingJournalEvent(
    eventId: eventId,
    journalTradeId: 'journal-xrp-20260803',
    type: type,
    occurredAt: occurredAt,
    recordedAt: occurredAt.add(const Duration(seconds: 1)),
    source: TradingJournalFactSource.exchange,
    quality: TradingJournalFactQuality.confirmed,
    scope: TradingJournalScope.position,
    currency: 'USDT',
    asOf: occurredAt,
    exchangeEventId: exchangeEventId,
    positionId: 'position-xrp-1',
    orderId: orderId,
    tradeId: tradeId,
    quantity: quantity,
    price: price,
    grossPnl: grossPnl,
    fee: fee,
    funding: funding,
    remainingQuantity: remainingQuantity,
    details: details,
  );

  test('plan is immutable and survives JSON round trip', () {
    final plan = xrpPlan();
    final restored = TradingJournalPlan.fromJson(plan.toJson());

    expect(restored.journalTradeId, plan.journalTradeId);
    expect(restored.targets, const [1.0603, 1.0567, 1.0531]);
    expect(restored.originalStopLoss, 1.0691);
    expect(restored.riskBudget, 0.5);
    expect(restored.passedGates, contains('full-protection'));
    expect(restored.toJson(), plan.toJson());
  });

  test('duplicate exchange identity is idempotent', () {
    final ledger = TradingJournalLedger.empty().appendPlan(xrpPlan());
    final tp1 = event(
      eventId: 'local-tp1-a',
      type: TradingJournalEventType.takeProfitFilled,
      occurredAt: at.add(const Duration(minutes: 20)),
      exchangeEventId: 'trade-xrp-tp1',
      orderId: 'tp-order-1',
      tradeId: 'trade-xrp-tp1',
      quantity: 13.91,
      price: 1.0603,
      grossPnl: 0.100,
      fee: 0.009,
      remainingQuantity: 7.49,
      details: const {'targetIndex': 1},
    );

    final first = ledger.appendEvent(tp1);
    final duplicate = first.appendEvent(
      TradingJournalEvent.fromJson(
        tp1.toJson(),
      ).copyWith(eventId: 'retry-local-tp1'),
    );

    expect(duplicate.events, hasLength(1));
    expect(duplicate.integrity, TradingJournalIntegrity.verified);
  });

  test('conflicting duplicate exchange identity becomes unverified', () {
    var ledger = TradingJournalLedger.empty().appendPlan(xrpPlan());
    ledger = ledger.appendEvent(
      event(
        eventId: 'tp1-a',
        type: TradingJournalEventType.takeProfitFilled,
        occurredAt: at.add(const Duration(minutes: 20)),
        exchangeEventId: 'trade-xrp-tp1',
        tradeId: 'trade-xrp-tp1',
        quantity: 13.91,
        grossPnl: 0.100,
      ),
    );
    ledger = ledger.appendEvent(
      event(
        eventId: 'tp1-conflict',
        type: TradingJournalEventType.takeProfitFilled,
        occurredAt: at.add(const Duration(minutes: 20)),
        exchangeEventId: 'trade-xrp-tp1',
        tradeId: 'trade-xrp-tp1',
        quantity: 13.91,
        grossPnl: 9.999,
      ),
    );

    expect(ledger.events, hasLength(1));
    expect(ledger.integrity, TradingJournalIntegrity.unverified);
    expect(ledger.warnings.single, contains('trade-xrp-tp1'));
  });

  test('TP1 then stop keeps realized TP1 and closes only remainder', () {
    var ledger = TradingJournalLedger.empty().appendPlan(xrpPlan());
    final events = [
      event(
        eventId: 'entry',
        type: TradingJournalEventType.entryFilled,
        occurredAt: at.add(const Duration(minutes: 1)),
        exchangeEventId: 'trade-entry',
        orderId: 'entry-order',
        tradeId: 'trade-entry',
        quantity: 21.4,
        price: 1.0665,
        fee: 0.004,
        remainingQuantity: 21.4,
      ),
      event(
        eventId: 'stop-confirmed',
        type: TradingJournalEventType.stopConfirmed,
        occurredAt: at.add(const Duration(minutes: 2)),
        exchangeEventId: 'stop-order-original',
        orderId: 'stop-order-original',
        quantity: 21.4,
        price: 1.0691,
      ),
      event(
        eventId: 'tp1',
        type: TradingJournalEventType.takeProfitFilled,
        occurredAt: at.add(const Duration(minutes: 20)),
        exchangeEventId: 'trade-tp1',
        orderId: 'tp-order-1',
        tradeId: 'trade-tp1',
        quantity: 13.91,
        price: 1.0603,
        grossPnl: 0.100,
        fee: 0.009,
        remainingQuantity: 7.49,
        details: const {'targetIndex': 1},
      ),
      event(
        eventId: 'risk-free-request',
        type: TradingJournalEventType.stopMoveRequested,
        occurredAt: at.add(const Duration(minutes: 21)),
        exchangeEventId: 'promotion-intent-1',
        details: const {
          'reason': 'tp1-profit-lock',
          'previousStop': 1.0691,
          'newStop': 1.0646,
        },
      ),
      event(
        eventId: 'risk-free-confirmed',
        type: TradingJournalEventType.stopMoveConfirmed,
        occurredAt: at.add(const Duration(minutes: 22)),
        exchangeEventId: 'stop-order-profit-lock',
        orderId: 'stop-order-profit-lock',
        price: 1.0646,
        details: const {
          'reason': 'tp1-profit-lock',
          'previousStop': 1.0691,
          'newStop': 1.0646,
        },
      ),
      event(
        eventId: 'stop-close',
        type: TradingJournalEventType.positionClosed,
        occurredAt: at.add(const Duration(minutes: 45)),
        exchangeEventId: 'trade-stop-close',
        orderId: 'stop-order-profit-lock',
        tradeId: 'trade-stop-close',
        quantity: 7.49,
        price: 1.0646,
        grossPnl: -0.050,
        fee: 0.004,
        funding: -0.002,
        remainingQuantity: 0,
        details: const {'closeReason': 'stop'},
      ),
    ];
    for (final value in events.reversed) {
      ledger = ledger.appendEvent(value);
    }

    final projection = TradingJournalProjector.project(
      ledger: ledger,
      journalTradeId: xrpPlan().journalTradeId,
    );

    expect(projection.timeline.map((item) => item.eventId), [
      'entry',
      'stop-confirmed',
      'tp1',
      'risk-free-request',
      'risk-free-confirmed',
      'stop-close',
    ]);
    expect(projection.state, TradingJournalTradeState.closed);
    expect(projection.highestTargetReached, 1);
    expect(projection.initialQuantity, closeTo(21.4, 0.000001));
    expect(projection.remainingQuantity, 0);
    expect(projection.grossPnl, closeTo(0.050, 0.000001));
    expect(projection.fees, closeTo(0.017, 0.000001));
    expect(projection.funding, closeTo(-0.002, 0.000001));
    expect(projection.netPnl, closeTo(0.031, 0.000001));
    expect(projection.closeReason, TradingJournalCloseReason.stop);
    expect(projection.profitLockConfirmed, isTrue);
    expect(projection.realizedR, isNotNull);
    expect(projection.holdingDuration, const Duration(minutes: 44));
    expect(projection.integrity, TradingJournalIntegrity.verified);
  });
}
