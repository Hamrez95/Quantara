import 'dart:async';
import 'dart:collection';

import '../domain/bitunix_public_stream_models.dart';
import '../domain/realtime_candidate_models.dart';
import '../domain/realtime_candle_pipeline_models.dart';
import '../domain/realtime_market_event_models.dart';
import '../domain/realtime_market_runtime_models.dart';
import 'bitunix_candle_backfill_source.dart';
import 'bitunix_public_stream_fleet_factory.dart';
import 'bitunix_public_stream_transport.dart';
import 'bitunix_web_socket_adapter.dart';
import 'realtime_candidate_coordinator.dart';
import 'realtime_candle_assembler.dart';
import 'realtime_candle_pipeline_coordinator.dart';
import 'realtime_market_event_bus.dart';

abstract interface class RealtimeMarketAnalysisGateway {
  Future<RealtimeCandidateAnalysisBatch> analyze(
    RealtimeCandlePipelineUpdate update,
  );
}

abstract interface class RealtimeMarketAnalysisSynchronizer {
  Future<void> synchronize(RealtimeCandlePipelineUpdate update);
}

abstract interface class RealtimeAuditedCandidateProjection {
  Future<void> restore();

  Future<void> apply({
    required CandidateRegistryAuditEvent auditEvent,
    required RealtimeOpportunityCandidate? candidate,
    required CandidateCoordinationOutcome outcome,
    required CandidateAuditPersistenceDecision persistenceDecision,
  });
}

final class NoopRealtimeAuditedCandidateProjection
    implements RealtimeAuditedCandidateProjection {
  const NoopRealtimeAuditedCandidateProjection();

  @override
  Future<void> restore() async {}

  @override
  Future<void> apply({
    required CandidateRegistryAuditEvent auditEvent,
    required RealtimeOpportunityCandidate? candidate,
    required CandidateCoordinationOutcome outcome,
    required CandidateAuditPersistenceDecision persistenceDecision,
  }) async {}
}

abstract interface class RealtimePublicStreamFleet {
  int get shardCount;

  Future<void> run();

  Future<void> stop();
}

abstract interface class RealtimePublicStreamFleetFactory {
  RealtimePublicStreamFleet build({
    required Iterable<BitunixPublicSubscription> subscriptions,
    required BitunixStreamEventHandler onEvent,
    required BitunixStreamFaultHandler onFault,
    required BitunixFleetStateHandler onState,
  });
}

final class BitunixRealtimePublicStreamFleetFactory
    implements RealtimePublicStreamFleetFactory {
  const BitunixRealtimePublicStreamFleetFactory({
    this.connector = const DefaultBitunixWebSocketConnector(),
    this.config,
    this.reconnectPolicy,
    this.clock,
    this.delay,
  });

  final BitunixWebSocketConnector connector;
  final BitunixPublicStreamConfig? config;
  final BitunixReconnectPolicy? reconnectPolicy;
  final BitunixUtcClock? clock;
  final BitunixAsyncDelay? delay;

  @override
  RealtimePublicStreamFleet build({
    required Iterable<BitunixPublicSubscription> subscriptions,
    required BitunixStreamEventHandler onEvent,
    required BitunixStreamFaultHandler onFault,
    required BitunixFleetStateHandler onState,
  }) {
    final fleet = BitunixPublicStreamFleetFactory.build(
      subscriptions: subscriptions,
      connector: connector,
      onEvent: onEvent,
      onFault: onFault,
      onState: onState,
      config: config,
      reconnectPolicy: reconnectPolicy,
      clock: clock,
      delay: delay,
    );
    return _BitunixRealtimePublicStreamFleet(fleet);
  }
}

final class _BitunixRealtimePublicStreamFleet
    implements RealtimePublicStreamFleet {
  const _BitunixRealtimePublicStreamFleet(this._delegate);

  final BitunixPublicStreamFleet _delegate;

  @override
  int get shardCount => _delegate.connections.length;

  @override
  Future<void> run() => _delegate.run();

  @override
  Future<void> stop() => _delegate.stop();
}

