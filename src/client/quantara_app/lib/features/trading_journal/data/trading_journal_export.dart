import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';

import '../domain/trading_journal_models.dart';

abstract final class TradingJournalExport {
  static const _encryptedSchema = 'quantara-journal-aes-gcm-v1';
  static const _pbkdf2Iterations = 180000;

  static Future<String> toEncryptedJson(
    TradingJournalLedger ledger, {
    required String passphrase,
  }) async {
    if (passphrase.length < 12) {
      throw const FormatException(
        'Export passphrase must contain at least 12 characters.',
      );
    }
    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    final algorithm = AesGcm.with256bits();
    final nonce = algorithm.newNonce();
    final key = await Pbkdf2.hmacSha256(
      iterations: _pbkdf2Iterations,
      bits: 256,
    ).deriveKeyFromPassword(password: passphrase, nonce: salt);
    final clearText = utf8.encode(toPrivacySafeJson(ledger));
    final box = await algorithm.encrypt(
      clearText,
      secretKey: key,
      nonce: nonce,
      aad: utf8.encode(_encryptedSchema),
    );
    return jsonEncode({
      'schema': _encryptedSchema,
      'kdf': 'PBKDF2-HMAC-SHA256',
      'iterations': _pbkdf2Iterations,
      'salt': base64Encode(salt),
      'nonce': base64Encode(box.nonce),
      'cipherText': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    });
  }

  static Future<TradingJournalLedger> fromEncryptedJson(
    String encrypted, {
    required String passphrase,
  }) async {
    final decoded = jsonDecode(encrypted);
    if (decoded is! Map<Object?, Object?>) {
      throw const FormatException('Encrypted journal must be a JSON object.');
    }
    final map = decoded.map((key, value) => MapEntry(key.toString(), value));
    if (map['schema'] != _encryptedSchema) {
      throw const FormatException('Unsupported encrypted journal schema.');
    }
    final iterations = map['iterations'] is num
        ? (map['iterations'] as num).toInt()
        : int.tryParse(map['iterations']?.toString() ?? '') ?? 0;
    if (iterations < 10000 || iterations > 1000000) {
      throw const FormatException('Invalid encrypted journal KDF parameters.');
    }
    final salt = base64Decode(map['salt']?.toString() ?? '');
    final nonce = base64Decode(map['nonce']?.toString() ?? '');
    final cipherText = base64Decode(map['cipherText']?.toString() ?? '');
    final mac = Mac(base64Decode(map['mac']?.toString() ?? ''));
    final key = await Pbkdf2.hmacSha256(
      iterations: iterations,
      bits: 256,
    ).deriveKeyFromPassword(password: passphrase, nonce: salt);
    final clearText = await AesGcm.with256bits().decrypt(
      SecretBox(cipherText, nonce: nonce, mac: mac),
      secretKey: key,
      aad: utf8.encode(_encryptedSchema),
    );
    return fromPrivacySafeJson(utf8.decode(clearText));
  }

  static String toPrivacySafeJson(TradingJournalLedger ledger) {
    final privacy = _PrivacyContext.fromLedger(ledger);
    return const JsonEncoder.withIndent('  ').convert({
      'schemaVersion': ledger.schemaVersion,
      'plans': ledger.plans
          .map((plan) => _privacySafePlan(plan, privacy))
          .toList(growable: false),
      'events': ledger.events
          .map((event) => _privacySafeEvent(event, privacy))
          .toList(growable: false),
      'integrity': ledger.integrity.name,
      'warnings': ledger.warnings
          .map(privacy.sanitizeText)
          .toList(growable: false),
    });
  }

  static TradingJournalLedger fromPrivacySafeJson(String text) {
    final decoded = jsonDecode(text);
    if (decoded is! Map<Object?, Object?>) {
      throw const FormatException('Journal import must be a JSON object.');
    }
    final map = decoded.map((key, value) => MapEntry(key.toString(), value));
    var ledger = TradingJournalLedger.empty();
    for (final plan in _mapList(map['plans'])) {
      ledger = ledger.appendPlan(TradingJournalPlan.fromJson(plan));
    }
    for (final event in _mapList(map['events'])) {
      ledger = ledger.appendEvent(TradingJournalEvent.fromJson(event));
    }
    return ledger;
  }

  static String toPrivacySafeCsv(TradingJournalLedger ledger) {
    const columns = [
      'journalTradeId',
      'eventId',
      'eventType',
      'occurredAtUtc',
      'factSource',
      'quality',
      'symbol',
      'timeframe',
      'direction',
      'positionId',
      'orderId',
      'tradeId',
      'quantity',
      'price',
      'grossPnl',
      'fee',
      'funding',
      'remainingQuantity',
      'currency',
    ];
    final privacy = _PrivacyContext.fromLedger(ledger);
    final plans = {for (final plan in ledger.plans) plan.journalTradeId: plan};
    final rows = <List<Object?>>[columns];
    for (final event in ledger.events) {
      final plan = plans[event.journalTradeId];
      rows.add([
        privacy.identifier('journal', event.journalTradeId),
        privacy.identifier('event', event.eventId),
        event.type.name,
        event.occurredAt.toUtc().toIso8601String(),
        event.source.name,
        event.quality.name,
        plan?.symbol ?? '',
        plan?.timeframe ?? '',
        plan?.direction.name ?? '',
        privacy.identifier('position', event.positionId),
        privacy.identifier('order', event.orderId),
        privacy.identifier('trade', event.tradeId),
        event.quantity ?? '',
        event.price ?? '',
        event.grossPnl ?? '',
        event.fee ?? '',
        event.funding ?? '',
        event.remainingQuantity ?? '',
        event.currency,
      ]);
    }
    return rows.map((row) => row.map(_csv).join(',')).join('\n');
  }

