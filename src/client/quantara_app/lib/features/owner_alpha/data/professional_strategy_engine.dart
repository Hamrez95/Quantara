import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

import '../../market_analysis/data/technical_indicator_engine.dart';
import '../../market_analysis/domain/market_chart_models.dart';
import '../../market_analysis/domain/market_regime_models.dart';
import '../domain/owner_alpha_models.dart';

enum ProfessionalSetupKind {
  trendPullback,
  breakoutRetest,
  arshiaCandle,
  rangeReversal,
}

enum ExternalContextState { unavailable, fresh, stale }

final class ProfessionalStrategyContext {
  const ProfessionalStrategyContext({
    required this.evaluatedAt,
    this.entryFeeRate = 0.0006,
    this.exitFeeRate = 0.0006,
    this.slippageRate = 0.0008,
    this.fundingReserveRate = 0.0003,
    this.minimumQuantity = 0.001,
    this.minimumNotional = 5,
    this.maximumLeverage = 10,
    this.externalContextState = ExternalContextState.unavailable,
    this.requireExternalContext = false,
  });

  final DateTime evaluatedAt;
  final double entryFeeRate;
  final double exitFeeRate;
  final double slippageRate;
  final double fundingReserveRate;
  final double minimumQuantity;
  final double minimumNotional;
  final int maximumLeverage;
  final ExternalContextState externalContextState;
  final bool requireExternalContext;

  bool get valid =>
      evaluatedAt.isUtc &&
      entryFeeRate.isFinite &&
      entryFeeRate >= 0 &&
      exitFeeRate.isFinite &&
      exitFeeRate >= 0 &&
      slippageRate.isFinite &&
      slippageRate >= 0 &&
      fundingReserveRate.isFinite &&
      fundingReserveRate >= 0 &&
      minimumQuantity.isFinite &&
      minimumQuantity > 0 &&
      minimumNotional.isFinite &&
      minimumNotional > 0 &&
      maximumLeverage > 0;
}

abstract final class ProfessionalStrategyEngine {
  static const version = 'professional-pack/1.0';

