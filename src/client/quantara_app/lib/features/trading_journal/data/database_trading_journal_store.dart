import '../../../core/persistence/quantara_database_provider.dart';
import '../../../core/persistence/quantara_durable_database.dart';
import '../domain/trading_journal_models.dart';
import 'trading_journal_store.dart';

final class DatabaseTradingJournalStore implements TradingJournalStore {
  DatabaseTradingJournalStore({
    Future<QuantaraDurableDatabase> Function()? databaseFactory,
    TradingJournalStore? legacyStore,
  }) : _databaseFactory =
           databaseFactory ?? (() => QuantaraDatabaseProvider.instance),
       _legacyStore = legacyStore ?? SharedPreferencesTradingJournalStore();

  static const _key = 'ledger';
  final Future<QuantaraDurableDatabase> Function() _databaseFactory;
  final TradingJournalStore _legacyStore;
  static Future<void> _globalTail = Future<void>.value();

  @override
  Future<TradingJournalLedger> load() async {
    await _globalTail;
    final database = await _databaseFactory();
    final record = await database.read(QuantaraDurableCategory.journal, _key);
    if (record != null) {
      return TradingJournalLedger.fromJson(record.payload);
    }
    final legacy = await _legacyStore.load();
    if (legacy.plans.isEmpty &&
        legacy.events.isEmpty &&
        legacy.generation == 0 &&
        legacy.warnings.isEmpty) {
      return legacy;
    }
    await _write(database, legacy, minimumRevision: 1);
    return legacy;
  }

  @override
  Future<void> replace(TradingJournalLedger ledger) => _serial(() async {
    final database = await _databaseFactory();
    await _write(database, ledger);
  });

  @override
  Future<void> appendPlan(TradingJournalPlan plan) => _serial(() async {
    final database = await _databaseFactory();
    final current = await _loadCanonical(database);
    await _write(database, current.appendPlan(plan));
  });

  @override
  Future<void> appendEvent(TradingJournalEvent event) => _serial(() async {
    final database = await _databaseFactory();
    final current = await _loadCanonical(database);
    await _write(database, current.appendEvent(event));
  });

  Future<TradingJournalLedger> _loadCanonical(
    QuantaraDurableDatabase database,
  ) async {
    final record = await database.read(QuantaraDurableCategory.journal, _key);
    if (record != null) return TradingJournalLedger.fromJson(record.payload);
    final legacy = await _legacyStore.load();
    if (legacy.plans.isNotEmpty ||
        legacy.events.isNotEmpty ||
        legacy.generation > 0 ||
        legacy.warnings.isNotEmpty) {
      await _write(database, legacy, minimumRevision: 1);
    }
    return legacy;
  }

  Future<void> _write(
    QuantaraDurableDatabase database,
    TradingJournalLedger ledger, {
    int minimumRevision = 0,
  }) async {
    final existing = await database.read(
      QuantaraDurableCategory.journal,
      _key,
    );
    final revision = existing == null
        ? (ledger.generation > minimumRevision
              ? ledger.generation
              : minimumRevision)
        : existing.revision + 1;
    final persisted = ledger.withGeneration(
      ledger.generation >= revision ? ledger.generation : revision,
    );
    await database.put(
      QuantaraDurableRecord(
        category: QuantaraDurableCategory.journal,
        key: _key,
        schemaVersion: persisted.schemaVersion,
        revision: revision,
        updatedAt: DateTime.now().toUtc(),
        payload: persisted.toJson(),
      ),
    );
  }

  Future<void> _serial(Future<void> Function() operation) {
    final result = _globalTail.then((_) => operation());
    _globalTail = result.catchError((Object _) {});
    return result;
  }
}
