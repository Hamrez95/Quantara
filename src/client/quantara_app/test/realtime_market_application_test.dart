import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/market_analysis/domain/market_chart_models.dart';
import 'package:quantara_app/features/owner_alpha/data/bitunix_candle_backfill_source.dart';
import 'package:quantara_app/features/owner_alpha/data/bitunix_public_stream_fleet_factory.dart';
import 'package:quantara_app/features/owner_alpha/data/bitunix_public_stream_transport.dart';
import 'package:quantara_app/features/owner_alpha/data/realtime_candidate_coordinator.dart';
import 'package:quantara_app/features/owner_alpha/data/realtime_candidate_registry.dart';
import 'package:quantara_app/features/owner_alpha/data/realtime_market_application.dart';
import 'package:quantara_app/features/owner_alpha/domain/bitunix_public_stream_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/candidate_audit_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/realtime_candidate_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/realtime_candle_pipeline_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/realtime_market_event_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/realtime_market_runtime_models.dart';

void main() {
  final key = RealtimeCandleStreamKey(
    symbol: 'BTCUSDT',
    interval: BitunixKlineInterval.fifteenMinutes,
  );
  final historyStart = DateTime.utc(2026, 8, 2, 6);

  group('RealtimeMarketUniverse', () {
    test('deduplicates, orders and bounds public subscriptions', () {
      final eth = RealtimeCandleStreamKey(
        symbol: 'ETHUSDT',
        interval: BitunixKlineInterval.oneHour,
      );
      final universe = RealtimeMarketUniverse([eth, key, key]);

      expect(universe.streams.map((stream) => stream.id), [key.id, eth.id]);
      expect(universe.subscriptions, hasLength(2));
      expect(
        universe.subscriptions.map((subscription) => subscription.channel),
        [key.interval.channel, eth.interval.channel],
      );
      expect(
        () => RealtimeMarketUniverse([key, eth], maximumStreams: 1),
        throwsArgumentError,
      );
    });
  });

  group('RealtimeMarketApplication', () {
    test('restores and bootstraps every stream before subscribing', () async {
      final order = <String>[];
      final clock = _MutableClock(DateTime.utc(2026, 8, 2, 10, 59));
      final source = _FakeBackfillSource(
        recent: _candles(historyStart, 20, interval: key.interval.duration),
        order: order,
      );
      final fleetFactory = _FakeFleetFactory(order: order);
      final projection = _FakeProjection(order: order);
      final application = _application(
        key: key,
        source: source,
        fleetFactory: fleetFactory,
        projection: projection,
        analysis: const _EmptyAnalysisGateway(),
        clock: clock,
      );

      await application.start();
      await _flushMicrotasks();

      expect(order.take(3), [
        'projection-restore',
        'backfill-recent',
        'fleet-build',
      ]);
      expect(
        fleetFactory.subscriptions.single.key,
        'BTCUSDT|market_kline_15min',
      );
      expect(application.state, RealtimeMarketRuntimeState.live);
      expect(application.health.configuredStreams, 1);
      expect(application.health.activeShards, 1);
      expect(application.health.liveShards, 1);

      await application.stop();
      expect(application.state, RealtimeMarketRuntimeState.stopped);
      expect(application.health.lastFaultMessage, isNull);
    });

    test(
      'quarantines one failed stream and connects the healthy stream',
      () async {
        final avax = RealtimeCandleStreamKey(
          symbol: 'AVAXUSDT',
          interval: BitunixKlineInterval.fifteenMinutes,
        );
        final clock = _MutableClock(DateTime.utc(2026, 8, 2, 10, 59));
        final source = _SelectiveBackfillSource(
          recent: _candles(historyStart, 20, interval: key.interval.duration),
          failures: {avax.id: const FormatException('invalid AVAX OHLC')},
        );
        final fleetFactory = _FakeFleetFactory();
        final application = RealtimeMarketApplication(
          universe: RealtimeMarketUniverse([key, avax]),
          backfillSource: source,
          fleetFactory: fleetFactory,
          analysisGateway: const _EmptyAnalysisGateway(),
          candidateCoordinator: RealtimeCandidateCoordinator(
            registry: RealtimeCandidateRegistry(),
            auditStore: _FakeAuditStore(),
          ),
          projection: _FakeProjection(),
          closedCandleLimit: 20,
          bootstrapSpacing: Duration.zero,
          clock: clock.call,
          delay: (_) async {},
        );

        await application.start();
        await _flushMicrotasks();

        expect(application.state, RealtimeMarketRuntimeState.live);
        expect(application.health.configuredStreams, 2);
        expect(application.health.activeStreams, 1);
        expect(application.health.quarantinedStreams, 1);
        expect(application.health.bootstrapFaults, 1);
        expect(application.health.degraded, isTrue);
        expect(application.health.operational, isTrue);
        expect(application.health.discoveryHealthy, isFalse);
        expect(fleetFactory.subscriptions, hasLength(1));
        expect(fleetFactory.subscriptions.single.symbol, 'BTCUSDT');
        expect(application.health.lastFaultMessage, contains(avax.id));

        await application.stop();
      },
    );

    test('fails startup when every configured stream is quarantined', () async {
      final avax = RealtimeCandleStreamKey(
        symbol: 'AVAXUSDT',
        interval: BitunixKlineInterval.fifteenMinutes,
      );
      final clock = _MutableClock(DateTime.utc(2026, 8, 2, 10, 59));
      final source = _SelectiveBackfillSource(
        recent: _candles(historyStart, 20, interval: key.interval.duration),
        failures: {
          key.id: const FormatException('invalid BTC OHLC'),
          avax.id: const FormatException('invalid AVAX OHLC'),
        },
      );
      final fleetFactory = _FakeFleetFactory();
      final application = RealtimeMarketApplication(
        universe: RealtimeMarketUniverse([key, avax]),
        backfillSource: source,
        fleetFactory: fleetFactory,
        analysisGateway: const _EmptyAnalysisGateway(),
        candidateCoordinator: RealtimeCandidateCoordinator(
          registry: RealtimeCandidateRegistry(),
          auditStore: _FakeAuditStore(),
        ),
        projection: _FakeProjection(),
        closedCandleLimit: 20,
        bootstrapSpacing: Duration.zero,
        clock: clock.call,
        delay: (_) async {},
      );

      await expectLater(application.start(), throwsStateError);

      expect(application.state, RealtimeMarketRuntimeState.failed);
      expect(application.health.activeStreams, 0);
      expect(application.health.quarantinedStreams, 2);
      expect(application.health.bootstrapFaults, 2);
      expect(fleetFactory.fleets, isEmpty);
      await application.stop();
    });

    test(
      'stops a constructed fleet after synchronous startup failure',
      () async {
        final clock = _MutableClock(DateTime.utc(2026, 8, 2, 10, 59));
        final source = _FakeBackfillSource(
          recent: _candles(historyStart, 20, interval: key.interval.duration),
        );
        final fleetFactory = _FakeFleetFactory(failRunSynchronously: true);
        final application = _application(
          key: key,
          source: source,
          fleetFactory: fleetFactory,
          projection: _FakeProjection(),
          analysis: const _EmptyAnalysisGateway(),
          clock: clock,
        );

        await expectLater(application.start(), throwsStateError);

        expect(fleetFactory.fleet.stopCalls, 1);
        expect(application.state, RealtimeMarketRuntimeState.failed);
        expect(application.health.activeShards, 0);
        await application.stop();
      },
    );

    test('rebootstraps on resume and records reconnect health', () async {
      final clock = _MutableClock(DateTime.utc(2026, 8, 2, 10, 59));
      final source = _FakeBackfillSource(
        recent: _candles(historyStart, 20, interval: key.interval.duration),
      );
      final fleetFactory = _FakeFleetFactory();
      final projection = _FakeProjection();
      final application = _application(
        key: key,
        source: source,
        fleetFactory: fleetFactory,
        projection: projection,
        analysis: const _EmptyAnalysisGateway(),
        clock: clock,
      );

      await application.start();
      await _flushMicrotasks();
      final firstFleet = fleetFactory.fleet;

      await firstFleet.transition(BitunixPublicConnectionState.backingOff);
      await firstFleet.transition(BitunixPublicConnectionState.live);
      await firstFleet.emitFault(
        BitunixPublicStreamFault(
          kind: BitunixPublicStreamFaultKind.malformedPayload,
          message: 'injected malformed payload',
          occurredAtUtc: clock.now,
          shardIndex: 0,
        ),
      );

      expect(application.health.reconnectTransitions, 1);
      expect(application.health.malformedPayloadFaults, 1);
      expect(application.health.discoveryHealthy, isTrue);

      await application.pause();
      expect(application.state, RealtimeMarketRuntimeState.paused);
      expect(firstFleet.stopCalls, 1);

      await application.resume();
      await _flushMicrotasks();

      expect(source.recentRequests, 2);
      expect(projection.restoreCalls, 1);
      expect(fleetFactory.fleets, hasLength(2));
      expect(fleetFactory.fleet, isNot(same(firstFleet)));
      expect(application.state, RealtimeMarketRuntimeState.live);

      await application.stop();
    });

    test(
      'runs public candle through analysis, audit, commit and projection',
      () async {
        final order = <String>[];
        final clock = _MutableClock(DateTime.utc(2026, 8, 2, 10, 59));
        final source = _FakeBackfillSource(
          recent: _candles(historyStart, 20, interval: key.interval.duration),
          order: order,
        );
        final auditStore = _FakeAuditStore(order: order);
        final registry = RealtimeCandidateRegistry();
        final coordinator = RealtimeCandidateCoordinator(
          registry: registry,
          auditStore: auditStore,
        );
        final projection = _FakeProjection(order: order);
        final analysis = _TriggerAnalysisGateway();
        final fleetFactory = _FakeFleetFactory(order: order);
        final application = _application(
          key: key,
          source: source,
          fleetFactory: fleetFactory,
          projection: projection,
          analysis: analysis,
          clock: clock,
          coordinator: coordinator,
        );
        await application.start();
        await _flushMicrotasks();

        clock.now = DateTime.utc(2026, 8, 2, 11, 0, 1);
        await fleetFactory.fleet.emit(
          _event(
            DateTime.utc(2026, 8, 2, 11),
            exchangeTimestampUtc: DateTime.utc(2026, 8, 2, 11, 0, 0, 500),
            receivedAtUtc: DateTime.utc(2026, 8, 2, 11, 0, 0, 700),
            close: 101,
          ),
        );
        expect(projection.applied, isEmpty);

        clock.now = DateTime.utc(2026, 8, 2, 11, 16, 1);
        await fleetFactory.fleet.emit(
          _event(
            DateTime.utc(2026, 8, 2, 11, 15),
            exchangeTimestampUtc: DateTime.utc(2026, 8, 2, 11, 16),
            receivedAtUtc: DateTime.utc(2026, 8, 2, 11, 16, 0, 200),
            close: 102,
          ),
        );

        expect(analysis.dispositions, [
          RealtimeCandlePipelineDisposition.workingUpdated,
          RealtimeCandlePipelineDisposition.candleClosed,
        ]);
        expect(order.indexOf('audit'), greaterThanOrEqualTo(0));
        expect(
          order.indexOf('projection'),
          greaterThan(order.indexOf('audit')),
        );
        expect(
          projection.applied.single.currentStage,
          OpportunityStage.triggered,
        );
        expect(
          registry.candidateFor('setup-1')?.stage,
          OpportunityStage.triggered,
        );
        expect(application.health.klineEventsReceived, 2);
        expect(application.health.closedCandleEvents, 1);
        expect(application.health.candidateEvaluations, 1);
        expect(application.health.candidateCommits, 1);
        expect(application.health.p95TransportLag, isNot(Duration.zero));

        await application.stop();
      },
    );

    test('reconciles an exact gap before allowing analysis again', () async {
      final clock = _MutableClock(DateTime.utc(2026, 8, 2, 10, 59));
      final source = _FakeBackfillSource(
        recent: _candles(historyStart, 20, interval: key.interval.duration),
        range: _candles(
          DateTime.utc(2026, 8, 2, 11),
          3,
          interval: key.interval.duration,
        ),
      );
      final analysis = _RecordingEmptyAnalysisGateway();
      final fleetFactory = _FakeFleetFactory();
      final application = _application(
        key: key,
        source: source,
        fleetFactory: fleetFactory,
        projection: _FakeProjection(),
        analysis: analysis,
        clock: clock,
      );
      await application.start();
      await _flushMicrotasks();

      clock.now = DateTime.utc(2026, 8, 2, 11, 0, 1);
      await fleetFactory.fleet.emit(
        _event(
          DateTime.utc(2026, 8, 2, 11),
          exchangeTimestampUtc: DateTime.utc(2026, 8, 2, 11, 0, 0, 500),
          receivedAtUtc: DateTime.utc(2026, 8, 2, 11, 0, 0, 700),
          close: 101,
        ),
      );

      clock.now = DateTime.utc(2026, 8, 2, 11, 46);
      await fleetFactory.fleet.emit(
        _event(
          DateTime.utc(2026, 8, 2, 11, 45),
          exchangeTimestampUtc: DateTime.utc(2026, 8, 2, 11, 45, 59),
          receivedAtUtc: DateTime.utc(2026, 8, 2, 11, 45, 59, 200),
          close: 105,
        ),
      );

      expect(source.rangeRequests, 1);
      expect(analysis.dispositions, [
        RealtimeCandlePipelineDisposition.workingUpdated,
        RealtimeCandlePipelineDisposition.reconciled,
      ]);
      expect(application.health.gapEvents, 1);
      expect(application.health.reconciliationEvents, 1);

      await application.stop();
    });

    test('does not commit or project when durable audit fails', () async {
      final clock = _MutableClock(DateTime.utc(2026, 8, 2, 10, 59));
      final source = _FakeBackfillSource(
        recent: _candles(historyStart, 20, interval: key.interval.duration),
      );
      final auditStore = _FakeAuditStore()..failAppend = true;
      final registry = RealtimeCandidateRegistry();
      final coordinator = RealtimeCandidateCoordinator(
        registry: registry,
        auditStore: auditStore,
      );
      final projection = _FakeProjection();
      final fleetFactory = _FakeFleetFactory();
      final application = _application(
        key: key,
        source: source,
        fleetFactory: fleetFactory,
        projection: projection,
        analysis: _TriggerAnalysisGateway(),
        clock: clock,
        coordinator: coordinator,
      );
      await application.start();
      await _flushMicrotasks();

      clock.now = DateTime.utc(2026, 8, 2, 11, 0, 1);
      await fleetFactory.fleet.emit(
        _event(
          DateTime.utc(2026, 8, 2, 11),
          exchangeTimestampUtc: DateTime.utc(2026, 8, 2, 11, 0, 0, 500),
          receivedAtUtc: DateTime.utc(2026, 8, 2, 11, 0, 0, 700),
          close: 101,
        ),
      );
      clock.now = DateTime.utc(2026, 8, 2, 11, 16, 1);
      await fleetFactory.fleet.emit(
        _event(
          DateTime.utc(2026, 8, 2, 11, 15),
          exchangeTimestampUtc: DateTime.utc(2026, 8, 2, 11, 16),
          receivedAtUtc: DateTime.utc(2026, 8, 2, 11, 16, 0, 200),
          close: 102,
        ),
      );

      expect(projection.applied, isEmpty);
      expect(
        registry.candidateFor('setup-1')?.stage,
        OpportunityStage.detected,
      );
      expect(application.health.candidateCommits, 0);

      await application.stop();
    });
  });
}

