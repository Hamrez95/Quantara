import 'dart:math' as math;

import '../../market_analysis/data/ichimoku_indicator_engine.dart';
import '../../market_analysis/data/market_regime_classifier.dart';
import '../../market_analysis/data/technical_indicator_engine.dart';
import '../../market_analysis/domain/market_chart_models.dart';
import '../../market_analysis/domain/market_regime_models.dart';
import '../domain/owner_alpha_models.dart';

abstract final class AdvancedStrategyEngine {
  static const _roundTripCostRate = 0.002;
  static const _targetMarginFraction = 0.20;

  static TradeIdea? tryCreate({
    required TimeframeChartAnalysis analysis,
    required double capital,
    required double riskPercent,
    required String languageCode,
    required AnalysisStrategy strategy,
    required SignalCadence cadence,
    required Map<String, ChartDirection> confluence,
  }) {
    if (analysis.candles.length < 60) {
      return null;
    }
    final indicators = TechnicalIndicatorEngine.analyze(analysis.candles);
    final regime = MarketRegimeClassifier.classify(
      analysis: analysis,
      indicators: indicators,
    );
    return switch (strategy) {
      AnalysisStrategy.structureZones => _bestIdea([
        _rangeMeanReversion(
          analysis: analysis,
          indicators: indicators,
          regime: regime,
          capital: capital,
          riskPercent: riskPercent,
          languageCode: languageCode,
          cadence: cadence,
        ),
        _priceActionReversal(
          analysis: analysis,
          indicators: indicators,
          regime: regime,
          capital: capital,
          riskPercent: riskPercent,
          languageCode: languageCode,
          cadence: cadence,
        ),
      ]),
      AnalysisStrategy.trendPullback => _ichimokuTrend(
        analysis: analysis,
        indicators: indicators,
        regime: regime,
        capital: capital,
        riskPercent: riskPercent,
        languageCode: languageCode,
        cadence: cadence,
        confluence: confluence,
      ),
      AnalysisStrategy.momentumContinuation => null,
    };
  }

  static TradeIdea? _rangeMeanReversion({
    required TimeframeChartAnalysis analysis,
    required TechnicalIndicatorSnapshot indicators,
    required MarketRegimeAssessment regime,
    required double capital,
    required double riskPercent,
    required String languageCode,
    required SignalCadence cadence,
  }) {
    if (regime.regime != MarketRegime.range) {
      return null;
    }
    final candle = analysis.latestCandle;
    final candleRange = math.max(
      candle.high - candle.low,
      indicators.atr14 * 0.05,
    );
    final body = math.max(
      (candle.close - candle.open).abs(),
      candleRange * 0.02,
    );
    final lowerWick = math.min(candle.open, candle.close) - candle.low;
    final upperWick = candle.high - math.max(candle.open, candle.close);
    final closeLocation = (candle.close - candle.low) / candleRange;
    final bandTolerance = indicators.atr14 * 0.35;
    final long =
        candle.close <= indicators.bollingerLower20 + bandTolerance &&
        indicators.rsi14 <= 42 &&
        (candle.isBullish || lowerWick >= body * 1.25 && closeLocation >= 0.55);
    final short =
        candle.close >= indicators.bollingerUpper20 - bandTolerance &&
        indicators.rsi14 >= 58 &&
        (!candle.isBullish ||
            upperWick >= body * 1.25 && closeLocation <= 0.45);
    if (!long && !short) {
      return null;
    }
    final rsiContribution =
        ((long ? 50 - indicators.rsi14 : indicators.rsi14 - 50) * 0.7)
            .round()
            .clamp(0, 15)
            .toInt();
    final adxContribution = ((22 - indicators.adx14) * 0.6)
        .round()
        .clamp(0, 10)
        .toInt();
    final efficiencyContribution = ((0.42 - indicators.trendEfficiency20) * 30)
        .round()
        .clamp(0, 10)
        .toInt();
    final score =
        55 +
        rsiContribution +
        adxContribution +
        efficiencyContribution +
        (indicators.relativeVolume20 <= 1.8 ? 5 : 0);
    if (score < _threshold(cadence, 76, 66, 56)) {
      return null;
    }
    final stop = long
        ? math.min(candle.low, indicators.bollingerLower20) -
              indicators.atr14 * 0.45
        : math.max(candle.high, indicators.bollingerUpper20) +
              indicators.atr14 * 0.45;
    final fa = languageCode != 'en';
    return _buildIdea(
      analysis: analysis,
      capital: capital,
      riskPercent: riskPercent,
      strategy: AnalysisStrategy.structureZones,
      long: long,
      entryCenter: candle.close,
      stop: stop,
      atr: indicators.atr14,
      targetMultiples: const [1.25, 1.8, 2.4],
      score: score,
      version: 'adaptive-range/2.1',
      summary: fa
          ? 'بازگشت به میانگین در بازار رنج با بولینگر، RSI و کندل برگشتی تأیید شد.'
          : 'A range mean-reversion setup was confirmed by Bollinger position, RSI and a reversal candle.',
      invalidation: fa
          ? 'شکست معتبر بیرون باند و عبور از حد ATR سناریوی بازگشت را باطل می‌کند.'
          : 'A confirmed extension beyond the band and ATR stop invalidates the setup.',
      reasons: fa
          ? [
              'رژیم رنج با اطمینان ${regime.confidencePercent}٪ تشخیص داده شد.',
              'RSI ${indicators.rsi14.toStringAsFixed(1)} و ADX ${indicators.adx14.toStringAsFixed(1)} است.',
              'امتیاز استراتژی $score از ۱۰۰ است.',
            ]
          : [
              'The range regime confidence is ${regime.confidencePercent}%.',
              'RSI is ${indicators.rsi14.toStringAsFixed(1)} and ADX is ${indicators.adx14.toStringAsFixed(1)}.',
              'The strategy score is $score out of 100.',
            ],
    );
  }

