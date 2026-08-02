import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/owner_alpha/data/realtime_candidate_engine.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/realtime_candidate_models.dart';

void main() {
  group('RealtimeCandidateEngine', () {
    test('progresses from detected to forming, armed and triggered', () {
      var candidate = _candidate(TradeDirection.long, confidence: 48);

      var result = RealtimeCandidateEngine.evaluate(
        candidate: candidate,
        observation: _observation(
          minute: 2,
          price: 98,
          qualityScore: 58,
        ),
      );
      expect(result.candidate.stage, OpportunityStage.forming);
      expect(result.stageChanged, isTrue);

      candidate = result.candidate;
      result = RealtimeCandidateEngine.evaluate(
        candidate: candidate,
        observation: _observation(
          minute: 3,
          price: 99.7,
          qualityScore: 70,
        ),
      );
      expect(result.candidate.stage, OpportunityStage.armed);
      expect(
        result.candidate.transitionReason,
        OpportunityTransitionReason.entryApproaching,
      );

      candidate = result.candidate;
      result = RealtimeCandidateEngine.evaluate(
        candidate: candidate,
        observation: _observation(
          minute: 4,
          price: 100.5,
          qualityScore: 76,
          triggerConfirmed: true,
          triggerCandleClosed: true,
        ),
      );
      expect(result.candidate.stage, OpportunityStage.triggered);
      expect(
        result.candidate.triggeredAtUtc,
        DateTime.utc(2026, 8, 2, 12, 4, 1),
      );
      expect(result.candidate.resolvedAtUtc, isNull);
    });

    test('does not trigger from an open candle', () {
      final result = RealtimeCandidateEngine.evaluate(
        candidate: _candidate(TradeDirection.long),
        observation: _observation(
          minute: 2,
          price: 100.5,
          qualityScore: 80,
          triggerConfirmed: true,
          triggerCandleClosed: false,
        ),
      );

      expect(result.candidate.stage, OpportunityStage.armed);
      expect(result.candidate.triggeredAtUtc, isNull);
    });

    test('stale data blocks transition without destroying candidate', () {
      final candidate = _candidate(TradeDirection.long);
      final result = RealtimeCandidateEngine.evaluate(
        candidate: candidate,
        observation: RealtimeMarketObservation(
          exchangeTimestampUtc: DateTime.utc(2026, 8, 2, 12, 2),
          receivedAtUtc: DateTime.utc(2026, 8, 2, 12, 2, 1),
          evaluatedAtUtc: DateTime.utc(2026, 8, 2, 12, 2, 10),
          lastPrice: 100.5,
          qualityScore: 90,
          structureValid: true,
          triggerConfirmed: true,
          triggerCandleClosed: true,
        ),
      );

      expect(result.candidate.stage, OpportunityStage.detected);
      expect(
        result.candidate.transitionReason,
        OpportunityTransitionReason.dataStale,
      );
      expect(result.eventAge, const Duration(seconds: 10));
      expect(result.processingLatency, const Duration(seconds: 9));
    });

    test('marks a setup missed instead of chasing price', () {
      final result = RealtimeCandidateEngine.evaluate(
        candidate: _candidate(TradeDirection.long),
        observation: _observation(
          minute: 2,
          price: 101.3,
          qualityScore: 82,
          triggerConfirmed: true,
          triggerCandleClosed: true,
        ),
      );

      expect(result.candidate.stage, OpportunityStage.missed);
      expect(
        result.candidate.transitionReason,
        OpportunityTransitionReason.priceRanAway,
      );
      expect(result.candidate.resolvedAtUtc, isNotNull);
    });

    test('expires a candidate before considering a late trigger', () {
      final candidate = _candidate(TradeDirection.long);
      final result = RealtimeCandidateEngine.evaluate(
        candidate: candidate,
        observation: RealtimeMarketObservation(
          exchangeTimestampUtc: candidate.validUntilUtc,
          receivedAtUtc: candidate.validUntilUtc,
          evaluatedAtUtc: candidate.validUntilUtc,
          lastPrice: 100.5,
          qualityScore: 90,
          structureValid: true,
          triggerConfirmed: true,
          triggerCandleClosed: true,
        ),
      );

      expect(result.candidate.stage, OpportunityStage.expired);
      expect(
        result.candidate.transitionReason,
        OpportunityTransitionReason.validityExpired,
      );
    });

    test('invalidates when structure or protective boundary fails', () {
      final structuralFailure = RealtimeCandidateEngine.evaluate(
        candidate: _candidate(TradeDirection.long),
        observation: _observation(
          minute: 2,
          price: 99,
          qualityScore: 75,
          structureValid: false,
        ),
      );
      expect(
        structuralFailure.candidate.stage,
        OpportunityStage.invalidated,
      );

      final stopFailure = RealtimeCandidateEngine.evaluate(
        candidate: _candidate(TradeDirection.short),
        observation: _observation(
          minute: 2,
          price: 103,
          qualityScore: 75,
        ),
      );
      expect(stopFailure.candidate.stage, OpportunityStage.invalidated);
    });

    test('uses direction-aware approach and overshoot for shorts', () {
      final candidate = _candidate(TradeDirection.short);
      expect(
        candidate.approachDistancePercent(101.3),
        closeTo(0.296, 0.001),
      );
      expect(candidate.overshootPercent(99.7), closeTo(0.3, 0.001));

      final armed = RealtimeCandidateEngine.evaluate(
        candidate: candidate,
        observation: _observation(
          minute: 2,
          price: 101.3,
          qualityScore: 72,
        ),
      ).candidate;
      expect(armed.stage, OpportunityStage.armed);

      final triggered = RealtimeCandidateEngine.evaluate(
        candidate: armed,
        observation: _observation(
          minute: 3,
          price: 100.5,
          qualityScore: 78,
          triggerConfirmed: true,
          triggerCandleClosed: true,
        ),
      ).candidate;
      expect(triggered.stage, OpportunityStage.triggered);
    });

    test('allows playbook-specific policy without global relaxation', () {
      final candidate = _candidate(TradeDirection.long);
      final observation = _observation(
        minute: 2,
        price: 99.2,
        qualityScore: 70,
      );

      final balanced = RealtimeCandidateEngine.evaluate(
        candidate: candidate,
        observation: observation,
      );
      final widerPullbackPolicy = RealtimeCandidateEngine.evaluate(
        candidate: candidate,
        observation: observation,
        policy: const RealtimeCandidatePolicy(
          formingScore: 52,
          armedScore: 64,
          approachDistancePercent: 1,
          maximumChasePercent: 0.25,
          maximumEventAge: Duration(seconds: 5),
        ),
      );

      expect(balanced.candidate.stage, OpportunityStage.forming);
      expect(widerPullbackPolicy.candidate.stage, OpportunityStage.armed);
    });

    test('never resurrects terminal candidates', () {
      final missed = RealtimeCandidateEngine.evaluate(
        candidate: _candidate(TradeDirection.long),
        observation: _observation(
          minute: 2,
          price: 102,
          qualityScore: 80,
        ),
      ).candidate;
      expect(missed.stage, OpportunityStage.missed);

      final later = RealtimeCandidateEngine.evaluate(
        candidate: missed,
        observation: _observation(
          minute: 3,
          price: 100.5,
          qualityScore: 90,
          triggerConfirmed: true,
          triggerCandleClosed: true,
        ),
      );

      expect(identical(later.candidate, missed), isTrue);
      expect(later.candidate.stage, OpportunityStage.missed);
    });

    test('does not regress a triggered candidate back into discovery', () {
      final triggered = RealtimeCandidateEngine.evaluate(
        candidate: _candidate(TradeDirection.long),
        observation: _observation(
          minute: 2,
          price: 100.5,
          qualityScore: 80,
          triggerConfirmed: true,
          triggerCandleClosed: true,
        ),
      ).candidate;
      expect(triggered.stage, OpportunityStage.triggered);

      final later = RealtimeCandidateEngine.evaluate(
        candidate: triggered,
        observation: _observation(
          minute: 3,
          price: 99,
          qualityScore: 20,
        ),
      );

      expect(identical(later.candidate, triggered), isTrue);
      expect(later.candidate.stage, OpportunityStage.triggered);
    });

    test('rejects invalid event ordering and non-actionable ideas', () {
      final observation = RealtimeMarketObservation(
        exchangeTimestampUtc: DateTime.utc(2026, 8, 2, 12, 2),
        receivedAtUtc: DateTime.utc(2026, 8, 2, 12, 2, 2),
        evaluatedAtUtc: DateTime.utc(2026, 8, 2, 12, 2, 1),
        lastPrice: 100,
        qualityScore: 70,
        structureValid: true,
        triggerConfirmed: false,
        triggerCandleClosed: false,
      );
      expect(() => observation.validate(), throwsArgumentError);

      expect(
        () => RealtimeOpportunityCandidate.fromIdea(
          _idea(TradeDirection.wait),
          detectedAtUtc: DateTime.utc(2026, 8, 2, 12, 1),
        ),
        throwsArgumentError,
      );
    });
  });
}

