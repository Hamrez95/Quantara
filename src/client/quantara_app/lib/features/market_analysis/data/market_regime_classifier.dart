import '../domain/market_chart_models.dart';
import '../domain/market_regime_models.dart';
import 'technical_indicator_engine.dart';

abstract final class MarketRegimeClassifier {
  static MarketRegimeAssessment classify({
    required TimeframeChartAnalysis analysis,
    required TechnicalIndicatorSnapshot indicators,
  }) {
    final close = analysis.latestCandle.close;
    final bullishBreakout =
        close > indicators.previousDonchianHigh20 &&
        indicators.plusDi14 > indicators.minusDi14;
    final bearishBreakout =
        close < indicators.previousDonchianLow20 &&
        indicators.minusDi14 > indicators.plusDi14;
    final volatilityExpansion = indicators.atrExpansionRatio >= 1.15;
    final volumeExpansion = indicators.relativeVolume20 >= 1.15;

    if ((bullishBreakout || bearishBreakout) &&
        volatilityExpansion &&
        volumeExpansion) {
      final confidence =
          (58 +
                  (indicators.atrExpansionRatio - 1).clamp(0, 1) * 18 +
                  (indicators.relativeVolume20 - 1).clamp(0, 2) * 10 +
                  (indicators.adx14 / 100).clamp(0, 1) * 14)
              .round()
              .clamp(0, 96);
      return MarketRegimeAssessment(
        regime: MarketRegime.breakoutExpansion,
        confidencePercent: confidence,
        reasons: [
          bullishBreakout
              ? 'Price closed above the previous 20-candle channel.'
              : 'Price closed below the previous 20-candle channel.',
          'ATR and relative volume are expanding together.',
        ],
      );
    }

    final bullishTrend =
        indicators.bullishEmaStack &&
        indicators.ema20SlopeAtr > 0.08 &&
        indicators.ema50SlopeAtr > 0.02 &&
        indicators.plusDi14 > indicators.minusDi14;
    final bearishTrend =
        indicators.bearishEmaStack &&
        indicators.ema20SlopeAtr < -0.08 &&
        indicators.ema50SlopeAtr < -0.02 &&
        indicators.minusDi14 > indicators.plusDi14;
    if ((bullishTrend || bearishTrend) &&
        indicators.adx14 >= 20 &&
        indicators.trendEfficiency20 >= 0.28) {
      final confidence =
          (50 +
                  (indicators.adx14 / 50).clamp(0, 1) * 20 +
                  indicators.trendEfficiency20.clamp(0, 1) * 18 +
                  analysis.directionStrength.clamp(0, 1) * 12)
              .round()
              .clamp(0, 94);
      return MarketRegimeAssessment(
        regime: MarketRegime.directionalTrend,
        confidencePercent: confidence,
        reasons: [
          bullishTrend
              ? 'EMA structure, slope and directional movement are bullish.'
              : 'EMA structure, slope and directional movement are bearish.',
          'Trend efficiency and ADX confirm directional persistence.',
        ],
      );
    }

    final flatEma = indicators.ema20SlopeAtr.abs() <= 0.12;
    final lowDirectionality =
        indicators.adx14 < 20 && indicators.trendEfficiency20 < 0.34;
    final containedVolatility = indicators.atrExpansionRatio < 1.2;
    if (flatEma && lowDirectionality && containedVolatility) {
      final confidence =
          (52 +
                  ((20 - indicators.adx14) / 20).clamp(0, 1) * 18 +
                  (1 - indicators.trendEfficiency20).clamp(0, 1) * 18 +
                  (1.2 - indicators.atrExpansionRatio).clamp(0, 0.5) * 20)
              .round()
              .clamp(0, 92);
      return MarketRegimeAssessment(
        regime: MarketRegime.range,
        confidencePercent: confidence,
        reasons: const [
          'EMA slope is flat and ADX is low.',
          'Price path is inefficient, which favours mean-reversion logic.',
        ],
      );
    }

    final conflictingDirection =
        analysis.direction == ChartDirection.sideways ||
        (indicators.plusDi14 - indicators.minusDi14).abs() < 4;
    if (indicators.atrExpansionRatio >= 1.65 && conflictingDirection) {
      return MarketRegimeAssessment(
        regime: MarketRegime.disorder,
        confidencePercent: 80,
        reasons: const [
          'Volatility expanded without a stable directional structure.',
          'The safest system outcome is no trade until structure reforms.',
        ],
      );
    }

    return MarketRegimeAssessment(
      regime: MarketRegime.transition,
      confidencePercent: 55,
      reasons: const [
        'The market is transitioning between clear trend, range and breakout states.',
      ],
    );
  }
}
