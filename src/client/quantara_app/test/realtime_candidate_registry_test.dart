import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/owner_alpha/data/realtime_candidate_registry.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/realtime_candidate_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/realtime_market_event_models.dart';

void main() {
  group('RealtimeCandidateRegistry', () {
    test(
      'registers identical candidates idempotently and rejects conflict',
      () {
        final registry = RealtimeCandidateRegistry();
        final candidate = _candidate();

        expect(
          registry.register(candidate).disposition,
          CandidateRegistrationDisposition.registered,
        );
        expect(
          registry.register(candidate).disposition,
          CandidateRegistrationDisposition.alreadyRegistered,
        );
        expect(
          registry.register(_candidate(entryLower: 99.5)).disposition,
          CandidateRegistrationDisposition.conflict,
        );
        expect(registry.candidateCount, 1);
      },
    );

    test('accepts an ordered event and publishes an auditable transition', () {
      final registry = RealtimeCandidateRegistry();
      final candidate = _candidate();
      registry.register(candidate);

      final update = registry.apply(
        _envelope(
          eventId: 'event-1',
          sequence: 1,
          minute: 2,
          price: 99.7,
          qualityScore: 70,
        ),
      );

      expect(update.accepted, isTrue);
      expect(update.candidate?.stage, OpportunityStage.armed);
      expect(update.evaluation?.stageChanged, isTrue);
      expect(update.auditEvent.auditSequence, 1);
      expect(update.auditEvent.previousStage, OpportunityStage.detected);
      expect(update.auditEvent.currentStage, OpportunityStage.armed);
      expect(
        update.auditEvent.transitionReason,
        OpportunityTransitionReason.entryApproaching,
      );
      expect(
        registry.candidateFor(candidate.setupId)?.stage,
        OpportunityStage.armed,
      );
    });

    test('deduplicates accepted event IDs without mutating the candidate', () {
      final registry = RealtimeCandidateRegistry();
      registry.register(_candidate());
      final envelope = _envelope(
        eventId: 'event-1',
        sequence: 1,
        minute: 2,
        price: 99.7,
        qualityScore: 70,
      );

      final accepted = registry.apply(envelope);
      final duplicate = registry.apply(envelope);

      expect(accepted.disposition, StreamEventDisposition.accepted);
      expect(duplicate.disposition, StreamEventDisposition.duplicate);
      expect(duplicate.evaluation, isNull);
      expect(duplicate.candidate?.stage, OpportunityStage.armed);
      expect(duplicate.auditEvent.auditSequence, 2);
    });

    test('detects a sequence gap before candidate evaluation', () {
      final registry = RealtimeCandidateRegistry();
      registry.register(_candidate());
      registry.apply(
        _envelope(
          eventId: 'event-1',
          sequence: 1,
          minute: 2,
          price: 99.7,
          qualityScore: 70,
        ),
      );

      final gap = registry.apply(
        _envelope(
          eventId: 'event-4',
          sequence: 4,
          minute: 3,
          price: 100.5,
          qualityScore: 80,
          triggerConfirmed: true,
        ),
      );

      expect(gap.disposition, StreamEventDisposition.gapDetected);
      expect(gap.requiresBackfill, isTrue);
      expect(gap.auditEvent.gap?.expectedSequence, 2);
      expect(gap.auditEvent.gap?.observedSequence, 4);
      expect(gap.auditEvent.gap?.missingEventCount, 2);
      expect(gap.candidate?.stage, OpportunityStage.armed);
    });

    test('reconciliation lets processing resume after a detected gap', () {
      final registry = RealtimeCandidateRegistry();
      final candidate = _candidate();
      registry.register(candidate);
      registry.apply(
        _envelope(
          eventId: 'event-1',
          sequence: 1,
          minute: 2,
          price: 99.7,
          qualityScore: 70,
        ),
      );
      expect(
        registry
            .apply(
              _envelope(
                eventId: 'event-4',
                sequence: 4,
                minute: 3,
                price: 100.5,
                qualityScore: 80,
                triggerConfirmed: true,
              ),
            )
            .requiresBackfill,
        isTrue,
      );

      registry.markReconciled(
        setupId: candidate.setupId,
        streamKey: RealtimeStreamKey(symbol: 'BTCUSDT', timeframe: '1h'),
        exchangeTimestampUtc: DateTime.utc(2026, 8, 2, 12, 3),
        sequence: 3,
      );
      final resumed = registry.apply(
        _envelope(
          eventId: 'event-4',
          sequence: 4,
          minute: 4,
          price: 100.5,
          qualityScore: 80,
          triggerConfirmed: true,
        ),
      );

      expect(resumed.disposition, StreamEventDisposition.accepted);
      expect(resumed.candidate?.stage, OpportunityStage.triggered);
    });

    test('rejects out-of-order sequence and timestamp fallback', () {
      final registry = RealtimeCandidateRegistry();
      registry.register(_candidate());
      registry.apply(
        _envelope(
          eventId: 'event-2',
          sequence: 2,
          minute: 3,
          price: 99.7,
          qualityScore: 70,
        ),
      );

      final oldSequence = registry.apply(
        _envelope(
          eventId: 'event-1',
          sequence: 1,
          minute: 4,
          price: 100,
          qualityScore: 75,
        ),
      );
      expect(oldSequence.disposition, StreamEventDisposition.outOfOrder);

      final timestampRegistry = RealtimeCandidateRegistry();
      timestampRegistry.register(_candidate());
      timestampRegistry.apply(
        _envelope(eventId: 'newer', minute: 5, price: 99.7, qualityScore: 70),
      );
      final oldTimestamp = timestampRegistry.apply(
        _envelope(eventId: 'older', minute: 4, price: 100, qualityScore: 75),
      );
      expect(oldTimestamp.disposition, StreamEventDisposition.outOfOrder);
    });

    test('rejects unknown and mismatched candidate identity', () {
      final registry = RealtimeCandidateRegistry();
      registry.register(_candidate());

      final unknown = registry.apply(
        _envelope(
          eventId: 'unknown',
          setupId: 'missing-setup',
          minute: 2,
          price: 100,
          qualityScore: 70,
        ),
      );
      expect(unknown.disposition, StreamEventDisposition.unknownCandidate);

      final mismatch = registry.apply(
        _envelope(
          eventId: 'mismatch',
          symbol: 'ETHUSDT',
          minute: 2,
          price: 100,
          qualityScore: 70,
        ),
      );
      expect(mismatch.disposition, StreamEventDisposition.identityMismatch);
    });

    test('enforces candidate capacity without evicting active truth', () {
      final registry = RealtimeCandidateRegistry(maximumCandidates: 1);
      expect(registry.register(_candidate()).accepted, isTrue);

      final second = registry.register(
        _candidate(setupId: 'BTCUSDT|1h|long|second'),
      );

      expect(
        second.disposition,
        CandidateRegistrationDisposition.capacityExceeded,
      );
      expect(registry.candidateCount, 1);
    });

    test('keeps only discovery-open candidates in active snapshot', () {
      final registry = RealtimeCandidateRegistry();
      final first = _candidate();
      final second = _candidate(setupId: 'BTCUSDT|1h|long|second');
      registry.register(first);
      registry.register(second);

      registry.apply(
        _envelope(
          eventId: 'trigger-first',
          setupId: first.setupId,
          sequence: 1,
          minute: 2,
          price: 100.5,
          qualityScore: 80,
          triggerConfirmed: true,
        ),
      );

      expect(registry.openDiscoveryCandidates, hasLength(1));
      expect(registry.openDiscoveryCandidates.single.setupId, second.setupId);
    });
  });
}

