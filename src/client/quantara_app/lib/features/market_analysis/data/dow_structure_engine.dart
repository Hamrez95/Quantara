import 'dart:math' as math;

import '../domain/dow_structure_models.dart';
import '../domain/market_chart_models.dart';

abstract final class DowStructureEngine {
  static DowStructureSnapshot analyze({
    required TimeframeChartAnalysis analysis,
    DowStructureConfig config = const DowStructureConfig(),
  }) {
    config.validate();
    final interval = _durationFor(analysis.timeframe);
    final candles = analysis.candles;
    final latest = candles.last;
    final latestClosedAt = latest.openTime.add(interval);
    final reasonCodes = <String>[];

    var gapped = false;
    for (var index = 1; index < candles.length; index++) {
      final delta = candles[index].openTime.difference(
        candles[index - 1].openTime,
      );
      if (delta.inMicroseconds >
          interval.inMicroseconds * config.maximumGapMultiple) {
        gapped = true;
        reasonCodes.add('dow:data:gap');
        break;
      }
    }

    final generatedBeforeClose = analysis.generatedAt.isBefore(latestClosedAt);
    final staleness = analysis.generatedAt.difference(latestClosedAt);
    final stale =
        generatedBeforeClose ||
        staleness > interval * config.maximumStalenessBars;
    if (generatedBeforeClose) reasonCodes.add('dow:data:unclosed');
    if (!generatedBeforeClose && stale) reasonCodes.add('dow:data:stale');

    final atr = _atr(candles);
    final pivots =
        <DowPivot>[
          ..._confirmedPivots(
            candles: candles,
            interval: interval,
            scope: DowStructureScope.internal,
            wing: config.internalWing,
            equalityTolerance: atr * config.equalPivotAtrFraction,
          ),
          ..._confirmedPivots(
            candles: candles,
            interval: interval,
            scope: DowStructureScope.external,
            wing: config.externalWing,
            equalityTolerance: atr * config.equalPivotAtrFraction,
          ),
        ]..sort((left, right) {
          final confirmed = left.confirmedAtUtc.compareTo(right.confirmedAtUtc);
          if (confirmed != 0) return confirmed;
          final scope = left.scope.index.compareTo(right.scope.index);
          if (scope != 0) return scope;
          return left.index.compareTo(right.index);
        });

    final internalPivots = pivots
        .where((pivot) => pivot.scope == DowStructureScope.internal)
        .toList(growable: false);
    final externalPivots = pivots
        .where((pivot) => pivot.scope == DowStructureScope.external)
        .toList(growable: false);
    final internalState = _stateFor(internalPivots);
    final externalState = _stateFor(externalPivots);

    final events = <DowStructureEvent>[];
    final internalEvent = _latestEvent(
      candles: candles,
      interval: interval,
      pivots: internalPivots,
      state: internalState,
      atr: atr,
      config: config,
      scope: DowStructureScope.internal,
    );
    if (internalEvent != null) events.add(internalEvent);
    final externalEvent = _latestEvent(
      candles: candles,
      interval: interval,
      pivots: externalPivots,
      state: externalState,
      atr: atr,
      config: config,
      scope: DowStructureScope.external,
    );
    if (externalEvent != null) events.add(externalEvent);

    final internal = _scopeSnapshot(
      scope: DowStructureScope.internal,
      pivots: internalPivots,
      state: internalState,
      latestEvent: internalEvent,
    );
    final external = _scopeSnapshot(
      scope: DowStructureScope.external,
      pivots: externalPivots,
      state: externalState,
      latestEvent: externalEvent,
    );

    if (pivots.isEmpty) reasonCodes.add('dow:structure:insufficient_pivots');
    reasonCodes
      ..add('dow:internal:${internal.state.name}')
      ..add('dow:external:${external.state.name}')
      ..addAll(events.map((event) => event.reasonCode));

    return DowStructureSnapshot(
      version: config.version,
      configFingerprint: config.fingerprint,
      analysisFingerprint: analysis.fingerprint,
      generatedAtUtc: analysis.generatedAt,
      valid: !gapped && !stale && atr.isFinite && atr > 0,
      stale: stale,
      gapped: gapped,
      internal: internal,
      external: external,
      pivots: pivots,
      events: events,
      reasonCodes: reasonCodes,
    );
  }

