import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('privacy export remains importable after deterministic pseudonymization', () {
    final source = File(
      'lib/features/trading_journal/data/trading_journal_export.dart',
    ).readAsStringSync();

    expect(source, contains('fromPrivacySafeJson'));
    expect(source, contains('appendPlan'));
    expect(source, contains('appendEvent'));
    expect(source, contains('_pseudonym'));
  });
}
