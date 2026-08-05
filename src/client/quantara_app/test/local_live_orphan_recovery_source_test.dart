import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('service publishes exchange truth instead of only the local ledger', () {
    final source = File(
      'lib/features/auto_trade/application/local_live_trade_service.dart',
    ).readAsStringSync();
    expect(source, contains('openPositionCount: _exchangeOpenPositionCount'));
    expect(source, contains('managedPositionCount: _managed.length'));
    expect(
      source,
      contains('unmanagedPositionCount: _unmanagedSymbols.length'),
    );
    expect(source, contains('_recoverVerifiedQuantaraOrphans'));
    expect(source, contains('recordRecoveredPosition'));
    expect(source, contains('adoptVerifiedOpenPosition'));
    expect(source, isNot(contains('openPositionCount: _managed.length')));
  });

  test(
    'secure recovery starts management-only and requires a later explicit arm',
    () {
      final controller = File(
        'lib/features/auto_trade/application/local_live_trade_controller.dart',
      ).readAsStringSync();
      final ui = File(
        'lib/features/owner_alpha/presentation/owner_alpha_auto_trade.dart',
      ).readAsStringSync();
      expect(controller, contains('bool recoveryOnly = false'));
      expect(
        controller,
        contains(
          'ExchangeTruthPhaseOneGate.realEntriesAllowed && !recoveryOnly',
        ),
      );
      expect(ui, contains('recoveryOnly: unrecoveredCount > 0'));
      expect(ui, contains('Confirm & recover'));
    },
  );

  test('notification does not claim the exchange is flat during recovery', () {
    final source = File(
      'lib/features/auto_trade/application/local_live_trade_service.dart',
    ).readAsStringSync();
    expect(source, contains('Secure exchange recovery'));
    expect(source, contains('recovery pending · entries blocked'));
  });
}