  static TradeIdea? _priceActionReversal({
    required TimeframeChartAnalysis analysis,
    required TechnicalIndicatorSnapshot indicators,
    required MarketRegimeAssessment regime,
    required double capital,
    required double riskPercent,
    required String languageCode,
    required SignalCadence cadence,
  }) {
    if (analysis.candles.length < 2 ||
        regime.regime != MarketRegime.range &&
            regime.regime != MarketRegime.transition) {
      return null;
    }
    final candle = analysis.latestCandle;
    final previous = analysis.candles[analysis.candles.length - 2];
    final support = _nearestZone(
      analysis.zones,
      ChartZoneRole.support,
      candle.close,
      indicators.atr14 * 1.25,
    );
    final resistance = _nearestZone(
      analysis.zones,
      ChartZoneRole.resistance,
      candle.close,
      indicators.atr14 * 1.25,
    );
    final body = math.max((candle.close - candle.open).abs(), 0.0000001);
    final candleRange = math.max(candle.high - candle.low, body);
    final lowerWick = math.min(candle.open, candle.close) - candle.low;
    final upperWick = candle.high - math.max(candle.open, candle.close);
    final closeLocation = (candle.close - candle.low) / candleRange;
    final bullishEngulfing =
        candle.isBullish &&
        !previous.isBullish &&
        candle.open <= previous.close &&
        candle.close >= previous.open;
    final bearishEngulfing =
        !candle.isBullish &&
        previous.isBullish &&
        candle.open >= previous.close &&
        candle.close <= previous.open;
    final bullishPin = lowerWick >= body * 1.5 && closeLocation >= 0.62;
    final bearishPin = upperWick >= body * 1.5 && closeLocation <= 0.38;
    final bullishSweep =
        support != null &&
        candle.low < support.lower &&
        candle.close > support.upper;
    final bearishSweep =
        resistance != null &&
        candle.high > resistance.upper &&
        candle.close < resistance.lower;
    final long =
        support != null && (bullishSweep || bullishEngulfing || bullishPin);
    final short =
        resistance != null && (bearishSweep || bearishEngulfing || bearishPin);
    if (!long && !short) {
      return null;
    }
    final selectedLong =
        long && (!short || support!.strength >= resistance!.strength);
    final zone = selectedLong ? support! : resistance!;
    final sweep = selectedLong ? bullishSweep : bearishSweep;
    final engulfing = selectedLong ? bullishEngulfing : bearishEngulfing;
    final pin = selectedLong ? bullishPin : bearishPin;
    final score =
        25 +
        (zone.strength * 15).round() +
        math.min(10, zone.touchCount * 2) +
        (engulfing || pin ? 18 : 0) +
        (sweep ? 15 : 0) +
        (indicators.relativeVolume20 >= 0.9 ? 8 : 0) +
        ((selectedLong && indicators.rsi14 <= 50) ||
                (!selectedLong && indicators.rsi14 >= 50)
            ? 9
            : 0);
    if (score < _threshold(cadence, 74, 64, 54)) {
      return null;
    }
    final stop = selectedLong
        ? math.min(candle.low, zone.lower) - indicators.atr14 * 0.35
        : math.max(candle.high, zone.upper) + indicators.atr14 * 0.35;
    final fa = languageCode != 'en';
    return _buildIdea(
      analysis: analysis,
      capital: capital,
      riskPercent: riskPercent,
      strategy: AnalysisStrategy.structureZones,
      long: selectedLong,
      entryCenter: candle.close,
      stop: stop,
      atr: indicators.atr14,
      targetMultiples: const [1.4, 2.2, 3.0],
      score: score,
      version: 'adaptive-price-action/2.1',
      summary: fa
          ? 'برگشت پرایس‌اکشن روی ناحیه معتبر با کندل بسته‌شده شناسایی شد.'
          : 'A price-action reversal at a validated zone was confirmed on a closed candle.',
      invalidation: fa
          ? 'بسته‌شدن معتبر پشت ناحیه و حد ATR سناریوی برگشت را باطل می‌کند.'
          : 'A confirmed close beyond the zone and ATR stop invalidates the reversal.',
      reasons: fa
          ? [
              'ناحیه ${zone.touchCount} واکنش و قدرت ${(zone.strength * 100).round()}٪ دارد.',
              if (sweep) 'شکار نقدینگی و بازگشت داخل ناحیه ثبت شد.',
              if (engulfing) 'کندل پوشای تأییدی ثبت شد.',
              if (pin) 'رد قیمت با سایه بلند ثبت شد.',
              'امتیاز استراتژی $score از ۱۰۰ است.',
            ]
          : [
              'The zone has ${zone.touchCount} reactions and ${(zone.strength * 100).round()}% strength.',
              if (sweep) 'A liquidity sweep returned inside the zone.',
              if (engulfing) 'A confirming engulfing candle was detected.',
              if (pin) 'A long-wick rejection candle was detected.',
              'The strategy score is $score out of 100.',
            ],
    );
  }

