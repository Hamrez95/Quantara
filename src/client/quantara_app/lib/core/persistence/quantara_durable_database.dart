import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sembast/sembast.dart';

const quantaraDurableDatabaseSchemaVersion = 2;

enum QuantaraDurableCategory {
  metadata,
  settings,
  journal,
  signalHistory,
  audit,
  recoveryMetadata,
  managedPositions,
  cache,
  secret,
}

enum QuantaraDatabaseIntegrity { verified, recovered, unverified }

final class QuantaraDatabaseHealth {
  const QuantaraDatabaseHealth({
    required this.schemaVersion,
    required this.integrity,
    required this.lastMigrationAt,
    required this.warnings,
  });

  final int schemaVersion;
  final QuantaraDatabaseIntegrity integrity;
  final DateTime? lastMigrationAt;
  final List<String> warnings;
}

final class QuantaraDurableRecord {
  QuantaraDurableRecord({
    required this.category,
    required this.key,
    required this.schemaVersion,
    required this.revision,
    required this.updatedAt,
    required Map<String, Object?> payload,
  }) : payload = Map.unmodifiable(_stringMap(payload));

  final QuantaraDurableCategory category;
  final String key;
  final int schemaVersion;
  final int revision;
  final DateTime updatedAt;
  final Map<String, Object?> payload;

  String get storageKey => '${category.name}\u001f$key';

  String get checksum => sha256
      .convert(
        utf8.encode(
          _canonicalJson({
            'category': category.name,
            'key': key,
            'schemaVersion': schemaVersion,
            'revision': revision,
            'updatedAt': updatedAt.toUtc().toIso8601String(),
            'payload': payload,
          }),
        ),
      )
      .toString();

  Map<String, Object?> toStorageMap() => {
    'category': category.name,
    'key': key,
    'schemaVersion': schemaVersion,
    'revision': revision,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'payload': payload,
    'checksum': checksum,
  };

  factory QuantaraDurableRecord.fromStorageMap(Map<Object?, Object?> source) {
    final map = _stringMap(source);
    final categoryName = map['category']?.toString() ?? '';
    final category = QuantaraDurableCategory.values.firstWhere(
      (item) => item.name == categoryName,
      orElse: () =>
          throw const FormatException('Unsupported durable record category.'),
    );
    final payloadRaw = map['payload'];
    if (payloadRaw is! Map<Object?, Object?>) {
      throw const FormatException('Durable record payload was not an object.');
    }
    final record = QuantaraDurableRecord(
      category: category,
      key: map['key']?.toString() ?? '',
      schemaVersion: _integer(map['schemaVersion']),
      revision: _integer(map['revision']),
      updatedAt:
          DateTime.tryParse(map['updatedAt']?.toString() ?? '')?.toUtc() ??
          (throw const FormatException('Invalid durable record timestamp.')),
      payload: _stringMap(payloadRaw),
    );
    if (record.key.trim().isEmpty ||
        record.schemaVersion <= 0 ||
        record.revision < 0) {
      throw const FormatException('Invalid durable record identity.');
    }
    if (map['checksum']?.toString() != record.checksum) {
      throw const FormatException('Durable record checksum mismatch.');
    }
    return record;
  }
}

final class QuantaraRestoreResult {
  const QuantaraRestoreResult({
    required this.importedRecords,
    required this.alreadyApplied,
  });

  final int importedRecords;
  final bool alreadyApplied;
}

final class QuantaraAtomicRecordMutation<T> {
  const QuantaraAtomicRecordMutation({required this.value, this.nextRecord});

  final T value;
  final QuantaraDurableRecord? nextRecord;
}

typedef QuantaraDatabaseMigration =
    Future<void> Function(QuantaraMigrationTransaction transaction);

typedef QuantaraAtomicRecordMutator<T> =
    Future<QuantaraAtomicRecordMutation<T>> Function(
      QuantaraDurableRecord? current,
    );