typedef RealtimeBootstrapDelay = Future<void> Function(Duration duration);

final class RealtimeMarketApplication {
  RealtimeMarketApplication({
    required this.universe,
    required RealtimeCandleBackfillSource backfillSource,
    required this.fleetFactory,
    required this.analysisGateway,
    required this.candidateCoordinator,
    this.projection = const NoopRealtimeAuditedCandidateProjection(),
    this.closedCandleLimit = 200,
    this.bootstrapSpacing = const Duration(milliseconds: 120),
    this.maximumPendingEventsPerStream = 64,
    this.maximumLatencySamples = 512,
    RealtimeCandleUtcClock? clock,
    RealtimeBootstrapDelay? delay,
  }) : _clock = clock ?? _utcNow,
       _delay = delay ?? _defaultDelay {
    if (closedCandleLimit < 20 || closedCandleLimit > 200) {
      throw ArgumentError.value(closedCandleLimit, 'closedCandleLimit');
    }
    if (bootstrapSpacing < Duration.zero) {
      throw ArgumentError.value(bootstrapSpacing, 'bootstrapSpacing');
    }
    if (maximumPendingEventsPerStream < 1) {
      throw ArgumentError.value(
        maximumPendingEventsPerStream,
        'maximumPendingEventsPerStream',
      );
    }
    if (maximumLatencySamples < 20) {
      throw ArgumentError.value(maximumLatencySamples, 'maximumLatencySamples');
    }

    _metrics = _RealtimeMarketMetrics(maximumLatencySamples);
    _eventBus = RealtimeMarketEventBus(
      handler: _handlePipelineUpdate,
      maximumPendingPerStream: maximumPendingEventsPerStream,
      maximumActiveStreams: universe.maximumStreams,
    );
    _candleCoordinator = RealtimeCandlePipelineCoordinator(
      assembler: RealtimeCandleAssembler(),
      backfillSource: backfillSource,
      eventBus: _eventBus,
      clock: _clock,
    );
  }

  final RealtimeMarketUniverse universe;
  final RealtimePublicStreamFleetFactory fleetFactory;
  final RealtimeMarketAnalysisGateway analysisGateway;
  final RealtimeCandidateCoordinator candidateCoordinator;
  final RealtimeAuditedCandidateProjection projection;
  final int closedCandleLimit;
  final Duration bootstrapSpacing;
  final int maximumPendingEventsPerStream;
  final int maximumLatencySamples;
  final RealtimeCandleUtcClock _clock;
  final RealtimeBootstrapDelay _delay;

  late final _RealtimeMarketMetrics _metrics;
  late final RealtimeMarketEventBus _eventBus;
  late final RealtimeCandlePipelineCoordinator _candleCoordinator;
  final Map<int, BitunixPublicConnectionState> _shardStates = {};
  Future<void> _lifecycleTail = Future.value();
  Future<void>? _fleetRun;
  RealtimePublicStreamFleet? _fleet;
  RealtimeMarketRuntimeState _state = RealtimeMarketRuntimeState.idle;
  bool _projectionRestored = false;
  bool _closed = false;

  RealtimeMarketRuntimeState get state => _state;

  RealtimeMarketHealthSnapshot get health => _metrics.snapshot(
    state: _state,
    configuredStreams: universe.streams.length,
    activeShards: _fleet?.shardCount ?? 0,
    liveShards: _shardStates.values
        .where((state) => state == BitunixPublicConnectionState.live)
        .length,
  );

  Future<void> start() => _serializeLifecycle(_startInternal);

  Future<void> resume() => _serializeLifecycle(() async {
    if (_state != RealtimeMarketRuntimeState.paused) {
      throw StateError('Only a paused realtime runtime can resume.');
    }
    await _startInternal();
  });

  Future<void> pause() => _serializeLifecycle(() async {
    if (_closed) return;
    if (_state == RealtimeMarketRuntimeState.paused ||
        _state == RealtimeMarketRuntimeState.idle) {
      _setState(RealtimeMarketRuntimeState.paused);
      return;
    }
    await _stopFleet(finalState: RealtimeMarketRuntimeState.paused);
  });

