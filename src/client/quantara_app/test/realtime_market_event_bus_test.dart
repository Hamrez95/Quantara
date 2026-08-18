import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/market_analysis/domain/market_chart_models.dart';
import 'package:quantara_app/features/owner_alpha/data/realtime_market_event_bus.dart';
import 'package:quantara_app/features/owner_alpha/domain/bitunix_public_stream_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/realtime_candle_pipeline_models.dart';

void main() {
  group('RealtimeMarketEventBus', () {
    test('preserves order within one stream', () async {
      final observed = <RealtimeCandlePipelineDisposition>[];
      final bus = RealtimeMarketEventBus(
        handler: (update) async {
          observed.add(update.disposition);
        },
      );

      final deliveries = await Future.wait([
        bus.publish(_update(RealtimeCandlePipelineDisposition.workingUpdated)),
        bus.publish(_update(RealtimeCandlePipelineDisposition.candleClosed)),
        bus.publish(_update(RealtimeCandlePipelineDisposition.gapDetected)),
      ]);

      expect(observed, [
        RealtimeCandlePipelineDisposition.workingUpdated,
        RealtimeCandlePipelineDisposition.candleClosed,
        RealtimeCandlePipelineDisposition.gapDetected,
      ]);
      expect(deliveries, everyElement(RealtimeMarketEventDelivery.delivered));
    });

    test('processes independent streams concurrently', () async {
      final btcGate = Completer<void>();
      final btcStarted = Completer<void>();
      final ethDelivered = Completer<void>();
      final bus = RealtimeMarketEventBus(
        handler: (update) async {
          if (update.key.symbol == 'BTCUSDT') {
            if (!btcStarted.isCompleted) btcStarted.complete();
            await btcGate.future;
          } else if (!ethDelivered.isCompleted) {
            ethDelivered.complete();
          }
        },
      );

      final btc = bus.publish(
        _update(
          RealtimeCandlePipelineDisposition.candleClosed,
          symbol: 'BTCUSDT',
        ),
      );
      await btcStarted.future;
      final eth = bus.publish(
        _update(
          RealtimeCandlePipelineDisposition.candleClosed,
          symbol: 'ETHUSDT',
        ),
      );

      await ethDelivered.future.timeout(const Duration(seconds: 1));
      btcGate.complete();
      expect(await btc, RealtimeMarketEventDelivery.delivered);
      expect(await eth, RealtimeMarketEventDelivery.delivered);
    });

    test(
      'coalesces queued working updates but never critical events',
      () async {
        final gate = Completer<void>();
        final started = Completer<void>();
        var calls = 0;
        final bus = RealtimeMarketEventBus(
          handler: (update) async {
            calls++;
            if (calls == 1) {
              started.complete();
              await gate.future;
            }
          },
        );

        final first = bus.publish(
          _update(RealtimeCandlePipelineDisposition.workingUpdated, close: 101),
        );
        await started.future;
        final staleQueued = bus.publish(
          _update(RealtimeCandlePipelineDisposition.workingUpdated, close: 102),
        );
        final latestQueued = bus.publish(
          _update(RealtimeCandlePipelineDisposition.workingUpdated, close: 103),
        );
        final critical = bus.publish(
          _update(RealtimeCandlePipelineDisposition.candleClosed, close: 104),
        );

        expect(await staleQueued, RealtimeMarketEventDelivery.coalesced);
        gate.complete();
        expect(await first, RealtimeMarketEventDelivery.delivered);
        expect(await latestQueued, RealtimeMarketEventDelivery.delivered);
        expect(await critical, RealtimeMarketEventDelivery.delivered);
        expect(bus.coalescedCount, 1);
        expect(calls, 3);
      },
    );

    test('never coalesces the bootstrap snapshot', () async {
      final gate = Completer<void>();
      final started = Completer<void>();
      final delivered = <RealtimeCandlePipelineDisposition>[];
      final bus = RealtimeMarketEventBus(
        handler: (update) async {
          delivered.add(update.disposition);
          if (!started.isCompleted) {
            started.complete();
            await gate.future;
          }
        },
      );

      final first = bus.publish(
        _update(RealtimeCandlePipelineDisposition.workingUpdated),
      );
      await started.future;
      final bootstrap = bus.publish(
        _update(RealtimeCandlePipelineDisposition.bootstrapped),
      );
      final latest = bus.publish(
        _update(RealtimeCandlePipelineDisposition.workingUpdated, close: 103),
      );

      gate.complete();
      expect(await first, RealtimeMarketEventDelivery.delivered);
      expect(await bootstrap, RealtimeMarketEventDelivery.delivered);
      expect(await latest, RealtimeMarketEventDelivery.delivered);
      expect(delivered, [
        RealtimeCandlePipelineDisposition.workingUpdated,
        RealtimeCandlePipelineDisposition.bootstrapped,
        RealtimeCandlePipelineDisposition.workingUpdated,
      ]);
    });

    test(
      'fails closed when critical per-stream capacity is exceeded',
      () async {
        final gate = Completer<void>();
        final started = Completer<void>();
        final bus = RealtimeMarketEventBus(
          maximumPendingPerStream: 1,
          handler: (update) async {
            if (!started.isCompleted) started.complete();
            await gate.future;
          },
        );

        final first = bus.publish(
          _update(RealtimeCandlePipelineDisposition.candleClosed),
        );
        await started.future;
        final second = bus.publish(
          _update(RealtimeCandlePipelineDisposition.gapDetected),
        );
        final third = bus.publish(
          _update(RealtimeCandlePipelineDisposition.outOfOrder),
        );

        await expectLater(
          third,
          throwsA(
            isA<RealtimeMarketEventBackpressureException>().having(
              (error) => error.disposition,
              'disposition',
              RealtimeMarketBackpressureDisposition.criticalStreamCapacity,
            ),
          ),
        );
        gate.complete();
        await first;
        await second;
        expect(bus.backpressureCount, 1);
      },
    );

    test(
      'drops stale working updates but retains stale critical events',
      () async {
        var now = DateTime.utc(2026, 8, 2, 12);
        final gate = Completer<void>();
        final started = Completer<void>();
        final observed = <RealtimeCandlePipelineDisposition>[];
        final bus = RealtimeMarketEventBus(
          maximumWorkingQueueAge: const Duration(seconds: 1),
          clock: () => now,
          handler: (update) async {
            observed.add(update.disposition);
            if (!started.isCompleted) {
              started.complete();
              await gate.future;
            }
          },
        );

        final first = bus.publish(
          _update(RealtimeCandlePipelineDisposition.candleClosed),
        );
        await started.future;
        final working = bus.publish(
          _update(RealtimeCandlePipelineDisposition.workingUpdated, close: 102),
        );
        final critical = bus.publish(
          _update(RealtimeCandlePipelineDisposition.gapDetected, close: 103),
        );
        now = now.add(const Duration(seconds: 2));
        gate.complete();

        expect(await first, RealtimeMarketEventDelivery.delivered);
        expect(await working, RealtimeMarketEventDelivery.staleDropped);
        expect(await critical, RealtimeMarketEventDelivery.delivered);
        expect(bus.staleDroppedCount, 1);
        expect(observed, [
          RealtimeCandlePipelineDisposition.candleClosed,
          RealtimeCandlePipelineDisposition.gapDetected,
        ]);
      },
    );

    test(
      'fails closed at active stream capacity with typed evidence',
      () async {
        final gate = Completer<void>();
        final started = Completer<void>();
        final bus = RealtimeMarketEventBus(
          maximumActiveStreams: 1,
          handler: (update) async {
            if (!started.isCompleted) started.complete();
            await gate.future;
          },
        );
        final first = bus.publish(
          _update(RealtimeCandlePipelineDisposition.candleClosed),
        );
        await started.future;

        await expectLater(
          bus.publish(
            _update(
              RealtimeCandlePipelineDisposition.candleClosed,
              symbol: 'ETHUSDT',
            ),
          ),
          throwsA(
            isA<RealtimeMarketEventBackpressureException>().having(
              (error) => error.disposition,
              'disposition',
              RealtimeMarketBackpressureDisposition.activeStreamCapacity,
            ),
          ),
        );
        gate.complete();
        await first;
      },
    );

    test('tracks queue pressure in O(1) bounded counters', () async {
      final gate = Completer<void>();
      final handlersStarted = Completer<void>();
      var activeHandlers = 0;
      final bus = RealtimeMarketEventBus(
        maximumPendingPerStream: 4,
        handler: (update) async {
          activeHandlers++;
          if (activeHandlers == 2 && !handlersStarted.isCompleted) {
            handlersStarted.complete();
          }
          await gate.future;
        },
      );

      final btcFirst = bus.publish(
        _update(
          RealtimeCandlePipelineDisposition.candleClosed,
          symbol: 'BTCUSDT',
        ),
      );
      final ethFirst = bus.publish(
        _update(
          RealtimeCandlePipelineDisposition.candleClosed,
          symbol: 'ETHUSDT',
        ),
      );
      await handlersStarted.future;

      final btcSecond = bus.publish(
        _update(
          RealtimeCandlePipelineDisposition.candleClosed,
          symbol: 'BTCUSDT',
          close: 102,
        ),
      );
      final btcThird = bus.publish(
        _update(
          RealtimeCandlePipelineDisposition.gapDetected,
          symbol: 'BTCUSDT',
          close: 103,
        ),
      );
      final ethSecond = bus.publish(
        _update(
          RealtimeCandlePipelineDisposition.candleClosed,
          symbol: 'ETHUSDT',
          close: 104,
        ),
      );

      expect(bus.pendingEventCount, 3);
      expect(bus.maximumObservedPendingEventCount, 3);
      expect(bus.maximumObservedPendingPerStream, 2);

      gate.complete();
      await Future.wait([btcFirst, ethFirst, btcSecond, btcThird, ethSecond]);
      expect(bus.pendingEventCount, 0);
      expect(bus.maximumObservedPendingEventCount, 3);
      expect(bus.maximumObservedPendingPerStream, 2);
    });

    test(
      'handler failure does not poison later events for the stream',
      () async {
        var calls = 0;
        final bus = RealtimeMarketEventBus(
          handler: (update) async {
            calls++;
            if (calls == 1) throw StateError('injected handler failure');
          },
        );

        final failed = bus.publish(
          _update(RealtimeCandlePipelineDisposition.candleClosed),
        );
        final recovered = bus.publish(
          _update(RealtimeCandlePipelineDisposition.gapDetected),
        );

        await expectLater(failed, throwsStateError);
        expect(await recovered, RealtimeMarketEventDelivery.delivered);
        expect(calls, 2);
      },
    );
  });
}

