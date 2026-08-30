import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/market_analysis/domain/market_chart_models.dart';
import 'package:quantara_app/features/owner_alpha/data/bitunix_candle_backfill_source.dart';
import 'package:quantara_app/features/owner_alpha/data/bitunix_public_stream_transport.dart';
import 'package:quantara_app/features/owner_alpha/data/bitunix_web_socket_adapter.dart';
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
  group('RealtimeMarketApplication end to end', () {
    test(
      'reconnects a fake public socket without duplicating a candidate',
      () async {
        final key = RealtimeCandleStreamKey(
          symbol: 'BTCUSDT',
          interval: BitunixKlineInterval.fiveMinutes,
        );
        final clock = _MutableClock(DateTime.utc(2026, 8, 2, 11, 59, 59));
        final firstSocket = _FakeSocket();
        final secondSocket = _FakeSocket();
        final connector = _QueueConnector([firstSocket, secondSocket]);
        final auditStore = _FakeAuditStore();
        final registry = RealtimeCandidateRegistry();
        final projection = _RecordingProjection();
        final analysis = _ClosedCandleAnalysisGateway();
        final application = _application(
          universe: RealtimeMarketUniverse([key]),
          connector: connector,
          clock: clock,
          analysisGateway: analysis,
          candidateCoordinator: RealtimeCandidateCoordinator(
            registry: registry,
            auditStore: auditStore,
          ),
          projection: projection,
        );

        await application.start();
        await _waitUntil(
          () => firstSocket.sent.isNotEmpty,
          description: 'first public subscription',
        );

        clock.now = DateTime.utc(2026, 8, 2, 12, 2, 0, 200);
        firstSocket.add(
          _klinePayload(
            key,
            exchangeTimestampUtc: DateTime.utc(2026, 8, 2, 12, 2),
            close: 101,
          ),
        );
        await _waitUntil(
          () => application.health.klineEventsReceived == 1,
          description: 'first working Kline delivery',
        );

        await firstSocket.serverClose();
        await _waitUntil(
          () => connector.connectCount == 2,
          description: 'second socket connection',
        );
        await _waitUntil(
          () => secondSocket.sent.isNotEmpty,
          description: 'second public subscription',
        );

        secondSocket.add(
          _klinePayload(
            key,
            exchangeTimestampUtc: DateTime.utc(2026, 8, 2, 12, 2),
            close: 101,
          ),
        );
        await _waitUntil(
          () => application.health.klineEventsReceived == 2,
          description: 'replayed working Kline delivery',
        );

        clock.now = DateTime.utc(2026, 8, 2, 12, 6, 0, 200);
        secondSocket.add(
          _klinePayload(
            key,
            exchangeTimestampUtc: DateTime.utc(2026, 8, 2, 12, 6),
            close: 102,
          ),
        );
        await _waitUntil(
          () => projection.applied.length == 1,
          description: 'audited candidate projection',
        );

        expect(connector.connectCount, 2);
        expect(analysis.dispositions, [
          RealtimeCandlePipelineDisposition.workingUpdated,
          RealtimeCandlePipelineDisposition.candleClosed,
        ]);
        expect(auditStore.events, hasLength(1));
        expect(projection.restoreCalls, 1);
        expect(projection.applied, hasLength(1));
        expect(application.health.reconnectTransitions, 1);
        expect(application.health.candidateEvaluations, 1);
        expect(application.health.candidateCommits, 1);
        expect(
          registry.candidateFor('e2e-setup')?.stage,
          OpportunityStage.triggered,
        );

        await application.stop();
      },
    );

    test(
      'keeps 100 symbols across five timeframes bounded and sub-second',
      () async {
        const intervals = [
          BitunixKlineInterval.fiveMinutes,
          BitunixKlineInterval.fifteenMinutes,
          BitunixKlineInterval.oneHour,
          BitunixKlineInterval.fourHours,
          BitunixKlineInterval.oneDay,
        ];
        final streams = [
          for (var symbolIndex = 0; symbolIndex < 100; symbolIndex++)
            for (final interval in intervals)
              RealtimeCandleStreamKey(
                symbol: 'Q${symbolIndex.toString().padLeft(3, '0')}USDT',
                interval: interval,
              ),
        ];
        final universe = RealtimeMarketUniverse(streams);
        final clock = _MutableClock(DateTime.utc(2026, 8, 2, 12, 0, 30, 200));
        final sockets = [_FakeSocket(), _FakeSocket()];
        final connector = _QueueConnector(sockets);
        final application = _application(
          universe: universe,
          connector: connector,
          clock: clock,
          analysisGateway: const _EmptyAnalysisGateway(),
          candidateCoordinator: RealtimeCandidateCoordinator(
            registry: RealtimeCandidateRegistry(),
            auditStore: _FakeAuditStore(),
          ),
        );

        await application.start();
        await _waitUntil(
          () => sockets.every((socket) => socket.sent.isNotEmpty),
          description: '500-stream shard subscriptions',
          timeout: const Duration(seconds: 5),
        );

        final subscriptionCount = sockets.fold<int>(0, (total, socket) {
          final message = jsonDecode(socket.sent.first) as Map<String, Object?>;
          return total + (message['args'] as List<Object?>).length;
        });
        expect(subscriptionCount, 500);
        expect(application.health.activeShards, 2);
        expect(application.health.liveShards, 2);

        final stopwatch = Stopwatch()..start();
        for (var index = 0; index < universe.streams.length; index++) {
          final key = universe.streams[index];
          final socket = index < 300 ? sockets.first : sockets.last;
          socket.add(
            _klinePayload(
              key,
              exchangeTimestampUtc: DateTime.utc(2026, 8, 2, 12, 0, 30),
              close: 100 + (index % 10),
            ),
          );
        }
        await _waitUntil(
          () => application.health.klineEventsReceived == 500,
          description: '500-stream Kline delivery',
          timeout: const Duration(seconds: 10),
        );
        stopwatch.stop();

        final health = application.health;
        expect(stopwatch.elapsed, lessThan(const Duration(seconds: 10)));
        expect(health.configuredStreams, 500);
        expect(health.eventsReceived, 500);
        expect(health.klineEventsReceived, 500);
        expect(health.backpressureFaults, 0);
        expect(health.malformedPayloadFaults, 0);
        expect(health.p95TransportLag, lessThan(const Duration(seconds: 1)));
        expect(health.p95PipelineLatency, lessThan(const Duration(seconds: 1)));
        expect(health.discoveryHealthy, isTrue);

        await application.stop();
      },
    );
  });
}

