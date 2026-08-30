import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/market_analysis/domain/market_chart_models.dart';
import 'package:quantara_app/features/owner_alpha/data/trade_idea_factory.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_chart_snapshot.dart';

void main() {
  test(
    'factory attaches bounded decision chart snapshot before journal persistence',
    () {
      final start = DateTime.utc(2026, 8, 20);
      final analysis = TimeframeChartAnalysis(
        symbol: 'BTCUSDT',
        timeframe: '15m',
        candles: List.generate(30, (index) {
          final open = 100.0 + index;
          return ChartCandle(
            openTime: start.add(Duration(minutes: index * 15)),
            open: open,
            high: open + 2,
            low: open - 1,
            close: open + 1,
            volume: 100,
          );
        }),
        zones: [
          ChartPriceZone(
            lower: 120,
            upper: 122,
            role: ChartZoneRole.support,
            state: ChartZoneState.active,
            touchCount: 3,
            strength: 0.9,
            distancePercent: 1,
            lastTouchedAt: start.add(const Duration(hours: 6)),
            explanation: 'fixture',
          ),
        ],
        direction: ChartDirection.bullish,
        directionStrength: 0.9,
        volatilityPercent: 1.2,
        summary: 'fixture',
        generatedAt: start.add(const Duration(hours: 8)),
        fingerprint: 'fixture',
      );

      final idea = TradeIdeaFactory.create(
        analysis: analysis,
        capital: 1000,
        riskPercent: 1,
      );

      expect(
        TradingJournalChartSnapshot.containsSnapshot(idea.indicatorSnapshot),
        isTrue,
      );
      final replay = TradingJournalChartSnapshot.decodeFromIndicatorSnapshot(
        idea.indicatorSnapshot,
        symbol: idea.symbol,
        timeframe: idea.timeframe,
      );
      expect(replay, isNotNull);
      expect(replay!.latestCandle.close, analysis.latestCandle.close);
    },
  );
}
