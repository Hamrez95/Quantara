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
    if (!_hasValidFinancialInputs(entry)) return entry;

    var active = entry.activatedAt != null;
    var activatedAt = entry.activatedAt;
    var highestTarget = entry.highestTargetHit;
    var latest = entry;
    final replayFrom = entry.resolvedAt ?? entry.activatedAt ?? entry.createdAt;

    for (final candle in candles) {
      if (!_validCandle(candle)) continue;
      if (candle.openTime.isBefore(replayFrom)) continue;
      if (!active && !candle.openTime.isBefore(entry.validUntil)) break;

      if (!active) {
        final touchesEntry =
            candle.low <= entry.entryUpper! && candle.high >= entry.entryLower!;
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
        highestTargetHit: highestTarget,
        activatedAt: activatedAt,
        resolvedAt: eventAt,
      );
    }

    final direction = entry.direction == TradeDirection.long ? 1.0 : -1.0;
    const targetFractions = <double>[0.40, 0.30, 0.30];
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

    // A target event marks the still-open remainder at the latest reached
    // target. A later stop sends only that remainder to the original stop.
    // This preserves the documented 40% / 30% / 30% paper-management policy
    // without pretending that the entire position exited at TP2 or TP3.
    final remainingSize = (entry.positionSize - realizedSize)
        .clamp(0, entry.positionSize)
        .toDouble();
    final remainingExit = outcome == SignalOutcome.stopped
        ? entry.stopLoss!
        : exitPrice;
    grossPnl += (remainingExit - referenceEntry) * remainingSize * direction;
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
        highestTargetHit: highestTarget,
        activatedAt: activatedAt,
        resolvedAt: eventAt,
      );
    }

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
