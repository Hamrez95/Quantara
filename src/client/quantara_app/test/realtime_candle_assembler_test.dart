import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/market_analysis/domain/market_chart_models.dart';
import 'package:quantara_app/features/owner_alpha/data/realtime_candle_assembler.dart';
import 'package:quantara_app/features/owner_alpha/domain/bitunix_public_stream_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/realtime_candle_pipeline_models.dart';

void main() {
  final key = RealtimeCandleStreamKey(
    symbol: 'BTCUSDT',
    interval: BitunixKlineInterval.fiveMinutes,
  );
  final historyStart = DateTime.utc(2026, 8, 2, 10);

  group('RealtimeCandleAssembler', () {
    test('bootstraps closed history and updates one working candle', () {
      final assembler = RealtimeCandleAssembler();
      final history = _candles(historyStart, 20);
      final bootstrap = assembler.bootstrap(
        key: key,
        closedCandles: history,
        observedAtUtc: DateTime.utc(2026, 8, 2, 11, 40),
        processedAtUtc: DateTime.utc(2026, 8, 2, 11, 40, 0, 20),
      );

      final workingOpen = history.last.openTime.add(const Duration(minutes: 5));
      final update = assembler.apply(
        _event(workingOpen, close: 102),
        processedAtUtc: DateTime.utc(2026, 8, 2, 11, 40, 1),
      );

      expect(bootstrap.disposition, RealtimeCandlePipelineDisposition.bootstrapped);
      expect(update.disposition, RealtimeCandlePipelineDisposition.workingUpdated);
      expect(update.allowsCandidatePreparation, isTrue);
      expect(update.triggersClosedCandleAnalysis, isFalse);
      expect(assembler.snapshotFor(key).workingCandle?.close, 102);
    });

    test('coalesces exact working repeats as duplicate', () {
      final assembler = _bootstrapped(key, historyStart);
      final workingOpen = DateTime.utc(2026, 8, 2, 11, 40);
      final event = _event(workingOpen, close: 102);

      assembler.apply(event, processedAtUtc: DateTime.utc(2026, 8, 2, 11, 40, 1));
      final duplicate = assembler.apply(
        event,
        processedAtUtc: DateTime.utc(2026, 8, 2, 11, 40, 2),
      );

      expect(duplicate.disposition, RealtimeCandlePipelineDisposition.duplicate);
      expect(duplicate.closedCandles, isEmpty);
    });

    test('rollover closes the prior working candle exactly once', () {
      final assembler = _bootstrapped(key, historyStart);
      final workingOpen = DateTime.utc(2026, 8, 2, 11, 40);
      assembler.apply(
        _event(workingOpen, close: 102),
        processedAtUtc: DateTime.utc(2026, 8, 2, 11, 40, 1),
      );

      final rollover = assembler.apply(
        _event(workingOpen.add(const Duration(minutes: 5)), close: 104),
        processedAtUtc: DateTime.utc(2026, 8, 2, 11, 45, 1),
      );

      expect(rollover.disposition, RealtimeCandlePipelineDisposition.candleClosed);
      expect(rollover.closedCandles.single.openTime, workingOpen);
      expect(rollover.triggersClosedCandleAnalysis, isTrue);
      expect(assembler.snapshotFor(key).closedCandles, hasLength(21));
    });

    test('gap blocks candidate preparation until exact REST reconciliation', () {
      final assembler = _bootstrapped(key, historyStart);
      final workingOpen = DateTime.utc(2026, 8, 2, 11, 40);
      assembler.apply(
        _event(workingOpen, close: 102),
        processedAtUtc: DateTime.utc(2026, 8, 2, 11, 40, 1),
      );

      final observedOpen = workingOpen.add(const Duration(minutes: 15));
      final gap = assembler.apply(
        _event(observedOpen, close: 106),
        processedAtUtc: DateTime.utc(2026, 8, 2, 11, 55, 1),
      );
      final blocked = assembler.apply(
        _event(observedOpen.add(const Duration(minutes: 5)), close: 107),
        processedAtUtc: DateTime.utc(2026, 8, 2, 12, 0, 1),
      );

      expect(gap.disposition, RealtimeCandlePipelineDisposition.gapDetected);
      expect(gap.gap?.fromOpenTimeUtc, workingOpen);
      expect(gap.gap?.toOpenTimeExclusiveUtc, observedOpen);
      expect(gap.allowsCandidatePreparation, isFalse);
      expect(blocked.disposition, RealtimeCandlePipelineDisposition.blockedByGap);

      final reconciled = assembler.reconcile(
        key: key,
        replacementClosedCandles: _candles(workingOpen, 3),
        receivedAtUtc: DateTime.utc(2026, 8, 2, 11, 55, 2),
        processedAtUtc: DateTime.utc(2026, 8, 2, 11, 55, 3),
      );

      expect(reconciled.disposition, RealtimeCandlePipelineDisposition.reconciled);
      expect(reconciled.closedCandles, hasLength(3));
      expect(reconciled.triggersClosedCandleAnalysis, isTrue);
      expect(reconciled.workingCandle?.openTime, observedOpen);
      expect(assembler.snapshotFor(key).trusted, isTrue);
    });

    test('rejects partial or shifted reconciliation ranges', () {
      final assembler = _bootstrapped(key, historyStart);
      final workingOpen = DateTime.utc(2026, 8, 2, 11, 40);
      assembler.apply(
        _event(workingOpen, close: 102),
        processedAtUtc: DateTime.utc(2026, 8, 2, 11, 40, 1),
      );
      assembler.apply(
        _event(workingOpen.add(const Duration(minutes: 15)), close: 106),
        processedAtUtc: DateTime.utc(2026, 8, 2, 11, 55, 1),
      );

      expect(
        () => assembler.reconcile(
          key: key,
          replacementClosedCandles: _candles(
            workingOpen.add(const Duration(minutes: 5)),
            2,
          ),
          receivedAtUtc: DateTime.utc(2026, 8, 2, 11, 55, 2),
          processedAtUtc: DateTime.utc(2026, 8, 2, 11, 55, 3),
        ),
        throwsStateError,
      );
      expect(assembler.snapshotFor(key).trusted, isFalse);
    });

    test('rejects an event older than current history', () {
      final assembler = _bootstrapped(key, historyStart);
      final update = assembler.apply(
        _event(DateTime.utc(2026, 8, 2, 11, 30), close: 99),
        processedAtUtc: DateTime.utc(2026, 8, 2, 11, 40),
      );

      expect(update.disposition, RealtimeCandlePipelineDisposition.outOfOrder);
      expect(update.allowsCandidatePreparation, isFalse);
    });
  });
}

RealtimeCandleAssembler _bootstrapped(
  RealtimeCandleStreamKey key,
  DateTime start,
) {
  final assembler = RealtimeCandleAssembler();
  assembler.bootstrap(
    key: key,
    closedCandles: _candles(start, 20),
    observedAtUtc: DateTime.utc(2026, 8, 2, 11, 40),
    processedAtUtc: DateTime.utc(2026, 8, 2, 11, 40, 0, 20),
  );
  return assembler;
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
