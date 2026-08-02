import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/market_analysis/domain/market_chart_models.dart';
import 'package:quantara_app/features/owner_alpha/data/bitunix_candle_backfill_source.dart';
import 'package:quantara_app/features/owner_alpha/data/realtime_candle_assembler.dart';
import 'package:quantara_app/features/owner_alpha/data/realtime_candle_pipeline_coordinator.dart';
import 'package:quantara_app/features/owner_alpha/data/realtime_market_event_bus.dart';
import 'package:quantara_app/features/owner_alpha/domain/bitunix_public_stream_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/realtime_candle_pipeline_models.dart';

void main() {
  final key = RealtimeCandleStreamKey(
    symbol: 'BTCUSDT',
    interval: BitunixKlineInterval.fiveMinutes,
  );
  final historyStart = DateTime.utc(2026, 8, 2, 10);

  group('RealtimeCandlePipelineCoordinator', () {
    test('bootstraps through REST and publishes the trusted snapshot', () async {
      final source = _FakeBackfillSource(
        recent: _candles(historyStart, 20),
      );
      final delivered = <RealtimeCandlePipelineUpdate>[];
      final bus = RealtimeMarketEventBus(handler: delivered.add);
      final coordinator = RealtimeCandlePipelineCoordinator(
        assembler: RealtimeCandleAssembler(),
        backfillSource: source,
        eventBus: bus,
        clock: _clock(),
      );

      final update = await coordinator.bootstrap(key: key, closedCandleLimit: 20);

      expect(update.disposition, RealtimeCandlePipelineDisposition.bootstrapped);
      expect(update.closedCandles, hasLength(20));
      expect(delivered.single, same(update));
      expect(source.recentRequests, 1);
    });

    test('delivers working updates and a rollover without full rescanning', () async {
      final source = _FakeBackfillSource(recent: _candles(historyStart, 20));
      final delivered = <RealtimeCandlePipelineUpdate>[];
      final coordinator = RealtimeCandlePipelineCoordinator(
        assembler: RealtimeCandleAssembler(),
        backfillSource: source,
        eventBus: RealtimeMarketEventBus(handler: delivered.add),
        clock: _clock(),
      );
      await coordinator.bootstrap(key: key, closedCandleLimit: 20);
      final workingOpen = DateTime.utc(2026, 8, 2, 11, 40);

      final working = await coordinator.handleKline(
        _event(workingOpen, close: 102),
      );
      final rollover = await coordinator.handleKline(
        _event(workingOpen.add(const Duration(minutes: 5)), close: 104),
      );

      expect(
        working.single.disposition,
        RealtimeCandlePipelineDisposition.workingUpdated,
      );
      expect(
        rollover.single.disposition,
        RealtimeCandlePipelineDisposition.candleClosed,
      );
      expect(source.rangeRequests, 0);
      expect(
        delivered.map((update) => update.disposition),
        containsAllInOrder([
          RealtimeCandlePipelineDisposition.bootstrapped,
          RealtimeCandlePipelineDisposition.workingUpdated,
          RealtimeCandlePipelineDisposition.candleClosed,
        ]),
      );
    });

    test('publishes a gap before exact REST reconciliation', () async {
      final workingOpen = DateTime.utc(2026, 8, 2, 11, 40);
      final source = _FakeBackfillSource(
        recent: _candles(historyStart, 20),
        range: _candles(workingOpen, 3),
      );
      final delivered = <RealtimeCandlePipelineUpdate>[];
      final coordinator = RealtimeCandlePipelineCoordinator(
        assembler: RealtimeCandleAssembler(),
        backfillSource: source,
        eventBus: RealtimeMarketEventBus(handler: delivered.add),
        clock: _clock(),
      );
      await coordinator.bootstrap(key: key, closedCandleLimit: 20);
      await coordinator.handleKline(_event(workingOpen, close: 102));

      final updates = await coordinator.handleKline(
        _event(workingOpen.add(const Duration(minutes: 15)), close: 106),
      );

      expect(
        updates.map((update) => update.disposition),
        [
          RealtimeCandlePipelineDisposition.gapDetected,
          RealtimeCandlePipelineDisposition.reconciled,
        ],
      );
      expect(source.rangeRequests, 1);
      final gapIndex = delivered.indexWhere(
        (update) =>
            update.disposition == RealtimeCandlePipelineDisposition.gapDetected,
      );
      final reconciledIndex = delivered.indexWhere(
        (update) =>
            update.disposition == RealtimeCandlePipelineDisposition.reconciled,
      );
      expect(gapIndex, greaterThanOrEqualTo(0));
      expect(reconciledIndex, greaterThan(gapIndex));
      expect(updates.last.allowsCandidatePreparation, isTrue);
    });

    test('failed backfill leaves stream blocked and retries before next event', () async {
      final workingOpen = DateTime.utc(2026, 8, 2, 11, 40);
      final source = _FakeBackfillSource(
        recent: _candles(historyStart, 20),
        range: _candles(workingOpen, 3),
      )..failNextRange = true;
      final assembler = RealtimeCandleAssembler();
      final coordinator = RealtimeCandlePipelineCoordinator(
        assembler: assembler,
        backfillSource: source,
        eventBus: RealtimeMarketEventBus(handler: (_) {}),
        clock: _clock(),
      );
      await coordinator.bootstrap(key: key, closedCandleLimit: 20);
      await coordinator.handleKline(_event(workingOpen, close: 102));

      await expectLater(
        coordinator.handleKline(
          _event(workingOpen.add(const Duration(minutes: 15)), close: 106),
        ),
        throwsStateError,
      );
      expect(assembler.snapshotFor(key).trusted, isFalse);

      final recovered = await coordinator.handleKline(
        _event(workingOpen.add(const Duration(minutes: 20)), close: 107),
      );

      expect(
        recovered.map((update) => update.disposition),
        [
          RealtimeCandlePipelineDisposition.reconciled,
          RealtimeCandlePipelineDisposition.candleClosed,
        ],
      );
      expect(assembler.snapshotFor(key).trusted, isTrue);
      expect(source.rangeRequests, 2);
    });

    test('serializes one stream while allowing another stream to progress', () async {
      final ethKey = RealtimeCandleStreamKey(
        symbol: 'ETHUSDT',
        interval: BitunixKlineInterval.fiveMinutes,
      );
      final gate = Completer<void>();
      final source = _FakeBackfillSource(
        recent: _candles(historyStart, 20),
        onRecent: (requestedKey) async {
          if (requestedKey == key) await gate.future;
        },
      );
      final coordinator = RealtimeCandlePipelineCoordinator(
        assembler: RealtimeCandleAssembler(),
        backfillSource: source,
        eventBus: RealtimeMarketEventBus(handler: (_) {}),
        clock: _clock(),
      );

      final btc = coordinator.bootstrap(key: key, closedCandleLimit: 20);
      await Future<void>.delayed(Duration.zero);
      final eth = coordinator.bootstrap(key: ethKey, closedCandleLimit: 20);

      await eth.timeout(const Duration(seconds: 1));
      gate.complete();
      await btc;
    });
  });
}

