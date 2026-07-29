import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';

void main() {
  test('manual leverage changes margin without changing planned risk', () {
    final idea = TradeIdea(
      symbol: 'BTCUSDT',
      timeframe: '1h',
      direction: TradeDirection.long,
      confidencePercent: 80,
      entryLower: 99,
      entryUpper: 100,
      stopLoss: 95,
      targets: const [105, 110, 115],
      riskReward: 1.5,
      maximumLoss: 100,
      positionSize: 10,
      notionalValue: 10000,
      recommendedLeverage: 5,
      maximumSafeLeverage: 8,
      requiredMargin: 2000,
      estimatedRoundTripCosts: 5,
      setupId: 'manual-leverage-test',
      candleClosedAt: DateTime.utc(2026, 1, 1),
      summary: 'test',
      invalidation: 'test',
      reasons: const ['test'],
    );

    expect(idea.marginAt(5), 2000);
    expect(idea.marginAt(50), 200);
    expect(idea.marginAt(125), 80);
    expect(idea.marginAt(126), isNull);
    expect(idea.notionalValue, 10000);
    expect(idea.maximumLoss, 100);
  });
}
