import 'dart:math' as math;

import '../domain/market_chart_models.dart';

abstract final class DemoCandleSeries {
  static List<ChartCandle> build({
    required String key,
    required double lastValue,
    required double changePercent,
    required Duration interval,
    int count = 90,
  }) {
    if (key.isEmpty || lastValue <= 0 || count < 20) {
      throw ArgumentError('Invalid demo series request.');
    }

    final random = _RepeatableRandom(_seed(key));
    final intervalMinutes = interval.inMinutes.clamp(1, 1440);
    final movementScale = 0.0018 * math.sqrt(intervalMinutes / 15);
    final drift = changePercent / 100 / count;
    final end = DateTime.utc(2026, 7, 20, 23);
    final start = end.subtract(interval * (count - 1));
    final result = <ChartCandle>[];
    var previous = lastValue / (1 + changePercent / 100);

    for (var index = 0; index < count; index++) {
      final cycle = math.sin(index * math.pi / 5.5) * movementScale;
      final noise = (random.nextUnit() - 0.5) * movementScale;
      final open = previous;
      final close = math.max(0.00000001, open * (1 + drift + cycle + noise));
      final upperBody = math.max(open, close);
      final lowerBody = math.min(open, close);
      final wick = movementScale * (0.4 + random.nextUnit());
      result.add(
        ChartCandle(
          openTime: start.add(interval * index),
          open: open,
          high: upperBody * (1 + wick),
          low: math.max(0.00000001, lowerBody * (1 - wick)),
          close: close,
          volume: 700 + random.nextUnit() * 1100,
        ),
      );
      previous = close;
    }

    final scale = lastValue / result.last.close;
    return result
        .map(
          (item) => ChartCandle(
            openTime: item.openTime,
            open: item.open * scale,
            high: item.high * scale,
            low: item.low * scale,
            close: item.close * scale,
            volume: item.volume,
          ),
        )
        .toList(growable: false);
  }

  static int _seed(String value) {
    var hash = 2166136261;
    for (final unit in value.codeUnits) {
      hash = ((hash ^ unit) * 16777619) & 0xFFFFFFFF;
    }
    return hash;
  }
}

final class _RepeatableRandom {
  _RepeatableRandom(this._state);

  int _state;

  double nextUnit() {
    _state = (1664525 * _state + 1013904223) & 0xFFFFFFFF;
    return _state / 0xFFFFFFFF;
  }
}

