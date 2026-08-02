import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/owner_alpha/data/realtime_candidate_coordinator.dart';
import 'package:quantara_app/features/owner_alpha/data/realtime_candidate_registry.dart';
import 'package:quantara_app/features/owner_alpha/domain/candidate_audit_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/realtime_candidate_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/realtime_market_event_models.dart';

void main() {
  group('RealtimeCandidateCoordinator', () {
    test(
      'persists a durable transition before committing candidate state',
      () async {
        final registry = RealtimeCandidateRegistry();
        final candidate = _candidate();
        registry.register(candidate);
        final store = _RecordingAuditStore(
          onAppend: (_) {
            expect(
              registry.candidateFor(candidate.setupId)?.stage,
              OpportunityStage.detected,
            );
          },
        );
        final coordinator = RealtimeCandidateCoordinator(
          registry: registry,
          auditStore: store,
        );

        final result = await coordinator.handle(
          _envelope(
            eventId: 'event-1',
            sequence: 1,
            minute: 2,
            price: 99.7,
            qualityScore: 70,
          ),
        );

        expect(result.outcome, CandidateCoordinationOutcome.committed);
        expect(result.publishable, isTrue);
        expect(store.events, hasLength(1));
        expect(
          registry.candidateFor(candidate.setupId)?.stage,
          OpportunityStage.armed,
        );
      },
    );

    test(
      'storage failure leaves candidate, cursor and dedup uncommitted',
      () async {
        final registry = RealtimeCandidateRegistry();
        final candidate = _candidate();
        registry.register(candidate);
        final store = _RecordingAuditStore()..failNext = true;
        final coordinator = RealtimeCandidateCoordinator(
          registry: registry,
          auditStore: store,
        );
        final envelope = _envelope(
          eventId: 'event-1',
          sequence: 1,
          minute: 2,
          price: 99.7,
          qualityScore: 70,
        );

        final failed = await coordinator.handle(envelope);
        expect(failed.outcome, CandidateCoordinationOutcome.durabilityFailed);
        expect(failed.publishable, isFalse);
        expect(
          registry.candidateFor(candidate.setupId)?.stage,
          OpportunityStage.detected,
        );

        final retried = await coordinator.handle(envelope);
        expect(retried.outcome, CandidateCoordinationOutcome.committed);
        expect(retried.update.disposition, StreamEventDisposition.accepted);
        expect(store.events, hasLength(1));
        expect(
          registry.candidateFor(candidate.setupId)?.stage,
          OpportunityStage.armed,
        );
      },
    );

    test(
      'commits accepted ticks without durable state changes without I/O',
      () async {
        final registry = RealtimeCandidateRegistry();
        final candidate = _candidate();
        registry.register(candidate);
        registry.apply(
          _envelope(
            eventId: 'forming',
            sequence: 1,
            minute: 2,
            price: 98.5,
            qualityScore: 58,
          ),
        );
        final store = _RecordingAuditStore();
        final coordinator = RealtimeCandidateCoordinator(
          registry: registry,
          auditStore: store,
        );

        final result = await coordinator.handle(
          _envelope(
            eventId: 'same-stage',
            sequence: 2,
            minute: 3,
            price: 98.6,
            qualityScore: 59,
          ),
        );

        expect(result.outcome, CandidateCoordinationOutcome.committed);
        expect(
          result.persistenceDecision,
          CandidateAuditPersistenceDecision.skip,
        );
        expect(store.events, isEmpty);
        expect(
          registry.candidateFor(candidate.setupId)?.stage,
          OpportunityStage.forming,
        );
      },
    );

    test(
      'aggregates duplicate noise without publishing or writing ledger',
      () async {
        final registry = RealtimeCandidateRegistry();
        registry.register(_candidate());
        final store = _RecordingAuditStore();
        final metrics = _RecordingMetricSink();
        final coordinator = RealtimeCandidateCoordinator(
          registry: registry,
          auditStore: store,
          metricSink: metrics,
        );
        final envelope = _envelope(
          eventId: 'event-1',
          sequence: 1,
          minute: 2,
          price: 99.7,
          qualityScore: 70,
        );
        await coordinator.handle(envelope);

        final duplicate = await coordinator.handle(envelope);

        expect(duplicate.outcome, CandidateCoordinationOutcome.rejected);
        expect(duplicate.publishable, isFalse);
        expect(
          duplicate.persistenceDecision,
          CandidateAuditPersistenceDecision.aggregate,
        );
        expect(metrics.dispositions, [StreamEventDisposition.duplicate]);
        expect(store.events, hasLength(1));
      },
    );

    test('persists a gap fault without mutating candidate state', () async {
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
      final store = _RecordingAuditStore();
      final coordinator = RealtimeCandidateCoordinator(
        registry: registry,
        auditStore: store,
      );

      final gap = await coordinator.handle(
        _envelope(
          eventId: 'event-4',
          sequence: 4,
          minute: 3,
          price: 100.5,
          qualityScore: 80,
          triggerConfirmed: true,
        ),
      );

      expect(gap.outcome, CandidateCoordinationOutcome.rejected);
      expect(gap.requiresBackfill, isTrue);
      expect(store.events, hasLength(1));
      expect(store.events.single.gap?.expectedSequence, 2);
      expect(
        registry.candidateFor(candidate.setupId)?.stage,
        OpportunityStage.armed,
      );
    });

    test(
      'serializes concurrent envelopes in candidate sequence order',
      () async {
        final registry = RealtimeCandidateRegistry();
        final candidate = _candidate();
        registry.register(candidate);
        final store = _RecordingAuditStore();
        final coordinator = RealtimeCandidateCoordinator(
          registry: registry,
          auditStore: store,
        );

        final results = await Future.wait([
          coordinator.handle(
            _envelope(
              eventId: 'event-1',
              sequence: 1,
              minute: 2,
              price: 98.5,
              qualityScore: 58,
            ),
          ),
          coordinator.handle(
            _envelope(
              eventId: 'event-2',
              sequence: 2,
              minute: 3,
              price: 99.7,
              qualityScore: 70,
            ),
          ),
        ]);

        expect(
          results.map((result) => result.outcome),
          everyElement(CandidateCoordinationOutcome.committed),
        );
        expect(store.events, hasLength(2));
        expect(
          registry.candidateFor(candidate.setupId)?.stage,
          OpportunityStage.armed,
        );
      },
    );

    test('processes independent candidates without head-of-line blocking', () async {
      const firstSetup = 'BTCUSDT|1h|long|coordinator';
      const secondSetup = 'BTCUSDT|1h|long|second';
      final registry = RealtimeCandidateRegistry();
      registry.register(_candidate(setupId: firstSetup));
      registry.register(_candidate(setupId: secondSetup));
      final store = _BlockingAuditStore(blockedSetupId: firstSetup);
      final coordinator = RealtimeCandidateCoordinator(
        registry: registry,
        auditStore: store,
      );

      final firstFuture = coordinator.handle(
        _envelope(
          eventId: 'first-event',
          setupId: firstSetup,
          sequence: 1,
          minute: 2,
          price: 99.7,
          qualityScore: 70,
        ),
      );
      await store.blockedAppendStarted.future;
      final secondResult = await coordinator
          .handle(
            _envelope(
              eventId: 'second-event',
              setupId: secondSetup,
              sequence: 1,
              minute: 2,
              price: 99.7,
              qualityScore: 70,
            ),
          )
          .timeout(const Duration(seconds: 1));

      expect(secondResult.outcome, CandidateCoordinationOutcome.committed);
      store.releaseBlockedAppend.complete();
      final firstResult = await firstFuture;
      expect(firstResult.outcome, CandidateCoordinationOutcome.committed);
    });

    test(
      'surfaces metric failure without blocking duplicate rejection',
      () async {
        final registry = RealtimeCandidateRegistry();
        registry.register(_candidate());
        final store = _RecordingAuditStore();
        final metrics = _RecordingMetricSink()..fail = true;
        final coordinator = RealtimeCandidateCoordinator(
          registry: registry,
          auditStore: store,
          metricSink: metrics,
        );
        final envelope = _envelope(
          eventId: 'event-1',
          sequence: 1,
          minute: 2,
          price: 99.7,
          qualityScore: 70,
        );
        await coordinator.handle(envelope);

        final duplicate = await coordinator.handle(envelope);

        expect(duplicate.outcome, CandidateCoordinationOutcome.rejected);
        expect(duplicate.diagnosticFailureMessage, contains('metric failure'));
      },
    );

    test(
      'reports commit conflict when same-candidate ownership is violated',
      () async {
        final registry = RealtimeCandidateRegistry();
        final candidate = _candidate();
        registry.register(candidate);
        final store = _RecordingAuditStore(
          onAppend: (_) {
            registry.markReconciled(
              setupId: candidate.setupId,
              streamKey: RealtimeStreamKey(
                symbol: candidate.symbol,
                timeframe: candidate.timeframe,
              ),
              exchangeTimestampUtc: DateTime.utc(2026, 8, 2, 12, 2),
              sequence: 1,
            );
          },
        );
        final coordinator = RealtimeCandidateCoordinator(
          registry: registry,
          auditStore: store,
        );

        final result = await coordinator.handle(
          _envelope(
            eventId: 'event-1',
            sequence: 1,
            minute: 2,
            price: 99.7,
            qualityScore: 70,
          ),
        );

        expect(result.outcome, CandidateCoordinationOutcome.commitConflict);
        expect(result.publishable, isFalse);
        expect(store.events, hasLength(1));
        expect(
          registry.candidateFor(candidate.setupId)?.stage,
          OpportunityStage.detected,
        );
      },
    );
  });
}

