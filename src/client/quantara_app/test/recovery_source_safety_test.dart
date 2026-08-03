import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'backup and reinstall recovery have no credential or mutation authority',
    () {
      final root = Directory.current.path;
      String source(String path) => File('$root/$path').readAsStringSync();

      final durableDatabaseSource = source(
        'lib/core/persistence/quantara_durable_database.dart',
      );
      final encryptedPackageSource = source(
        'lib/features/recovery/data/encrypted_recovery_package.dart',
      );
      final reinstallRecoverySource = source(
        'lib/features/recovery/domain/exchange_reinstall_recovery.dart',
      );
      final recoverySources = [
        durableDatabaseSource,
        encryptedPackageSource,
        reinstallRecoverySource,
      ].join('\n');

      final importPaths = RegExp(r"import\s+'([^']+)'")
          .allMatches(recoverySources)
          .map((match) => match.group(1) ?? '')
          .toList(growable: false);
      for (final importPath in importPaths) {
        for (final forbiddenFragment in const [
          '/auto_trade/',
          'bitunix',
          'credential_store',
          'secure_credentials',
          'secure_storage',
        ]) {
          expect(importPath, isNot(contains(forbiddenFragment)));
        }
      }

      for (final forbiddenAuthority in const [
        'BitunixApiCredentials',
        'BitunixLocalLiveApiClient',
        'ExchangeCredentialStore',
        'placeOrder(',
        'placeMarketEntry(',
        'placePositionStop(',
        'placePartialTakeProfit(',
        'modifyPositionStop(',
        'cancelOrder(',
        'cancelEntryOrder(',
        'closePositionReduceOnly(',
        'withdraw(',
        'transfer(',
        'flash_close_position',
        '/trade/place_order',
        '/trade/modify_order',
        '/trade/cancel_orders',
        '/assets/withdraw',
        '/assets/transfer',
      ]) {
        expect(recoverySources, isNot(contains(forbiddenAuthority)));
      }

      expect(
        encryptedPackageSource,
        contains('secretKey: key'),
        reason:
            'cryptography uses secretKey as an AES-GCM parameter; it is not an '
            'exchange credential store.',
      );
      expect(
        durableDatabaseSource,
        contains('Secret-like fields are forbidden in durable data.'),
      );
      expect(durableDatabaseSource, contains("normalized.contains('apikey')"));
      expect(
        durableDatabaseSource,
        contains("normalized.contains('credential')"),
      );
      expect(recoverySources, contains('QuantaraDurableCategory.secret'));
      expect(reinstallRecoverySource, contains('newEntriesAllowed: false'));
      expect(
        reinstallRecoverySource,
        contains('RecoveryManagementMode.observeOnly'),
      );
      expect(
        reinstallRecoverySource,
        contains('requiresCredentialReconnect: true'),
      );
    },
  );
}
