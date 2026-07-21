import 'dart:math' as math;

import '../domain/market_chart_models.dart';

abstract final class ChartStructureAnalyzer {
  static ChartStructureSnapshot analyze(List<ChartCandle> candles) {
    if (candles.length < 24 || candles.any((item) => !item.isValid)) {
      throw ArgumentError('A valid ordered candle window is required.');
    }

    final ranges = <double>[];
    for (var index = 0; index < candles.length; index++) {
      final candle = candles[index];
      if (index == 0) {
        ranges.add(candle.high - candle.low);
      } else {
        final previous = candles[index - 1].close;
        ranges.add(
          math.max(
            candle.high - candle.low,
            math.max(
              (candle.high - previous).abs(),
              (candle.low - previous).abs(),
            ),
          ),
        );
      }
    }

    final averageRanges = _rollingAverage(ranges, 14);
    final averageVolumes = _rollingAverage(
      candles.map((item) => item.volume).toList(growable: false),
      20,
    );
    final pivots = <_Pivot>[];
    for (var index = 2; index < candles.length - 2; index++) {
      final candle = candles[index];
      if (_confirmedHigh(candles, index)) {
        pivots.add(
          _createPivot(
            value: candle.high,
            isHigh: true,
            index: index,
            candle: candle,
            averageRange: averageRanges[index],
            averageVolume: averageVolumes[index],
          ),
        );
      }
      if (_confirmedLow(candles, index)) {
        pivots.add(
          _createPivot(
            value: candle.low,
            isHigh: false,
            index: index,
            candle: candle,
            averageRange: averageRanges[index],
            averageVolume: averageVolumes[index],
          ),
        );
      }
    }

    pivots.sort((left, right) {
      final byValue = left.value.compareTo(right.value);
      return byValue == 0 ? left.index.compareTo(right.index) : byValue;
    });
    final clusters = <_PivotCluster>[];
    for (final pivot in pivots) {
      final tolerance = math.max(
        pivot.value * 0.001,
        pivot.averageRange * 0.58,
      );
      if (clusters.isEmpty ||
          pivot.value >
              clusters.last.center +
                  math.max(clusters.last.maxTolerance, tolerance)) {
        clusters.add(_PivotCluster(pivot, tolerance));
      } else {
        clusters.last.add(pivot, tolerance);
      }
    }

    final current = candles.last.close;
    final currentRange = averageRanges.last;
    final zones = <ChartPriceZone>[];
    for (final cluster in clusters) {
      if (cluster.items.length < 2) {
        continue;
      }
      final halfWidth = math.max(
        cluster.averageTolerance / 2,
        cluster.center * 0.0004,
      );
      final lower = cluster.center - halfWidth;
      final upper = cluster.center + halfWidth;
      final originalRole = cluster.highCount > cluster.lowCount
          ? ChartZoneRole.resistance
          : ChartZoneRole.support;
      var role = current < lower
          ? ChartZoneRole.resistance
          : current > upper
          ? ChartZoneRole.support
          : ChartZoneRole.pivot;
      var state = ChartZoneState.active;
      if (originalRole == ChartZoneRole.resistance &&
          current > upper + currentRange * 0.75) {
        role = ChartZoneRole.support;
        state = ChartZoneState.flipped;
      } else if (originalRole == ChartZoneRole.support &&
          current < lower - currentRange * 0.75) {
        role = ChartZoneRole.resistance;
        state = ChartZoneState.flipped;
      }

      final age = candles.length - 1 - cluster.lastIndex;
      final touchScore = math.min(1, cluster.items.length / 12);
      final recencyScore = 1 / (1 + age / 48);
      final rejectionScore = math.min(1, cluster.averageRejection / 1.5);
      final volumeScore = math.min(1, cluster.averageRelativeVolume / 1.75);
      var strength =
          touchScore * 0.45 +
          recencyScore * 0.25 +
          rejectionScore * 0.2 +
          volumeScore * 0.1;
      if (state == ChartZoneState.flipped) {
        strength *= 0.9;
      }
      zones.add(
        ChartPriceZone(
          lower: lower,
          upper: upper,
          role: role,
          state: state,
          touchCount: cluster.items.length,
          strength: strength.clamp(0, 1).toDouble(),
          distancePercent: (cluster.center - current).abs() / current * 100,
          lastTouchedAt: candles[cluster.lastIndex].openTime,
          explanation: _explanation(role, state, cluster.items.length),
        ),
      );
    }
    zones.sort((left, right) {
      final byStrength = right.strength.compareTo(left.strength);
      return byStrength == 0
          ? left.distancePercent.compareTo(right.distancePercent)
          : byStrength;
    });

    final fast = _averageClose(candles, 9);
    final slow = _averageClose(candles, 30);
    final normalized = currentRange == 0 ? 0 : (fast - slow) / currentRange;
    final direction = normalized >= 0.5
        ? ChartDirection.bullish
        : normalized <= -0.5
        ? ChartDirection.bearish
        : ChartDirection.sideways;
    return ChartStructureSnapshot(
      zones: zones.take(8).toList(growable: false),
      direction: direction,
      directionStrength: math.min(1, normalized.abs() / 2),
      volatilityPercent: currentRange / current * 100,
    );
  }