  static List<DowPivot> _confirmedPivots({
    required List<ChartCandle> candles,
    required Duration interval,
    required DowStructureScope scope,
    required int wing,
    required double equalityTolerance,
  }) {
    final result = <DowPivot>[];
    DowPivot? previousHigh;
    DowPivot? previousLow;
    for (var index = wing; index < candles.length - wing; index++) {
      final candle = candles[index];
      var isHigh = true;
      var isLow = true;
      for (var offset = 1; offset <= wing; offset++) {
        final before = candles[index - offset];
        final after = candles[index + offset];
        if (candle.high <= before.high || candle.high <= after.high) {
          isHigh = false;
        }
        if (candle.low >= before.low || candle.low >= after.low) {
          isLow = false;
        }
        if (!isHigh && !isLow) break;
      }
      final confirmedAt = candles[index + wing].openTime.add(interval);
      if (isHigh) {
        final label = _highLabel(
          previousHigh?.price,
          candle.high,
          equalityTolerance,
        );
        final pivot = DowPivot(
          scope: scope,
          kind: DowPivotKind.high,
          label: label,
          index: index,
          price: candle.high,
          pivotTimeUtc: candle.openTime,
          confirmedAtUtc: confirmedAt,
        );
        result.add(pivot);
        previousHigh = pivot;
      }
      if (isLow) {
        final label = _lowLabel(
          previousLow?.price,
          candle.low,
          equalityTolerance,
        );
        final pivot = DowPivot(
          scope: scope,
          kind: DowPivotKind.low,
          label: label,
          index: index,
          price: candle.low,
          pivotTimeUtc: candle.openTime,
          confirmedAtUtc: confirmedAt,
        );
        result.add(pivot);
        previousLow = pivot;
      }
    }
    result.sort((left, right) => left.index.compareTo(right.index));
    return result;
  }

  static DowPivotLabel _highLabel(
    double? previous,
    double current,
    double tolerance,
  ) {
    if (previous == null) return DowPivotLabel.unknown;
    if ((current - previous).abs() <= tolerance) return DowPivotLabel.equalHigh;
    return current > previous ? DowPivotLabel.hh : DowPivotLabel.lh;
  }

  static DowPivotLabel _lowLabel(
    double? previous,
    double current,
    double tolerance,
  ) {
    if (previous == null) return DowPivotLabel.unknown;
    if ((current - previous).abs() <= tolerance) return DowPivotLabel.equalLow;
    return current > previous ? DowPivotLabel.hl : DowPivotLabel.ll;
  }

  static DowStructureState _stateFor(List<DowPivot> pivots) {
    final highs = pivots.where((pivot) => pivot.kind == DowPivotKind.high);
    final lows = pivots.where((pivot) => pivot.kind == DowPivotKind.low);
    if (highs.length < 2 || lows.length < 2) return DowStructureState.unknown;
    final high = highs.last.label;
    final low = lows.last.label;
    if (high == DowPivotLabel.hh && low == DowPivotLabel.hl) {
      return DowStructureState.bullishContinuation;
    }
    if (high == DowPivotLabel.lh && low == DowPivotLabel.ll) {
      return DowStructureState.bearishContinuation;
    }
    if ((high == DowPivotLabel.hh && low == DowPivotLabel.ll) ||
        (high == DowPivotLabel.lh && low == DowPivotLabel.hl)) {
      return DowStructureState.transition;
    }
    if (high == DowPivotLabel.equalHigh || low == DowPivotLabel.equalLow) {
      return DowStructureState.range;
    }
    return DowStructureState.range;
  }

