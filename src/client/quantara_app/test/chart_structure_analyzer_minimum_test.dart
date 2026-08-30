import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/market_analysis/data/chart_structure_analyzer.dart';
import 'package:quantara_app/features/market_analysis/domain/market_chart_models.dart';

void main() {
  test('structure analysis fails closed below its 30-candle lookback', () {
    expect(
      () => ChartStructureAnalyzer.analyze(_candles(24)),
      throwsArgumentError,
    );
  });

  test('structure analysis accepts a valid 30-candle window', () {
    final snapshot = ChartStructureAnalyzer.analyze(_candles(30));

    expect(snapshot.volatilityPercent, greaterThanOrEqualTo(0));
    expect(snapshot.directionStrength, inInclusiveRange(0, 1));
  });
}

List<ChartCandle> _candles(int count) => List.generate(count, (index) {
  final open = 100 + index * 0.3;
  final close = open + 0.2;
  return ChartCandle(
    openTime: DateTime.utc(2026, 1, 1).add(Duration(hours: index)),
    open: open,
    high: close + 0.4,
    low: open - 0.4,
    close: close,
    volume: 1000 + index.toDouble(),
  );
});