RealtimeCandlePipelineUpdate _update(
  RealtimeCandlePipelineDisposition disposition, {
  String symbol = 'BTCUSDT',
  double close = 101,
}) {
  final openTime = DateTime.utc(2026, 8, 2, 12);
  final candle = ChartCandle(
    openTime: openTime,
    open: close - 1,
    high: close + 1,
    low: close - 2,
    close: close,
    volume: 10,
  );
  final gap =
      disposition == RealtimeCandlePipelineDisposition.gapDetected ||
          disposition == RealtimeCandlePipelineDisposition.blockedByGap
      ? RealtimeCandleGap(
          fromOpenTimeUtc: openTime,
          toOpenTimeExclusiveUtc: openTime.add(const Duration(minutes: 5)),
          observedWorkingOpenTimeUtc: openTime.add(const Duration(minutes: 5)),
        )
      : null;
  return RealtimeCandlePipelineUpdate(
    key: RealtimeCandleStreamKey(
      symbol: symbol,
      interval: BitunixKlineInterval.fiveMinutes,
    ),
    disposition: disposition,
    workingCandle: candle,
    closedCandles: disposition == RealtimeCandlePipelineDisposition.candleClosed
        ? [candle]
        : const [],
    gap: gap,
    exchangeTimestampUtc: openTime.add(const Duration(minutes: 1)),
    receivedAtUtc: openTime.add(const Duration(minutes: 1, milliseconds: 20)),
    processedAtUtc: openTime.add(const Duration(minutes: 1, milliseconds: 40)),
  );
}
