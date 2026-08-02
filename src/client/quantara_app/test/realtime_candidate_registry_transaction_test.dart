import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/owner_alpha/data/realtime_candidate_registry.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/realtime_candidate_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/realtime_market_event_models.dart';

void main() {
  group('RealtimeCandidateRegistry transaction', () {
    test('prepare is side-effect free and commit applies exactly once', () {
      final registry = RealtimeCandidateRegistry();
      final candidate = _candidate();
      registry.register(candidate);
      final revisionBefore = registry.revisionFor(candidate.setupId);

      final prepared = registry.prepare(_envelope());

      expect(prepared.requiresCommit, isTrue);
      expect(prepared.update.candidate?.stage, OpportunityStage.armed);
      expect(registry.revisionFor(candidate.setupId), revisionBefore);
      expect(
        registry.candidateFor(candidate.setupId)?.stage,
        OpportunityStage.detected,
      );

      final committed = registry.commit(prepared);
      expect(committed.candidate?.stage, OpportunityStage.armed);
      expect(registry.revisionFor(candidate.setupId), revisionBefore + 1);
      expect(
        registry.candidateFor(candidate.setupId)?.stage,
        OpportunityStage.armed,
      );
      expect(() => registry.commit(prepared), throwsStateError);
    });

    test('same-candidate reconciliation invalidates a stale preparation', () {
      final registry = RealtimeCandidateRegistry();
      final candidate = _candidate();
      registry.register(candidate);
      final prepared = registry.prepare(_envelope());

      registry.markReconciled(
        setupId: candidate.setupId,
        streamKey: RealtimeStreamKey(
          symbol: candidate.symbol,
          timeframe: candidate.timeframe,
        ),
        exchangeTimestampUtc: DateTime.utc(2026, 8, 2, 12, 2),
        sequence: 1,
      );

      expect(() => registry.commit(prepared), throwsStateError);
      expect(
        registry.candidateFor(candidate.setupId)?.stage,
        OpportunityStage.detected,
      );
    });

    test('independent candidate changes do not invalidate preparation', () {
      final registry = RealtimeCandidateRegistry();
      final candidate = _candidate();
      registry.register(candidate);
      final prepared = registry.prepare(_envelope());

      registry.register(_candidate(setupId: 'BTCUSDT|1h|long|second'));

      expect(
        registry.commit(prepared).candidate?.stage,
        OpportunityStage.armed,
      );
    });

    test('rejected preparation needs no commit and preserves state', () {
      final registry = RealtimeCandidateRegistry();
      final candidate = _candidate();
      registry.register(candidate);

      final prepared = registry.prepare(
        RealtimeObservationEnvelope(
          eventId: 'wrong-symbol',
          setupId: candidate.setupId,
          symbol: 'ETHUSDT',
          timeframe: candidate.timeframe,
          sequence: 1,
          observation: _observation(),
        ),
      );

      expect(prepared.requiresCommit, isFalse);
      expect(
        prepared.update.disposition,
        StreamEventDisposition.identityMismatch,
      );
      expect(registry.commit(prepared), same(prepared.update));
      expect(
        registry.candidateFor(candidate.setupId)?.stage,
        OpportunityStage.detected,
      );
    });

    test('legacy apply keeps atomic behavior for non-durable callers', () {
      final registry = RealtimeCandidateRegistry();
      final candidate = _candidate();
      registry.register(candidate);

      final update = registry.apply(_envelope());

      expect(update.disposition, StreamEventDisposition.accepted);
      expect(update.candidate?.stage, OpportunityStage.armed);
      expect(
        registry.candidateFor(candidate.setupId)?.stage,
        OpportunityStage.armed,
      );
    });
  });
}

RealtimeOpportunityCandidate _candidate({
  String setupId = 'BTCUSDT|1h|long|transaction',
}) => RealtimeOpportunityCandidate.fromIdea(
  TradeIdea(
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
    setupId: setupId,
    candleClosedAt: DateTime.utc(2026, 8, 2, 12),
    summary: 'test setup',
    invalidation: 'test invalidation',
    reasons: const ['test'],
    strategy: AnalysisStrategy.structureZones,
    strategyVersion: 'candidate-transaction/1.0',
  ),
  detectedAtUtc: DateTime.utc(2026, 8, 2, 12, 1),
);

RealtimeObservationEnvelope _envelope() => RealtimeObservationEnvelope(
  eventId: 'event-1',
  setupId: 'BTCUSDT|1h|long|transaction',
  symbol: 'BTCUSDT',
  timeframe: '1h',
  sequence: 1,
  observation: _observation(),
);

RealtimeMarketObservation _observation() => RealtimeMarketObservation(
  exchangeTimestampUtc: DateTime.utc(2026, 8, 2, 12, 2),
  receivedAtUtc: DateTime.utc(2026, 8, 2, 12, 2, 0, 200),
  evaluatedAtUtc: DateTime.utc(2026, 8, 2, 12, 2, 1),
  lastPrice: 99.7,
  qualityScore: 70,
  structureValid: true,
  triggerConfirmed: false,
  triggerCandleClosed: false,
);