  static TradeIdea create({
    required TimeframeChartAnalysis analysis,
    required double capital,
    required double riskPercent,
    required Map<String, ChartDirection> confluence,
    required String languageCode,
    required AnalysisStrategy strategy,
    required SignalCadence cadence,
    ProfessionalStrategyContext? context,
  }) {
    final effectiveContext =
        context ??
        ProfessionalStrategyContext(evaluatedAt: analysis.generatedAt.toUtc());
    final fa = languageCode != 'en';
    if (!capital.isFinite || capital <= 0) {
      throw ArgumentError.value(capital, 'capital');
    }
    if (!riskPercent.isFinite || riskPercent <= 0 || riskPercent > 2) {
      throw ArgumentError.value(riskPercent, 'riskPercent');
    }
    if (!effectiveContext.valid) {
      return _wait(
        analysis: analysis,
        kind: _kindFor(strategy, analysis, null),
        maximumLoss: capital * riskPercent / 100,
        fa: fa,
        summaryFa: 'تنظیمات هزینه یا محدودیت صرافی معتبر نیست.',
        summaryEn: 'Exchange cost or constraint settings are invalid.',
        reason: SetupRejectionReason.dataUnavailable,
      );
    }

    final closed = _closedCandleGate(
      analysis: analysis,
      evaluatedAt: effectiveContext.evaluatedAt,
    );
    if (!closed) {
      return _wait(
        analysis: analysis,
        kind: _kindFor(strategy, analysis, null),
        maximumLoss: capital * riskPercent / 100,
        fa: fa,
        summaryFa: 'فقط کندل کامل و بسته‌شده قابل ارزیابی است.',
        summaryEn: 'Only a fully closed candle may be evaluated.',
        reason: SetupRejectionReason.dataUnavailable,
      );
    }
    if (effectiveContext.requireExternalContext &&
        effectiveContext.externalContextState != ExternalContextState.fresh) {
      return _wait(
        analysis: analysis,
        kind: _kindFor(strategy, analysis, null),
        maximumLoss: capital * riskPercent / 100,
        fa: fa,
        summaryFa:
            'کانتکست اختیاری بازار در دسترس یا تازه نیست؛ حالت فقط مشاهده فعال است.',
        summaryEn:
            'Optional market context is unavailable or stale; observe-only mode is active.',
        reason: SetupRejectionReason.dataUnavailable,
      );
    }

    TechnicalIndicatorSnapshot indicators;
    try {
      indicators = TechnicalIndicatorEngine.analyze(analysis.candles);
    } on ArgumentError {
      return _wait(
        analysis: analysis,
        kind: _kindFor(strategy, analysis, null),
        maximumLoss: capital * riskPercent / 100,
        fa: fa,
        summaryFa: 'برای محاسبه پایدار اندیکاتورها داده کافی وجود ندارد.',
        summaryEn: 'There is not enough data for stable indicator calculation.',
        reason: SetupRejectionReason.dataUnavailable,
      );
    }

    final kind = _kindFor(strategy, analysis, indicators);
    final parentGate = _parentDirectionGate(
      analysis: analysis,
      kind: kind,
      confluence: confluence,
    );
    if (!parentGate.allowed) {
      return _wait(
        analysis: analysis,
        kind: kind,
        maximumLoss: capital * riskPercent / 100,
        fa: fa,
        summaryFa: parentGate.fa,
        summaryEn: parentGate.en,
        reason: SetupRejectionReason.weakDirection,
      );
    }

    final setup = switch (kind) {
      ProfessionalSetupKind.trendPullback => _trendPullback(
        analysis,
        indicators,
        cadence,
      ),
      ProfessionalSetupKind.breakoutRetest => _breakoutRetest(
        analysis,
        indicators,
        cadence,
      ),
      ProfessionalSetupKind.arshiaCandle => _arshiaCandle(
        analysis,
        indicators,
        cadence,
      ),
      ProfessionalSetupKind.rangeReversal => _rangeReversal(
        analysis,
        indicators,
        cadence,
      ),
    };

    if (setup == null) {
      return _wait(
        analysis: analysis,
        kind: kind,
        maximumLoss: capital * riskPercent / 100,
        fa: fa,
        summaryFa: _noSetupFa(kind),
        summaryEn: _noSetupEn(kind),
        reason: kind == ProfessionalSetupKind.rangeReversal
            ? SetupRejectionReason.invalidZones
            : SetupRejectionReason.weakDirection,
      );
    }

    return _buildIdea(
      analysis: analysis,
      setup: setup,
      kind: kind,
      capital: capital,
      riskPercent: riskPercent,
      strategy: strategy,
      context: effectiveContext,
      fa: fa,
      externalContextAvailable:
          effectiveContext.externalContextState == ExternalContextState.fresh,
    );
  }

  static ProfessionalSetupKind _kindFor(
    AnalysisStrategy strategy,
    TimeframeChartAnalysis analysis,
    TechnicalIndicatorSnapshot? indicators,
  ) => switch (strategy) {
    AnalysisStrategy.trendPullback => ProfessionalSetupKind.trendPullback,
    AnalysisStrategy.momentumContinuation =>
      ProfessionalSetupKind.breakoutRetest,
    AnalysisStrategy.structureZones =>
      analysis.direction == ChartDirection.sideways ||
              (indicators != null &&
                  indicators.adx14 < 19 &&
                  indicators.trendEfficiency20 < 0.38)
          ? ProfessionalSetupKind.rangeReversal
          : ProfessionalSetupKind.arshiaCandle,
  };

  static bool _closedCandleGate({
    required TimeframeChartAnalysis analysis,
    required DateTime evaluatedAt,
  }) {
    if (!evaluatedAt.isUtc ||
        !analysis.generatedAt.isUtc ||
        analysis.candles.any((candle) => !candle.isValid)) {
      return false;
    }
    final interval = _durationFor(analysis.timeframe);
    if (interval == Duration.zero) return false;
    final candleClosedAt = analysis.latestCandle.openTime.add(interval);
    if (candleClosedAt.isAfter(evaluatedAt)) return false;
    if (evaluatedAt.difference(candleClosedAt) > interval * 3) return false;
    for (var index = 1; index < analysis.candles.length; index++) {
      if (!analysis.candles[index].openTime.isAfter(
        analysis.candles[index - 1].openTime,
      )) {
        return false;
      }
    }
    return true;
  }

