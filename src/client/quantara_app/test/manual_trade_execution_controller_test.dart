import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:quantara_app/features/auto_trade/application/auto_trade_controller.dart';
import 'package:quantara_app/features/auto_trade/application/manual_trade_execution_controller.dart';
import 'package:quantara_app/features/auto_trade/data/bitunix_local_live_api_client.dart';
import 'package:quantara_app/features/auto_trade/data/bitunix_private_api_client.dart';
import 'package:quantara_app/features/auto_trade/data/manual_trade_execution_store.dart';
import 'package:quantara_app/features/auto_trade/data/secure_auto_trade_credentials_store.dart';
import 'package:quantara_app/features/auto_trade/domain/auto_trade_models.dart';
import 'package:quantara_app/features/auto_trade/domain/private_account_reconciliation.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';
import 'package:quantara_app/features/trading_journal/application/manual_trade_journal_observer.dart';
import 'package:quantara_app/features/trading_journal/data/trading_journal_store.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_models.dart';

void main() {
  final now = DateTime.utc(2026, 9, 20, 16);

  test(
    'explicit confirmation opens one position with selected TP count',
    () async {
      final account = _account(now);
      final accountController = _FakeAccountController(account);
      final exchange = _FakeExchange();
      final executionStore = _MemoryExecutionStore();
      final journalStore = _MemoryJournalStore();
      final controller = ManualTradeExecutionController(
        accountController: accountController,
        exchange: exchange,
        credentialsStore: _FakeCredentialsStore(),
        executionStore: executionStore,
        journalObserver: ManualTradeJournalObserver(store: journalStore),
        utcNow: () => now,
      );

      final prepared = await controller.prepare(_setup(now));

      expect(prepared, isNotNull);
      expect(prepared!.plan.allowed, isTrue);
      controller.recalculate(margin: 100, leverage: 5, targetCount: 2);
      expect(controller.preparation!.plan.allowed, isTrue);

      final receipt = await controller.confirmAndExecute();

      expect(receipt, isNotNull);
      expect(receipt!.targetOrderIds, hasLength(2));
      expect(exchange.entryCalls, 1);
      expect(exchange.takeProfitCalls, 2);
      expect(exchange.closeCalls, 0);
      expect(exchange.changedLeverage, 5);
      expect(executionStore.record!.state, ManualTradeExecutionState.protected);
      expect(executionStore.record!.positionId, 'position-1');
      expect(journalStore.ledger.plans.single.setupId, 'setup-540');
      expect(
        journalStore.ledger.plans.single.source,
        TradingJournalSource.manual,
      );
      expect(journalStore.ledger.plans.single.positionId, 'position-1');

      controller.dispose();
      accountController.dispose();
    },
  );

  test(
    'ambiguous previous submit stays blocked even when current account is flat',
    () async {
      final account = _account(now);
      final accountController = _FakeAccountController(account);
      final exchange = _FakeExchange();
      final executionStore = _MemoryExecutionStore()
        ..record = ManualTradeExecutionRecord(
          setupId: 'setup-540',
          symbol: 'BTCUSDT',
          clientId: 'q-manual-deadbeef',
          state: ManualTradeExecutionState.ambiguous,
          updatedAtUtc: now.subtract(const Duration(minutes: 5)),
          margin: 100,
          leverage: 5,
          targetCount: 2,
        );
      final controller = ManualTradeExecutionController(
        accountController: accountController,
        exchange: exchange,
        credentialsStore: _FakeCredentialsStore(),
        executionStore: executionStore,
        journalObserver: ManualTradeJournalObserver(
          store: _MemoryJournalStore(),
        ),
        utcNow: () => now,
        exchangePollDelay: Duration.zero,
      );

      final prepared = await controller.prepare(_setup(now));

      expect(prepared, isNull);
      expect(controller.error, contains('ambiguous'));
      expect(exchange.entryCalls, 0);

      controller.dispose();
      accountController.dispose();
    },
  );

  test(
    'unverified selected TP ladder closes the new exposure fail-closed',
    () async {
      final account = _account(now);
      final accountController = _FakeAccountController(account);
      final exchange = _FakeExchange(confirmTargets: false);
      final executionStore = _MemoryExecutionStore();
      final controller = ManualTradeExecutionController(
        accountController: accountController,
        exchange: exchange,
        credentialsStore: _FakeCredentialsStore(),
        executionStore: executionStore,
        journalObserver: ManualTradeJournalObserver(
          store: _MemoryJournalStore(),
        ),
        utcNow: () => now,
        exchangePollDelay: Duration.zero,
      );

      expect(await controller.prepare(_setup(now)), isNotNull);
      controller.recalculate(margin: 100, leverage: 5, targetCount: 2);

      final receipt = await controller.confirmAndExecute();

      expect(receipt, isNull);
      expect(exchange.takeProfitCalls, 2);
      expect(exchange.closeCalls, 1);
      expect(
        executionStore.record!.state,
        ManualTradeExecutionState.failedSafe,
      );
      expect(controller.error, contains('SL/TP ladder'));

      controller.dispose();
      accountController.dispose();
    },
  );

  test('protected setup cannot be submitted twice', () async {
    final account = _account(now);
    final accountController = _FakeAccountController(account);
    final exchange = _FakeExchange();
    final executionStore = _MemoryExecutionStore();
    final controller = ManualTradeExecutionController(
      accountController: accountController,
      exchange: exchange,
      credentialsStore: _FakeCredentialsStore(),
      executionStore: executionStore,
      journalObserver: ManualTradeJournalObserver(store: _MemoryJournalStore()),
      utcNow: () => now,
      exchangePollDelay: Duration.zero,
    );

    expect(await controller.prepare(_setup(now)), isNotNull);
    expect(await controller.confirmAndExecute(), isNotNull);
    expect(exchange.entryCalls, 1);

    final second = await controller.prepare(_setup(now));

    expect(second, isNull);
    expect(controller.error, contains('already opened'));
    expect(exchange.entryCalls, 1);

    controller.dispose();
    accountController.dispose();
  });
}

