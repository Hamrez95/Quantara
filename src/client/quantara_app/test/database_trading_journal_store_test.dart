import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:quantara_app/core/persistence/quantara_durable_database.dart';
import 'package:quantara_app/features/trading_journal/data/database_trading_journal_store.dart';
import 'package:quantara_app/features/trading_journal/data/trading_journal_store.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_models.dart';

void main() {
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

  test('legacy journal migrates once and database remains authoritative', () async {
    final database = SembastQuantaraDurableDatabase(
      factory: databaseFactoryMemory,
      path: 'journal-migration.db',
    );
    await database.initialize();
    final legacy = _MemoryTradingJournalStore(
      TradingJournalLedger.empty().appendPlan(plan('journal-1')),
    );
    final store = DatabaseTradingJournalStore(
      databaseFactory: () async => database,
      legacyStore: legacy,
    );

    final migrated = await store.load();
    final durable = await database.read(
      QuantaraDurableCategory.journal,
      'ledger',
    );

    expect(migrated.plans.single.journalTradeId, 'journal-1');
    expect(durable, isNotNull);
    expect(durable!.revision, greaterThanOrEqualTo(1));
    expect(legacy.replaceCalls, 1);

    legacy.ledger = TradingJournalLedger.empty().appendPlan(plan('legacy-only'));
    final reloaded = await DatabaseTradingJournalStore(
      databaseFactory: () async => database,
      legacyStore: legacy,
    ).load();

    expect(reloaded.plans.single.journalTradeId, 'journal-1');
    expect(legacy.loadCalls, 1);
  });

  test('database append is idempotent and mirrors verified state', () async {
    final database = SembastQuantaraDurableDatabase(
      factory: databaseFactoryMemory,
      path: 'journal-append.db',
    );
    await database.initialize();
    final legacy = _MemoryTradingJournalStore(TradingJournalLedger.empty());
    final store = DatabaseTradingJournalStore(
      databaseFactory: () async => database,
      legacyStore: legacy,
    );

    await store.appendPlan(plan('journal-1'));
    await store.appendEvent(fill('local-1', 'trade-1'));
    await store.appendEvent(fill('retry-local', 'trade-1'));

    final durable = await store.load();
    expect(durable.plans, hasLength(1));
    expect(durable.events, hasLength(1));
    expect(durable.events.single.tradeId, 'trade-1');
    expect(legacy.ledger.plans, hasLength(1));
    expect(legacy.ledger.events, hasLength(1));
    expect(legacy.replaceCalls, greaterThanOrEqualTo(2));
  });

  test('malformed durable journal fails closed instead of using legacy', () async {
    final database = SembastQuantaraDurableDatabase(
      factory: databaseFactoryMemory,
      path: 'journal-corruption.db',
    );
    await database.initialize();
    await database.put(
      QuantaraDurableRecord(
        category: QuantaraDurableCategory.journal,
        key: 'ledger',
        schemaVersion: 1,
        revision: 1,
        updatedAt: DateTime.utc(2026, 8, 4),
        payload: const {'schemaVersion': 1, 'generation': 'invalid'},
      ),
    );
    final legacy = _MemoryTradingJournalStore(
      TradingJournalLedger.empty().appendPlan(plan('must-not-fallback')),
    );
    final store = DatabaseTradingJournalStore(
      databaseFactory: () async => database,
      legacyStore: legacy,
    );

    await expectLater(store.load(), throwsA(anything));
    expect(legacy.loadCalls, 0);
  });
}

final class _MemoryTradingJournalStore implements TradingJournalStore {
  _MemoryTradingJournalStore(this.ledger);

  TradingJournalLedger ledger;
  int loadCalls = 0;
  int replaceCalls = 0;

  @override
  Future<TradingJournalLedger> load() async {
    loadCalls++;
    return ledger;
  }

  @override
  Future<void> replace(TradingJournalLedger value) async {
    replaceCalls++;
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
