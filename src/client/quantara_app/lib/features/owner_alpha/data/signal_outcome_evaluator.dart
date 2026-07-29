import '../../market_analysis/domain/market_chart_models.dart';
import '../domain/owner_alpha_models.dart';

/// Replays closed candles after a signal was created.
///
/// If a candle touches both the stop and a target, the stop wins. OHLC data
/// cannot prove the intrabar order, so the conservative result avoids
/// overstating performance.
abstract final class SignalOutcomeEvaluator {
  static SignalJournalEntry evaluate({
    required SignalJournalEntry entry,
    required Iterable<ChartCandle> candles,
    required DateTime evaluatedAt,
  }) {
    if (entry.hasTerminalOutcome || entry.closed) return entry;
    if (entry.entryLower == null ||
        entry.entryUpper == null ||
        entry.stopLoss == null ||
        entry.targets.length != 3 ||
        entry.positionSize <= 0 ||
        entry.notionalValue <= 0) {
      return entry;
    }

    var active = entry.activatedAt != null;
    var activatedAt = entry.activatedAt;
    var highestTarget = entry.highestTargetHit;
    var latest = entry;
    final replayFrom =
        entry.resolvedAt ?? entry.activatedAt ?? entry.createdAt;

    for (final candle in candles) {
      if (candle.openTime.isBefore(replayFrom)) continue;
      if (!active && !candle.openTime.isBefore(entry.validUntil)) break;

      if (!active) {
        final touchesEntry =
            candle.low <= entry.entryUpper! &&
            candle.high >= entry.entryLower!;
        if (!touchesEntry) continue;
        active = true;
        activatedAt = candle.openTime;
      }

      final stopHit = entry.direction == TradeDirection.long
          ? candle.low <= entry.stopLoss!
          : candle.high >= entry.stopLoss!;
      if (stopHit) {
        return _withResult(
          entry: latest,
          outcome: SignalOutcome.stopped,
          exitPrice: entry.stopLoss!,
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
          activatedAt: activatedAt,
        );
      }
    }

    if (!active && !evaluatedAt.toUtc().isBefore(entry.validUntil)) {
      return entry.copyWith(
        outcome: SignalOutcome.expiredUntriggered,
        resolvedAt: entry.validUntil,
      );
    }
    return latest;
  }

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
    final direction = entry.direction == TradeDirection.long ? 1.0 : -1.0;
    var effectiveExit = exitPrice;
    var grossPnl =
        (exitPrice - referenceEntry) * entry.positionSize * direction;

    // When price reaches one or more targets and later stops, model equal
    // one-third scale-outs at the reached targets and send only the remaining
    // size to the stop. This avoids reporting the whole position as a stop
    // after the journal already recorded TP1/TP2.
    if (outcome == SignalOutcome.stopped && highestTarget > 0) {
      final trancheSize = entry.positionSize / entry.targets.length;
      final realizedTargets = entry.targets
          .take(highestTarget)
          .fold<double>(
            0,
            (sum, target) =>
                sum + (target - referenceEntry) * trancheSize * direction,
          );
      final remainingSize =
          entry.positionSize - trancheSize * highestTarget;
      final stoppedRemainder =
          (entry.stopLoss! - referenceEntry) * remainingSize * direction;
      grossPnl = realizedTargets + stoppedRemainder;
      effectiveExit =
          referenceEntry + grossPnl / entry.positionSize * direction;
    }
    final priceChange =
        ((effectiveExit - referenceEntry) / referenceEntry) *
        direction *
        100;
    final netPnl = grossPnl - entry.estimatedRoundTripCosts;
    final marginReturn = entry.selectedMargin <= 0
        ? 0.0
        : netPnl / entry.selectedMargin * 100;
    return entry.copyWith(
      outcome: outcome,
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
