import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/market_analysis/domain/dow_structure_models.dart';
import 'package:quantara_app/features/market_analysis/domain/market_chart_models.dart';
import 'package:quantara_app/features/owner_alpha/data/trade_idea_factory.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';

void main() {
  test('Champion remains unchanged when Dow rollout is disabled', () {
    final analysis = _trendAnalysis();
    final champion = TradeIdeaFactory.create(
      analysis: analysis,
      capital: 10000,
      riskPercent: 1,
      confluence: const {'4h': ChartDirection.bullish},
      languageCode: 'en',
      strategy: AnalysisStrategy.trendPullback,
      cadence: SignalCadence.active,
    );
    final disabled = TradeIdeaFactory.create(
      analysis: analysis,
      capital: 10000,
      riskPercent: 1,
      confluence: const {'4h': ChartDirection.bullish},
      languageCode: 'en',
      strategy: AnalysisStrategy.trendPullback,
      cadence: SignalCadence.active,
      dowRollout: const DowStructureRollout.disabled(),
    );

    expect(champion.setupId, disabled.setupId);
    expect(champion.direction, disabled.direction);
    expect(champion.evidenceBreakdown, disabled.evidenceBreakdown);
    expect(champion.contextVersion, disabled.contextVersion);
  });

  test('shadow records capped Dow evidence without changing authority', () {
    final analysis = _trendAnalysis();
    final champion = TradeIdeaFactory.create(
      analysis: analysis,
      capital: 10000,
      riskPercent: 1,
      confluence: const {'4h': ChartDirection.bullish},
      languageCode: 'en',
      strategy: AnalysisStrategy.trendPullback,
      cadence: SignalCadence.active,
    );
    expect(champion.isActionable, isTrue);

    final shadow = TradeIdeaFactory.create(
      analysis: analysis,
      capital: 10000,
      riskPercent: 1,
      confluence: const {'4h': ChartDirection.bullish},
      languageCode: 'en',
      strategy: AnalysisStrategy.trendPullback,
      cadence: SignalCadence.active,
      dowRollout: const DowStructureRollout.shadow(),
    );

    expect(shadow.direction, champion.direction);
    expect(shadow.setupId, champion.setupId);
    expect(
      shadow.evidenceBreakdown['dowStructuralAlignment'],
      inInclusiveRange(0, 20),
    );
    expect(shadow.reasons.any((reason) => reason.startsWith('dow:')), isTrue);
  });
}

TimeframeChartAnalysis _trendAnalysis() {
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
      close = open + 0.15 + math.sin(index * 0.5) * 0.03;
      high = close + 0.2;
      low = open - 0.2;
      volume = 1100 + math.sin(index * 0.3) * 80;
    } else if (index < 179) {
      open = price;
      close = open - 0.35;
      high = open + 0.15;
      low = close - 0.2;
      volume = 900;
    } else {
      open = price;
      close = open + 0.45;
      high = close + 0.15;
      low = open - 0.15;
      volume = 1450;
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
  final latest = candles.last;
  return TimeframeChartAnalysis(
    symbol: 'ETHUSDT',
    timeframe: '1h',
    candles: candles,
    zones: [
      ChartPriceZone(
        lower: latest.close - 2.8,
        upper: latest.close - 2.2,
        role: ChartZoneRole.support,
        state: ChartZoneState.active,
        touchCount: 2,
        strength: 0.84,
        distancePercent: 2,
        lastTouchedAt: candles[candles.length - 5].openTime,
        explanation: 'fresh demand range',
      ),
      ChartPriceZone(
        lower: latest.close + 3.5,
        upper: latest.close + 4.2,
        role: ChartZoneRole.resistance,
        state: ChartZoneState.active,
        touchCount: 2,
        strength: 0.78,
        distancePercent: 3,
        lastTouchedAt: candles[candles.length - 20].openTime,
        explanation: 'next supply range',
      ),
    ],
    direction: ChartDirection.bullish,
    directionStrength: 0.78,
    volatilityPercent: 0.8,
    summary: 'contextual trend fixture',
    generatedAt: latest.openTime.add(const Duration(hours: 1)),
    fingerprint: 'dow-factory-trend-fixture',
  );
}