  static TradeIdea? _ichimokuTrend({
    required TimeframeChartAnalysis analysis,
    required TechnicalIndicatorSnapshot indicators,
    required MarketRegimeAssessment regime,
    required double capital,
    required double riskPercent,
    required String languageCode,
    required SignalCadence cadence,
    required Map<String, ChartDirection> confluence,
  }) {
    if (analysis.candles.length < 80 ||
        regime.regime != MarketRegime.directionalTrend &&
            regime.regime != MarketRegime.transition) {
      return null;
    }
    final ichimoku = IchimokuIndicatorEngine.analyze(analysis.candles);
    final candle = analysis.latestCandle;
    final previous = analysis.candles[analysis.candles.length - 2];
    final long =
        candle.close > ichimoku.cloudTop &&
        ichimoku.tenkan9 > ichimoku.kijun26 &&
        ichimoku.bullishCloud &&
        candle.close > ichimoku.chikouReferenceHigh;
    final short =
        candle.close < ichimoku.cloudBottom &&
        ichimoku.tenkan9 < ichimoku.kijun26 &&
        ichimoku.bearishCloud &&
        candle.close < ichimoku.chikouReferenceLow;
    if (!long && !short) {
      return null;
    }
    final pullback =
        (candle.close - ichimoku.kijun26).abs() <= indicators.atr14 * 1.1 ||
        long &&
            candle.low <= ichimoku.tenkan9 &&
            candle.close > ichimoku.tenkan9 ||
        short &&
            candle.high >= ichimoku.tenkan9 &&
            candle.close < ichimoku.tenkan9;
    final cloudBreak =
        long && previous.close <= ichimoku.cloudTop ||
        short && previous.close >= ichimoku.cloudBottom;
    final candleTrigger = long ? candle.isBullish : !candle.isBullish;
    final aligned = confluence.values
        .where(
          (direction) =>
              long && direction == ChartDirection.bullish ||
              short && direction == ChartDirection.bearish,
        )
        .length;
    final score =
        58 +
        (indicators.adx14 / 35 * 14).round().clamp(0, 14).toInt() +
        (pullback || cloudBreak ? 14 : 0) +
        (candleTrigger ? 7 : 0) +
        math.min(7, aligned * 2);
    if ((!pullback && !cloudBreak) ||
        !candleTrigger ||
        score < _threshold(cadence, 82, 72, 62)) {
      return null;
    }
    final stop = long
        ? math.min(
                math.min(ichimoku.kijun26, ichimoku.cloudBottom),
                indicators.recentSwingLow,
              ) -
              indicators.atr14 * 0.35
        : math.max(
                math.max(ichimoku.kijun26, ichimoku.cloudTop),
                indicators.recentSwingHigh,
              ) +
              indicators.atr14 * 0.35;
    final fa = languageCode != 'en';
    return _buildIdea(
      analysis: analysis,
      capital: capital,
      riskPercent: riskPercent,
      strategy: AnalysisStrategy.trendPullback,
      long: long,
      entryCenter: candle.close,
      stop: stop,
      atr: indicators.atr14,
      targetMultiples: const [1.6, 2.5, 3.5],
      score: score,
      version: 'ichimoku-trend/2.1',
      summary: fa
          ? 'روند ایچیموکو با ابر، تنکان/کیجون، چیکو و کندل بسته‌شده تأیید شد.'
          : 'An Ichimoku trend was confirmed by the cloud, Tenkan/Kijun, Chikou and a closed candle.',
      invalidation: fa
          ? 'بازگشت معتبر پشت کیجون، ابر و حد ATR سناریوی روند را باطل می‌کند.'
          : 'A confirmed return beyond Kijun, the cloud and ATR stop invalidates the setup.',
      reasons: fa
          ? [
              'ابر فعلی بدون استفاده از داده آینده محاسبه شده است.',
              'ADX ${indicators.adx14.toStringAsFixed(1)} و هم‌جهتی $aligned تایم‌فریم است.',
              'امتیاز استراتژی $score از ۱۰۰ است.',
            ]
          : [
              'The cloud was calculated without future-data leakage.',
              'ADX is ${indicators.adx14.toStringAsFixed(1)} with $aligned aligned timeframes.',
              'The strategy score is $score out of 100.',
            ],
    );
  }

