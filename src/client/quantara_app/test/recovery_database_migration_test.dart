import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:quantara_app/core/persistence/quantara_durable_database.dart';

void main() {
  test(
    'migrates every supported schema without losing durable records',
    () async {
      final factory = databaseFactoryMemory;
      final v1 = SembastQuantaraDurableDatabase(
        factory: factory,
        path: 'migration.db',
        targetSchemaVersion: 1,
      );
      await v1.initialize();
      await v1.put(
        QuantaraDurableRecord(
          category: QuantaraDurableCategory.settings,
          key: 'owner-alpha',
          schemaVersion: 1,
          revision: 4,
          updatedAt: DateTime.utc(2026, 8, 3),
          payload: const {
            'symbols': ['BTCUSDT', 'XRPUSDT'],
            'risk': 0.5,
          },
        ),
      );
      await v1.close();

      final v2 = SembastQuantaraDurableDatabase(
        factory: factory,
        path: 'migration.db',
        targetSchemaVersion: 2,
      );
      final health = await v2.initialize();
      final migrated = await v2.read(
        QuantaraDurableCategory.settings,
        'owner-alpha',
      );

      expect(health.schemaVersion, 2);
      expect(health.integrity, QuantaraDatabaseIntegrity.verified);
      expect(migrated, isNotNull);
      expect(migrated!.revision, 4);
      expect(migrated.payload['symbols'], ['BTCUSDT', 'XRPUSDT']);
      await v2.close();
    },
  );

  test(
    'failed migration rolls back and preserves the previous database',
    () async {
      final factory = databaseFactoryMemory;
      final original = SembastQuantaraDurableDatabase(
        factory: factory,
        path: 'rollback.db',
        targetSchemaVersion: 1,
      );
      await original.initialize();
      await original.put(
        QuantaraDurableRecord(
          category: QuantaraDurableCategory.journal,
          key: 'ledger',
          schemaVersion: 1,
          revision: 9,
          updatedAt: DateTime.utc(2026, 8, 3),
          payload: const {'generation': 9},
        ),
      );
      await original.close();

      final broken = SembastQuantaraDurableDatabase(
        factory: factory,
        path: 'rollback.db',
        targetSchemaVersion: 2,
        migrations: {
          2: (transaction) async {
            await transaction.put(
              QuantaraDurableRecord(
                category: QuantaraDurableCategory.metadata,
                key: 'half-written',
                schemaVersion: 2,
                revision: 1,
                updatedAt: DateTime.utc(2026, 8, 3),
                payload: const {'invalid': true},
              ),
            );
            throw StateError('simulated migration crash');
          },
        },
      );
      await expectLater(broken.initialize(), throwsStateError);

      final reopened = SembastQuantaraDurableDatabase(
        factory: factory,
        path: 'rollback.db',
        targetSchemaVersion: 1,
      );
      final health = await reopened.initialize();
      final ledger = await reopened.read(
        QuantaraDurableCategory.journal,
        'ledger',
      );
      final halfWritten = await reopened.read(
        QuantaraDurableCategory.metadata,
        'half-written',
      );

      expect(health.schemaVersion, 1);
      expect(ledger?.revision, 9);
      expect(halfWritten, isNull);
      await reopened.close();
    },
  );

  test(
    'secret records are rejected by the durable database boundary',
    () async {
      final database = SembastQuantaraDurableDatabase(
        factory: databaseFactoryMemory,
        path: 'secret-boundary.db',
      );
      await database.initialize();

      await expectLater(
        database.put(
          QuantaraDurableRecord(
            category: QuantaraDurableCategory.secret,
            key: 'bitunix-api-secret',
            schemaVersion: 1,
            revision: 1,
            updatedAt: DateTime.utc(2026, 8, 3),
            payload: const {'secretKey': 'must-never-persist'},
          ),
        ),
        throwsArgumentError,
      );
      await database.close();
    },
  );
}
