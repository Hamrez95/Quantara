import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
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
    final analysis = result.analysis;
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
      requiredMargin: 500,
      estimatedRoundTripCosts: 2,
      setupId: 'BTCUSDT|1h|long|fixed-closed-candle',
      candleClosedAt: DateTime.utc(2026, 7, 26, 9),
      summary: 'actionable',
      invalidation: 'stop',
      reasons: const ['test'],
    );
    final actionable = SymbolRadarResult(
      quote: result.quote,
      analysis: analysis,
      idea: idea,
      analysesByTimeframe: {'1h': analysis},
      ideasByTimeframe: {'1h': idea},
    );
    return OwnerAlphaSnapshot(
      radar: [actionable, ...base.radar.skip(1)],
      selectedSymbol: actionable.quote.symbol,
      selectedTimeframe: '1h',
      selectedAnalysis: analysis,
      selectedIdea: idea,
      timeframeDirections: {'1h': analysis.direction},
      generatedAt: base.generatedAt,
    );
  }
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
