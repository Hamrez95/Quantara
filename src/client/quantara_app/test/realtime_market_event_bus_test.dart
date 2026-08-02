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

      expect(
        observed,
        [
          RealtimeCandlePipelineDisposition.workingUpdated,
          RealtimeCandlePipelineDisposition.candleClosed,
          RealtimeCandlePipelineDisposition.gapDetected,
        ],
      );
      expect(deliveries, everyElement(RealtimeMarketEventDelivery.delivered));
    });

    test('processes independent streams concurrently', () async {
      final btcGate = Completer<void>();
      final btcStarted = Completer<void>();
      final ethDelivered = Completer<void>();
      final bus = RealtimeMarketEventBus(
        handler: (update) async {
          if (update.key.symbol == 'BTCUSDT') {
            btcStarted.complete();
            await btcGate.future;
          } else {
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

    test('coalesces queued working updates but never critical events', () async {
      final gate = Completer<void>();
      var calls = 0;
      final bus = RealtimeMarketEventBus(
        handler: (update) async {
          calls++;
          if (calls == 1) await gate.future;
        },
      );

      final first = bus.publish(
        _update(RealtimeCandlePipelineDisposition.workingUpdated, close: 101),
      );
      await Future<void>.delayed(Duration.zero);
      final staleQueued = bus.publish(
        _update(RealtimeCandlePipelineDisposition.workingUpdated, close: 102),
      );
      final latestQueued = bus.publish(
        _update(RealtimeCandlePipelineDisposition.workingUpdated, close: 103),
      );
      final critical = bus.publish(
        _update(RealtimeCandlePipelineDisposition.candleClosed, close: 104),
      );

      expect(
        await staleQueued,
        RealtimeMarketEventDelivery.coalesced,
      );
      gate.complete();
      expect(await first, RealtimeMarketEventDelivery.delivered);
      expect(await latestQueued, RealtimeMarketEventDelivery.delivered);
      expect(await critical, RealtimeMarketEventDelivery.delivered);
      expect(bus.coalescedCount, 1);
      expect(calls, 3);
    });

    test('fails closed when critical per-stream capacity is exceeded', () async {
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
        throwsA(isA<RealtimeMarketEventBackpressureException>()),
      );
      gate.complete();
      await first;
      await second;
      expect(bus.backpressureCount, 1);
    });

    test('handler failure does not poison later events for the stream', () async {
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
    });
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
  final gap = disposition == RealtimeCandlePipelineDisposition.gapDetected ||
          disposition == RealtimeCandlePipelineDisposition.blockedByGap
      ? RealtimeCandleGap(
          fromOpenTimeUtc: openTime,
          toOpenTimeExclusiveUtc: openTime.add(const Duration(minutes: 5)),
          observedWorkingOpenTimeUtc: openTime.add(
            const Duration(minutes: 5),
          ),
        )
      : null;
  return RealtimeCandlePipelineUpdate(
    key: RealtimeCandleStreamKey(
      symbol: symbol,
      interval: BitunixKlineInterval.fiveMinutes,
    ),
    disposition: disposition,
    workingCandle: candle,
    closedCandles:
        disposition == RealtimeCandlePipelineDisposition.candleClosed
        ? [candle]
        : const [],
    gap: gap,
    exchangeTimestampUtc: openTime.add(const Duration(minutes: 1)),
    receivedAtUtc: openTime.add(const Duration(minutes: 1, milliseconds: 20)),
    processedAtUtc: openTime.add(const Duration(minutes: 1, milliseconds: 40)),
  );
}