  static ChartPriceZone? _nearestZone(
    Iterable<ChartPriceZone> zones,
    ChartZoneRole role,
    double price,
    double maximumDistance,
  ) {
    final candidates = zones
        .where((zone) => zone.role == role)
        .where((zone) => (zone.center - price).abs() <= maximumDistance)
        .toList(growable: false);
    candidates.sort(
      (left, right) =>
          (left.center - price).abs().compareTo((right.center - price).abs()),
    );
    return candidates.isEmpty ? null : candidates.first;
  }

  static TradeIdea? _bestIdea(Iterable<TradeIdea?> ideas) {
    final candidates = ideas.whereType<TradeIdea>().toList(growable: false);
    if (candidates.isEmpty) {
      return null;
    }
    candidates.sort(
      (left, right) =>
          right.confidencePercent.compareTo(left.confidencePercent),
    );
    return candidates.first;
  }

  static int _threshold(
    SignalCadence cadence,
    int conservative,
    int balanced,
    int active,
  ) {
    return switch (cadence) {
      SignalCadence.conservative => conservative,
      SignalCadence.balanced => balanced,
      SignalCadence.active => active,
    };
  }

  static TradeIdea? _buildIdea({
    required TimeframeChartAnalysis analysis,
    required double capital,
    required double riskPercent,
    required AnalysisStrategy strategy,
    required bool long,
    required double entryCenter,
    required double stop,
    required double atr,
    required List<double> targetMultiples,
    required int score,
    required String version,
    required String summary,
    required String invalidation,
    required List<String> reasons,
  }) {
    final entryHalfWidth = math.max(atr * 0.05, entryCenter * 0.0002);
    final entryLower = entryCenter - entryHalfWidth;
    final entryUpper = entryCenter + entryHalfWidth;
    final conservativeEntry = long ? entryUpper : entryLower;
    if (!stop.isFinite ||
        stop <= 0 ||
        long && stop >= conservativeEntry ||
        !long && stop <= conservativeEntry) {
      return null;
    }
    final estimatedCostPerUnit = conservativeEntry * _roundTripCostRate;
    final stopDistance = (conservativeEntry - stop).abs();
    final riskPerUnit = stopDistance + estimatedCostPerUnit;
    final maximumLoss = capital * riskPercent / 100;
    if (riskPerUnit <= 0 || !riskPerUnit.isFinite || maximumLoss <= 0) {
      return null;
    }
    final riskSizedUnits = maximumLoss / riskPerUnit;
    final riskSizedNotional = riskSizedUnits * conservativeEntry;
    final volatilityRate = analysis.volatilityPercent / 100;
    final stopDistancePercent = stopDistance / conservativeEntry;
    final liquidationCap =
        (0.45 / math.max(0.005, stopDistancePercent + volatilityRate * 0.75))
            .floor()
            .clamp(1, 10)
            .toInt();
    final confidenceCap = score >= 84
        ? 8
        : score >= 74
        ? 6
        : score >= 64
        ? 4
        : 3;
    final safeLeverage = math.min(liquidationCap, confidenceCap).toInt();
    final targetMargin = capital * _targetMarginFraction;
    final fundingLeverage = (riskSizedNotional / targetMargin)
        .ceil()
        .clamp(1, 100)
        .toInt();
    final recommendedLeverage = math.min(safeLeverage, fundingLeverage).toInt();
    final fundedUnits = targetMargin * recommendedLeverage / conservativeEntry;
    final positionSize = math.min(riskSizedUnits, fundedUnits);
    if (!positionSize.isFinite || positionSize <= 0) {
      return null;
    }
    final notionalValue = positionSize * conservativeEntry;
    final targets = [
      for (final multiple in targetMultiples)
        long
            ? conservativeEntry + riskPerUnit * multiple
            : conservativeEntry - riskPerUnit * multiple,
    ];
    if (targets.any((target) => target <= 0 || !target.isFinite)) {
      return null;
    }
    return TradeIdea(
      symbol: analysis.symbol,
      timeframe: analysis.timeframe,
      direction: long ? TradeDirection.long : TradeDirection.short,
      confidencePercent: score.clamp(0, 94).toInt(),
      entryLower: entryLower,
      entryUpper: entryUpper,
      stopLoss: stop,
      targets: List.unmodifiable(targets),
      riskReward: targetMultiples.first,
      maximumLoss: maximumLoss,
      positionSize: positionSize,
      notionalValue: notionalValue,
      recommendedLeverage: recommendedLeverage,
      maximumSafeLeverage: safeLeverage,
      requiredMargin: notionalValue / recommendedLeverage,
      estimatedRoundTripCosts: positionSize * estimatedCostPerUnit,
      setupId:
          '${analysis.symbol}|${analysis.timeframe}|$version|${long ? 'long' : 'short'}|${analysis.fingerprint}',
      candleClosedAt: analysis.latestCandle.openTime.add(
        _durationFor(analysis.timeframe),
      ),
      summary: summary,
      invalidation: invalidation,
      reasons: List.unmodifiable(reasons),
      strategy: strategy,
      strategyVersion: version,
    );
  }

  static Duration _durationFor(String timeframe) => switch (timeframe) {
    '15m' => const Duration(minutes: 15),
    '1h' => const Duration(hours: 1),
    '4h' => const Duration(hours: 4),
    '1D' => const Duration(days: 1),
    _ => Duration.zero,
  };
}
