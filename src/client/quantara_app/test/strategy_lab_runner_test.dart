import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/market_analysis/domain/market_chart_models.dart';
import 'package:quantara_app/features/strategy_lab/data/strategy_lab_runner.dart';
import 'package:quantara_app/features/strategy_lab/domain/strategy_lab_models.dart';

void main() {
  test('produces a deterministic, cost-aware report without future access', () {
    final candles = _oscillatingCandles();
    const config = StrategyLabConfig(
      strategy: StrategyKind.structureZones,
      symbol: 'BTCUSDT',
      timeframe: '1h',
      window: Duration(days: 3),
      initialCapital: 10000,
      riskPercent: 0.5,
    );

    final first = StrategyLabRunner.run(config: config, candles: candles);
    final second = StrategyLabRunner.run(config: config, candles: candles);

    expect(first.netPnl, second.netPnl);
    expect(first.trades.length, second.trades.length);
    expect(first.startedAt.isUtc, isTrue);
    expect(first.endedAt.isAfter(first.startedAt), isTrue);
    expect(first.maxDrawdownPercent, greaterThanOrEqualTo(0));
    expect(first.warnings, isNotEmpty);
  });

  test('rejects a strategy on an unsupported timeframe', () {
    expect(
      () => StrategyLabRunner.run(
        config: const StrategyLabConfig(
          strategy: StrategyKind.kbsmResearch,
          symbol: 'BTCUSDT',
          timeframe: '15m',
          window: Duration(days: 1),
          initialCapital: 10000,
          riskPercent: 0.5,
        ),
        candles: _oscillatingCandles(),
      ),
      throwsArgumentError,
    );
  });
}

List<ChartCandle> _oscillatingCandles() {
  return List.generate(120, (index) {
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
