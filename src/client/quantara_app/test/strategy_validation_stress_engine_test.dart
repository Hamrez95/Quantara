import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/strategy_lab/data/strategy_validation_stress_engine.dart';
import 'package:quantara_app/features/strategy_lab/domain/strategy_validation_models.dart';

void main() {
  test('trade-order Monte Carlo is deterministic for the same seed', () {
    const samples = [1.2, -1.0, 0.8, -0.4, 1.7, 0.3, -0.8, 1.1];

    final first = StrategyValidationStressEngine.tradeOrderMonteCarlo(
      samples,
      iterations: 500,
      seed: 42,
    );
    final second = StrategyValidationStressEngine.tradeOrderMonteCarlo(
      samples,
      iterations: 500,
      seed: 42,
    );

    expect(first.medianMaximumDrawdownR, second.medianMaximumDrawdownR);
    expect(first.p95MaximumDrawdownR, second.p95MaximumDrawdownR);
    expect(
      first.worstMaximumDrawdownR,
      greaterThanOrEqualTo(first.p95MaximumDrawdownR),
    );
  });

  test('cost and partial-fill stress lowers expectancy', () {
    final results = StrategyValidationStressEngine.stressScenarios(
      List.filled(100, 0.5),
      const [
        ValidationStressScenario(id: 'base'),
        ValidationStressScenario(
          id: 'cost-fill-stress',
          extraCostRPerTrade: 0.1,
          partialFillRatio: 0.7,
          missedFillRate: 0.2,
        ),
      ],
      seed: 7,
    );

    expect(results, hasLength(2));
    expect(results.first.stressedExpectancyR, closeTo(0.5, 0.000001));
    expect(
      results.last.stressedExpectancyR,
      lessThan(results.first.stressedExpectancyR),
    );
    expect(results.last.effectiveTradeCount, lessThan(100));
  });

  test(
    'same-risk no-skill baseline and contextual benchmarks are reproducible',
    () {
      final first = StrategyValidationStressEngine.baselines(
        currentRMulitples: const [1, -1, 2, -0.5, 0.8],
        benchmarkStartPrice: 100,
        benchmarkEndPrice: 110,
        simpleTrendReturnPercent: 6,
        seed: 99,
      );
      final second = StrategyValidationStressEngine.baselines(
        currentRMulitples: const [1, -1, 2, -0.5, 0.8],
        benchmarkStartPrice: 100,
        benchmarkEndPrice: 110,
        simpleTrendReturnPercent: 6,
        seed: 99,
      );

      expect(
        first.sameRiskRandomTimingExpectancyR,
        second.sameRiskRandomTimingExpectancyR,
      );
      expect(first.buyHoldReturnPercent, closeTo(10, 0.000001));
      expect(first.simpleTrendReturnPercent, 6);
      expect(first.currentEngineExpectancyR, greaterThan(0));
    },
  );
}
