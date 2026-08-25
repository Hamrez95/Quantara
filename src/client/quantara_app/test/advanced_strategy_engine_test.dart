import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/market_analysis/domain/market_chart_models.dart';
import 'package:quantara_app/features/owner_alpha/data/trade_idea_factory.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';

void main() {
  test('range edge can promote a closed-candle price action reversal', () {
    final candles = <ChartCandle>[];
    final base = DateTime.utc(2026, 1, 1);
    for (var index = 0; index < 119; index++) {
      final center = 100 + math.sin(index * math.pi / 3) * 1.2;
      final open = center - 0.15;
      final close = center + 0.15;
      candles.add(
        ChartCandle(
          openTime: base.add(Duration(hours: index)),
          open: open,
          high: center + 0.45,
          low: center - 0.45,
          close: close,
          volume: 1000,
        ),
      );
    }
    candles.add(
      ChartCandle(
        openTime: base.add(const Duration(hours: 119)),
        open: 98.7,
        high: 99.6,
        low: 97.2,
        close: 99.35,
        volume: 1100,
      ),
    );
    final closedAt = candles.last.openTime.add(const Duration(hours: 1));
    final analysis = TimeframeChartAnalysis(
      symbol: 'BTCUSDT',
      timeframe: '1h',
      candles: candles,
      zones: [
        ChartPriceZone(
          lower: 97.0,
          upper: 97.8,
          role: ChartZoneRole.support,
          state: ChartZoneState.active,
          touchCount: 4,
          strength: 0.86,
          distancePercent: 1.8,
          lastTouchedAt: candles.last.openTime,
          explanation: 'validated support',
        ),
        ChartPriceZone(
          lower: 102.0,
          upper: 102.8,
          role: ChartZoneRole.resistance,
          state: ChartZoneState.active,
          touchCount: 4,
          strength: 0.82,
          distancePercent: 2.8,
          lastTouchedAt: candles[candles.length - 4].openTime,
          explanation: 'validated resistance',
        ),
      ],
      direction: ChartDirection.sideways,
      directionStrength: 0.12,
      volatilityPercent: 1.0,
      summary: 'range support test',
      generatedAt: closedAt,
      fingerprint: 'range-reversal-test',
    );

    final idea = TradeIdeaFactory.create(
      analysis: analysis,
      capital: 10000,
      riskPercent: 1,
      languageCode: 'en',
      strategy: AnalysisStrategy.structureZones,
      cadence: SignalCadence.active,
      confluence: const {'4h': ChartDirection.sideways},
    );

    expect(idea.isActionable, isTrue);
    expect(idea.direction, TradeDirection.long);
    expect(idea.strategyVersion, 'rangeReversal/1.0');
    expect(idea.stopLoss, lessThan(idea.entryLower!));
    expect(idea.targets.first, greaterThan(idea.entryUpper!));
    expect(idea.maximumLoss, closeTo(100, 0.001));
    _expectDecisionIndicatorSnapshot(idea);
  });

  test('trend pullback promotes an aligned no-lookahead setup', () {
    final candles = <ChartCandle>[];
    var price = 100.0;
    final base = DateTime.utc(2026, 2, 1);
    for (var index = 0; index < 180; index++) {
      late final double open;
      late final double close;
      late final double high;
      late final double low;
      late final double volume;
      if (index < 175) {
        open = price;
        close = open + 0.15;
        high = close + 0.2;
        low = open - 0.2;
        volume = 1100;
      } else if (index < 179) {
        open = price;
        close = open - 0.35;
        high = open + 0.15;
        low = close - 0.2;
        volume = 950;
      } else {
        open = price;
        close = open + 0.45;
        high = close + 0.15;
        low = open - 0.15;
        volume = 1350;
      }
      candles.add(
        ChartCandle(
          openTime: base.add(Duration(hours: index)),
          open: open,
          high: high,
          low: low,
          close: close,
          volume: volume,
        ),
      );
      price = close;
    }
    final closedAt = candles.last.openTime.add(const Duration(hours: 1));
    final analysis = TimeframeChartAnalysis(
      symbol: 'ETHUSDT',
      timeframe: '1h',
      candles: candles,
      zones: const [],
      direction: ChartDirection.bullish,
      directionStrength: 0.78,
      volatilityPercent: 0.8,
      summary: 'professional pullback test',
      generatedAt: closedAt,
      fingerprint: 'trend-pullback-test',
    );

    final idea = TradeIdeaFactory.create(
      analysis: analysis,
      capital: 10000,
      riskPercent: 1,
      languageCode: 'en',
      strategy: AnalysisStrategy.trendPullback,
      cadence: SignalCadence.active,
      confluence: const {'4h': ChartDirection.bullish},
    );

    expect(idea.isActionable, isTrue);
    expect(idea.direction, TradeDirection.long);
    expect(idea.strategyVersion, 'trendPullback/1.0');
    expect(idea.stopLoss, lessThan(idea.entryLower!));
    expect(idea.targets, hasLength(3));
    expect(idea.candleClosedAt, closedAt);
    _expectDecisionIndicatorSnapshot(idea);
  });
}

void _expectDecisionIndicatorSnapshot(TradeIdea idea) {
  final strategyIndicators = Map<String, double>.fromEntries(
    idea.indicatorSnapshot.entries.where(
      (entry) => !entry.key.startsWith('journalChart.'),
    ),
  );
  expect(strategyIndicators, hasLength(23));
  expect(
    idea.indicatorSnapshot.keys.any(
      (key) => key.startsWith('journalChart.v1.'),
    ),
    isTrue,
  );
  for (final key in const [
    'ema20',
    'ema50',
    'ema200',
    'ema20SlopeAtr',
    'ema50SlopeAtr',
    'atr14',
    'atrPercent',
    'atrExpansionRatio',
    'rsi14',
    'adx14',
    'plusDi14',
    'minusDi14',
    'relativeVolume20',
    'volumeZScore20',
    'previousDonchianHigh20',
    'previousDonchianLow20',
    'bollingerMiddle20',
    'bollingerUpper20',
    'bollingerLower20',
    'bollingerBandwidthPercent',
    'trendEfficiency20',
    'recentSwingHigh',
    'recentSwingLow',
  ]) {
    final value = strategyIndicators[key];
    expect(value, isNotNull, reason: 'missing $key');
    expect(value!.isFinite, isTrue, reason: '$key must be finite');
  }
}