RealtimeOpportunityCandidate _candidate(
  TradeDirection direction, {
  int confidence = 60,
}) => RealtimeOpportunityCandidate.fromIdea(
  _idea(direction, confidence: confidence),
  detectedAtUtc: DateTime.utc(2026, 8, 2, 12, 1),
);

TradeIdea _idea(TradeDirection direction, {int confidence = 60}) {
  final actionable = direction != TradeDirection.wait;
  double? stopLoss;
  List<double> targets = const [];
  if (direction == TradeDirection.long) {
    stopLoss = 98;
    targets = const [102, 104, 106];
  } else if (direction == TradeDirection.short) {
    stopLoss = 103;
    targets = const [99, 97, 95];
  }

  return TradeIdea(
    symbol: 'BTCUSDT',
    timeframe: '1h',
    direction: direction,
    confidencePercent: confidence,
    entryLower: actionable ? 100 : null,
    entryUpper: actionable ? 101 : null,
    stopLoss: stopLoss,
    targets: targets,
    riskReward: actionable ? 2 : null,
    maximumLoss: 50,
    positionSize: actionable ? 1 : null,
    notionalValue: actionable ? 100 : null,
    recommendedLeverage: actionable ? 2 : null,
    maximumSafeLeverage: actionable ? 5 : null,
    requiredMargin: actionable ? 50 : null,
    estimatedRoundTripCosts: actionable ? 0.2 : 0,
    setupId: actionable
        ? 'BTCUSDT|1h|${direction.name}|test'
        : 'wait-test',
    candleClosedAt: DateTime.utc(2026, 8, 2, 12),
    summary: 'test setup',
    invalidation: 'test invalidation',
    reasons: const ['test'],
    rejectionReason: actionable
        ? SetupRejectionReason.none
        : SetupRejectionReason.weakDirection,
    strategy: AnalysisStrategy.structureZones,
    strategyVersion: 'candidate-foundation/1.0',
  );
}

RealtimeMarketObservation _observation({
  required int minute,
  required double price,
  required int qualityScore,
  bool structureValid = true,
  bool triggerConfirmed = false,
  bool triggerCandleClosed = false,
}) => RealtimeMarketObservation(
  exchangeTimestampUtc: DateTime.utc(2026, 8, 2, 12, minute),
  receivedAtUtc: DateTime.utc(2026, 8, 2, 12, minute, 0, 200),
  evaluatedAtUtc: DateTime.utc(2026, 8, 2, 12, minute, 1),
  lastPrice: price,
  qualityScore: qualityScore,
  structureValid: structureValid,
  triggerConfirmed: triggerConfirmed,
  triggerCandleClosed: triggerCandleClosed,
);
