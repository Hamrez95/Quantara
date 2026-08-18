import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/market_analysis/domain/market_chart_models.dart';
import 'package:quantara_app/features/owner_alpha/data/realtime_contextual_market_analysis.dart';
import 'package:quantara_app/features/owner_alpha/domain/bitunix_public_stream_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/realtime_candle_pipeline_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/realtime_market_runtime_models.dart';

void main() {
  final key = RealtimeCandleStreamKey(
    symbol: 'BTCUSDT',
    interval: BitunixKlineInterval.fifteenMinutes,
  );
  final history = [
    for (var index = 0; index < 20; index++)
      _candle(
        DateTime.utc(2026, 8, 2, 7).add(Duration(minutes: index * 15)),
        100 + index.toDouble(),
      ),
  ];

  test('passes a full immutable trusted snapshot to analysis', () async {
    final analyzer = _RecordingAnalyzer();
    final gateway = SnapshottingRealtimeMarketAnalysisGateway(
      analyzer: analyzer,
    );
    await gateway.synchronize(_bootstrap(key, history));
    final working = _candle(DateTime.utc(2026, 8, 2, 12), 121);
    final update = _update(
      key: key,
      disposition: RealtimeCandlePipelineDisposition.workingUpdated,
      working: working,
    );

    await gateway.synchronize(update);
    final result = await gateway.analyze(update);

    expect(result.isEmpty, isTrue);
    expect(analyzer.contexts, hasLength(1));
    final context = analyzer.contexts.single;
    expect(context.closedCandles, hasLength(20));
    expect(context.workingCandle, same(working));
    expect(context.eventClosedCandles, isEmpty);
    expect(() => context.closedCandles.add(working), throwsUnsupportedError);
  });

  test('appends rollover and keeps the snapshot bounded', () async {
    final analyzer = _RecordingAnalyzer();
    final gateway = SnapshottingRealtimeMarketAnalysisGateway(
      analyzer: analyzer,
      maximumClosedCandlesPerStream: 20,
    );
    await gateway.synchronize(_bootstrap(key, history));
    final closed = _candle(DateTime.utc(2026, 8, 2, 12), 121);
    final working = _candle(DateTime.utc(2026, 8, 2, 12, 15), 122);
    final update = _update(
      key: key,
      disposition: RealtimeCandlePipelineDisposition.candleClosed,
      working: working,
      closed: [closed],
    );

    await gateway.synchronize(update);
    await gateway.analyze(update);

    final context = analyzer.contexts.single;
    expect(context.closedCandles, hasLength(20));
    expect(context.closedCandles.last.openTime, closed.openTime);
    expect(context.closedCandles.first.openTime, history[1].openTime);
    expect(context.triggersClosedCandleAnalysis, isTrue);
    final features = gateway.featuresFor(key);
    expect(features, isNotNull);
    expect(features!.candleCount, 21);
    expect(features.sma20, closeTo(110.55, 1e-9));
  });

  test('blocks analysis while a stream gap is active', () async {
    final analyzer = _RecordingAnalyzer();
    final gateway = SnapshottingRealtimeMarketAnalysisGateway(
      analyzer: analyzer,
    );
    await gateway.synchronize(_bootstrap(key, history));
    final gap = RealtimeCandleGap(
      fromOpenTimeUtc: DateTime.utc(2026, 8, 2, 12),
      toOpenTimeExclusiveUtc: DateTime.utc(2026, 8, 2, 12, 30),
      observedWorkingOpenTimeUtc: DateTime.utc(2026, 8, 2, 12, 30),
    );
    await gateway.synchronize(
      _update(
        key: key,
        disposition: RealtimeCandlePipelineDisposition.gapDetected,
        working: null,
        gap: gap,
      ),
    );
    final working = _candle(DateTime.utc(2026, 8, 2, 12, 30), 123);
    final update = _update(
      key: key,
      disposition: RealtimeCandlePipelineDisposition.workingUpdated,
      working: working,
    );

    await expectLater(gateway.synchronize(update), throwsStateError);
    expect(analyzer.contexts, isEmpty);
  });

  test('requires bootstrap and the exact synchronized event', () async {
    final gateway = SnapshottingRealtimeMarketAnalysisGateway(
      analyzer: _RecordingAnalyzer(),
    );
    final working = _candle(DateTime.utc(2026, 8, 2, 12), 121);
    final update = _update(
      key: key,
      disposition: RealtimeCandlePipelineDisposition.workingUpdated,
      working: working,
    );
    await expectLater(gateway.synchronize(update), throwsStateError);

    await gateway.synchronize(_bootstrap(key, history));
    await gateway.synchronize(update);
    final equivalent = _update(
      key: key,
      disposition: RealtimeCandlePipelineDisposition.workingUpdated,
      working: working,
    );
    await expectLater(gateway.analyze(equivalent), throwsStateError);
  });
}

final class _RecordingAnalyzer implements RealtimeContextualMarketAnalyzer {
  final List<RealtimeCandleAnalysisContext> contexts = [];

  @override
  Future<RealtimeCandidateAnalysisBatch> analyze(
    RealtimeCandleAnalysisContext context,
  ) async {
    contexts.add(context);
    return RealtimeCandidateAnalysisBatch();
  }
}

RealtimeCandlePipelineUpdate _bootstrap(
  RealtimeCandleStreamKey key,
  List<ChartCandle> history,
) => RealtimeCandlePipelineUpdate(
  key: key,
  disposition: RealtimeCandlePipelineDisposition.bootstrapped,
  workingCandle: null,
  closedCandles: history,
  gap: null,
  exchangeTimestampUtc: DateTime.utc(2026, 8, 2, 12),
  receivedAtUtc: DateTime.utc(2026, 8, 2, 12),
  processedAtUtc: DateTime.utc(2026, 8, 2, 12, 0, 0, 100),
);

RealtimeCandlePipelineUpdate _update({
  required RealtimeCandleStreamKey key,
  required RealtimeCandlePipelineDisposition disposition,
  required ChartCandle? working,
  List<ChartCandle> closed = const [],
  RealtimeCandleGap? gap,
}) => RealtimeCandlePipelineUpdate(
  key: key,
  disposition: disposition,
  workingCandle: working,
  closedCandles: closed,
  gap: gap,
  exchangeTimestampUtc: DateTime.utc(2026, 8, 2, 12, 1),
  receivedAtUtc: DateTime.utc(2026, 8, 2, 12, 1, 0, 100),
  processedAtUtc: DateTime.utc(2026, 8, 2, 12, 1, 0, 200),
);

ChartCandle _candle(DateTime openTime, double close) => ChartCandle(
  openTime: openTime,
  open: close - 1,
  high: close + 1,
  low: close - 2,
  close: close,
  volume: 10,
);