  static _ParentGate _parentDirectionGate({
    required TimeframeChartAnalysis analysis,
    required ProfessionalSetupKind kind,
    required Map<String, ChartDirection> confluence,
  }) {
    final parent = _parentTimeframe(analysis.timeframe);
    if (parent == null) return const _ParentGate.allowed();
    final direction = confluence[parent];
    if (direction == null) {
      return _ParentGate.blocked(
        fa: 'تایم‌فریم بالاتر $parent تازه و قابل اتکا نیست.',
        en: 'The higher timeframe $parent is not fresh and available.',
      );
    }
    if (kind == ProfessionalSetupKind.rangeReversal) {
      return direction == ChartDirection.sideways
          ? const _ParentGate.allowed()
          : const _ParentGate.blocked(
              fa: 'رنج کوتاه‌مدت با روند تایم‌فریم بالاتر هم‌خوان نیست.',
              en: 'The short-term range conflicts with the higher-timeframe trend.',
            );
    }
    if (analysis.direction == ChartDirection.sideways ||
        direction != analysis.direction) {
      return const _ParentGate.blocked(
        fa: 'جهت تایم‌فریم بالاتر با ستاپ هم‌سو نیست.',
        en: 'The higher timeframe is not aligned with the setup.',
      );
    }
    return const _ParentGate.allowed();
  }

  static _RawSetup? _trendPullback(
    TimeframeChartAnalysis analysis,
    TechnicalIndicatorSnapshot indicators,
    SignalCadence cadence,
  ) {
    final latest = analysis.latestCandle;
    final atr = indicators.atr14;
    final adxFloor = switch (cadence) {
      SignalCadence.conservative => 23.0,
      SignalCadence.balanced => 20.0,
      SignalCadence.active => 18.0,
    };
    final long = analysis.direction == ChartDirection.bullish;
    final aligned = long
        ? indicators.ema20 > indicators.ema50 &&
              indicators.plusDi14 > indicators.minusDi14
        : indicators.ema20 < indicators.ema50 &&
              indicators.minusDi14 > indicators.plusDi14;
    if (!aligned || indicators.adx14 < adxFloor || atr <= 0) return null;
    final nearEma20 = (latest.close - indicators.ema20).abs() <= atr * 0.65;
    final heldEma50 = long
        ? latest.low > indicators.ema50 - atr * 0.15
        : latest.high < indicators.ema50 + atr * 0.15;
    final directionalCandle = _directionalBody(latest, long, minimum: 0.42);
    if (!nearEma20 || !heldEma50 || !directionalCandle) return null;
    final stop = _structuralStop(analysis, indicators, long, latest);
    if (!_stopValid(long, latest.close, stop)) return null;
    return _RawSetup(
      long: long,
      entry: latest.close,
      stop: stop,
      confidenceBase: 65,
      regime: MarketRegime.directionalTrend,
      reasonsFa: [
        'EMA20 و EMA50 با جهت روند هم‌سو هستند.',
        'ADX ${indicators.adx14.toStringAsFixed(1)} و DMI جهت را تأیید می‌کنند.',
        'پولبک نزدیک EMA20 با کندل بسته‌شده رد شده است.',
      ],
      reasonsEn: [
        'EMA20 and EMA50 align with the trend.',
        'ADX ${indicators.adx14.toStringAsFixed(1)} and DMI confirm direction.',
        'A closed candle rejected the pullback near EMA20.',
      ],
    );
  }

