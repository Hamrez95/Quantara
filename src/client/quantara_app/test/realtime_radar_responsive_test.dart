import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/app/quantara_app.dart';
import 'package:quantara_app/features/owner_alpha/data/realtime_production_runtime.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/realtime_candidate_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/realtime_market_runtime_models.dart';

import 'support/owner_alpha_test_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final testCase in <({Locale locale, String label})>[
    (locale: const Locale('fa'), label: 'دیدن تحلیل'),
    (locale: const Locale('en'), label: 'View analysis'),
  ]) {
    testWidgets(
      'realtime Radar remains readable across responsive widths in ${testCase.locale.languageCode}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        for (final width in const [320.0, 360.0, 390.0, 430.0, 768.0, 1280.0]) {
          tester.view.physicalSize = Size(width, 900);
          tester.platformDispatcher.textScaleFactorTestValue = width == 320
              ? 2
              : 1;
          final host = RealtimeMarketHost(runtime: _RadarRuntime());
          await tester.pumpWidget(
            QuantaraApp(
              repository: const FakeOwnerAlphaRepository(),
              settingsStore: MemoryOwnerAlphaSettingsStore(),
              preferencesStore: MemoryAppPreferencesStore(),
              opportunityStateStore: MemoryOpportunityStateStore(),
              notificationGateway: RecordingSetupNotificationGateway(),
              realtimeMarketHost: host,
              initialLocale: testCase.locale,
              initialThemeMode: width == 390 ? ThemeMode.light : ThemeMode.dark,
            ),
          );
          await tester.pumpAndSettle();

          final action = find.text(testCase.label);
          await tester.ensureVisible(action.first);
          await tester.pump();

          expect(action, findsOneWidget);
          expect(find.textContaining('72/100'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
      },
    );
  }
}

final class _RadarRuntime implements RealtimeMarketRuntimeLifecycle {
  RealtimeMarketRuntimeState _state = RealtimeMarketRuntimeState.idle;

  @override
  RealtimeMarketRuntimeState get state => _state;

  @override
  int get candidateSnapshotRevision => 1;

  @override
  List<RealtimeOpportunityCandidate> get radarCandidates => [_candidate()];

  @override
  RealtimeMarketHealthSnapshot get health => RealtimeMarketHealthSnapshot(
    state: _state,
    configuredStreams: 1,
    activeStreams: 1,
    activeShards: 1,
    liveShards: _state == RealtimeMarketRuntimeState.live ? 1 : 0,
    eventsReceived: 1,
    klineEventsReceived: 1,
    closedCandleEvents: 1,
    gapEvents: 0,
    reconciliationEvents: 0,
    candidateEvaluations: 1,
    candidateCommits: 1,
    reconnectTransitions: 0,
    malformedPayloadFaults: 0,
    backpressureFaults: 0,
    p95TransportLag: const Duration(milliseconds: 80),
    p95PipelineLatency: const Duration(milliseconds: 12),
    lastEventAtUtc: DateTime.now().toUtc(),
    lastFaultAtUtc: null,
    lastFaultMessage: null,
  );

  @override
  Future<void> start() async => _state = RealtimeMarketRuntimeState.live;

  @override
  Future<void> resume() async => _state = RealtimeMarketRuntimeState.live;

  @override
  Future<void> pause() async => _state = RealtimeMarketRuntimeState.paused;

  @override
  Future<void> stop() async => _state = RealtimeMarketRuntimeState.stopped;
}

RealtimeOpportunityCandidate _candidate() {
  final detected = DateTime.now().toUtc().subtract(const Duration(seconds: 2));
  return RealtimeOpportunityCandidate.fromIdea(
    TradeIdea(
      symbol: 'VERYLONGSYMBOLUSDT',
      timeframe: '15m',
      direction: TradeDirection.long,
      confidencePercent: 72,
      setupQualityScore: 72,
      entryLower: 100,
      entryUpper: 101,
      stopLoss: 98,
      targets: const [102, 104],
      riskReward: 2,
      maximumLoss: 50,
      positionSize: 1,
      notionalValue: 100,
      recommendedLeverage: 2,
      maximumSafeLeverage: 5,
      requiredMargin: 50,
      estimatedRoundTripCosts: 0.2,
      setupId: 'VERYLONGSYMBOLUSDT|15m|long|responsive',
      candleClosedAt: detected.subtract(const Duration(minutes: 15)),
      summary: 'Responsive realtime setup',
      invalidation: 'Below 98',
      reasons: const ['test'],
      rejectionReason: SetupRejectionReason.none,
      strategy: AnalysisStrategy.structureZones,
      strategyVersion: 'very-long-playbook-version/1.0',
    ),
    detectedAtUtc: detected,
  );
}
