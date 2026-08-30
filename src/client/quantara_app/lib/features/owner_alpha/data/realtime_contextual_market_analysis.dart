import '../../hot_path_performance/domain/rolling_market_features.dart';
import '../../market_analysis/domain/market_chart_models.dart';
import '../domain/realtime_candle_pipeline_models.dart';
import '../domain/realtime_market_runtime_models.dart';
import 'realtime_market_application.dart';

final class RealtimeCandleAnalysisContext {
  RealtimeCandleAnalysisContext({
    required this.update,
    required this.snapshot,
  }) {
    if (update.key != snapshot.key) {
      throw ArgumentError(
        'The analysis update and snapshot must use the same stream.',
      );
    }
    if (!update.streamTrusted || !snapshot.trusted) {
      throw StateError(
        'Untrusted candle state cannot enter realtime analysis.',
      );
    }
    if (update.workingCandle?.openTime != snapshot.workingCandle?.openTime) {
      throw StateError(
        'The analysis snapshot does not match the event working candle.',
      );
    }
  }

  final RealtimeCandlePipelineUpdate update;
  final RealtimeCandleStreamSnapshot snapshot;

  RealtimeCandleStreamKey get key => update.key;
  RealtimeCandlePipelineDisposition get disposition => update.disposition;
  List<ChartCandle> get closedCandles => snapshot.closedCandles;
  List<ChartCandle> get eventClosedCandles => update.closedCandles;
  ChartCandle? get workingCandle => snapshot.workingCandle;
  DateTime get exchangeTimestampUtc => update.exchangeTimestampUtc;
  DateTime get receivedAtUtc => update.receivedAtUtc;
  DateTime get processedAtUtc => update.processedAtUtc;
  bool get triggersClosedCandleAnalysis => update.triggersClosedCandleAnalysis;
}

abstract interface class RealtimeContextualMarketAnalyzer {
  Future<RealtimeCandidateAnalysisBatch> analyze(
    RealtimeCandleAnalysisContext context,
  );
}

