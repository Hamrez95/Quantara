import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/market_analysis/domain/market_chart_models.dart';
import 'package:quantara_app/features/owner_alpha/application/owner_alpha_controller.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';

import 'support/owner_alpha_test_fakes.dart';

void main() {
  test(
    'risk changes reprice the cached plan without a market request',
    () async {
      final repository = _SwitchableRepository();
      final controller = OwnerAlphaController(
        repository: repository,
        settingsStore: MemoryOwnerAlphaSettingsStore(),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      final requestsBefore = repository.requests;

      await controller.updateRiskSettings(capital: 20000, riskPercent: 2);

      expect(repository.requests, requestsBefore);
      expect(controller.snapshot!.selectedIdea.maximumLoss, 400);
    },
  );

  test('failed timeframe refresh restores the previous selection', () async {
    final repository = _SwitchableRepository();
    final controller = OwnerAlphaController(
      repository: repository,
      settingsStore: MemoryOwnerAlphaSettingsStore(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    repository.fail = true;

    await controller.selectTimeframe('1D');

    expect(controller.selectedTimeframe, '1h');
    expect(controller.snapshot!.selectedTimeframe, '1h');
    expect(controller.error, isNotNull);
  });

  test(
    'cached symbol and timeframe selections make no market request',
    () async {
      final repository = _SwitchableRepository();
      final controller = OwnerAlphaController(
        repository: repository,
        settingsStore: MemoryOwnerAlphaSettingsStore(),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      final requestsBefore = repository.requests;

      await controller.selectSymbol('ETHUSDT');
      await controller.selectTimeframe('4h');

      expect(repository.requests, requestsBefore);
      expect(controller.selectedSymbol, 'ETHUSDT');
      expect(controller.selectedTimeframe, '4h');
      expect(controller.snapshot!.selectedAnalysis.symbol, 'ETHUSDT');
      expect(controller.snapshot!.selectedAnalysis.timeframe, '4h');
    },
  );

  test(
    'a user selection waits for an active scan and commits atomically',
    () async {
      final repository = _ControlledRepository();
      final controller = OwnerAlphaController(
        repository: repository,
        settingsStore: MemoryOwnerAlphaSettingsStore(),
      );
      addTearDown(controller.dispose);

      final initialization = controller.initialize();
      await Future<void>.delayed(Duration.zero);
      expect(repository.gates, hasLength(1));

      final selection = controller.selectSymbol('ETHUSDT');
      await Future<void>.delayed(Duration.zero);
      expect(repository.gates, hasLength(1));
      expect(controller.selectedSymbol, 'BTCUSDT');

      repository.gates.first.complete();
      await initialization;
      await Future<void>.delayed(Duration.zero);
      expect(repository.gates, hasLength(2));
      expect(controller.selectedSymbol, 'BTCUSDT');
      expect(controller.snapshot!.selectedSymbol, 'BTCUSDT');

      repository.gates.last.complete();
      await selection;
      expect(controller.selectedSymbol, 'ETHUSDT');
      expect(controller.snapshot!.selectedSymbol, 'ETHUSDT');
    },
  );

  test(
    'language changes retranslate cached ideas without a market request',
    () async {
      final repository = _SwitchableRepository();
      final controller = OwnerAlphaController(
        repository: repository,
        settingsStore: MemoryOwnerAlphaSettingsStore(),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      final requestsBefore = repository.requests;

      controller.setLanguage('en');

      expect(repository.requests, requestsBefore);
      expect(controller.languageCode, 'en');
      expect(
        controller.snapshot!.selectedIdea.summary,
        isNot(contains('ساختار')),
      );
      expect(
        controller.snapshot!.selectedIdea.summary,
        isNot(contains('سناریو')),
      );
      expect(controller.selectedSymbol, 'BTCUSDT');
    },
  );

  test('persists taken setups and deduplicates local notifications', () async {
    final repository = _ActionableRepository();
    final stateStore = MemoryOpportunityStateStore();
    final notifications = RecordingSetupNotificationGateway();
    final controller = OwnerAlphaController(
      repository: repository,
      settingsStore: MemoryOwnerAlphaSettingsStore(),
      opportunityStateStore: stateStore,
      notificationGateway: notifications,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    final idea = controller.snapshot!.opportunities.first;

    expect(await controller.setNotificationsEnabled(true), isTrue);
    await controller.setTaken(idea.setupId, true);
    await controller.refresh();
    final firstNotificationCount = notifications.shown.length;
    await controller.refresh();

    expect(controller.isTaken(idea.setupId), isTrue);
    expect(stateStore.value.takenSetupIds, contains(idea.setupId));
    expect(firstNotificationCount, greaterThan(0));
    expect(notifications.shown, hasLength(firstNotificationCount));
  });
}

final class _ActionableRepository implements OwnerAlphaRepository {
  final _delegate = const FakeOwnerAlphaRepository();
  final DateTime _signalTime = DateTime.now().toUtc();

  @override
  Future<OwnerAlphaSnapshot> scan({
    required List<String> symbols,
    required String selectedSymbol,
    required String selectedTimeframe,
    required double capital,
    required double riskPercent,
    required String languageCode,
  }) async {
    final base = await _delegate.scan(
      symbols: symbols,
      selectedSymbol: selectedSymbol,
      selectedTimeframe: selectedTimeframe,
      capital: capital,
      riskPercent: riskPercent,
      languageCode: languageCode,
    );
    final result = base.radar.first;
    final signalTime = _signalTime;
    final analysis = _actionableAnalysis(signalTime);
    final parentAnalysis = _actionableAnalysis(signalTime, timeframe: '4h');
    final idea = TradeIdea(
      symbol: result.quote.symbol,
      timeframe: '1h',
      direction: TradeDirection.long,
      confidencePercent: 80,
      entryLower: 100,
      entryUpper: 101,
      stopLoss: 95,
      targets: const [110, 120, 130],
      riskReward: 2,
      maximumLoss: 100,
      positionSize: 10,
      notionalValue: 1000,
      recommendedLeverage: 2,
      maximumSafeLeverage: 8,
      requiredMargin: 500,
      estimatedRoundTripCosts: 2,
      setupId: 'BTCUSDT|1h|long|fixed-closed-candle',
      candleClosedAt: signalTime,
      summary: 'actionable',
      invalidation: 'stop',
      reasons: const ['test'],
    );
    final actionable = SymbolRadarResult(
      quote: result.quote,
      analysis: analysis,
      idea: idea,
      analysesByTimeframe: {'1h': analysis, '4h': parentAnalysis},
      ideasByTimeframe: {'1h': idea},
    );
    return OwnerAlphaSnapshot(
      radar: [actionable, ...base.radar.skip(1)],
      selectedSymbol: actionable.quote.symbol,
      selectedTimeframe: '1h',
      selectedAnalysis: analysis,
      selectedIdea: idea,
      timeframeDirections: {
        '1h': analysis.direction,
        '4h': parentAnalysis.direction,
      },
      generatedAt: signalTime,
    );
  }
}

TimeframeChartAnalysis _actionableAnalysis(
  DateTime generatedAt, {
  String timeframe = '1h',
}) {
  final interval = timeframe == '4h'
      ? const Duration(hours: 4)
      : const Duration(hours: 1);
  final candles = List.generate(60, (index) {
    final open = 100 + index * 0.1;
    final last = index == 59;
    final close = open + (last ? 0.35 : 0.15);
    return ChartCandle(
      openTime: generatedAt.subtract(interval * (60 - index)),
      open: open,
      high: close + (last ? 0.1 : 0.7),
      low: open - (last ? 0.1 : 0.7),
      close: close,
      volume: last ? 1400 : 1000 + index.toDouble(),
    );
  });
  final current = candles.last.close;
  return TimeframeChartAnalysis(
    symbol: 'BTCUSDT',
    timeframe: timeframe,
    candles: candles,
    zones: [
      ChartPriceZone(
        lower: current - 4.5,
        upper: current - 3.5,
        role: ChartZoneRole.support,
        state: ChartZoneState.active,
        touchCount: 4,
        strength: 0.8,
        distancePercent: 3,
        lastTouchedAt: candles[45].openTime,
        explanation: 'support',
      ),
      ChartPriceZone(
        lower: current + 14,
        upper: current + 16,
        role: ChartZoneRole.resistance,
        state: ChartZoneState.active,
        touchCount: 3,
        strength: 0.72,
        distancePercent: 10,
        lastTouchedAt: candles[48].openTime,
        explanation: 'resistance',
      ),
    ],
    direction: ChartDirection.bullish,
    directionStrength: 0.8,
    volatilityPercent: 0.8,
    summary: 'actionable fixture',
    generatedAt: generatedAt,
    fingerprint: 'controller-actionable-fixture-$timeframe',
  );
}

final class _SwitchableRepository implements OwnerAlphaRepository {
  var requests = 0;
  var fail = false;
  final _delegate = const FakeOwnerAlphaRepository();

  @override
  Future<OwnerAlphaSnapshot> scan({
    required List<String> symbols,
    required String selectedSymbol,
    required String selectedTimeframe,
    required double capital,
    required double riskPercent,
    required String languageCode,
  }) {
    requests++;
    if (fail) {
      throw const FormatException('network unavailable');
    }
    return _delegate.scan(
      symbols: symbols,
      selectedSymbol: selectedSymbol,
      selectedTimeframe: selectedTimeframe,
      capital: capital,
      riskPercent: riskPercent,
      languageCode: languageCode,
    );
  }
}

final class _ControlledRepository implements OwnerAlphaRepository {
  final gates = <Completer<void>>[];
  final _delegate = const FakeOwnerAlphaRepository();

  @override
  Future<OwnerAlphaSnapshot> scan({
    required List<String> symbols,
    required String selectedSymbol,
    required String selectedTimeframe,
    required double capital,
    required double riskPercent,
    required String languageCode,
  }) async {
    final gate = Completer<void>();
    gates.add(gate);
    await gate.future;
    return _delegate.scan(
      symbols: symbols,
      selectedSymbol: selectedSymbol,
      selectedTimeframe: selectedTimeframe,
      capital: capital,
      riskPercent: riskPercent,
      languageCode: languageCode,
    );
  }
}
