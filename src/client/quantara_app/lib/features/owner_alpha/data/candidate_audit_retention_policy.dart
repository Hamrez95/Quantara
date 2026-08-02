import '../domain/realtime_candidate_models.dart';
import '../domain/realtime_market_event_models.dart';

enum CandidateAuditPersistenceDecision { persist, aggregate, skip }

abstract final class CandidateAuditRetentionPolicy {
  static CandidateAuditPersistenceDecision decide(
    CandidateRegistryAuditEvent event,
  ) {
    return switch (event.disposition) {
      StreamEventDisposition.accepted => _acceptedDecision(event),
      StreamEventDisposition.duplicate =>
        CandidateAuditPersistenceDecision.aggregate,
      StreamEventDisposition.outOfOrder ||
      StreamEventDisposition.gapDetected ||
      StreamEventDisposition.unknownCandidate ||
      StreamEventDisposition.identityMismatch =>
        CandidateAuditPersistenceDecision.persist,
    };
  }

  static CandidateAuditPersistenceDecision _acceptedDecision(
    CandidateRegistryAuditEvent event,
  ) {
    if (event.previousStage != event.currentStage ||
        event.transitionReason == OpportunityTransitionReason.dataStale) {
      return CandidateAuditPersistenceDecision.persist;
    }
    return CandidateAuditPersistenceDecision.skip;
  }
}
