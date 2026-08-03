import 'dart:math' as math;

import '../../market_analysis/domain/market_chart_models.dart';
import '../../market_analysis/domain/market_regime_models.dart';
import '../domain/owner_alpha_models.dart';
import 'advanced_strategy_engine.dart';
import 'strategy_engine_v2.dart';

abstract final class TradeIdeaFactory {
  static const assumedRoundTripCostRate = 0.002;
  static const targetMarginFraction = 0.20;

  static TradeIdea create({
    required TimeframeChartAnalysis analysis,
    required double capital,
    required double riskPercent,
    Map<String, ChartDirection> confluence = const {},
    String languageCode = 'fa',
    AnalysisStrategy strategy = AnalysisStrategy.structureZones,
    SignalCadence cadence = SignalCadence.balanced,
  }) {
    if (!capital.isFinite || capital <= 0) {
      throw ArgumentError.value(capital, 'capital');
    }
    if (!riskPercent.isFinite || riskPercent <= 0 || riskPercent > 2) {
      throw ArgumentError.value(riskPercent, 'riskPercent');
    }

    final advancedIdea = AdvancedStrategyEngine.tryCreate(
      analysis: analysis,
      capital: capital,
      riskPercent: riskPercent,
      languageCode: languageCode,
      strategy: strategy,
      cadence: cadence,
      confluence: confluence,
    );
    if (advancedIdea != null) {
      return advancedIdea;
    }

    final v2Idea = StrategyEngineV2.tryCreate(
      analysis: analysis,
      capital: capital,
      riskPercent: riskPercent,
      languageCode: languageCode,
      strategy: strategy,
      cadence: cadence,
      confluence: confluence,
    );
    if (v2Idea != null) {
      return v2Idea;
    }

    return _structureZones(
      analysis: analysis,
      capital: capital,
      riskPercent: riskPercent,
      confluence: confluence,
      languageCode: languageCode,
      cadence: cadence,
    );
  }

