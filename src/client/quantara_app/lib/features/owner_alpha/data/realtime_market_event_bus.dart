import 'dart:async';
import 'dart:collection';

import '../domain/realtime_candle_pipeline_models.dart';

enum RealtimeMarketEventDelivery { delivered, coalesced, staleDropped }

enum RealtimeMarketBackpressureDisposition {
  activeStreamCapacity,
  criticalStreamCapacity,
}

final class RealtimeMarketEventBackpressureException implements Exception {
  const RealtimeMarketEventBackpressureException(
    this.disposition,
    this.message,
  );

  final RealtimeMarketBackpressureDisposition disposition;
  final String message;

  @override
  String toString() => message;
}

typedef RealtimeMarketEventHandler =
    FutureOr<void> Function(RealtimeCandlePipelineUpdate update);

typedef RealtimeMarketEventBusClock = DateTime Function();

final class RealtimeMarketEventBus {
  RealtimeMarketEventBus({
    required this.handler,
    this.maximumPendingPerStream = 64,
    this.maximumActiveStreams = 2000,
    this.maximumWorkingQueueAge = const Duration(seconds: 2),
    RealtimeMarketEventBusClock? clock,
  }) : _clock = clock ?? _utcNow {
    if (maximumPendingPerStream < 1) {
      throw ArgumentError.value(
        maximumPendingPerStream,
        'maximumPendingPerStream',
      );
    }
    if (maximumActiveStreams < 1) {
      throw ArgumentError.value(maximumActiveStreams, 'maximumActiveStreams');
    }
    if (maximumWorkingQueueAge <= Duration.zero ||
        maximumWorkingQueueAge > const Duration(minutes: 1)) {
      throw ArgumentError.value(
        maximumWorkingQueueAge,
        'maximumWorkingQueueAge',
      );
    }
  }

  final RealtimeMarketEventHandler handler;
  final int maximumPendingPerStream;
  final int maximumActiveStreams;
  final Duration maximumWorkingQueueAge;
  final RealtimeMarketEventBusClock _clock;
  final Map<RealtimeCandleStreamKey, _StreamEventQueue> _streams = {};
  var _closed = false;
  var _activeStreamCount = 0;
  var _pendingEventCount = 0;
  var _maximumObservedPendingEventCount = 0;
  var _maximumObservedPendingPerStream = 0;
  var _deliveredCount = 0;
  var _coalescedCount = 0;
  var _backpressureCount = 0;
  var _staleDroppedCount = 0;

  int get activeStreamCount => _activeStreamCount;

  int get pendingEventCount => _pendingEventCount;

  int get maximumObservedPendingEventCount => _maximumObservedPendingEventCount;

  int get maximumObservedPendingPerStream => _maximumObservedPendingPerStream;

  int get deliveredCount => _deliveredCount;

  int get coalescedCount => _coalescedCount;

  int get backpressureCount => _backpressureCount;

  int get staleDroppedCount => _staleDroppedCount;

  Future<RealtimeMarketEventDelivery> publish(
    RealtimeCandlePipelineUpdate update,
  ) {
    if (_closed) {
      return Future.error(StateError('The market event bus is closed.'));
    }

    var stream = _streams[update.key];
    if (stream == null) {
      if (_activeStreamCount >= maximumActiveStreams) {
        _backpressureCount++;
        return Future.error(
          const RealtimeMarketEventBackpressureException(
            RealtimeMarketBackpressureDisposition.activeStreamCapacity,
            'The market event bus reached its active-stream capacity.',
          ),
        );
      }
      stream = _StreamEventQueue();
      _streams[update.key] = stream;
      _activeStreamCount++;
    }

    if (!update.isCritical) {
      final retained = Queue<_PendingMarketEvent>();
      while (stream.queue.isNotEmpty) {
        final pending = stream.queue.removeFirst();
        if (pending.update.isCritical) {
          retained.add(pending);
        } else {
          _pendingEventCount--;
          _coalescedCount++;
          pending.complete(RealtimeMarketEventDelivery.coalesced);
        }
      }
      stream.queue.addAll(retained);
      if (stream.queue.length >= maximumPendingPerStream) {
        _coalescedCount++;
        return Future.value(RealtimeMarketEventDelivery.coalesced);
      }
    } else if (stream.queue.length >= maximumPendingPerStream) {
      _backpressureCount++;
      return Future.error(
        RealtimeMarketEventBackpressureException(
          RealtimeMarketBackpressureDisposition.criticalStreamCapacity,
          'Critical market event capacity was exceeded for ${update.key.id}.',
        ),
      );
    }

    final pending = _PendingMarketEvent(update, enqueuedAtUtc: _clock());
    stream.queue.addLast(pending);
    _recordEnqueue(stream.queue.length);
    if (!stream.draining) {
      stream.draining = true;
      unawaited(_drain(update.key, stream));
    }
    return pending.future;
  }

