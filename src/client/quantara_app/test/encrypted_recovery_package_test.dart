import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:quantara_app/core/persistence/quantara_durable_database.dart';
import 'package:quantara_app/features/recovery/data/encrypted_recovery_package.dart';

void main() {
  test('encrypted recovery round trip excludes secrets and is idempotent', () async {
    final source = SembastQuantaraDurableDatabase(
      factory: databaseFactoryMemory,
      path: 'backup-source.db',
    );
    await source.initialize();
    await source.putAll([
      QuantaraDurableRecord(
        category: QuantaraDurableCategory.settings,
        key: 'app',
        schemaVersion: 1,
        revision: 2,
        updatedAt: DateTime.utc(2026, 8, 3),
        payload: const {'language': 'fa', 'theme': 'dark'},
      ),
      QuantaraDurableRecord(
        category: QuantaraDurableCategory.journal,
        key: 'ledger',
        schemaVersion: 1,
        revision: 7,
        updatedAt: DateTime.utc(2026, 8, 3),
        payload: const {
          'events': [
            {'eventId': 'fill:trade-1', 'clientId': 'redact-me'},
          ],
          'apiKey': 'never-export',
          'nested': {'secretKey': 'never-export-either'},
        },
      ),
      QuantaraDurableRecord(
        category: QuantaraDurableCategory.cache,
        key: 'candles',
        schemaVersion: 1,
        revision: 1,
        updatedAt: DateTime.utc(2026, 8, 3),
        payload: const {'count': 1000},
      ),
    ]);

    final encrypted = await EncryptedRecoveryPackage.export(
      database: source,
      passphrase: 'correct horse battery staple',
      appVersion: '1.2.0-rc.2+121',
    );
    expect(encrypted, isNot(contains('never-export')));
    expect(encrypted, isNot(contains('redact-me')));
    expect(encrypted, isNot(contains('candles')));

    final target = SembastQuantaraDurableDatabase(
      factory: databaseFactoryMemory,
      path: 'backup-target.db',
    );
    await target.initialize();
    final first = await EncryptedRecoveryPackage.restore(
      database: target,
      encryptedPackage: encrypted,
      passphrase: 'correct horse battery staple',
    );
    final second = await EncryptedRecoveryPackage.restore(
      database: target,
      encryptedPackage: encrypted,
      passphrase: 'correct horse battery staple',
    );

    expect(first.importedRecords, 2);
    expect(first.alreadyApplied, isFalse);
    expect(second.importedRecords, 0);
    expect(second.alreadyApplied, isTrue);
    expect(
      (await target.list()).where((record) => record.key == 'ledger'),
      hasLength(1),
    );
    final journal = await target.read(
      QuantaraDurableCategory.journal,
      'ledger',
    );
    expect(journal?.payload.toString(), isNot(contains('clientId')));
    expect(journal?.payload.toString(), isNot(contains('apiKey')));
    expect(journal?.payload.toString(), isNot(contains('secretKey')));
  });

  test('wrong password or corruption cannot overwrite current data', () async {
    final source = SembastQuantaraDurableDatabase(
      factory: databaseFactoryMemory,
      path: 'corrupt-source.db',
    );
    await source.initialize();
    await source.put(
      QuantaraDurableRecord(
        category: QuantaraDurableCategory.settings,
        key: 'app',
        schemaVersion: 1,
        revision: 1,
        updatedAt: DateTime.utc(2026, 8, 3),
        payload: const {'language': 'fa'},
      ),
    );
    final encrypted = await EncryptedRecoveryPackage.export(
      database: source,
      passphrase: 'correct horse battery staple',
      appVersion: '1.2.0-rc.2+121',
    );

    final target = SembastQuantaraDurableDatabase(
      factory: databaseFactoryMemory,
      path: 'corrupt-target.db',
    );
    await target.initialize();
    await target.put(
      QuantaraDurableRecord(
        category: QuantaraDurableCategory.settings,
        key: 'app',
        schemaVersion: 1,
        revision: 99,
        updatedAt: DateTime.utc(2026, 8, 4),
        payload: const {'language': 'en', 'sentinel': true},
      ),
    );

    await expectLater(
      EncryptedRecoveryPackage.restore(
        database: target,
        encryptedPackage: encrypted,
        passphrase: 'wrong password value',
      ),
      throwsA(anything),
    );
    final corrupted = encrypted.replaceFirst('cipherText', 'cipherTextBroken');
    await expectLater(
      EncryptedRecoveryPackage.restore(
        database: target,
        encryptedPackage: corrupted,
        passphrase: 'correct horse battery staple',
      ),
      throwsFormatException,
    );

    final current = await target.read(
      QuantaraDurableCategory.settings,
      'app',
    );
    expect(current?.revision, 99);
    expect(current?.payload['sentinel'], isTrue);
  });
}
