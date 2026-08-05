from pathlib import Path

root = Path('src/client/quantara_app')


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{path}: expected one anchor, found {count}')
    path.write_text(text.replace(old, new, 1))


mapper = root / 'lib/features/auto_trade/data/bitunix_pnl_mapper.dart'
text = mapper.read_text()
if '_closedPositionAttributionTolerance' not in text:
    replace_once(
        mapper,
        "final class BitunixPnlMapper {\n  const BitunixPnlMapper._();",
        "final class BitunixPnlMapper {\n  const BitunixPnlMapper._();\n\n  static const _closedPositionAttributionTolerance = Duration(minutes: 2);\n  static const _minimumNearestSeparation = Duration(seconds: 5);",
    )
    replace_once(
        mapper,
        '''  static String? _resolvePositionId({
    required String symbol,
    required DateTime occurredAt,
    required List<ExchangeUnrealizedPnl> openPositions,
    required List<ExchangePositionSettlement> settlements,
  }) {
    final at = occurredAt.toUtc();
    final closedMatches = settlements
        .where((item) {
          if (item.symbol.toUpperCase() != symbol) return false;
          final openedAt = item.openedAt;
          if (openedAt != null && at.isBefore(openedAt.toUtc())) return false;
          return !at.isAfter(item.closedAt.toUtc());
        })
        .map((item) => item.positionId)
        .where((item) => item.isNotEmpty)
        .toSet();
    if (closedMatches.length == 1) return closedMatches.single;
    if (closedMatches.length > 1) return null;

    final openMatches = openPositions
        .where((item) => item.symbol.toUpperCase() == symbol)
        .map((item) => item.positionId)
        .where((item) => item.trim().isNotEmpty)
        .toSet();
    if (openMatches.length == 1) return openMatches.single;
    return null;
  }''',
        '''  static String? _resolvePositionId({
    required String symbol,
    required DateTime occurredAt,
    required List<ExchangeUnrealizedPnl> openPositions,
    required List<ExchangePositionSettlement> settlements,
  }) {
    final at = occurredAt.toUtc();
    final exactClosedMatches = settlements
        .where((item) {
          if (item.symbol.toUpperCase() != symbol) return false;
          final openedAt = item.openedAt;
          if (openedAt != null && at.isBefore(openedAt.toUtc())) return false;
          return !at.isAfter(item.closedAt.toUtc());
        })
        .map((item) => item.positionId.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
    if (exactClosedMatches.length == 1) return exactClosedMatches.single;
    if (exactClosedMatches.length > 1) return null;

    final toleranceMicros =
        _closedPositionAttributionTolerance.inMicroseconds;
    final tolerantClosedMatches = settlements
        .where((item) {
          if (item.symbol.toUpperCase() != symbol) return false;
          final openedAt = item.openedAt;
          if (openedAt != null && at.isBefore(openedAt.toUtc())) return false;
          return item.positionId.trim().isNotEmpty;
        })
        .map(
          (item) => (
            positionId: item.positionId.trim(),
            deltaMicros: at
                .difference(item.closedAt.toUtc())
                .inMicroseconds
                .abs(),
          ),
        )
        .where((item) => item.deltaMicros <= toleranceMicros)
        .toList(growable: false)
      ..sort((left, right) => left.deltaMicros.compareTo(right.deltaMicros));
    if (tolerantClosedMatches.length == 1) {
      return tolerantClosedMatches.single.positionId;
    }
    if (tolerantClosedMatches.length > 1) {
      final nearest = tolerantClosedMatches[0];
      final next = tolerantClosedMatches[1];
      if (nearest.deltaMicros + _minimumNearestSeparation.inMicroseconds <
          next.deltaMicros) {
        return nearest.positionId;
      }
      return null;
    }

    final openMatches = openPositions
        .where((item) => item.symbol.toUpperCase() == symbol)
        .map((item) => item.positionId)
        .where((item) => item.trim().isNotEmpty)
        .toSet();
    if (openMatches.length == 1) return openMatches.single;
    return null;
  }''',
    )