final class _FakeAccountController extends AutoTradeController {
  _FakeAccountController(this.value)
    : super(
        apiClient: BitunixPrivateApiClient(client: http.Client()),
        credentialsStore: _FakeCredentialsStore(),
      );

  final AutoTradeAccountSnapshot value;

  @override
  AutoTradeAccountSnapshot? get snapshot => value;

  @override
  bool get isConnected => true;

  @override
  bool get canStartNewEntry => true;

  @override
  Future<bool> reconcile({
    required PrivateAccountRefreshReason reason,
    bool force = false,
  }) async => true;
}

final class _FakeCredentialsStore implements AutoTradeCredentialsStore {
  const _FakeCredentialsStore();

  @override
  Future<BitunixApiCredentials?> load() async =>
      const BitunixApiCredentials(apiKey: '12345678', secretKey: 'abcdefgh');

  @override
  Future<void> save(BitunixApiCredentials credentials) async {}

  @override
  Future<void> clear() async {}
}

final class _MemoryExecutionStore implements ManualTradeExecutionStore {
  ManualTradeExecutionRecord? record;

  @override
  Future<ManualTradeExecutionRecord?> load(String setupId) async =>
      record?.setupId == setupId ? record : null;

  @override
  Future<void> save(ManualTradeExecutionRecord value) async {
    record = value;
  }
}

final class _MemoryJournalStore implements TradingJournalStore {
  TradingJournalLedger ledger = TradingJournalLedger.empty();

  @override
  Future<TradingJournalLedger> load() async => ledger;

