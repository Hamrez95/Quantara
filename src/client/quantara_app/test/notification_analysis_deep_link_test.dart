import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/app/quantara_app.dart';
import 'package:quantara_app/features/market_analysis/presentation/quantara_candlestick_chart.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';

import 'support/owner_alpha_test_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('notification launch opens its exact symbol and timeframe', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const setupId = 'notification-deep-link-setup';
    final gateway = RecordingSetupNotificationGateway(launchSetupId: setupId);
    addTearDown(gateway.dispose);
    final stateStore = MemoryOpportunityStateStore()
      ..value = OpportunityState(journal: [_entry(setupId)]);

    await tester.pumpWidget(
      QuantaraApp(
        repository: const FakeOwnerAlphaRepository(),
        settingsStore: MemoryOwnerAlphaSettingsStore(),
        preferencesStore: MemoryAppPreferencesStore(),
        opportunityStateStore: stateStore,
        notificationGateway: gateway,
        initialLocale: const Locale('fa'),
      ),
    );
    await tester.pumpAndSettle();

    final chart = tester.widget<QuantaraCandlestickChart>(
      find.byType(QuantaraCandlestickChart),
    );
    expect(chart.analysis.symbol, 'BTCUSDT');
    expect(chart.analysis.timeframe, '15m');
    expect(find.textContaining('BTCUSDT · 15m'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('notification tap while running reuses the same analysis path', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const setupId = 'notification-live-deep-link';
    final gateway = RecordingSetupNotificationGateway();
    addTearDown(gateway.dispose);
    final stateStore = MemoryOpportunityStateStore()
      ..value = OpportunityState(journal: [_entry(setupId)]);
    await tester.pumpWidget(
      QuantaraApp(
        repository: const FakeOwnerAlphaRepository(),
        settingsStore: MemoryOwnerAlphaSettingsStore(),
        preferencesStore: MemoryAppPreferencesStore(),
        opportunityStateStore: stateStore,
        notificationGateway: gateway,
      ),
    );
    await tester.pumpAndSettle();

    gateway.open(setupId);
    await tester.pumpAndSettle();

    final chart = tester.widget<QuantaraCandlestickChart>(
      find.byType(QuantaraCandlestickChart),
    );
    expect(chart.analysis.symbol, 'BTCUSDT');
    expect(chart.analysis.timeframe, '15m');
    expect(tester.takeException(), isNull);
  });
}

SignalJournalEntry _entry(String setupId) => SignalJournalEntry(
  setupId: setupId,
  symbol: 'BTCUSDT',
  timeframe: '15m',
  direction: TradeDirection.long,
  strategy: AnalysisStrategy.structureZones,
  strategyVersion: 'test-v1',
  createdAt: DateTime.utc(2026, 8, 18, 10),
  validUntil: DateTime.utc(2030),
  entryLower: 1,
  entryUpper: 2,
  stopLoss: 0.5,
  targets: const [3, 4, 5],
  maximumLoss: 10,
  positionSize: 1,
  notionalValue: 100,
  estimatedRoundTripCosts: 0.1,
  recommendedLeverage: 2,
  maximumSafeLeverage: 3,
  selectedLeverage: 2,
  summary: 'Notification setup',
  invalidation: 'Below 0.5',
  confidencePercent: 80,
  outcome: SignalOutcome.active,
);