  static _RawSetup? _breakoutRetest(
    TimeframeChartAnalysis analysis,
    TechnicalIndicatorSnapshot indicators,
    SignalCadence cadence,
  ) {
    final candles = analysis.candles;
    if (candles.length < 24 || indicators.atr14 <= 0) return null;
    final breakout = candles[candles.length - 2];
    final retest = candles.last;
    final window = candles.sublist(candles.length - 22, candles.length - 2);
    final priorHigh = window.map((item) => item.high).reduce(math.max);
    final priorLow = window.map((item) => item.low).reduce(math.min);
    final averageVolume =
        window.fold<double>(0, (sum, item) => sum + item.volume) /
        window.length;
    final breakoutRvol = averageVolume <= 0
        ? 0.0
        : breakout.volume / averageVolume;
    final volumeFloor = switch (cadence) {
      SignalCadence.conservative => 1.35,
      SignalCadence.balanced => 1.15,
      SignalCadence.active => 1.0,
    };
    final atr = indicators.atr14;
    final longBreak = breakout.close > priorHigh + atr * 0.08;
    final shortBreak = breakout.close < priorLow - atr * 0.08;
    if ((!longBreak && !shortBreak) || breakoutRvol < volumeFloor) return null;
    final long = longBreak;
    final level = long ? priorHigh : priorLow;
    final touched = long
        ? retest.low <= level + atr * 0.28
        : retest.high >= level - atr * 0.28;
    final reclaimed = long ? retest.close >= level : retest.close <= level;
    final rejection = _directionalBody(retest, long, minimum: 0.30);
    final dmiAligned = long
        ? indicators.plusDi14 >= indicators.minusDi14
        : indicators.minusDi14 >= indicators.plusDi14;
    if (!touched || !reclaimed || !rejection || !dmiAligned) return null;
    final structural = long
        ? math.min(retest.low, level - atr * 0.25)
        : math.max(retest.high, level + atr * 0.25);
    if (!_stopValid(long, retest.close, structural)) return null;
    return _RawSetup(
      long: long,
      entry: retest.close,
      stop: structural,
      confidenceBase: 68,
      regime: MarketRegime.breakoutExpansion,
      reasonsFa: [
        'شکست روی کندل قبلی و فقط پس از بسته‌شدن تأیید شده است.',
        'حجم نسبی شکست ${breakoutRvol.toStringAsFixed(2)} است.',
        'آخرین کندل سطح شکسته‌شده را Retest و پس گرفته است.',
      ],
      reasonsEn: [
        'The breakout was confirmed only after the prior candle closed.',
        'Breakout relative volume is ${breakoutRvol.toStringAsFixed(2)}.',
        'The latest candle retested and reclaimed the broken level.',
      ],
    );
  }

  static _RawSetup? _arshiaCandle(
    TimeframeChartAnalysis analysis,
    TechnicalIndicatorSnapshot indicators,
    SignalCadence cadence,
  ) {
    if (analysis.timeframe == '5m' || indicators.atr14 <= 0) return null;
    final latest = analysis.latestCandle;
    final closes = analysis.candles.map((item) => item.close).toList();
    final sma7 = closes.sublist(closes.length - 7).reduce((a, b) => a + b) / 7;
    final long = analysis.direction == ChartDirection.bullish;
    final emaAligned = long
        ? indicators.ema20 > indicators.ema50 && latest.close > indicators.ema20
        : indicators.ema20 < indicators.ema50 &&
              latest.close < indicators.ema20;
    final nearSma =
        (latest.close - sma7).abs() <= indicators.atr14 * 0.7 ||
        (long
            ? latest.low <= sma7 + indicators.atr14 * 0.18
            : latest.high >= sma7 - indicators.atr14 * 0.18);
    final bodyFloor = switch (cadence) {
      SignalCadence.conservative => 0.58,
      SignalCadence.balanced => 0.52,
      SignalCadence.active => 0.46,
    };
    final strongClose = _directionalBody(latest, long, minimum: bodyFloor);
    final closeLocation = _closeLocation(latest, long) >= 0.72;
    final volumeFloor = cadence == SignalCadence.conservative ? 1.05 : 0.9;
    if (!emaAligned ||
        !nearSma ||
        !strongClose ||
        !closeLocation ||
        indicators.relativeVolume20 < volumeFloor ||
        indicators.adx14 < 16) {
      return null;
    }
    final stop = _structuralStop(analysis, indicators, long, latest);
    if (!_stopValid(long, latest.close, stop)) return null;
    return _RawSetup(
      long: long,
      entry: latest.close,
      stop: stop,
      confidenceBase: 66,
      regime: MarketRegime.directionalTrend,
      reasonsFa: [
        'ستاپ فقط روی کندل بسته‌شده و تایم‌فریم ۱۵ دقیقه یا بالاتر بررسی شده است.',
        'SMA7، EMA20/50 و جهت ساختار هم‌سو هستند.',
        'بدنه و محل بسته‌شدن کندل، برتری سمت معامله را نشان می‌دهد.',
        'حجم نسبی ${indicators.relativeVolume20.toStringAsFixed(2)} است.',
      ],
      reasonsEn: [
        'The setup is evaluated only on a closed candle at 15m or higher.',
        'SMA7, EMA20/50 and market structure align.',
        'Candle body and close location show directional control.',
        'Relative volume is ${indicators.relativeVolume20.toStringAsFixed(2)}.',
      ],
    );
  }