  static DowStructureEvent? _latestEvent({
    required List<ChartCandle> candles,
    required Duration interval,
    required List<DowPivot> pivots,
    required DowStructureState state,
    required double atr,
    required DowStructureConfig config,
    required DowStructureScope scope,
  }) {
    if (pivots.isEmpty || !atr.isFinite || atr <= 0) return null;
    final highs = pivots.where((pivot) => pivot.kind == DowPivotKind.high);
    final lows = pivots.where((pivot) => pivot.kind == DowPivotKind.low);
    if (highs.isEmpty || lows.isEmpty) return null;
    final high = highs.last;
    final low = lows.last;
    final latest = candles.last;
    final acceptance = atr * config.acceptanceAtrFraction;
    final body = (latest.close - latest.open).abs();
    final displaced = body >= atr * config.minimumBodyAtrFraction;
    final occurredAt = latest.openTime.add(interval);

    if (latest.close > high.price + acceptance && displaced) {
      return DowStructureEvent(
        type: state == DowStructureState.bearishContinuation
            ? DowStructureEventType.chochUp
            : DowStructureEventType.bosUp,
        scope: scope,
        occurredAtUtc: occurredAt,
        level: high.price,
        close: latest.close,
        acceptanceDistance: latest.close - high.price,
      );
    }
    if (latest.close < low.price - acceptance && displaced) {
      return DowStructureEvent(
        type: state == DowStructureState.bullishContinuation
            ? DowStructureEventType.chochDown
            : DowStructureEventType.bosDown,
        scope: scope,
        occurredAtUtc: occurredAt,
        level: low.price,
        close: latest.close,
        acceptanceDistance: low.price - latest.close,
      );
    }
    if (latest.high > high.price && latest.close <= high.price) {
      return DowStructureEvent(
        type: DowStructureEventType.failedBreakUp,
        scope: scope,
        occurredAtUtc: occurredAt,
        level: high.price,
        close: latest.close,
        acceptanceDistance: 0,
      );
    }
    if (latest.low < low.price && latest.close >= low.price) {
      return DowStructureEvent(
        type: DowStructureEventType.failedBreakDown,
        scope: scope,
        occurredAtUtc: occurredAt,
        level: low.price,
        close: latest.close,
        acceptanceDistance: 0,
      );
    }
    return null;
  }

  static DowScopeSnapshot _scopeSnapshot({
    required DowStructureScope scope,
    required List<DowPivot> pivots,
    required DowStructureState state,
    required DowStructureEvent? latestEvent,
  }) {
    final highs = pivots.where((pivot) => pivot.kind == DowPivotKind.high);
    final lows = pivots.where((pivot) => pivot.kind == DowPivotKind.low);
    final latestHigh = highs.isEmpty ? null : highs.last;
    final latestLow = lows.isEmpty ? null : lows.last;
    final protected = switch (state) {
      DowStructureState.bullishContinuation => latestLow,
      DowStructureState.bearishContinuation => latestHigh,
      _ => null,
    };
    return DowScopeSnapshot(
      scope: scope,
      state: state,
      latestHigh: latestHigh,
      latestLow: latestLow,
      protectedPivot: protected,
      latestEvent: latestEvent,
    );
  }

  static double _atr(List<ChartCandle> candles) {
    if (candles.length < 2) return double.nan;
    final start = math.max(1, candles.length - 14);
    var total = 0.0;
    var count = 0;
    for (var index = start; index < candles.length; index++) {
      final candle = candles[index];
      final previousClose = candles[index - 1].close;
      final trueRange = math.max(
        candle.high - candle.low,
        math.max(
          (candle.high - previousClose).abs(),
          (candle.low - previousClose).abs(),
        ),
      );
      total += trueRange;
      count++;
    }
    return count == 0 ? double.nan : total / count;
  }

  static Duration _durationFor(String timeframe) => switch (timeframe) {
    '5m' => const Duration(minutes: 5),
    '15m' => const Duration(minutes: 15),
    '30m' => const Duration(minutes: 30),
    '1h' => const Duration(hours: 1),
    '4h' => const Duration(hours: 4),
    '1D' => const Duration(days: 1),
    _ => throw ArgumentError.value(timeframe, 'timeframe'),
  };
}

abstract final class DowStructuralAlignmentEngine {
  static const version = 'dow-structural-alignment/1.0';

