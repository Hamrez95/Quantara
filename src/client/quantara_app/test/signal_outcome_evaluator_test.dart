import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/market_analysis/domain/market_chart_models.dart';
import 'package:quantara_app/features/owner_alpha/data/signal_outcome_evaluator.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';

void main() {
  test('tracks an untaken long signal through TP2', () {
    final entry = _entry();
    final result = SignalOutcomeEvaluator.evaluate(
      entry: entry,
      candles: [
        _candle(minutes: 0, low: 99.5, high: 101),
        _candle(minutes: 15, low: 100.5, high: 104.5),
      ],
      evaluatedAt: _origin.add(const Duration(minutes: 30)),
    );

    expect(result.outcome, SignalOutcome.tp2);
    expect(result.highestTargetHit, 2);
    expect(result.simulatedPnl, greaterThan(0));
    expect(result.marginReturnPercent, greaterThan(result.priceChangePercent!));
  });

  test('uses stop-first when one candle touches stop and target', () {
    final result = SignalOutcomeEvaluator.evaluate(
      entry: _entry(),
      candles: [_candle(minutes: 0, low: 97, high: 103)],
      evaluatedAt: _origin.add(const Duration(minutes: 15)),
    );

    expect(result.outcome, SignalOutcome.stopped);
    expect(result.highestTargetHit, 0);
    expect(result.simulatedPnl, lessThan(0));
  });

  test('evaluates short targets in the opposite price direction', () {
    final result = SignalOutcomeEvaluator.evaluate(
      entry: _entry(direction: TradeDirection.short),
      candles: [
        _candle(minutes: 0, low: 99, high: 100.5),
        _candle(minutes: 15, low: 95.5, high: 99),
      ],
      evaluatedAt: _origin.add(const Duration(minutes: 30)),
    );

    expect(result.outcome, SignalOutcome.tp2);
    expect(result.priceChangePercent, greaterThan(0));
  });

  test('keeps realized target profit when the remainder later stops', () {
    final afterTp2 = SignalOutcomeEvaluator.evaluate(
      entry: _entry(),
      candles: [
        _candle(minutes: 0, low: 99.5, high: 101),
        _candle(minutes: 15, low: 100.5, high: 104.5),
      ],
      evaluatedAt: _origin.add(const Duration(minutes: 30)),
    );
    final stopped = SignalOutcomeEvaluator.evaluate(
      entry: afterTp2,
      candles: [_candle(minutes: 30, low: 97.5, high: 101)],
      evaluatedAt: _origin.add(const Duration(minutes: 45)),
    );

    expect(stopped.outcome, SignalOutcome.stopped);
    expect(stopped.highestTargetHit, 2);
    expect(stopped.simulatedPnl, greaterThan(0));
  });
}

final _origin = DateTime.utc(2026, 7, 29, 10);

SignalJournalEntry _entry({
  TradeDirection direction = TradeDirection.long,
}) {
  final long = direction == TradeDirection.long;
  return SignalJournalEntry(
    setupId: 'BTCUSDT|15m|${direction.name}|test',
    symbol: 'BTCUSDT',
    timeframe: '15m',
    direction: direction,
    strategy: AnalysisStrategy.structureZones,
    strategyVersion: 'test/1',
    createdAt: _origin,
    validUntil: _origin.add(const Duration(minutes: 45)),
    entryLower: 99.5,
    entryUpper: 100.5,
    stopLoss: long ? 98 : 102,
    targets: long ? const [102, 104, 106] : const [98, 96, 94],
    maximumLoss: 10,
    positionSize: 5,
    notionalValue: 500,
    estimatedRoundTripCosts: 1,
    recommendedLeverage: 5,
    maximumSafeLeverage: 8,
    selectedLeverage: 5,
    summary: 'test',
    invalidation: 'test',
  );
}

ChartCandle _candle({
  required int minutes,
  required double low,
  required double high,
}) {
  return ChartCandle(
    openTime: _origin.add(Duration(minutes: minutes)),
    open: (low + high) / 2,
    high: high,
    low: low,
    close: (low + high) / 2,
    volume: 10,
  );
}
