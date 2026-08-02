import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/market_analysis/domain/market_chart_models.dart';
import 'package:quantara_app/features/market_analysis/presentation/tradingview_lightweight_chart.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';

void main() {
  test(
    'renders a frozen overlay only when historical candles cover the signal',
    () {
      final signal = _signal();
      final covered = _analysis(
        start: _origin.subtract(const Duration(minutes: 10)),
      );
      final afterSignal = _analysis(
        start: _origin.add(const Duration(minutes: 1)),
      );

      expect(
        ChartSignalOverlayPolicy.canRender(analysis: covered, signal: signal),
        isTrue,
      );
      expect(
        ChartSignalOverlayPolicy.create(analysis: covered, signal: signal),
        isNotNull,
      );
      expect(
        ChartSignalOverlayPolicy.canRender(
          analysis: afterSignal,
          signal: signal,
        ),
        isFalse,
      );
    },
  );

  test(
    'renders immediately when signal was created inside the last candle',
    () {
      final analysis = _analysis(
        start: _origin.subtract(const Duration(minutes: 20)),
      );

      expect(
        ChartSignalOverlayPolicy.canRender(
          analysis: analysis,
          signal: _signal(),
        ),
        isTrue,
      );
    },
  );

  test('rejects a frozen overlay for a different timeframe', () {
    final analysis = _analysis(
      start: _origin.subtract(const Duration(minutes: 10)),
      timeframe: '1h',
    );

    expect(
      ChartSignalOverlayPolicy.canRender(analysis: analysis, signal: _signal()),
      isFalse,
    );
  });
}

final _origin = DateTime.utc(2026, 8, 1, 12);

TimeframeChartAnalysis _analysis({
  required DateTime start,
  String timeframe = '15m',
}) {
  return TimeframeChartAnalysis(
    symbol: 'BTCUSDT',
    timeframe: timeframe,
    candles: [
      for (var index = 0; index < 20; index++)
        ChartCandle(
          openTime: start.add(Duration(minutes: index)),
          open: 100,
          high: 102,
          low: 99,
          close: 101,
          volume: 10,
        ),
    ],
    zones: const [],
    direction: ChartDirection.bullish,
    directionStrength: 0.7,
    volatilityPercent: 1,
    summary: 'test',
    generatedAt: start.add(const Duration(minutes: 20)),
    fingerprint: 'overlay-test-$timeframe-${start.millisecondsSinceEpoch}',
  );
}

SignalJournalEntry _signal() => SignalJournalEntry(
  setupId: 'BTCUSDT|15m|long|frozen',
  symbol: 'BTCUSDT',
  timeframe: '15m',
  direction: TradeDirection.long,
  strategy: AnalysisStrategy.structureZones,
  strategyVersion: 'test/1',
  createdAt: _origin,
  validUntil: _origin.add(const Duration(minutes: 45)),
  entryLower: 99.5,
  entryUpper: 100.5,
  stopLoss: 98,
  targets: const [102, 104, 106],
  maximumLoss: 10,
  positionSize: 5,
  notionalValue: 500,
  estimatedRoundTripCosts: 1,
  recommendedLeverage: 5,
  maximumSafeLeverage: 8,
  selectedLeverage: 5,
  summary: 'test',
  invalidation: 'test',
);