abstract interface class QuantaraDurableDatabase {
  Future<QuantaraDatabaseHealth> initialize();
  Future<QuantaraDurableRecord?> read(
    QuantaraDurableCategory category,
    String key,
  );
  Future<List<QuantaraDurableRecord>> list({
    Set<QuantaraDurableCategory>? categories,
  });
  Future<void> put(QuantaraDurableRecord record);
  Future<void> putAll(Iterable<QuantaraDurableRecord> records);
  Future<void> delete(QuantaraDurableCategory category, String key);
  Future<QuantaraRestoreResult> restoreBatch({
    required String restoreId,
    required Iterable<QuantaraDurableRecord> records,
  });
  Future<void> close();
}

abstract interface class QuantaraAtomicDurableDatabase {
  Future<T> mutateRecord<T>({
    required QuantaraDurableCategory category,
    required String key,
    required QuantaraAtomicRecordMutator<T> mutation,
  });
}

final class QuantaraMigrationTransaction {
  QuantaraMigrationTransaction._(this._transaction, this._recordsStore);

  final Transaction _transaction;
  final StoreRef<String, Map<String, Object?>> _recordsStore;

  Future<QuantaraDurableRecord?> read(
    QuantaraDurableCategory category,
    String key,
  ) async {
    final raw = await _recordsStore
        .record(_recordKey(category, key))
        .get(_transaction);
    return raw == null ? null : QuantaraDurableRecord.fromStorageMap(raw);
  }

  Future<void> put(QuantaraDurableRecord record) async {
    _validateRecord(record);
    await _recordsStore
        .record(record.storageKey)
        .put(_transaction, record.toStorageMap());
  }

  Future<void> delete(QuantaraDurableCategory category, String key) =>
      _recordsStore.record(_recordKey(category, key)).delete(_transaction);
}

