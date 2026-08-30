import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/owner_alpha/data/realtime_candidate_engine.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/realtime_candidate_models.dart';

void main() {
  test('stale price and structure cannot invalidate a live candidate', () {
    final idea = TradeIdea(
      symbol: 'BTCUSDT',
      timeframe: '1h',
      direction: TradeDirection.long,
      confidencePercent: 60,
      entryLower: 100,
      entryUpper: 101,
      stopLoss: 98,
      targets: const [102, 104, 106],
      riskReward: 2,
      maximumLoss: 50,
      positionSize: 1,
      notionalValue: 100,
      recommendedLeverage: 2,
      maximumSafeLeverage: 5,
      requiredMargin: 50,
      estimatedRoundTripCosts: 0.2,
      setupId: 'BTCUSDT|1h|long|stale-safety',
      candleClosedAt: DateTime.utc(2026, 8, 2, 12),
      summary: 'test setup',
      invalidation: 'test invalidation',
      reasons: const ['test'],
      strategy: AnalysisStrategy.structureZones,
      strategyVersion: 'candidate-foundation/1.0',
    );
    final candidate = RealtimeOpportunityCandidate.fromIdea(
      idea,
      detectedAtUtc: DateTime.utc(2026, 8, 2, 12, 1),
    );

    final result = RealtimeCandidateEngine.evaluate(
      candidate: candidate,
      observation: RealtimeMarketObservation(
        exchangeTimestampUtc: DateTime.utc(2026, 8, 2, 12, 2),
        receivedAtUtc: DateTime.utc(2026, 8, 2, 12, 2, 1),
        evaluatedAtUtc: DateTime.utc(2026, 8, 2, 12, 2, 10),
        lastPrice: 97,
        qualityScore: 90,
        structureValid: false,
        triggerConfirmed: true,
        triggerCandleClosed: true,
      ),
    );

    expect(result.candidate.stage, OpportunityStage.detected);
    expect(
      result.candidate.transitionReason,
      OpportunityTransitionReason.dataStale,
    );
    expect(result.candidate.resolvedAtUtc, isNull);
  });
}
