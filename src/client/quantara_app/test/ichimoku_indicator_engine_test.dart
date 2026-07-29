import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/market_analysis/data/ichimoku_indicator_engine.dart';
import 'package:quantara_app/features/market_analysis/domain/market_chart_models.dart';

void main() {
  test('Ichimoku uses shifted source windows without future leakage', () {
    final candles = <ChartCandle>[];
    var price = 100.0;
    for (var index = 0; index < 140; index++) {
      final open = price;
      final close = open + 0.35;
      candles.add(
        ChartCandle(
          openTime: DateTime.utc(2026, 1, 1).add(Duration(hours: index)),
          open: open,
          high: close + 0.25,
          low: open - 0.20,
          close: close,
          volume: 1000 + index.toDouble(),
        ),
      );
      price = close;
    }

    final snapshot = IchimokuIndicatorEngine.analyze(candles);

    expect(snapshot.tenkan9, greaterThan(snapshot.kijun26));
    expect(snapshot.senkouA, greaterThan(snapshot.senkouB));
    expect(candles.last.close, greaterThan(snapshot.cloudTop));
    expect(candles.last.close, greaterThan(snapshot.chikouReferenceHigh));
  });
}