  static DowStructuralAlignment evaluate({
    required DowStructureSnapshot snapshot,
    required ChartDirection candidateDirection,
    required bool trendContinuation,
    required bool rangeCompatible,
    required double entryPrice,
    required double invalidationPrice,
    required double? firstTargetPrice,
    ChartDirection? parentDirection,
    double cap = 20,
  }) {
    final reasons = <String>[...snapshot.reasonCodes, 'dow:alignment:$version'];
    if (!snapshot.valid) {
      reasons.add('dow:gate:untrusted_structure');
      return DowStructuralAlignment(
        version: version,
        score: 0,
        cap: cap,
        allowed: false,
        snapshot: snapshot,
        reasonCodes: reasons,
      );
    }

    var score = 0.0;
    var allowed = true;
    final external = snapshot.external;
    final internal = snapshot.internal;
    final expectedDirection = candidateDirection;

    if (trendContinuation) {
      if (expectedDirection == ChartDirection.sideways ||
          external.direction == ChartDirection.sideways) {
        allowed = false;
        reasons.add('dow:gate:trend_requires_external_continuation');
      } else if (external.direction != expectedDirection) {
        allowed = false;
        reasons.add('dow:gate:external_direction_conflict');
      } else {
        score += 8;
        reasons.add('dow:evidence:external_aligned');
      }
      if (internal.direction != ChartDirection.sideways &&
          internal.direction != expectedDirection) {
        allowed = false;
        reasons.add('dow:gate:internal_external_conflict');
      } else if (internal.direction == expectedDirection) {
        score += 4;
        reasons.add('dow:evidence:internal_aligned');
      }
    } else if (rangeCompatible) {
      final compatible =
          external.state == DowStructureState.range ||
          external.state == DowStructureState.transition;
      if (!compatible) {
        allowed = false;
        reasons.add('dow:gate:range_playbook_context_mismatch');
      } else {
        score += 6;
        reasons.add('dow:evidence:range_context');
      }
    }

    if (parentDirection != null && trendContinuation) {
      if (parentDirection == expectedDirection) {
        score += 3;
        reasons.add('dow:evidence:higher_timeframe_aligned');
      } else {
        allowed = false;
        reasons.add('dow:gate:higher_timeframe_conflict');
      }
    }

    final latestEvent = external.latestEvent ?? internal.latestEvent;
    if (latestEvent != null) {
      final alignedBos =
          (expectedDirection == ChartDirection.bullish &&
              latestEvent.type == DowStructureEventType.bosUp) ||
          (expectedDirection == ChartDirection.bearish &&
              latestEvent.type == DowStructureEventType.bosDown);
      final opposingChoch =
          (expectedDirection == ChartDirection.bullish &&
              latestEvent.type == DowStructureEventType.chochDown) ||
          (expectedDirection == ChartDirection.bearish &&
              latestEvent.type == DowStructureEventType.chochUp);
      if (alignedBos) {
        score += 3;
        reasons.add('dow:evidence:aligned_bos');
      }
      if (opposingChoch) {
        allowed = false;
        reasons.add('dow:gate:opposing_choch');
      }
    }

    final risk = (entryPrice - invalidationPrice).abs();
    if (risk.isFinite && risk > 0 && firstTargetPrice != null) {
      final reward = (firstTargetPrice - entryPrice).abs();
      final rr = reward / risk;
      if (rr >= 1.5) {
        score += 2;
        reasons.add('dow:evidence:room_to_target');
      } else {
        reasons.add('dow:penalty:limited_room_to_target');
      }
    }

    final protected = external.protectedPivot;
    if (protected != null) {
      final stopProtectsStructure = expectedDirection == ChartDirection.bullish
          ? invalidationPrice <= protected.price
          : expectedDirection == ChartDirection.bearish
          ? invalidationPrice >= protected.price
          : false;
      if (stopProtectsStructure) {
        score += 2;
        reasons.add('dow:evidence:structural_invalidation');
      } else if (trendContinuation) {
        reasons.add('dow:penalty:stop_inside_protected_structure');
      }
    }

    return DowStructuralAlignment(
      version: version,
      score: score,
      cap: cap,
      allowed: allowed,
      snapshot: snapshot,
      reasonCodes: reasons,
    );
  }
}