  static List<double> _rollingAverage(List<double> values, int period) {
    final result = List<double>.filled(values.length, 0);
    var sum = 0.0;
    for (var index = 0; index < values.length; index++) {
      sum += values[index];
      if (index >= period) {
        sum -= values[index - period];
      }
      result[index] = sum / math.min(index + 1, period);
    }
    return result;
  }

  static bool _confirmedHigh(List<ChartCandle> candles, int index) {
    final value = candles[index].high;
    return value > candles[index - 1].high &&
        value > candles[index - 2].high &&
        value >= candles[index + 1].high &&
        value >= candles[index + 2].high;
  }

  static bool _confirmedLow(List<ChartCandle> candles, int index) {
    final value = candles[index].low;
    return value < candles[index - 1].low &&
        value < candles[index - 2].low &&
        value <= candles[index + 1].low &&
        value <= candles[index + 2].low;
  }

  static _Pivot _createPivot({
    required double value,
    required bool isHigh,
    required int index,
    required ChartCandle candle,
    required double averageRange,
    required double averageVolume,
  }) {
    final wick = isHigh
        ? candle.high - math.max(candle.open, candle.close)
        : math.min(candle.open, candle.close) - candle.low;
    return _Pivot(
      value: value,
      isHigh: isHigh,
      index: index,
      averageRange: averageRange,
      rejection: averageRange == 0
          ? 0
          : (wick / averageRange).clamp(0, 3).toDouble(),
      relativeVolume: averageVolume == 0
          ? 0
          : (candle.volume / averageVolume).clamp(0, 5).toDouble(),
    );
  }

  static double _averageClose(List<ChartCandle> candles, int count) {
    var total = 0.0;
    for (var index = candles.length - count; index < candles.length; index++) {
      total += candles[index].close;
    }
    return total / count;
  }

  static String _explanation(
    ChartZoneRole role,
    ChartZoneState state,
    int touches,
  ) {
    final roleText = switch (role) {
      ChartZoneRole.support => 'حمایتی',
      ChartZoneRole.resistance => 'مقاومتی',
      ChartZoneRole.pivot => 'تصمیم',
    };
    final stateText = state == ChartZoneState.flipped
        ? 'تغییر نقش داده'
        : 'فعال است';
    return 'ناحیه $roleText با $touches واکنش تأییدشده؛ $stateText.';
  }
}

final class _Pivot {
  const _Pivot({
    required this.value,
    required this.isHigh,
    required this.index,
    required this.averageRange,
    required this.rejection,
    required this.relativeVolume,
  });

  final double value;
  final bool isHigh;
  final int index;
  final double averageRange;
  final double rejection;
  final double relativeVolume;
}

final class _PivotCluster {
  _PivotCluster(_Pivot first, double tolerance)
    : _valueSum = first.value,
      _toleranceSum = tolerance,
      _rejectionSum = first.rejection,
      _volumeSum = first.relativeVolume,
      maxTolerance = tolerance,
      lastIndex = first.index,
      highCount = first.isHigh ? 1 : 0,
      lowCount = first.isHigh ? 0 : 1 {
    items.add(first);
  }

  final List<_Pivot> items = [];
  double _valueSum;
  double _toleranceSum;
  double _rejectionSum;
  double _volumeSum;
  double maxTolerance;
  int lastIndex;
  int highCount;
  int lowCount;

  double get center => _valueSum / items.length;
  double get averageTolerance => _toleranceSum / items.length;
  double get averageRejection => _rejectionSum / items.length;
  double get averageRelativeVolume => _volumeSum / items.length;

  void add(_Pivot item, double tolerance) {
    items.add(item);
    _valueSum += item.value;
    _toleranceSum += tolerance;
    _rejectionSum += item.rejection;
    _volumeSum += item.relativeVolume;
    maxTolerance = math.max(maxTolerance, tolerance);
    lastIndex = math.max(lastIndex, item.index);
    highCount += item.isHigh ? 1 : 0;
    lowCount += item.isHigh ? 0 : 1;
  }
}
