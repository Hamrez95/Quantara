import '../../market_analysis/domain/market_chart_models.dart';
import '../domain/bitunix_public_stream_models.dart';
import '../domain/realtime_candle_pipeline_models.dart';

final class RealtimeCandleAssembler {
  RealtimeCandleAssembler({this.maximumClosedCandlesPerStream = 500}) {
    if (maximumClosedCandlesPerStream < 20) {
      throw ArgumentError.value(
        maximumClosedCandlesPerStream,
        'maximumClosedCandlesPerStream',
        'At least 20 closed candles are required for analysis.',
      );
    }
  }

  final int maximumClosedCandlesPerStream;
  final Map<RealtimeCandleStreamKey, _CandleStreamState> _states = {};

  RealtimeCandlePipelineUpdate bootstrap({
    required RealtimeCandleStreamKey key,
    required List<ChartCandle> closedCandles,
    required DateTime observedAtUtc,
    required DateTime processedAtUtc,
  }) {
    _requireUtc(observedAtUtc, 'observedAtUtc');
    _requireUtc(processedAtUtc, 'processedAtUtc');
    final normalized = _validateClosedSequence(key, closedCandles);
    if (normalized.length < 20) {
      throw ArgumentError.value(
        normalized.length,
        'closedCandles',
        'Bootstrap requires at least 20 closed candles.',
      );
    }

    final retained = normalized.length <= maximumClosedCandlesPerStream
        ? normalized
        : normalized.sublist(normalized.length - maximumClosedCandlesPerStream);
    _states[key] = _CandleStreamState(closedCandles: retained);
    return RealtimeCandlePipelineUpdate(
      key: key,
      disposition: RealtimeCandlePipelineDisposition.bootstrapped,
      workingCandle: null,
      closedCandles: retained,
      gap: null,
      exchangeTimestampUtc: observedAtUtc,
      receivedAtUtc: observedAtUtc,
      processedAtUtc: processedAtUtc,
    );
  }

  RealtimeCandlePipelineUpdate apply(
    BitunixKlineEvent event, {
    required DateTime processedAtUtc,
  }) {
    _requireUtc(processedAtUtc, 'processedAtUtc');
    final key = RealtimeCandleStreamKey(
      symbol: event.symbol,
      interval: event.interval,
    );
    final state = _states[key];
    if (state == null) {
      throw StateError('The candle stream must be bootstrapped before use.');
    }
    final candle = _fromEvent(event);

    final activeGap = state.gap;
    if (activeGap != null) {
      return _update(
        key: key,
        state: state,
        disposition: RealtimeCandlePipelineDisposition.blockedByGap,
        closedCandles: const [],
        gap: activeGap,
        exchangeTimestampUtc: event.exchangeTimestampUtc,
        receivedAtUtc: event.receivedAtUtc,
        processedAtUtc: processedAtUtc,
      );
    }

    final working = state.workingCandle;
    if (working == null) {
      final expected = state.closedCandles.last.openTime.add(
        key.interval.duration,
      );
      if (candle.openTime.isBefore(expected)) {
        return _update(
          key: key,
          state: state,
          disposition: RealtimeCandlePipelineDisposition.outOfOrder,
          closedCandles: const [],
          exchangeTimestampUtc: event.exchangeTimestampUtc,
          receivedAtUtc: event.receivedAtUtc,
          processedAtUtc: processedAtUtc,
        );
      }
      if (candle.openTime.isAfter(expected)) {
        return _blockForGap(
          key: key,
          state: state,
          pendingWorking: candle,
          fromOpenTimeUtc: expected,
          event: event,
          processedAtUtc: processedAtUtc,
        );
      }
      state.workingCandle = candle;
      return _update(
        key: key,
        state: state,
        disposition: RealtimeCandlePipelineDisposition.workingUpdated,
        closedCandles: const [],
        exchangeTimestampUtc: event.exchangeTimestampUtc,
        receivedAtUtc: event.receivedAtUtc,
        processedAtUtc: processedAtUtc,
      );
    }

    if (candle.openTime == working.openTime) {
      if (_sameCandle(candle, working)) {
        return _update(
          key: key,
          state: state,
          disposition: RealtimeCandlePipelineDisposition.duplicate,
          closedCandles: const [],
          exchangeTimestampUtc: event.exchangeTimestampUtc,
          receivedAtUtc: event.receivedAtUtc,
          processedAtUtc: processedAtUtc,
        );
      }
      state.workingCandle = candle;
      return _update(
        key: key,
        state: state,
        disposition: RealtimeCandlePipelineDisposition.workingUpdated,
        closedCandles: const [],
        exchangeTimestampUtc: event.exchangeTimestampUtc,
        receivedAtUtc: event.receivedAtUtc,
        processedAtUtc: processedAtUtc,
      );
    }

    if (candle.openTime.isBefore(working.openTime)) {
      return _update(
        key: key,
        state: state,
        disposition: RealtimeCandlePipelineDisposition.outOfOrder,
        closedCandles: const [],
        exchangeTimestampUtc: event.exchangeTimestampUtc,
        receivedAtUtc: event.receivedAtUtc,
        processedAtUtc: processedAtUtc,
      );
    }

    final expectedNext = working.openTime.add(key.interval.duration);
    if (candle.openTime.isAfter(expectedNext)) {
      return _blockForGap(
        key: key,
        state: state,
        pendingWorking: candle,
        fromOpenTimeUtc: working.openTime,
        event: event,
        processedAtUtc: processedAtUtc,
      );
    }
    if (candle.openTime != expectedNext) {
      return _update(
        key: key,
        state: state,
        disposition: RealtimeCandlePipelineDisposition.outOfOrder,
        closedCandles: const [],
        exchangeTimestampUtc: event.exchangeTimestampUtc,
        receivedAtUtc: event.receivedAtUtc,
        processedAtUtc: processedAtUtc,
      );
    }

    _appendClosed(state, working);
    state.workingCandle = candle;
    return _update(
      key: key,
      state: state,
      disposition: RealtimeCandlePipelineDisposition.candleClosed,
      closedCandles: [working],
      exchangeTimestampUtc: event.exchangeTimestampUtc,
      receivedAtUtc: event.receivedAtUtc,
      processedAtUtc: processedAtUtc,
    );
  }

