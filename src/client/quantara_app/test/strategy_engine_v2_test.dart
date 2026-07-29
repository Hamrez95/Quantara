import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/market_analysis/domain/market_chart_models.dart';
import 'package:quantara_app/features/owner_alpha/data/trade_idea_factory.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';

void main() {
  test('momentum continuation creates a risk-sized Donchian setup', () {
    final candles = <ChartCandle>[];
    var price = 100.0;
    for (var index = 0; index < 219; index++) {
      final open = price;
      final close = open + 0.08;
      candles.add(
        ChartCandle(
          openTime: DateTime.utc(2026, 1, 1).add(Duration(hours: index)),
          open: open,
          high: close + 0.18,
          low: open - 0.14,
          close: close,
          volume: 1000,
        ),
      );
      price = close;
    }
    candles.add(
      ChartCandle(
        openTime: DateTime.utc(2026, 1, 1).add(const Duration(hours: 219)),
        open: price,
        high: price + 3.4,
        low: price - 0.3,
        close: price + 3.0,
        volume: 4200,
      ),
    );
    final analysis = TimeframeChartAnalysis(
      symbol: 'BTCUSDT',
      timeframe: '1h',
      candles: candles,
      zones: const [],
      direction: ChartDirection.bullish,
      directionStrength: 0.8,
      volatilityPercent: 1.2,
      summary: 'test breakout',
      generatedAt: DateTime.utc(2026, 1, 12),
      fingerprint: 'donchian-breakout-test',
    );

    final idea = TradeIdeaFactory.create(
      analysis: analysis,
      capital: 10000,
      riskPercent: 1,
      languageCode: 'en',
      strategy: AnalysisStrategy.momentumContinuation,
      cadence: SignalCadence.active,
      confluence: const {
        '15m': ChartDirection.bullish,
        '1h': ChartDirection.bullish,
        '4h': ChartDirection.bullish,
      },
    );

    expect(idea.isActionable, isTrue);
    expect(idea.direction, TradeDirection.long);
    expect(idea.targets, hasLength(3));
    expect(idea.riskReward, 1.8);
    expect(idea.strategyVersion, contains('donchian'));
    expect(idea.maximumLoss, closeTo(100, 0.001));
    expect(idea.positionSize, isNotNull);
    expect(idea.recommendedLeverage, isNotNull);
  });
}
