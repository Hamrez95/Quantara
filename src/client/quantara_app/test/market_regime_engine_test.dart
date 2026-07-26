import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/market_analysis/domain/market_chart_models.dart';
import 'package:quantara_app/features/strategy_lab/data/market_regime_engine.dart';
import 'package:quantara_app/features/strategy_lab/domain/strategy_lab_models.dart';

void main() {
  test('classifies a persistent rising market as markup', () {
    final candles = _candles(step: 1.5);

    expect(MarketRegimeEngine.classify(candles), MarketRegime.markup);
  });

  test('classifies a persistent falling market as markdown', () {
    final candles = _candles(step: -0.9, start: 200);

    expect(MarketRegimeEngine.classify(candles), MarketRegime.markdown);
  });

  test('fails closed to transition when history is insufficient', () {
    final candles = _candles(step: 1, count: 20);

    expect(MarketRegimeEngine.classify(candles), MarketRegime.transition);
  });
}

List<ChartCandle> _candles({
  required double step,
  double start = 100,
  int count = 60,
}) {
  return List.generate(count, (index) {
    final open = start + step * index;
    final close = open + step * 0.7;
    return ChartCandle(
      openTime: DateTime.utc(2026, 7, 1).add(Duration(hours: index)),
      open: open,
      high: open > close ? open + 0.8 : close + 0.8,
      low: open < close ? open - 0.8 : close - 0.8,
      close: close,
      volume: 1000,
    );
  });
}
