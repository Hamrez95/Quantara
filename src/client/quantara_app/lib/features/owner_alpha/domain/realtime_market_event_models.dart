import 'realtime_candidate_models.dart';

enum StreamEventDisposition {
  accepted,
  duplicate,
  outOfOrder,
  gapDetected,
  unknownCandidate,
  identityMismatch,
}

enum CandidateRegistrationDisposition {
  registered,
  alreadyRegistered,
  conflict,
  capacityExceeded,
}

final class RealtimeStreamKey {
  RealtimeStreamKey({required String symbol, required String timeframe})
    : symbol = _normalize(symbol, 'symbol'),
      timeframe = _normalize(timeframe, 'timeframe');

  final String symbol;
  final String timeframe;

  static String _normalize(String value, String name) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, name, 'A non-empty value is required.');
    }
    return normalized;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RealtimeStreamKey &&
          symbol == other.symbol &&
          timeframe == other.timeframe;

  @override
  int get hashCode => Object.hash(symbol, timeframe);

  @override
  String toString() => '$symbol|$timeframe';
}

final class RealtimeObservationEnvelope {
  RealtimeObservationEnvelope({
    required String eventId,
    required String setupId,
    required String symbol,
    required String timeframe,
    required this.observation,
    this.sequence,
  }) : eventId = _required(eventId, 'eventId'),
       setupId = _required(setupId, 'setupId'),
       symbol = _required(symbol, 'symbol'),
       timeframe = _required(timeframe, 'timeframe') {
    if (sequence != null && sequence! < 0) {
      throw ArgumentError.value(sequence, 'sequence');
    }
    observation.validate();
  }

  final String eventId;
  final String setupId;
  final String symbol;
  final String timeframe;
  final int? sequence;
  final RealtimeMarketObservation observation;

  RealtimeStreamKey get streamKey =>
      RealtimeStreamKey(symbol: symbol, timeframe: timeframe);

  String get deduplicationKey => '${streamKey.toString()}|$eventId';

  static String _required(String value, String name) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, name, 'A non-empty value is required.');
    }
    return normalized;
  }
}

final class RealtimeStreamGap {
  const RealtimeStreamGap({
    required this.expectedSequence,
    required this.observedSequence,
  });

  final int expectedSequence;
  final int observedSequence;

  int get missingEventCount => observedSequence - expectedSequence;
}

final class CandidateRegistryAuditEvent {
  const CandidateRegistryAuditEvent({
    required this.auditSequence,
    required this.disposition,
    required this.eventId,
    required this.setupId,
    required this.streamKey,
    required this.observedAtUtc,
    required this.previousStage,
    required this.currentStage,
    required this.transitionReason,
    required this.gap,
  });

  final int auditSequence;
  final StreamEventDisposition disposition;
  final String eventId;
  final String setupId;
  final RealtimeStreamKey streamKey;
  final DateTime observedAtUtc;
  final OpportunityStage? previousStage;
  final OpportunityStage? currentStage;
  final OpportunityTransitionReason? transitionReason;
  final RealtimeStreamGap? gap;
}

final class CandidateRegistryUpdate {
  const CandidateRegistryUpdate({
    required this.disposition,
    required this.candidate,
    required this.evaluation,
    required this.auditEvent,
  });

  final StreamEventDisposition disposition;
  final RealtimeOpportunityCandidate? candidate;
  final CandidateEvaluationResult? evaluation;
  final CandidateRegistryAuditEvent auditEvent;

  bool get accepted => disposition == StreamEventDisposition.accepted;

  bool get requiresBackfill =>
      disposition == StreamEventDisposition.gapDetected;
}

final class CandidateRegistrationResult {
  const CandidateRegistrationResult({
    required this.disposition,
    required this.candidate,
  });

  final CandidateRegistrationDisposition disposition;
  final RealtimeOpportunityCandidate? candidate;

  bool get accepted =>
      disposition == CandidateRegistrationDisposition.registered ||
      disposition == CandidateRegistrationDisposition.alreadyRegistered;
}
