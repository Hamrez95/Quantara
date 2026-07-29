import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('trade idea factory routes strategy modes through engine v2', () {
    final factory = File(
      'lib/features/owner_alpha/data/trade_idea_factory.dart',
    ).readAsStringSync();
    final engine = File(
      'lib/features/owner_alpha/data/strategy_engine_v2.dart',
    ).readAsStringSync();

    expect(factory, contains('StrategyEngineV2.tryCreate'));
    expect(engine, contains('2.0-trend-pullback'));
    expect(engine, contains('2.0-donchian-breakout'));
    expect(engine, contains('previousDonchianHigh20'));
    expect(engine, contains('relativeVolume20'));
  });
}
