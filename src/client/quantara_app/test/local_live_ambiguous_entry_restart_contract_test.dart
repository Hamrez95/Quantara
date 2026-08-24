import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('entry attempt is durable before exchange mutation', () {
    final source = File(
      'lib/features/auto_trade/application/local_live_trade_service.dart',
    ).readAsStringSync();

    final attempted = source.indexOf(
      'OpportunityRankingOutcome.executionAttempted',
    );
    final durableIdentity = source.indexOf(
      '_executedSetupIds.add(idea.setupId);',
      attempted,
    );
    final durablePersist = source.indexOf(
      'await _persistState();',
      durableIdentity,
    );
    final mutation = source.indexOf(
      'final placed = await exchange.placeMarketEntry(',
      attempted,
    );

    expect(attempted, greaterThanOrEqualTo(0));
    expect(durableIdentity, greaterThan(attempted));
    expect(durablePersist, greaterThan(durableIdentity));
    expect(mutation, greaterThan(durablePersist));
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
