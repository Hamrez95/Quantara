import 'dart:collection';

enum ChartZoneRole { support, resistance, pivot }

enum ChartZoneState { active, flipped }

enum ChartDirection { bullish, bearish, sideways }

final class ChartCandle {
  const ChartCandle({
    required this.openTime,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
  });

  final DateTime openTime;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;

  bool get isBullish => close >= open;

  bool get isValid =>
      openTime.isUtc &&
      open > 0 &&
      high >= open &&
      high >= close &&
      low <= open &&
      low <= close &&
      low > 0 &&
      volume >= 0;
}

final class ChartPriceZone {
  const ChartPriceZone({
    required this.lower,
    required this.upper,
    required this.role,
    required this.state,
    required this.touchCount,
    required this.strength,
    required this.distancePercent,
    required this.lastTouchedAt,
    required this.explanation,
  });

  final double lower;
  final double upper;
  final ChartZoneRole role;
  final ChartZoneState state;
  final int touchCount;
  final double strength;
  final double distancePercent;
  final DateTime lastTouchedAt;
  final String explanation;

  double get center => (lower + upper) / 2;
}

final class ChartStructureSnapshot {
  ChartStructureSnapshot({
    required Iterable<ChartPriceZone> zones,
    required this.direction,
    required this.directionStrength,
    required this.volatilityPercent,
  }) : zones = UnmodifiableListView(zones.toList(growable: false));

  final UnmodifiableListView<ChartPriceZone> zones;
  final ChartDirection direction;
  final double directionStrength;
  final double volatilityPercent;
}

final class TimeframeChartAnalysis {
  TimeframeChartAnalysis({
    required this.symbol,
    required this.timeframe,
    required Iterable<ChartCandle> candles,
    required Iterable<ChartPriceZone> zones,
    required this.direction,
    required this.directionStrength,
    required this.volatilityPercent,
    required this.summary,
    required this.generatedAt,
    required this.fingerprint,
  }) : candles = UnmodifiableListView(candles.toList(growable: false)),
       zones = UnmodifiableListView(zones.toList(growable: false)) {
    if (symbol.trim().isEmpty || timeframe.trim().isEmpty) {
      throw ArgumentError('Symbol and timeframe are required.');
    }
    if (this.candles.length < 20 ||
        this.candles.any((candle) => !candle.isValid)) {
      throw ArgumentError('At least 20 valid UTC candles are required.');
    }
    for (var index = 1; index < this.candles.length; index++) {
      if (!this.candles[index].openTime.isAfter(
        this.candles[index - 1].openTime,
      )) {
        throw ArgumentError('Candles must be strictly ordered.');
      }
    }
    if (this.zones.any(
      (zone) =>
          zone.lower <= 0 ||
          zone.upper < zone.lower ||
          zone.strength < 0 ||
          zone.strength > 1 ||
          zone.touchCount < 1,
    )) {
      throw ArgumentError('Price zones are invalid.');
    }
    if (!generatedAt.isUtc || fingerprint.trim().isEmpty) {
      throw ArgumentError('UTC generation time and fingerprint are required.');
    }
  }

  final String symbol;
  final String timeframe;
  final UnmodifiableListView<ChartCandle> candles;
  final UnmodifiableListView<ChartPriceZone> zones;
  final ChartDirection direction;
  final double directionStrength;
  final double volatilityPercent;
  final String summary;
  final DateTime generatedAt;
  final String fingerprint;

  ChartCandle get latestCandle => candles.last;

  List<ChartPriceZone> get strongestZones {
    final copy = zones.toList(growable: false)
      ..sort((left, right) {
        final strength = right.strength.compareTo(left.strength);
        if (strength != 0) {
          return strength;
        }
        return left.distancePercent.compareTo(right.distancePercent);
      });
    return copy.take(4).toList(growable: false);
  }
}

