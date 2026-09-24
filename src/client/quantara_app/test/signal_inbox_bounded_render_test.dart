import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Signal Inbox bounds initial heavy card rendering', () {
    final source = File(
      'lib/features/owner_alpha/presentation/owner_alpha_signals.dart',
    ).readAsStringSync();

    expect(source, contains('static const _pageSize = 20;'));
    expect(source, contains('.take(_visibleLimit)'));
    expect(source, contains("Key('signal-inbox-show-more')"));
    expect(
      source,
      isNot(contains('for (var index = 0; index < filtered.length; index++)')),
    );

    final stateStart = source.indexOf('class _SignalInboxViewState');
    final policyStart = source.indexOf('class _SignalPolicyCard', stateStart);
    final inboxState = source.substring(stateStart, policyStart);
    expect(
      inboxState,
      isNot(contains('_performanceJournalController.initialize()')),
    );
    expect(
      inboxState,
      contains('await _performanceJournalController.refresh()'),
    );
  });
}
