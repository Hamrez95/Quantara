import 'dart:math' as math;

import '../domain/market_chart_models.dart';

final class TechnicalIndicatorSnapshot {
  const TechnicalIndicatorSnapshot({
    required this.ema20,
    required this.ema50,
    required this.ema200,
    required this.ema20SlopeAtr,
    required this.ema50SlopeAtr,
    required this.atr14,
    required this.atrPercent,
    required this.atrExpansionRatio,
    required this.rsi14,
    required this.adx14,
    required this.plusDi14,
    required this.minusDi14,
    required this.relativeVolume20,
    required this.volumeZScore20,
    required this.previousDonchianHigh20,
    required this.previousDonchianLow20,
    required this.bollingerMiddle20,
    required this.bollingerUpper20,
    required this.bollingerLower20,
    required this.bollingerBandwidthPercent,
    required this.trendEfficiency20,
    required this.recentSwingHigh,
    required this.recentSwingLow,
  });

  final double ema20;
  final double ema50;
  final double ema200;
  final double ema20SlopeAtr;
  final double ema50SlopeAtr;
  final double atr14;
  final double atrPercent;
  final double atrExpansionRatio;
  final double rsi14;
  final double adx14;
  final double plusDi14;
  final double minusDi14;
  final double relativeVolume20;
  final double volumeZScore20;
  final double previousDonchianHigh20;
  final double previousDonchianLow20;
  final double bollingerMiddle20;
  final double bollingerUpper20;
  final double bollingerLower20;
  final double bollingerBandwidthPercent;
  final double trendEfficiency20;
  final double recentSwingHigh;
  final double recentSwingLow;

  bool get bullishEmaStack => ema20 > ema50 && ema50 > ema200;
  bool get bearishEmaStack => ema20 < ema50 && ema50 < ema200;
}

abstract final class TechnicalIndicatorEngine {
  static TechnicalIndicatorSnapshot analyze(List<ChartCandle> candles) {
    if (candles.length < 60 || candles.any((candle) => !candle.isValid)) {
      throw ArgumentError('At least 60 valid candles are required.');
    }
    for (var index = 1; index < candles.length; index++) {
      if (!candles[index].openTime.isAfter(candles[index - 1].openTime)) {
        throw ArgumentError('Candles must be strictly ordered.');
      }
    }

    final closes = candles.map((candle) => candle.close).toList(growable: false);
    final volumes = candles.map((candle) => candle.volume).toList(growable: false);
    final ema20Series = _emaSeries(closes, 20);
    final ema50Series = _emaSeries(closes, 50);
    final ema200Series = _emaSeries(closes, 200);
    final trueRanges = _trueRanges(candles);
    final atrSeries = _wildersSeries(trueRanges, 14);
    final latestAtr = math.max(atrSeries.last, closes.last * 0.000001);
    final slopeLookback = math.min(5, candles.length - 1);

    final previousVolumes = volumes.sublist(volumes.length - 21, volumes.length - 1);
    final averageVolume = _average(previousVolumes);
    final volumeDeviation = _standardDeviation(previousVolumes, averageVolume);
    final relativeVolume = averageVolume <= 0 ? 0 : volumes.last / averageVolume;
    final volumeZScore = volumeDeviation <= 0
        ? 0
        : (volumes.last - averageVolume) / volumeDeviation;

    final donchianWindow = candles.sublist(candles.length - 21, candles.length - 1);
    final previousDonchianHigh = donchianWindow
        .map((candle) => candle.high)
        .reduce(math.max);
    final previousDonchianLow = donchianWindow
        .map((candle) => candle.low)
        .reduce(math.min);

    final bollingerCloses = closes.sublist(closes.length - 20);
    final bollingerMiddle = _average(bollingerCloses);
    final bollingerDeviation = _standardDeviation(
      bollingerCloses,
      bollingerMiddle,
    );
    final bollingerUpper = bollingerMiddle + bollingerDeviation * 2;
    final bollingerLower = bollingerMiddle - bollingerDeviation * 2;

    final priorAtrWindow = atrSeries
        .sublist(math.max(0, atrSeries.length - 21), atrSeries.length - 1)
        .where((value) => value > 0)
        .toList(growable: false);
    final atrBaseline = priorAtrWindow.isEmpty
        ? latestAtr
        : _average(priorAtrWindow);

    final efficiencyStart = closes.length - 20;
    final netMove = (closes.last - closes[efficiencyStart]).abs();
    var pathLength = 0.0;
    for (var index = efficiencyStart + 1; index < closes.length; index++) {
      pathLength += (closes[index] - closes[index - 1]).abs();
    }

    final swingWindow = candles.sublist(candles.length - 10);
    final directional = _directionalMovement(candles, trueRanges);

    return TechnicalIndicatorSnapshot(
      ema20: ema20Series.last,
      ema50: ema50Series.last,
      ema200: ema200Series.last,
      ema20SlopeAtr:
          (ema20Series.last - ema20Series[ema20Series.length - 1 - slopeLookback]) /
          latestAtr,
      ema50SlopeAtr:
          (ema50Series.last - ema50Series[ema50Series.length - 1 - slopeLookback]) /
          latestAtr,
      atr14: latestAtr,
      atrPercent: latestAtr / closes.last * 100,
      atrExpansionRatio: atrBaseline <= 0 ? 1 : latestAtr / atrBaseline,
      rsi14: _rsi(closes, 14),
      adx14: directional.$1,
      plusDi14: directional.$2,
      minusDi14: directional.$3,
      relativeVolume20: relativeVolume,
      volumeZScore20: volumeZScore,
      previousDonchianHigh20: previousDonchianHigh,
      previousDonchianLow20: previousDonchianLow,
      bollingerMiddle20: bollingerMiddle,
      bollingerUpper20: bollingerUpper,
      bollingerLower20: bollingerLower,
      bollingerBandwidthPercent: bollingerMiddle <= 0
          ? 0
          : (bollingerUpper - bollingerLower) / bollingerMiddle * 100,
      trendEfficiency20: pathLength <= 0 ? 0 : netMove / pathLength,
      recentSwingHigh: swingWindow.map((candle) => candle.high).reduce(math.max),
      recentSwingLow: swingWindow.map((candle) => candle.low).reduce(math.min),
    );
  }