  static TradeIdea _structureZones({
    required TimeframeChartAnalysis analysis,
    required double capital,
    required double riskPercent,
    required Map<String, ChartDirection> confluence,
    required String languageCode,
    required SignalCadence cadence,
  }) {
    final maximumLoss = capital * riskPercent / 100;
    final fa = languageCode != 'en';
    final current = analysis.latestCandle.close;
    final supports =
        analysis.zones
            .where(
              (zone) =>
                  zone.role == ChartZoneRole.support && zone.upper < current,
            )
            .toList(growable: false)
          ..sort((left, right) => right.upper.compareTo(left.upper));
    final resistances =
        analysis.zones
            .where(
              (zone) =>
                  zone.role == ChartZoneRole.resistance && zone.lower > current,
            )
            .toList(growable: false)
          ..sort((left, right) => left.lower.compareTo(right.lower));
    final aligned = confluence.values
        .where((direction) => direction == analysis.direction)
        .length;
    final cadenceFloor = switch (cadence) {
      SignalCadence.conservative => 0.42,
      SignalCadence.balanced => 0.32,
      SignalCadence.active => 0.25,
    };
    final directional = analysis.direction != ChartDirection.sideways;
    final enoughStrength = analysis.directionStrength >= cadenceFloor;

    if (!directional || !enoughStrength) {
      return TradeIdea.wait(
        symbol: analysis.symbol,
        timeframe: analysis.timeframe,
        confidencePercent: (35 + analysis.directionStrength * 30).round(),
        maximumLoss: maximumLoss,
        summary: fa
            ? 'ساختار فعلی جهت و قدرت کافی برای تعریف ورود کم‌ریسک ندارد.'
            : 'The current structure lacks enough direction and strength for a lower-risk entry.',
        invalidation: fa
            ? 'پس از شکست معتبر ساختار یا تشکیل ناحیه تازه دوباره بررسی شود.'
            : 'Review after a confirmed structure break or a newly formed zone.',
        reasons: fa
            ? const [
                'قدرت روند هنوز پایین است.',
                'صبر در این وضعیت بخشی از مدیریت سرمایه است.',
              ]
            : const [
                'Trend strength is still low.',
                'Waiting here is part of risk management.',
              ],
        rejectionReason: SetupRejectionReason.weakDirection,
      );
    }

    final long = analysis.direction == ChartDirection.bullish;
    if ((long && (supports.isEmpty || resistances.isEmpty)) ||
        (!long && (resistances.isEmpty || supports.isEmpty))) {
      return TradeIdea.wait(
        symbol: analysis.symbol,
        timeframe: analysis.timeframe,
        confidencePercent: (42 + analysis.directionStrength * 25).round(),
        maximumLoss: maximumLoss,
        summary: fa
            ? 'روند دیده می‌شود، اما حد ضرر و هدف معتبر هم‌زمان پیدا نشد.'
            : 'A trend is visible, but a valid stop and target were not found together.',
        invalidation: fa
            ? 'با تشکیل حمایت و مقاومت تأییدشده دوباره بررسی شود.'
            : 'Review when confirmed support and resistance zones form.',
        reasons: fa
            ? const [
                'بدون مرز ابطال روشن، محاسبه حجم قابل اتکا نیست.',
                'سیگنال ناقص به موقعیت معاملاتی تبدیل نمی‌شود.',
              ]
            : const [
                'Position sizing is unreliable without a clear invalidation boundary.',
                'An incomplete signal is not promoted to a trade setup.',
              ],
        rejectionReason: SetupRejectionReason.invalidZones,
      );
    }

    final protectiveZone = long ? supports.first : resistances.first;
    final targetZone = long ? resistances.first : supports.first;
    final volatilityBuffer = math.max(
      current * 0.0015,
      current * analysis.volatilityPercent / 100 * 0.35,
    );
    final stop = long
        ? protectiveZone.lower - volatilityBuffer
        : protectiveZone.upper + volatilityBuffer;
    final entryHalfWidth = math.max(
      current * 0.0005,
      current * analysis.volatilityPercent / 100 * 0.08,
    );
    final entryLower = current - entryHalfWidth;
    final entryUpper = current + entryHalfWidth;
    final conservativeEntry = long ? entryUpper : entryLower;
    final firstTarget = targetZone.center;
    final stopDistancePerUnit = (conservativeEntry - stop).abs();
    final grossRewardPerUnit = (firstTarget - conservativeEntry).abs();
    final estimatedCostPerUnit = conservativeEntry * assumedRoundTripCostRate;
    final riskPerUnit = stopDistancePerUnit + estimatedCostPerUnit;
    final rewardPerUnit = math.max(
      0.0,
      grossRewardPerUnit - estimatedCostPerUnit,
    );
    final riskReward = riskPerUnit == 0 ? 0.0 : rewardPerUnit / riskPerUnit;

    if (riskPerUnit <= 0 ||
        firstTarget <= 0 ||
        (long && firstTarget <= conservativeEntry) ||
        (!long && firstTarget >= conservativeEntry) ||
        riskReward < 1.6) {
      return TradeIdea.wait(
        symbol: analysis.symbol,
        timeframe: analysis.timeframe,
        confidencePercent: (48 + analysis.directionStrength * 22).round(),
        maximumLoss: maximumLoss,
        summary: fa
            ? 'جهت بازار مشخص است، اما نسبت سود به زیان ورود فعلی کافی نیست.'
            : 'Market direction is clear, but the current entry has insufficient reward relative to risk.',
        invalidation: fa
            ? 'با بهترشدن قیمت ورود یا جابه‌جایی ناحیه هدف دوباره بررسی شود.'
            : 'Review after entry price improves or the target zone moves.',
        reasons: fa
            ? [
                'حداقل نسبت قابل قبول ۱٫۶ است.',
                'نسبت فعلی ${riskReward.toStringAsFixed(2)} است.',
              ]
            : [
                'The minimum acceptable ratio is 1.6.',
                'The current ratio is ${riskReward.toStringAsFixed(2)}.',
              ],
        rejectionReason: SetupRejectionReason.insufficientRiskReward,
      );
    }

    final riskSizedUnits = maximumLoss / riskPerUnit;
    final riskSizedNotional = riskSizedUnits * conservativeEntry;
    final stopDistancePercent = stopDistancePerUnit / conservativeEntry;
    final volatilityRate = analysis.volatilityPercent / 100;
    final liquidationCushionCap =
        (0.45 / math.max(0.005, stopDistancePercent + volatilityRate * 0.75))
            .floor()
            .clamp(1, 10)
            .toInt();
    final confidenceCap = confidenceLeverageCap(
      analysis.directionStrength,
      protectiveZone.strength,
    );
    final safeLeverage = math.min(liquidationCushionCap, confidenceCap);
    final targetMargin = capital * targetMarginFraction;
    final fundingLeverage = (riskSizedNotional / targetMargin)
        .ceil()
        .clamp(1, 100)
        .toInt();
    final recommendedLeverage = math.min(safeLeverage, fundingLeverage).toInt();
    final fundedUnits = targetMargin * recommendedLeverage / conservativeEntry;
    final positionSize = math.min(riskSizedUnits, fundedUnits);
    final notionalValue = positionSize * conservativeEntry;
    final requiredMargin = notionalValue / recommendedLeverage;
    final estimatedRoundTripCosts = positionSize * estimatedCostPerUnit;
    final secondTarget = long
        ? conservativeEntry + riskPerUnit * math.max(2.2, riskReward + 0.6)
        : conservativeEntry - riskPerUnit * math.max(2.2, riskReward + 0.6);
    final thirdTarget = long
        ? conservativeEntry + riskPerUnit * math.max(3.2, riskReward + 1.4)
        : conservativeEntry - riskPerUnit * math.max(3.2, riskReward + 1.4);
    final confidence =
        (52 +
                analysis.directionStrength * 24 +
                protectiveZone.strength * 12 +
                math.min(3, aligned) * 4)
            .round()
            .clamp(0, 92)
            .toInt();
    final directionText = long
        ? (fa ? 'خرید' : 'long')
        : (fa ? 'فروش' : 'short');

    return TradeIdea(
      symbol: analysis.symbol,
      timeframe: analysis.timeframe,
      direction: long ? TradeDirection.long : TradeDirection.short,
      confidencePercent: confidence,
      entryLower: entryLower,
      entryUpper: entryUpper,
      stopLoss: stop,
      targets: List.unmodifiable([firstTarget, secondTarget, thirdTarget]),
      riskReward: riskReward,
      maximumLoss: maximumLoss,
      positionSize: positionSize,
      notionalValue: notionalValue,
      recommendedLeverage: recommendedLeverage,
      maximumSafeLeverage: safeLeverage,
      requiredMargin: requiredMargin,
      estimatedRoundTripCosts: estimatedRoundTripCosts,
      setupId:
          '${analysis.symbol}|${analysis.timeframe}|${long ? 'long' : 'short'}|${analysis.fingerprint}',
      candleClosedAt: analysis.latestCandle.openTime.add(
        _durationFor(analysis.timeframe),
      ),
      summary: fa
          ? 'سناریوی $directionText با حد ابطال روشن و نسبت سود به زیان قابل بررسی است؛ این تحلیل الگوریتمی است، نه دستور معامله.'
          : 'The $directionText scenario has clear invalidation and reviewable reward relative to risk. It is algorithmic analysis, not a trade instruction.',
      invalidation: fa
          ? (long
                ? 'بسته‌شدن معتبر زیر ناحیه حمایتی، سناریوی خرید را باطل می‌کند.'
                : 'بسته‌شدن معتبر بالای ناحیه مقاومتی، سناریوی فروش را باطل می‌کند.')
          : (long
                ? 'A confirmed close below support invalidates the long scenario.'
                : 'A confirmed close above resistance invalidates the short scenario.'),
      reasons: List.unmodifiable(
        fa
            ? [
                'قدرت ساختار ${(analysis.directionStrength * 100).round()}٪ است.',
                'ناحیه محافظ ${protectiveZone.touchCount} واکنش تأییدشده دارد.',
                if (aligned > 0) '$aligned تایم‌فریم با جهت فعلی هم‌سو است.',
                'زیان محاسباتی به ${riskPercent.toStringAsFixed(1)}٪ سرمایه محدود شده است.',
                'اهرم ${recommendedLeverage}x برای درگیرکردن حداکثر ۲۰٪ سرمایه انتخاب شده و از سقف امن این ستاپ بالاتر نمی‌رود.',
                'برای کارمزد و لغزش رفت‌وبرگشت، ۰٫۲۰٪ هزینه فرضی در نظر گرفته شده است.',
              ]
            : [
                'Structure strength is ${(analysis.directionStrength * 100).round()}%.',
                'The protective zone has ${protectiveZone.touchCount} confirmed reactions.',
                if (aligned > 0)
                  '$aligned timeframes align with the current direction.',
                'Calculated loss is limited to ${riskPercent.toStringAsFixed(1)}% of capital.',
                '${recommendedLeverage}x targets at most 20% account margin without exceeding this setup’s safety cap.',
                'A 0.20% round-trip fee and slippage estimate is included.',
              ],
      ),
      strategy: AnalysisStrategy.structureZones,
      strategyVersion: strategyVersion(AnalysisStrategy.structureZones),
      marketRegime: MarketRegime.directionalTrend,
    );
  }

