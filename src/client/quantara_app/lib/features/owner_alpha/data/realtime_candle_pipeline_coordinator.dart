import 'dart:async';

import '../domain/bitunix_public_stream_models.dart';
import '../domain/realtime_candle_pipeline_models.dart';
import 'bitunix_candle_backfill_source.dart';
import 'realtime_candle_assembler.dart';
import 'realtime_market_event_bus.dart';

typedef RealtimeCandleUtcClock = DateTime Function();

final class RealtimeCandlePipelineCoordinator {
  RealtimeCandlePipelineCoordinator({
    required this.assembler,
    required this.backfillSource,
    required this.eventBus,
    RealtimeCandleUtcClock? clock,
  }) : clock = clock ?? _utcNow;

  final RealtimeCandleAssembler assembler;
  final RealtimeCandleBackfillSource backfillSource;
  final RealtimeMarketEventBus eventBus;
  final RealtimeCandleUtcClock clock;
  final Map<RealtimeCandleStreamKey, Future<void>> _operationTails = {};

  Future<RealtimeCandlePipelineUpdate> bootstrap({
    required RealtimeCandleStreamKey key,
    int closedCandleLimit = 200,
  }) {
    return _serialize(key, () async {
      final now = clock();
      final candles = await backfillSource.loadRecentClosed(
        key: key,
        limit: closedCandleLimit,
        nowUtc: now,
      );
      final update = assembler.bootstrap(
        key: key,
        closedCandles: candles,
        observedAtUtc: now,
        processedAtUtc: clock(),
      );
      await eventBus.publish(update);
      return update;
    });
  }

  Future<List<RealtimeCandlePipelineUpdate>> handleKline(
    BitunixKlineEvent event,
  ) {
    final key = RealtimeCandleStreamKey(
      symbol: event.symbol,
      interval: event.interval,
    );
    return _serialize(key, () async {
      final emitted = <RealtimeCandlePipelineUpdate>[];
      final before = assembler.snapshotFor(key);
      if (!before.trusted) {
        emitted.add(await _reconcile(key));
      }

      final update = assembler.apply(event, processedAtUtc: clock());
      emitted.add(update);
      await eventBus.publish(update);
      if (update.disposition ==
          RealtimeCandlePipelineDisposition.gapDetected) {
        emitted.add(await _reconcile(key));
      }
      return List.unmodifiable(emitted);
    });
  }

  Future<RealtimeCandlePipelineUpdate> reconcile(
    RealtimeCandleStreamKey key,
  ) => _serialize(key, () => _reconcile(key));

  Future<RealtimeCandlePipelineUpdate> _reconcile(
    RealtimeCandleStreamKey key,
  ) async {
    final snapshot = assembler.snapshotFor(key);
    final gap = snapshot.gap;
    if (gap == null) {
      throw StateError('The candle stream has no gap to reconcile.');
    }
    final replacements = await backfillSource.loadClosedRange(
      key: key,
      fromInclusiveUtc: gap.fromOpenTimeUtc,
      toExclusiveUtc: gap.toOpenTimeExclusiveUtc,
    );
    final update = assembler.reconcile(
      key: key,
      replacementClosedCandles: replacements,
      processedAtUtc: clock(),
    );
    await eventBus.publish(update);
    return update;
  }

  Future<T> _serialize<T>(
    RealtimeCandleStreamKey key,
    Future<T> Function() operation,
  ) {
    final previous = _operationTails[key] ?? Future.value();
    final result = previous.then((_) => operation());
    final tail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _operationTails[key] = tail;
    unawaited(
      tail.whenComplete(() {
        if (identical(_operationTails[key], tail)) {
          _operationTails.remove(key);
        }
      }),
    );
    return result;
  }

  static DateTime _utcNow() => DateTime.now().toUtc();
}
