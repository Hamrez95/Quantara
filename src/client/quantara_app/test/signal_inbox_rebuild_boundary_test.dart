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
  test('manual trade entry point is not deadlocked by stale account UI state', () {
    final source = File(
      'lib/features/owner_alpha/presentation/owner_alpha_signals.dart',
    ).readAsStringSync();

    final gateStart = source.indexOf('String? _tradeBlockReason');
    final gateEnd = source.indexOf(
      'Future<void> _showManualTrade',
      gateStart,
    );
    final gate = source.substring(gateStart, gateEnd);

    expect(gate, contains('marketDataFresh'));
    expect(gate, contains('entry.validUntil'));
    expect(gate, contains('entry.stopLoss'));
    expect(gate, isNot(contains('autoTradeController.isConnected')));
    expect(gate, isNot(contains('autoTradeController.canStartNewEntry')));
    expect(source, contains('manualTradeController.prepare(entry)'));
    expect(
      source,
      contains(
        'private account snapshot',
      ),
      reason: 'The UI gate should document that account truth is refreshed by preflight.',
    );
  });

}