  @override
  Future<void> replace(TradingJournalLedger value) async {
    ledger = value;
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

final class _FakeExchange extends BitunixLocalLiveApiClient {
  _FakeExchange({this.confirmTargets = true}) : super(client: http.Client());

  final bool confirmTargets;
  int entryCalls = 0;
  int takeProfitCalls = 0;
  int closeCalls = 0;
  int changedLeverage = 0;
  BitunixLivePosition? position;
  final List<BitunixPendingProtection> protections = [];

  @override
  Future<double> fetchMarkPrice(String symbol) async => 100;

  @override
  Future<BitunixInstrumentRules> fetchInstrumentRules(String symbol) async =>
      const BitunixInstrumentRules(
        symbol: 'BTCUSDT',
        minimumQuantity: 0.001,
        maximumMarketQuantity: 1000,
        quantityPrecision: 3,
        pricePrecision: 1,
        minimumLeverage: 1,
        maximumLeverage: 50,
        open: true,
        apiSupported: true,
      );

  @override
  Future<AutoTradeAccountSnapshot> fetchCurrentAccountSnapshot(
    BitunixApiCredentials credentials,
  ) async => _account(DateTime.utc(2026, 9, 20, 16));

  @override
  Future<void> ensureIsolatedMargin({
    required String symbol,
    required BitunixApiCredentials credentials,
  }) async {}

  @override
  Future<void> changeLeverage({
    required String symbol,
    required int leverage,
    required BitunixApiCredentials credentials,
  }) async {
    changedLeverage = leverage;
  }

  @override
  Future<BitunixPlacedOrder> placeMarketEntry({
    required String symbol,
    required double quantity,
    required bool long,
    required String clientId,
    required double stopLoss,
    required BitunixApiCredentials credentials,
  }) async {
    entryCalls++;
    position = BitunixLivePosition(
      positionId: 'position-1',
      symbol: symbol,
      quantity: quantity,
      side: long ? 'LONG' : 'SHORT',
      marginMode: 'ISOLATION',
      positionMode: 'HEDGE',
      leverage: changedLeverage,
      averageOpenPrice: 100,
      realizedPnl: 0,
      unrealizedPnl: 0,
      fee: 0,
      funding: 0,
      openedAt: DateTime.utc(2026, 9, 20, 16),
    );
    protections.add(
      BitunixPendingProtection(
        orderId: 'stop-entry',
        positionId: 'position-1',
        symbol: symbol,
        takeProfitPrice: 0,
        stopLossPrice: stopLoss,
        takeProfitQuantity: 0,
        stopLossQuantity: quantity,
      ),
    );
    return BitunixPlacedOrder(orderId: 'entry-1', clientId: clientId);
  }

  @override
  Future<BitunixOrderDetail> fetchOrderDetail({
    required String orderId,
    required BitunixApiCredentials credentials,
  }) async => BitunixOrderDetail(
    orderId: orderId,
    clientId: 'client',
    symbol: 'BTCUSDT',
    quantity: position!.quantity,
    filledQuantity: position!.quantity,
    status: 'FILLED',
    fee: 0,
    realizedPnl: 0,
  );

  @override
  Future<List<BitunixLivePosition>> fetchPositions(
    BitunixApiCredentials credentials, {
    String? symbol,
  }) async => position == null ? const [] : [position!];

  @override
  Future<List<BitunixPendingProtection>> fetchPendingProtection(
    BitunixApiCredentials credentials, {
    String? symbol,
    String? positionId,
  }) async => List.unmodifiable(protections);

  @override
  Future<String> placePositionStop({
    required String symbol,
    required String positionId,
    required double stopLoss,
    required BitunixApiCredentials credentials,
  }) async => 'stop-fallback';

  @override
  Future<String> placePartialTakeProfit({
    required String symbol,
    required String positionId,
    required double triggerPrice,
    required double quantity,
    required BitunixApiCredentials credentials,
  }) async {
    takeProfitCalls++;
    final id = 'tp-$takeProfitCalls';
    if (confirmTargets) {
      protections.add(
        BitunixPendingProtection(
          orderId: id,
          positionId: positionId,
          symbol: symbol,
          takeProfitPrice: triggerPrice,
          stopLossPrice: 0,
          takeProfitQuantity: quantity,
          stopLossQuantity: 0,
        ),
      );
    }
    return id;
  }

  @override
  Future<BitunixPlacedOrder> closePositionReduceOnly({
    required BitunixLivePosition position,
    required String clientId,
    required BitunixApiCredentials credentials,
  }) async {
    closeCalls++;
    this.position = null;
    return BitunixPlacedOrder(orderId: position.positionId, clientId: clientId);
  }
}

SignalJournalEntry _setup(DateTime now) => SignalJournalEntry(
  setupId: 'setup-540',
  symbol: 'BTCUSDT',
  timeframe: '1h',
  direction: TradeDirection.long,
  strategy: AnalysisStrategy.trendPullback,
  strategyVersion: 'trend-pullback/test',
  createdAt: now.subtract(const Duration(minutes: 5)),
  validUntil: now.add(const Duration(hours: 2)),
  entryLower: 99.5,
  entryUpper: 100.5,
  stopLoss: 98,
  targets: const [104, 108, 112],
  maximumLoss: 100,
  positionSize: 40,
  notionalValue: 4000,
  estimatedRoundTripCosts: 9.2,
  recommendedLeverage: 5,
  maximumSafeLeverage: 10,
  selectedLeverage: 5,
  summary: 'fixture',
  invalidation: 'fixture',
  setupQualityScore: 80,
  confidencePercent: 80,
  sizingCapital: 10000,
  outcome: SignalOutcome.pendingEntry,
);

AutoTradeAccountSnapshot _account(DateTime syncedAt) =>
    AutoTradeAccountSnapshot(
      marginCoin: 'USDT',
      available: 5000,
      frozen: 0,
      positionMargin: 0,
      crossUnrealizedPnl: 0,
      isolatedUnrealizedPnl: 0,
      positionMode: 'HEDGE',
      positions: const [],
      orders: const [],
      syncedAt: syncedAt,
    );
