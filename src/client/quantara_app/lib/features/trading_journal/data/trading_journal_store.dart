import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/trading_journal_models.dart';

const tradingJournalActiveSlotKey = 'quantara.trading-journal.v1.active';
const tradingJournalSlotAKey = 'quantara.trading-journal.v1.slot.a';
const tradingJournalSlotBKey = 'quantara.trading-journal.v1.slot.b';

abstract interface class TradingJournalStore {
  Future<TradingJournalLedger> load();
  Future<void> replace(TradingJournalLedger ledger);
  Future<void> appendPlan(TradingJournalPlan plan);
  Future<void> appendEvent(TradingJournalEvent event);
}

/// Marks the device-local foreground-service mirror. A durable store may read
/// this mirror only to import newer Local Live facts; generic legacy stores
/// remain migration-only and can never override database truth.
abstract interface class ForegroundTradingJournalMirror {}

final class TradingJournalEnvelope {
  const TradingJournalEnvelope({
    required this.schemaVersion,
    required this.generation,
    required this.payload,
    required this.checksum,
  });

  factory TradingJournalEnvelope.fromLedger(TradingJournalLedger ledger) {
    final payload = _canonicalJson(ledger.toJson());
    return TradingJournalEnvelope(
      schemaVersion: 1,
      generation: ledger.generation,
      payload: payload,
      checksum: sha256.convert(utf8.encode(payload)).toString(),
    );
  }

  final int schemaVersion;
  final int generation;
  final String payload;
  final String checksum;

  String encode() => jsonEncode({
    'schemaVersion': schemaVersion,
    'generation': generation,
    'payload': payload,
    'checksum': checksum,
  });

  TradingJournalLedger decodeLedger() {
    final actual = sha256.convert(utf8.encode(payload)).toString();
    if (actual != checksum) {
      throw const FormatException('Journal checksum mismatch.');
    }
    final decoded = jsonDecode(payload);
    if (decoded is! Map<Object?, Object?>) {
      throw const FormatException('Journal payload was not an object.');
    }
    final ledger = TradingJournalLedger.fromJson(
      decoded.map((key, value) => MapEntry(key.toString(), value)),
    );
    if (ledger.generation != generation) {
      throw const FormatException('Journal generation mismatch.');
    }
    return ledger;
  }

  factory TradingJournalEnvelope.decode(String encoded) {
    final decoded = jsonDecode(encoded);
    if (decoded is! Map<Object?, Object?>) {
      throw const FormatException('Journal envelope was not an object.');
    }
    final map = decoded.map((key, value) => MapEntry(key.toString(), value));
    return TradingJournalEnvelope(
      schemaVersion: _integer(map['schemaVersion'], fallback: 1),
      generation: _integer(map['generation']),
      payload: map['payload']?.toString() ?? '',
      checksum: map['checksum']?.toString() ?? '',
    );
  }
}

