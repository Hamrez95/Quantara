import 'owner_alpha_models.dart';

enum OpportunityStage {
  detected,
  forming,
  armed,
  triggered,
  missed,
  expired,
  invalidated,
}

enum OpportunityTransitionReason {
  created,
  evidenceImproved,
  evidenceWeakened,
  entryApproaching,
  triggerConfirmed,
  priceRanAway,
  validityExpired,
  structureInvalidated,
  dataStale,
}

final class RealtimeOpportunityCandidate {
  RealtimeOpportunityCandidate._({
    required this.setupId,
    required this.symbol,
    required this.timeframe,
    required this.playbookId,
    required this.direction,
    required this.entryLower,
    required this.entryUpper,
    required this.invalidationPrice,
    required this.validUntilUtc,
    required this.detectedAtUtc,
    required this.lastUpdatedAtUtc,
    required this.qualityScore,
    required this.stage,
    required this.transitionReason,
    required this.lastPrice,
    required this.triggeredAtUtc,
    required this.resolvedAtUtc,
  });

  factory RealtimeOpportunityCandidate.fromIdea(
    TradeIdea idea, {
    required DateTime detectedAtUtc,
    String? playbookId,
  }) {
    if (!idea.isActionable ||
        idea.direction == TradeDirection.wait ||
        idea.entryLower == null ||
        idea.entryUpper == null ||
        idea.stopLoss == null) {
      throw ArgumentError(
        'Only complete actionable trade ideas can be tracked.',
      );
    }
    if (!detectedAtUtc.isUtc) {
      throw ArgumentError.value(
        detectedAtUtc,
        'detectedAtUtc',
        'UTC is required.',
      );
    }
    if (idea.confidencePercent < 0 || idea.confidencePercent > 100) {
      throw ArgumentError.value(
        idea.confidencePercent,
        'confidencePercent',
      );
    }

    final lower = idea.entryLower!;
    final upper = idea.entryUpper!;
    final invalidation = idea.stopLoss!;
    if (!_validPrice(lower) ||
        !_validPrice(upper) ||
        !_validPrice(invalidation) ||
        lower > upper) {
      throw ArgumentError('The idea contains invalid financial boundaries.');
    }
    if (idea.direction == TradeDirection.long && invalidation >= lower) {
      throw ArgumentError(
        'A long invalidation must remain below the entry zone.',
      );
    }
    if (idea.direction == TradeDirection.short && invalidation <= upper) {
      throw ArgumentError(
        'A short invalidation must remain above the entry zone.',
      );
    }

    final validUntil = idea.validUntil.toUtc();
    if (!validUntil.isAfter(detectedAtUtc)) {
      throw ArgumentError('The candidate must be detected before it expires.');
    }

    return RealtimeOpportunityCandidate._(
      setupId: idea.setupId,
      symbol: idea.symbol,
      timeframe: idea.timeframe,
      playbookId: playbookId ?? idea.strategyVersion,
      direction: idea.direction,
      entryLower: lower,
      entryUpper: upper,
      invalidationPrice: invalidation,
      validUntilUtc: validUntil,
      detectedAtUtc: detectedAtUtc,
      lastUpdatedAtUtc: detectedAtUtc,
      qualityScore: idea.confidencePercent,
      stage: OpportunityStage.detected,
      transitionReason: OpportunityTransitionReason.created,
      lastPrice: null,
      triggeredAtUtc: null,
      resolvedAtUtc: null,
    );
  }

  final String setupId;
  final String symbol;
  final String timeframe;
  final String playbookId;
  final TradeDirection direction;
  final double entryLower;
  final double entryUpper;
  final double invalidationPrice;
  final DateTime validUntilUtc;
  final DateTime detectedAtUtc;
  final DateTime lastUpdatedAtUtc;
  final int qualityScore;
  final OpportunityStage stage;
  final OpportunityTransitionReason transitionReason;
  final double? lastPrice;
  final DateTime? triggeredAtUtc;
  final DateTime? resolvedAtUtc;

  bool get isTerminal => switch (stage) {
    OpportunityStage.missed ||
    OpportunityStage.expired ||
    OpportunityStage.invalidated => true,
    _ => false,
  };

  bool get isClosedForDiscovery =>
      stage == OpportunityStage.triggered || isTerminal;

  bool containsPrice(double price) =>
      _validPrice(price) && price >= entryLower && price <= entryUpper;

  double approachDistancePercent(double price) {
    if (!_validPrice(price) || containsPrice(price)) return 0;
    if (direction == TradeDirection.long) {
      if (price < entryLower) return (entryLower - price) / price * 100;
      return 0;
    }
    if (price > entryUpper) return (price - entryUpper) / price * 100;
    return 0;
  }

  double overshootPercent(double price) {
    if (!_validPrice(price) || containsPrice(price)) return 0;
    if (direction == TradeDirection.long && price > entryUpper) {
      return (price - entryUpper) / entryUpper * 100;
    }
    if (direction == TradeDirection.short && price < entryLower) {
      return (entryLower - price) / entryLower * 100;
    }
    return 0;
  }