  Future<void> close({bool drain = true}) async {
    if (_closed) return;
    _closed = true;
    if (drain) {
      await Future.wait([
        for (final stream in _streams.values) stream.drained.future,
      ]);
      return;
    }

    for (final stream in _streams.values) {
      while (stream.queue.isNotEmpty) {
        final pending = stream.queue.removeFirst();
        _pendingEventCount--;
        pending.completeError(
          StateError('The market event bus closed before delivery.'),
        );
      }
      if (!stream.draining && !stream.drained.isCompleted) {
        stream.drained.complete();
      }
    }
  }

  Future<void> _drain(
    RealtimeCandleStreamKey key,
    _StreamEventQueue stream,
  ) async {
    try {
      while (stream.queue.isNotEmpty) {
        final pending = stream.queue.removeFirst();
        _pendingEventCount--;
        final queuedFor = _clock().difference(pending.enqueuedAtUtc);
        if (!pending.update.isCritical &&
            !queuedFor.isNegative &&
            queuedFor > maximumWorkingQueueAge) {
          _staleDroppedCount++;
          pending.complete(RealtimeMarketEventDelivery.staleDropped);
          continue;
        }
        try {
          await handler(pending.update);
          _deliveredCount++;
          pending.complete(RealtimeMarketEventDelivery.delivered);
        } on Object catch (error, stackTrace) {
          pending.completeError(error, stackTrace);
        }
      }
    } finally {
      stream.draining = false;
      if (stream.queue.isNotEmpty) {
        stream.draining = true;
        unawaited(_drain(key, stream));
      } else {
        if (identical(_streams[key], stream)) {
          _streams.remove(key);
          _activeStreamCount--;
        }
        if (!stream.drained.isCompleted) stream.drained.complete();
      }
    }
  }

  void _recordEnqueue(int streamPendingCount) {
    _pendingEventCount++;
    if (_pendingEventCount > _maximumObservedPendingEventCount) {
      _maximumObservedPendingEventCount = _pendingEventCount;
    }
    if (streamPendingCount > _maximumObservedPendingPerStream) {
      _maximumObservedPendingPerStream = streamPendingCount;
    }
  }
}

final class _StreamEventQueue {
  final Queue<_PendingMarketEvent> queue = Queue();
  final Completer<void> drained = Completer<void>();
  bool draining = false;
}

final class _PendingMarketEvent {
  _PendingMarketEvent(this.update, {required this.enqueuedAtUtc});

  final RealtimeCandlePipelineUpdate update;
  final DateTime enqueuedAtUtc;
  final Completer<RealtimeMarketEventDelivery> _completer = Completer();

  Future<RealtimeMarketEventDelivery> get future => _completer.future;

  void complete(RealtimeMarketEventDelivery delivery) {
    if (!_completer.isCompleted) _completer.complete(delivery);
  }

  void completeError(Object error, [StackTrace? stackTrace]) {
    if (_completer.isCompleted) return;
    _completer.completeError(error, stackTrace);
  }
}

DateTime _utcNow() => DateTime.now().toUtc();
