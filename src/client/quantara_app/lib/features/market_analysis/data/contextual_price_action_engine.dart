import 'dart:math' as math;

import '../domain/contextual_price_action_models.dart';
import '../domain/market_chart_models.dart';
import '../domain/market_regime_models.dart';
import 'technical_indicator_engine.dart';

abstract final class StructureExpectationEngine {
  static StructureExpectationAssessment analyze({
    required TimeframeChartAnalysis analysis,
    required TechnicalIndicatorSnapshot indicators,
  }) {
    final candles = analysis.candles;
    final highs = <double>[];
    final lows = <double>[];
    for (var i = 2; i < candles.length - 2; i++) {
      final candle = candles[i];
      if (candle.high > candles[i - 1].high &&
          candle.high >= candles[i - 2].high &&
          candle.high > candles[i + 1].high &&
          candle.high >= candles[i + 2].high) {
        highs.add(candle.high);
      }
      if (candle.low < candles[i - 1].low &&
          candle.low <= candles[i - 2].low &&
          candle.low < candles[i + 1].low &&
          candle.low <= candles[i + 2].low) {
        lows.add(candle.low);
      }
    }
    final last = candles.last;
    final previousHigh = highs.isNotEmpty ? highs.last : indicators.recentSwingHigh;
    final previousLow = lows.isNotEmpty ? lows.last : indicators.recentSwingLow;
    final bullishSequence = highs.length >= 2 &&
        lows.length >= 2 &&
        highs.last > highs[highs.length - 2] &&
        lows.last > lows[lows.length - 2];
    final bearishSequence = highs.length >= 2 &&
        lows.length >= 2 &&
        highs.last < highs[highs.length - 2] &&
        lows.last < lows[lows.length - 2];
    final sequence = bullishSequence
        ? SwingSequence.bullish
        : bearishSequence
        ? SwingSequence.bearish
        : highs.length >= 2 && lows.length >= 2
        ? SwingSequence.mixed
        : SwingSequence.unknown;
    final closedAbove = last.close > previousHigh;
    final closedBelow = last.close < previousLow;
    final sweptHigh = last.high > previousHigh && last.close <= previousHigh;
    final sweptLow = last.low < previousLow && last.close >= previousLow;
    final event = sweptHigh || sweptLow
        ? StructureEvent.failedBreak
        : (bullishSequence && closedBelow) || (bearishSequence && closedAbove)
        ? StructureEvent.changeOfCharacter
        : closedAbove || closedBelow
        ? StructureEvent.breakOfStructure
        : StructureEvent.none;
    final bias = closedAbove || bullishSequence || sweptLow
        ? ChartDirection.bullish
        : closedBelow || bearishSequence || sweptHigh
        ? ChartDirection.bearish
        : ChartDirection.sideways;
    final disorder = indicators.atrExpansionRatio > 1.7 &&
        sequence == SwingSequence.mixed;
    final regime = disorder
        ? MarketRegime.disorder
        : event == StructureEvent.breakOfStructure
        ? MarketRegime.breakoutExpansion
        : bias == ChartDirection.sideways
        ? MarketRegime.range
        : event == StructureEvent.changeOfCharacter
        ? MarketRegime.transition
        : MarketRegime.directionalTrend;
    final expectedMove = event == StructureEvent.failedBreak
        ? (sweptLow
              ? ExpectedMarketMove.failedBreakReversal
              : ExpectedMarketMove.failedBreakReversal)
        : event == StructureEvent.breakOfStructure
        ? ExpectedMarketMove.breakoutContinuation
        : bias == ChartDirection.bullish
        ? ExpectedMarketMove.continuationHigher
        : bias == ChartDirection.bearish
        ? ExpectedMarketMove.continuationLower
        : ExpectedMarketMove.observeOnly;
    var score = 35.0;
    if (sequence == SwingSequence.bullish || sequence == SwingSequence.bearish) {
      score += 25;
    }
    if (event == StructureEvent.breakOfStructure) score += 18;
    if (event == StructureEvent.failedBreak) score += 14;
    if (event == StructureEvent.changeOfCharacter) score -= 8;
    if (disorder) score -= 25;
    score += analysis.directionStrength.clamp(0, 1) * 18;
    final protectedSwing = bias == ChartDirection.bullish
        ? previousLow
        : bias == ChartDirection.bearish
        ? previousHigh
        : null;
    return StructureExpectationAssessment(
      sequence: sequence,
      event: event,
      bias: bias,
      regime: regime,
      expectedMove: expectedMove,
      protectedSwing: protectedSwing,
      score: score.clamp(0, 100).toDouble(),
      reasons: [
        'Swing sequence: ${sequence.name}.',
        'Structure event: ${event.name}.',
        if (protectedSwing != null)
          'Protected swing is ${protectedSwing.toStringAsPrecision(8)}.',
      ],
    );
  }
}