RealtimeMarketApplication _application({
  required RealtimeMarketUniverse universe,
  required _QueueConnector connector,
  required _MutableClock clock,
  required RealtimeMarketAnalysisGateway analysisGateway,
  required RealtimeCandidateCoordinator candidateCoordinator,
  RealtimeAuditedCandidateProjection projection =
      const NoopRealtimeAuditedCandidateProjection(),
}) => RealtimeMarketApplication(
  universe: universe,
  backfillSource: const _GeneratedBackfillSource(),
  fleetFactory: BitunixRealtimePublicStreamFleetFactory(
    connector: connector,
    config: BitunixPublicStreamConfig(
      connectTimeout: const Duration(seconds: 2),
      pingInterval: const Duration(hours: 1),
      silenceTimeout: const Duration(hours: 2),
    ),
    reconnectPolicy: BitunixReconnectPolicy(
      baseDelay: const Duration(seconds: 1),
      maximumDelay: const Duration(seconds: 4),
      maximumJitter: Duration.zero,
    ),
    clock: clock.call,
    delay: (_) async {},
  ),
  analysisGateway: analysisGateway,
  candidateCoordinator: candidateCoordinator,
  projection: projection,
  closedCandleLimit: 20,
  bootstrapSpacing: Duration.zero,
  clock: clock.call,
  delay: (_) async {},
);

final class _GeneratedBackfillSource implements RealtimeCandleBackfillSource {
  const _GeneratedBackfillSource();

  @override
  Future<List<ChartCandle>> loadRecentClosed({
    required RealtimeCandleStreamKey key,
    required int limit,
    required DateTime nowUtc,
  }) async {
    final workingOpen = _workingOpen(key.interval);
    final firstOpen = workingOpen.subtract(key.interval.duration * limit);
    return [
      for (var index = 0; index < limit; index++)
        _candle(firstOpen.add(key.interval.duration * index), index),
    ];
  }

  @override
  Future<List<ChartCandle>> loadClosedRange({
    required RealtimeCandleStreamKey key,
    required DateTime fromInclusiveUtc,
    required DateTime toExclusiveUtc,
  }) async {
    final result = <ChartCandle>[];
    var cursor = fromInclusiveUtc;
    var index = 0;
    while (cursor.isBefore(toExclusiveUtc)) {
      result.add(_candle(cursor, index++));
      cursor = cursor.add(key.interval.duration);
    }
    return result;
  }

