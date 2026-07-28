import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';

void main() {
  final closedAt = DateTime.utc(2026, 7, 28, 8);
  final idea = TradeIdea(
    symbol: 'BTCUSDT',
    timeframe: '1h',
    direction: TradeDirection.long,
    confidencePercent: 70,
    entryLower: 100,
    entryUpper: 101,
    stopLoss: 98,
    targets: const [104, 106, 108],
    riskReward: 1.8,
    maximumLoss: 10,
    positionSize: 1,
    notionalValue: 100,
    recommendedLeverage: 2,
    requiredMargin: 50,
    estimatedRoundTripCosts: 0.2,
    setupId: 'BTCUSDT|1h|long|fixture',
    candleClosedAt: closedAt,
    summary: 'fixture',
    invalidation: 'close below support',
    reasons: const ['fixture'],
    strategy: AnalysisStrategy.trendPullback,
    strategyVersion: 'trend-pullback/1.0',
  );

  test('derives a bounded validity window from the candle close', () {
    expect(idea.createdAt, closedAt);
    expect(idea.validUntil, DateTime.utc(2026, 7, 28, 11));
    expect(idea.isExpiredAt(DateTime.utc(2026, 7, 28, 10, 59)), isFalse);
    expect(idea.isExpiredAt(DateTime.utc(2026, 7, 28, 11)), isTrue);
  });

  test('journal survives serialization and exposes lifecycle', () {
    final original = SignalJournalEntry.fromIdea(idea).copyWith(
      note: 'entered after retest',
    );
    final restored = SignalJournalEntry.tryFromJson(original.toJson());

    expect(restored, isNotNull);
    expect(restored!.setupId, original.setupId);
    expect(restored.note, 'entered after retest');
    expect(restored.strategy, AnalysisStrategy.trendPullback);
    expect(
      restored.lifecycle(
        DateTime.utc(2026, 7, 28, 10, 30),
        taken: false,
      ),
      SignalLifecycle.expiring,
    );
    expect(
      restored.lifecycle(DateTime.utc(2026, 7, 28, 12), taken: true),
      SignalLifecycle.taken,
    );
    expect(
      restored.copyWith(closed: true).lifecycle(
            DateTime.utc(2026, 7, 28, 9),
            taken: true,
          ),
      SignalLifecycle.closed,
    );
  });
}
