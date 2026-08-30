import 'dart:collection';
import 'dart:math' as math;

import '../../market_analysis/domain/market_chart_models.dart';

final class RollingMarketFeatureSnapshot {
  const RollingMarketFeatureSnapshot({
    required this.version,
    required this.candleCount,
    required this.sma20,
    required this.ema20,
    required this.ema50,
    required this.ema200,
    required this.atr14,
    required this.relativeVolume20,
    required this.closeVolatility20,
    required this.previousDonchianHigh20,
    required this.previousDonchianLow20,
  });

  final String version;
  final int candleCount;
  final double sma20;
  final double ema20;
  final double ema50;
  final double ema200;
  final double atr14;
  final double relativeVolume20;
  final double closeVolatility20;
  final double previousDonchianHigh20;
  final double previousDonchianLow20;
}

/// Incremental O(1) feature state with bounded 21-candle window memory.
///
/// EMA and Wilder ATR retain their recursive state instead of rescanning old
/// candles. Windowed features keep only the exact values needed by the active
/// 20-period playbook inputs.
final class RollingMarketFeatureState {
  static const version = 'rolling-market-features/1.0';

  final Queue<ChartCandle> _window = Queue<ChartCandle>();
  var _count = 0;
  DateTime? _lastOpenTimeUtc;
  double? _lastClose;
  var _ema20 = 0.0;
  var _ema50 = 0.0;
  var _ema200 = 0.0;
  var _atr14 = 0.0;
  var _closeSum20 = 0.0;
  var _closeSquareSum20 = 0.0;
  var _volumeSum21 = 0.0;

  int get candleCount => _count;
  int get retainedCandleCount => _window.length;

  RollingMarketFeatureSnapshot? append(ChartCandle candle) {
    if (!candle.isValid) {
      throw ArgumentError.value(candle, 'candle', 'Valid OHLCV is required.');
    }
    final lastOpenTimeUtc = _lastOpenTimeUtc;
    if (lastOpenTimeUtc != null && !candle.openTime.isAfter(lastOpenTimeUtc)) {
      throw StateError('Rolling candles must be strictly ordered.');
    }

    final previousClose = _lastClose;
    final trueRange = previousClose == null
        ? candle.high - candle.low
        : math.max(
            candle.high - candle.low,
            math.max(
              (candle.high - previousClose).abs(),
              (candle.low - previousClose).abs(),
            ),
          );
    if (_count == 0) {
      _ema20 = candle.close;
      _ema50 = candle.close;
      _ema200 = candle.close;
      _atr14 = trueRange;
    } else {
      _ema20 = _ema(_ema20, candle.close, 20);
      _ema50 = _ema(_ema50, candle.close, 50);
      _ema200 = _ema(_ema200, candle.close, 200);
      _atr14 = _count < 14
          ? (_atr14 * _count + trueRange) / (_count + 1)
          : (_atr14 * 13 + trueRange) / 14;
    }

    _window.addLast(candle);
    _closeSum20 += candle.close;
    _closeSquareSum20 += candle.close * candle.close;
    _volumeSum21 += candle.volume;
    if (_window.length > 20) {
      final leavingWindow = _window.elementAt(_window.length - 21);
      _closeSum20 -= leavingWindow.close;
      _closeSquareSum20 -= leavingWindow.close * leavingWindow.close;
    }
    while (_window.length > 21) {
      _volumeSum21 -= _window.removeFirst().volume;
    }

    _count++;
    _lastClose = candle.close;
    _lastOpenTimeUtc = candle.openTime;
    if (_count < 21) return null;

    final currentWindow = _window.toList(growable: false);
    final current = currentWindow.last;
    final previous = currentWindow.take(currentWindow.length - 1);
    var donchianHigh = -double.infinity;
    var donchianLow = double.infinity;
    for (final value in previous) {
      donchianHigh = math.max(donchianHigh, value.high);
      donchianLow = math.min(donchianLow, value.low);
    }
    final averagePreviousVolume = (_volumeSum21 - current.volume) / 20;
    final mean = _closeSum20 / 20;
    final variance = math.max(0, _closeSquareSum20 / 20 - mean * mean);
    return RollingMarketFeatureSnapshot(
      version: version,
      candleCount: _count,
      sma20: mean,
      ema20: _ema20,
      ema50: _ema50,
      ema200: _ema200,
      atr14: _atr14,
      relativeVolume20: averagePreviousVolume <= 0
          ? 0.0
          : current.volume / averagePreviousVolume,
      closeVolatility20: math.sqrt(variance),
      previousDonchianHigh20: donchianHigh,
      previousDonchianLow20: donchianLow,
    );
  }

  static double _ema(double previous, double value, int period) {
    final multiplier = 2 / (period + 1);
    return value * multiplier + previous * (1 - multiplier);
  }
}

/// Independent batch reference used only for equivalence and benchmark gates.
abstract final class BatchMarketFeatureReference {
  static RollingMarketFeatureSnapshot compute(List<ChartCandle> candles) {
    if (candles.length < 21 || candles.any((candle) => !candle.isValid)) {
      throw ArgumentError('At least 21 valid candles are required.');
    }
    for (var index = 1; index < candles.length; index++) {
      if (!candles[index].openTime.isAfter(candles[index - 1].openTime)) {
        throw ArgumentError('Candles must be strictly ordered.');
      }
    }
    var ema20 = candles.first.close;
    var ema50 = candles.first.close;
    var ema200 = candles.first.close;
    var atr14 = candles.first.high - candles.first.low;
    for (var index = 1; index < candles.length; index++) {
      final candle = candles[index];
      final previousClose = candles[index - 1].close;
      final trueRange = math.max(
        candle.high - candle.low,
        math.max(
          (candle.high - previousClose).abs(),
          (candle.low - previousClose).abs(),
        ),
      );
      ema20 = _ema(ema20, candle.close, 20);
      ema50 = _ema(ema50, candle.close, 50);
      ema200 = _ema(ema200, candle.close, 200);
      atr14 = index < 14
          ? (atr14 * index + trueRange) / (index + 1)
          : (atr14 * 13 + trueRange) / 14;
    }
    final currentWindow = candles.sublist(candles.length - 20);
    final previousWindow = candles.sublist(
      candles.length - 21,
      candles.length - 1,
    );
    final closeSum = currentWindow.fold<double>(
      0,
      (sum, candle) => sum + candle.close,
    );
    final closeSquareSum = currentWindow.fold<double>(
      0,
      (sum, candle) => sum + candle.close * candle.close,
    );
    final volumeAverage =
        previousWindow.fold<double>(0, (sum, candle) => sum + candle.volume) /
        20;
    final mean = closeSum / 20;
    return RollingMarketFeatureSnapshot(
      version: RollingMarketFeatureState.version,
      candleCount: candles.length,
      sma20: mean,
      ema20: ema20,
      ema50: ema50,
      ema200: ema200,
      atr14: atr14,
      relativeVolume20: volumeAverage <= 0
          ? 0.0
          : candles.last.volume / volumeAverage,
      closeVolatility20: math.sqrt(
        math.max(0, closeSquareSum / 20 - mean * mean),
      ),
      previousDonchianHigh20: previousWindow
          .map((candle) => candle.high)
          .reduce(math.max),
      previousDonchianLow20: previousWindow
          .map((candle) => candle.low)
          .reduce(math.min),
    );
  }

  static double _ema(double previous, double value, int period) {
    final multiplier = 2 / (period + 1);
    return value * multiplier + previous * (1 - multiplier);
  }
}
