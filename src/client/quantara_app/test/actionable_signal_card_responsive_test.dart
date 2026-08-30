import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/app/quantara_app.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';

import 'support/owner_alpha_test_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final testCase in <({Locale locale, String actionLabel})>[
    (locale: const Locale('fa'), actionLabel: 'اقدام امن'),
    (locale: const Locale('en'), actionLabel: 'Safe next action'),
  ]) {
    testWidgets(
      'actionable summary survives 320px large text in ${testCase.locale.languageCode}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 700);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        final stateStore = MemoryOpportunityStateStore()
          ..value = OpportunityState(journal: [_activeEntry()]);
        await tester.pumpWidget(
          QuantaraApp(
            repository: const FakeOwnerAlphaRepository(),
            settingsStore: MemoryOwnerAlphaSettingsStore(),
            preferencesStore: MemoryAppPreferencesStore(),
            opportunityStateStore: stateStore,
            notificationGateway: RecordingSetupNotificationGateway(),
            initialLocale: testCase.locale,
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

        final action = find.textContaining(testCase.actionLabel);
        await tester.ensureVisible(action.first);
        await tester.pump();

        expect(action, findsWidgets);
        expect(find.textContaining('Setup Quality 91'), findsNothing);
        expect(find.textContaining('کیفیت ستاپ 91'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

SignalJournalEntry _activeEntry() => SignalJournalEntry(
  setupId: 'TESTUSDT|15m|long|responsive',
  symbol: 'BTCUSDT',
  timeframe: '15m',
  direction: TradeDirection.long,
  strategy: AnalysisStrategy.structureZones,
  strategyVersion: 'test-v1',
  createdAt: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
  validUntil: DateTime.now().toUtc().add(const Duration(hours: 1)),
  entryLower: 1,
  entryUpper: 2,
  stopLoss: 0.5,
  targets: const [3, 4],
  maximumLoss: 10,
  positionSize: 1,
  notionalValue: 100,
  estimatedRoundTripCosts: 0.1,
  recommendedLeverage: 2,
  maximumSafeLeverage: 3,
  selectedLeverage: 2,
  summary: 'Responsive test setup',
  invalidation: 'Below 0.5',
  confidencePercent: 91,
  setupQualityScore: null,
  outcome: SignalOutcome.active,
  activatedAt: DateTime.now().toUtc().subtract(const Duration(minutes: 2)),
);
