import 'dart:convert';
import 'dart:math';

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

  static String toPrivacySafeJson(TradingJournalLedger ledger) =>
      const JsonEncoder.withIndent('  ').convert({
        'schemaVersion': ledger.schemaVersion,
        'plans': ledger.plans.map(_privacySafePlan).toList(growable: false),
        'events': ledger.events.map(_privacySafeEvent).toList(growable: false),
        'integrity': ledger.integrity.name,
        'warnings': ledger.warnings,
      });

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
    final plans = {for (final plan in ledger.plans) plan.journalTradeId: plan};
    final rows = <List<Object?>>[columns];
    for (final event in ledger.events) {
      final plan = plans[event.journalTradeId];
      rows.add([
        event.journalTradeId,
        event.eventId,
        event.type.name,
        event.occurredAt.toUtc().toIso8601String(),
        event.source.name,
        event.quality.name,
        plan?.symbol ?? '',
        plan?.timeframe ?? '',
        plan?.direction.name ?? '',
        event.positionId ?? '',
        event.orderId ?? '',
        event.tradeId ?? '',
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

  static Map<String, Object?> _privacySafePlan(TradingJournalPlan plan) {
    final result = Map<String, Object?>.from(plan.toJson());
    // Client IDs are correlation hints and can contain implementation details;
    // public exports intentionally omit them along with all credentials.
    result.remove('clientId');
    return _privacySafeMap(result);
  }

  static Map<String, Object?> _privacySafeEvent(TradingJournalEvent event) {
    final result = Map<String, Object?>.from(event.toJson());
    result.remove('clientId');
    return _privacySafeMap(result);
  }

  static Map<String, Object?> _privacySafeMap(Map<Object?, Object?> value) => {
    for (final entry in value.entries)
      if (!_secretLike(entry.key.toString()))
        entry.key.toString(): _privacySafeValue(entry.value),
  };

  static Object? _privacySafeValue(Object? value) {
    if (value is Map<Object?, Object?>) return _privacySafeMap(value);
    if (value is List<Object?>) {
      return value.map(_privacySafeValue).toList(growable: false);
    }
    return value;
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
