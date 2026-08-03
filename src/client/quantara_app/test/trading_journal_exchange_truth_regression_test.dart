import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/domain/local_live_trade_models.dart';
import 'package:quantara_app/features/auto_trade/domain/trading_pnl_projection.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';
import 'package:quantara_app/features/trading_journal/application/local_live_journal_observer.dart';
import 'package:quantara_app/features/trading_journal/data/trading_journal_store.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_models.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_projection.dart';

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

  test(
    'unverified PnL creates only a stale marker and later confirmed fill remains conflict-free',
    () async {
      final store = _MemoryJournalStore(
        TradingJournalLedger.empty().appendPlan(plan()),
      );
      final observer = LocalLiveJournalObserver(store: store);
      final ambiguous = TradingPnlProjection.reconcile(
        currency: 'USDT',
        asOf: openedAt.add(const Duration(minutes: 30)),
        unrealizedByPosition: const {},
        fills: [
          ExchangePnlFill(
            tradeId: 'same-trade-id',
            orderId: 'stop-1',
            positionId: 'position-1',
            symbol: 'XRPUSDT',
            quantity: 21.4,
            price: 1.0691,
            realizedPnl: -0.2,
            fee: 0.01,
            reduceOnly: true,
            occurredAt: openedAt.add(const Duration(minutes: 29)),
          ),
          ExchangePnlFill(
            tradeId: 'same-trade-id',
            orderId: 'stop-1',
            positionId: 'position-1',
            symbol: 'XRPUSDT',
            quantity: 21.4,
            price: 1.0691,
            realizedPnl: -0.3,
            fee: 0.01,
            reduceOnly: true,
            occurredAt: openedAt.add(const Duration(minutes: 29)),
          ),
        ],
        settlements: const [],
      );
      final ambiguousPosition = ambiguous.forPositionId('position-1')!;
      expect(ambiguousPosition.isVerified, isFalse);

      await observer.reconcilePosition(
        managed: managed(),
        positionPnl: ambiguousPosition,
        positionClosed: true,
      );

      expect(store.ledger.events, hasLength(1));
      expect(
        store.ledger.events.single.type,
        TradingJournalEventType.staleDetected,
      );
      expect(
        store.ledger.events.single.quality,
        TradingJournalFactQuality.stale,
      );
      expect(store.ledger.events.single.tradeId, isNull);
      expect(store.ledger.integrity, TradingJournalIntegrity.verified);

      final confirmed = TradingPnlProjection.reconcile(
        currency: 'USDT',
        asOf: openedAt.add(const Duration(minutes: 31)),
        unrealizedByPosition: const {},
        fills: [
          ExchangePnlFill(
            tradeId: 'same-trade-id',
            orderId: 'stop-1',
            positionId: 'position-1',
            symbol: 'XRPUSDT',
            quantity: 21.4,
            price: 1.0691,
            realizedPnl: -0.2,
            fee: 0.01,
            reduceOnly: true,
            occurredAt: openedAt.add(const Duration(minutes: 29)),
          ),
        ],
        settlements: [
          ExchangePositionSettlement(
            positionId: 'position-1',
            symbol: 'XRPUSDT',
            funding: 0,
            openedAt: openedAt,
            closedAt: openedAt.add(const Duration(minutes: 29)),
            realizedPnl: -0.2,
            fee: 0.01,
          ),
        ],
      );
      final confirmedPosition = confirmed.forPositionId('position-1')!;
      expect(confirmedPosition.isVerified, isTrue);

      await observer.reconcilePosition(
        managed: managed(),
        positionPnl: confirmedPosition,
        positionClosed: true,
      );

      final exchangeFill = store.ledger.events.singleWhere(
        (event) => event.tradeId == 'same-trade-id',
      );
      expect(exchangeFill.quality, TradingJournalFactQuality.confirmed);
      expect(exchangeFill.type, TradingJournalEventType.positionClosed);
      expect(store.ledger.integrity, TradingJournalIntegrity.verified);
    },
  );

  test(
    'emergency request remains open until its exchange fill is confirmed',
    () async {
      final store = _MemoryJournalStore(
        TradingJournalLedger.empty().appendPlan(plan()),
      );
      final observer = LocalLiveJournalObserver(store: store);

      await observer.recordLifecycle(
        managed: managed(),
        type: TradingJournalEventType.positionClosed,
        identity: 'emergency-close-request:position-1',
        message: 'Reduce-only emergency close submitted.',
        quality: TradingJournalFactQuality.calculated,
      );

      final request = store.ledger.events.single;
      expect(request.type, TradingJournalEventType.reconciliationStarted);
      expect(
        request.details['requestedType'],
        TradingJournalEventType.positionClosed.name,
      );
      final beforeFill = TradingJournalProjector.project(
        ledger: store.ledger,
        journalTradeId: plan().journalTradeId,
      );
      expect(beforeFill.state, isNot(TradingJournalTradeState.closed));

      final confirmed = TradingPnlProjection.reconcile(
        currency: 'USDT',
        asOf: openedAt.add(const Duration(minutes: 15)),
        unrealizedByPosition: const {},
        fills: [
          ExchangePnlFill(
            tradeId: 'emergency-fill-1',
            orderId: 'emergency-order-1',
            positionId: 'position-1',
            symbol: 'XRPUSDT',
            quantity: 21.4,
            price: 1.067,
            realizedPnl: -0.01,
            fee: 0.01,
            reduceOnly: true,
            occurredAt: openedAt.add(const Duration(minutes: 14)),
            clientId: 'client-entry-emergency-close',
          ),
        ],
        settlements: [
          ExchangePositionSettlement(
            positionId: 'position-1',
            symbol: 'XRPUSDT',
            funding: 0,
            openedAt: openedAt,
            closedAt: openedAt.add(const Duration(minutes: 14)),
            realizedPnl: -0.01,
            fee: 0.01,
          ),
        ],
      );

      await observer.reconcilePosition(
        managed: managed(),
        positionPnl: confirmed.forPositionId('position-1')!,
        positionClosed: true,
      );

      final fill = store.ledger.events.singleWhere(
        (event) => event.tradeId == 'emergency-fill-1',
      );
      expect(fill.type, TradingJournalEventType.positionClosed);
      expect(
        fill.details['closeReason'],
        TradingJournalCloseReason.emergency.name,
      );
      final afterFill = TradingJournalProjector.project(
        ledger: store.ledger,
        journalTradeId: plan().journalTradeId,
      );
      expect(afterFill.state, TradingJournalTradeState.closed);
      expect(afterFill.closeReason, TradingJournalCloseReason.emergency);
    },
  );
}

final class _MemoryJournalStore implements TradingJournalStore {
  _MemoryJournalStore(this.ledger);

  TradingJournalLedger ledger;

  @override
  Future<TradingJournalLedger> load() async => ledger;

  @override
  Future<void> replace(TradingJournalLedger next) async {
    ledger = next;
  }

  @override
  Future<void> appendPlan(TradingJournalPlan plan) async {
    ledger = ledger.appendPlan(plan);
  }

  @override
  Future<void> appendEvent(TradingJournalEvent event) async {
    ledger = ledger.appendEvent(event);
  }
}
