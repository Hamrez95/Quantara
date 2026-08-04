import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/market_analysis/domain/market_chart_models.dart';
import 'package:quantara_app/features/owner_alpha/data/trade_idea_factory.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';

void main() {
  test('fails closed when required margin exceeds the position cap', () {
    final idea = TradeIdeaFactory.create(
      analysis: _tightTrendAnalysis(),
      capital: 10000,
      riskPercent: 2,
      confluence: const {'4h': ChartDirection.bullish},
      languageCode: 'en',
      strategy: AnalysisStrategy.trendPullback,
      cadence: SignalCadence.active,
    );

    expect(idea.direction, TradeDirection.wait);
    expect(idea.summary, contains('margin'));
    expect(idea.requiredMargin, isNull);
    expect(idea.rejectionReason, SetupRejectionReason.insufficientRiskReward);
  });

  test('range reversal rejects support located above the long entry', () {
    final idea = TradeIdeaFactory.create(
      analysis: _wrongSideRangeAnalysis(),
      capital: 10000,
      riskPercent: 0.5,
      confluence: const {'4h': ChartDirection.sideways},
      languageCode: 'en',
      strategy: AnalysisStrategy.structureZones,
      cadence: SignalCadence.active,
    );

    expect(idea.direction, TradeDirection.wait);
    expect(idea.summary, contains('correct price side'));
    expect(idea.rejectionReason, SetupRejectionReason.insufficientRiskReward);
  });
}

TimeframeChartAnalysis _tightTrendAnalysis() {
  final base = DateTime.utc(2026, 7, 1);
  final candles = <ChartCandle>[];
  var price = 100.0;
  for (var index = 0; index < 80; index++) {
    final open = price;
    final last = index == 79;
    final close = open + (last ? 0.08 : 0.025);
    candles.add(
      ChartCandle(
        openTime: base.add(Duration(hours: index)),
        open: open,
        high: close + (last ? 0.01 : 0.04),
        low: open - (last ? 0.01 : 0.04),
        close: close,
        volume: last ? 1400 : 1000,
      ),
    );
    price = close;
  }
  final closedAt = candles.last.openTime.add(const Duration(hours: 1));
  final current = candles.last.close;
  return TimeframeChartAnalysis(
    symbol: 'BTCUSDT',
    timeframe: '1h',
    candles: candles,
    zones: [
      ChartPriceZone(
        lower: current - 0.09,
        upper: current - 0.05,
        role: ChartZoneRole.support,
        state: ChartZoneState.active,
        touchCount: 3,
        strength: 0.8,
        distancePercent: 0.08,
        lastTouchedAt: candles[candles.length - 2].openTime,
        explanation: 'tight support',
      ),
      ChartPriceZone(
        lower: current + 2,
        upper: current + 2.2,
        role: ChartZoneRole.resistance,
        state: ChartZoneState.active,
        touchCount: 3,
        strength: 0.7,
        distancePercent: 2,
        lastTouchedAt: candles[candles.length - 5].openTime,
        explanation: 'resistance',
      ),
    ],
    direction: ChartDirection.bullish,
    directionStrength: 0.85,
    volatilityPercent: 0.1,
    summary: 'tight trend',
    generatedAt: closedAt,
    fingerprint: 'tight-trend-margin-cap',
  );
}

TimeframeChartAnalysis _wrongSideRangeAnalysis() {
  final base = DateTime.utc(2026, 7, 1);
  final candles = <ChartCandle>[];
  for (var index = 0; index < 79; index++) {
    final center = 100 + math.sin(index * math.pi / 3) * 1.2;
    candles.add(
      ChartCandle(
        openTime: base.add(Duration(hours: index)),
        open: center - 0.15,
        high: center + 0.45,
        low: center - 0.45,
        close: center + 0.15,
        volume: 1000,
      ),
    );
  }
  candles.add(
    ChartCandle(
      openTime: base.add(const Duration(hours: 79)),
      open: 98.7,
      high: 99.6,
      low: 97.2,
      close: 99.35,
      volume: 1100,
    ),
  );
  final closedAt = candles.last.openTime.add(const Duration(hours: 1));
  return TimeframeChartAnalysis(
    symbol: 'BTCUSDT',
    timeframe: '1h',
    candles: candles,
    zones: [
      ChartPriceZone(
        lower: 100.2,
        upper: 101.0,
        role: ChartZoneRole.support,
        state: ChartZoneState.active,
        touchCount: 4,
        strength: 0.86,
        distancePercent: 1,
        lastTouchedAt: candles.last.openTime,
        explanation: 'wrong-side support',
      ),
      ChartPriceZone(
        lower: 102,
        upper: 102.8,
        role: ChartZoneRole.resistance,
        state: ChartZoneState.active,
        touchCount: 4,
        strength: 0.82,
        distancePercent: 3,
        lastTouchedAt: candles[candles.length - 4].openTime,
        explanation: 'resistance',
      ),
    ],
    direction: ChartDirection.sideways,
    directionStrength: 0.12,
    volatilityPercent: 1,
    summary: 'wrong-side range',
    generatedAt: closedAt,
    fingerprint: 'wrong-side-range-boundary',
  );
}
