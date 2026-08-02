import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/owner_alpha/data/candidate_audit_retention_policy.dart';
import 'package:quantara_app/features/owner_alpha/domain/realtime_candidate_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/realtime_market_event_models.dart';

void main() {
  group('CandidateAuditRetentionPolicy', () {
    test('persists lifecycle transitions and stale-data faults', () {
      expect(
        CandidateAuditRetentionPolicy.decide(
          _event(
            disposition: StreamEventDisposition.accepted,
            previousStage: OpportunityStage.detected,
            currentStage: OpportunityStage.armed,
            reason: OpportunityTransitionReason.entryApproaching,
          ),
        ),
        CandidateAuditPersistenceDecision.persist,
      );
      expect(
        CandidateAuditRetentionPolicy.decide(
          _event(
            disposition: StreamEventDisposition.accepted,
            previousStage: OpportunityStage.armed,
            currentStage: OpportunityStage.armed,
            reason: OpportunityTransitionReason.dataStale,
          ),
        ),
        CandidateAuditPersistenceDecision.persist,
      );
    });

    test('skips accepted ticks without a durable state change', () {
      expect(
        CandidateAuditRetentionPolicy.decide(
          _event(
            disposition: StreamEventDisposition.accepted,
            previousStage: OpportunityStage.forming,
            currentStage: OpportunityStage.forming,
            reason: OpportunityTransitionReason.evidenceImproved,
          ),
        ),
        CandidateAuditPersistenceDecision.skip,
      );
    });

    test('aggregates duplicates and persists ordering or identity faults', () {
      expect(
        CandidateAuditRetentionPolicy.decide(
          _event(disposition: StreamEventDisposition.duplicate),
        ),
        CandidateAuditPersistenceDecision.aggregate,
      );
      for (final disposition in [
        StreamEventDisposition.outOfOrder,
        StreamEventDisposition.gapDetected,
        StreamEventDisposition.unknownCandidate,
        StreamEventDisposition.identityMismatch,
      ]) {
        expect(
          CandidateAuditRetentionPolicy.decide(
            _event(disposition: disposition),
          ),
          CandidateAuditPersistenceDecision.persist,
        );
      }
    });
  });
}

CandidateRegistryAuditEvent _event({
  required StreamEventDisposition disposition,
  OpportunityStage? previousStage,
  OpportunityStage? currentStage,
  OpportunityTransitionReason? reason,
}) => CandidateRegistryAuditEvent(
  auditSequence: 1,
  disposition: disposition,
  eventId: 'event',
  setupId: 'setup',
  streamKey: RealtimeStreamKey(symbol: 'BTCUSDT', timeframe: '1h'),
  observedAtUtc: DateTime.utc(2026, 8, 2),
  previousStage: previousStage,
  currentStage: currentStage,
  transitionReason: reason,
  gap: disposition == StreamEventDisposition.gapDetected
      ? const RealtimeStreamGap(expectedSequence: 2, observedSequence: 4)
      : null,
);
