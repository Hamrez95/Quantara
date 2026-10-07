import '../../market_analysis/domain/market_chart_models.dart';
import '../domain/owner_alpha_models.dart';
import '../domain/profit_protection_policy.dart';

/// Replays closed candles after a signal was created.
///
/// If a candle touches both the active stop and a target, the stop wins. OHLC
/// data cannot prove the intrabar order, so the conservative result avoids
/// overstating performance.
abstract final class SignalOutcomeEvaluator {
  static const version = 'closed-candle-replay/2';
  static const _costBuffer = 0.0017;

  static SignalJournalEntry evaluate({
    required SignalJournalEntry entry,
    required Iterable<ChartCandle> candles,
    required DateTime evaluatedAt,
  }) {
    if (entry.hasTerminalOutcome || entry.closed) return entry;
    if (!_hasValidFinancialInputs(entry)) return entry;

    final candleDuration = _candleDuration(entry.timeframe);
    if (candleDuration == null) return entry;
    final evaluationTime = evaluatedAt.toUtc();
    var active = entry.activatedAt != null;
    var activatedAt = entry.activatedAt;
    var highestTarget = entry.highestTargetHit;
    var latest = entry;
    final replayFrom = entry.resolvedAt ?? entry.activatedAt ?? entry.createdAt;

    for (final candle in candles) {
      if (!_validCandle(candle)) continue;
      if (candle.openTime.add(candleDuration).isAfter(evaluationTime)) continue;
      if (candle.openTime.isBefore(replayFrom)) continue;
      // A TP raised the stop only after this candle. Replaying that same
      // candle against the raised stop fabricates an earlier stop-out.
      if (entry.resolvedAt != null &&
          !candle.openTime.isAfter(entry.resolvedAt!)) {
        continue;
      }
      if (!active && !candle.openTime.isBefore(entry.validUntil)) break;

      if (!active) {
        final touchesEntry =
            candle.low <= entry.entryUpper! && candle.high >= entry.entryLower!;
        if (!touchesEntry) continue;
        active = true;
        activatedAt = candle.openTime;
      }

      final activeStop = _activeStop(entry, highestTarget);
      final stopHit = entry.direction == TradeDirection.long
          ? candle.low <= activeStop
          : candle.high >= activeStop;
      if (stopHit) {
        return _withResult(
          entry: latest,
          outcome: SignalOutcome.stopped,
          exitPrice: activeStop,
          eventAt: candle.openTime,
          activatedAt: activatedAt,
          highestTarget: highestTarget,
        );
      }

      var candleTarget = highestTarget;
      for (var index = 0; index < entry.targets.length; index++) {
        final hit = entry.direction == TradeDirection.long
            ? candle.high >= entry.targets[index]
            : candle.low <= entry.targets[index];
        if (hit) candleTarget = index + 1;
      }
      if (candleTarget > highestTarget) {
        highestTarget = candleTarget;
        latest = _withResult(
          entry: latest,
          outcome: _targetOutcome(highestTarget),
          exitPrice: entry.targets[highestTarget - 1],
          eventAt: candle.openTime,
          activatedAt: activatedAt,
          highestTarget: highestTarget,
        );
        if (highestTarget == 3) return latest;
      } else if (latest.outcome == SignalOutcome.pendingEntry) {
        latest = latest.copyWith(
          outcome: SignalOutcome.active,
          outcomeEvaluationVersion: version,
          activatedAt: activatedAt,
        );
      }
    }

    if (!active && !evaluatedAt.toUtc().isBefore(entry.validUntil)) {
      return entry.copyWith(
        outcome: SignalOutcome.expiredUntriggered,
        outcomeEvaluationVersion: version,
        resolvedAt: entry.validUntil,
      );
    }
    return latest;
  }

  static Duration? _candleDuration(String timeframe) => switch (timeframe) {
    '1m' => const Duration(minutes: 1),
    '5m' => const Duration(minutes: 5),
    '15m' => const Duration(minutes: 15),
    '30m' => const Duration(minutes: 30),
    '1h' => const Duration(hours: 1),
    '4h' => const Duration(hours: 4),
    '1D' || '1d' => const Duration(days: 1),
    _ => null,
  };

  static double _activeStop(SignalJournalEntry entry, int highestTarget) {
    if (highestTarget >= 2) return entry.targets.first;
    if (highestTarget >= 1) {
      final referenceEntry = entry.direction == TradeDirection.long
          ? entry.entryUpper!
          : entry.entryLower!;
      return entry.direction == TradeDirection.long
          ? referenceEntry * (1 + _costBuffer)
          : referenceEntry * (1 - _costBuffer);
    }
    return entry.stopLoss!;
  }