RealtimeMarketApplication _application({
  required RealtimeCandleStreamKey key,
  required _FakeBackfillSource source,
  required _FakeFleetFactory fleetFactory,
  required RealtimeAuditedCandidateProjection projection,
  required RealtimeMarketAnalysisGateway analysis,
  required _MutableClock clock,
  RealtimeCandidateCoordinator? coordinator,
}) {
  final candidateCoordinator =
      coordinator ??
      RealtimeCandidateCoordinator(
        registry: RealtimeCandidateRegistry(),
        auditStore: _FakeAuditStore(),
      );
  return RealtimeMarketApplication(
    universe: RealtimeMarketUniverse([key]),
    backfillSource: source,
    fleetFactory: fleetFactory,
    analysisGateway: analysis,
    candidateCoordinator: candidateCoordinator,
    projection: projection,
    closedCandleLimit: 20,
    bootstrapSpacing: Duration.zero,
    clock: clock.call,
    delay: (_) async {},
  );
}

final class _MutableClock {
  _MutableClock(this.now);

  DateTime now;

  DateTime call() => now;
}

final class _SelectiveBackfillSource implements RealtimeCandleBackfillSource {
  _SelectiveBackfillSource({required this.recent, required this.failures});

  final List<ChartCandle> recent;
  final Map<String, Object> failures;

