import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/market_analysis/domain/market_chart_models.dart';
import 'package:quantara_app/features/strategy_lab/data/strategy_lab_runner.dart';
import 'package:quantara_app/features/strategy_lab/domain/strategy_lab_models.dart';

void main() {
  test('produces deterministic portfolio-gated leak-free folds', () {
    final candles = _oscillatingCandles();
    const config = StrategyLabConfig(
      strategy: StrategyKind.structureZones,
      symbol: 'BTCUSDT',
      timeframe: '1h',
      window: Duration(days: 3),
      initialCapital: 10000,
      riskPercent: 0.5,
      walkForwardFolds: 4,
    );

    final first = StrategyLabRunner.run(config: config, candles: candles);
    final second = StrategyLabRunner.run(config: config, candles: candles);

    expect(first.netPnl, second.netPnl);
    expect(first.trades.length, second.trades.length);
    expect(first.reservedEntries, second.reservedEntries);
    expect(first.rejectedEntries, second.rejectedEntries);
    expect(first.startedAt.isUtc, isTrue);
    expect(first.endedAt.isAfter(first.startedAt), isTrue);
    expect(first.maxDrawdownPercent, greaterThanOrEqualTo(0));
    expect(first.walkForwardFolds, isNotEmpty);
    expect(first.walkForwardFolds.every((fold) => fold.leakFree), isTrue);
    expect(first.dataLeakageDetected, isFalse);
    expect(
      first.warnings.any((item) => item.contains('PortfolioEntryCandidate')),
      isTrue,
    );
    for (final trade in first.trades) {
      expect(trade.setupId, isNotEmpty);
      expect(trade.reservedRisk, greaterThan(0));
      expect(trade.reservedMargin, greaterThan(0));
    }
  });

  test('appending future candles cannot alter earlier fold boundaries', () {
    final candles = _oscillatingCandles();
    const config = StrategyLabConfig(
      strategy: StrategyKind.structureZones,
      symbol: 'BTCUSDT',
      timeframe: '1h',
      window: Duration(days: 3),
      initialCapital: 10000,
      riskPercent: 0.5,
      walkForwardFolds: 4,
    );
    final original = StrategyLabRunner.run(config: config, candles: candles);
    final extended = StrategyLabRunner.run(
      config: config,
      candles: [
        ...candles,
        ...List.generate(12, (index) {
          final previous = index == 0
              ? candles.last
              : _futureCandle(candles.last, index - 1);
          return _futureCandle(previous, index);
        }),
      ],
    );

    expect(original.walkForwardFolds.every((fold) => fold.leakFree), isTrue);
    expect(extended.walkForwardFolds.every((fold) => fold.leakFree), isTrue);
    expect(original.dataLeakageDetected, isFalse);
    expect(extended.dataLeakageDetected, isFalse);
  });

  test('rejects a professional strategy on an unsupported timeframe', () {
    expect(
      () => StrategyLabRunner.run(
        config: const StrategyLabConfig(
          strategy: StrategyKind.kbsmResearch,
          symbol: 'BTCUSDT',
          timeframe: '1D',
          window: Duration(days: 30),
          initialCapital: 10000,
          riskPercent: 0.5,
        ),
        candles: _dailyCandles(),
      ),
      throwsArgumentError,
    );
  });
}

List<ChartCandle> _oscillatingCandles() {
  return List.generate(160, (index) {
    final block = index ~/ 12;
    final within = index % 12;
    final rising = block.isEven;
    final base = 100 + block * 1.5;
    final open = base + (rising ? within : 12 - within) * 0.7;
    final close = open + (rising ? 0.45 : -0.45);
    return ChartCandle(
      openTime: DateTime.utc(2026, 7, 1).add(Duration(hours: index)),
      open: open,
      high: (open > close ? open : close) + 1.1,
      low: (open < close ? open : close) - 1.1,
      close: close,
      volume: 1000 + within * 30,
    );
  });
}

List<ChartCandle> _dailyCandles() => List.generate(80, (index) {
  final open = 100 + index * 0.2;
  return ChartCandle(
    openTime: DateTime.utc(2026, 1, 1).add(Duration(days: index)),
    open: open,
    high: open + 1,
    low: open - 1,
    close: open + 0.3,
    volume: 1000,
  );
});

ChartCandle _futureCandle(ChartCandle previous, int index) {
  final openTime = previous.openTime.add(const Duration(hours: 1));
  final open = previous.close + (index.isEven ? 0.2 : -0.2);
  final close = open + (index.isEven ? 0.35 : -0.35);
  return ChartCandle(
    openTime: openTime,
    open: open,
    high: (open > close ? open : close) + 0.8,
    low: (open < close ? open : close) - 0.8,
    close: close,
    volume: 1100,
  );
}
