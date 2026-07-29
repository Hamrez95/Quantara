import 'dart:math' as math;

import '../domain/market_chart_models.dart';

final class IchimokuSnapshot {
  const IchimokuSnapshot({
    required this.tenkan9,
    required this.kijun26,
    required this.senkouA,
    required this.senkouB,
    required this.chikouReferenceHigh,
    required this.chikouReferenceLow,
  });

  final double tenkan9;
  final double kijun26;
  final double senkouA;
  final double senkouB;
  final double chikouReferenceHigh;
  final double chikouReferenceLow;

  double get cloudTop => math.max(senkouA, senkouB);
  double get cloudBottom => math.min(senkouA, senkouB);
  bool get bullishCloud => senkouA > senkouB;
  bool get bearishCloud => senkouA < senkouB;
}

abstract final class IchimokuIndicatorEngine {
  static const displacement = 26;

  static IchimokuSnapshot analyze(List<ChartCandle> candles) {
    if (candles.length < 80 || candles.any((candle) => !candle.isValid)) {
      throw ArgumentError('At least 80 valid candles are required.');
    }
    for (var index = 1; index < candles.length; index++) {
      if (!candles[index].openTime.isAfter(candles[index - 1].openTime)) {
        throw ArgumentError('Candles must be strictly ordered.');
      }
    }

    final currentEnd = candles.length;
    final shiftedEnd = currentEnd - displacement;
    final tenkan = _midpoint(candles, endExclusive: currentEnd, period: 9);
    final kijun = _midpoint(candles, endExclusive: currentEnd, period: 26);

    // The cloud visible at the current candle was calculated 26 candles ago.
    // Using the shifted source window prevents future-cloud lookahead.
    final shiftedTenkan = _midpoint(
      candles,
      endExclusive: shiftedEnd,
      period: 9,
    );
    final shiftedKijun = _midpoint(
      candles,
      endExclusive: shiftedEnd,
      period: 26,
    );
    final senkouA = (shiftedTenkan + shiftedKijun) / 2;
    final senkouB = _midpoint(candles, endExclusive: shiftedEnd, period: 52);

    final referenceStart = math.max(0, shiftedEnd - 5);
    final reference = candles.sublist(referenceStart, shiftedEnd);
    final chikouReferenceHigh = reference
        .map((candle) => candle.high)
        .reduce(math.max);
    final chikouReferenceLow = reference
        .map((candle) => candle.low)
        .reduce(math.min);

    return IchimokuSnapshot(
      tenkan9: tenkan,
      kijun26: kijun,
      senkouA: senkouA,
      senkouB: senkouB,
      chikouReferenceHigh: chikouReferenceHigh,
      chikouReferenceLow: chikouReferenceLow,
    );
  }

  static double _midpoint(
    List<ChartCandle> candles, {
    required int endExclusive,
    required int period,
  }) {
    final start = endExclusive - period;
    if (start < 0 || endExclusive > candles.length || start >= endExclusive) {
      throw ArgumentError('The Ichimoku window is incomplete.');
    }
    final window = candles.sublist(start, endExclusive);
    final high = window.map((candle) => candle.high).reduce(math.max);
    final low = window.map((candle) => candle.low).reduce(math.min);
    return (high + low) / 2;
  }
}