RealtimeOpportunityCandidate _candidate({
  String setupId = 'BTCUSDT|1h|long|registry',
  double entryLower = 100,
}) => RealtimeOpportunityCandidate.fromIdea(
  TradeIdea(
    symbol: 'BTCUSDT',
    timeframe: '1h',
    direction: TradeDirection.long,
    confidencePercent: 60,
    entryLower: entryLower,
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
    strategyVersion: 'candidate-registry/1.0',
  ),
  detectedAtUtc: DateTime.utc(2026, 8, 2, 12, 1),
);

RealtimeObservationEnvelope _envelope({
  required String eventId,
  required int minute,
  required double price,
  required int qualityScore,
  String setupId = 'BTCUSDT|1h|long|registry',
  String symbol = 'BTCUSDT',
  String timeframe = '1h',
  int? sequence,
  bool triggerConfirmed = false,
}) => RealtimeObservationEnvelope(
  eventId: eventId,
  setupId: setupId,
  symbol: symbol,
  timeframe: timeframe,
  sequence: sequence,
  observation: RealtimeMarketObservation(
    exchangeTimestampUtc: DateTime.utc(2026, 8, 2, 12, minute),
    receivedAtUtc: DateTime.utc(2026, 8, 2, 12, minute, 0, 200),
    evaluatedAtUtc: DateTime.utc(2026, 8, 2, 12, minute, 1),
    lastPrice: price,
    qualityScore: qualityScore,
    structureValid: true,
    triggerConfirmed: triggerConfirmed,
    triggerCandleClosed: triggerConfirmed,
  ),
);
