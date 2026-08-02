import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/realtime_candidate_models.dart';

void main() {
  test('supported realtime timeframes retain three closed candles', () {
    final closedAt = DateTime.utc(2026, 8, 2, 12);
    const windows = <String, Duration>{
      '5m': Duration(minutes: 15),
      '15m': Duration(minutes: 45),
      '1h': Duration(hours: 3),
      '4h': Duration(hours: 12),
      '1D': Duration(days: 3),
    };

    for (final entry in windows.entries) {
      final idea = _idea(timeframe: entry.key, closedAt: closedAt);

      expect(idea.validityWindow, entry.value);
      expect(idea.validUntil, closedAt.add(entry.value));
    }
  });

  test('a 5m candidate can be detected after its candle closes', () {
    final closedAt = DateTime.utc(2026, 8, 2, 12);
    final detectedAt = DateTime.utc(2026, 8, 2, 12, 6);

    final candidate = RealtimeOpportunityCandidate.fromIdea(
      _idea(timeframe: '5m', closedAt: closedAt),
      detectedAtUtc: detectedAt,
    );

    expect(candidate.detectedAtUtc, detectedAt);
    expect(candidate.validUntilUtc, DateTime.utc(2026, 8, 2, 12, 15));
  });
}

TradeIdea _idea({required String timeframe, required DateTime closedAt}) =>
    TradeIdea(
      symbol: 'BTCUSDT',
      timeframe: timeframe,
      direction: TradeDirection.long,
      confidencePercent: 85,
      entryLower: 100,
      entryUpper: 103,
      stopLoss: 98,
      targets: const [106, 109],
      riskReward: 2,
      maximumLoss: 5,
      positionSize: 1,
      notionalValue: 102,
      recommendedLeverage: 1,
      maximumSafeLeverage: 3,
      requiredMargin: 102,
      estimatedRoundTripCosts: 0.1,
      setupId: 'validity-$timeframe',
      candleClosedAt: closedAt,
      summary: 'validity fixture',
      invalidation: 'below structure',
      reasons: const ['closed trigger'],
    );