final class _RecordingAuditStore implements CandidateAuditStore {
  _RecordingAuditStore({this.onAppend});

  final void Function(CandidateRegistryAuditEvent event)? onAppend;
  final List<CandidateRegistryAuditEvent> events = [];
  bool failNext = false;

  @override
  Future<CandidateAuditLedger> load() async => CandidateAuditLedger.empty();

  @override
  Future<void> append(CandidateRegistryAuditEvent event) async {
    onAppend?.call(event);
    if (failNext) {
      failNext = false;
      throw StateError('injected persistence failure');
    }
    events.add(event);
  }
}

final class _BlockingAuditStore implements CandidateAuditStore {
  _BlockingAuditStore({required this.blockedSetupId});

  final String blockedSetupId;
  final Completer<void> blockedAppendStarted = Completer<void>();
  final Completer<void> releaseBlockedAppend = Completer<void>();

  @override
  Future<CandidateAuditLedger> load() async => CandidateAuditLedger.empty();

  @override
  Future<void> append(CandidateRegistryAuditEvent event) async {
    if (event.setupId == blockedSetupId) {
      blockedAppendStarted.complete();
      await releaseBlockedAppend.future;
    }
  }
}

final class _RecordingMetricSink implements CandidateAuditMetricSink {
  final List<StreamEventDisposition> dispositions = [];
  bool fail = false;

  @override
  Future<void> increment(StreamEventDisposition disposition) async {
    if (fail) throw StateError('metric failure');
    dispositions.add(disposition);
  }
}

RealtimeOpportunityCandidate _candidate({
  String setupId = 'BTCUSDT|1h|long|coordinator',
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
    strategyVersion: 'candidate-coordinator/1.0',
  ),
  detectedAtUtc: DateTime.utc(2026, 8, 2, 12, 1),
);

RealtimeObservationEnvelope _envelope({
  required String eventId,
  required int minute,
  required double price,
  required int qualityScore,
  String setupId = 'BTCUSDT|1h|long|coordinator',
  int? sequence,
  bool triggerConfirmed = false,
}) => RealtimeObservationEnvelope(
  eventId: eventId,
  setupId: setupId,
  symbol: 'BTCUSDT',
  timeframe: '1h',
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