  @override
  Future<List<ChartCandle>> loadRecentClosed({
    required RealtimeCandleStreamKey key,
    required int limit,
    required DateTime nowUtc,
  }) async {
    final failure = failures[key.id];
    if (failure != null) throw failure;
    return recent.sublist(recent.length - limit);
  }

  @override
  Future<List<ChartCandle>> loadClosedRange({
    required RealtimeCandleStreamKey key,
    required DateTime fromInclusiveUtc,
    required DateTime toExclusiveUtc,
  }) async => const [];
}

final class _FakeBackfillSource implements RealtimeCandleBackfillSource {
  _FakeBackfillSource({
    required this.recent,
    this.range = const [],
    this.order,
  });

  final List<ChartCandle> recent;
  final List<ChartCandle> range;
  final List<String>? order;
  int recentRequests = 0;
  int rangeRequests = 0;

  @override
  Future<List<ChartCandle>> loadRecentClosed({
    required RealtimeCandleStreamKey key,
    required int limit,
    required DateTime nowUtc,
  }) async {
    recentRequests++;
    order?.add('backfill-recent');
    return recent.sublist(recent.length - limit);
  }

  @override
  Future<List<ChartCandle>> loadClosedRange({
    required RealtimeCandleStreamKey key,
    required DateTime fromInclusiveUtc,
    required DateTime toExclusiveUtc,
  }) async {
    rangeRequests++;
    return range
        .where(
          (candle) =>
              !candle.openTime.isBefore(fromInclusiveUtc) &&
              candle.openTime.isBefore(toExclusiveUtc),
        )
        .toList(growable: false);
  }
}