abstract final class ZoneQualityEngine {
  static ZoneQualityAssessment analyze({
    required TimeframeChartAnalysis analysis,
    required TechnicalIndicatorSnapshot indicators,
    required StructureExpectationAssessment structure,
  }) {
    final latest = analysis.latestCandle;
    final desiredRole = structure.bias == ChartDirection.bearish
        ? ChartZoneRole.resistance
        : ChartZoneRole.support;
    final matching = analysis.zones.where((zone) => zone.role == desiredRole).toList()
      ..sort((a, b) => (latest.close - a.center).abs().compareTo(
            (latest.close - b.center).abs(),
          ));
    final zone = matching.isEmpty ? null : matching.first;
    if (zone == null) {
      return ZoneQualityAssessment(
        zone: null,
        freshness: 0,
        departureStrength: 0,
        touchQuality: 0,
        penetrationQuality: 0,
        compressionQuality: 0,
        roomToTarget: 0,
        score: 0,
        reasons: const ['No direction-compatible structural zone is available.'],
      );
    }
    final intervalMs = _medianIntervalMs(analysis.candles);
    final ageBars = intervalMs <= 0
        ? 999.0
        : analysis.generatedAt.difference(zone.lastTouchedAt).inMilliseconds /
              intervalMs;
    final freshness = (1 - ageBars / 80).clamp(0, 1).toDouble();
    final atr = math.max(indicators.atr14, latest.close * 0.0001);
    final departureStrength = ((latest.close - zone.center).abs() / (atr * 3))
        .clamp(0, 1)
        .toDouble();
    final touchQuality = (1 / math.max(1, zone.touchCount)).clamp(0, 1).toDouble();
    final width = math.max(zone.upper - zone.lower, latest.close * 0.00005);
    final penetration = desiredRole == ChartZoneRole.support
        ? (zone.upper - latest.low) / width
        : (latest.high - zone.lower) / width;
    final penetrationQuality = (1 - penetration.clamp(0, 1)).clamp(0, 1).toDouble();
    final recent = analysis.candles.skip(math.max(0, analysis.candles.length - 6)).toList();
    final recentRange = recent
            .map((c) => c.high - c.low)
            .fold<double>(0, (a, b) => a + b) /
        recent.length;
    final compressionQuality = (1 - recentRange / (atr * 2.2)).clamp(0, 1).toDouble();
    final opposing = analysis.zones.where((candidate) =>
        desiredRole == ChartZoneRole.support
            ? candidate.role == ChartZoneRole.resistance && candidate.lower > latest.close
            : candidate.role == ChartZoneRole.support && candidate.upper < latest.close);
    final room = opposing.isEmpty
        ? atr * 2
        : opposing
            .map((candidate) => (candidate.center - latest.close).abs())
            .reduce(math.min);
    final roomToTarget = (room / (atr * 4)).clamp(0, 1).toDouble();
    final score = 100 *
        (freshness * 0.22 +
            departureStrength * 0.18 +
            touchQuality * 0.14 +
            penetrationQuality * 0.16 +
            compressionQuality * 0.12 +
            roomToTarget * 0.18);
    return ZoneQualityAssessment(
      zone: zone,
      freshness: freshness,
      departureStrength: departureStrength,
      touchQuality: touchQuality,
      penetrationQuality: penetrationQuality,
      compressionQuality: compressionQuality,
      roomToTarget: roomToTarget,
      score: score.clamp(0, 100).toDouble(),
      reasons: [
        'Zone freshness ${(freshness * 100).round()}%.',
        'Room to opposing structure ${(roomToTarget * 100).round()}%.',
        'Zone is a range ${zone.lower.toStringAsPrecision(8)}–${zone.upper.toStringAsPrecision(8)}, not a hindsight line.',
      ],
    );
  }
}