final class SembastQuantaraDurableDatabase
    implements QuantaraDurableDatabase, QuantaraAtomicDurableDatabase {
  factory SembastQuantaraDurableDatabase({
    required DatabaseFactory factory,
    required String path,
    int targetSchemaVersion = quantaraDurableDatabaseSchemaVersion,
    Map<int, QuantaraDatabaseMigration>? migrations,
  }) => SembastQuantaraDurableDatabase._(
    factory,
    path,
    targetSchemaVersion: targetSchemaVersion,
    migrations: migrations,
  );

  SembastQuantaraDurableDatabase._(
    this._factory,
    this._path, {
    this.targetSchemaVersion = quantaraDurableDatabaseSchemaVersion,
    Map<int, QuantaraDatabaseMigration>? migrations,
  }) : _migrations = Map.unmodifiable({
         1: _migrationV1,
         2: _migrationV2,
         ...?migrations,
       });

  static final StoreRef<String, Map<String, Object?>> _records =
      stringMapStoreFactory.store('durable_records');
  static final StoreRef<String, Map<String, Object?>> _metadata =
      stringMapStoreFactory.store('database_metadata');
  static final StoreRef<String, Map<String, Object?>> _restoreReceipts =
      stringMapStoreFactory.store('restore_receipts');
  static const _schemaKey = 'schema';

  final DatabaseFactory _factory;
  final String _path;
  final int targetSchemaVersion;
  final Map<int, QuantaraDatabaseMigration> _migrations;
  Database? _database;
  Future<void> _writeTail = Future<void>.value();

  Database get _db =>
      _database ??
      (throw StateError('Durable database has not been initialized.'));

  @override
  Future<QuantaraDatabaseHealth> initialize() async {
    if (targetSchemaVersion <= 0) {
      throw ArgumentError.value(targetSchemaVersion, 'targetSchemaVersion');
    }
    _database ??= await _factory.openDatabase(_path);
    var previousVersion = 0;
    DateTime? migratedAt;
    await _db.transaction((transaction) async {
      final schema = await _metadata.record(_schemaKey).get(transaction);
      previousVersion = _integer(schema?['schemaVersion']);
      if (previousVersion > targetSchemaVersion) {
        throw StateError(
          'Database schema $previousVersion is newer than supported '
          '$targetSchemaVersion.',
        );
      }
      for (
        var version = previousVersion + 1;
        version <= targetSchemaVersion;
        version++
      ) {
        final migration = _migrations[version];
        if (migration == null) {
          throw StateError('Missing database migration for schema $version.');
        }
        await migration(QuantaraMigrationTransaction._(transaction, _records));
      }
      if (previousVersion != targetSchemaVersion) {
        migratedAt = DateTime.now().toUtc();
        await _metadata.record(_schemaKey).put(transaction, {
          'schemaVersion': targetSchemaVersion,
          'lastMigrationAt': migratedAt!.toIso8601String(),
        });
      } else {
        migratedAt = DateTime.tryParse(
          schema?['lastMigrationAt']?.toString() ?? '',
        )?.toUtc();
      }
    });
    return QuantaraDatabaseHealth(
      schemaVersion: targetSchemaVersion,
      integrity: QuantaraDatabaseIntegrity.verified,
      lastMigrationAt: migratedAt,
      warnings: const [],
    );
  }

  @override
  Future<QuantaraDurableRecord?> read(
    QuantaraDurableCategory category,
    String key,
  ) async {
    final raw = await _records.record(_recordKey(category, key)).get(_db);
    return raw == null ? null : QuantaraDurableRecord.fromStorageMap(raw);
  }

  @override
  Future<List<QuantaraDurableRecord>> list({
    Set<QuantaraDurableCategory>? categories,
  }) async {
    final snapshots = await _records.find(_db);
    final records = <QuantaraDurableRecord>[];
    for (final snapshot in snapshots) {
      final record = QuantaraDurableRecord.fromStorageMap(snapshot.value);
      if (categories == null || categories.contains(record.category)) {
        records.add(record);
      }
    }
    records.sort((left, right) {
      final category = left.category.name.compareTo(right.category.name);
      return category != 0 ? category : left.key.compareTo(right.key);
    });
    return List.unmodifiable(records);
  }

  @override
  Future<void> put(QuantaraDurableRecord record) => _serial(() async {
    _validateRecord(record);
    await _db.transaction((transaction) async {
      await _putWithClient(transaction, record);
    });
  });

  @override
  Future<void> putAll(Iterable<QuantaraDurableRecord> records) =>
      _serial(() async {
        final materialized = records.toList(growable: false);
        for (final record in materialized) {
          _validateRecord(record);
        }
        await _db.transaction((transaction) async {
          for (final record in materialized) {
            await _putWithClient(transaction, record);
          }
        });
      });

  @override
  Future<void> delete(QuantaraDurableCategory category, String key) =>
      _serial(() => _records.record(_recordKey(category, key)).delete(_db));

  @override
  Future<T> mutateRecord<T>({
    required QuantaraDurableCategory category,
    required String key,
    required QuantaraAtomicRecordMutator<T> mutation,
  }) {
    if (category == QuantaraDurableCategory.secret) {
      throw ArgumentError('Secret records are forbidden in durable storage.');
    }
    if (key.trim().isEmpty || key.length > 240) {
      throw ArgumentError.value(key, 'key');
    }
    return _serialValue(() async {
      return _db.transaction((transaction) async {
        final storageKey = _recordKey(category, key);
        final raw = await _records.record(storageKey).get(transaction);
        final current = raw == null
            ? null
            : QuantaraDurableRecord.fromStorageMap(raw);
        final result = await mutation(current);
        final next = result.nextRecord;
        if (next != null) {
          if (next.category != category || next.key != key) {
            throw StateError(
              'Atomic mutation changed durable record identity.',
            );
          }
          _validateRecord(next);
          await _putWithClient(transaction, next);
        }
        return result.value;
      });
    });
  }

  @override
  Future<QuantaraRestoreResult> restoreBatch({
    required String restoreId,
    required Iterable<QuantaraDurableRecord> records,
  }) async {
    final normalizedId = restoreId.trim();
    if (normalizedId.isEmpty || normalizedId.length > 200) {
      throw ArgumentError.value(restoreId, 'restoreId');
    }
    final materialized = records.toList(growable: false);
    for (final record in materialized) {
      _validateRecord(record);
    }
    var result = const QuantaraRestoreResult(
      importedRecords: 0,
      alreadyApplied: false,
    );
    await _serial(() async {
      await _db.transaction((transaction) async {
        final receipt = await _restoreReceipts
            .record(normalizedId)
            .get(transaction);
        if (receipt != null) {
          result = const QuantaraRestoreResult(
            importedRecords: 0,
            alreadyApplied: true,
          );
          return;
        }
        var imported = 0;
        for (final incoming in materialized) {
          final existingRaw = await _records
              .record(incoming.storageKey)
              .get(transaction);
          final existing = existingRaw == null
              ? null
              : QuantaraDurableRecord.fromStorageMap(existingRaw);
          if (existing != null && existing.revision > incoming.revision) {
            continue;
          }
          if (existing != null && existing.revision == incoming.revision) {
            if (existing.checksum == incoming.checksum) {
              continue;
            }
            throw StateError('Conflicting durable record revision.');
          }
          await _records
              .record(incoming.storageKey)
              .put(transaction, incoming.toStorageMap());
          imported++;
        }
        await _restoreReceipts.record(normalizedId).put(transaction, {
          'appliedAt': DateTime.now().toUtc().toIso8601String(),
          'recordCount': materialized.length,
        });
        result = QuantaraRestoreResult(
          importedRecords: imported,
          alreadyApplied: false,
        );
      });
    });
    return result;
  }

  @override
  Future<void> close() async {
    final database = _database;
    _database = null;
    await database?.close();
  }

  Future<void> _putWithClient(
    DatabaseClient client,
    QuantaraDurableRecord record,
  ) async {
    final existingRaw = await _records.record(record.storageKey).get(client);
    if (existingRaw != null) {
      final existing = QuantaraDurableRecord.fromStorageMap(existingRaw);
      if (record.revision < existing.revision) {
        throw StateError('Durable record revision moved backwards.');
      }
      if (record.revision == existing.revision &&
          record.checksum != existing.checksum) {
        throw StateError('Conflicting durable record revision.');
      }
    }
    await _records.record(record.storageKey).put(client, record.toStorageMap());
  }

  Future<void> _serial(Future<void> Function() operation) =>
      _serialValue<void>(operation);

  Future<T> _serialValue<T>(Future<T> Function() operation) {
    final result = _writeTail.then((_) => operation());
    _writeTail = result.then<void>((_) {}).catchError((Object _) {});
    return result;
  }

  static Future<void> _migrationV1(
    QuantaraMigrationTransaction transaction,
  ) async {}

  static Future<void> _migrationV2(
    QuantaraMigrationTransaction transaction,
  ) async {
    final existing = await transaction.read(
      QuantaraDurableCategory.metadata,
      'data-classification',
    );
    if (existing != null) return;
    await transaction.put(
      QuantaraDurableRecord(
        category: QuantaraDurableCategory.metadata,
        key: 'data-classification',
        schemaVersion: 1,
        revision: 1,
        updatedAt: DateTime.now().toUtc(),
        payload: const {
          'encryptedUserData': [
            'settings',
            'journal',
            'signalHistory',
            'audit',
            'recoveryMetadata',
            'managedPositions',
          ],
          'reconstructableCache': ['cache'],
          'neverPersisted': ['secret'],
        },
      ),
    );
  }
}

