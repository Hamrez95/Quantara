import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

import '../../../core/persistence/quantara_durable_database.dart';

abstract final class EncryptedRecoveryPackage {
  static const _envelopeSchema = 'quantara-recovery-aes-gcm-v1';
  static const _packageSchema = 1;
  static const _iterations = 210000;
  static const _includedCategories = {
    QuantaraDurableCategory.settings,
    QuantaraDurableCategory.journal,
    QuantaraDurableCategory.signalHistory,
    QuantaraDurableCategory.audit,
    QuantaraDurableCategory.recoveryMetadata,
    QuantaraDurableCategory.managedPositions,
  };

  static Future<String> export({
    required QuantaraDurableDatabase database,
    required String passphrase,
    required String appVersion,
  }) async {
    _validatePassphrase(passphrase);
    final records = await database.list(categories: _includedCategories);
    final safeRecords = records
        .map(_privacySafeRecord)
        .map((record) => record.toStorageMap())
        .toList(growable: false);
    final createdAt = DateTime.now().toUtc();
    final recordsJson = _canonicalJson(safeRecords);
    final checksum = sha256.convert(utf8.encode(recordsJson)).toString();
    final backupId = sha256
        .convert(
          utf8.encode(
            '$checksum|${createdAt.microsecondsSinceEpoch}|$appVersion',
          ),
        )
        .toString();
    final clearPackage = _canonicalJson({
      'packageSchema': _packageSchema,
      'databaseSchema': quantaraDurableDatabaseSchemaVersion,
      'appVersion': appVersion,
      'backupId': backupId,
      'createdAt': createdAt.toIso8601String(),
      'categories': _includedCategories.map((item) => item.name).toList()
        ..sort(),
      'recordCount': safeRecords.length,
      'recordsChecksum': checksum,
      'records': safeRecords,
    });

    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    final algorithm = AesGcm.with256bits();
    final nonce = algorithm.newNonce();
    final key = await Pbkdf2.hmacSha256(
      iterations: _iterations,
      bits: 256,
    ).deriveKeyFromPassword(password: passphrase, nonce: salt);
    final box = await algorithm.encrypt(
      utf8.encode(clearPackage),
      secretKey: key,
      nonce: nonce,
      aad: utf8.encode(_envelopeSchema),
    );
    return jsonEncode({
      'schema': _envelopeSchema,
      'kdf': 'PBKDF2-HMAC-SHA256',
      'iterations': _iterations,
      'salt': base64Encode(salt),
      'nonce': base64Encode(box.nonce),
      'cipherText': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    });
  }

