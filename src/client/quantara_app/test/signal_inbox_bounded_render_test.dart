import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Signal Inbox uses a viewport-lazy sliver list', () {
    final source = File(
      'lib/features/owner_alpha/presentation/owner_alpha_signals.dart',
    ).readAsStringSync();

    expect(source, contains('CustomScrollView('));
    expect(source, contains('SliverChildBuilderDelegate('));
    expect(source, contains('childCount: filtered.length'));
    expect(source, isNot(contains('_visibleLimit')));
    expect(source, isNot(contains('signal-inbox-show-more')));
    expect(
      source,
      contains(r"PageStorageKey<String>('signal-card-${entry.setupId}')"),
    );
    expect(source, contains(r"'signal-diagnostics-${entry.setupId}'"));
    expect(source, contains("Key('setup-performance-open')"));
    expect(
      source,
      contains(r"ValueKey('manual-trade-open-${entry.setupId}')"),
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

  test('Owner Alpha gives Setup Inbox ownership of the scroll viewport', () {
    final source = File(
      'lib/features/owner_alpha/presentation/owner_alpha_page.dart',
    ).readAsStringSync();

    expect(
      source,
      contains('if (destination == 1 && controller.snapshot != null)'),
    );
    expect(
      source,
      contains("scrollKey: PageStorageKey('owner-alpha-\$destination')"),
    );
  });
}
