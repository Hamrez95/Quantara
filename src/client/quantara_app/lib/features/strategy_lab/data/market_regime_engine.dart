import 'dart:math' as math;

import '../../market_analysis/domain/market_chart_models.dart';
import '../domain/strategy_lab_models.dart';

abstract final class MarketRegimeEngine {
  static MarketRegime classify(List<ChartCandle> candles) {
    if (candles.length < 30) {
      return MarketRegime.transition;
    }
    final window = candles.sublist(math.max(0, candles.length - 40));
    final fast = _averageClose(window, 9);
    final slow = _averageClose(window, 30);
    final current = window.last.close;
    final averageRange =
        window.fold<double>(0, (sum, item) => sum + item.high - item.low) /
        window.length;
    if (averageRange <= 0) {
      return MarketRegime.transition;
    }
    final normalizedTrend = (fast - slow) / averageRange;
    final rangeWidth =
        (window.map((item) => item.high).reduce(math.max) -
            window.map((item) => item.low).reduce(math.min)) /
        current;
    final recent = window.sublist(window.length - 12);
    final earlier = window.sublist(window.length - 24, window.length - 12);
    final recentVolume = _averageVolume(recent);
    final earlierVolume = _averageVolume(earlier);
    final volumeExpanding =
        earlierVolume > 0 && recentVolume / earlierVolume >= 1.12;

    if (normalizedTrend >= 0.62) {
      return MarketRegime.markup;
    }
    if (normalizedTrend <= -0.62) {
      return MarketRegime.markdown;
    }
    if (rangeWidth <= 0.055 && normalizedTrend.abs() <= 0.32) {
      if (!volumeExpanding) {
        return MarketRegime.range;
      }
      final location =
          (current - window.map((item) => item.low).reduce(math.min)) /
          math.max(
            1e-12,
            window.map((item) => item.high).reduce(math.max) -
                window.map((item) => item.low).reduce(math.min),
          );
      return location >= 0.55
          ? MarketRegime.accumulation
          : MarketRegime.distribution;
    }
    return MarketRegime.transition;
  }

  static double _averageClose(List<ChartCandle> candles, int count) {
    final start = math.max(0, candles.length - count);
    final slice = candles.sublist(start);
    return slice.fold<double>(0, (sum, item) => sum + item.close) /
        slice.length;
  }

  static double _averageVolume(List<ChartCandle> candles) =>
      candles.fold<double>(0, (sum, item) => sum + item.volume) /
      candles.length;
}
