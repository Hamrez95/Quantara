import '../domain/realtime_candidate_models.dart';
import '../domain/owner_alpha_models.dart';

abstract final class RealtimeCandidateEngine {
  static CandidateEvaluationResult evaluate({
    required RealtimeOpportunityCandidate candidate,
    required RealtimeMarketObservation observation,
    RealtimeCandidatePolicy policy = const RealtimeCandidatePolicy.balanced(),
  }) {
    observation.validate();
    policy.validate();

    final previousStage = candidate.stage;
    if (candidate.isTerminal) {
      return CandidateEvaluationResult(
        previousStage: previousStage,
        candidate: candidate,
        eventAge: observation.eventAge,
        processingLatency: observation.processingLatency,
      );
    }

    final atUtc = observation.evaluatedAtUtc;
    if (!atUtc.isBefore(candidate.validUntilUtc)) {
      return _result(
        previousStage: previousStage,
        candidate: candidate.transition(
          nextStage: OpportunityStage.expired,
          reason: OpportunityTransitionReason.validityExpired,
          atUtc: atUtc,
          observedPrice: observation.lastPrice,
          observedQualityScore: observation.qualityScore,
          resolvedAtUtc: atUtc,
        ),
        observation: observation,
      );
    }

    if (!observation.structureValid ||
        _invalidationBreached(candidate, observation.lastPrice)) {
      return _result(
        previousStage: previousStage,
        candidate: candidate.transition(
          nextStage: OpportunityStage.invalidated,
          reason: OpportunityTransitionReason.structureInvalidated,
          atUtc: atUtc,
          observedPrice: observation.lastPrice,
          observedQualityScore: observation.qualityScore,
          resolvedAtUtc: atUtc,
        ),
        observation: observation,
      );
    }

    if (observation.eventAge > policy.maximumEventAge) {
      return _result(
        previousStage: previousStage,
        candidate: candidate.transition(
          nextStage: candidate.stage,
          reason: OpportunityTransitionReason.dataStale,
          atUtc: atUtc,
          observedPrice: observation.lastPrice,
          observedQualityScore: observation.qualityScore,
        ),
        observation: observation,
      );
    }

    final overshoot = candidate.overshootPercent(observation.lastPrice);
    if (overshoot > policy.maximumChasePercent) {
      return _result(
        previousStage: previousStage,
        candidate: candidate.transition(
          nextStage: OpportunityStage.missed,
          reason: OpportunityTransitionReason.priceRanAway,
          atUtc: atUtc,
          observedPrice: observation.lastPrice,
          observedQualityScore: observation.qualityScore,
          resolvedAtUtc: atUtc,
        ),
        observation: observation,
      );
    }

    final triggerIsFinal =
        observation.triggerConfirmed && observation.triggerCandleClosed;
    final triggerHasQuality = observation.qualityScore >= policy.armedScore;
    if (triggerIsFinal && triggerHasQuality) {
      return _result(
        previousStage: previousStage,
        candidate: candidate.transition(
          nextStage: OpportunityStage.triggered,
          reason: OpportunityTransitionReason.triggerConfirmed,
          atUtc: atUtc,
          observedPrice: observation.lastPrice,
          observedQualityScore: observation.qualityScore,
          triggeredAtUtc: atUtc,
        ),
        observation: observation,
      );
    }

    final approachDistance = candidate.approachDistancePercent(
      observation.lastPrice,
    );
    final nearEntry =
        candidate.containsPrice(observation.lastPrice) ||
        approachDistance <= policy.approachDistancePercent ||
        overshoot > 0;

    late final OpportunityStage nextStage;
    late final OpportunityTransitionReason reason;
    if (observation.qualityScore < policy.formingScore) {
      nextStage = OpportunityStage.detected;
      reason = observation.qualityScore < candidate.qualityScore
          ? OpportunityTransitionReason.evidenceWeakened
          : OpportunityTransitionReason.created;
    } else if (observation.qualityScore >= policy.armedScore && nearEntry) {
      nextStage = OpportunityStage.armed;
      reason = OpportunityTransitionReason.entryApproaching;
    } else {
      nextStage = OpportunityStage.forming;
      reason = observation.qualityScore < candidate.qualityScore
          ? OpportunityTransitionReason.evidenceWeakened
          : OpportunityTransitionReason.evidenceImproved;
    }

    return _result(
      previousStage: previousStage,
      candidate: candidate.transition(
        nextStage: nextStage,
        reason: reason,
        atUtc: atUtc,
        observedPrice: observation.lastPrice,
        observedQualityScore: observation.qualityScore,
      ),
      observation: observation,
    );
  }

  static bool _invalidationBreached(
    RealtimeOpportunityCandidate candidate,
    double price,
  ) => switch (candidate.direction) {
    TradeDirection.long => price <= candidate.invalidationPrice,
    TradeDirection.short => price >= candidate.invalidationPrice,
    TradeDirection.wait => true,
  };

  static CandidateEvaluationResult _result({
    required OpportunityStage previousStage,
    required RealtimeOpportunityCandidate candidate,
    required RealtimeMarketObservation observation,
  }) => CandidateEvaluationResult(
    previousStage: previousStage,
    candidate: candidate,
    eventAge: observation.eventAge,
    processingLatency: observation.processingLatency,
  );
}
