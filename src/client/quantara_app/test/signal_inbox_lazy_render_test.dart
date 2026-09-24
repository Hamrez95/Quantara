import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/app/quantara_app.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';

import 'support/owner_alpha_test_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Signal Inbox materializes only viewport setup cards', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now().toUtc();
    final entries = List.generate(
      82,
      (index) => _entry(index: index, now: now),
      growable: false,
    );
    final stateStore = MemoryOpportunityStateStore()
      ..value = OpportunityState(journal: entries);

    await tester.pumpWidget(
      QuantaraApp(
        repository: const FakeOwnerAlphaRepository(),
        settingsStore: MemoryOwnerAlphaSettingsStore(),
        preferencesStore: MemoryAppPreferencesStore(),
        opportunityStateStore: stateStore,
        notificationGateway: RecordingSetupNotificationGateway(),
        initialLocale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();

    final navigation = find.byType(NavigationBar);
    final inbox = find.descendant(
      of: navigation,
      matching: find.byIcon(Icons.inbox_outlined),
    );
    await tester.tap(inbox.first);
    await tester.pumpAndSettle();

    final materialized = find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> &&
          key.value.startsWith('manual-trade-open-');
    });

    final scrollView = find.byType(CustomScrollView);
    expect(scrollView, findsOneWidget);

    for (
      var attempt = 0;
      attempt < 8 && materialized.evaluate().isEmpty;
      attempt++
    ) {
      await tester.drag(scrollView, const Offset(0, -500));
      await tester.pump();
    }

    final initiallyBuilt = materialized.evaluate().length;
    expect(initiallyBuilt, greaterThan(0));
    expect(initiallyBuilt, lessThan(entries.length));
    expect(
      find.byKey(const ValueKey('manual-trade-open-PERF81USDT|15m|long|81')),
      findsNothing,
    );

    final lastCard = find.byKey(
      const ValueKey('manual-trade-open-PERF81USDT|15m|long|81'),
    );
    for (var attempt = 0; attempt < 160 && lastCard.evaluate().isEmpty; attempt++) {
      await tester.drag(scrollView, const Offset(0, -600));
      await tester.pump();
    }

    expect(lastCard, findsOneWidget);
  });
}

SignalJournalEntry _entry({required int index, required DateTime now}) {
  final symbol = 'PERF${index}USDT';
  return SignalJournalEntry(
    setupId: '$symbol|15m|long|$index',
    symbol: symbol,
    timeframe: '15m',
    direction: TradeDirection.long,
    strategy: AnalysisStrategy.structureZones,
    strategyVersion: 'perf-test-v1',
    createdAt: now.subtract(Duration(minutes: index + 1)),
    validUntil: now.add(const Duration(hours: 2)),
    entryLower: 100,
    entryUpper: 101,
    stopLoss: 95,
    targets: const [110, 120, 130],
    maximumLoss: 10,
    positionSize: 1,
    notionalValue: 100,
    estimatedRoundTripCosts: 0.1,
    recommendedLeverage: 2,
    maximumSafeLeverage: 3,
    selectedLeverage: 2,
    summary: 'Lazy render setup $index',
    invalidation: 'Below 95',
    confidencePercent: 80,
    setupQualityScore: 90,
    outcome: SignalOutcome.active,
    activatedAt: now.subtract(Duration(minutes: index + 1)),
  );
}
