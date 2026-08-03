import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:quantara_app/core/persistence/quantara_durable_database.dart';
import 'package:quantara_app/features/recovery/data/encrypted_recovery_package.dart';

void main() {
  test('durable database rejects secret-like fields before export', () async {
    const apiKeyCanary = 'qtr-api-key-canary-never-persist';
    const secretKeyCanary = 'qtr-secret-key-canary-never-persist';
    final source = SembastQuantaraDurableDatabase(
      factory: databaseFactoryMemory,
      path: 'secret-boundary-source.db',
    );
    await source.initialize();

    Future<void> expectRejected({
      required String key,
      required Map<String, Object?> payload,
      required String canary,
    }) async {
      Object? rejection;
      try {
        await source.put(
          QuantaraDurableRecord(
            category: QuantaraDurableCategory.journal,
            key: key,
            schemaVersion: 1,
            revision: 1,
            updatedAt: DateTime.utc(2026, 8, 3),
            payload: payload,
          ),
        );
      } catch (error) {
        rejection = error;
      }
      expect(rejection, isA<ArgumentError>());
      expect(rejection.toString(), isNot(contains(canary)));
      expect(
        await source.read(QuantaraDurableCategory.journal, key),
        isNull,
      );
    }

    await expectRejected(
      key: 'forbidden-api-key',
      payload: const {'apiKey': apiKeyCanary},
      canary: apiKeyCanary,
    );
    await expectRejected(
      key: 'forbidden-nested-secret',
      payload: const {
        'nested': {'secretKey': secretKeyCanary},
      },
      canary: secretKeyCanary,
    );

    final persistedJson = jsonEncode(
      (await source.list()).map((record) => record.toStorageMap()).toList(),
    );
    expect(persistedJson, isNot(contains(apiKeyCanary)));
    expect(persistedJson, isNot(contains(secretKeyCanary)));
  });

  test(
    'encrypted recovery round trip exports only persistable privacy-safe data '
    'and is idempotent',
    () async {
      const externalCredentialCanaries = [
        'qtr-api-key-canary-outside-database',
        'qtr-secret-canary-outside-database',
      ];
      const privateClientReference = 'privacy-client-reference';
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
              {
                'eventId': 'fill:trade-1',
                'clientId': privateClientReference,
                'exchangeOrderId': 'order-1',
              },
            ],
            'strategy': 'trend-following',
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
      final envelopeJson = jsonEncode(jsonDecode(encrypted));
      for (final canary in externalCredentialCanaries) {
        expect(encrypted, isNot(contains(canary)));
        expect(envelopeJson, isNot(contains(canary)));
      }
      expect(encrypted, isNot(contains(privateClientReference)));
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
      expect(journal?.payload.toString(), contains('fill:trade-1'));
      expect(journal?.payload.toString(), contains('order-1'));
      expect(journal?.payload.toString(), isNot(contains('clientId')));
      expect(journal?.payload.toString(), isNot(contains(privateClientReference)));
    },
  );

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

    final current = await target.read(QuantaraDurableCategory.settings, 'app');
    expect(current?.revision, 99);
    expect(current?.payload['sentinel'], isTrue);
  });

  test('equal-revision restore conflict rolls back the whole batch', () async {
    final source = SembastQuantaraDurableDatabase(
      factory: databaseFactoryMemory,
      path: 'conflict-source.db',
    );
    await source.initialize();
    await source.putAll([
      QuantaraDurableRecord(
        category: QuantaraDurableCategory.journal,
        key: 'new-ledger',
        schemaVersion: 1,
        revision: 1,
        updatedAt: DateTime.utc(2026, 8, 3),
        payload: const {'events': <Object?>[]},
      ),
      QuantaraDurableRecord(
        category: QuantaraDurableCategory.settings,
        key: 'app',
        schemaVersion: 1,
        revision: 5,
        updatedAt: DateTime.utc(2026, 8, 3),
        payload: const {'language': 'fa'},
      ),
    ]);
    final encrypted = await EncryptedRecoveryPackage.export(
      database: source,
      passphrase: 'correct horse battery staple',
      appVersion: '1.2.0-rc.2+121',
    );

    final target = SembastQuantaraDurableDatabase(
      factory: databaseFactoryMemory,
      path: 'conflict-target.db',
    );
    await target.initialize();
    await target.put(
      QuantaraDurableRecord(
        category: QuantaraDurableCategory.settings,
        key: 'app',
        schemaVersion: 1,
        revision: 5,
        updatedAt: DateTime.utc(2026, 8, 4),
        payload: const {'language': 'en', 'sentinel': true},
      ),
    );

    await expectLater(
      EncryptedRecoveryPackage.restore(
        database: target,
        encryptedPackage: encrypted,
        passphrase: 'correct horse battery staple',
      ),
      throwsStateError,
    );

    final current = await target.read(QuantaraDurableCategory.settings, 'app');
    expect(current?.payload['language'], 'en');
    expect(current?.payload['sentinel'], isTrue);
    expect(
      await target.read(QuantaraDurableCategory.journal, 'new-ledger'),
      isNull,
    );
  });
}
