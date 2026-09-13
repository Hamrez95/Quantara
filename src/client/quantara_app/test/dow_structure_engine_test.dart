import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/market_analysis/data/dow_structure_engine.dart';
import 'package:quantara_app/features/market_analysis/domain/dow_structure_models.dart';
import 'package:quantara_app/features/market_analysis/domain/market_chart_models.dart';

void main() {
  group('DowStructureEngine', () {
    test('is deterministic for identical closed-candle evidence', () {
      final analysis = _waveTrend();

      final first = DowStructureEngine.analyze(analysis: analysis);
      final second = DowStructureEngine.analyze(analysis: analysis);

      expect(first.fingerprint, second.fingerprint);
      expect(first.reasonCodes, second.reasonCodes);
      expect(first.pivots.map((item) => item.reasonCode),
          second.pivots.map((item) => item.reasonCode));
      expect(first.valid, isTrue);
    });

    test('confirmed pivots do not repaint when later candles are appended', () {
      final full = _waveTrend(count: 96);
      final prefixCandles = full.candles.take(78).toList(growable: false);
      final prefix = _analysis(
        candles: prefixCandles,
        generatedAt: prefixCandles.last.openTime.add(const Duration(hours: 1)),
        fingerprint: 'prefix',
      );

      final before = DowStructureEngine.analyze(analysis: prefix);
      final after = DowStructureEngine.analyze(analysis: full);
      final afterByIdentity = {
        for (final pivot in after.pivots)
          '${pivot.scope.name}/${pivot.kind.name}/${pivot.index}': pivot,
      };

      for (final pivot in before.pivots) {
        final identity = '${pivot.scope.name}/${pivot.kind.name}/${pivot.index}';
        final later = afterByIdentity[identity];
        expect(later, isNotNull, reason: identity);
        expect(later!.price, pivot.price, reason: identity);
        expect(later.label, pivot.label, reason: identity);
        expect(later.confirmedAtUtc, pivot.confirmedAtUtc, reason: identity);
      }
    });

    test('wick-only break is failed-break context, never BOS', () {
      final base = _waveTrend(count: 90);
      final initial = DowStructureEngine.analyze(analysis: base);
      final level = initial.external.latestHigh?.price;
      expect(level, isNotNull);
      final candles = base.candles.toList(growable: true);
      final previous = candles.last;
      candles.add(
        ChartCandle(
          openTime: previous.openTime.add(const Duration(hours: 1)),
          open: level! - 0.3,
          high: level + 2,
          low: level - 1,
          close: level - 0.2,
          volume: 1500,
        ),
      );
      final analysis = _analysis(
        candles: candles,
        generatedAt: candles.last.openTime.add(const Duration(hours: 1)),
        fingerprint: 'wick-only',
      );

      final result = DowStructureEngine.analyze(analysis: analysis);
      final types = result.events.map((event) => event.type).toSet();

      expect(types, isNot(contains(DowStructureEventType.bosUp)));
      expect(types, contains(DowStructureEventType.failedBreakUp));
    });

    test('gap invalidates structure for new-entry evidence', () {
      final source = _waveTrend(count: 80);
      final candles = <ChartCandle>[];
      for (var index = 0; index < source.candles.length; index++) {
        final candle = source.candles[index];
        final shift = index >= 40 ? const Duration(hours: 3) : Duration.zero;
        candles.add(
          ChartCandle(
            openTime: candle.openTime.add(shift),
            open: candle.open,
            high: candle.high,
            low: candle.low,
            close: candle.close,
            volume: candle.volume,
          ),
        );
      }
      final result = DowStructureEngine.analyze(
        analysis: _analysis(
          candles: candles,
          generatedAt: candles.last.openTime.add(const Duration(hours: 1)),
          fingerprint: 'gap',
        ),
      );

      expect(result.gapped, isTrue);
      expect(result.valid, isFalse);
      expect(result.reasonCodes, contains('dow:data:gap'));
    });

    test('stale closed candles invalidate structure', () {
      final source = _waveTrend(count: 80);
      final result = DowStructureEngine.analyze(
        analysis: _analysis(
          candles: source.candles,
          generatedAt: source.candles.last.openTime.add(const Duration(hours: 8)),
          fingerprint: 'stale',
        ),
      );

      expect(result.stale, isTrue);
      expect(result.valid, isFalse);
      expect(result.reasonCodes, contains('dow:data:stale'));
    });
  });

  group('DowStructuralAlignmentEngine', () {
    test('a Dow gate can reject but cannot create an entry signal', () {
      final snapshot = DowStructureEngine.analyze(analysis: _waveTrend());
      final alignment = DowStructuralAlignmentEngine.evaluate(
        snapshot: snapshot,
        candidateDirection: ChartDirection.bearish,
        trendContinuation: true,
        rangeCompatible: false,
        entryPrice: 115,
        invalidationPrice: 118,
        firstTargetPrice: 109,
        parentDirection: ChartDirection.bearish,
      );

      expect(alignment.allowed, isFalse);
      expect(
        alignment.reasonCodes,
        contains('dow:gate:external_direction_conflict'),
      );
      expect(alignment.cappedScore, lessThanOrEqualTo(20));
    });
  });
}

TimeframeChartAnalysis _waveTrend({int count = 90}) {
  final base = DateTime.utc(2026, 8, 1);
  final candles = <ChartCandle>[];
  for (var index = 0; index < count; index++) {
    final center = 100 + index * 0.18 + math.sin(index * math.pi / 6) * 2.8;
    final open = center - 0.10;
    final close = center + 0.10;
    candles.add(
      ChartCandle(
        openTime: base.add(Duration(hours: index)),
        open: open,
        high: math.max(open, close) + 0.45,
        low: math.min(open, close) - 0.45,
        close: close,
        volume: 1000 + index * 2,
      ),
    );
  }
  return _analysis(
    candles: candles,
    generatedAt: candles.last.openTime.add(const Duration(hours: 1)),
    fingerprint: 'wave-$count',
  );
}

TimeframeChartAnalysis _analysis({
  required List<ChartCandle> candles,
  required DateTime generatedAt,
  required String fingerprint,
}) => TimeframeChartAnalysis(
  symbol: 'BTCUSDT',
  timeframe: '1h',
  candles: candles,
  zones: const [],
  direction: ChartDirection.bullish,
  directionStrength: 0.75,
  volatilityPercent: 1.1,
  summary: 'Dow synthetic fixture',
  generatedAt: generatedAt,
  fingerprint: fingerprint,
);
