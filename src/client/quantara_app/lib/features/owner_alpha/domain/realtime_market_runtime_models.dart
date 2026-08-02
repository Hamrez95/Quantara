import 'bitunix_public_stream_models.dart';
import 'realtime_candidate_models.dart';
import 'realtime_candle_pipeline_models.dart';
import 'realtime_market_event_models.dart';

enum RealtimeMarketRuntimeState {
  idle,
  restoring,
  bootstrapping,
  connecting,
  live,
  paused,
  stopping,
  stopped,
  failed,
}

final class RealtimeMarketUniverse {
  RealtimeMarketUniverse(
    Iterable<RealtimeCandleStreamKey> streams, {
    this.maximumStreams = 2000,
  }) : streams = _normalize(streams, maximumStreams);

  final int maximumStreams;
  final List<RealtimeCandleStreamKey> streams;

  List<BitunixPublicSubscription> get subscriptions => List.unmodifiable([
    for (final stream in streams)
      BitunixPublicSubscription.kline(
        symbol: stream.symbol,
        interval: stream.interval,
      ),
  ]);

  static List<RealtimeCandleStreamKey> _normalize(
    Iterable<RealtimeCandleStreamKey> values,
    int maximumStreams,
  ) {
    if (maximumStreams < 1) {
      throw ArgumentError.value(maximumStreams, 'maximumStreams');
    }
    final unique = <String, RealtimeCandleStreamKey>{};
    for (final value in values) {
      unique[value.id] = value;
    }
    final ordered = unique.values.toList(growable: false)
      ..sort((left, right) => left.id.compareTo(right.id));
    if (ordered.isEmpty) {
      throw ArgumentError.value(
        values,
        'streams',
        'At least one stream is required.',
      );
    }
    if (ordered.length > maximumStreams) {
      throw ArgumentError.value(
        ordered.length,
        'streams',
        'The realtime universe exceeds its bounded stream capacity.',
      );
    }
    return List.unmodifiable(ordered);
  }
}

final class RealtimeCandidateAnalysisBatch {
  RealtimeCandidateAnalysisBatch({
    Iterable<RealtimeOpportunityCandidate> candidates = const [],
    Iterable<RealtimeObservationEnvelope> observations = const [],
  }) : candidates = List.unmodifiable(candidates),
       observations = List.unmodifiable(observations);

  final List<RealtimeOpportunityCandidate> candidates;
  final List<RealtimeObservationEnvelope> observations;

  bool get isEmpty => candidates.isEmpty && observations.isEmpty;
}

final class RealtimeMarketHealthSnapshot {
  const RealtimeMarketHealthSnapshot({
    required this.state,
    required this.configuredStreams,
    required this.activeShards,
    required this.liveShards,
    required this.eventsReceived,
    required this.klineEventsReceived,
    required this.closedCandleEvents,
    required this.gapEvents,
    required this.reconciliationEvents,
    required this.candidateEvaluations,
    required this.candidateCommits,
    required this.reconnectTransitions,
    required this.malformedPayloadFaults,
    required this.backpressureFaults,
    required this.p95TransportLag,
    required this.p95PipelineLatency,
    required this.lastEventAtUtc,
    required this.lastFaultAtUtc,
    required this.lastFaultMessage,
  });

  final RealtimeMarketRuntimeState state;
  final int configuredStreams;
  final int activeShards;
  final int liveShards;
  final int eventsReceived;
  final int klineEventsReceived;
  final int closedCandleEvents;
  final int gapEvents;
  final int reconciliationEvents;
  final int candidateEvaluations;
  final int candidateCommits;
  final int reconnectTransitions;
  final int malformedPayloadFaults;
  final int backpressureFaults;
  final Duration p95TransportLag;
  final Duration p95PipelineLatency;
  final DateTime? lastEventAtUtc;
  final DateTime? lastFaultAtUtc;
  final String? lastFaultMessage;

  bool get discoveryHealthy =>
      state == RealtimeMarketRuntimeState.live &&
      activeShards > 0 &&
      liveShards == activeShards &&
      lastFaultMessage == null;
}
