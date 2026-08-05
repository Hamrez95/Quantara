import 'dart:async';
import 'dart:convert';

import '../../../core/persistence/quantara_database_provider.dart';
import '../../../core/persistence/quantara_durable_database.dart';
import '../domain/trading_journal_models.dart';
import 'trading_journal_store.dart';

TradingJournalLedger mergeTradingJournalLedgers(
  TradingJournalLedger durable,
  TradingJournalLedger foregroundMirror,
) {
  var merged = durable;
  for (final plan in foregroundMirror.plans) {
    merged = merged.appendPlan(plan);
  }
  for (final event in foregroundMirror.events) {
    merged = merged.appendEvent(event);
  }
  for (final warning in foregroundMirror.warnings) {
    if (merged.warnings.contains(warning)) continue;
    merged = foregroundMirror.integrity == TradingJournalIntegrity.unverified
        ? merged.withIntegrityWarning(warning)
        : merged.withRecoveryWarning(warning);
  }
  if (foregroundMirror.integrity == TradingJournalIntegrity.unverified &&
      foregroundMirror.warnings.isEmpty &&
      merged.integrity != TradingJournalIntegrity.unverified) {
    merged = merged.withIntegrityWarning(
      'Foreground journal mirror reported unverified integrity.',
    );
  }
  final highestGeneration = [
    durable.generation,
    foregroundMirror.generation,
    merged.generation,
  ].reduce((left, right) => left > right ? left : right);
  return merged.withGeneration(highestGeneration);
}

bool _sameLedger(TradingJournalLedger left, TradingJournalLedger right) =>
    jsonEncode(left.toJson()) == jsonEncode(right.toJson());

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
  Future<TradingJournalLedger> load() => _serialValue(() async {
    final database = await _databaseFactory();
    final record = await database.read(QuantaraDurableCategory.journal, _key);
    final foregroundMirror = await _legacyStore.load();
    if (record == null) {
      if (_isEmpty(foregroundMirror)) return foregroundMirror;
      return _write(database, foregroundMirror, minimumRevision: 1);
    }
    final durable = TradingJournalLedger.fromJson(record.payload);
    final merged = mergeTradingJournalLedgers(durable, foregroundMirror);
    if (_sameLedger(durable, merged)) return durable;
    return _write(database, merged);
  });

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
    final foregroundMirror = await _legacyStore.load();
    if (record == null) {
      if (_isEmpty(foregroundMirror)) return foregroundMirror;
      return _write(database, foregroundMirror, minimumRevision: 1);
    }
    final durable = TradingJournalLedger.fromJson(record.payload);
    final merged = mergeTradingJournalLedgers(durable, foregroundMirror);
    if (_sameLedger(durable, merged)) return durable;
    return _write(database, merged);
  }

  Future<TradingJournalLedger> _write(
    QuantaraDurableDatabase database,
    TradingJournalLedger ledger, {
    int minimumRevision = 0,
  }) async {
    final existing = await database.read(QuantaraDurableCategory.journal, _key);
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
    try {
      await _legacyStore.replace(persisted);
    } on Object {
      // The durable database is authoritative. The temporary rollback mirror
      // must never make a verified database commit appear to have failed.
    }
    return persisted;
  }

  Future<void> _serial(Future<void> Function() operation) {
    final result = _globalTail.then((_) => operation());
    _globalTail = result.catchError((Object _) {});
    return result;
  }

  Future<T> _serialValue<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    final result = _globalTail.then((_) async {
      try {
        completer.complete(await operation());
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    _globalTail = result.catchError((Object _) {});
    return completer.future;
  }

  static bool _isEmpty(TradingJournalLedger ledger) =>
      ledger.plans.isEmpty &&
      ledger.events.isEmpty &&
      ledger.generation == 0 &&
      ledger.warnings.isEmpty;
}