final class _FakeFleetFactory implements RealtimePublicStreamFleetFactory {
  _FakeFleetFactory({this.order, this.failRunSynchronously = false});

  final List<String>? order;
  final bool failRunSynchronously;
  final List<_FakeFleet> fleets = [];
  List<BitunixPublicSubscription> subscriptions = const [];

  _FakeFleet get fleet => fleets.last;

  @override
  RealtimePublicStreamFleet build({
    required Iterable<BitunixPublicSubscription> subscriptions,
    required BitunixStreamEventHandler onEvent,
    required BitunixStreamFaultHandler onFault,
    required BitunixFleetStateHandler onState,
  }) {
    order?.add('fleet-build');
    this.subscriptions = List.unmodifiable(subscriptions);
    final fleet = _FakeFleet(
      onEvent: onEvent,
      onFault: onFault,
      onState: onState,
      failRunSynchronously: failRunSynchronously,
    );
    fleets.add(fleet);
    return fleet;
  }
}

final class _FakeFleet implements RealtimePublicStreamFleet {
  _FakeFleet({
    required this.onEvent,
    required this.onFault,
    required this.onState,
    required this.failRunSynchronously,
  });

  final BitunixStreamEventHandler onEvent;
  final BitunixStreamFaultHandler onFault;
  final BitunixFleetStateHandler onState;
  final bool failRunSynchronously;
  final Completer<void> _stopped = Completer<void>();
  int stopCalls = 0;

