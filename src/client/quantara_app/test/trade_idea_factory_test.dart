import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/market_analysis/domain/market_chart_models.dart';
import 'package:quantara_app/features/owner_alpha/data/trade_idea_factory.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';

void main() {
  test('uses leverage to keep margin within the per-position budget', () {
    final analysis = _analysis(direction: ChartDirection.bullish);
    final idea = TradeIdeaFactory.create(
      analysis: analysis,
      capital: 10000,
      riskPercent: 1,
      confluence: const {'4h': ChartDirection.bullish},
      strategy: AnalysisStrategy.trendPullback,
    );
    final repeated = TradeIdeaFactory.create(
      analysis: analysis,
      capital: 10000,
      riskPercent: 1,
      confluence: const {'4h': ChartDirection.bullish},
      strategy: AnalysisStrategy.trendPullback,
    );

    expect(idea.direction, TradeDirection.long);
    expect(idea.maximumLoss, 100);
    expect(idea.recommendedLeverage, greaterThan(1));
    expect(idea.targets, hasLength(3));
    expect(idea.targets[1], greaterThan(idea.targets[0]));
    expect(idea.targets[2], greaterThan(idea.targets[1]));
    expect(
      idea.requiredMargin,
      lessThanOrEqualTo(10000 * TradeIdeaFactory.targetMarginFraction + 0.0001),
    );
    final conservativeEntry = idea.entryUpper!;
    final lossPerUnit =
        (conservativeEntry - idea.stopLoss!).abs() +
        conservativeEntry * TradeIdeaFactory.assumedRoundTripCostRate;
    expect(idea.positionSize! * lossPerUnit, closeTo(100, 0.01));
    expect(idea.estimatedRoundTripCosts, greaterThan(0));
    expect(idea.setupId, hasLength(64));
    expect(idea.setupId, repeated.setupId);
    expect(idea.candleClosedAt, analysis.generatedAt);
  });

  test('returns wait when the market has no aligned parent structure', () {
    final idea = TradeIdeaFactory.create(
      analysis: _analysis(direction: ChartDirection.sideways),
      capital: 10000,
      riskPercent: 1,
    );

    expect(idea.direction, TradeDirection.wait);
    expect(idea.positionSize, isNull);
    expect(idea.estimatedRoundTripCosts, 0);
    expect(idea.targets, isEmpty);
  });

  test('builds a short setup with stop above entry and targets below it', () {
    final idea = TradeIdeaFactory.create(
      analysis: _analysis(direction: ChartDirection.bearish),
      capital: 10000,
      riskPercent: 1,
      confluence: const {'4h': ChartDirection.bearish},
      strategy: AnalysisStrategy.trendPullback,
    );

    expect(idea.direction, TradeDirection.short);
    expect(idea.stopLoss, greaterThan(idea.entryUpper!));
    expect(idea.targets.first, lessThan(idea.entryLower!));
    expect(idea.targets[1], lessThan(idea.targets[0]));
    expect(idea.targets[2], lessThan(idea.targets[1]));
    expect(idea.riskReward, greaterThanOrEqualTo(1.6));
    expect(idea.setupId, hasLength(64));
    expect(
      idea.requiredMargin,
      lessThanOrEqualTo(10000 * TradeIdeaFactory.targetMarginFraction + 0.0001),
    );
  });
}

TimeframeChartAnalysis _analysis({required ChartDirection direction}) {
  final bearish = direction == ChartDirection.bearish;
  final sideways = direction == ChartDirection.sideways;
  final sign = bearish ? -1.0 : 1.0;
  var price = 100.0;
  final candles = <ChartCandle>[];
  for (var index = 0; index < 80; index++) {
    late final double open;
    late final double close;
    late final double high;
    late final double low;
    late final double volume;
    if (sideways) {
      open = 100 + (index.isEven ? -0.1 : 0.1);
      close = 100 + (index.isEven ? 0.1 : -0.1);
      high = 100.5;
      low = 99.5;
      volume = 1000;
    } else if (index < 75) {
      open = price;
      close = open + sign * 0.15;
      high = (open > close ? open : close) + 0.2;
      low = (open < close ? open : close) - 0.2;
      volume = 1000;
    } else if (index < 79) {
      open = price;
      close = open - sign * 0.35;
      high = (open > close ? open : close) + 0.15;
      low = (open < close ? open : close) - 0.2;
      volume = 950;
    } else {
      open = price;
      close = open + sign * 0.45;
      high = (open > close ? open : close) + 0.15;
      low = (open < close ? open : close) - 0.15;
      volume = 1250;
    }
    candles.add(
      ChartCandle(
        openTime: DateTime.utc(2026, 7, 1).add(Duration(hours: index)),
        open: open,
        high: high,
        low: low,
        close: close,
        volume: volume,
      ),
    );
    price = close;
  }
  final current = candles.last.close;
  final closedAt = candles.last.openTime.add(const Duration(hours: 1));
  return TimeframeChartAnalysis(
    symbol: 'BTCUSDT',
    timeframe: '1h',
    candles: candles,
    zones: [
      ChartPriceZone(
        lower: current - (bearish ? 16 : 4.5),
        upper: current - (bearish ? 14 : 3.5),
        role: ChartZoneRole.support,
        state: ChartZoneState.active,
        touchCount: 4,
        strength: 0.8,
        distancePercent: 3,
        lastTouchedAt: candles[65].openTime,
        explanation: 'support',
      ),
      ChartPriceZone(
        lower: current + (bearish ? 3.5 : 14),
        upper: current + (bearish ? 4.5 : 16),
        role: ChartZoneRole.resistance,
        state: ChartZoneState.active,
        touchCount: 3,
        strength: 0.72,
        distancePercent: 10,
        lastTouchedAt: candles[68].openTime,
        explanation: 'resistance',
      ),
    ],
    direction: direction,
    directionStrength: direction == ChartDirection.sideways ? 0.1 : 0.8,
    volatilityPercent: 0.8,
    summary: 'test',
    generatedAt: closedAt,
    fingerprint: 'test-fingerprint-${direction.name}',
  );
}
