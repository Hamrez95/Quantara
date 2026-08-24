import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('entry attempt is durable before exchange mutation', () {
    final source = File(
      'lib/features/auto_trade/application/local_live_trade_service.dart',
    ).readAsStringSync();

    final durableAttempt = source.indexOf(
      '_executedSetupIds.add(idea.setupId);\n          await _persistState();',
    );
    final mutation = source.indexOf(
      'final placed = await exchange.placeMarketEntry(',
    );

    expect(durableAttempt, greaterThanOrEqualTo(0));
    expect(mutation, greaterThan(durableAttempt));
  });

  test('ambiguous post-submit failures remain fail closed', () {
    final source = File(
      'lib/features/auto_trade/application/local_live_trade_service.dart',
    ).readAsStringSync();

    expect(source, contains('if (orderRequestStarted) {'));
    expect(source, contains('await portfolioGuard.markAmbiguous('));
    expect(source, isNot(contains('_executedSetupIds.remove(idea.setupId)')));
  });
}
