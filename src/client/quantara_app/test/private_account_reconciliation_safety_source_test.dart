import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('guarded Local Live authority remains explicit and fail closed', () {
    final domain = File(
      'lib/features/auto_trade/domain/private_account_reconciliation.dart',
    ).readAsStringSync();
    final controller = File(
      'lib/features/auto_trade/application/local_live_trade_controller.dart',
    ).readAsStringSync();
    final service = File(
      'lib/features/auto_trade/application/local_live_trade_service.dart',
    ).readAsStringSync();

    expect(domain, contains('static const bool realEntriesAllowed = true'));
    expect(domain, contains('static const bool explicitUserArmRequired = true'));
    expect(domain, contains('static const bool automaticArmAllowed = false'));
    expect(domain, isNot(contains('placeOrder')));
    expect(domain, isNot(contains('cancelOrder')));
    expect(domain, isNot(contains('withdraw')));
    expect(domain, isNot(contains('transfer')));
    expect(controller, contains("'entriesEnabled': entriesEnabled"));
    expect(controller, contains('allowAutoRestart: false'));
    expect(controller, contains('autoRunOnBoot: false'));
    expect(controller, contains('autoRunOnMyPackageReplaced: false'));
    expect(service, contains('bool _entriesEnabled = false'));
    expect(service, contains("case 'block_entries_private_state':"));
    expect(
      service,
      contains('Existing protected positions continue to be reconciled.'),
    );
  });
}