  Future<void> stop() => _serializeLifecycle(() async {
    if (_closed) return;
    await _stopFleet(finalState: RealtimeMarketRuntimeState.stopped);
    await _eventBus.close(drain: true);
    _closed = true;
  });

  Future<void> _startInternal() async {
    if (_closed) {
      throw StateError('The realtime market runtime is closed.');
    }
    if (_state == RealtimeMarketRuntimeState.restoring ||
        _state == RealtimeMarketRuntimeState.bootstrapping ||
        _state == RealtimeMarketRuntimeState.connecting ||
        _state == RealtimeMarketRuntimeState.live) {
      throw StateError('The realtime market runtime is already active.');
    }

    try {
      if (!_projectionRestored) {
        _setState(RealtimeMarketRuntimeState.restoring);
        await projection.restore();
        _projectionRestored = true;
      }

      _setState(RealtimeMarketRuntimeState.bootstrapping);
      for (var index = 0; index < universe.streams.length; index++) {
        await _candleCoordinator.bootstrap(
          key: universe.streams[index],
          closedCandleLimit: closedCandleLimit,
        );
        if (index + 1 < universe.streams.length &&
            bootstrapSpacing > Duration.zero) {
          await _delay(bootstrapSpacing);
        }
      }

      _shardStates.clear();
      final fleet = fleetFactory.build(
        subscriptions: universe.subscriptions,
        onEvent: _handlePublicEvent,
        onFault: _handleTransportFault,
        onState: _handleShardState,
      );
      _fleet = fleet;
      _setState(RealtimeMarketRuntimeState.connecting);
      late final Future<void> run;
      run = fleet.run();
      _fleetRun = run;
      unawaited(
        run.then<void>(
          (_) => _handleFleetTermination(run),
          onError: (Object error, StackTrace _) =>
              _handleFleetTermination(run, error: error),
        ),
      );
    } on Object catch (error) {
      await _discardFailedFleet();
      _setState(RealtimeMarketRuntimeState.failed);
      _metrics.recordFault(
        message: 'Realtime startup failed: $error',
        occurredAtUtc: _clock(),
      );
      rethrow;
    }
  }

  Future<void> _discardFailedFleet() async {
    final fleet = _fleet;
    final run = _fleetRun;
    _fleet = null;
    _fleetRun = null;
    _shardStates.clear();
    if (fleet != null) {
      try {
        await fleet.stop();
      } on Object {
        // Startup failure remains the primary fault.
      }
    }
    if (run != null) {
      try {
        await run;
      } on Object {
        // The startup failure is reported by the caller.
      }
    }
  }

  void _handleFleetTermination(Future<void> run, {Object? error}) {
    if (!identical(_fleetRun, run)) return;
    _fleetRun = null;
    _fleet = null;
    _shardStates.clear();
    if (_closed ||
        _state == RealtimeMarketRuntimeState.stopping ||
        _state == RealtimeMarketRuntimeState.paused ||
        _state == RealtimeMarketRuntimeState.stopped) {
      return;
    }
    _setState(RealtimeMarketRuntimeState.failed);
    _metrics.recordFault(
      message: error == null
          ? 'The public stream fleet stopped unexpectedly.'
          : 'The public stream fleet failed: $error',
      occurredAtUtc: _clock(),
    );
  }

  Future<void> _stopFleet({
    required RealtimeMarketRuntimeState finalState,
  }) async {
    _setState(RealtimeMarketRuntimeState.stopping);
    final fleet = _fleet;
    final run = _fleetRun;
    _fleet = null;
    _fleetRun = null;
    if (fleet != null) await fleet.stop();
    if (run != null) {
      try {
        await run;
      } on Object {
        // The transport fault was already captured through the fleet callback.
      }
    }
    _shardStates.clear();
    _setState(finalState);
  }