final class _FakeBackfillSource implements RealtimeCandleBackfillSource {
  _FakeBackfillSource({
    required this.recent,
    this.range = const [],
    this.onRecent,
  });

  final List<ChartCandle> recent;
  final List<ChartCandle> range;
  final Future<void> Function(RealtimeCandleStreamKey key)? onRecent;
  bool failNextRange = false;
  int recentRequests = 0;
  int rangeRequests = 0;

  @override
  Future<List<ChartCandle>> loadRecentClosed({
    required RealtimeCandleStreamKey key,
    required int limit,
    required DateTime nowUtc,
  }) async {
    recentRequests++;
    await onRecent?.call(key);
    return recent.sublist(recent.length - limit);
  }

  @override
  Future<List<ChartCandle>> loadClosedRange({
    required RealtimeCandleStreamKey key,
    required DateTime fromInclusiveUtc,
    required DateTime toExclusiveUtc,
  }) async {
    rangeRequests++;
    if (failNextRange) {
      failNextRange = false;
      throw StateError('injected backfill failure');
    }
    return range
        .where(
          (candle) =>
              !candle.openTime.isBefore(fromInclusiveUtc) &&
              candle.openTime.isBefore(toExclusiveUtc),
        )
        .toList(growable: false);
  }
}

DateTime Function() _clock() {
  var tick = 0;
  return () => DateTime.utc(2026, 8, 2, 12, 30).add(
    Duration(microseconds: tick++),
  );
}

List<ChartCandle> _candles(DateTime start, int count) => [
  for (var index = 0; index < count; index++)
    ChartCandle(
      openTime: start.add(Duration(minutes: index * 5)),
      open: 100 + index.toDouble(),
      high: 102 + index.toDouble(),
      low: 99 + index.toDouble(),
      close: 101 + index.toDouble(),
      volume: 10 + index.toDouble(),
    ),
];

BitunixKlineEvent _event(DateTime openTime, {required double close}) =>
    BitunixKlineEvent(
      symbol: 'BTCUSDT',
      interval: BitunixKlineInterval.fiveMinutes,
      openTimeUtc: openTime,
      open: close - 1,
      high: close + 1,
      low: close - 2,
      close: close,
      baseVolume: 12,
      quoteVolume: 1200,
      exchangeTimestampUtc: openTime.add(const Duration(minutes: 1)),
      receivedAtUtc: openTime.add(const Duration(minutes: 1, milliseconds: 50)),
    );