  RealtimeCandlePipelineUpdate reconcile({
    required RealtimeCandleStreamKey key,
    required List<ChartCandle> replacementClosedCandles,
    required DateTime processedAtUtc,
  }) {
    _requireUtc(processedAtUtc, 'processedAtUtc');
    final state = _states[key];
    if (state == null) {
      throw StateError('The candle stream is not bootstrapped.');
    }
    final gap = state.gap;
    final pendingWorking = state.pendingWorking;
    final pendingExchangeTimestampUtc = state.pendingExchangeTimestampUtc;
    final pendingReceivedAtUtc = state.pendingReceivedAtUtc;
    if (gap == null ||
        pendingWorking == null ||
        pendingExchangeTimestampUtc == null ||
        pendingReceivedAtUtc == null) {
      throw StateError('The candle stream has no active gap to reconcile.');
    }

    final replacements = _validateClosedSequence(key, replacementClosedCandles);
    final expectedCount =
        gap.missingDuration.inMilliseconds ~/
        key.interval.duration.inMilliseconds;
    if (replacements.length != expectedCount || replacements.isEmpty) {
      throw StateError(
        'Backfill did not cover the exact missing candle range.',
      );
    }
    if (replacements.first.openTime != gap.fromOpenTimeUtc ||
        replacements.last.openTime.add(key.interval.duration) !=
            gap.toOpenTimeExclusiveUtc) {
      throw StateError('Backfill boundaries do not match the detected gap.');
    }

    for (final candle in replacements) {
      _appendClosed(state, candle);
    }
    state.workingCandle = pendingWorking;
    state.pendingWorking = null;
    state.pendingExchangeTimestampUtc = null;
    state.pendingReceivedAtUtc = null;
    state.gap = null;

    return _update(
      key: key,
      state: state,
      disposition: RealtimeCandlePipelineDisposition.reconciled,
      closedCandles: replacements,
      exchangeTimestampUtc: pendingExchangeTimestampUtc,
      receivedAtUtc: pendingReceivedAtUtc,
      processedAtUtc: processedAtUtc,
    );
  }

  RealtimeCandleStreamSnapshot snapshotFor(RealtimeCandleStreamKey key) {
    final state = _states[key];
    if (state == null) {
      throw StateError('The candle stream is not bootstrapped.');
    }
    return RealtimeCandleStreamSnapshot(
      key: key,
      closedCandles: state.closedCandles,
      workingCandle: state.workingCandle,
      gap: state.gap,
    );
  }

