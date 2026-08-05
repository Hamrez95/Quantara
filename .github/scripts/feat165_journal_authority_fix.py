from pathlib import Path

root = Path('src/client/quantara_app')


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{path}: expected one anchor, found {count}')
    path.write_text(text.replace(old, new, 1))


store_contract = root / 'lib/features/trading_journal/data/trading_journal_store.dart'
text = store_contract.read_text()
if 'ForegroundTradingJournalMirror' not in text:
    replace_once(
        store_contract,
        '''abstract interface class TradingJournalStore {
  Future<TradingJournalLedger> load();
  Future<void> replace(TradingJournalLedger ledger);
  Future<void> appendPlan(TradingJournalPlan plan);
  Future<void> appendEvent(TradingJournalEvent event);
}
''',
        '''abstract interface class TradingJournalStore {
  Future<TradingJournalLedger> load();
  Future<void> replace(TradingJournalLedger ledger);
  Future<void> appendPlan(TradingJournalPlan plan);
  Future<void> appendEvent(TradingJournalEvent event);
}

/// Marks the device-local foreground-service mirror. A durable store may read
/// this mirror only to import newer Local Live facts; generic legacy stores
/// remain migration-only and can never override database truth.
abstract interface class ForegroundTradingJournalMirror {}
''',
    )
    replace_once(
        store_contract,
        '''final class SharedPreferencesTradingJournalStore
    implements TradingJournalStore {''',
        '''final class SharedPreferencesTradingJournalStore
    implements TradingJournalStore, ForegroundTradingJournalMirror {''',
    )

store = root / 'lib/features/trading_journal/data/database_trading_journal_store.dart'
text = store.read_text()
start = text.index('TradingJournalLedger mergeTradingJournalLedgers(')
end = text.index('\nfinal class DatabaseTradingJournalStore', start)
new_helper = '''TradingJournalLedger mergeTradingJournalLedgers(
  TradingJournalLedger durable,
  TradingJournalLedger foregroundMirror, {
  DateTime? newerThan,
}) {
  if (durable.integrity == TradingJournalIntegrity.unverified ||
      foregroundMirror.integrity == TradingJournalIntegrity.unverified) {
    return durable;
  }
  var merged = durable;
  bool isNewer(DateTime timestamp) =>
      newerThan == null || timestamp.toUtc().isAfter(newerThan.toUtc());

  for (final plan in foregroundMirror.plans) {
    if (plan.source != TradingJournalSource.localLive ||
        !isNewer(plan.decidedAt)) {
      continue;
    }
    merged = merged.appendPlan(plan);
  }
  final knownTradeIds = merged.plans
      .map((plan) => plan.journalTradeId)
      .toSet();
  for (final event in foregroundMirror.events) {
    if (!knownTradeIds.contains(event.journalTradeId) ||
        !isNewer(event.recordedAt)) {
      continue;
    }
    merged = merged.appendEvent(event);
  }
  return merged;
}

bool _sameLedger(TradingJournalLedger left, TradingJournalLedger right) =>
    jsonEncode(left.toJson()) == jsonEncode(right.toJson());
'''
store.write_text(text[:start] + new_helper + text[end:])

text = store.read_text()
old_load = '''  @override
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
  });'''
new_load = '''  @override
  Future<TradingJournalLedger> load() => _serialValue(() async {
    final database = await _databaseFactory();
    final record = await database.read(QuantaraDurableCategory.journal, _key);
    if (record == null) {
      final legacy = await _legacyStore.load();
      if (_isEmpty(legacy)) return legacy;
      return _write(database, legacy, minimumRevision: 1);
    }
    if (_legacyStore is! ForegroundTradingJournalMirror) {
      return TradingJournalLedger.fromJson(record.payload);
    }
    final durable = TradingJournalLedger.fromJson(record.payload);
    if (durable.integrity == TradingJournalIntegrity.unverified) {
      return durable;
    }
    final foregroundMirror = await _legacyStore.load();
    final merged = mergeTradingJournalLedgers(
      durable,
      foregroundMirror,
      newerThan: record.updatedAt,
    );
    if (_sameLedger(durable, merged)) return durable;
    return _write(database, merged);
  });'''
replace_once(store, old_load, new_load)

old_canonical = '''  Future<TradingJournalLedger> _loadCanonical(
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
  }'''
new_canonical = '''  Future<TradingJournalLedger> _loadCanonical(
    QuantaraDurableDatabase database,
  ) async {
    final record = await database.read(QuantaraDurableCategory.journal, _key);
    if (record == null) {
      final legacy = await _legacyStore.load();
      if (_isEmpty(legacy)) return legacy;
      return _write(database, legacy, minimumRevision: 1);
    }
    if (_legacyStore is! ForegroundTradingJournalMirror) {
      return TradingJournalLedger.fromJson(record.payload);
    }
    final durable = TradingJournalLedger.fromJson(record.payload);
    if (durable.integrity == TradingJournalIntegrity.unverified) {
      return durable;
    }
    final foregroundMirror = await _legacyStore.load();
    final merged = mergeTradingJournalLedgers(
      durable,
      foregroundMirror,
      newerThan: record.updatedAt,
    );
    if (_sameLedger(durable, merged)) return durable;
    return _write(database, merged);
  }'''
replace_once(store, old_canonical, new_canonical)

regression = root / 'test/trading_journal_foreground_merge_test.dart'
text = regression.read_text()
if "newerThan: DateTime.utc(2026, 8, 5, 3)," not in text:
    replace_once(
        regression,
        '''    final merged = mergeTradingJournalLedgers(durable, foreground);''',
        '''    final merged = mergeTradingJournalLedgers(
      durable,
      foreground,
      newerThan: DateTime.utc(2026, 8, 5, 3),
    );''',
    )
    append = '''

  test('ignores stale migration-only plans after durable database exists', () {
    final durablePlan = _plan();
    final stalePlan = TradingJournalPlan.fromJson({
      ...durablePlan.toJson(),
      'journalTradeId': 'legacy-only',
      'setupId': 'legacy-setup',
      'decidedAt': DateTime.utc(2026, 8, 4).toIso8601String(),
    });
    final durable = TradingJournalLedger.empty().appendPlan(durablePlan);
    final foreground = TradingJournalLedger.empty().appendPlan(stalePlan);

    final merged = mergeTradingJournalLedgers(
      durable,
      foreground,
      newerThan: DateTime.utc(2026, 8, 5),
    );

    expect(merged.plans, hasLength(1));
    expect(merged.plans.single.journalTradeId, durablePlan.journalTradeId);
  });
'''
    marker = '\n}\n\nTradingJournalPlan _plan()'
    if marker not in regression.read_text():
        raise SystemExit('foreground merge test main marker missing')
    regression.write_text(regression.read_text().replace(marker, append + marker, 1))