  RealtimeOpportunityCandidate transition({
    required OpportunityStage nextStage,
    required OpportunityTransitionReason reason,
    required DateTime atUtc,
    required double observedPrice,
    required int observedQualityScore,
    DateTime? triggeredAtUtc,
    DateTime? resolvedAtUtc,
  }) {
    if (!atUtc.isUtc || atUtc.isBefore(lastUpdatedAtUtc)) {
      throw ArgumentError(
        'Candidate transitions require monotonic UTC time.',
      );
    }
    if (!_validPrice(observedPrice)) {
      throw ArgumentError.value(observedPrice, 'observedPrice');
    }
    if (observedQualityScore < 0 || observedQualityScore > 100) {
      throw ArgumentError.value(
        observedQualityScore,
        'observedQualityScore',
      );
    }
    if (isClosedForDiscovery && nextStage != stage) {
      throw StateError('A closed discovery candidate cannot be resurrected.');
    }

    return RealtimeOpportunityCandidate._(
      setupId: setupId,
      symbol: symbol,
      timeframe: timeframe,
      playbookId: playbookId,
      direction: direction,
      entryLower: entryLower,
      entryUpper: entryUpper,
      invalidationPrice: invalidationPrice,
      validUntilUtc: validUntilUtc,
      detectedAtUtc: detectedAtUtc,
      lastUpdatedAtUtc: atUtc,
      qualityScore: observedQualityScore,
      stage: nextStage,
      transitionReason: reason,
      lastPrice: observedPrice,
      triggeredAtUtc: triggeredAtUtc ?? this.triggeredAtUtc,
      resolvedAtUtc: resolvedAtUtc ?? this.resolvedAtUtc,
    );
  }

  static bool _validPrice(double value) => value.isFinite && value > 0;
}

final class RealtimeMarketObservation {
  const RealtimeMarketObservation({
    required this.exchangeTimestampUtc,
    required this.receivedAtUtc,
    required this.evaluatedAtUtc,
    required this.lastPrice,
    required this.qualityScore,
    required this.structureValid,
    required this.triggerConfirmed,
    required this.triggerCandleClosed,
  });

  final DateTime exchangeTimestampUtc;
  final DateTime receivedAtUtc;
  final DateTime evaluatedAtUtc;
  final double lastPrice;
  final int qualityScore;
  final bool structureValid;
  final bool triggerConfirmed;
  final bool triggerCandleClosed;

  Duration get eventAge {
    final value = evaluatedAtUtc.difference(exchangeTimestampUtc);
    return value.isNegative ? Duration.zero : value;
  }

  Duration get processingLatency => evaluatedAtUtc.difference(receivedAtUtc);

  void validate({Duration allowedClockSkew = const Duration(seconds: 2)}) {
    if (!exchangeTimestampUtc.isUtc ||
        !receivedAtUtc.isUtc ||
        !evaluatedAtUtc.isUtc) {
      throw ArgumentError('Realtime observation timestamps must be UTC.');
    }
    if (receivedAtUtc.add(allowedClockSkew).isBefore(exchangeTimestampUtc) ||
        evaluatedAtUtc.isBefore(receivedAtUtc)) {
      throw ArgumentError('Realtime observation timestamps are out of order.');
    }
    if (!lastPrice.isFinite || lastPrice <= 0) {
      throw ArgumentError.value(lastPrice, 'lastPrice');
    }
    if (qualityScore < 0 || qualityScore > 100) {
      throw ArgumentError.value(qualityScore, 'qualityScore');
    }
  }
}

final class RealtimeCandidatePolicy {
  const RealtimeCandidatePolicy({
    required this.formingScore,
    required this.armedScore,
    required this.approachDistancePercent,
    required this.maximumChasePercent,
    required this.maximumEventAge,
  });

  static const balanced = RealtimeCandidatePolicy(
    formingScore: 52,
    armedScore: 64,
    approachDistancePercent: 0.45,
    maximumChasePercent: 0.25,
    maximumEventAge: Duration(seconds: 5),
  );

  final int formingScore;
  final int armedScore;
  final double approachDistancePercent;
  final double maximumChasePercent;
  final Duration maximumEventAge;

  void validate() {
    if (formingScore < 0 ||
        formingScore > 100 ||
        armedScore < formingScore ||
        armedScore > 100) {
      throw ArgumentError('Candidate score thresholds are invalid.');
    }
    if (!approachDistancePercent.isFinite ||
        approachDistancePercent < 0 ||
        !maximumChasePercent.isFinite ||
        maximumChasePercent < 0 ||
        maximumEventAge <= Duration.zero) {
      throw ArgumentError('Candidate timing or distance policy is invalid.');
    }
  }
}

final class CandidateEvaluationResult {
  const CandidateEvaluationResult({
    required this.previousStage,
    required this.candidate,
    required this.eventAge,
    required this.processingLatency,
  });

  final OpportunityStage previousStage;
  final RealtimeOpportunityCandidate candidate;
  final Duration eventAge;
  final Duration processingLatency;

  bool get stageChanged => previousStage != candidate.stage;
}