abstract final class CandleBehaviorEngine {
  static CandleBehaviorAssessment analyze({
    required TimeframeChartAnalysis analysis,
    required StructureExpectationAssessment structure,
    required ZoneQualityAssessment zone,
  }) {
    final candles = analysis.candles;
    final latest = candles.last;
    final previous = candles[candles.length - 2];
    final range = math.max(latest.high - latest.low, latest.close * 0.000001);
    final body = (latest.close - latest.open).abs();
    final closeLocation = ((latest.close - latest.low) / range).clamp(0, 1).toDouble();
    final bodyFraction = (body / range).clamp(0, 1).toDouble();
    final bullish = structure.bias != ChartDirection.bearish;
    final rejectionWick = bullish
        ? math.min(latest.open, latest.close) - latest.low
        : latest.high - math.max(latest.open, latest.close);
    final rejectionStrength = (rejectionWick / range).clamp(0, 1).toDouble();
    final engulfing = bullish
        ? latest.close > previous.high && latest.open <= previous.close
        : latest.close < previous.low && latest.open >= previous.close;
    final selectedZone = zone.zone;
    final reclaim = selectedZone != null &&
        (bullish
            ? latest.low <= selectedZone.upper && latest.close > selectedZone.upper
            : latest.high >= selectedZone.lower && latest.close < selectedZone.lower);
    final acceptance = selectedZone != null &&
        (bullish
            ? latest.close > selectedZone.upper && closeLocation > 0.62
            : latest.close < selectedZone.lower && closeLocation < 0.38);
    final absorption = rejectionStrength >= 0.42 && bodyFraction <= 0.48;
    final followThrough = candles.length >= 3 &&
        (bullish
            ? latest.close > previous.close && previous.close > candles[candles.length - 3].close
            : latest.close < previous.close && previous.close < candles[candles.length - 3].close);
    final failedBreakout = structure.event == StructureEvent.failedBreak;
    var score = 28.0 + bodyFraction * 18 + rejectionStrength * 22;
    if (engulfing) score += 12;
    if (reclaim) score += 14;
    if (acceptance) score += 8;
    if (absorption) score += 8;
    if (followThrough) score += 10;
    if (failedBreakout) score += 8;
    final directionCloseQuality = bullish ? closeLocation : 1 - closeLocation;
    score += directionCloseQuality * 15;
    return CandleBehaviorAssessment(
      closeLocation: closeLocation,
      bodyFraction: bodyFraction,
      rejectionStrength: rejectionStrength,
      engulfing: engulfing,
      reclaim: reclaim,
      acceptance: acceptance,
      absorption: absorption,
      followThrough: followThrough,
      failedBreakout: failedBreakout,
      score: score.clamp(0, 100).toDouble(),
      reasons: [
        'Body/range ${(bodyFraction * 100).round()}%, directional close quality ${(directionCloseQuality * 100).round()}%.',
        if (reclaim) 'Price reclaimed the structural zone.',
        if (failedBreakout) 'The candle confirms a failed structural break.',
      ],
    );
  }
}

abstract final class VolumeBehaviorEngine {
  static VolumeBehaviorAssessment analyze({
    required TimeframeChartAnalysis analysis,
    required TechnicalIndicatorSnapshot indicators,
    required StructureExpectationAssessment structure,
    required CandleBehaviorAssessment candle,
  }) {
    final candles = analysis.candles;
    final latest = candles.last;
    final start = math.max(0, candles.length - 21);
    final baseline = candles.sublist(start, candles.length - 1);
    final average = baseline.isEmpty
        ? 0.0
        : baseline.fold<double>(0, (sum, c) => sum + c.volume) / baseline.length;
    final relativeVolume = average <= 0 ? 0.0 : latest.volume / average;
    final prior5 = candles.sublist(math.max(0, candles.length - 6), candles.length - 1);
    final priorAverage = prior5.isEmpty
        ? average
        : prior5.fold<double>(0, (sum, c) => sum + c.volume) / prior5.length;
    final breakoutExpansion = structure.event == StructureEvent.breakOfStructure &&
        relativeVolume >= 1.2;
    final pullbackContraction = structure.regime == MarketRegime.directionalTrend &&
        priorAverage < average * 0.9;
    final reExpansion = relativeVolume >= math.max(1.05, priorAverage / math.max(1, average));
    final climax = relativeVolume >= 2.2;
    final absorption = relativeVolume >= 1.5 && candle.bodyFraction < 0.35;
    final effortVsResult = relativeVolume >= 1.35 &&
        (latest.close - latest.open).abs() <= indicators.atr14 * 0.3;
    final lookback = candles.length >= 8 ? candles[candles.length - 8] : candles.first;
    final priceExpanded = (latest.close - lookback.close).abs() > indicators.atr14 * 1.2;
    final volumeContracted = latest.volume < lookback.volume * 0.8;
    final divergence = priceExpanded && volumeContracted;
    var score = 35.0 + relativeVolume.clamp(0, 2) * 18;
    if (breakoutExpansion) score += 18;
    if (pullbackContraction) score += 8;
    if (reExpansion) score += 10;
    if (absorption) score += 8;
    if (effortVsResult) score += structure.event == StructureEvent.failedBreak ? 10 : -8;
    if (divergence) score -= 18;
    if (climax && structure.event != StructureEvent.failedBreak) score -= 8;
    return VolumeBehaviorAssessment(
      relativeVolume: relativeVolume,
      breakoutExpansion: breakoutExpansion,
      pullbackContraction: pullbackContraction,
      reExpansion: reExpansion,
      climax: climax,
      absorption: absorption,
      effortVsResult: effortVsResult,
      divergence: divergence,
      score: score.clamp(0, 100).toDouble(),
      reasons: [
        'Session-local relative volume is ${relativeVolume.toStringAsFixed(2)}.',
        if (breakoutExpansion) 'Breakout has volume expansion.',
        if (divergence) 'Price expansion is not confirmed by volume.',
      ],
    );
  }
}