  static List<double> _emaSeries(List<double> values, int period) {
    final multiplier = 2 / (period + 1);
    final result = List<double>.filled(values.length, 0);
    result[0] = values.first;
    for (var index = 1; index < values.length; index++) {
      result[index] =
          values[index] * multiplier + result[index - 1] * (1 - multiplier);
    }
    return result;
  }

  static List<double> _trueRanges(List<ChartCandle> candles) {
    final result = List<double>.filled(candles.length, 0);
    result[0] = candles.first.high - candles.first.low;
    for (var index = 1; index < candles.length; index++) {
      final candle = candles[index];
      final previousClose = candles[index - 1].close;
      result[index] = math.max(
        candle.high - candle.low,
        math.max(
          (candle.high - previousClose).abs(),
          (candle.low - previousClose).abs(),
        ),
      );
    }
    return result;
  }

  static List<double> _wildersSeries(List<double> values, int period) {
    final result = List<double>.filled(values.length, 0);
    var sum = 0.0;
    for (var index = 0; index < values.length; index++) {
      if (index < period) {
        sum += values[index];
        result[index] = sum / (index + 1);
      } else {
        result[index] =
            (result[index - 1] * (period - 1) + values[index]) / period;
      }
    }
    return result;
  }

  static double _rsi(List<double> closes, int period) {
    final gains = List<double>.filled(closes.length, 0);
    final losses = List<double>.filled(closes.length, 0);
    for (var index = 1; index < closes.length; index++) {
      final change = closes[index] - closes[index - 1];
      if (change >= 0) {
        gains[index] = change;
      } else {
        losses[index] = -change;
      }
    }
    final averageGains = _wildersSeries(gains, period);
    final averageLosses = _wildersSeries(losses, period);
    if (averageLosses.last <= 0) {
      return averageGains.last <= 0 ? 50 : 100;
    }
    final relativeStrength = averageGains.last / averageLosses.last;
    return 100 - 100 / (1 + relativeStrength);
  }

  static (double, double, double) _directionalMovement(
    List<ChartCandle> candles,
    List<double> trueRanges,
  ) {
    const period = 14;
    final plusDm = List<double>.filled(candles.length, 0);
    final minusDm = List<double>.filled(candles.length, 0);
    for (var index = 1; index < candles.length; index++) {
      final upMove = candles[index].high - candles[index - 1].high;
      final downMove = candles[index - 1].low - candles[index].low;
      plusDm[index] = upMove > downMove && upMove > 0 ? upMove : 0;
      minusDm[index] = downMove > upMove && downMove > 0 ? downMove : 0;
    }
    final smoothedTr = _wildersSeries(trueRanges, period);
    final smoothedPlus = _wildersSeries(plusDm, period);
    final smoothedMinus = _wildersSeries(minusDm, period);
    final plusDi = List<double>.filled(candles.length, 0);
    final minusDi = List<double>.filled(candles.length, 0);
    final dx = List<double>.filled(candles.length, 0);
    for (var index = 0; index < candles.length; index++) {
      final tr = smoothedTr[index];
      if (tr <= 0) continue;
      plusDi[index] = 100 * smoothedPlus[index] / tr;
      minusDi[index] = 100 * smoothedMinus[index] / tr;
      final total = plusDi[index] + minusDi[index];
      if (total > 0) {
        dx[index] = 100 * (plusDi[index] - minusDi[index]).abs() / total;
      }
    }
    final adx = _wildersSeries(dx, period).last;
    return (adx, plusDi.last, minusDi.last);
  }

  static double _average(List<double> values) {
    if (values.isEmpty) return 0;
    return values.reduce((left, right) => left + right) / values.length;
  }

  static double _standardDeviation(List<double> values, double average) {
    if (values.length < 2) return 0;
    var squared = 0.0;
    for (final value in values) {
      squared += math.pow(value - average, 2).toDouble();
    }
    return math.sqrt(squared / values.length);
  }
}
