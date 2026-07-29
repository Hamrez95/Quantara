import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/market_analysis/data/technical_indicator_engine.dart';
import 'package:quantara_app/features/market_analysis/domain/market_chart_models.dart';

void main() {
  test('indicator engine detects a persistent bullish series', () {
    final candles = <ChartCandle>[];
    var price = 100.0;
    for (var index = 0; index < 220; index++) {
      final open = price;
      final close = open + 0.45 + index / 2000;
      candles.add(
        ChartCandle(
          openTime: DateTime.utc(2026, 1, 1).add(Duration(hours: index)),
          open: open,
          high: close + 0.35,
          low: open - 0.25,
          close: close,
          volume: 1000 + index * 3,
        ),
      );
      price = close;
    }

    final result = TechnicalIndicatorEngine.analyze(candles);

    expect(result.ema20, greaterThan(result.ema50));
    expect(result.ema50, greaterThan(result.ema200));
    expect(result.atr14, greaterThan(0));
    expect(result.rsi14, greaterThan(60));
    expect(result.adx14, greaterThan(20));
    expect(result.plusDi14, greaterThan(result.minusDi14));
    expect(result.trendEfficiency20, greaterThan(0.8));
    expect(result.previousDonchianHigh20, lessThan(candles.last.close));
  });
}
