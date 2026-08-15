import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/market_analysis/data/contextual_price_action_engine.dart';
import 'package:quantara_app/features/market_analysis/data/technical_indicator_engine.dart';
import 'package:quantara_app/features/market_analysis/domain/contextual_price_action_models.dart';
import 'package:quantara_app/features/market_analysis/domain/market_chart_models.dart';
import 'package:quantara_app/features/owner_alpha/data/professional_strategy_engine.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';

void main() {
  test('v3 produces five independently capped evidence families', () {
    final analysis = _trendAnalysis();
    final assessment = ContextualPriceActionEngine.analyze(analysis: analysis);

    expect(assessment.version, 'contextual-price-action/3.0');
    expect(assessment.families.keys.toSet(), ContextualEvidenceFamily.values.toSet());
    expect(assessment.setupQualityScore, inInclusiveRange(0, 100));
    expect(assessment.expectation, isNotEmpty);
    expect(assessment.trigger, isNotEmpty);
    expect(assessment.invalidation, isNotEmpty);
    for (final family in assessment.families.values) {
      expect(family.cap, 20);
      expect(family.cappedScore, inInclusiveRange(0, 20));
      expect(family.reasons, isNotEmpty);
    }
    expect(
      assessment.families.values.fold<double>(
        0,
        (sum, family) => sum + family.cappedScore,
      ),
      lessThanOrEqualTo(100),
    );
  });

  test('zone evidence preserves ranges and penalizes repeated touches', () {
    final analysis = _trendAnalysis();
    final indicators = TechnicalIndicatorEngine.analyze(analysis.candles);
    final structure = StructureExpectationEngine.analyze(
      analysis: analysis,
      indicators: indicators,
    );
    final zone = ZoneQualityEngine.analyze(
      analysis: analysis,
      indicators: indicators,
      structure: structure,
    );

    expect(zone.zone, isNotNull);
    expect(zone.zone!.upper, greaterThan(zone.zone!.lower));
    expect(zone.freshness, inInclusiveRange(0, 1));
    expect(zone.departureStrength, inInclusiveRange(0, 1));
    expect(zone.touchQuality, inInclusiveRange(0, 1));
    expect(zone.score, inInclusiveRange(0, 100));
  });

  test('failed structural break is explicit and does not require candle color', () {
    final candles = <ChartCandle>[];
    final base = DateTime.utc(2026, 8, 1);
    for (var index = 0; index < 39; index++) {
      final center = 100 + math.sin(index * math.pi / 4) * 1.5;
      candles.add(
        ChartCandle(
          openTime: base.add(Duration(hours: index)),
          open: center - 0.1,
          high: center + 0.6,
          low: center - 0.6,
          close: center + 0.1,
          volume: 1000,
        ),
      );
    }
    candles.add(
      ChartCandle(
        openTime: base.add(const Duration(hours: 39)),
        open: 102,
        high: 106,
        low: 99,
        close: 100,
        volume: 2400,
      ),
    );
    final analysis = TimeframeChartAnalysis(
      symbol: 'BTCUSDT',
      timeframe: '1h',
      candles: candles,
      zones: const [],
      direction: ChartDirection.sideways,
      directionStrength: 0.2,
      volatilityPercent: 1.2,
      summary: 'failed break fixture',
      generatedAt: candles.last.openTime.add(const Duration(hours: 1)),
      fingerprint: 'failed-break-fixture',
    );
    const indicators = TechnicalIndicatorSnapshot(
      ema20: 100,
      ema50: 100,
      ema200: 100,
      ema20SlopeAtr: 0,
      ema50SlopeAtr: 0,
      atr14: 2,
      atrPercent: 2,
      atrExpansionRatio: 1.4,
      rsi14: 50,
      adx14: 18,
      plusDi14: 20,
      minusDi14: 20,
      relativeVolume20: 2.4,
      volumeZScore20: 2,
      previousDonchianHigh20: 104,
      previousDonchianLow20: 96,
      bollingerMiddle20: 100,
      bollingerUpper20: 104,
      bollingerLower20: 96,
      bollingerBandwidthPercent: 8,
      trendEfficiency20: 0.2,
      recentSwingHigh: 104,
      recentSwingLow: 96,
    );

    final structure = StructureExpectationEngine.analyze(
      analysis: analysis,
      indicators: indicators,
    );

    expect(structure.event, StructureEvent.failedBreak);
    expect(structure.expectedMove, ExpectedMarketMove.failedBreakReversal);
  });

  test('ADX and DMI remain bounded inside one momentum family', () {
    final analysis = _trendAnalysis();
    final base = TechnicalIndicatorEngine.analyze(analysis.candles);
    final extreme = TechnicalIndicatorSnapshot(
      ema20: base.ema20,
      ema50: base.ema50,
      ema200: base.ema200,
      ema20SlopeAtr: base.ema20SlopeAtr,
      ema50SlopeAtr: base.ema50SlopeAtr,
      atr14: base.atr14,
      atrPercent: base.atrPercent,
      atrExpansionRatio: 2,
      rsi14: 55,
      adx14: 100,
      plusDi14: 100,
      minusDi14: 0,
      relativeVolume20: base.relativeVolume20,
      volumeZScore20: base.volumeZScore20,
      previousDonchianHigh20: base.previousDonchianHigh20,
      previousDonchianLow20: base.previousDonchianLow20,
      bollingerMiddle20: base.bollingerMiddle20,
      bollingerUpper20: base.bollingerUpper20,
      bollingerLower20: base.bollingerLower20,
      bollingerBandwidthPercent: base.bollingerBandwidthPercent,
      trendEfficiency20: base.trendEfficiency20,
      recentSwingHigh: base.recentSwingHigh,
      recentSwingLow: base.recentSwingLow,
    );
    final assessment = ContextualPriceActionEngine.analyze(
      analysis: analysis,
      indicators: extreme,
    );

    expect(
      assessment.families[ContextualEvidenceFamily.momentum]!.cappedScore,
      lessThanOrEqualTo(20),
    );
    expect(
      assessment.families[ContextualEvidenceFamily.structure]!.cappedScore,
      lessThanOrEqualTo(20),
    );
  });

  test('actionable professional signal carries v3 quality and evidence', () {
    final analysis = _trendAnalysis();
    final idea = ProfessionalStrategyEngine.create(
      analysis: analysis,
      capital: 10000,
      riskPercent: 1,
      confluence: const {'4h': ChartDirection.bullish},
      languageCode: 'en',
      strategy: AnalysisStrategy.trendPullback,
      cadence: SignalCadence.active,
    );

    expect(idea.isActionable, isTrue);
    expect(idea.indicatorSnapshot, hasLength(23));
    expect(idea.contextVersion, 'contextual-price-action/3.0');
    expect(idea.setupQualityScore, inInclusiveRange(0, 100));
    expect(idea.displayQualityScore, idea.setupQualityScore);
    expect(idea.expectation, isNotEmpty);
    expect(idea.trigger, isNotEmpty);
    expect(idea.evidenceBreakdown.keys.toSet(), {
      'structure',
      'zone',
      'candle',
      'volume',
      'momentum',
    });
    expect(idea.evidenceBreakdown.values.every((value) => value <= 20), isTrue);
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
    fingerprint: 'contextual-trend-fixture',
  );
}