  static Future<QuantaraRestoreResult> restore({
    required QuantaraDurableDatabase database,
    required String encryptedPackage,
    required String passphrase,
  }) async {
    _validatePassphrase(passphrase);
    final envelope = _decodeObject(encryptedPackage, 'Encrypted recovery');
    if (envelope['schema'] != _envelopeSchema) {
      throw const FormatException('Unsupported recovery encryption schema.');
    }
    for (final requiredKey in const [
      'iterations',
      'salt',
      'nonce',
      'cipherText',
      'mac',
    ]) {
      if (envelope[requiredKey] == null ||
          envelope[requiredKey].toString().trim().isEmpty) {
        throw FormatException('Recovery envelope field $requiredKey is missing.');
      }
    }
    final iterations = _integer(envelope['iterations']);
    if (iterations < 10000 || iterations > 1000000) {
      throw const FormatException('Invalid recovery KDF parameters.');
    }
    late final List<int> salt;
    late final List<int> nonce;
    late final List<int> cipherText;
    late final Mac mac;
    try {
      salt = base64Decode(envelope['salt'].toString());
      nonce = base64Decode(envelope['nonce'].toString());
      cipherText = base64Decode(envelope['cipherText'].toString());
      mac = Mac(base64Decode(envelope['mac'].toString()));
    } on FormatException {
      throw const FormatException('Recovery envelope encoding is invalid.');
    }
    final key = await Pbkdf2.hmacSha256(
      iterations: iterations,
      bits: 256,
    ).deriveKeyFromPassword(password: passphrase, nonce: salt);
    final clearBytes = await AesGcm.with256bits().decrypt(
      SecretBox(cipherText, nonce: nonce, mac: mac),
      secretKey: key,
      aad: utf8.encode(_envelopeSchema),
    );
    final package = _decodeObject(utf8.decode(clearBytes), 'Recovery package');
    if (_integer(package['packageSchema']) != _packageSchema) {
      throw const FormatException('Unsupported recovery package schema.');
    }
    final databaseSchema = _integer(package['databaseSchema']);
    if (databaseSchema <= 0 ||
        databaseSchema > quantaraDurableDatabaseSchemaVersion) {
      throw const FormatException('Unsupported recovery database schema.');
    }
    final backupId = package['backupId']?.toString().trim() ?? '';
    if (backupId.length != 64) {
      throw const FormatException('Invalid recovery package identity.');
    }
    final rawRecords = package['records'];
    if (rawRecords is! List<Object?>) {
      throw const FormatException('Recovery records were not a list.');
    }
    if (_integer(package['recordCount']) != rawRecords.length) {
      throw const FormatException('Recovery record count mismatch.');
    }
    final recordsChecksum = sha256
        .convert(utf8.encode(_canonicalJson(rawRecords)))
        .toString();
    if (recordsChecksum != package['recordsChecksum']?.toString()) {
      throw const FormatException('Recovery package checksum mismatch.');
    }
    final records = <QuantaraDurableRecord>[];
    for (final raw in rawRecords) {
      if (raw is! Map<Object?, Object?>) {
        throw const FormatException('Recovery record was not an object.');
      }
      final record = QuantaraDurableRecord.fromStorageMap(raw);
      if (!_includedCategories.contains(record.category)) {
        throw const FormatException('Recovery package contained forbidden data.');
      }
      records.add(record);
    }
    return database.restoreBatch(restoreId: backupId, records: records);
  }

  static QuantaraDurableRecord _privacySafeRecord(
    QuantaraDurableRecord record,
  ) => QuantaraDurableRecord(
    category: record.category,
    key: record.key,
    schemaVersion: record.schemaVersion,
    revision: record.revision,
    updatedAt: record.updatedAt,
    payload: _privacySafeMap(record.payload),
  );

  static Map<String, Object?> _privacySafeMap(Map<Object?, Object?> value) => {
    for (final entry in value.entries)
      if (!_privateKey(entry.key.toString()))
        entry.key.toString(): _privacySafeValue(entry.value),
  };

  static Object? _privacySafeValue(Object? value) {
    if (value is Map<Object?, Object?>) return _privacySafeMap(value);
    if (value is List<Object?>) {
      return value.map(_privacySafeValue).toList(growable: false);
    }
    return value;
  }

  static bool _privateKey(String key) {
    final normalized = key.toLowerCase().replaceAll(RegExp('[^a-z]'), '');
    return normalized.contains('apikey') ||
        normalized.contains('secret') ||
        normalized.contains('credential') ||
        normalized.contains('password') ||
        normalized.contains('token') ||
        normalized.contains('clientid');
  }

  static Map<String, Object?> _decodeObject(String text, String label) {
    final decoded = jsonDecode(text);
    if (decoded is! Map<Object?, Object?>) {
      throw FormatException('$label must be a JSON object.');
    }
    return {
      for (final entry in decoded.entries)
        entry.key.toString(): entry.value,
    };
  }

  static void _validatePassphrase(String passphrase) {
    if (passphrase.length < 12) {
      throw const FormatException(
        'Recovery passphrase must contain at least 12 characters.',
      );
    }
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
    if (input is Iterable) {
      return input.map(normalize).toList(growable: false);
    }
    return input;
  }

  return jsonEncode(normalize(value));
}

int _integer(Object? value, {int fallback = 0}) => value is num
    ? value.toInt()
    : int.tryParse(value?.toString() ?? '') ?? fallback;