  static bool _hasValidFinancialInputs(SignalJournalEntry entry) {
    final entryLower = entry.entryLower;
    final entryUpper = entry.entryUpper;
    final stopLoss = entry.stopLoss;
    if (entryLower == null ||
        entryUpper == null ||
        stopLoss == null ||
        !entryLower.isFinite ||
        !entryUpper.isFinite ||
        !stopLoss.isFinite ||
        entryLower <= 0 ||
        entryUpper <= 0 ||
        stopLoss <= 0 ||
        entryLower > entryUpper ||
        entry.targets.length != 3 ||
        entry.targets.any((value) => !value.isFinite || value <= 0) ||
        !entry.positionSize.isFinite ||
        entry.positionSize <= 0 ||
        !entry.notionalValue.isFinite ||
        entry.notionalValue <= 0 ||
        !entry.estimatedRoundTripCosts.isFinite ||
        entry.estimatedRoundTripCosts < 0 ||
        entry.selectedLeverage < 1) {
      return false;
    }
    return true;
  }

  static bool _validCandle(ChartCandle candle) =>
      candle.open.isFinite &&
      candle.high.isFinite &&
      candle.low.isFinite &&
      candle.close.isFinite &&
      candle.open > 0 &&
      candle.high > 0 &&
      candle.low > 0 &&
      candle.close > 0 &&
      candle.high >= candle.low;

  static SignalJournalEntry _withResult({
    required SignalJournalEntry entry,
    required SignalOutcome outcome,
    required double exitPrice,
    required DateTime eventAt,
    required DateTime? activatedAt,
    required int highestTarget,
  }) {
    // Use the least favorable edge of the entry zone. This keeps the paper
    // result conservative instead of assuming a perfect midpoint fill.
    final referenceEntry = entry.direction == TradeDirection.long
        ? entry.entryUpper!
        : entry.entryLower!;
    if (!referenceEntry.isFinite ||
        referenceEntry <= 0 ||
        !exitPrice.isFinite ||
        exitPrice <= 0) {
      return entry.copyWith(
        outcome: outcome,
        outcomeEvaluationVersion: version,
        highestTargetHit: highestTarget,
        activatedAt: activatedAt,
        resolvedAt: eventAt,
      );
    }

    final direction = entry.direction == TradeDirection.long ? 1.0 : -1.0;
    final targetFractions = ProfitProtectionPolicy.forJournal(
      entry,
    ).targetFractions;
    final reachedTargets = highestTarget
        .clamp(0, targetFractions.length)
        .toInt();
    var realizedSize = 0.0;
    var grossPnl = 0.0;

    for (var index = 0; index < reachedTargets; index++) {
      final trancheSize = entry.positionSize * targetFractions[index];
      realizedSize += trancheSize;
      grossPnl +=
          (entry.targets[index] - referenceEntry) * trancheSize * direction;
    }

    // TP1 realizes the largest tranche. The remainder is protected beyond
    // break-even after TP1 and at TP1 after TP2, matching Local Live.
    final remainingSize = (entry.positionSize - realizedSize)
        .clamp(0, entry.positionSize)
        .toDouble();
    grossPnl += (exitPrice - referenceEntry) * remainingSize * direction;
    final effectiveExit =
        referenceEntry + grossPnl / entry.positionSize * direction;
    final priceChange =
        ((effectiveExit - referenceEntry) / referenceEntry) * direction * 100;
    final netPnl = grossPnl - entry.estimatedRoundTripCosts;
    final selectedMargin = entry.selectedMargin;
    final marginReturn = selectedMargin <= 0 || !selectedMargin.isFinite
        ? 0.0
        : netPnl / selectedMargin * 100;

    if (!effectiveExit.isFinite ||
        !grossPnl.isFinite ||
        !priceChange.isFinite ||
        !netPnl.isFinite ||
        !marginReturn.isFinite) {
      return entry.copyWith(
        outcome: outcome,
        outcomeEvaluationVersion: version,
        highestTargetHit: highestTarget,
        activatedAt: activatedAt,
        resolvedAt: eventAt,
      );
    }

    return entry.copyWith(
      outcome: outcome,
      outcomeEvaluationVersion: version,
      highestTargetHit: highestTarget,
      activatedAt: activatedAt,
      resolvedAt: eventAt,
      priceChangePercent: priceChange,
      simulatedPnl: netPnl,
      marginReturnPercent: marginReturn,
    );
  }

  static SignalOutcome _targetOutcome(int target) => switch (target) {
    1 => SignalOutcome.tp1,
    2 => SignalOutcome.tp2,
    _ => SignalOutcome.tp3,
  };
}