  RealtimeCandlePipelineUpdate _blockForGap({
    required RealtimeCandleStreamKey key,
    required _CandleStreamState state,
    required ChartCandle pendingWorking,
    required DateTime fromOpenTimeUtc,
    required BitunixKlineEvent event,
    required DateTime processedAtUtc,
  }) {
    final gap = RealtimeCandleGap(
      fromOpenTimeUtc: fromOpenTimeUtc,
      toOpenTimeExclusiveUtc: pendingWorking.openTime,
      observedWorkingOpenTimeUtc: pendingWorking.openTime,
    );
    state.gap = gap;
    state.pendingWorking = pendingWorking;
    state.pendingExchangeTimestampUtc = event.exchangeTimestampUtc;
    state.pendingReceivedAtUtc = event.receivedAtUtc;
    return _update(
      key: key,
      state: state,
      disposition: RealtimeCandlePipelineDisposition.gapDetected,
      closedCandles: const [],
      gap: gap,
      exchangeTimestampUtc: event.exchangeTimestampUtc,
      receivedAtUtc: event.receivedAtUtc,
      processedAtUtc: processedAtUtc,
    );
  }

  RealtimeCandlePipelineUpdate _update({
    required RealtimeCandleStreamKey key,
    required _CandleStreamState state,
    required RealtimeCandlePipelineDisposition disposition,
    required List<ChartCandle> closedCandles,
    required DateTime exchangeTimestampUtc,
    required DateTime receivedAtUtc,
    required DateTime processedAtUtc,
    RealtimeCandleGap? gap,
  }) => RealtimeCandlePipelineUpdate(
    key: key,
    disposition: disposition,
    workingCandle: state.workingCandle,
    closedCandles: closedCandles,
    gap: gap,
    exchangeTimestampUtc: exchangeTimestampUtc,
    receivedAtUtc: receivedAtUtc,
    processedAtUtc: processedAtUtc,
  );

  List<ChartCandle> _validateClosedSequence(
    RealtimeCandleStreamKey key,
    List<ChartCandle> candles,
  ) {
    if (candles.isEmpty || candles.any((candle) => !candle.isValid)) {
      throw ArgumentError('Closed candles must be a non-empty valid sequence.');
    }
    final ordered = List<ChartCandle>.of(candles)
      ..sort((left, right) => left.openTime.compareTo(right.openTime));
    for (var index = 1; index < ordered.length; index++) {
      if (ordered[index].openTime !=
          ordered[index - 1].openTime.add(key.interval.duration)) {
        throw ArgumentError('Closed candles must be strictly contiguous.');
      }
    }
    return ordered;
  }

  void _appendClosed(_CandleStreamState state, ChartCandle candle) {
    final existing = state.closedCandles.isEmpty
        ? null
        : state.closedCandles.last;
    if (existing != null) {
      if (candle.openTime == existing.openTime) {
        state.closedCandles[state.closedCandles.length - 1] = candle;
        return;
      }
      if (!candle.openTime.isAfter(existing.openTime)) {
        throw StateError('A closed candle cannot move history backwards.');
      }
    }
    state.closedCandles.add(candle);
    if (state.closedCandles.length > maximumClosedCandlesPerStream) {
      state.closedCandles.removeAt(0);
    }
  }

  static ChartCandle _fromEvent(BitunixKlineEvent event) => ChartCandle(
    openTime: event.openTimeUtc,
    open: event.open,
    high: event.high,
    low: event.low,
    close: event.close,
    volume: event.baseVolume,
  );

  static bool _sameCandle(ChartCandle left, ChartCandle right) =>
      left.openTime == right.openTime &&
      left.open == right.open &&
      left.high == right.high &&
      left.low == right.low &&
      left.close == right.close &&
      left.volume == right.volume;

  static void _requireUtc(DateTime value, String name) {
    if (!value.isUtc) {
      throw ArgumentError.value(value, name, 'UTC is required.');
    }
  }
}

final class _CandleStreamState {
  _CandleStreamState({required List<ChartCandle> closedCandles})
    : closedCandles = List.of(closedCandles);

  final List<ChartCandle> closedCandles;
  ChartCandle? workingCandle;
  ChartCandle? pendingWorking;
  DateTime? pendingExchangeTimestampUtc;
  DateTime? pendingReceivedAtUtc;
  RealtimeCandleGap? gap;
}
