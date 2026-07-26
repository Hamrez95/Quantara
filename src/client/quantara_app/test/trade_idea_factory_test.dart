import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/market_analysis/domain/market_chart_models.dart';
import 'package:quantara_app/features/owner_alpha/data/trade_idea_factory.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';

void main() {
  test('sizes an actionable idea from stop distance and estimated costs', () {
    final analysis = _analysis(direction: ChartDirection.bullish);

    final idea = TradeIdeaFactory.create(
      analysis: analysis,
      capital: 10000,
      riskPercent: 1,
      confluence: const {
        '1h': ChartDirection.bullish,
        '4h': ChartDirection.bullish,
      },
    );

    expect(idea.direction, TradeDirection.long);
    expect(idea.maximumLoss, 100);
    expect(idea.positionSize, isNotNull);
    final conservativeEntry = idea.entryUpper!;
    final lossPerUnit =
        (conservativeEntry - idea.stopLoss!).abs() +
        conservativeEntry * TradeIdeaFactory.assumedRoundTripCostRate;
    expect(idea.positionSize! * lossPerUnit, closeTo(100, 0.0001));
    expect(idea.estimatedRoundTripCosts, greaterThan(0));
    expect(idea.riskReward, greaterThanOrEqualTo(1.6));
    expect(idea.targets, hasLength(3));
    expect(idea.targets[1], greaterThan(idea.targets[0]));
    expect(idea.targets[2], greaterThan(idea.targets[1]));
    expect(idea.recommendedLeverage, inInclusiveRange(1, 8));
    expect(idea.requiredMargin, lessThanOrEqualTo(10000));
    expect(idea.notionalValue, closeTo(
      idea.requiredMargin! * idea.recommendedLeverage!,
      0.0001,
    ));
    expect(idea.setupId, contains('test-fingerprint-bullish'));
  });

  test('returns wait when the market has no directional structure', () {
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
}

TimeframeChartAnalysis _analysis({required ChartDirection direction}) {
  final candles = List.generate(60, (index) {
    final open = 100 + index * 0.5;
    return ChartCandle(
      openTime: DateTime.utc(2026, 7, 1).add(Duration(hours: index)),
      open: open,
      high: open + 1.2,
      low: open - 1,
      close: open + 0.5,
      volume: 1000 + index.toDouble(),
    );
  });
  final current = candles.last.close;
  return TimeframeChartAnalysis(
    symbol: 'BTCUSDT',
    timeframe: '1h',
    candles: candles,
    zones: [
      ChartPriceZone(
        lower: current - 4.5,
        upper: current - 3.5,
        role: ChartZoneRole.support,
        state: ChartZoneState.active,
        touchCount: 4,
        strength: 0.8,
        distancePercent: 3,
        lastTouchedAt: candles[45].openTime,
        explanation: 'support',
      ),
      ChartPriceZone(
        lower: current + 14,
        upper: current + 16,
        role: ChartZoneRole.resistance,
        state: ChartZoneState.active,
        touchCount: 3,
        strength: 0.72,
        distancePercent: 10,
        lastTouchedAt: candles[48].openTime,
        explanation: 'resistance',
      ),
    ],
    direction: direction,
    directionStrength: direction == ChartDirection.sideways ? 0.1 : 0.8,
    volatilityPercent: 0.8,
    summary: 'test',
    generatedAt: DateTime.utc(2026, 7, 21),
    fingerprint: 'test-fingerprint-${direction.name}',
  );
}
