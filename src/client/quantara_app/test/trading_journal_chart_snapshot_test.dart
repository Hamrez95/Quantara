import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/market_analysis/domain/market_chart_models.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_chart_snapshot.dart';

void main() {
  TimeframeChartAnalysis analysis() {
    final start = DateTime.utc(2026, 8, 20);
    final candles = List.generate(80, (index) {
      final open = 100.0 + index;
      return ChartCandle(
        openTime: start.add(Duration(minutes: 15 * index)),
        open: open,
        high: open + 2,
        low: open - 1,
        close: open + 1,
        volume: 1000 + index.toDouble(),
      );
    });
    return TimeframeChartAnalysis(
      symbol: 'BTCUSDT',
      timeframe: '15m',
      candles: candles,
      zones: [
        ChartPriceZone(
          lower: 120,
          upper: 122,
          role: ChartZoneRole.support,
          state: ChartZoneState.active,
          touchCount: 3,
          strength: 0.8,
          distancePercent: 1.2,
          lastTouchedAt: start.add(const Duration(hours: 8)),
          explanation: 'fixture',
        ),
      ],
      direction: ChartDirection.bullish,
      directionStrength: 0.77,
      volatilityPercent: 2.4,
      summary: 'fixture',
      generatedAt: start.add(const Duration(hours: 20)),
      fingerprint: 'fixture-80',
    );
  }

  test('persists a bounded immutable decision-time chart and replays it', () {
    final source = analysis();
    final encoded = TradingJournalChartSnapshot.encodeIntoIndicatorSnapshot(
      source,
    );
    final replay = TradingJournalChartSnapshot.decodeFromIndicatorSnapshot(
      encoded,
      symbol: source.symbol,
      timeframe: source.timeframe,
    );

    expect(TradingJournalChartSnapshot.containsSnapshot(encoded), isTrue);
    expect(replay, isNotNull);
    expect(replay!.candles, hasLength(64));
    expect(replay.candles.first.openTime, source.candles[16].openTime);
    expect(replay.candles.last.close, source.candles.last.close);
    expect(replay.generatedAt, source.generatedAt);
    expect(replay.direction, ChartDirection.bullish);
    expect(replay.directionStrength, source.directionStrength);
    expect(replay.zones.single.lower, 120);
    expect(replay.zones.single.upper, 122);
  });

  test('refuses incomplete or unbounded snapshot instead of inventing data', () {
    final encoded = TradingJournalChartSnapshot.encodeIntoIndicatorSnapshot(
      analysis(),
    );
    final missingCandle = Map<String, double>.from(encoded)
      ..remove('journalChart.v1.c0.open');
    final oversized = Map<String, double>.from(encoded)
      ..['journalChart.v1.candleCount'] =
          (TradingJournalChartSnapshot.maximumCandles + 1).toDouble();

    expect(
      TradingJournalChartSnapshot.decodeFromIndicatorSnapshot(
        missingCandle,
        symbol: 'BTCUSDT',
        timeframe: '15m',
      ),
      isNull,
    );
    expect(
      TradingJournalChartSnapshot.decodeFromIndicatorSnapshot(
        oversized,
        symbol: 'BTCUSDT',
        timeframe: '15m',
      ),
      isNull,
    );
  });
}
