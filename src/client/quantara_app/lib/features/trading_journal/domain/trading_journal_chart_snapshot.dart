import '../../market_analysis/domain/market_chart_models.dart';

/// Versioned, bounded codec for the market chart that existed when a journal
/// decision was made. The compact representation deliberately fits inside the
/// existing immutable numeric indicator snapshot, so it inherits the journal's
/// durability/checksum/restart behavior without adding a second persistence
/// path or consulting newer market data while decoding.
abstract final class TradingJournalChartSnapshot {
  static const schemaVersion = 1;
  static const maximumCandles = 64;
  static const maximumZones = 8;
  static const _prefix = 'journalChart.v1.';

  static Map<String, double> encodeIntoIndicatorSnapshot(
    TimeframeChartAnalysis analysis,
  ) {
    final sourceCandles = analysis.candles.length <= maximumCandles
        ? analysis.candles
        : analysis.candles.skip(analysis.candles.length - maximumCandles);
    final candles = sourceCandles.toList(growable: false);
    final zones = analysis.strongestZones.take(maximumZones).toList(
      growable: false,
    );
    final result = <String, double>{
      '${_prefix}schema': schemaVersion.toDouble(),
      '${_prefix}generatedAtMs': analysis.generatedAt
          .toUtc()
          .millisecondsSinceEpoch
          .toDouble(),
      '${_prefix}direction': analysis.direction.index.toDouble(),
      '${_prefix}directionStrength': analysis.directionStrength,
      '${_prefix}volatilityPercent': analysis.volatilityPercent,
      '${_prefix}candleCount': candles.length.toDouble(),
      '${_prefix}zoneCount': zones.length.toDouble(),
    };
    for (var index = 0; index < candles.length; index++) {
      final candle = candles[index];
      final base = '${_prefix}c$index.';
      result['${base}timeMs'] = candle.openTime
          .toUtc()
          .millisecondsSinceEpoch
          .toDouble();
      result['${base}open'] = candle.open;
      result['${base}high'] = candle.high;
      result['${base}low'] = candle.low;
      result['${base}close'] = candle.close;
      result['${base}volume'] = candle.volume;
    }
    for (var index = 0; index < zones.length; index++) {
      final zone = zones[index];
      final base = '${_prefix}z$index.';
      result['${base}lower'] = zone.lower;
      result['${base}upper'] = zone.upper;
      result['${base}role'] = zone.role.index.toDouble();
      result['${base}state'] = zone.state.index.toDouble();
      result['${base}touchCount'] = zone.touchCount.toDouble();
      result['${base}strength'] = zone.strength;
      result['${base}distancePercent'] = zone.distancePercent;
      result['${base}lastTouchedMs'] = zone.lastTouchedAt
          .toUtc()
          .millisecondsSinceEpoch
          .toDouble();
    }
    return result;
  }

  static TimeframeChartAnalysis? decodeFromIndicatorSnapshot(
    Map<String, double> snapshot, {
    required String symbol,
    required String timeframe,
  }) {
    final schema = snapshot['${_prefix}schema']?.round();
    final generatedAtMs = snapshot['${_prefix}generatedAtMs']?.round();
    final directionIndex = snapshot['${_prefix}direction']?.round();
    final directionStrength = snapshot['${_prefix}directionStrength'];
    final volatilityPercent = snapshot['${_prefix}volatilityPercent'];
    final candleCount = snapshot['${_prefix}candleCount']?.round();
    final zoneCount = snapshot['${_prefix}zoneCount']?.round();
    if (schema != schemaVersion ||
        generatedAtMs == null ||
        directionIndex == null ||
        directionIndex < 0 ||
        directionIndex >= ChartDirection.values.length ||
        directionStrength == null ||
        volatilityPercent == null ||
        candleCount == null ||
        candleCount < 20 ||
        candleCount > maximumCandles ||
        zoneCount == null ||
        zoneCount < 0 ||
        zoneCount > maximumZones ||
        symbol.trim().isEmpty ||
        timeframe.trim().isEmpty) {
      return null;
    }

    final candles = <ChartCandle>[];
    for (var index = 0; index < candleCount; index++) {
      final base = '${_prefix}c$index.';
      final timeMs = snapshot['${base}timeMs']?.round();
      final open = snapshot['${base}open'];
      final high = snapshot['${base}high'];
      final low = snapshot['${base}low'];
      final close = snapshot['${base}close'];
      final volume = snapshot['${base}volume'];
      if (timeMs == null ||
          open == null ||
          high == null ||
          low == null ||
          close == null ||
          volume == null) {
        return null;
      }
      final candle = ChartCandle(
        openTime: DateTime.fromMillisecondsSinceEpoch(timeMs, isUtc: true),
        open: open,
        high: high,
        low: low,
        close: close,
        volume: volume,
      );
      if (!candle.isValid) return null;
      candles.add(candle);
    }

    final zones = <ChartPriceZone>[];
    for (var index = 0; index < zoneCount; index++) {
      final base = '${_prefix}z$index.';
      final lower = snapshot['${base}lower'];
      final upper = snapshot['${base}upper'];
      final roleIndex = snapshot['${base}role']?.round();
      final stateIndex = snapshot['${base}state']?.round();
      final touchCount = snapshot['${base}touchCount']?.round();
      final strength = snapshot['${base}strength'];
      final distancePercent = snapshot['${base}distancePercent'];
      final lastTouchedMs = snapshot['${base}lastTouchedMs']?.round();
      if (lower == null ||
          upper == null ||
          roleIndex == null ||
          roleIndex < 0 ||
          roleIndex >= ChartZoneRole.values.length ||
          stateIndex == null ||
          stateIndex < 0 ||
          stateIndex >= ChartZoneState.values.length ||
          touchCount == null ||
          strength == null ||
          distancePercent == null ||
          lastTouchedMs == null) {
        return null;
      }
      zones.add(
        ChartPriceZone(
          lower: lower,
          upper: upper,
          role: ChartZoneRole.values[roleIndex],
          state: ChartZoneState.values[stateIndex],
          touchCount: touchCount,
          strength: strength,
          distancePercent: distancePercent,
          lastTouchedAt: DateTime.fromMillisecondsSinceEpoch(
            lastTouchedMs,
            isUtc: true,
          ),
          explanation: 'Persisted decision-time zone',
        ),
      );
    }

    try {
      return TimeframeChartAnalysis(
        symbol: symbol.trim().toUpperCase(),
        timeframe: timeframe.trim(),
        candles: candles,
        zones: zones,
        direction: ChartDirection.values[directionIndex],
        directionStrength: directionStrength,
        volatilityPercent: volatilityPercent,
        summary: 'Persisted decision-time journal snapshot',
        generatedAt: DateTime.fromMillisecondsSinceEpoch(
          generatedAtMs,
          isUtc: true,
        ),
        fingerprint: 'journal-snapshot-v1-$generatedAtMs-$candleCount',
      );
    } on ArgumentError {
      return null;
    }
  }

  static bool containsSnapshot(Map<String, double> snapshot) =>
      snapshot['${_prefix}schema']?.round() == schemaVersion;
}