  static bool protectiveAlignment(
    TimeframeChartAnalysis analysis,
    List<ChartPriceZone> supports,
    List<ChartPriceZone> resistances,
  ) {
    final current = analysis.latestCandle.close;
    final zones = analysis.direction == ChartDirection.bullish
        ? supports
        : resistances;
    if (zones.isEmpty || current <= 0) {
      return false;
    }
    final distance = (current - zones.first.center).abs() / current;
    return distance <= math.max(0.008, analysis.volatilityPercent / 100 * 1.4);
  }

  static String strategyVersion(AnalysisStrategy strategy) =>
      switch (strategy) {
        AnalysisStrategy.structureZones => 'structure-zones/1.2',
        AnalysisStrategy.trendPullback => 'trend-pullback/2.0',
        AnalysisStrategy.momentumContinuation => 'donchian-breakout/2.0',
      };

  static int confidenceLeverageCap(
    double directionStrength,
    double protectiveZoneStrength,
  ) {
    final combined = directionStrength * 0.6 + protectiveZoneStrength * 0.4;
    if (combined < 0.45) return 2;
    if (combined < 0.6) return 3;
    if (combined < 0.75) return 5;
    return 8;
  }

  static Duration _durationFor(String timeframe) => switch (timeframe) {
    '15m' => const Duration(minutes: 15),
    '1h' => const Duration(hours: 1),
    '4h' => const Duration(hours: 4),
    '1D' => const Duration(days: 1),
    _ => Duration.zero,
  };
}
