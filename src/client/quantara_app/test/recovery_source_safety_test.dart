import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('backup and reinstall recovery have no credential or mutation authority', () {
    final root = Directory.current.path;
    String source(String path) => File('$root/$path').readAsStringSync();

    final recoverySources = [
      'lib/core/persistence/quantara_durable_database.dart',
      'lib/features/recovery/data/encrypted_recovery_package.dart',
      'lib/features/recovery/domain/exchange_reinstall_recovery.dart',
    ].map(source).join('\n');

    for (final forbidden in const [
      'BitunixApiCredentials',
      'secretKey',
      'apiKey',
      'placeMarketEntry(',
      'placePositionStop(',
      'placePartialTakeProfit(',
      'modifyPositionStop(',
      'cancelEntryOrder(',
      'closePositionReduceOnly(',
      'flash_close_position',
      '/trade/place_order',
      '/trade/modify_order',
      '/trade/cancel_orders',
    ]) {
      expect(recoverySources, isNot(contains(forbidden)));
    }
    expect(recoverySources, contains('QuantaraDurableCategory.secret'));
    expect(recoverySources, contains('RecoveryManagementMode.observeOnly'));
    expect(recoverySources, contains('requiresCredentialReconnect'));
  });
}