  static _RawSetup? _rangeReversal(
    TimeframeChartAnalysis analysis,
    TechnicalIndicatorSnapshot indicators,
    SignalCadence cadence,
  ) {
    if (indicators.atr14 <= 0 ||
        indicators.adx14 > (cadence == SignalCadence.active ? 23 : 20) ||
        indicators.trendEfficiency20 > 0.42 ||
        indicators.atrExpansionRatio > 1.35) {
      return null;
    }
    final latest = analysis.latestCandle;
    final supports =
        analysis.zones
            .where((zone) => zone.role == ChartZoneRole.support)
            .toList()
          ..sort(
            (a, b) => (latest.close - a.center).abs().compareTo(
              (latest.close - b.center).abs(),
            ),
          );
    final resistances =
        analysis.zones
            .where((zone) => zone.role == ChartZoneRole.resistance)
            .toList()
          ..sort(
            (a, b) => (latest.close - a.center).abs().compareTo(
              (latest.close - b.center).abs(),
            ),
          );
    if (supports.isEmpty || resistances.isEmpty) return null;
    final support = supports.first;
    final resistance = resistances.first;
    final nearSupport = latest.low <= support.upper + indicators.atr14 * 0.25;
    final nearResistance =
        latest.high >= resistance.lower - indicators.atr14 * 0.25;
    final long = nearSupport && _rejectionWick(latest, true);
    final short = nearResistance && _rejectionWick(latest, false);
    if (long == short) return null;
    final stop = long
        ? math.min(latest.low, support.lower) - indicators.atr14 * 0.12
        : math.max(latest.high, resistance.upper) + indicators.atr14 * 0.12;
    if (!_stopValid(long, latest.close, stop)) return null;
    return _RawSetup(
      long: long,
      entry: latest.close,
      stop: stop,
      confidenceBase: 62,
      regime: MarketRegime.range,
      reasonsFa: [
        'ADX و کارایی روند، بازار رنج را تأیید می‌کنند.',
        'قیمت به مرز ساختاری رنج واکنش داده است.',
        'سایه ردکننده و بسته‌شدن کندل برگشت را تأیید می‌کنند.',
      ],
      reasonsEn: [
        'ADX and trend efficiency confirm a range.',
        'Price reacted at a structural range boundary.',
        'A rejection wick and candle close confirm the reversal.',
      ],
    );
  }