  @override
  int get shardCount => 1;

  @override
  Future<void> run() {
    if (failRunSynchronously) {
      throw StateError('injected synchronous fleet startup failure');
    }
    return _runUntilStopped();
  }

  Future<void> _runUntilStopped() async {
    await onState(0, BitunixPublicConnectionState.connecting);
    await onState(0, BitunixPublicConnectionState.live);
    await _stopped.future;
    await onState(0, BitunixPublicConnectionState.stopped);
  }

  Future<void> emit(BitunixPublicStreamEvent event) async {
    await onEvent(event);
  }

  Future<void> emitFault(BitunixPublicStreamFault fault) async {
    await onFault(fault);
  }

  Future<void> transition(BitunixPublicConnectionState state) async {
    await onState(0, state);
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    if (!_stopped.isCompleted) _stopped.complete();
  }
}

final class _EmptyAnalysisGateway implements RealtimeMarketAnalysisGateway {
  const _EmptyAnalysisGateway();

  @override
  Future<RealtimeCandidateAnalysisBatch> analyze(
    RealtimeCandlePipelineUpdate update,
  ) async => RealtimeCandidateAnalysisBatch();
}

final class _RecordingEmptyAnalysisGateway
    implements RealtimeMarketAnalysisGateway {
  final List<RealtimeCandlePipelineDisposition> dispositions = [];

  @override
  Future<RealtimeCandidateAnalysisBatch> analyze(
    RealtimeCandlePipelineUpdate update,
  ) async {
    dispositions.add(update.disposition);
    return RealtimeCandidateAnalysisBatch();
  }
}

