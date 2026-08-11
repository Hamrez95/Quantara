import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/owner_alpha/application/owner_alpha_controller.dart';
import 'package:quantara_app/features/owner_alpha/domain/bitunix_public_stream_models.dart';
import 'package:quantara_app/features/trading_lab/application/trading_lab_benchmark.dart';
import 'package:quantara_app/features/trading_lab/domain/trading_lab_models.dart';

void main() {
  test(
    '30m is available in production and Lab benchmark timeframe universe',
    () {
      expect(OwnerAlphaController.timeframes, contains('30m'));
      expect(
        BitunixKlineInterval.values.map((item) => item.timeframe),
        contains('30m'),
      );
      expect(BitunixKlineInterval.thirtyMinutes.channel, 'market_kline_30min');
    },
  );

  test('benchmark records run capital and fixed 5m-to-1h target universe', () {
    final run = TradingLabRun(
      manifest: TradingLabRunManifest(
        runId: 'benchmark-run',
        startedAtUtc: DateTime.utc(2026, 8, 11),
        startingEquity: 500,
        riskPercent: 1,
        maximumConcurrentPositions: 2,
        leverage: 5,
        symbols: const ['BTCUSDT'],
        timeframes: const ['5m', '15m', '30m', '1h'],
        strategies: const ['trendPullback@test'],
      ),
    );
    final matrix = buildTradingLabBenchmarkMatrix([
      run,
    ], generatedAtUtc: DateTime.utc(2026, 8, 11, 1));
    expect(matrix['targetTimeframes'], ['5m', '15m', '30m', '1h']);
    final configs = matrix['runConfigurations']! as List<Object?>;
    final first = configs.single as Map<String, Object?>;
    expect(first['startingEquity'], 500);
    expect(first['maximumConcurrentPositions'], 2);
    expect(matrix['rankingStatus'], 'insufficient_evidence');
  });
}
