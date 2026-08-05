import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('closed positions detach even when optional history fetch fails', () {
    final source = File(
      'lib/features/auto_trade/application/local_live_trade_service.dart',
    ).readAsStringSync();

    expect(source, contains('var closedHistoryAvailable = false;'));
    expect(source, contains("'closed_history_deferred'"));
    expect(source, contains('_managed.remove(managed);'));
    expect(source, contains('pnlVerified: managedHistoryVerified'));
    expect(source, contains('_auditFingerprintSeenAt[fingerprint]'));
    expect(source, contains('if (!closedHistoryAvailable || !journalReconciled)'));
  });

  test('inactive adaptive target slots are not journalled as TP orders', () {
    final source = File(
      'lib/features/trading_journal/application/local_live_journal_observer.dart',
    ).readAsStringSync();

    expect(
      RegExp(
        r"if \(orderId\.trim\(\)\.isEmpty \|\| quantity <= 0\) continue;",
      ).allMatches(source),
      hasLength(2),
    );
  });
}
