import '../../cockpit/domain/cockpit_models.dart';
import '../domain/market_chart_models.dart';
import 'chart_structure_analyzer.dart';
import 'demo_candle_series.dart';

abstract final class DemoMarketChartFactory {
  static TimeframeChartAnalysis create({
    required MarketQuote quote,
    required String timeframe,
  }) {
    final interval = _durationFor(timeframe);
    final candles = DemoCandleSeries.build(
      key: '${quote.symbol}|$timeframe|structure-v1',
      lastValue: quote.price,
      changePercent: quote.changePercent,
      interval: interval,
    );
    final structure = ChartStructureAnalyzer.analyze(candles);
    return TimeframeChartAnalysis(
      symbol: quote.symbol,
      timeframe: timeframe,
      candles: candles,
      zones: structure.zones,
      direction: structure.direction,
      directionStrength: structure.directionStrength,
      volatilityPercent: structure.volatilityPercent,
      summary: _summary(structure, candles.last.close, timeframe),
      generatedAt: DateTime.utc(2026, 7, 20, 23),
      fingerprint: _fingerprint(
        quote.symbol,
        timeframe,
        candles,
        structure.zones,
      ),
    );
  }

  static Duration _durationFor(String timeframe) {
    return switch (timeframe) {
      '15m' => const Duration(minutes: 15),
      '1h' => const Duration(hours: 1),
      '4h' => const Duration(hours: 4),
      '1D' => const Duration(days: 1),
      _ => throw ArgumentError.value(timeframe, 'timeframe'),
    };
  }

  static String _summary(
    ChartStructureSnapshot structure,
    double currentValue,
    String timeframe,
  ) {
    final direction = switch (structure.direction) {
      ChartDirection.bullish => 'ساختار $timeframe متمایل به صعود است',
      ChartDirection.bearish => 'ساختار $timeframe متمایل به نزول است',
      ChartDirection.sideways => 'ساختار $timeframe فعلاً خنثی و نوسانی است',
    };
    final below =
        structure.zones
            .where((zone) => zone.center < currentValue)
            .toList(growable: false)
          ..sort((left, right) => right.center.compareTo(left.center));
    final above =
        structure.zones
            .where((zone) => zone.center > currentValue)
            .toList(growable: false)
          ..sort((left, right) => left.center.compareTo(right.center));
    final support = below.isEmpty
        ? 'حمایت معتبر نزدیک پیدا نشد'
        : 'حمایت نزدیک ${below.first.center.toStringAsFixed(2)}';
    final resistance = above.isEmpty
        ? 'مقاومت معتبر نزدیک پیدا نشد'
        : 'مقاومت نزدیک ${above.first.center.toStringAsFixed(2)}';
    return '$direction؛ $support و $resistance.';
  }

  static String _fingerprint(
    String symbol,
    String timeframe,
    List<ChartCandle> candles,
    Iterable<ChartPriceZone> zones,
  ) {
    var hash = 2166136261;
    void add(String value) {
      for (final unit in value.codeUnits) {
        hash = ((hash ^ unit) * 16777619) & 0xFFFFFFFF;
      }
    }

    add(symbol);
    add(timeframe);
    for (final candle in candles) {
      add(candle.openTime.microsecondsSinceEpoch.toString());
      add(candle.open.toStringAsFixed(8));
      add(candle.high.toStringAsFixed(8));
      add(candle.low.toStringAsFixed(8));
      add(candle.close.toStringAsFixed(8));
    }
    for (final zone in zones) {
      add(zone.lower.toStringAsFixed(8));
      add(zone.upper.toStringAsFixed(8));
      add(zone.strength.toStringAsFixed(6));
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}

