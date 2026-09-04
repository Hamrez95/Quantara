import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/owner_alpha/domain/strategy_evaluation_trade_replay.dart';

void main() {
  StrategyEvaluationTradeReplay replay() => StrategyEvaluationTradeReplay(
    evaluationRunId: 'run-1',
    tradeId: 'trade-1',
    strategyId: 'structure_zones',
    strategyVersion: '1.2.3',
    snapshotHash: 'sha256-snapshot',
    symbol: 'BTCUSDT',
    timeframe: '15m',
    events: <StrategyEvaluationReplayEvent>[
      StrategyEvaluationReplayEvent(
        type: StrategyEvaluationReplayEventType.finalClose,
        timestampUtc: DateTime.utc(2026, 8, 1, 3),
        price: 104,
        reasonCode: 'tp2',
      ),
      StrategyEvaluationReplayEvent(
        type: StrategyEvaluationReplayEventType.signalDetected,
        timestampUtc: DateTime.utc(2026, 8, 1),
        price: 100,
      ),
      StrategyEvaluationReplayEvent(
        type: StrategyEvaluationReplayEventType.initialStop,
        timestampUtc: DateTime.utc(2026, 8, 1, 0, 1),
        price: 98,
      ),
      StrategyEvaluationReplayEvent(
        type: StrategyEvaluationReplayEventType.takeProfit1,
        timestampUtc: DateTime.utc(2026, 8, 1, 0, 1),
        price: 103,
      ),
      StrategyEvaluationReplayEvent(
        type: StrategyEvaluationReplayEventType.actualFill,
        timestampUtc: DateTime.utc(2026, 8, 1, 1),
        price: 101,
        quantity: 0.2,
      ),
      StrategyEvaluationReplayEvent(
        type: StrategyEvaluationReplayEventType.partialExit,
        timestampUtc: DateTime.utc(2026, 8, 1, 2),
        price: 103,
        quantity: 0.1,
      ),
    ],
  );

  test('replay sorts immutable lifecycle facts deterministically', () {
    final value = replay();

    expect(value.events.first.type, StrategyEvaluationReplayEventType.signalDetected);
    expect(value.events.last.type, StrategyEvaluationReplayEventType.finalClose);
    expect(value.evaluationRunId, 'run-1');
    expect(value.strategyVersion, '1.2.3');
    expect(value.snapshotHash, 'sha256-snapshot');
    expect(value.grantsLocalLiveAuthority, isFalse);
  });

  test('Replay to entry hides future outcome until explicitly revealed', () {
    final value = replay();

    final hidden = value.visibleEvents(revealOutcome: false);
    final revealed = value.visibleEvents(revealOutcome: true);

    expect(
      hidden.any(
        (event) => event.type == StrategyEvaluationReplayEventType.partialExit,
      ),
      isFalse,
    );
    expect(
      hidden.any(
        (event) => event.type == StrategyEvaluationReplayEventType.finalClose,
      ),
      isFalse,
    );
    expect(
      hidden.last.type,
      StrategyEvaluationReplayEventType.actualFill,
    );
    expect(revealed.length, value.events.length);
  });

  test('missing candle history is explicit and never fabricates coverage', () {
    final requestedStart = DateTime.utc(2026, 8, 1);
    final requestedEnd = DateTime.utc(2026, 8, 2);
    final missing = StrategyEvaluationReplayCandleCoverage.failure(
      requestedStartUtc: requestedStart,
      requestedEndUtc: requestedEnd,
      reason: 'historical_candles_unavailable',
    );
    final partial = StrategyEvaluationReplayCandleCoverage.success(
      requestedStartUtc: requestedStart,
      requestedEndUtc: requestedEnd,
      coveredStartUtc: requestedStart.add(const Duration(hours: 1)),
      coveredEndUtc: requestedEnd,
    );

    expect(missing.succeeded, isFalse);
    expect(missing.fullyCovered, isFalse);
    expect(missing.failureReason, 'historical_candles_unavailable');
    expect(partial.succeeded, isTrue);
    expect(partial.fullyCovered, isFalse);
  });
}
