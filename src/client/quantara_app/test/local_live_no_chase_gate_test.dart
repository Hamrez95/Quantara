import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/data/bitunix_order_book_top.dart';
import 'package:quantara_app/features/auto_trade/domain/execution_quality_models.dart';
import 'package:quantara_app/features/auto_trade/domain/local_live_no_chase_gate.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';

void main() {
  final now = DateTime.utc(2026, 8, 17, 12);
  const gate = LocalLiveNoChaseGate();

  test('long uses best ask against frozen entry upper boundary', () {
    final allowed = gate.evaluate(
      idea: _idea(
        direction: TradeDirection.long,
        candleClosedAt: now.subtract(const Duration(minutes: 5)),
      ),
      topOfBook: const BitunixOrderBookTop(bestBid: 99.8, bestAsk: 100.9),
      evaluatedAtUtc: now,
    );
    final rejected = gate.evaluate(
      idea: _idea(
        direction: TradeDirection.long,
        candleClosedAt: now.subtract(const Duration(minutes: 5)),
      ),
      topOfBook: const BitunixOrderBookTop(bestBid: 100.9, bestAsk: 101.1),
      evaluatedAtUtc: now,
    );

    expect(allowed.allowed, isTrue);
    expect(rejected.allowed, isFalse);
    expect(rejected.reason, NoChaseDecisionReason.priceBeyondBoundary);
  });

  test('short uses best bid against frozen entry lower boundary', () {
    final allowed = gate.evaluate(
      idea: _idea(
        direction: TradeDirection.short,
        candleClosedAt: now.subtract(const Duration(minutes: 5)),
      ),
      topOfBook: const BitunixOrderBookTop(bestBid: 99.1, bestAsk: 99.3),
      evaluatedAtUtc: now,
    );
    final rejected = gate.evaluate(
      idea: _idea(
        direction: TradeDirection.short,
        candleClosedAt: now.subtract(const Duration(minutes: 5)),
      ),
      topOfBook: const BitunixOrderBookTop(bestBid: 98.9, bestAsk: 99.1),
      evaluatedAtUtc: now,
    );

    expect(allowed.allowed, isTrue);
    expect(rejected.allowed, isFalse);
    expect(rejected.reason, NoChaseDecisionReason.priceBeyondBoundary);
  });

  test('expired frozen intent is rejected even at an acceptable price', () {
    final decision = gate.evaluate(
      idea: _idea(
        direction: TradeDirection.long,
        candleClosedAt: now.subtract(const Duration(hours: 4)),
      ),
      topOfBook: const BitunixOrderBookTop(bestBid: 99.8, bestAsk: 100.2),
      evaluatedAtUtc: now,
    );

    expect(decision.allowed, isFalse);
    expect(decision.reason, NoChaseDecisionReason.staleIntent);
  });

  test('non-actionable or incomplete idea fails closed', () {
    expect(
      () => gate.evaluate(
        idea: _idea(
          direction: TradeDirection.wait,
          candleClosedAt: now,
          entryLower: null,
          entryUpper: null,
        ),
        topOfBook: const BitunixOrderBookTop(bestBid: 99.8, bestAsk: 100.2),
        evaluatedAtUtc: now,
      ),
      throwsFormatException,
    );
  });
}

TradeIdea _idea({
  required TradeDirection direction,
  required DateTime candleClosedAt,
  double? entryLower = 99,
  double? entryUpper = 101,
}) => TradeIdea(
  symbol: 'BTCUSDT',
  timeframe: '1h',
  direction: direction,
  confidencePercent: 80,
  entryLower: entryLower,
  entryUpper: entryUpper,
  stopLoss: direction == TradeDirection.short ? 103 : 97,
  targets: const [104, 106, 108],
  riskReward: 2,
  maximumLoss: 10,
  positionSize: 1,
  notionalValue: 100,
  recommendedLeverage: 3,
  maximumSafeLeverage: 5,
  requiredMargin: 33.34,
  estimatedRoundTripCosts: 0.2,
  setupId: 'setup-1',
  candleClosedAt: candleClosedAt,
  summary: 'test',
  invalidation: 'test',
  reasons: const ['test'],
);
