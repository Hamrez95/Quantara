import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/core/persistence/quantara_durable_database.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  test(
    'conflicting atomic mutation rolls back without partial overwrite',
    () async {
      final database = SembastQuantaraDurableDatabase(
        factory: databaseFactoryMemory,
        path: 'portfolio-atomic-rollback.db',
      );
      await database.initialize();
      final original = QuantaraDurableRecord(
        category: QuantaraDurableCategory.managedPositions,
        key: 'portfolio-risk-ledger-v1',
        schemaVersion: 1,
        revision: 1,
        updatedAt: DateTime.utc(2026, 8, 4, 2),
        payload: const {'ledgerRevision': 1, 'pendingRisk': 3},
      );
      await database.put(original);

      await expectLater(
        database.mutateRecord<void>(
          category: QuantaraDurableCategory.managedPositions,
          key: 'portfolio-risk-ledger-v1',
          mutation: (current) async {
            expect(current?.checksum, original.checksum);
            return QuantaraAtomicRecordMutation<void>(
              value: null,
              nextRecord: QuantaraDurableRecord(
                category: QuantaraDurableCategory.managedPositions,
                key: 'portfolio-risk-ledger-v1',
                schemaVersion: 1,
                revision: 1,
                updatedAt: DateTime.utc(2026, 8, 4, 3),
                payload: const {'ledgerRevision': 1, 'pendingRisk': 9},
              ),
            );
          },
        ),
        throwsStateError,
      );

      final persisted = await database.read(
        QuantaraDurableCategory.managedPositions,
        'portfolio-risk-ledger-v1',
      );
      expect(persisted, isNotNull);
      expect(persisted!.checksum, original.checksum);
      expect(persisted.payload['pendingRisk'], 3);

      await database.close();
    },
  );

  test('throwing mutator leaves no durable record behind', () async {
    final database = SembastQuantaraDurableDatabase(
      factory: databaseFactoryMemory,
      path: 'portfolio-atomic-throw.db',
    );
    await database.initialize();

    await expectLater(
      database.mutateRecord<void>(
        category: QuantaraDurableCategory.managedPositions,
        key: 'portfolio-risk-ledger-v1',
        mutation: (current) async {
          expect(current, isNull);
          throw StateError('simulated decision failure');
        },
      ),
      throwsStateError,
    );

    expect(
      await database.read(
        QuantaraDurableCategory.managedPositions,
        'portfolio-risk-ledger-v1',
      ),
      isNull,
    );

    await database.close();
  });
}