  static ChartCandle _candle(DateTime openTime, int index) => ChartCandle(
    openTime: openTime,
    open: 100 + index.toDouble(),
    high: 102 + index.toDouble(),
    low: 99 + index.toDouble(),
    close: 101 + index.toDouble(),
    volume: 10 + index.toDouble(),
  );
}

DateTime _workingOpen(BitunixKlineInterval interval) => switch (interval) {
  BitunixKlineInterval.fiveMinutes ||
  BitunixKlineInterval.fifteenMinutes ||
  BitunixKlineInterval.thirtyMinutes ||
  BitunixKlineInterval.oneHour ||
  BitunixKlineInterval.fourHours => DateTime.utc(2026, 8, 2, 12),
  BitunixKlineInterval.oneDay => DateTime.utc(2026, 8, 2),
};

String _klinePayload(
  RealtimeCandleStreamKey key, {
  required DateTime exchangeTimestampUtc,
  required double close,
}) => jsonEncode({
  'ch': key.interval.channel,
  'symbol': key.symbol,
  'ts': exchangeTimestampUtc.millisecondsSinceEpoch,
  'data': {
    'o': (close - 1).toString(),
    'h': (close + 1).toString(),
    'l': (close - 2).toString(),
    'c': close.toString(),
    'b': '12',
    'q': '1200',
  },
});

final class _ClosedCandleAnalysisGateway
    implements RealtimeMarketAnalysisGateway {
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
        setupId: 'e2e-setup',
        candleClosedAt: update.closedCandles.last.openTime,
        summary: 'end-to-end setup',
        invalidation: 'below structure',
        reasons: const ['closed trigger'],
      ),
      detectedAtUtc: update.processedAtUtc,
    );
    return RealtimeCandidateAnalysisBatch(
      candidates: [candidate],
      observations: [
        RealtimeObservationEnvelope(
          eventId: 'e2e-event-1',
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

final class _EmptyAnalysisGateway implements RealtimeMarketAnalysisGateway {
  const _EmptyAnalysisGateway();

  @override
  Future<RealtimeCandidateAnalysisBatch> analyze(
    RealtimeCandlePipelineUpdate update,
  ) async => RealtimeCandidateAnalysisBatch();
}

final class _FakeAuditStore implements CandidateAuditStore {
  final List<CandidateRegistryAuditEvent> events = [];

  @override
  Future<CandidateAuditLedger> load() async => CandidateAuditLedger.empty();

  @override
  Future<void> append(CandidateRegistryAuditEvent event) async {
    events.add(event);
  }
}

final class _RecordingProjection implements RealtimeAuditedCandidateProjection {
  final List<CandidateRegistryAuditEvent> applied = [];
  int restoreCalls = 0;

  @override
  Future<void> restore() async {
    restoreCalls++;
  }

  @override
  Future<void> apply({
    required CandidateRegistryAuditEvent auditEvent,
    required RealtimeOpportunityCandidate? candidate,
    required CandidateCoordinationOutcome outcome,
    required CandidateAuditPersistenceDecision persistenceDecision,
  }) async {
    applied.add(auditEvent);
  }
}

final class _MutableClock {
  _MutableClock(this.now);

  DateTime now;

  DateTime call() => now;
}

final class _QueueConnector implements BitunixWebSocketConnector {
  _QueueConnector(List<_FakeSocket> sockets) : _sockets = List.of(sockets);

  final List<_FakeSocket> _sockets;
  final List<Uri> uris = [];
  var connectCount = 0;

  @override
  BitunixWebSocket connect(Uri uri) {
    uris.add(uri);
    if (connectCount >= _sockets.length) {
      throw StateError('No fake socket is available for connection attempt.');
    }
    return _sockets[connectCount++];
  }
}

final class _FakeSocket implements BitunixWebSocket {
  final StreamController<Object?> _controller = StreamController<Object?>();
  final List<String> sent = [];
  var _closed = false;

  @override
  Future<void> get ready async {}

  @override
  Stream<Object?> get messages => _controller.stream;

  @override
  void send(String message) {
    if (_closed) throw StateError('Socket is closed.');
    sent.add(message);
  }

  void add(Object? message) {
    if (_closed) throw StateError('Socket is closed.');
    _controller.add(message);
  }

  Future<void> serverClose() async {
    if (_closed) return;
    _closed = true;
    await _controller.close();
  }

  @override
  Future<void> close({int? code, String? reason}) async {
    if (_closed) return;
    _closed = true;
    await _controller.close();
  }
}

Future<void> _waitUntil(
  bool Function() predicate, {
  required String description,
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException(
        'Condition was not reached before timeout: $description.',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
