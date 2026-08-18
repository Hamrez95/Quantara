import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/realtime_candidate_models.dart';
import 'package:quantara_app/features/owner_alpha/presentation/realtime_radar_presentation.dart';

void main() {
  test('projects domain lifecycle and preserves the raw reason code', () {
    final candidate = _candidate().transition(
      nextStage: OpportunityStage.armed,
      reason: OpportunityTransitionReason.entryApproaching,
      atUtc: DateTime.utc(2026, 8, 2, 12, 2),
      observedPrice: 99.8,
      observedQualityScore: 72,
    );

    final item = RealtimeRadarItemPresentation.fromEvidence(
      candidate: candidate,
      nowUtc: DateTime.utc(2026, 8, 2, 12, 2, 3),
      realtimeOperational: true,
    );

    expect(item.lane, RealtimeRadarLane.armed);
    expect(item.dataUncertain, isFalse);
    expect(item.rawReasonCode, 'candidate-transition:entryApproaching');
    expect(item.distanceToEntryPercent, closeTo(0.2004, 0.0001));
    expect(item.conciseReason(persian: true), contains('تریگر'));
  });

  test(
    'fails closed when realtime health or domain freshness is uncertain',
    () {
      final stale = _candidate().transition(
        nextStage: OpportunityStage.detected,
        reason: OpportunityTransitionReason.dataStale,
        atUtc: DateTime.utc(2026, 8, 2, 12, 2),
        observedPrice: 100,
        observedQualityScore: 80,
      );

      final item = RealtimeRadarItemPresentation.fromEvidence(
        candidate: stale,
        nowUtc: DateTime.utc(2026, 8, 2, 12, 2, 8),
        realtimeOperational: true,
      );

      expect(item.dataUncertain, isTrue);
      expect(item.safeNextAction(persian: false), 'Wait for fresh data');
      expect(item.rawReasonCode, 'candidate-transition:dataStale');
    },
  );

  test('journal outcome advances triggered evidence to managing only', () {
    final candidate = _candidate().transition(
      nextStage: OpportunityStage.triggered,
      reason: OpportunityTransitionReason.triggerConfirmed,
      atUtc: DateTime.utc(2026, 8, 2, 12, 2),
      observedPrice: 100.5,
      observedQualityScore: 78,
    );
    final journal = SignalJournalEntry.fromIdea(
      _idea(),
    ).copyWith(outcome: SignalOutcome.tp1);

    final items = RealtimeRadarProjection.build(
      candidates: [candidate],
      journal: [journal],
      nowUtc: DateTime.utc(2026, 8, 2, 12, 3),
      realtimeOperational: true,
    );

    expect(items.single.lane, RealtimeRadarLane.managing);
    expect(items.single.rawReasonCode, 'signal-outcome:tp1');
    expect(items.single.candidate.qualityScore, 78);
  });
}

RealtimeOpportunityCandidate _candidate() =>
    RealtimeOpportunityCandidate.fromIdea(
      _idea(),
      detectedAtUtc: DateTime.utc(2026, 8, 2, 12, 1),
    );

TradeIdea _idea() => TradeIdea(
  symbol: 'BTCUSDT',
  timeframe: '1h',
  direction: TradeDirection.long,
  confidencePercent: 72,
  setupQualityScore: 72,
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
  setupId: 'BTCUSDT|1h|long|test',
  candleClosedAt: DateTime.utc(2026, 8, 2, 12),
  summary: 'test setup',
  invalidation: 'test invalidation',
  reasons: const ['test'],
  rejectionReason: SetupRejectionReason.none,
  strategy: AnalysisStrategy.structureZones,
  strategyVersion: 'candidate-foundation/1.0',
);
