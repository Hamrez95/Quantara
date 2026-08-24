import '../../market_analysis/domain/market_chart_models.dart';

/// Versioned, bounded codec for the market chart that existed when a journal
/// decision was made. The snapshot contains market evidence only and never
/// fetches newer candles while decoding.
abstract final class TradingJournalChartSnapshot {
  static const schemaVersion = 1;
  static const maximumCandles = 120;
  static const maximumZones = 8;

  static Map<String, Object?> encode(TimeframeChartAnalysis analysis) {
    final candles = analysis.candles.length <= maximumCandles
        ? analysis.candles
        : analysis.candles.skip(analysis.candles.length - maximumCandles);
    final zones = analysis.zones.length <= maximumZones
        ? analysis.zones
        : analysis.zones.take(maximumZones);
    return <String, Object?>{
      'schemaVersion': schemaVersion,
      'symbol': analysis.symbol,
      'timeframe': analysis.timeframe,
      'generatedAt': analysis.generatedAt.toUtc().toIso8601String(),
      'fingerprint': analysis.fingerprint,
      'direction': analysis.direction.name,
      'directionStrength': analysis.directionStrength,
      'volatilityPercent': analysis.volatilityPercent,
      'summary': analysis.summary,
      'candles': candles
          .map(
            (candle) => <String, Object?>{
              'openTime': candle.openTime.toUtc().toIso8601String(),
              'open': candle.open,
              'high': candle.high,
              'low': candle.low,
              'close': candle.close,
              'volume': candle.volume,
            },
          )
          .toList(growable: false),
      'zones': zones
          .map(
            (zone) => <String, Object?>{
              'lower': zone.lower,
              'upper': zone.upper,
              'role': zone.role.name,
              'state': zone.state.name,
              'touchCount': zone.touchCount,
              'strength': zone.strength,
              'distancePercent': zone.distancePercent,
              'lastTouchedAt': zone.lastTouchedAt.toUtc().toIso8601String(),
              'explanation': zone.explanation,
            },
          )
          .toList(growable: false),
    };
  }

  static TimeframeChartAnalysis? decode(Object? raw) {
    if (raw is! Map<Object?, Object?>) return null;
    final json = raw.map((key, value) => MapEntry(key.toString(), value));
    if ((json['schemaVersion'] as num?)?.toInt() != schemaVersion) return null;
    final symbol = json['symbol']?.toString().trim() ?? '';
    final timeframe = json['timeframe']?.toString().trim() ?? '';
    final generatedAt = DateTime.tryParse(json['generatedAt']?.toString() ?? '')
        ?.toUtc();
    final fingerprint = json['fingerprint']?.toString().trim() ?? '';
    if (symbol.isEmpty ||
        timeframe.isEmpty ||
        generatedAt == null ||
        fingerprint.isEmpty) {
      return null;
    }

    final candleRows = json['candles'];
    if (candleRows is! List<Object?> ||
        candleRows.length < 20 ||
        candleRows.length > maximumCandles) {
      return null;
    }
    final candles = <ChartCandle>[];
    for (final row in candleRows) {
      if (row is! Map<Object?, Object?>) return null;
      final item = row.map((key, value) => MapEntry(key.toString(), value));
      final openTime = DateTime.tryParse(item['openTime']?.toString() ?? '')
          ?.toUtc();
      final open = (item['open'] as num?)?.toDouble();
      final high = (item['high'] as num?)?.toDouble();
      final low = (item['low'] as num?)?.toDouble();
      final close = (item['close'] as num?)?.toDouble();
      final volume = (item['volume'] as num?)?.toDouble();
      if (openTime == null ||
          open == null ||
          high == null ||
          low == null ||
          close == null ||
          volume == null) {
        return null;
      }
      final candle = ChartCandle(
        openTime: openTime,
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
    final zoneRows = json['zones'];
    if (zoneRows is List<Object?>) {
      if (zoneRows.length > maximumZones) return null;
      for (final row in zoneRows) {
        if (row is! Map<Object?, Object?>) return null;
        final item = row.map((key, value) => MapEntry(key.toString(), value));
        final lower = (item['lower'] as num?)?.toDouble();
        final upper = (item['upper'] as num?)?.toDouble();
        final touchCount = (item['touchCount'] as num?)?.toInt();
        final strength = (item['strength'] as num?)?.toDouble();
        final distancePercent = (item['distancePercent'] as num?)?.toDouble();
        final lastTouchedAt =
            DateTime.tryParse(item['lastTouchedAt']?.toString() ?? '')?.toUtc();
        final role = ChartZoneRole.values
            .where((value) => value.name == item['role']?.toString())
            .firstOrNull;
        final state = ChartZoneState.values
            .where((value) => value.name == item['state']?.toString())
            .firstOrNull;
        if (lower == null ||
            upper == null ||
            touchCount == null ||
            strength == null ||
            distancePercent == null ||
            lastTouchedAt == null ||
            role == null ||
            state == null) {
          return null;
        }
        zones.add(
          ChartPriceZone(
            lower: lower,
            upper: upper,
            role: role,
            state: state,
            touchCount: touchCount,
            strength: strength,
            distancePercent: distancePercent,
            lastTouchedAt: lastTouchedAt,
            explanation: item['explanation']?.toString() ?? '',
          ),
        );
      }
    }

    final direction = ChartDirection.values
        .where((value) => value.name == json['direction']?.toString())
        .firstOrNull;
    final directionStrength = (json['directionStrength'] as num?)?.toDouble();
    final volatilityPercent = (json['volatilityPercent'] as num?)?.toDouble();
    if (direction == null ||
        directionStrength == null ||
        volatilityPercent == null) {
      return null;
    }

    try {
      return TimeframeChartAnalysis(
        symbol: symbol,
        timeframe: timeframe,
        candles: candles,
        zones: zones,
        direction: direction,
        directionStrength: directionStrength,
        volatilityPercent: volatilityPercent,
        summary: json['summary']?.toString() ?? '',
        generatedAt: generatedAt,
        fingerprint: fingerprint,
      );
    } on ArgumentError {
      return null;
    }
  }
}