  static TradeIdea _buildIdea({
    required TimeframeChartAnalysis analysis,
    required _RawSetup setup,
    required ProfessionalSetupKind kind,
    required double capital,
    required double riskPercent,
    required AnalysisStrategy strategy,
    required ProfessionalStrategyContext context,
    required bool fa,
    required bool externalContextAvailable,
  }) {
    final maximumLoss = capital * riskPercent / 100;
    final entryBand = math.max(
      setup.entry * 0.00035,
      (setup.entry - setup.stop).abs() * 0.08,
    );
    final entryLower = setup.entry - entryBand;
    final entryUpper = setup.entry + entryBand;
    final conservativeEntry = setup.long ? entryUpper : entryLower;
    final stopDistance = (conservativeEntry - setup.stop).abs();
    final costRate =
        context.entryFeeRate +
        context.exitFeeRate +
        context.slippageRate +
        context.fundingReserveRate;
    final costPerUnit = conservativeEntry * costRate;
    final riskPerUnit = stopDistance + costPerUnit;
    if (!riskPerUnit.isFinite || riskPerUnit <= 0) {
      return _wait(
        analysis: analysis,
        kind: kind,
        maximumLoss: maximumLoss,
        fa: fa,
        summaryFa: 'ریسک هر واحد معتبر نیست.',
        summaryEn: 'Per-unit risk is invalid.',
        reason: SetupRejectionReason.insufficientRiskReward,
      );
    }
    var quantity = maximumLoss / riskPerUnit;
    quantity = _roundDown(quantity, 6);
    final notional = quantity * conservativeEntry;
    if (quantity < context.minimumQuantity ||
        notional < context.minimumNotional) {
      return _wait(
        analysis: analysis,
        kind: kind,
        maximumLoss: maximumLoss,
        fa: fa,
        summaryFa: 'حجم محاسبه‌شده از حداقل صرافی کمتر است.',
        summaryEn: 'The calculated size is below exchange minimums.',
        reason: SetupRejectionReason.insufficientRiskReward,
      );
    }
    final stopPercent = stopDistance / conservativeEntry;
    final structuralCap = (0.35 / math.max(0.01, stopPercent))
        .floor()
        .clamp(1, context.maximumLeverage)
        .toInt();
    final leverage = math.min(structuralCap, context.maximumLeverage).toInt();
    final requiredMargin = notional / leverage;
    final minimumRr = kind == ProfessionalSetupKind.rangeReversal ? 1.6 : 1.8;
    final target1 = setup.long
        ? conservativeEntry + riskPerUnit * minimumRr
        : conservativeEntry - riskPerUnit * minimumRr;
    final target2 = setup.long
        ? conservativeEntry + riskPerUnit * 2.6
        : conservativeEntry - riskPerUnit * 2.6;
    final target3 = setup.long
        ? conservativeEntry + riskPerUnit * 3.6
        : conservativeEntry - riskPerUnit * 3.6;
    final setupId = _deterministicSetupId(
      analysis: analysis,
      kind: kind,
      long: setup.long,
      entry: conservativeEntry,
      stop: setup.stop,
    );
    final confidence =
        (setup.confidenceBase +
                math.min(10, analysis.directionStrength * 10) +
                (externalContextAvailable ? 3 : 0))
            .round()
            .clamp(0, 90)
            .toInt();
    final labelFa = _labelFa(kind);
    final labelEn = _labelEn(kind);
    final contextReasonFa = externalContextAvailable
        ? 'کانتکست اختیاری بازار تازه است.'
        : 'کانتکست اختیاری خارجی در امتیازدهی استفاده نشده است.';
    final contextReasonEn = externalContextAvailable
        ? 'Optional market context is fresh.'
        : 'Unavailable optional external context was not used for scoring.';
    return TradeIdea(
      symbol: analysis.symbol,
      timeframe: analysis.timeframe,
      direction: setup.long ? TradeDirection.long : TradeDirection.short,
      confidencePercent: confidence,
      entryLower: entryLower,
      entryUpper: entryUpper,
      stopLoss: setup.stop,
      targets: List.unmodifiable([target1, target2, target3]),
      riskReward: minimumRr,
      maximumLoss: maximumLoss,
      positionSize: quantity,
      notionalValue: notional,
      recommendedLeverage: leverage,
      maximumSafeLeverage: structuralCap,
      requiredMargin: requiredMargin,
      estimatedRoundTripCosts: quantity * costPerUnit,
      setupId: setupId,
      candleClosedAt: analysis.latestCandle.openTime.add(
        _durationFor(analysis.timeframe),
      ),
      summary: fa
          ? '$labelFa با کندل بسته، Stop ساختاری و هزینه‌های محافظه‌کارانه تأیید شده است؛ این دستور معامله یا تضمین سود نیست.'
          : '$labelEn is confirmed with a closed candle, structural stop and conservative costs. It is not a trade instruction or profit guarantee.',
      invalidation: fa
          ? (setup.long
                ? 'بسته‌شدن معتبر زیر Stop ساختاری، سناریو را باطل می‌کند.'
                : 'بسته‌شدن معتبر بالای Stop ساختاری، سناریو را باطل می‌کند.')
          : (setup.long
                ? 'A confirmed close below the structural stop invalidates the setup.'
                : 'A confirmed close above the structural stop invalidates the setup.'),
      reasons: List.unmodifiable([
        ...(fa ? setup.reasonsFa : setup.reasonsEn),
        fa ? contextReasonFa : contextReasonEn,
        fa
            ? 'کارمزد، لغزش و ذخیره Funding در زیان حداکثر لحاظ شده‌اند.'
            : 'Fees, slippage and a funding reserve are included in maximum loss.',
        fa
            ? 'شناسه ستاپ قطعی است و از ثبت تکراری جلوگیری می‌کند.'
            : 'The setup ID is deterministic and prevents duplicate admission.',
      ]),
      strategy: strategy,
      strategyVersion: '${kind.name}/1.0',
      marketRegime: setup.regime,
    );
  }