final class _TriggerAnalysisGateway implements RealtimeMarketAnalysisGateway {
  final List<RealtimeCandlePipelineDisposition> dispositions = [];
  bool _emitted = false;

  @override
  Future<RealtimeCandidateAnalysisBatch> analyze(
    RealtimeCandlePipelineUpdate update,
  ) async {
    dispositions.add(update.disposition);
    if (_emitted ||
        update.disposition != RealtimeCandlePipelineDisposition.candleClosed) {
      return RealtimeCandidateAnalysisBatch();
    }
    _emitted = true;
    final candidate = RealtimeOpportunityCandidate.fromIdea(
      TradeIdea(
        symbol: update.key.symbol,
        timeframe: update.key.timeframe,
        direction: TradeDirection.long,
        confidencePercent: 85,
        entryLower: 100,
        entryUpper: 103,
        stopLoss: 98,
        targets: const [106, 109],
        riskReward: 2,
        maximumLoss: 5,
        positionSize: 1,
        notionalValue: 102,
        recommendedLeverage: 1,
        maximumSafeLeverage: 3,
        requiredMargin: 102,
        estimatedRoundTripCosts: 0.1,
        setupId: 'setup-1',
        candleClosedAt: DateTime.utc(2026, 8, 2, 11, 15),
        summary: 'test setup',
        invalidation: 'below structure',
        reasons: const ['closed trigger'],
      ),
      detectedAtUtc: update.processedAtUtc,
    );
    return RealtimeCandidateAnalysisBatch(
      candidates: [candidate],
      observations: [
        RealtimeObservationEnvelope(
          eventId: 'event-1',
          setupId: candidate.setupId,
          symbol: candidate.symbol,
          timeframe: candidate.timeframe,
          sequence: 1,
          observation: RealtimeMarketObservation(
            exchangeTimestampUtc: update.exchangeTimestampUtc,
            receivedAtUtc: update.receivedAtUtc,
            evaluatedAtUtc: update.processedAtUtc,
            lastPrice: update.workingCandle!.close,
            qualityScore: 85,
            structureValid: true,
            triggerConfirmed: true,
            triggerCandleClosed: true,
          ),
        ),
      ],
    );
  }
}

final class _FakeAuditStore implements CandidateAuditStore {
  _FakeAuditStore({this.order});

  final List<String>? order;
  final List<CandidateRegistryAuditEvent> events = [];
  bool failAppend = false;

  @override
  Future<CandidateAuditLedger> load() async => CandidateAuditLedger.empty();

  @override
  Future<void> append(CandidateRegistryAuditEvent event) async {
    order?.add('audit');
    if (failAppend) throw StateError('injected audit failure');
    events.add(event);
  }
}

final class _FakeProjection implements RealtimeAuditedCandidateProjection {
  _FakeProjection({this.order});

  final List<String>? order;
  final List<CandidateRegistryAuditEvent> applied = [];
  int restoreCalls = 0;

  @override
  Future<void> restore() async {
    restoreCalls++;
    order?.add('projection-restore');
  }

  @override
  Future<void> apply({
    required CandidateRegistryAuditEvent auditEvent,
    required RealtimeOpportunityCandidate? candidate,
    required CandidateCoordinationOutcome outcome,
    required CandidateAuditPersistenceDecision persistenceDecision,
  }) async {
    order?.add('projection');
    applied.add(auditEvent);
  }
}

List<ChartCandle> _candles(
  DateTime start,
  int count, {
  required Duration interval,
}) => [
  for (var index = 0; index < count; index++)
    ChartCandle(
      openTime: start.add(interval * index),
      open: 100 + index.toDouble(),
      high: 102 + index.toDouble(),
      low: 99 + index.toDouble(),
      close: 101 + index.toDouble(),
      volume: 10 + index.toDouble(),
    ),
];

BitunixKlineEvent _event(
  DateTime openTime, {
  required DateTime exchangeTimestampUtc,
  required DateTime receivedAtUtc,
  required double close,
}) => BitunixKlineEvent(
  symbol: 'BTCUSDT',
  interval: BitunixKlineInterval.fifteenMinutes,
  openTimeUtc: openTime,
  open: close - 1,
  high: close + 1,
  low: close - 2,
  close: close,
  baseVolume: 12,
  quoteVolume: 1200,
  exchangeTimestampUtc: exchangeTimestampUtc,
  receivedAtUtc: receivedAtUtc,
);

Future<void> _flushMicrotasks() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}