store = root / 'lib/features/trading_journal/data/database_trading_journal_store.dart'
text = store.read_text()
if "import 'dart:convert';" not in text:
    store.write_text(text.replace("import 'dart:async';", "import 'dart:async';\nimport 'dart:convert';", 1))
if 'mergeTradingJournalLedgers' not in store.read_text():
    replace_once(
        store,
        '''  @override
  Future<TradingJournalLedger> load() => _serialValue(() async {
    final database = await _databaseFactory();
    final record = await database.read(QuantaraDurableCategory.journal, _key);
    if (record != null) {
      return TradingJournalLedger.fromJson(record.payload);
    }
    final legacy = await _legacyStore.load();
    if (_isEmpty(legacy)) return legacy;
    return _write(database, legacy, minimumRevision: 1);
  });''',
        '''  @override
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
  });''',
    )
    replace_once(
        store,
        '''  Future<TradingJournalLedger> _loadCanonical(
    QuantaraDurableDatabase database,
  ) async {
    final record = await database.read(QuantaraDurableCategory.journal, _key);
    if (record != null) return TradingJournalLedger.fromJson(record.payload);
    final legacy = await _legacyStore.load();
    if (_isEmpty(legacy)) return legacy;
    return _write(database, legacy, minimumRevision: 1);
  }''',
        '''  Future<TradingJournalLedger> _loadCanonical(
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
  }''',
    )
    text = store.read_text()
    helper = '''

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
'''
    marker = '\nfinal class DatabaseTradingJournalStore implements TradingJournalStore {'
    if marker not in text:
        raise SystemExit('database journal store class marker missing')
    store.write_text(text.replace(marker, helper + marker, 1))

observer = root / 'lib/features/trading_journal/application/local_live_journal_observer.dart'
text = observer.read_text()
if '_closeReasonForFill' not in text:
    replace_once(
        observer,
        '''            if (!isTarget)
              'closeReason': fill.orderId == managed.stopOrderId
                  ? TradingJournalCloseReason.stop.name
                  : fill.clientId.endsWith('-emergency-close')
                  ? TradingJournalCloseReason.emergency.name
                  : TradingJournalCloseReason.exchange.name,''',
        '''            if (!isTarget)
              'closeReason': _closeReasonForFill(
                managed: managed,
                fill: fill,
              ).name,''',
    )
    text = observer.read_text()
    helper = '''  static TradingJournalCloseReason _closeReasonForFill({
    required LocalLiveManagedPosition managed,
    required ExchangePnlFill fill,
  }) {
    if (fill.clientId.endsWith('-emergency-close')) {
      return TradingJournalCloseReason.emergency;
    }
    if (fill.orderId == managed.stopOrderId) {
      return TradingJournalCloseReason.stop;
    }
    final stop = managed.originalStopLoss;
    final price = fill.price;
    if (stop.isFinite && stop > 0 && price.isFinite && price > 0) {
      final tolerance = stop.abs() * 0.003;
      final stopLike = switch (managed.direction) {
        TradeDirection.long => price <= stop + tolerance,
        TradeDirection.short => price >= stop - tolerance,
        TradeDirection.wait => false,
      };
      if (stopLike) return TradingJournalCloseReason.stop;
    }
    return TradingJournalCloseReason.exchange;
  }

'''
    marker = '  static TradingJournalDirection _direction(TradeDirection direction) =>'
    if marker not in text:
        raise SystemExit('journal observer direction marker missing')
    observer.write_text(text.replace(marker, helper + marker, 1))

