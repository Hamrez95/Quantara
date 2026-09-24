import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Owner Alpha startup keeps destination-only controllers lazy', () {
    final source = File(
      'lib/features/owner_alpha/presentation/owner_alpha_page.dart',
    ).readAsStringSync();

    final initStart = source.indexOf('void initState()');
    final disposeStart = source.indexOf('void dispose()', initStart);
    expect(initStart, greaterThanOrEqualTo(0));
    expect(disposeStart, greaterThan(initStart));

    final initBody = source.substring(initStart, disposeStart);
    expect(initBody, contains('_autoTradeController.initialize()'));
    expect(initBody, isNot(contains('_tradingLabController.initialize()')));
    expect(
      initBody,
      isNot(contains('_unattendedAutoTradeController.initialize()')),
    );
    expect(initBody, isNot(contains('_journalController.initialize()')));

    expect(source, contains('_ensureDestinationInitialized'));
    expect(source, contains('case 4:'));
    expect(source, contains('case 5:'));
    expect(source, contains('case 6:'));
  });
}
