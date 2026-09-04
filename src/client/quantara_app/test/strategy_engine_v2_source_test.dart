import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('trade idea factory routes every mode through versioned registry', () {
    final factory = File(
      'lib/features/owner_alpha/data/trade_idea_factory.dart',
    ).readAsStringSync();
    final registry = File(
      'lib/features/owner_alpha/data/strategy_registry.dart',
    ).readAsStringSync();
    final engine = File(
      'lib/features/owner_alpha/data/professional_strategy_engine.dart',
    ).readAsStringSync();

    expect(factory, contains('StrategyRegistry.shared'));
    expect(factory, contains('resolveForNewRun'));
    expect(factory, contains('resolution.module.evaluate'));
    expect(factory, isNot(contains('ProfessionalStrategyEngine.create')));
    expect(registry, contains('ProfessionalStrategyEngine.create'));
    expect(engine, contains('ProfessionalSetupKind.trendPullback'));
    expect(engine, contains('ProfessionalSetupKind.breakoutRetest'));
    expect(engine, contains('ProfessionalSetupKind.arshiaCandle'));
    expect(engine, contains('ProfessionalSetupKind.rangeReversal'));
    expect(engine, contains('relativeVolume20'));
    expect(engine, contains('_closedCandleGate'));
    expect(engine, contains('_deterministicSetupId'));
    expect(factory, isNot(contains('StrategyEngineV2.tryCreate')));
  });
}
