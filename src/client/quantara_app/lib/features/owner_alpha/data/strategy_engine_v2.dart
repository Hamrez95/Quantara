import 'dart:math' as math;

import '../../market_analysis/data/market_regime_classifier.dart';
import '../../market_analysis/data/technical_indicator_engine.dart';
import '../../market_analysis/domain/market_chart_models.dart';
import '../../market_analysis/domain/market_regime_models.dart';
import '../domain/owner_alpha_models.dart';

abstract final class StrategyEngineV2 {
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
    if (strategy == AnalysisStrategy.structureZones) {
      return null;
    }
    final indicators = TechnicalIndicatorEngine.analyze(analysis.candles);
    final regime = MarketRegimeClassifier.classify(
      analysis: analysis,
      indicators: indicators,
    );
    return switch (strategy) {
      AnalysisStrategy.trendPullback => _trendPullback(
        analysis: analysis,
        indicators: indicators,
        regime: regime,
        capital: capital,
        riskPercent: riskPercent,
        languageCode: languageCode,
        cadence: cadence,
        confluence: confluence,
      ),
      AnalysisStrategy.momentumContinuation => _donchianBreakout(
        analysis: analysis,
        indicators: indicators,
        regime: regime,
        capital: capital,
        riskPercent: riskPercent,
        languageCode: languageCode,
        cadence: cadence,
        confluence: confluence,
      ),
      AnalysisStrategy.structureZones => null,
    };
  }

  static TradeIdea _trendPullback({
    required TimeframeChartAnalysis analysis,
    required TechnicalIndicatorSnapshot indicators,
    required MarketRegimeAssessment regime,
    required double capital,
    required double riskPercent,
    required String languageCode,
    required SignalCadence cadence,
    required Map<String, ChartDirection> confluence,
  }) {
    final fa = languageCode != 'en';
    final candle = analysis.latestCandle;
    final long =
        indicators.ema20 > indicators.ema50 &&
        indicators.plusDi14 > indicators.minusDi14;
    final short =
        indicators.ema20 < indicators.ema50 &&
        indicators.minusDi14 > indicators.plusDi14;
    final directional = long || short;
    final nearestTrendAverage = math.min(
      (candle.close - indicators.ema20).abs(),
      (candle.close - indicators.ema50).abs(),
    );
    final pullbackNearValue = nearestTrendAverage <= indicators.atr14 * 0.85;
    final rsiReset = long
        ? indicators.rsi14 >= 42 && indicators.rsi14 <= 68
        : short
        ? indicators.rsi14 >= 32 && indicators.rsi14 <= 58
        : false;
    final candleTrigger = long ? candle.isBullish : !candle.isBullish;
    final regimeAllowed =
        regime.regime == MarketRegime.directionalTrend ||
        (regime.regime == MarketRegime.transition && indicators.adx14 >= 18);
    final alignedTimeframes = confluence.values
        .where(
          (direction) =>
              (long && direction == ChartDirection.bullish) ||
              (short && direction == ChartDirection.bearish),
        )
        .length;

    final scoreParts = <String, int>{
      'regime': regimeAllowed ? 18 : 0,
      'trend': directional ? 18 : 0,
      'adx': (indicators.adx14 / 35 * 14).round().clamp(0, 14).toInt(),
      'pullback': pullbackNearValue ? 20 : 0,
      'rsiReset': rsiReset ? 10 : 0,
      'priceAction': candleTrigger ? 10 : 0,
      'volume': indicators.relativeVolume20 >= 0.75 ? 5 : 0,
      'multiTimeframe': math.min(5, alignedTimeframes * 2).toInt(),
    };
    final score = scoreParts.values.fold<int>(0, (sum, value) => sum + value);
    final threshold = _scoreThreshold(
      cadence,
      conservative: 76,
      balanced: 66,
      active: 56,
    );

    if (!regimeAllowed || !directional || score < threshold) {
      return _wait(
        analysis: analysis,
        strategy: AnalysisStrategy.trendPullback,
        confidencePercent: score.clamp(0, 92).toInt(),
        maximumLoss: capital * riskPercent / 100,
        rejectionReason: SetupRejectionReason.weakDirection,
        summary: fa
            ? 'پولبک روند در حال شکل‌گیری است، اما امتیاز تأیید هنوز برای ورود کافی نیست.'
            : 'A trend pullback is forming, but its confirmation score is not high enough yet.',
        invalidation: fa
            ? 'پس از نزدیک‌شدن قیمت به میانگین روند و تشکیل کندل تأییدی دوباره بررسی شود.'
            : 'Review after price retests the trend averages and closes with confirmation.',
        reasons: fa
            ? [
                'امتیاز فعلی $score از حد لازم $threshold کمتر است.',
                'ADX ${indicators.adx14.toStringAsFixed(1)} و RSI ${indicators.rsi14.toStringAsFixed(1)} است.',
              ]
            : [
                'The current score is $score versus the required $threshold.',
                'ADX is ${indicators.adx14.toStringAsFixed(1)} and RSI is ${indicators.rsi14.toStringAsFixed(1)}.',
              ],
      );
    }

    final entryHalfWidth = indicators.atr14 * 0.06;
    final entryLower = candle.close - entryHalfWidth;
    final entryUpper = candle.close + entryHalfWidth;
    final conservativeEntry = long ? entryUpper : entryLower;
    final atrStop = long
        ? conservativeEntry - indicators.atr14 * 1.25
        : conservativeEntry + indicators.atr14 * 1.25;
    final structuralStop = long
        ? indicators.recentSwingLow
        : indicators.recentSwingHigh;
    final stop = long
        ? math.min(atrStop, structuralStop)
        : math.max(atrStop, structuralStop);

    return _buildIdea(
      analysis: analysis,
      strategy: AnalysisStrategy.trendPullback,
      capital: capital,
      riskPercent: riskPercent,
      long: long,
      entryLower: entryLower,
      entryUpper: entryUpper,
      stop: stop,
      targetMultiples: const [1.6, 2.4, 3.2],
      score: score,
      summary: fa
          ? 'پولبک هم‌جهت روند با تأیید EMA، ADX، RSI و کندل بسته‌شده شناسایی شد.'
          : 'A trend-aligned pullback was confirmed by EMA structure, ADX, RSI and the closed candle.',
      invalidation: fa
          ? 'بسته‌شدن معتبر پشت کف یا سقف نوسانی و حد ATR سناریو را باطل می‌کند.'
          : 'A confirmed close beyond the swing and ATR stop invalidates the setup.',
      reasons: fa
          ? [
              'امتیاز استراتژی $score از ۱۰۰ است.',
              'رژیم بازار ${regime.regime.name} با اطمینان ${regime.confidencePercent}٪ تشخیص داده شد.',
              'حجم نسبی ${indicators.relativeVolume20.toStringAsFixed(2)} و ATR ${indicators.atrPercent.toStringAsFixed(2)}٪ است.',
            ]
          : [
              'The strategy score is $score out of 100.',
              'The regime is ${regime.regime.name} with ${regime.confidencePercent}% confidence.',
              'Relative volume is ${indicators.relativeVolume20.toStringAsFixed(2)} and ATR is ${indicators.atrPercent.toStringAsFixed(2)}%.',
            ],
      version: '2.0-trend-pullback',
    );
  }

  static TradeIdea _donchianBreakout({
    required TimeframeChartAnalysis analysis,
    required TechnicalIndicatorSnapshot indicators,
    required MarketRegimeAssessment regime,
    required double capital,
    required double riskPercent,
    required String languageCode,
    required SignalCadence cadence,
    required Map<String, ChartDirection> confluence,
  }) {
    final fa = languageCode != 'en';
    final candle = analysis.latestCandle;
    final long = candle.close > indicators.previousDonchianHigh20;
    final short = candle.close < indicators.previousDonchianLow20;
    final breakout = long || short;
    final directionConfirmed = long
        ? indicators.plusDi14 > indicators.minusDi14
        : short
        ? indicators.minusDi14 > indicators.plusDi14
        : false;
    final alignedTimeframes = confluence.values
        .where(
          (direction) =>
              (long && direction == ChartDirection.bullish) ||
              (short && direction == ChartDirection.bearish),
        )
        .length;
    final expansionDistance = long
        ? candle.close - indicators.previousDonchianHigh20
        : short
        ? indicators.previousDonchianLow20 - candle.close
        : 0.0;
    final normalizedExpansion = indicators.atr14 <= 0
        ? 0.0
        : expansionDistance / indicators.atr14;

    final scoreParts = <String, int>{
      'channelBreak': breakout ? 25 : 0,
      'directionalMovement': directionConfirmed ? 14 : 0,
      'atrExpansion': ((indicators.atrExpansionRatio - 0.9) * 20)
          .round()
          .clamp(0, 16)
          .toInt(),
      'relativeVolume': ((indicators.relativeVolume20 - 0.7) * 12)
          .round()
          .clamp(0, 16)
          .toInt(),
      'breakDistance': (normalizedExpansion * 18).round().clamp(0, 14).toInt(),
      'adx': (indicators.adx14 / 35 * 10).round().clamp(0, 10).toInt(),
      'multiTimeframe': math.min(5, alignedTimeframes * 2).toInt(),
    };
    final score = scoreParts.values.fold<int>(0, (sum, value) => sum + value);
    final threshold = _scoreThreshold(
      cadence,
      conservative: 78,
      balanced: 68,
      active: 58,
    );
    final regimeAllowed =
        regime.regime == MarketRegime.breakoutExpansion ||
        (regime.regime == MarketRegime.directionalTrend &&
            indicators.atrExpansionRatio >= 1.05);

    if (!breakout ||
        !directionConfirmed ||
        !regimeAllowed ||
        score < threshold) {
      return _wait(
        analysis: analysis,
        strategy: AnalysisStrategy.momentumContinuation,
        confidencePercent: score.clamp(0, 92).toInt(),
        maximumLoss: capital * riskPercent / 100,
        rejectionReason: SetupRejectionReason.weakDirection,
        summary: fa
            ? 'شکست کانال هنوز از نظر حجم، ATR و حرکت جهت‌دار تأیید کافی ندارد.'
            : 'The channel breakout is not sufficiently confirmed by volume, ATR and directional movement.',
        invalidation: fa
            ? 'پس از بسته‌شدن بیرون کانال ۲۰ کندلی با افزایش حجم و نوسان دوباره بررسی شود.'
            : 'Review after a close outside the prior 20-candle channel with volume and volatility expansion.',
        reasons: fa
            ? [
                'امتیاز فعلی $score از حد لازم $threshold کمتر است.',
                'حجم نسبی ${indicators.relativeVolume20.toStringAsFixed(2)} و انبساط ATR برابر ${indicators.atrExpansionRatio.toStringAsFixed(2)} است.',
              ]
            : [
                'The current score is $score versus the required $threshold.',
                'Relative volume is ${indicators.relativeVolume20.toStringAsFixed(2)} and ATR expansion is ${indicators.atrExpansionRatio.toStringAsFixed(2)}.',
              ],
      );
    }

    final entryHalfWidth = indicators.atr14 * 0.05;
    final entryLower = candle.close - entryHalfWidth;
    final entryUpper = candle.close + entryHalfWidth;
    final conservativeEntry = long ? entryUpper : entryLower;
    final channelStop = long
        ? indicators.previousDonchianHigh20 - indicators.atr14 * 0.45
        : indicators.previousDonchianLow20 + indicators.atr14 * 0.45;
    final candleStop = long ? candle.low : candle.high;
    final atrStop = long
        ? conservativeEntry - indicators.atr14 * 1.55
        : conservativeEntry + indicators.atr14 * 1.55;
    final stop = long
        ? math.min(atrStop, math.min(channelStop, candleStop))
        : math.max(atrStop, math.max(channelStop, candleStop));

    return _buildIdea(
      analysis: analysis,
      strategy: AnalysisStrategy.momentumContinuation,
      capital: capital,
      riskPercent: riskPercent,
      long: long,
      entryLower: entryLower,
      entryUpper: entryUpper,
      stop: stop,
      targetMultiples: const [1.8, 2.8, 4.0],
      score: score,
      summary: fa
          ? 'شکست کانال ۲۰ کندلی با انبساط ATR، حجم و حرکت جهت‌دار تأیید شد.'
          : 'A 20-candle channel breakout was confirmed by ATR, volume and directional expansion.',
      invalidation: fa
          ? 'بازگشت معتبر داخل کانال و عبور از حد ATR سناریوی شکست را باطل می‌کند.'
          : 'A confirmed return inside the channel through the ATR stop invalidates the breakout.',
      reasons: fa
          ? [
              'امتیاز استراتژی $score از ۱۰۰ است.',
              'فاصله شکست ${normalizedExpansion.toStringAsFixed(2)} ATR است.',
              'حجم نسبی ${indicators.relativeVolume20.toStringAsFixed(2)} و ADX ${indicators.adx14.toStringAsFixed(1)} است.',
            ]
          : [
              'The strategy score is $score out of 100.',
              'Breakout distance is ${normalizedExpansion.toStringAsFixed(2)} ATR.',
              'Relative volume is ${indicators.relativeVolume20.toStringAsFixed(2)} and ADX is ${indicators.adx14.toStringAsFixed(1)}.',
            ],
      version: '2.0-donchian-breakout',
    );
  }

  static int _scoreThreshold(
    SignalCadence cadence, {
    required int conservative,
    required int balanced,
    required int active,
  }) {
    return switch (cadence) {
      SignalCadence.conservative => conservative,
      SignalCadence.balanced => balanced,
      SignalCadence.active => active,
    };
  }

  static TradeIdea _buildIdea({
    required TimeframeChartAnalysis analysis,
    required AnalysisStrategy strategy,
    required double capital,
    required double riskPercent,
    required bool long,
    required double entryLower,
    required double entryUpper,
    required double stop,
    required List<double> targetMultiples,
    required int score,
    required String summary,
    required String invalidation,
    required List<String> reasons,
    required String version,
  }) {
    final conservativeEntry = long ? entryUpper : entryLower;
    final estimatedCostPerUnit = conservativeEntry * _roundTripCostRate;
    final stopDistance = (conservativeEntry - stop).abs();
    final riskPerUnit = stopDistance + estimatedCostPerUnit;
    final maximumLoss = capital * riskPercent / 100;
    if (riskPerUnit <= 0 || !riskPerUnit.isFinite) {
      return _wait(
        analysis: analysis,
        strategy: strategy,
        confidencePercent: score,
        maximumLoss: maximumLoss,
        rejectionReason: SetupRejectionReason.invalidZones,
        summary: summary,
        invalidation: invalidation,
        reasons: reasons,
      );
    }

    final riskSizedUnits = maximumLoss / riskPerUnit;
    final riskSizedNotional = riskSizedUnits * conservativeEntry;
    final stopDistancePercent = stopDistance / conservativeEntry;
    final volatilityRate = analysis.volatilityPercent / 100;
    final liquidationCushionCap =
        (0.45 / math.max(0.005, stopDistancePercent + volatilityRate * 0.75))
            .floor()
            .clamp(1, 10)
            .toInt();
    final confidenceCap = score >= 82
        ? 8
        : score >= 72
        ? 6
        : score >= 62
        ? 4
        : 3;
    final safeLeverage = math.min(liquidationCushionCap, confidenceCap).toInt();
    final targetMargin = capital * _targetMarginFraction;
    final fundingLeverage = (riskSizedNotional / targetMargin)
        .ceil()
        .clamp(1, 100)
        .toInt();
    final recommendedLeverage = math.min(safeLeverage, fundingLeverage).toInt();
    final fundedUnits = targetMargin * recommendedLeverage / conservativeEntry;
    final positionSize = math.min(riskSizedUnits, fundedUnits);
    final notionalValue = positionSize * conservativeEntry;
    final requiredMargin = notionalValue / recommendedLeverage;
    final targets = [
      for (final multiple in targetMultiples)
        long
            ? conservativeEntry + riskPerUnit * multiple
            : conservativeEntry - riskPerUnit * multiple,
    ];

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
      requiredMargin: requiredMargin,
      estimatedRoundTripCosts: positionSize * estimatedCostPerUnit,
      setupId:
          '${analysis.symbol}|${analysis.timeframe}|${strategy.name}|${long ? 'long' : 'short'}|${analysis.fingerprint}',
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

  static TradeIdea _wait({
    required TimeframeChartAnalysis analysis,
    required AnalysisStrategy strategy,
    required int confidencePercent,
    required double maximumLoss,
    required SetupRejectionReason rejectionReason,
    required String summary,
    required String invalidation,
    required List<String> reasons,
  }) {
    return TradeIdea(
      symbol: analysis.symbol,
      timeframe: analysis.timeframe,
      direction: TradeDirection.wait,
      confidencePercent: confidencePercent.clamp(0, 92).toInt(),
      entryLower: null,
      entryUpper: null,
      stopLoss: null,
      targets: const [],
      riskReward: null,
      maximumLoss: maximumLoss,
      positionSize: null,
      notionalValue: null,
      recommendedLeverage: null,
      maximumSafeLeverage: null,
      requiredMargin: null,
      estimatedRoundTripCosts: 0,
      setupId: '${analysis.symbol}|${analysis.timeframe}|${strategy.name}|wait',
      candleClosedAt: analysis.latestCandle.openTime.add(
        _durationFor(analysis.timeframe),
      ),
      summary: summary,
      invalidation: invalidation,
      reasons: List.unmodifiable(reasons),
      rejectionReason: rejectionReason,
      strategy: strategy,
      strategyVersion: '2.0-shadow',
    );
  }

  static Duration _durationFor(String timeframe) {
    return switch (timeframe) {
      '15m' => const Duration(minutes: 15),
      '1h' => const Duration(hours: 1),
      '4h' => const Duration(hours: 4),
      '1D' => const Duration(days: 1),
      _ => Duration.zero,
    };
  }
}
