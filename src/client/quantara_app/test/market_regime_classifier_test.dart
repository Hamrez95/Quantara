import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/market_analysis/data/market_regime_classifier.dart';
import 'package:quantara_app/features/market_analysis/data/technical_indicator_engine.dart';
import 'package:quantara_app/features/market_analysis/domain/market_chart_models.dart';
import 'package:quantara_app/features/market_analysis/domain/market_regime_models.dart';

void main() {
  test('classifies confirmed channel expansion as breakout', () {
    final analysis = _analysis(close: 112, direction: ChartDirection.bullish);
    final result = MarketRegimeClassifier.classify(
      analysis: analysis,
      indicators: _snapshot(
        previousDonchianHigh20: 110,
        previousDonchianLow20: 95,
        atrExpansionRatio: 1.35,
        relativeVolume20: 1.8,
        plusDi14: 32,
        minusDi14: 14,
        adx14: 29,
      ),
    );

    expect(result.regime, MarketRegime.breakoutExpansion);
    expect(result.confidencePercent, greaterThanOrEqualTo(60));
  });

  test('classifies low ADX and inefficient price path as range', () {
    final analysis = _analysis(close: 100, direction: ChartDirection.sideways);
    final result = MarketRegimeClassifier.classify(
      analysis: analysis,
      indicators: _snapshot(
        ema20SlopeAtr: 0.02,
        ema50SlopeAtr: 0.01,
        adx14: 13,
        trendEfficiency20: 0.18,
        atrExpansionRatio: 0.95,
      ),
    );

    expect(result.regime, MarketRegime.range);
  });
}

TimeframeChartAnalysis _analysis({
  required double close,
  required ChartDirection direction,
}) {
  final candles = <ChartCandle>[];
  for (var index = 0; index < 60; index++) {
    candles.add(
      ChartCandle(
        openTime: DateTime.utc(2026, 1, 1).add(Duration(hours: index)),
        open: close,
        high: close + 1,
        low: close - 1,
        close: close,
        volume: 1000,
      ),
    );
  }
  return TimeframeChartAnalysis(
    symbol: 'BTCUSDT',
    timeframe: '1h',
    candles: candles,
    zones: const [],
    direction: direction,
    directionStrength: direction == ChartDirection.sideways ? 0.1 : 0.75,
    volatilityPercent: 1,
    summary: 'test',
    generatedAt: DateTime.utc(2026, 1, 4),
    fingerprint: 'regime-test-$close-${direction.name}',
  );
}

TechnicalIndicatorSnapshot _snapshot({
  double ema20SlopeAtr = 0.3,
  double ema50SlopeAtr = 0.15,
  double atrExpansionRatio = 1,
  double relativeVolume20 = 1,
  double adx14 = 25,
  double plusDi14 = 25,
  double minusDi14 = 15,
  double trendEfficiency20 = 0.5,
  double previousDonchianHigh20 = 120,
  double previousDonchianLow20 = 80,
}) {
  return TechnicalIndicatorSnapshot(
    ema20: 105,
    ema50: 100,
    ema200: 95,
    ema20SlopeAtr: ema20SlopeAtr,
    ema50SlopeAtr: ema50SlopeAtr,
    atr14: 2,
    atrPercent: 2,
    atrExpansionRatio: atrExpansionRatio,
    rsi14: 55,
    adx14: adx14,
    plusDi14: plusDi14,
    minusDi14: minusDi14,
    relativeVolume20: relativeVolume20,
    volumeZScore20: 1,
    previousDonchianHigh20: previousDonchianHigh20,
    previousDonchianLow20: previousDonchianLow20,
    bollingerMiddle20: 100,
    bollingerUpper20: 105,
    bollingerLower20: 95,
    bollingerBandwidthPercent: 10,
    trendEfficiency20: trendEfficiency20,
    recentSwingHigh: 106,
    recentSwingLow: 94,
  );
}