abstract final class MomentumContextEngine {
  static MomentumContextAssessment analyze({
    required TimeframeChartAnalysis analysis,
    required TechnicalIndicatorSnapshot indicators,
    required StructureExpectationAssessment structure,
  }) {
    final candles = analysis.candles;
    final earlierEnd = math.max(15, candles.length - 7);
    final earlier = candles.sublist(0, earlierEnd);
    final priorRsi = _simpleRsi(earlier.map((c) => c.close).toList());
    final rsi = indicators.rsi14;
    final bullish = structure.bias != ChartDirection.bearish;
    final rsiReset = bullish ? rsi >= 42 && rsi <= 62 : rsi >= 38 && rsi <= 58;
    final priceDelta = candles.last.close - candles[earlierEnd - 1].close;
    final rsiDelta = rsi - priorRsi;
    final divergence = bullish
        ? priceDelta > 0 && rsiDelta < -4
        : priceDelta < 0 && rsiDelta > 4;
    final directionalSpread = indicators.plusDi14 - indicators.minusDi14;
    final directionAligned = bullish ? directionalSpread > 0 : directionalSpread < 0;
    final momentumLoss = !directionAligned || divergence || indicators.adx14 < 16;
    final expansion = indicators.adx14 >= 23 &&
        directionAligned &&
        indicators.atrExpansionRatio >= 1.05;
    var score = 38.0;
    if (directionAligned) score += 20;
    score += (indicators.adx14 / 40).clamp(0, 1) * 20;
    if (rsiReset) score += 12;
    if (expansion) score += 14;
    if (divergence) score -= 22;
    if (momentumLoss) score -= 12;
    return MomentumContextAssessment(
      rsi: rsi,
      adx: indicators.adx14,
      directionalSpread: directionalSpread,
      rsiReset: rsiReset,
      divergence: divergence,
      momentumLoss: momentumLoss,
      expansion: expansion,
      score: score.clamp(0, 100).toDouble(),
      reasons: [
        'RSI ${rsi.toStringAsFixed(1)}, ADX ${indicators.adx14.toStringAsFixed(1)}, DMI spread ${directionalSpread.toStringAsFixed(1)}.',
        if (rsiReset) 'RSI is reset inside contextual continuation range.',
        if (momentumLoss) 'Momentum is losing directional confirmation.',
      ],
    );
  }
}

abstract final class ContextualPriceActionEngine {
  static const version = 'contextual-price-action/3.0';
  static const familyCap = 20.0;

