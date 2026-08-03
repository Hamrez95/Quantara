import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/trading_journal/data/trading_journal_export.dart';
import 'package:quantara_app/features/trading_journal/data/trading_journal_store.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  TradingJournalPlan plan(String id) => TradingJournalPlan(
    journalTradeId: id,
    setupId: 'setup-$id',
    analysisVersion: 'v1',
    symbol: 'XRPUSDT',
    market: 'USDT_PERPETUAL',
    timeframe: '15m',
    direction: TradingJournalDirection.short,
    strategy: 'structureZones',
    cadence: 'balanced',
    source: TradingJournalSource.localLive,
    decidedAt: DateTime.utc(2026, 8, 3),
    decisionPrice: 1.0665,
    entryLower: 1.066,
    entryUpper: 1.067,
    plannedEntry: 1.0665,
    originalStopLoss: 1.0691,
    targets: const [1.0603, 1.0567, 1.0531],
    expectedRMultiples: const [2.38, 3.77, 5.15],
    confidencePercent: 80,
    confluence: const ['15m', '1h'],
    regime: 'trend',
    rationale: 'fixture',
    invalidation: 'fixture',
    accountEquity: 100,
    riskPercent: 0.5,
    riskBudget: 0.5,
    leverage: 10,
    expectedMargin: 2.3,
    passedGates: const ['isolated'],
    blockedGates: const [],
    appVersion: '1.2.0',
    strategyRulesVersion: 'rules-1',
  );

  TradingJournalEvent fill(String eventId, String exchangeId) =>
      TradingJournalEvent(
        eventId: eventId,
        journalTradeId: 'journal-1',
        type: TradingJournalEventType.takeProfitFilled,
        occurredAt: DateTime.utc(2026, 8, 3, 10),
        recordedAt: DateTime.utc(2026, 8, 3, 10, 0, 1),
        source: TradingJournalFactSource.exchange,
        quality: TradingJournalFactQuality.confirmed,
        scope: TradingJournalScope.position,
        currency: 'USDT',
        asOf: DateTime.utc(2026, 8, 3, 10),
        exchangeEventId: exchangeId,
        positionId: 'position-1',
        orderId: 'tp-1',
        tradeId: exchangeId,
        quantity: 10,
        price: 1.0603,
        grossPnl: 0.1,
        fee: 0.01,
        remainingQuantity: 5,
        details: const {'targetIndex': 1},
      );

  test(
    'dual-slot store commits atomically and reloads latest generation',
    () async {
      final store = SharedPreferencesTradingJournalStore();
      await store.replace(
        TradingJournalLedger.empty().appendPlan(plan('journal-1')),
      );
      await store.appendEvent(fill('local-1', 'trade-1'));

      final restored = await SharedPreferencesTradingJournalStore().load();

      expect(restored.plans, hasLength(1));
      expect(restored.events, hasLength(1));
      expect(restored.events.single.tradeId, 'trade-1');
      expect(restored.generation, greaterThanOrEqualTo(2));
    },
  );

  test('corrupt active slot falls back to previous verified slot', () async {
    final store = SharedPreferencesTradingJournalStore();
    await store.replace(
      TradingJournalLedger.empty().appendPlan(plan('journal-1')),
    );
    await store.appendEvent(fill('local-1', 'trade-1'));

    final preferences = await SharedPreferences.getInstance();
    final active = preferences.getString(tradingJournalActiveSlotKey);
    expect(active, anyOf('a', 'b'));
    await preferences.setString(
      active == 'a' ? tradingJournalSlotAKey : tradingJournalSlotBKey,
      '{malformed',
    );

    final restored = await SharedPreferencesTradingJournalStore().load();

    expect(restored.plans.single.journalTradeId, 'journal-1');
    expect(restored.integrity, isNot(TradingJournalIntegrity.unverified));
    expect(restored.warnings, isNotEmpty);
  });

  test('crash before pointer flip keeps old committed snapshot', () async {
    final store = SharedPreferencesTradingJournalStore();
    await store.replace(
      TradingJournalLedger.empty().appendPlan(plan('journal-1')),
    );
    final before = await store.load();

    final preferences = await SharedPreferences.getInstance();
    final active = preferences.getString(tradingJournalActiveSlotKey)!;
    final inactiveKey = active == 'a'
        ? tradingJournalSlotBKey
        : tradingJournalSlotAKey;
    final uncommitted = before.appendEvent(fill('local-1', 'trade-1'));
    await preferences.setString(
      inactiveKey,
      TradingJournalEnvelope.fromLedger(uncommitted).encode(),
    );

    final restored = await SharedPreferencesTradingJournalStore().load();

    expect(restored.events, isEmpty);
    expect(restored.generation, before.generation);
  });

  test('append retry is idempotent across store reconstruction', () async {
    final firstStore = SharedPreferencesTradingJournalStore();
    await firstStore.replace(
      TradingJournalLedger.empty().appendPlan(plan('journal-1')),
    );
    await firstStore.appendEvent(fill('local-1', 'trade-1'));

    final secondStore = SharedPreferencesTradingJournalStore();
    await secondStore.appendEvent(fill('retry-local', 'trade-1'));
    final restored = await secondStore.load();

    expect(restored.events, hasLength(1));
  });

  test('privacy export round-trips journal but excludes secrets', () {
    final ledger = TradingJournalLedger.empty()
        .appendPlan(plan('journal-1'))
        .appendEvent(fill('local-1', 'trade-1'));

    final jsonText = TradingJournalExport.toPrivacySafeJson(ledger);
    final csvText = TradingJournalExport.toPrivacySafeCsv(ledger);
    final restored = TradingJournalExport.fromPrivacySafeJson(jsonText);
    final decoded = jsonDecode(jsonText) as Map<String, Object?>;

    expect(restored.plans, hasLength(1));
    expect(restored.events, hasLength(1));
    expect(decoded.keys, containsAll(['schemaVersion', 'plans', 'events']));
    expect(jsonText.toLowerCase(), isNot(contains('apikey')));
    expect(jsonText.toLowerCase(), isNot(contains('secretkey')));
    expect(jsonText.toLowerCase(), isNot(contains('credential')));
    expect(csvText, contains('journalTradeId'));
    expect(csvText, contains('trade-1'));
    expect(csvText.toLowerCase(), isNot(contains('secret')));
  });
}
