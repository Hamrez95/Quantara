import '../../../core/persistence/quantara_database_provider.dart';
import '../../../core/persistence/quantara_durable_database.dart';
import '../domain/trading_lab_models.dart';

abstract interface class TradingLabRunStore {
  Future<TradingLabRun?> loadActive();
  Future<void> save(TradingLabRun run);
  Future<void> replaceHistory(TradingLabRun run);
  Future<List<TradingLabRun>> loadHistory({int limit = 20});
  Future<void> clearActive();
}

final class DatabaseTradingLabRunStore implements TradingLabRunStore {
  DatabaseTradingLabRunStore({
    Future<QuantaraDurableDatabase> Function()? databaseFactory,
  }) : _databaseFactory =
           databaseFactory ?? (() => QuantaraDatabaseProvider.instance);

  static const _activeKey = 'trading-lab:active:v1';
  static const _historyPrefix = 'trading-lab:run:v1:';
  final Future<QuantaraDurableDatabase> Function() _databaseFactory;
  Future<void> _tail = Future<void>.value();

  @override
  Future<TradingLabRun?> loadActive() async {
    final database = await _databaseFactory();
    final record = await database.read(
      QuantaraDurableCategory.audit,
      _activeKey,
    );
    if (record == null) return null;
    return TradingLabRun.fromJson(record.payload);
  }

  @override
  Future<void> save(TradingLabRun run) => _serial(() async {
    final database = await _databaseFactory();
    await _put(database, _activeKey, run);
    await _put(database, '$_historyPrefix${run.manifest.runId}', run);
  });

  @override
  Future<void> replaceHistory(TradingLabRun run) => _serial(() async {
    final database = await _databaseFactory();
    await _put(database, '$_historyPrefix${run.manifest.runId}', run);
  });

  @override
  Future<List<TradingLabRun>> loadHistory({int limit = 20}) async {
    if (limit < 1 || limit > 200) {
      throw ArgumentError.value(limit, 'limit');
    }
    final database = await _databaseFactory();
    final records = await database.list(
      categories: {QuantaraDurableCategory.audit},
    );
    final runs = <TradingLabRun>[];
    for (final record in records) {
      if (!record.key.startsWith(_historyPrefix)) continue;
      try {
        runs.add(TradingLabRun.fromJson(record.payload));
      } on Object {
        // One damaged historical experiment must not hide healthy runs.
      }
    }
    runs.sort(
      (left, right) =>
          right.manifest.startedAtUtc.compareTo(left.manifest.startedAtUtc),
    );
    return List.unmodifiable(runs.take(limit));
  }

  @override
  Future<void> clearActive() => _serial(() async {
    final database = await _databaseFactory();
    await database.delete(QuantaraDurableCategory.audit, _activeKey);
  });

  Future<void> _put(
    QuantaraDurableDatabase database,
    String key,
    TradingLabRun run,
  ) async {
    final existing = await database.read(QuantaraDurableCategory.audit, key);
    await database.put(
      QuantaraDurableRecord(
        category: QuantaraDurableCategory.audit,
        key: key,
        schemaVersion: tradingLabSchemaVersion,
        revision: (existing?.revision ?? 0) + 1,
        updatedAt: DateTime.now().toUtc(),
        payload: run.toJson(),
      ),
    );
  }

  Future<void> _serial(Future<void> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.catchError((Object _) {});
    return result;
  }
}
