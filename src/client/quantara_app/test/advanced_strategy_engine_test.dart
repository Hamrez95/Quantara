import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/market_analysis/domain/market_chart_models.dart';
import 'package:quantara_app/features/owner_alpha/data/trade_idea_factory.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';

void main() {
  test('structure and zones can promote a closed-candle price action reversal', () {
    final candles = <ChartCandle>[];
    for (var index = 0; index < 118; index++) {
      final center = 100 + math.sin(index * 0.45) * 0.75;
      final open = center - 0.12;
      final close = center + 0.12;
      candles.add(
        ChartCandle(
          openTime: DateTime.utc(2026, 1, 1).add(Duration(hours: index)),
          open: open,
          high: math.max(open, close) + 0.28,
          low: math.min(open, close) - 0.28,
          close: close,
          volume: 1000,
        ),
      );
    }
    candles.add(
      ChartCandle(
        openTime: DateTime.utc(2026, 1, 1).add(const Duration(hours: 118)),
        open: 100.0,
        high: 100.15,
        low: 98.85,
        close: 99.0,
        volume: 950,
      ),
    );
    candles.add(
      ChartCandle(
        openTime: DateTime.utc(2026, 1, 1).add(const Duration(hours: 119)),
        open: 98.9,
        high: 100.35,
        low: 98.45,
        close: 100.2,
        volume: 1250,
      ),
    );

    final analysis = TimeframeChartAnalysis(
      symbol: 'BTCUSDT',
      timeframe: '1h',
      candles: candles,
      zones: [
        ChartPriceZone(
          lower: 98.55,
          upper: 99.15,
          role: ChartZoneRole.support,
          state: ChartZoneState.active,
          touchCount: 4,
          strength: 0.86,
          distancePercent: 1.2,
          lastTouchedAt: candles.last.openTime,
          explanation: 'validated support',
        ),
      ],
      direction: ChartDirection.sideways,
      directionStrength: 0.12,
      volatilityPercent: 1.0,
      summary: 'range support test',
      generatedAt: DateTime.utc(2026, 1, 6),
      fingerprint: 'price-action-reversal-test',
    );

    final idea = TradeIdeaFactory.create(
      analysis: analysis,
      capital: 10000,
      riskPercent: 1,
      languageCode: 'en',
      strategy: AnalysisStrategy.structureZones,
      cadence: SignalCadence.active,
    );

    expect(idea.isActionable, isTrue);
    expect(idea.direction, TradeDirection.long);
    expect(idea.strategyVersion, contains('adaptive-price-action'));
    expect(idea.stopLoss, lessThan(idea.entryLower!));
    expect(idea.targets.first, greaterThan(idea.entryUpper!));
    expect(idea.maximumLoss, closeTo(100, 0.001));
  });

  test('trend pullback can promote a no-lookahead Ichimoku setup', () {
    final candles = <ChartCandle>[];
    var price = 100.0;
    for (var index = 0; index < 170; index++) {
      final open = price;
      final close = open + 0.32;
      candles.add(
        ChartCandle(
          openTime: DateTime.utc(2026, 2, 1).add(Duration(hours: index)),
          open: open,
          high: close + 0.22,
          low: open - 0.18,
          close: close,
          volume: 1100,
        ),
      );
      price = close;
    }
    for (var index = 170; index < 179; index++) {
      final open = price;
      final close = open - 0.18;
      candles.add(
        ChartCandle(
          openTime: DateTime.utc(2026, 2, 1).add(Duration(hours: index)),
          open: open,
          high: open + 0.20,
          low: close - 0.20,
          close: close,
          volume: 950,
        ),
      );
      price = close;
    }
    candles.add(
      ChartCandle(
        openTime: DateTime.utc(2026, 2, 1).add(const Duration(hours: 179)),
        open: price - 0.15,
        high: price + 0.65,
        low: price - 0.30,
        close: price + 0.55,
        volume: 1350,
      ),
    );

    final analysis = TimeframeChartAnalysis(
      symbol: 'ETHUSDT',
      timeframe: '1h',
      candles: candles,
      zones: const [],
      direction: ChartDirection.bullish,
      directionStrength: 0.78,
      volatilityPercent: 0.8,
      summary: 'Ichimoku pullback test',
      generatedAt: DateTime.utc(2026, 2, 9),
      fingerprint: 'ichimoku-trend-test',
    );

    final idea = TradeIdeaFactory.create(
      analysis: analysis,
      capital: 10000,
      riskPercent: 1,
      languageCode: 'en',
      strategy: AnalysisStrategy.trendPullback,
      cadence: SignalCadence.active,
      confluence: const {
        '15m': ChartDirection.bullish,
        '1h': ChartDirection.bullish,
        '4h': ChartDirection.bullish,
      },
    );

    expect(idea.isActionable, isTrue);
    expect(idea.direction, TradeDirection.long);
    expect(
      idea.strategyVersion,
      anyOf(contains('ichimoku'), contains('trend-pullback')),
    );
    expect(idea.stopLoss, lessThan(idea.entryLower!));
    expect(idea.targets, hasLength(3));
  });
}
