import 'dart:math' as math;

import '../domain/strategy_validation_models.dart';

abstract final class StrategyValidationStressEngine {
  static TradeOrderMonteCarloSummary tradeOrderMonteCarlo(
    Iterable<double> rMultiples, {
    int iterations = 2000,
    int seed = 110,
  }) {
    final samples = rMultiples.toList(growable: false);
    if (samples.length < 2 ||
        samples.any((value) => !value.isFinite) ||
        iterations < 200 ||
        iterations > 20000) {
      throw ArgumentError('Invalid trade-order Monte Carlo input.');
    }
    final random = math.Random(seed);
    final drawdowns = <double>[];
    for (var iteration = 0; iteration < iterations; iteration++) {
      final path = List<double>.of(samples)..shuffle(random);
      var equityR = 0.0;
      var peakR = 0.0;
      var maximumDrawdownR = 0.0;
      for (final value in path) {
        equityR += value;
        peakR = math.max(peakR, equityR);
        maximumDrawdownR = math.max(maximumDrawdownR, peakR - equityR);
      }
      drawdowns.add(maximumDrawdownR);
    }
    drawdowns.sort();
    double percentile(double p) {
      final index = ((drawdowns.length - 1) * p).round();
      return drawdowns[index.clamp(0, drawdowns.length - 1)];
    }

    return TradeOrderMonteCarloSummary(
      sampleSize: samples.length,
      iterations: iterations,
      seed: seed,
      medianMaximumDrawdownR: percentile(0.5),
      p95MaximumDrawdownR: percentile(0.95),
      worstMaximumDrawdownR: drawdowns.last,
    );
  }

  static List<ValidationStressResult> stressScenarios(
    Iterable<double> rMultiples,
    Iterable<ValidationStressScenario> scenarios, {
    int seed = 110,
  }) {
    final samples = rMultiples.toList(growable: false);
    final configured = scenarios.toList(growable: false);
    if (samples.isEmpty ||
        samples.any((value) => !value.isFinite) ||
        configured.isEmpty ||
        configured.any((scenario) => !scenario.valid)) {
      throw ArgumentError('Invalid validation stress input.');
    }

    return List.unmodifiable(
      configured.map((scenario) {
        final random = math.Random(_scenarioSeed(seed, scenario.id));
        var netR = 0.0;
        var fills = 0;
        for (final value in samples) {
          if (random.nextDouble() < scenario.missedFillRate) continue;
          fills += 1;
          netR +=
              value * scenario.partialFillRatio - scenario.extraCostRPerTrade;
        }
        return ValidationStressResult(
          scenarioId: scenario.id,
          sampleSize: samples.length,
          effectiveTradeCount: fills,
          stressedExpectancyR: fills == 0 ? 0 : netR / fills,
          stressedNetR: netR,
        );
      }),
    );
  }

  static ValidationBaselineEvidence baselines({
    required Iterable<double> currentRMulitples,
    required double benchmarkStartPrice,
    required double benchmarkEndPrice,
    required double simpleTrendReturnPercent,
    int seed = 110,
  }) {
    final samples = currentRMulitples.toList(growable: false);
    if (samples.isEmpty ||
        samples.any((value) => !value.isFinite) ||
        !benchmarkStartPrice.isFinite ||
        !benchmarkEndPrice.isFinite ||
        benchmarkStartPrice <= 0 ||
        benchmarkEndPrice <= 0 ||
        !simpleTrendReturnPercent.isFinite) {
      throw ArgumentError('Invalid validation baseline input.');
    }
    final current =
        samples.fold<double>(0, (sum, value) => sum + value) / samples.length;
    final random = math.Random(seed);
    var randomNetR = 0.0;
    for (final value in samples) {
      final absoluteRiskOutcome = value.abs();
      randomNetR += random.nextBool()
          ? absoluteRiskOutcome
          : -absoluteRiskOutcome;
    }
    return ValidationBaselineEvidence(
      currentEngineExpectancyR: current,
      sameRiskRandomTimingExpectancyR: randomNetR / samples.length,
      buyHoldReturnPercent:
          (benchmarkEndPrice - benchmarkStartPrice) / benchmarkStartPrice * 100,
      simpleTrendReturnPercent: simpleTrendReturnPercent,
      seed: seed,
    );
  }

  static int _scenarioSeed(int seed, String id) {
    var hash = seed & 0x7fffffff;
    for (final unit in id.codeUnits) {
      hash = ((hash * 31) + unit) & 0x7fffffff;
    }
    return hash;
  }
}