service = root / 'lib/features/auto_trade/application/local_live_trade_service.dart'
text = service.read_text()
if 'quantara.local-live.pending-journal-closures.v1' not in text:
    replace_once(
        service,
        "const localLiveSessionPositionIdsKey =\n    'quantara.local-live.session-positions.v1';",
        "const localLiveSessionPositionIdsKey =\n    'quantara.local-live.session-positions.v1';\nconst localLivePendingJournalClosuresKey =\n    'quantara.local-live.pending-journal-closures.v1';",
    )
    replace_once(
        service,
        '  final List<LocalLiveManagedPosition> _managed = [];\n  final Set<String> _executedSetupIds = {};',
        '  final List<LocalLiveManagedPosition> _managed = [];\n  final List<LocalLiveManagedPosition> _pendingJournalClosures = [];\n  final Set<String> _executedSetupIds = {};',
    )
    replace_once(
        service,
        '  bool _entriesEnabled = false;\n  bool _cycleRunning = false;',
        '  bool _entriesEnabled = false;\n  bool _userRequestedEntries = false;\n  bool _cycleRunning = false;',
    )
    replace_once(
        service,
        "    if (id == 'stop_entries') {\n      _entriesEnabled = false;",
        "    if (id == 'stop_entries') {\n      _userRequestedEntries = false;\n      _entriesEnabled = false;",
    )
    replace_once(
        service,
        "        _entriesEnabled = message['entriesEnabled'] == true;",
        "        _userRequestedEntries = message['entriesEnabled'] == true;\n        _entriesEnabled = _userRequestedEntries;",
    )
    replace_once(
        service,
        "      case 'stop':\n        _entriesEnabled = false;",
        "      case 'stop':\n        _userRequestedEntries = false;\n        _entriesEnabled = false;",
    )
    replace_once(
        service,
        "        final reason = message['reason']?.toString() ?? 'unavailable';\n        _auditEvent(",
        "        final reason = message['reason']?.toString() ?? 'unavailable';\n        if (reason == 'disconnected') _userRequestedEntries = false;\n        _auditEvent(",
    )
    replace_once(
        service,
        "      case 'emergency_close':\n        _entriesEnabled = false;",
        "      case 'emergency_close':\n        _userRequestedEntries = false;\n        _entriesEnabled = false;",
    )
    replace_once(
        service,
        "      final positions = await exchange.fetchPositions(credentials);\n      _lastExchangeSync = DateTime.now().toUtc();",
        "      final positions = await exchange.fetchPositions(credentials);\n      _lastExchangeSync = DateTime.now().toUtc();\n      _entriesEnabled = _userRequestedEntries;",
    )
    replace_once(
        service,
        "              ownedPositionIds: Set.unmodifiable(_sessionPositionIds),\n            );\n      final managedPositionIds = _managed",
        "              ownedPositionIds: Set.unmodifiable(_sessionPositionIds),\n            );\n      await _reconcilePendingJournalClosures(account.authoritativePnl);\n      final managedPositionIds = _managed",
    )
    replace_once(
        service,
        "      if (lossPercent >= configuration.dailyLossLimitPercent) {\n        _entriesEnabled = false;",
        "      if (lossPercent >= configuration.dailyLossLimitPercent) {\n        _userRequestedEntries = false;\n        _entriesEnabled = false;",
    )
    replace_once(
        service,
        "      if (_consecutiveFailures >= 3) {\n        _entriesEnabled = false;",
        "      if (_consecutiveFailures >= 3) {\n        _userRequestedEntries = false;\n        _entriesEnabled = false;",
    )
    replace_once(
        service,
        '''      if (position == null || position.quantity <= 0) {
        if (positionPnl != null) {
          await _journalObserver.reconcilePosition(
            managed: managed,
            positionPnl: positionPnl,
            positionClosed: true,
          );
        }
        final history = await exchange.fetchClosedPositions(
          positionId: managed.positionId,
          credentials: credentials,
        );
        if (history.isEmpty) {
          _auditEvent(
            'pnl_pending',
            'Closed position history is not available yet; PnL remains unavailable.',
            symbol: managed.symbol,
          );
        }
        _managed.remove(managed);
        _closedPositionCount++;
        _auditEvent(
          'position_closed',
          'Managed position closed and realized result reconciled.',
          symbol: managed.symbol,
        );
        continue;
      }''',
        '''      if (position == null || position.quantity <= 0) {
        var journalReconciled = false;
        if (positionPnl != null && positionPnl.isVerified) {
          await _journalObserver.reconcilePosition(
            managed: managed,
            positionPnl: positionPnl,
            positionClosed: true,
          );
          journalReconciled = true;
        }
        final history = await exchange.fetchClosedPositions(
          positionId: managed.positionId,
          credentials: credentials,
        );
        if (!journalReconciled &&
            !_pendingJournalClosures.any(
              (item) => item.positionId == managed.positionId,
            )) {
          _pendingJournalClosures.add(managed);
        }
        if (history.isEmpty || !journalReconciled) {
          _auditEvent(
            'pnl_pending',
            'The position is exchange-closed; final journal economics remain queued until verified fill history is available.',
            symbol: managed.symbol,
          );
        }
        _managed.remove(managed);
        _closedPositionCount++;
        await _persistState();
        _auditEvent(
          'position_closed',
          journalReconciled
              ? 'Managed position closed and realized result reconciled.'
              : 'Managed position closed; journal economics queued for verified reconciliation.',
          symbol: managed.symbol,
        );
        continue;
      }''',
    )
    text = service.read_text()
    method = '''  Future<void> _reconcilePendingJournalClosures(
    TradingPnlProjection pnlProjection,
  ) async {
    var changed = false;
    for (final managed in List<LocalLiveManagedPosition>.of(
      _pendingJournalClosures,
    )) {
      final positionPnl = pnlProjection.forPositionId(managed.positionId);
      if (positionPnl == null || !positionPnl.isVerified) continue;
      await _journalObserver.reconcilePosition(
        managed: managed,
        positionPnl: positionPnl,
        positionClosed: true,
      );
      _pendingJournalClosures.remove(managed);
      changed = true;
      _auditEvent(
        'journal_close_reconciled',
        'Queued closed-position economics were reconciled from verified exchange history.',
        symbol: managed.symbol,
      );
    }
    if (changed) await _persistState();
  }

'''
    marker = '  Future<void> _reconcileManagedPositions('
    if marker not in text:
        raise SystemExit('reconcile managed marker missing')
    service.write_text(text.replace(marker, method + marker, 1))
    replace_once(
        service,
        '''    final managedRaw = await FlutterForegroundTask.getData<String>(
      key: localLiveManagedPositionsKey,
    );''',
        '''    final pendingClosuresRaw = await FlutterForegroundTask.getData<String>(
      key: localLivePendingJournalClosuresKey,
    );
    if (pendingClosuresRaw != null) {
      try {
        final decoded = jsonDecode(pendingClosuresRaw);
        if (decoded is List<Object?>) {
          _pendingJournalClosures
            ..clear()
            ..addAll(
              decoded.whereType<Map<Object?, Object?>>().map(
                (item) => LocalLiveManagedPosition.fromJson(
                  item.map((key, value) => MapEntry(key.toString(), value)),
                ),
              ),
            );
        }
      } on Object {
        _pendingJournalClosures.clear();
      }
    }
    final managedRaw = await FlutterForegroundTask.getData<String>(
      key: localLiveManagedPositionsKey,
    );''',
    )
    replace_once(
        service,
        '''  Future<void> _persistState() async {
    await FlutterForegroundTask.saveData(
      key: localLiveManagedPositionsKey,
      value: jsonEncode(_managed.map((item) => item.toJson()).toList()),
    );''',
        '''  Future<void> _persistState() async {
    await FlutterForegroundTask.saveData(
      key: localLiveManagedPositionsKey,
      value: jsonEncode(_managed.map((item) => item.toJson()).toList()),
    );
    await FlutterForegroundTask.saveData(
      key: localLivePendingJournalClosuresKey,
      value: jsonEncode(
        _pendingJournalClosures.map((item) => item.toJson()).toList(),
      ),
    );''',
    )
    replace_once(
        service,
        '''  Future<void> _trip(String message) async {
    _entriesEnabled = false;''',
        '''  Future<void> _trip(String message) async {
    _userRequestedEntries = false;
    _entriesEnabled = false;''',
    )
