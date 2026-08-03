import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/domain/auto_trade_models.dart';
import 'package:quantara_app/features/auto_trade/domain/local_live_trade_models.dart';
import 'package:quantara_app/features/auto_trade/domain/trading_pnl_projection.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';
import 'package:quantara_app/features/trading_journal/application/local_live_journal_observer.dart';
import 'package:quantara_app/features/trading_journal/data/trading_journal_export.dart';
import 'package:quantara_app/features/trading_journal/data/trading_journal_store.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_models.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_projection.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final openedAt = DateTime.utc(2026, 8, 3, 10);

  TradingJournalPlan plan() => TradingJournalPlan(
    journalTradeId: 'local-live:position-1',
    setupId: 'setup-1',
    analysisVersion: 'rules-1',
    symbol: 'XRPUSDT',
    market: 'USDT_PERPETUAL',
    timeframe: '15m',
    direction: TradingJournalDirection.short,
    strategy: 'structureZones',
    cadence: 'local-live',
    source: TradingJournalSource.localLive,
    decidedAt: openedAt,
    decisionPrice: 1.0665,
    entryLower: 1.066,
    entryUpper: 1.067,
    plannedEntry: 1.0665,
    originalStopLoss: 1.0691,
    targets: const [1.0603, 1.0567, 1.0531],
    expectedRMultiples: const [2.38, 3.77, 5.15],
    confidencePercent: 82,
    confluence: const ['15m structure', '1h agreement'],
    regime: 'directionalTrend',
    rationale: 'fixture',
    invalidation: 'fixture',
    accountEquity: 100,
    riskPercent: 0.5,
    riskBudget: 0.5,
    leverage: 10,
    expectedMargin: 2.2823,
    passedGates: const ['isolated', 'full-protection'],
    blockedGates: const [],
    appVersion: '1.2.0-rc.2+121',
    strategyRulesVersion: 'rules-1',
    positionId: 'position-1',
    entryOrderId: 'entry-order',
    clientId: 'client-entry',
  );

  LocalLiveManagedPosition managed() => LocalLiveManagedPosition(
    setupId: 'setup-1',
    symbol: 'XRPUSDT',
    timeframe: '15m',
    direction: TradeDirection.short,
    positionId: 'position-1',
    entryOrderId: 'entry-order',
    clientId: 'client-entry',
    initialQuantity: 21.4,
    entryPrice: 1.0665,
    originalStopLoss: 1.0691,
    targets: const [1.0603, 1.0567, 1.0531],
    leverage: 10,
    openedAt: openedAt,
    stopOrderId: 'stop-1',
    targetQuantities: const [13.91, 4.28, 3.21],
    targetOrderIds: const ['tp-1', 'tp-2', 'tp-3'],
  );

  TradingJournalEvent event({
    required String id,
    required TradingJournalEventType type,
    required DateTime at,
    double? gross,
    double? fee,
    double? funding,
  }) => TradingJournalEvent(
    eventId: id,
    journalTradeId: 'local-live:position-1',
    type: type,
    occurredAt: at,
    recordedAt: at,
    source: TradingJournalFactSource.exchange,
    quality: TradingJournalFactQuality.confirmed,
    scope: TradingJournalScope.position,
    currency: 'USDT',
    asOf: at,
    exchangeEventId: id,
    positionId: 'position-1',
    grossPnl: gross,
    fee: fee,
    funding: funding,
  );

  test('net remains unavailable until fee and funding are explicit facts', () {
    var ledger = TradingJournalLedger.empty().appendPlan(plan());
    ledger = ledger.appendEvent(
      event(
        id: 'tp-fill',
        type: TradingJournalEventType.takeProfitFilled,
        at: openedAt.add(const Duration(minutes: 20)),
        gross: 0.1,
        fee: 0.01,
      ),
    );

    final incomplete = TradingJournalProjector.project(
      ledger: ledger,
      journalTradeId: plan().journalTradeId,
    );
    expect(incomplete.grossPnl, 0.1);
    expect(incomplete.fees, 0.01);
    expect(incomplete.funding, isNull);
    expect(incomplete.netPnl, isNull);

    ledger = ledger.appendEvent(
      event(
        id: 'funding-zero',
        type: TradingJournalEventType.fundingApplied,
        at: openedAt.add(const Duration(minutes: 21)),
        funding: 0,
      ),
    );
    final complete = TradingJournalProjector.project(
      ledger: ledger,
      journalTradeId: plan().journalTradeId,
    );
    expect(complete.funding, 0);
    expect(complete.netPnl, closeTo(0.09, 0.000001));
  });

  test('observer includes entry fee in authoritative final net', () async {
    final store = _MemoryJournalStore(
      TradingJournalLedger.empty().appendPlan(plan()),
    );
    final observer = LocalLiveJournalObserver(store: store);
    final projection = TradingPnlProjection.reconcile(
      currency: 'USDT',
      asOf: openedAt.add(const Duration(hours: 1)),
      unrealizedByPosition: const {},
      fills: [
        ExchangePnlFill(
          tradeId: 'trade-entry',
          orderId: 'entry-order',
          positionId: 'position-1',
          symbol: 'XRPUSDT',
          quantity: 21.4,
          price: 1.0665,
          realizedPnl: 0,
          fee: 0.004,
          reduceOnly: false,
          occurredAt: openedAt.add(const Duration(minutes: 1)),
        ),
        ExchangePnlFill(
          tradeId: 'trade-tp1',
          orderId: 'tp-1',
          positionId: 'position-1',
          symbol: 'XRPUSDT',
          quantity: 13.91,
          price: 1.0603,
          realizedPnl: 0.1,
          fee: 0.009,
          reduceOnly: true,
          occurredAt: openedAt.add(const Duration(minutes: 20)),
        ),
        ExchangePnlFill(
          tradeId: 'trade-stop',
          orderId: 'stop-1',
          positionId: 'position-1',
          symbol: 'XRPUSDT',
          quantity: 7.49,
          price: 1.0646,
          realizedPnl: -0.05,
          fee: 0.004,
          reduceOnly: true,
          occurredAt: openedAt.add(const Duration(minutes: 45)),
        ),
      ],
      settlements: [
        ExchangePositionSettlement(
          positionId: 'position-1',
          symbol: 'XRPUSDT',
          funding: -0.002,
          openedAt: openedAt,
          closedAt: openedAt.add(const Duration(minutes: 45)),
          realizedPnl: 0.05,
          fee: 0.017,
        ),
      ],
    );

    await observer.reconcilePosition(
      managed: managed(),
      positionPnl: projection.forPositionId('position-1')!,
      positionClosed: true,
    );

    final journal = TradingJournalProjector.project(
      ledger: store.ledger,
      journalTradeId: plan().journalTradeId,
    );
    expect(journal.grossPnl, closeTo(0.05, 0.000001));
    expect(journal.fees, closeTo(0.017, 0.000001));
    expect(journal.funding, closeTo(-0.002, 0.000001));
    expect(journal.netPnl, closeTo(0.031, 0.000001));
  });

  test('only the final non-target exit fill closes the position', () async {
    final store = _MemoryJournalStore(
      TradingJournalLedger.empty().appendPlan(plan()),
    );
    final observer = LocalLiveJournalObserver(store: store);
    final projection = TradingPnlProjection.reconcile(
      currency: 'USDT',
      asOf: openedAt.add(const Duration(hours: 1)),
      unrealizedByPosition: const {},
      fills: [
        ExchangePnlFill(
          tradeId: 'trade-entry-multi-close',
          orderId: 'entry-order',
          positionId: 'position-1',
          symbol: 'XRPUSDT',
          quantity: 21.4,
          price: 1.0665,
          realizedPnl: 0,
          fee: 0.004,
          reduceOnly: false,
          occurredAt: openedAt.add(const Duration(minutes: 1)),
        ),
        ExchangePnlFill(
          tradeId: 'trade-stop-part-1',
          orderId: 'stop-1',
          positionId: 'position-1',
          symbol: 'XRPUSDT',
          quantity: 10,
          price: 1.0688,
          realizedPnl: -0.1,
          fee: 0.005,
          reduceOnly: true,
          occurredAt: openedAt.add(const Duration(minutes: 40)),
        ),
        ExchangePnlFill(
          tradeId: 'trade-stop-part-2',
          orderId: 'stop-1',
          positionId: 'position-1',
          symbol: 'XRPUSDT',
          quantity: 11.4,
          price: 1.0691,
          realizedPnl: -0.114,
          fee: 0.006,
          reduceOnly: true,
          occurredAt: openedAt.add(const Duration(minutes: 41)),
        ),
      ],
      settlements: [
        ExchangePositionSettlement(
          positionId: 'position-1',
          symbol: 'XRPUSDT',
          funding: 0,
          openedAt: openedAt,
          closedAt: openedAt.add(const Duration(minutes: 41)),
          realizedPnl: -0.214,
          fee: 0.015,
        ),
      ],
    );

    await observer.reconcilePosition(
      managed: managed(),
      positionPnl: projection.forPositionId('position-1')!,
      positionClosed: true,
    );

    final firstExit = store.ledger.events.singleWhere(
      (item) => item.tradeId == 'trade-stop-part-1',
    );
    final finalExit = store.ledger.events.singleWhere(
      (item) => item.tradeId == 'trade-stop-part-2',
    );
    expect(firstExit.type, TradingJournalEventType.positionPartiallyClosed);
    expect(firstExit.remainingQuantity, closeTo(11.4, 0.000001));
    expect(finalExit.type, TradingJournalEventType.positionClosed);
    expect(finalExit.remainingQuantity, 0);
  });

  test(
    'profit-lock confirmation identity never conflicts with original stop',
    () async {
      var initial = TradingJournalLedger.empty().appendPlan(plan());
      initial = initial.appendEvent(
        TradingJournalEvent(
          eventId: 'original-stop',
          journalTradeId: plan().journalTradeId,
          type: TradingJournalEventType.stopConfirmed,
          occurredAt: openedAt,
          recordedAt: openedAt,
          source: TradingJournalFactSource.exchange,
          quality: TradingJournalFactQuality.confirmed,
          scope: TradingJournalScope.position,
          currency: 'USDT',
          asOf: openedAt,
          exchangeEventId: 'stop-order:stop-1',
          positionId: 'position-1',
          orderId: 'stop-1',
          price: 1.0691,
        ),
      );
      final store = _MemoryJournalStore(initial);
      final observer = LocalLiveJournalObserver(store: store);

      await observer.recordStopMove(
        managed: managed(),
        stage: 1,
        previousStop: 1.0691,
        proposedStop: 1.0646,
        confirmed: true,
        reason: 'TP1 profit lock',
        orderId: 'stop-1',
      );

      expect(store.ledger.integrity, TradingJournalIntegrity.verified);
      expect(store.ledger.events, hasLength(2));
    },
  );

  test(
    'journal plan persistence failure never escapes into trade management',
    () async {
      final store = _MemoryJournalStore(
        TradingJournalLedger.empty(),
        failPlanWrites: true,
      );
      final observer = LocalLiveJournalObserver(store: store);
      final idea = TradeIdea(
        symbol: 'XRPUSDT',
        timeframe: '15m',
        direction: TradeDirection.short,
        confidencePercent: 82,
        entryLower: 1.066,
        entryUpper: 1.067,
        stopLoss: 1.0691,
        targets: const [1.0603, 1.0567, 1.0531],
        riskReward: 2.38,
        maximumLoss: 0.5,
        positionSize: 21.4,
        notionalValue: 22.8231,
        recommendedLeverage: 10,
        maximumSafeLeverage: 10,
        requiredMargin: 2.28231,
        estimatedRoundTripCosts: 0.017,
        setupId: 'setup-1',
        candleClosedAt: openedAt,
        summary: 'fixture',
        invalidation: 'fixture',
        reasons: const ['15m structure'],
      );
      final account = AutoTradeAccountSnapshot(
        marginCoin: 'USDT',
        available: 100,
        frozen: 0,
        positionMargin: 0,
        crossUnrealizedPnl: 0,
        isolatedUnrealizedPnl: 0,
        positionMode: 'HEDGE',
        positions: const [],
        orders: const [],
        syncedAt: openedAt,
      );

      await expectLater(
        observer.recordProtectedPosition(
          idea: idea,
          managed: managed(),
          account: account,
          riskPercent: 0.5,
        ),
        completes,
      );
      expect(store.ledger.plans, isEmpty);
      expect(store.ledger.events, isEmpty);
    },
  );

  test('recursive privacy export removes nested secret-like fields', () {
    var ledger = TradingJournalLedger.empty().appendPlan(plan());
    ledger = ledger.appendEvent(
      TradingJournalEvent(
        eventId: 'nested-details',
        journalTradeId: plan().journalTradeId,
        type: TradingJournalEventType.manualNote,
        occurredAt: openedAt,
        recordedAt: openedAt,
        source: TradingJournalFactSource.user,
        quality: TradingJournalFactQuality.userEntered,
        scope: TradingJournalScope.journal,
        currency: 'USDT',
        asOf: openedAt,
        details: const {
          'safe': 'kept',
          'nested': {
            'apiKey': 'must-not-export',
            'deeper': [
              {'accessToken': 'must-not-export-either'},
            ],
          },
        },
      ),
    );

    final exported = TradingJournalExport.toPrivacySafeJson(ledger);
    expect(exported, contains('kept'));
    expect(exported, isNot(contains('must-not-export')));
    expect(exported.toLowerCase(), isNot(contains('apikey')));
    expect(exported.toLowerCase(), isNot(contains('accesstoken')));
  });

  test(
    'a recovered valid slot remains available after the next crash',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = SharedPreferencesTradingJournalStore();
      await store.replace(TradingJournalLedger.empty().appendPlan(plan()));
      await store.appendEvent(
        event(
          id: 'first-event',
          type: TradingJournalEventType.manualNote,
          at: openedAt,
        ),
      );

      final preferences = await SharedPreferences.getInstance();
      var active = preferences.getString(tradingJournalActiveSlotKey)!;
      await preferences.setString(
        active == 'a' ? tradingJournalSlotAKey : tradingJournalSlotBKey,
        '{corrupt-active',
      );

      await store.appendEvent(
        event(
          id: 'second-event',
          type: TradingJournalEventType.manualNote,
          at: openedAt.add(const Duration(minutes: 1)),
        ),
      );
      active = preferences.getString(tradingJournalActiveSlotKey)!;
      await preferences.setString(
        active == 'a' ? tradingJournalSlotAKey : tradingJournalSlotBKey,
        '{crash-during-next-write',
      );

      final recovered = await SharedPreferencesTradingJournalStore().load();
      expect(recovered.plans.single.journalTradeId, plan().journalTradeId);
      expect(recovered.integrity, TradingJournalIntegrity.recovered);
    },
  );
}

final class _MemoryJournalStore implements TradingJournalStore {
  _MemoryJournalStore(this.ledger, {this.failPlanWrites = false});

  TradingJournalLedger ledger;
  final bool failPlanWrites;

  @override
  Future<TradingJournalLedger> load() async => ledger;

  @override
  Future<void> replace(TradingJournalLedger next) async {
    ledger = next;
  }

  @override
  Future<void> appendPlan(TradingJournalPlan plan) async {
    if (failPlanWrites) throw StateError('simulated journal failure');
    ledger = ledger.appendPlan(plan);
  }

  @override
  Future<void> appendEvent(TradingJournalEvent event) async {
    ledger = ledger.appendEvent(event);
  }
}
