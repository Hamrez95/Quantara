import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Phase 1 reconciliation remains observer-only and fail closed', () {
    final domain = File(
      'lib/features/auto_trade/domain/private_account_reconciliation.dart',
    ).readAsStringSync();
    final controller = File(
      'lib/features/auto_trade/application/local_live_trade_controller.dart',
    ).readAsStringSync();
    final service = File(
      'lib/features/auto_trade/application/local_live_trade_service.dart',
    ).readAsStringSync();

    expect(domain, contains('static const bool realEntriesAllowed = false'));
    expect(domain, isNot(contains('placeOrder')));
    expect(domain, isNot(contains('cancelOrder')));
    expect(domain, isNot(contains('withdraw')));
    expect(domain, isNot(contains('transfer')));
    expect(controller, contains("'entriesEnabled': entriesEnabled"));
    expect(service, contains('bool _entriesEnabled = false'));
    expect(service, contains("case 'block_entries_private_state':"));
    expect(
      service,
      contains('Existing protected positions continue to be reconciled.'),
    );
  });
}
