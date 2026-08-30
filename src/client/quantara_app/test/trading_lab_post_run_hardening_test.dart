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

  test(
    'benchmark records strategy timeframe config and capital dimensions',
    () {
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
          minimumConfidencePercent: 65,
          minimumRiskReward: 1.5,
          maxEstimatedCostToRiskPercent: 25,
          portfolioRiskPercent: 3,
          symbolHeatPercent: 1,
        ),
      );
      final matrix = buildTradingLabBenchmarkMatrix([
        run,
      ], generatedAtUtc: DateTime.utc(2026, 8, 11, 1));

      expect(matrix['schema'], 'quantara.trading_lab.benchmark.v2');
      expect(matrix['targetTimeframes'], ['5m', '15m', '30m', '1h']);
      expect(matrix['minimumClosedTradesForRanking'], 30);
      expect(matrix['rankingStatus'], 'insufficient_evidence');
      expect(matrix['rankedEligibleStrategyTimeframes'], isEmpty);
      expect(matrix['rankedEligibleConfigurations'], isEmpty);
      expect(matrix['rankedEligibleCapital'], isEmpty);

      final configs = matrix['runConfigurations']! as List<Object?>;
      final first = configs.single as Map<String, Object?>;
      expect(first['startingEquity'], 500);
      expect(first['maximumConcurrentPositions'], 2);
      expect(first['minimumConfidencePercent'], 65);
      expect(first['minimumRiskReward'], 1.5);
      expect(first['maxEstimatedCostToRiskPercent'], 25);

      final configMatrix = matrix['configurationMatrix']! as List<Object?>;
      final config = configMatrix.single as Map<String, Object?>;
      expect(config['startingEquity'], 500);
      expect(config['riskPercent'], 1);
      expect(config['leverage'], 5);
      expect(config['evidenceTier'], 'insufficient_sample');

      final capitalMatrix = matrix['capitalMatrix']! as List<Object?>;
      final capital = capitalMatrix.single as Map<String, Object?>;
      expect(capital['startingEquity'], 500);
      expect(capital['evidenceTier'], 'insufficient_sample');
    },
  );
}