final class SharedPreferencesTradingJournalStore
    implements TradingJournalStore, ForegroundTradingJournalMirror {
  SharedPreferencesTradingJournalStore({
    Future<SharedPreferences> Function()? preferencesFactory,
  }) : _preferencesFactory =
           preferencesFactory ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _preferencesFactory;
  static Future<void> _globalTail = Future<void>.value();

  @override
  Future<TradingJournalLedger> load() async {
    await _globalTail;
    final preferences = await _preferencesFactory();
    await preferences.reload();
    return _loadFrom(preferences);
  }

  @override
  Future<void> replace(TradingJournalLedger ledger) => _serial(() async {
    final preferences = await _preferencesFactory();
    await preferences.reload();
    final current = _loadFrom(preferences);
    final nextGeneration = current.generation >= ledger.generation
        ? current.generation + 1
        : ledger.generation;
    final committed = ledger.withGeneration(nextGeneration);
    final active = _activeSlot(preferences);
    final target = active == 'a' ? 'b' : 'a';
    final targetKey = target == 'a'
        ? tradingJournalSlotAKey
        : tradingJournalSlotBKey;
    final envelope = TradingJournalEnvelope.fromLedger(committed);
    final encoded = envelope.encode();
    final wrote = await preferences.setString(targetKey, encoded);
    if (!wrote) throw StateError('Could not persist journal slot.');
    final verify = preferences.getString(targetKey);
    if (verify == null) throw StateError('Journal slot read-back failed.');
    TradingJournalEnvelope.decode(verify).decodeLedger();
    final flipped = await preferences.setString(
      tradingJournalActiveSlotKey,
      target,
    );
    if (!flipped) throw StateError('Could not commit journal pointer.');
  });

  @override
  Future<void> appendPlan(TradingJournalPlan plan) => _serial(() async {
    final preferences = await _preferencesFactory();
    await preferences.reload();
    final current = _loadFrom(preferences);
    await _replaceWithPreferences(preferences, current.appendPlan(plan));
  });

  @override
  Future<void> appendEvent(TradingJournalEvent event) => _serial(() async {
    final preferences = await _preferencesFactory();
    await preferences.reload();
    final current = _loadFrom(preferences);
    await _replaceWithPreferences(preferences, current.appendEvent(event));
  });

  Future<void> _replaceWithPreferences(
    SharedPreferences preferences,
    TradingJournalLedger ledger,
  ) async {
    final active = _activeSlot(preferences);
    final target = active == 'a' ? 'b' : 'a';
    final targetKey = target == 'a'
        ? tradingJournalSlotAKey
        : tradingJournalSlotBKey;
    final current = _loadFrom(preferences);
    final next = ledger.withGeneration(
      current.generation >= ledger.generation
          ? current.generation + 1
          : ledger.generation,
    );
    final encoded = TradingJournalEnvelope.fromLedger(next).encode();
    if (!await preferences.setString(targetKey, encoded)) {
      throw StateError('Could not persist journal slot.');
    }
    final stored = preferences.getString(targetKey);
    if (stored == null) throw StateError('Journal slot read-back failed.');
    TradingJournalEnvelope.decode(stored).decodeLedger();
    if (!await preferences.setString(tradingJournalActiveSlotKey, target)) {
      throw StateError('Could not commit journal pointer.');
    }
  }

  TradingJournalLedger _loadFrom(SharedPreferences preferences) {
    final pointer = preferences.getString(tradingJournalActiveSlotKey);
    if (pointer != 'a' && pointer != 'b') {
      final a = _tryDecode(preferences.getString(tradingJournalSlotAKey));
      final b = _tryDecode(preferences.getString(tradingJournalSlotBKey));
      if (a != null && b != null) {
        return (a.generation >= b.generation ? a : b).withRecoveryWarning(
          'Recovered journal after the commit pointer was missing.',
        );
      }
      if (a != null) return a.withRecoveryWarning('Recovered journal slot A.');
      if (b != null) return b.withRecoveryWarning('Recovered journal slot B.');
      final hadStoredData = [
        preferences.getString(tradingJournalSlotAKey),
        preferences.getString(tradingJournalSlotBKey),
      ].any((item) => item != null && item.trim().isNotEmpty);
      return hadStoredData
          ? TradingJournalLedger.empty().withIntegrityWarning(
              'Both journal slots were unreadable; no values were fabricated.',
            )
          : TradingJournalLedger.empty();
    }

    final activeKey = pointer == 'a'
        ? tradingJournalSlotAKey
        : tradingJournalSlotBKey;
    final fallbackKey = pointer == 'a'
        ? tradingJournalSlotBKey
        : tradingJournalSlotAKey;
    final activeResult = _tryDecode(preferences.getString(activeKey));
    if (activeResult != null) return activeResult;
    final fallback = _tryDecode(preferences.getString(fallbackKey));
    if (fallback != null) {
      return fallback.withRecoveryWarning(
        'Recovered journal from the previous verified slot.',
      );
    }
    final hadStoredData = [
      preferences.getString(activeKey),
      preferences.getString(fallbackKey),
    ].any((item) => item != null && item.trim().isNotEmpty);
    return hadStoredData
        ? TradingJournalLedger.empty().withIntegrityWarning(
            'Both journal slots were unreadable; no values were fabricated.',
          )
        : TradingJournalLedger.empty();
  }

  static TradingJournalLedger? _tryDecode(String? encoded) {
    if (encoded == null || encoded.trim().isEmpty) return null;
    try {
      return TradingJournalEnvelope.decode(encoded).decodeLedger();
    } on Object {
      return null;
    }
  }

  static String _activeSlot(SharedPreferences preferences) {
    final pointer = preferences.getString(tradingJournalActiveSlotKey);
    if (pointer == 'a' || pointer == 'b') {
      final pointedKey = pointer == 'a'
          ? tradingJournalSlotAKey
          : tradingJournalSlotBKey;
      if (_tryDecode(preferences.getString(pointedKey)) != null) {
        return pointer!;
      }
      final fallback = pointer == 'a' ? 'b' : 'a';
      final fallbackKey = fallback == 'a'
          ? tradingJournalSlotAKey
          : tradingJournalSlotBKey;
      if (_tryDecode(preferences.getString(fallbackKey)) != null) {
        return fallback;
      }
      return pointer!;
    }
    final a = _tryDecode(preferences.getString(tradingJournalSlotAKey));
    final b = _tryDecode(preferences.getString(tradingJournalSlotBKey));
    if (a != null && b != null) return a.generation >= b.generation ? 'a' : 'b';
    if (a != null) return 'a';
    if (b != null) return 'b';
    return 'a';
  }

  Future<void> _serial(Future<void> Function() operation) {
    final result = _globalTail.then((_) => operation());
    _globalTail = result.catchError((Object _) {});
    return result;
  }
}

String _canonicalJson(Object? value) {
  Object? normalize(Object? input) {
    if (input is Map) {
      final keys = input.keys.map((key) => key.toString()).toList()..sort();
      return <String, Object?>{
        for (final key in keys) key: normalize(input[key]),
      };
    }
    if (input is List) return input.map(normalize).toList(growable: false);
    return input;
  }

  return jsonEncode(normalize(value));
}

int _integer(Object? value, {int fallback = 0}) => value is num
    ? value.toInt()
    : int.tryParse(value?.toString() ?? '') ?? fallback;