  static TradeIdea _wait({
    required TimeframeChartAnalysis analysis,
    required ProfessionalSetupKind kind,
    required double maximumLoss,
    required bool fa,
    required String summaryFa,
    required String summaryEn,
    required SetupRejectionReason reason,
  }) {
    final closedAt = analysis.latestCandle.openTime.add(
      _durationFor(analysis.timeframe),
    );
    final setupId = sha256
        .convert(
          utf8.encode(
            '${analysis.symbol}|${analysis.timeframe}|${kind.name}|wait|'
            '${closedAt.toUtc().toIso8601String()}|$version',
          ),
        )
        .toString();
    return TradeIdea(
      symbol: analysis.symbol,
      timeframe: analysis.timeframe,
      direction: TradeDirection.wait,
      confidencePercent: 35,
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
      setupId: setupId,
      candleClosedAt: closedAt,
      summary: fa ? summaryFa : summaryEn,
      invalidation: fa
          ? 'پس از بسته‌شدن کندل جدید و تازه‌شدن تایم‌فریم‌ها دوباره ارزیابی شود.'
          : 'Re-evaluate after a new candle closes and timeframes are fresh.',
      reasons: [
        fa
            ? 'ستاپ ناقص به Candidate قابل اقدام تبدیل نمی‌شود.'
            : 'An incomplete setup is not promoted to an actionable candidate.',
      ],
      rejectionReason: reason,
      strategy: _analysisStrategyFor(kind),
      strategyVersion: '${kind.name}/1.0',
      marketRegime: MarketRegime.transition,
    );
  }

  static AnalysisStrategy _analysisStrategyFor(ProfessionalSetupKind kind) =>
      switch (kind) {
        ProfessionalSetupKind.trendPullback => AnalysisStrategy.trendPullback,
        ProfessionalSetupKind.breakoutRetest =>
          AnalysisStrategy.momentumContinuation,
        ProfessionalSetupKind.arshiaCandle ||
        ProfessionalSetupKind.rangeReversal => AnalysisStrategy.structureZones,
      };

  static double _structuralStop(
    TimeframeChartAnalysis analysis,
    TechnicalIndicatorSnapshot indicators,
    bool long,
    ChartCandle latest,
  ) {
    final protective =
        analysis.zones
            .where(
              (zone) => long
                  ? zone.role == ChartZoneRole.support &&
                        zone.lower < latest.close
                  : zone.role == ChartZoneRole.resistance &&
                        zone.upper > latest.close,
            )
            .toList()
          ..sort(
            (a, b) => (latest.close - a.center).abs().compareTo(
              (latest.close - b.center).abs(),
            ),
          );
    final zoneStop = protective.isEmpty
        ? (long ? indicators.recentSwingLow : indicators.recentSwingHigh)
        : (long ? protective.first.lower : protective.first.upper);
    return long
        ? math.min(zoneStop, latest.low) - indicators.atr14 * 0.12
        : math.max(zoneStop, latest.high) + indicators.atr14 * 0.12;
  }

  static bool _directionalBody(
    ChartCandle candle,
    bool long, {
    required double minimum,
  }) {
    final range = candle.high - candle.low;
    if (range <= 0) return false;
    final body = (candle.close - candle.open).abs();
    final direction = long
        ? candle.close > candle.open
        : candle.close < candle.open;
    return direction && body / range >= minimum;
  }

