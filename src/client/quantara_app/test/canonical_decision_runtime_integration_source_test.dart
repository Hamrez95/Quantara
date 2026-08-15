import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('paper broker consumes canonical pre-execution decision', () {
    final source = File(
      'lib/features/trading_lab/application/trading_lab_paper_broker.dart',
    ).readAsStringSync();
    expect(source, contains('evaluateTradingLabCanonicalDecision'));
    expect(source, contains('DecisionEnvironment.paper'));
    expect(source, contains('canonical.quantity'));
    expect(source, contains('canonical.leverage'));
    expect(source, contains('canonical.requiredMargin'));
    expect(
      source,
      isNot(contains('final quantity = riskBudget / stopDistance')),
    );
  });

  test('local live uses canonical sizing before atomic reservation', () {
    final source = File(
      'lib/features/auto_trade/application/local_live_trade_service.dart',
    ).readAsStringSync();
    expect(source, contains('evaluateLocalLiveCanonicalDecision'));
    expect(source, contains('canonical.normalizedEntry'));
    expect(source, contains('canonical.normalizedStop'));
    expect(source, contains('canonical.quantity'));
    expect(source, isNot(contains('entryPrice * 0.0017')));
    expect(source, contains('portfolioGuard.reserve'));
    expect(source, contains('exchange.placeMarketEntry'));
  });
}