  static Map<String, Object?> _privacySafePlan(
    TradingJournalPlan plan,
    _PrivacyContext privacy,
  ) {
    final result = Map<String, Object?>.from(plan.toJson());
    result.remove('clientId');
    return _privacySafeMap(result, privacy);
  }

  static Map<String, Object?> _privacySafeEvent(
    TradingJournalEvent event,
    _PrivacyContext privacy,
  ) {
    final result = Map<String, Object?>.from(event.toJson());
    result.remove('clientId');
    return _privacySafeMap(result, privacy);
  }

  static Map<String, Object?> _privacySafeMap(
    Map<Object?, Object?> value,
    _PrivacyContext privacy,
  ) => {
    for (final entry in value.entries)
      if (!_secretLike(entry.key.toString()))
        entry.key.toString(): _privacySafeField(
          entry.key.toString(),
          entry.value,
          privacy,
        ),
  };

  static Object? _privacySafeField(
    String key,
    Object? value,
    _PrivacyContext privacy,
  ) {
    final identifierKind = _identifierKind(key);
    if (identifierKind != null && value is String) {
      return privacy.identifier(identifierKind, value);
    }
    return _privacySafeValue(value, privacy);
  }

  static Object? _privacySafeValue(Object? value, _PrivacyContext privacy) {
    if (value is Map<Object?, Object?>) return _privacySafeMap(value, privacy);
    if (value is List<Object?>) {
      return value
          .map((item) => _privacySafeValue(item, privacy))
          .toList(growable: false);
    }
    if (value is String) return privacy.sanitizeText(value);
    return value;
  }

  static String? _identifierKind(String key) {
    final normalized = key.toLowerCase().replaceAll(RegExp('[^a-z]'), '');
    return switch (normalized) {
      'journaltradeid' => 'journal',
      'eventid' => 'event',
      'exchangeeventid' => 'exchange_event',
      'positionid' => 'position',
      'entryorderid' || 'orderid' => 'order',
      'tradeid' => 'trade',
      'clientid' => 'client',
      _ => null,
    };
  }

  static bool _secretLike(String key) {
    final normalized = key.toLowerCase().replaceAll(RegExp('[^a-z]'), '');
    return normalized.contains('apikey') ||
        normalized.contains('secret') ||
        normalized.contains('credential') ||
        normalized.contains('password') ||
        normalized.contains('token');
  }

  static String _csv(Object? value) {
    final text = value?.toString() ?? '';
    if (!text.contains(RegExp('[,\n"]'))) return text;
    return '"${text.replaceAll('"', '""')}"';
  }

  static List<Map<String, Object?>> _mapList(Object? value) {
    if (value is! List<Object?>) return const [];
    return value
        .whereType<Map<Object?, Object?>>()
        .map(
          (item) =>
              item.map((key, itemValue) => MapEntry(key.toString(), itemValue)),
        )
        .toList(growable: false);
  }
}

final class _PrivacyContext {
  _PrivacyContext(this._knownIdentifiers);

  factory _PrivacyContext.fromLedger(TradingJournalLedger ledger) {
    final known = <String, String>{};

    void remember(String kind, String? raw) {
      final value = raw?.trim() ?? '';
      if (value.isEmpty) return;
      known[value] = _pseudonym(kind, value);
    }

    for (final plan in ledger.plans) {
      remember('journal', plan.journalTradeId);
      remember('position', plan.positionId);
      remember('order', plan.entryOrderId);
      remember('client', plan.clientId);
    }
    for (final event in ledger.events) {
      remember('journal', event.journalTradeId);
      remember('event', event.eventId);
      remember('exchange_event', event.exchangeEventId);
      remember('position', event.positionId);
      remember('order', event.orderId);
      remember('client', event.clientId);
      remember('trade', event.tradeId);
    }
    return _PrivacyContext(known);
  }

  final Map<String, String> _knownIdentifiers;

  String identifier(String kind, String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return '';
    return _knownIdentifiers[value] ?? _pseudonym(kind, value);
  }

  String sanitizeText(String text) {
    var result = text;
    final identifiers = _knownIdentifiers.entries.toList(growable: false)
      ..sort((left, right) => right.key.length.compareTo(left.key.length));
    for (final entry in identifiers) {
      result = result.replaceAll(entry.key, entry.value);
    }
    return result;
  }

  static String _pseudonym(String kind, String raw) {
    final digest = crypto.sha256
        .convert(utf8.encode('quantara-journal-id-v1:$kind:$raw'))
        .toString();
    return '${kind}_${digest.substring(0, 16)}';
  }
}