  static double _closeLocation(ChartCandle candle, bool long) {
    final range = candle.high - candle.low;
    if (range <= 0) return 0;
    return long
        ? (candle.close - candle.low) / range
        : (candle.high - candle.close) / range;
  }

  static bool _rejectionWick(ChartCandle candle, bool long) {
    final body = math.max(1e-12, (candle.close - candle.open).abs());
    final lower = math.min(candle.open, candle.close) - candle.low;
    final upper = candle.high - math.max(candle.open, candle.close);
    return long
        ? candle.close > candle.open && lower >= body * 1.15 && upper <= lower
        : candle.close < candle.open && upper >= body * 1.15 && lower <= upper;
  }

  static bool _stopValid(bool long, double entry, double stop) =>
      entry.isFinite &&
      stop.isFinite &&
      entry > 0 &&
      stop > 0 &&
      (long ? stop < entry : stop > entry);

  static String _deterministicSetupId({
    required TimeframeChartAnalysis analysis,
    required ProfessionalSetupKind kind,
    required bool long,
    required double entry,
    required double stop,
  }) {
    final closedAt = analysis.latestCandle.openTime.add(
      _durationFor(analysis.timeframe),
    );
    final canonical = jsonEncode({
      'symbol': analysis.symbol.toUpperCase(),
      'timeframe': analysis.timeframe,
      'kind': kind.name,
      'direction': long ? 'long' : 'short',
      'closedAt': closedAt.toUtc().toIso8601String(),
      'entry': entry.toStringAsFixed(8),
      'stop': stop.toStringAsFixed(8),
      'version': version,
    });
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  static double _roundDown(double value, int precision) {
    final factor = math.pow(10, precision).toDouble();
    return (value * factor).floor() / factor;
  }

  static String? _parentTimeframe(String timeframe) => switch (timeframe) {
    '5m' => '15m',
    '15m' => '1h',
    '1h' => '4h',
    '4h' => '1D',
    '1D' => null,
    _ => null,
  };

  static Duration _durationFor(String timeframe) => switch (timeframe) {
    '5m' => const Duration(minutes: 5),
    '15m' => const Duration(minutes: 15),
    '1h' => const Duration(hours: 1),
    '4h' => const Duration(hours: 4),
    '1D' => const Duration(days: 1),
    _ => Duration.zero,
  };

  static String _labelFa(ProfessionalSetupKind kind) => switch (kind) {
    ProfessionalSetupKind.trendPullback => 'پولبک روند',
    ProfessionalSetupKind.breakoutRetest => 'شکست و Retest',
    ProfessionalSetupKind.arshiaCandle => 'ستاپ کندلی ارشیا',
    ProfessionalSetupKind.rangeReversal => 'برگشت از رنج',
  };

  static String _labelEn(ProfessionalSetupKind kind) => switch (kind) {
    ProfessionalSetupKind.trendPullback => 'Trend Pullback',
    ProfessionalSetupKind.breakoutRetest => 'Breakout + Retest',
    ProfessionalSetupKind.arshiaCandle => 'Arshia Candle Setup',
    ProfessionalSetupKind.rangeReversal => 'Range Reversal',
  };

  static String _noSetupFa(ProfessionalSetupKind kind) =>
      'قواعد شفاف ${_labelFa(kind)} روی آخرین کندل بسته کامل نشده‌اند.';

  static String _noSetupEn(ProfessionalSetupKind kind) =>
      'The explicit ${_labelEn(kind)} rules are not complete on the latest closed candle.';
}

final class _RawSetup {
  const _RawSetup({
    required this.long,
    required this.entry,
    required this.stop,
    required this.confidenceBase,
    required this.regime,
    required this.reasonsFa,
    required this.reasonsEn,
  });

  final bool long;
  final double entry;
  final double stop;
  final int confidenceBase;
  final MarketRegime regime;
  final List<String> reasonsFa;
  final List<String> reasonsEn;
}

final class _ParentGate {
  const _ParentGate.allowed() : allowed = true, fa = '', en = '';

  const _ParentGate.blocked({required this.fa, required this.en})
    : allowed = false;

  final bool allowed;
  final String fa;
  final String en;
}