final class SnapshottingRealtimeMarketAnalysisGateway
    implements
        RealtimeMarketAnalysisGateway,
        RealtimeMarketAnalysisSynchronizer {
  SnapshottingRealtimeMarketAnalysisGateway({
    required this.analyzer,
    this.maximumStreams = 2000,
    this.maximumClosedCandlesPerStream = 500,
  }) {
    if (maximumStreams < 1) {
      throw ArgumentError.value(maximumStreams, 'maximumStreams');
    }
    if (maximumClosedCandlesPerStream < 20) {
      throw ArgumentError.value(
        maximumClosedCandlesPerStream,
        'maximumClosedCandlesPerStream',
      );
    }
  }

  final RealtimeContextualMarketAnalyzer analyzer;
  final int maximumStreams;
  final int maximumClosedCandlesPerStream;
  final Map<RealtimeCandleStreamKey, _AnalysisStreamState> _states = {};

  RollingMarketFeatureSnapshot? featuresFor(RealtimeCandleStreamKey key) =>
      _states[key]?.rollingFeatures;

  @override
  Future<void> synchronize(RealtimeCandlePipelineUpdate update) async {
    switch (update.disposition) {
      case RealtimeCandlePipelineDisposition.bootstrapped:
        _storeBootstrap(update);
        return;
      case RealtimeCandlePipelineDisposition.gapDetected:
      case RealtimeCandlePipelineDisposition.blockedByGap:
        final state = _requireState(update.key);
        state.gap = update.gap;
        return;
      case RealtimeCandlePipelineDisposition.reconciled:
        final state = _requireState(update.key);
        _appendClosed(state, update.closedCandles);
        state.workingCandle = update.workingCandle;
        state.gap = null;
        state.lastUpdate = update;
        return;
      case RealtimeCandlePipelineDisposition.candleClosed:
        final state = _requireState(update.key);
        _appendClosed(state, update.closedCandles);
        state.workingCandle = update.workingCandle;
        state.lastUpdate = update;
        return;
      case RealtimeCandlePipelineDisposition.workingUpdated:
        final state = _requireState(update.key);
        if (state.gap != null) {
          throw StateError(
            'A working candle cannot update while a gap is active.',
          );
        }
        state.workingCandle = update.workingCandle;
        state.lastUpdate = update;
        return;
      case RealtimeCandlePipelineDisposition.duplicate:
      case RealtimeCandlePipelineDisposition.outOfOrder:
        return;
    }
  }

  @override
  Future<RealtimeCandidateAnalysisBatch> analyze(
    RealtimeCandlePipelineUpdate update,
  ) async {
    final state = _requireState(update.key);
    if (!identical(state.lastUpdate, update)) {
      throw StateError(
        'Realtime analysis requires the synchronized event instance.',
      );
    }
    if (state.gap != null || !update.streamTrusted) {
      throw StateError(
        'Untrusted candle state cannot enter realtime analysis.',
      );
    }
    return analyzer.analyze(
      RealtimeCandleAnalysisContext(
        update: update,
        snapshot: RealtimeCandleStreamSnapshot(
          key: update.key,
          closedCandles: state.closedCandles,
          workingCandle: state.workingCandle,
          gap: state.gap,
        ),
      ),
    );
  }

  void _storeBootstrap(RealtimeCandlePipelineUpdate update) {
    if (update.closedCandles.length < 20 ||
        update.workingCandle != null ||
        update.gap != null) {
      throw StateError('Invalid realtime bootstrap snapshot.');
    }
    if (!_states.containsKey(update.key) && _states.length >= maximumStreams) {
      throw StateError('Realtime analysis stream capacity was exceeded.');
    }
    final retained =
        update.closedCandles.length <= maximumClosedCandlesPerStream
        ? update.closedCandles
        : update.closedCandles.sublist(
            update.closedCandles.length - maximumClosedCandlesPerStream,
          );
    final featureState = RollingMarketFeatureState();
    RollingMarketFeatureSnapshot? rollingFeatures;
    for (final candle in retained) {
      rollingFeatures = featureState.append(candle) ?? rollingFeatures;
    }
    _states[update.key] = _AnalysisStreamState(
      closedCandles: retained,
      lastUpdate: update,
      featureState: featureState,
      rollingFeatures: rollingFeatures,
    );
  }

  _AnalysisStreamState _requireState(RealtimeCandleStreamKey key) {
    final state = _states[key];
    if (state == null) {
      throw StateError('Realtime analysis must be bootstrapped before use.');
    }
    return state;
  }

  void _appendClosed(_AnalysisStreamState state, List<ChartCandle> candles) {
    for (final candle in candles) {
      final last = state.closedCandles.isEmpty
          ? null
          : state.closedCandles.last;
      if (last != null) {
        if (last.openTime == candle.openTime) {
          state.closedCandles[state.closedCandles.length - 1] = candle;
          state.rebuildFeatures();
          continue;
        }
        if (!candle.openTime.isAfter(last.openTime)) {
          throw StateError('Closed candle history cannot move backwards.');
        }
      }
      state.closedCandles.add(candle);
      state.rollingFeatures = state.featureState.append(candle);
      if (state.closedCandles.length > maximumClosedCandlesPerStream) {
        state.closedCandles.removeAt(0);
      }
    }
  }
}

final class _AnalysisStreamState {
  _AnalysisStreamState({
    required List<ChartCandle> closedCandles,
    required this.lastUpdate,
    required this.featureState,
    required this.rollingFeatures,
  }) : closedCandles = List.of(closedCandles);

  final List<ChartCandle> closedCandles;
  RollingMarketFeatureState featureState;
  RollingMarketFeatureSnapshot? rollingFeatures;
  ChartCandle? workingCandle;
  RealtimeCandleGap? gap;
  RealtimeCandlePipelineUpdate lastUpdate;

  void rebuildFeatures() {
    featureState = RollingMarketFeatureState();
    rollingFeatures = null;
    for (final candle in closedCandles) {
      rollingFeatures = featureState.append(candle) ?? rollingFeatures;
    }
  }
}