void _validateRecord(QuantaraDurableRecord record) {
  if (record.category == QuantaraDurableCategory.secret) {
    throw ArgumentError('Secret records are forbidden in durable storage.');
  }
  if (record.key.trim().isEmpty || record.key.length > 240) {
    throw ArgumentError.value(record.key, 'record.key');
  }
  if (record.schemaVersion <= 0 || record.revision < 0) {
    throw ArgumentError('Invalid durable record version.');
  }
  if (_containsSecretLikeField(record.payload)) {
    throw ArgumentError('Secret-like fields are forbidden in durable data.');
  }
}

bool _containsSecretLikeField(Object? value) {
  if (value is Map<Object?, Object?>) {
    for (final entry in value.entries) {
      final normalized = entry.key.toString().toLowerCase().replaceAll(
        RegExp('[^a-z]'),
        '',
      );
      if (normalized.contains('apikey') ||
          normalized.contains('secret') ||
          normalized.contains('credential') ||
          normalized.contains('password') ||
          normalized.contains('token')) {
        return true;
      }
      if (_containsSecretLikeField(entry.value)) return true;
    }
  } else if (value is Iterable<Object?>) {
    return value.any(_containsSecretLikeField);
  }
  return false;
}

String _recordKey(QuantaraDurableCategory category, String key) =>
    '${category.name}\u001f$key';

Map<String, Object?> _stringMap(Map<Object?, Object?> source) => {
  for (final entry in source.entries) entry.key.toString(): entry.value,
};

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