  Future<void> _handlePublicEvent(BitunixPublicStreamEvent event) async {
    _metrics.recordPublicEvent(event, observedAtUtc: _clock());
    if (event is! BitunixKlineEvent) return;

    try {
      await _candleCoordinator.handleKline(event);
    } on RealtimeMarketEventBackpressureException catch (error) {
      _metrics.recordBackpressure(error.toString(), _clock());
      rethrow;
    } on Object catch (error) {
      _metrics.recordFault(
        message: 'Realtime candle processing failed: $error',
        occurredAtUtc: _clock(),
      );
      rethrow;
    }
  }

  Future<void> _handlePipelineUpdate(
    RealtimeCandlePipelineUpdate update,
  ) async {
    _metrics.recordPipelineUpdate(update);
    final synchronizer =
        analysisGateway is RealtimeMarketAnalysisSynchronizer
        ? analysisGateway as RealtimeMarketAnalysisSynchronizer
        : null;
    if (synchronizer != null) {
      try {
        await synchronizer.synchronize(update);
      } on Object catch (error) {
        _metrics.recordFault(
          message: 'Realtime analysis synchronization failed: $error',
          occurredAtUtc: _clock(),
        );
        rethrow;
      }
    }
    if (!update.allowsCandidatePreparation) return;

    late final RealtimeCandidateAnalysisBatch batch;
    try {
      batch = await analysisGateway.analyze(update);
    } on Object catch (error) {
      _metrics.recordFault(
        message: 'Realtime market analysis failed: $error',
        occurredAtUtc: _clock(),
      );
      rethrow;
    }
    if (batch.isEmpty) return;

    for (final candidate in batch.candidates) {
      candidateCoordinator.registry.register(candidate);
    }
    for (final observation in batch.observations) {
      _metrics.candidateEvaluations++;
      final result = await candidateCoordinator.handle(observation);
      if (result.committed) _metrics.candidateCommits++;
      if (result.persistenceDecision !=
              CandidateAuditPersistenceDecision.persist ||
          result.outcome == CandidateCoordinationOutcome.durabilityFailed) {
        continue;
      }
      try {
        await projection.apply(
          auditEvent: result.update.auditEvent,
          candidate: result.update.candidate,
          outcome: result.outcome,
          persistenceDecision: result.persistenceDecision,
        );
      } on Object catch (error) {
        _metrics.recordFault(
          message: 'Audited candidate projection failed: $error',
          occurredAtUtc: _clock(),
        );
      }
    }
  }

  Future<void> _handleTransportFault(BitunixPublicStreamFault fault) async {
    _metrics.recordTransportFault(fault);
  }

  Future<void> _handleShardState(
    int shardIndex,
    BitunixPublicConnectionState state,
  ) async {
    final previous = _shardStates[shardIndex];
    _shardStates[shardIndex] = state;
    if (state == BitunixPublicConnectionState.backingOff &&
        previous != BitunixPublicConnectionState.backingOff) {
      _metrics.reconnectTransitions++;
    }

    final fleet = _fleet;
    if (fleet != null &&
        fleet.shardCount > 0 &&
        _shardStates.length == fleet.shardCount &&
        _shardStates.values.every(
          (value) => value == BitunixPublicConnectionState.live,
        )) {
      _setState(RealtimeMarketRuntimeState.live);
    } else if (!_closed &&
        _state != RealtimeMarketRuntimeState.stopping &&
        _state != RealtimeMarketRuntimeState.paused &&
        _state != RealtimeMarketRuntimeState.stopped &&
        state != BitunixPublicConnectionState.stopped) {
      _setState(RealtimeMarketRuntimeState.connecting);
    }
  }

  Future<T> _serializeLifecycle<T>(Future<T> Function() operation) {
    final result = _lifecycleTail.then((_) => operation());
    _lifecycleTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  void _setState(RealtimeMarketRuntimeState next) {
    _state = next;
  }

  static DateTime _utcNow() => DateTime.now().toUtc();

  static Future<void> _defaultDelay(Duration duration) =>
      Future.delayed(duration);
}

final class _RealtimeMarketMetrics {
  _RealtimeMarketMetrics(this.maximumSamples);

