import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Local Live uses exposure-aware PnL readiness without weakening safety',
    () {
      final source = File(
        'lib/features/auto_trade/application/local_live_trade_service.dart',
      ).readAsStringSync();

      expect(source, contains('LocalLiveCycleReadinessPolicy.evaluate'));
      expect(source, contains('emptyAccountHistoryPending'));
      expect(source, contains('unmanagedExposureBlocked'));
      expect(source, contains('placePositionStop'));
      expect(source, contains('placePartialTakeProfit'));
      expect(source, contains('closePositionReduceOnly'));
      expect(source, contains('for (var index = 0; index < 3; index++)'));
    },
  );

  test('production realtime warm-up remains bounded and indicator-safe', () {
    final source = File(
      'lib/features/owner_alpha/data/realtime_production_runtime.dart',
    ).readAsStringSync();

    expect(source, contains('closedCandleLimit: 64'));
    expect(source, isNot(contains('closedCandleLimit: 120')));
    expect(source, contains('backgroundPauseGrace'));
    expect(source, contains('degradedRetryInterval'));
  });
}