  static ContextualPriceActionAssessment analyze({
    required TimeframeChartAnalysis analysis,
    TechnicalIndicatorSnapshot? indicators,
  }) {
    final technical = indicators ?? TechnicalIndicatorEngine.analyze(analysis.candles);
    final structure = StructureExpectationEngine.analyze(
      analysis: analysis,
      indicators: technical,
    );
    final zone = ZoneQualityEngine.analyze(
      analysis: analysis,
      indicators: technical,
      structure: structure,
    );
    final candle = CandleBehaviorEngine.analyze(
      analysis: analysis,
      structure: structure,
      zone: zone,
    );
    final volume = VolumeBehaviorEngine.analyze(
      analysis: analysis,
      indicators: technical,
      structure: structure,
      candle: candle,
    );
    final momentum = MomentumContextEngine.analyze(
      analysis: analysis,
      indicators: technical,
      structure: structure,
    );
    EvidenceFamilyScore family(
      ContextualEvidenceFamily name,
      double raw,
      List<String> reasons,
    ) => EvidenceFamilyScore(
      family: name,
      rawScore: raw / 5,
      cap: familyCap,
      reasons: reasons,
    );
    final families = <ContextualEvidenceFamily, EvidenceFamilyScore>{
      ContextualEvidenceFamily.structure:
          family(ContextualEvidenceFamily.structure, structure.score, structure.reasons),
      ContextualEvidenceFamily.zone:
          family(ContextualEvidenceFamily.zone, zone.score, zone.reasons),
      ContextualEvidenceFamily.candle:
          family(ContextualEvidenceFamily.candle, candle.score, candle.reasons),
      ContextualEvidenceFamily.volume:
          family(ContextualEvidenceFamily.volume, volume.score, volume.reasons),
      ContextualEvidenceFamily.momentum:
          family(ContextualEvidenceFamily.momentum, momentum.score, momentum.reasons),
    };
    var quality = families.values.fold<double>(0, (sum, value) => sum + value.cappedScore);
    if (structure.regime == MarketRegime.disorder) quality *= 0.55;
    if (momentum.momentumLoss && volume.divergence) quality *= 0.75;
    final score = quality.round().clamp(0, 100).toInt();
    final bias = structure.bias;
    final expectation = switch (structure.expectedMove) {
      ExpectedMarketMove.continuationHigher => 'Expect continuation toward the next higher structural zone.',
      ExpectedMarketMove.continuationLower => 'Expect continuation toward the next lower structural zone.',
      ExpectedMarketMove.rangeRotationHigher => 'Expect rotation from range support toward the range mean/opposite edge.',
      ExpectedMarketMove.rangeRotationLower => 'Expect rotation from range resistance toward the range mean/opposite edge.',
      ExpectedMarketMove.breakoutContinuation => 'Expect continuation only if the break is accepted and holds.',
      ExpectedMarketMove.failedBreakReversal => 'Expect reversal only after the failed break is reclaimed.',
      ExpectedMarketMove.observeOnly => 'Structure has no directional expectation; observe only.',
    };
    final trigger = bias == ChartDirection.bullish
        ? 'Require a closed-candle reclaim/acceptance with directional follow-through.'
        : bias == ChartDirection.bearish
        ? 'Require a closed-candle rejection/acceptance lower with directional follow-through.'
        : 'Require a closed-candle break or range-edge reclaim before arming.';
    final protected = structure.protectedSwing;
    final invalidation = protected == null
        ? 'Invalidate when structure becomes disordered or the active zone is decisively lost.'
        : bias == ChartDirection.bullish
        ? 'Invalidate on a confirmed close below protected swing ${protected.toStringAsPrecision(8)}.'
        : 'Invalidate on a confirmed close above protected swing ${protected.toStringAsPrecision(8)}.';
    return ContextualPriceActionAssessment(
      version: version,
      structure: structure,
      zone: zone,
      candle: candle,
      volume: volume,
      momentum: momentum,
      families: families,
      setupQualityScore: score,
      regime: structure.regime,
      expectation: expectation,
      trigger: trigger,
      invalidation: invalidation,
    );
  }
}

int _medianIntervalMs(List<ChartCandle> candles) {
  if (candles.length < 2) return 0;
  final values = <int>[];
  for (var i = 1; i < candles.length; i++) {
    values.add(candles[i].openTime.difference(candles[i - 1].openTime).inMilliseconds);
  }
  values.sort();
  return values[values.length ~/ 2];
}

double _simpleRsi(List<double> closes) {
  if (closes.length < 15) return 50;
  var gains = 0.0;
  var losses = 0.0;
  final start = closes.length - 15;
  for (var i = start + 1; i < closes.length; i++) {
    final change = closes[i] - closes[i - 1];
    if (change >= 0) {
      gains += change;
    } else {
      losses -= change;
    }
  }
  if (losses == 0) return gains == 0 ? 50 : 100;
  final rs = gains / losses;
  return 100 - (100 / (1 + rs));
}
