import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('account state does not rebuild the whole Signal Inbox', () {
    final source = File(
      'lib/features/owner_alpha/presentation/owner_alpha_signals.dart',
    ).readAsStringSync();

    final stateStart = source.indexOf('class _SignalInboxViewState');
    final policyStart = source.indexOf('class _SignalPolicyCard', stateStart);
    final inboxState = source.substring(stateStart, policyStart);

    expect(inboxState, isNot(contains('_onAutoTradeStateChanged')));
    expect(inboxState, isNot(contains('autoTradeController.addListener')));
    expect(source, contains('animation: tradeAvailabilityListenable'));
    expect(
      'animation: tradeAvailabilityListenable'.allMatches(source).length,
      greaterThanOrEqualTo(2),
    );
    expect(source, contains('now: DateTime.now().toUtc()'));
  });
}
