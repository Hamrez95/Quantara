import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/application/manual_trade_execution_controller.dart';
import 'package:quantara_app/features/auto_trade/data/bitunix_local_live_api_client.dart';
import 'package:quantara_app/features/auto_trade/data/manual_trade_execution_store.dart';
import 'package:quantara_app/features/auto_trade/data/secure_auto_trade_credentials_store.dart';
import 'package:quantara_app/features/auto_trade/domain/auto_trade_models.dart';
import 'package:quantara_app/features/auto_trade/domain/private_account_reconciliation.dart';
import 'package:quantara_app/features/auto_trade/presentation/manual_trade_execution_sheet.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';

void main() {
  final now = DateTime.utc(2026, 9, 23, 12);

  testWidgets(
    'manual trade sheet exposes RTL capital controls and TP selection',
    (tester) async {
      final controller = ManualTradeExecutionController.withGateways(
        accountGateway: _AccountGateway(_account(now)),
        exchangeGateway: const _PrepareOnlyExchangeGateway(),
        credentialsStore: const _CredentialsStore(),
        executionStore: _MemoryExecutionStore(),
        utcNow: () => now,
      );
      final setup = _setup(now);
      expect(await controller.prepare(setup), isNotNull);

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: ManualTradeExecutionSheet(
                controller: controller,
                setup: setup,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('باز کردن معامله'), findsOneWidget);
      expect(find.byKey(const Key('manual-trade-margin')), findsOneWidget);
      expect(find.byKey(const Key('manual-trade-leverage')), findsOneWidget);
      expect(find.byKey(const Key('manual-trade-tp-count')), findsOneWidget);

      await tester.tap(find.text('1 TP'));
      await tester.pump();

      expect(controller.preparation!.plan.targetCount, 1);
      expect(
        controller.preparation!.plan.targetAllocation.activeTargetCount,
        1,
      );

      await tester.enterText(
        find.byKey(const Key('manual-trade-margin')),
        '80',
      );
      await tester.pump();

      expect(controller.preparation!.plan.systemSuggested, isFalse);
      expect(controller.preparation!.plan.margin, closeTo(80, 1));

      await tester.scrollUntilVisible(
        find.byKey(const Key('manual-trade-review')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('manual-trade-review')), findsOneWidget);

      controller.dispose();
    },
  );
}

final class _AccountGateway implements ManualTradeAccountGateway {
  const _AccountGateway(this.value);

  final AutoTradeAccountSnapshot value;

  @override
  AutoTradeAccountSnapshot? get snapshot => value;

  @override
  bool get canStartNewEntry => true;

  @override
  Future<bool> reconcile({
    required PrivateAccountRefreshReason reason,
    bool force = false,
  }) async => true;
}

final class _PrepareOnlyExchangeGateway implements ManualTradeExchangeGateway {
  const _PrepareOnlyExchangeGateway();

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
  ) async => throw UnimplementedError();

  @override
  Future<void> ensureIsolatedMargin({
    required String symbol,
    required BitunixApiCredentials credentials,
  }) async => throw UnimplementedError();

  @override
  Future<void> changeLeverage({
    required String symbol,
    required int leverage,
    required BitunixApiCredentials credentials,
  }) async => throw UnimplementedError();

  @override
  Future<BitunixPlacedOrder> placeMarketEntry({
    required String symbol,
    required double quantity,
    required bool long,
    required String clientId,
    required double stopLoss,
    required BitunixApiCredentials credentials,
  }) async => throw UnimplementedError();

  @override
  Future<List<BitunixPendingProtection>> fetchPendingProtection(
    BitunixApiCredentials credentials, {
    String? symbol,
    String? positionId,
  }) async => throw UnimplementedError();

  @override
  Future<String> placePositionStop({
    required String symbol,
    required String positionId,
    required double stopLoss,
    required BitunixApiCredentials credentials,
  }) async => throw UnimplementedError();

  @override
  Future<String> placePartialTakeProfit({
    required String symbol,
    required String positionId,
    required double triggerPrice,
    required double quantity,
    required BitunixApiCredentials credentials,
  }) async => throw UnimplementedError();

  @override
  Future<BitunixOrderDetail> fetchOrderDetail({
    required String orderId,
    required BitunixApiCredentials credentials,
  }) async => throw UnimplementedError();

  @override
  Future<List<BitunixLivePosition>> fetchPositions(
    BitunixApiCredentials credentials, {
    String? symbol,
  }) async => throw UnimplementedError();

  @override
  Future<void> cancelEntryOrder({
    required String symbol,
    required String orderId,
    required String clientId,
    required BitunixApiCredentials credentials,
  }) async => throw UnimplementedError();

  @override
  Future<BitunixPlacedOrder> closePositionReduceOnly({
    required BitunixLivePosition position,
    required String clientId,
    required BitunixApiCredentials credentials,
  }) async => throw UnimplementedError();
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

final class _CredentialsStore implements AutoTradeCredentialsStore {
  const _CredentialsStore();

  @override
  Future<BitunixApiCredentials?> load() async =>
      const BitunixApiCredentials(apiKey: '12345678', secretKey: 'abcdefgh');

  @override
  Future<void> save(BitunixApiCredentials credentials) async {}

  @override
  Future<void> clear() async {}
}

SignalJournalEntry _setup(DateTime now) => SignalJournalEntry(
  setupId: 'setup-widget-540',
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