  final int maximumSamples;
  final Queue<int> _transportLagMicros = Queue();
  final Queue<int> _pipelineLatencyMicros = Queue();
  int eventsReceived = 0;
  int klineEventsReceived = 0;
  int closedCandleEvents = 0;
  int gapEvents = 0;
  int reconciliationEvents = 0;
  int candidateEvaluations = 0;
  int candidateCommits = 0;
  int reconnectTransitions = 0;
  int malformedPayloadFaults = 0;
  int backpressureFaults = 0;
  DateTime? lastEventAtUtc;
  DateTime? lastFaultAtUtc;
  String? lastFaultMessage;

  void recordPublicEvent(
    BitunixPublicStreamEvent event, {
    required DateTime observedAtUtc,
  }) {
    eventsReceived++;
    if (event is BitunixKlineEvent) klineEventsReceived++;
    lastEventAtUtc = observedAtUtc;
    _record(
      _transportLagMicros,
      _nonNegative(event.transportLag).inMicroseconds,
    );
  }

  void recordPipelineUpdate(RealtimeCandlePipelineUpdate update) {
    switch (update.disposition) {
      case RealtimeCandlePipelineDisposition.candleClosed:
        closedCandleEvents++;
        break;
      case RealtimeCandlePipelineDisposition.gapDetected:
        gapEvents++;
        break;
      case RealtimeCandlePipelineDisposition.reconciled:
        reconciliationEvents++;
        break;
      case RealtimeCandlePipelineDisposition.bootstrapped:
      case RealtimeCandlePipelineDisposition.workingUpdated:
      case RealtimeCandlePipelineDisposition.duplicate:
      case RealtimeCandlePipelineDisposition.outOfOrder:
      case RealtimeCandlePipelineDisposition.blockedByGap:
        break;
    }
    final latency = update.processedAtUtc.difference(update.receivedAtUtc);
    _record(_pipelineLatencyMicros, _nonNegative(latency).inMicroseconds);
  }

  void recordTransportFault(BitunixPublicStreamFault fault) {
    if (fault.kind == BitunixPublicStreamFaultKind.malformedPayload) {
      malformedPayloadFaults++;
    }
    recordFault(message: fault.message, occurredAtUtc: fault.occurredAtUtc);
  }

  void recordBackpressure(String message, DateTime occurredAtUtc) {
    backpressureFaults++;
    recordFault(message: message, occurredAtUtc: occurredAtUtc);
  }

  void recordFault({required String message, required DateTime occurredAtUtc}) {
    lastFaultMessage = message;
    lastFaultAtUtc = occurredAtUtc;
  }

  RealtimeMarketHealthSnapshot snapshot({
    required RealtimeMarketRuntimeState state,
    required int configuredStreams,
    required int activeShards,
    required int liveShards,
  }) => RealtimeMarketHealthSnapshot(
    state: state,
    configuredStreams: configuredStreams,
    activeShards: activeShards,
    liveShards: liveShards,
    eventsReceived: eventsReceived,
    klineEventsReceived: klineEventsReceived,
    closedCandleEvents: closedCandleEvents,
    gapEvents: gapEvents,
    reconciliationEvents: reconciliationEvents,
    candidateEvaluations: candidateEvaluations,
    candidateCommits: candidateCommits,
    reconnectTransitions: reconnectTransitions,
    malformedPayloadFaults: malformedPayloadFaults,
    backpressureFaults: backpressureFaults,
    p95TransportLag: _p95(_transportLagMicros),
    p95PipelineLatency: _p95(_pipelineLatencyMicros),
    lastEventAtUtc: lastEventAtUtc,
    lastFaultAtUtc: lastFaultAtUtc,
    lastFaultMessage: lastFaultMessage,
  );

  void _record(Queue<int> values, int value) {
    values.addLast(value);
    while (values.length > maximumSamples) {
      values.removeFirst();
    }
  }

  static Duration _p95(Queue<int> values) {
    if (values.isEmpty) return Duration.zero;
    final ordered = values.toList(growable: false)..sort();
    final index = ((ordered.length - 1) * 0.95).ceil();
    return Duration(microseconds: ordered[index]);
  }

  static Duration _nonNegative(Duration value) =>
      value.isNegative ? Duration.zero : value;
}
