import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('local-live journal persists the trade idea indicator snapshot', () {
    final source = File(
      'lib/features/trading_journal/application/local_live_journal_observer.dart',
    ).readAsStringSync();

    expect(source, contains('indicatorSnapshot: idea.indicatorSnapshot'));
  });
}
