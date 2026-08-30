import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/hot_path_performance/domain/rolling_market_features.dart';
import 'package:quantara_app/features/market_analysis/domain/market_chart_models.dart';

void main() {
  test(
    'rolling features remain equivalent to the independent batch oracle',
    () {
      final random = math.Random(198);
      final candles = <ChartCandle>[];
      final rolling = RollingMarketFeatureState();
      var price = 30000.0;

      for (var index = 0; index < 500; index++) {
        final move = random.nextDouble() * 120 - 60;
        final open = price;
        final close = math.max(1, open + move).toDouble();
        final candle = ChartCandle(
          openTime: DateTime.utc(2026, 1, 1).add(Duration(minutes: index * 5)),
          open: open,
          high: math.max(open, close) + random.nextDouble() * 25,
          low: math.min(open, close) - random.nextDouble() * 25,
          close: close,
          volume: 100 + random.nextDouble() * 900,
        );
        candles.add(candle);
        final actual = rolling.append(candle);
        price = close;

        if (candles.length < 21) {
          expect(actual, isNull);
          continue;
        }
        final expected = BatchMarketFeatureReference.compute(candles);
        expect(actual, isNotNull);
        _expectNear(actual!.sma20, expected.sma20);
        _expectNear(actual.ema20, expected.ema20);
        _expectNear(actual.ema50, expected.ema50);
        _expectNear(actual.ema200, expected.ema200);
        _expectNear(actual.atr14, expected.atr14);
        _expectNear(actual.relativeVolume20, expected.relativeVolume20);
        _expectNear(actual.closeVolatility20, expected.closeVolatility20);
        _expectNear(
          actual.previousDonchianHigh20,
          expected.previousDonchianHigh20,
        );
        _expectNear(
          actual.previousDonchianLow20,
          expected.previousDonchianLow20,
        );
        expect(actual.candleCount, candles.length);
        expect(rolling.retainedCandleCount, lessThanOrEqualTo(21));
      }
    },
  );

  test('rejects invalid and non-monotonic candles without mutating state', () {
    final rolling = RollingMarketFeatureState();
    final first = _candle(DateTime.utc(2026, 1, 1), 100);
    rolling.append(first);

    expect(() => rolling.append(first), throwsStateError);
    expect(
      () => rolling.append(
        ChartCandle(
          openTime: DateTime.utc(2026, 1, 1, 0, 5),
          open: 100,
          high: 99,
          low: 98,
          close: 100,
          volume: 1,
        ),
      ),
      throwsArgumentError,
    );
    expect(rolling.candleCount, 1);
    expect(rolling.retainedCandleCount, 1);
  });
}

ChartCandle _candle(DateTime time, double close) => ChartCandle(
  openTime: time,
  open: close,
  high: close + 1,
  low: close - 1,
  close: close,
  volume: 10,
);

void _expectNear(double actual, double expected) {
  expect(actual, closeTo(expected, 1e-5));
}
