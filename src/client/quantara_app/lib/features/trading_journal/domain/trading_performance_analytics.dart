import 'dart:math' as math;

import 'trading_journal_models.dart';
import 'trading_journal_projection.dart';
import 'trading_performance_models.dart';

abstract final class TradingPerformanceAnalytics {
  static const minimumInsightSamples = 20;
  static const minimumRatioSamples = 30;
  static const defaultMaximumClosedTrades = 2000;

  static TradingPerformanceReport build({
    required Iterable<TradingJournalProjection> projections,
    TradingPerformanceFilter? filter,
    DateTime? generatedAtUtc,
    int bootstrapSeed = 109,
    int bootstrapIterations = 1000,
    int maximumClosedTrades = defaultMaximumClosedTrades,
  }) {
    if (generatedAtUtc != null && !generatedAtUtc.isUtc) {
      throw ArgumentError('Performance report generation time must be UTC.');
    }
    if (bootstrapIterations < 200 || bootstrapIterations > 20000) {
      throw ArgumentError('Performance bootstrap iterations are out of range.');
    }
    if (maximumClosedTrades <= 0) {
      throw ArgumentError.value(
        maximumClosedTrades,
        'maximumClosedTrades',
        'must be positive',
      );
    }

    final effectiveFilter = filter ?? TradingPerformanceFilter();
    final generatedAt = generatedAtUtc ?? DateTime.now().toUtc();
    final selected = <TradingJournalProjection>[];
    var closedTrades = 0;
    var economicsPendingTrades = 0;

    for (final projection in projections) {
      if (!_matches(projection, effectiveFilter) ||
          projection.state != TradingJournalTradeState.closed) {
        continue;
      }
      closedTrades += 1;
      if (closedTrades > maximumClosedTrades) {
        throw StateError(
          'Trading performance window exceeded $maximumClosedTrades closed trades.',
        );
      }
      final net = projection.netPnl;
      if (projection.economicsPending || net == null || !net.isFinite) {
        economicsPendingTrades += 1;
        continue;
      }
      selected.add(projection);
    }

    selected.sort((left, right) {
      final leftAt = left.closedAt ?? left.decidedAt;
      final rightAt = right.closedAt ?? right.decidedAt;
      final byTime = leftAt.compareTo(rightAt);
      if (byTime != 0) return byTime;
      return left.journalTradeId.compareTo(right.journalTradeId);
    });

    final pnl = selected.map((item) => item.netPnl!).toList(growable: false);
    final rValues = selected
        .map((item) => item.realizedR)
        .whereType<double>()
        .where((value) => value.isFinite)
        .toList(growable: false);
    final wins = pnl.where((value) => value > 0).toList(growable: false);
    final losses = pnl.where((value) => value < 0).toList(growable: false);
    final breakEvens = pnl.where((value) => value == 0).length;
    final grossProfit = wins.fold<double>(0, (sum, value) => sum + value);
    final grossLossAbs = losses.fold<double>(
      0,
      (sum, value) => sum + value.abs(),
    );
    final grossPnl = selected
        .map((item) => item.grossPnl)
        .whereType<double>()
        .where((value) => value.isFinite)
        .fold<double>(0, (sum, value) => sum + value);
    final fees = selected
        .map((item) => item.fees)
        .whereType<double>()
        .where((value) => value.isFinite)
        .fold<double>(0, (sum, value) => sum + value.abs());
    final funding = selected
        .map((item) => item.funding)
        .whereType<double>()
        .where((value) => value.isFinite)
        .fold<double>(0, (sum, value) => sum + value);
    final netPnl = pnl.fold<double>(0, (sum, value) => sum + value);

    final drawdowns = _drawdowns(pnl);
    final maximumDrawdown = drawdowns.isEmpty
        ? 0.0
        : drawdowns.reduce(math.max);
    final averageDrawdown = drawdowns.isEmpty
        ? 0.0
        : drawdowns.fold<double>(0, (sum, value) => sum + value) /
              drawdowns.length;
    final recoveryFactor = maximumDrawdown <= 0
        ? 0.0
        : netPnl / maximumDrawdown;
    final averageWin = wins.isEmpty
        ? 0.0
        : wins.fold<double>(0, (sum, value) => sum + value) / wins.length;
    final averageLoss = losses.isEmpty
        ? 0.0
        : losses.fold<double>(0, (sum, value) => sum + value.abs()) /
              losses.length;
    final payoffRatio = averageLoss <= 0 ? 0.0 : averageWin / averageLoss;
    final expectancyR = rValues.isEmpty
        ? 0.0
        : rValues.fold<double>(0, (sum, value) => sum + value) /
              rValues.length;
    final profitFactor = grossLossAbs <= 0
        ? (grossProfit > 0 ? double.infinity : 0.0)
        : grossProfit / grossLossAbs;

    final streaks = _streaks(pnl);
    var totalTimeInMarket = Duration.zero;
    var riskHours = 0.0;
    var capitalHours = 0.0;
    for (final item in selected) {
      final duration = item.holdingDuration;
      if (duration == null || duration.isNegative) continue;
      totalTimeInMarket += duration;
      final hours = duration.inMicroseconds / Duration.microsecondsPerHour;
      final plan = item.plan;
      if (plan == null) continue;
      if (plan.riskBudget.isFinite && plan.riskBudget > 0) {
        riskHours += plan.riskBudget * hours;
      }
      if (plan.expectedMargin.isFinite && plan.expectedMargin > 0) {
        capitalHours += plan.expectedMargin * hours;
      }
    }

    final mfe = selected
        .map((item) => item.mfe)
        .whereType<double>()
        .where((value) => value.isFinite)
        .toList(growable: false);
    final mae = selected
        .map((item) => item.mae)
        .whereType<double>()
        .where((value) => value.isFinite)
        .toList(growable: false);
    final givebacks = <double>[];
    final captures = <double>[];
    for (final item in selected) {
      final move = item.priceMovePercent;
      final maximum = item.mfe;
      if (move == null ||
          maximum == null ||
          !move.isFinite ||
          !maximum.isFinite ||
          maximum <= 0) {
        continue;
      }
      givebacks.add(math.max(0, maximum - move));
      captures.add((move / maximum * 100).clamp(-500, 500).toDouble());
    }

    final entrySlippage = selected.fold<double>(0, (sum, item) {
      final plan = item.plan;
      final actual = item.entryPrice;
      final quantity = item.initialQuantity;
      if (plan == null ||
          actual == null ||
          !actual.isFinite ||
          quantity == null ||
          !quantity.isFinite ||
          quantity <= 0) {
        return sum;
      }
      final adverse = plan.direction == TradingJournalDirection.short
          ? plan.plannedEntry - actual
          : actual - plan.plannedEntry;
      return sum + math.max(0, adverse) * quantity;
    });

    final uncertainty = _bootstrap(
      rValues,
      seed: bootstrapSeed,
      iterations: bootstrapIterations,
    );
    final warnings = <String>[
      if (selected.length < minimumInsightSamples)
        'Small sample: attribution is descriptive only; do not change strategy parameters from this report.',
      if (rValues.length < minimumRatioSamples)
        'Sharpe/Sortino-like ratios are hidden until at least $minimumRatioSamples priced trades with realized R exist.',
      if (economicsPendingTrades > 0)
        '$economicsPendingTrades closed trade(s) have pending/unknown economics and are excluded from PnL metrics instead of being treated as zero.',
      if (selected.any(
        (item) => item.integrity == TradingJournalIntegrity.unverified,
      ))
        'One or more priced trades are unverified; treat aggregate conclusions as provisional.',
      if (selected.any(
        (item) =>
            item.grossPnl == null || item.fees == null || item.funding == null,
      ))
        'One or more priced fixtures lack a complete gross/fee/funding breakdown; confirmed journal projections should provide all cost components before net economics are trusted.',
      'Entry slippage is attribution only and is not subtracted from net PnL again because confirmed fills already affect journal economics.',
    ];

    return TradingPerformanceReport(
      generatedAtUtc: generatedAt,
      filter: effectiveFilter,
      closedTrades: closedTrades,
      pricedTrades: selected.length,
      economicsPendingTrades: economicsPendingTrades,
      wins: wins.length,
      losses: losses.length,
      breakEvens: breakEvens,
      grossPnl: grossPnl,
      fees: fees,
      funding: funding,
      netPnl: netPnl,
      entrySlippageAttribution: entrySlippage,
      winRatePercent: selected.isEmpty
          ? 0
          : wins.length / selected.length * 100,
      averageWin: averageWin,
      averageLoss: averageLoss,
      payoffRatio: payoffRatio,
      expectancyR: expectancyR,
      profitFactor: profitFactor,
      maximumDrawdown: maximumDrawdown,
      averageDrawdown: averageDrawdown,
      recoveryFactor: recoveryFactor,
      sharpeLike: rValues.length < minimumRatioSamples
          ? null
          : _sharpe(rValues),
      sortinoLike: rValues.length < minimumRatioSamples
          ? null
          : _sortino(rValues),
      maximumWinStreak: streaks.$1,
      maximumLossStreak: streaks.$2,
      totalTimeInMarket: totalTimeInMarket,
      averageMfePercent: _meanOrNull(mfe),
      averageMaePercent: _meanOrNull(mae),
      averageGivebackPercent: _meanOrNull(givebacks),
      averageCapturePercent: _meanOrNull(captures),
      riskHours: riskHours,
      capitalHours: capitalHours,
      netPnlPerRiskHour: riskHours <= 0 ? 0 : netPnl / riskHours,
      netPnlPerCapitalHour: capitalHours <= 0 ? 0 : netPnl / capitalHours,
      uncertainty: uncertainty,
      bySymbol: _groups(selected, (item) => item.symbol),
      byTimeframe: _groups(selected, (item) => item.timeframe),
      byStrategy: _groups(selected, (item) => item.strategy),
      byStrategyVersion: _groups(
        selected,
        (item) => item.plan?.strategyRulesVersion ?? 'unknown',
      ),
      byRegime: _groups(selected, (item) => item.plan?.regime ?? 'unknown'),
      byDirection: _groups(selected, (item) => item.direction.name),
      byMode: _groups(selected, (item) => item.source.name),
      byLeverageBand: _groups(selected, _leverageBand),
      byConfidenceBand: _groups(selected, _confidenceBand),
      warnings: warnings,
    );
  }

  static bool _matches(
    TradingJournalProjection projection,
    TradingPerformanceFilter filter,
  ) {
    final at = projection.closedAt ?? projection.decidedAt;
    if (filter.startedAtUtc != null && at.isBefore(filter.startedAtUtc!)) {
      return false;
    }
    if (filter.endedAtUtc != null && !at.isBefore(filter.endedAtUtc!)) {
      return false;
    }
    if (filter.symbols.isNotEmpty &&
        !filter.symbols.contains(projection.symbol.toUpperCase())) {
      return false;
    }
    if (filter.timeframes.isNotEmpty &&
        !filter.timeframes.contains(projection.timeframe)) {
      return false;
    }
    if (filter.strategies.isNotEmpty &&
        !filter.strategies.contains(projection.strategy)) {
      return false;
    }
    final strategyVersion = projection.plan?.strategyRulesVersion ?? 'unknown';
    if (filter.strategyVersions.isNotEmpty &&
        !filter.strategyVersions.contains(strategyVersion)) {
      return false;
    }
    final regime = projection.plan?.regime ?? 'unknown';
    if (filter.regimes.isNotEmpty && !filter.regimes.contains(regime)) {
      return false;
    }
    if (filter.sources.isNotEmpty &&
        !filter.sources.contains(projection.source)) {
      return false;
    }
    if (filter.directions.isNotEmpty &&
        !filter.directions.contains(projection.direction)) {
      return false;
    }
    return true;
  }

  static List<double> _drawdowns(List<double> pnl) {
    var equity = 0.0;
    var peak = 0.0;
    final values = <double>[];
    for (final value in pnl) {
      equity += value;
      peak = math.max(peak, equity);
      final drawdown = peak - equity;
      if (drawdown > 0) values.add(drawdown);
    }
    return values;
  }

  static (int, int) _streaks(List<double> pnl) {
    var currentWins = 0;
    var currentLosses = 0;
    var maxWins = 0;
    var maxLosses = 0;
    for (final value in pnl) {
      if (value > 0) {
        currentWins += 1;
        currentLosses = 0;
        maxWins = math.max(maxWins, currentWins);
      } else if (value < 0) {
        currentLosses += 1;
        currentWins = 0;
        maxLosses = math.max(maxLosses, currentLosses);
      } else {
        currentWins = 0;
        currentLosses = 0;
      }
    }
    return (maxWins, maxLosses);
  }

  static Map<String, TradingPerformanceGroup> _groups(
    List<TradingJournalProjection> items,
    String Function(TradingJournalProjection item) keyOf,
  ) {
    final buckets = <String, _GroupAccumulator>{};
    for (final item in items) {
      final key = keyOf(item);
      final bucket = buckets.putIfAbsent(
        key,
        () => _GroupAccumulator(key),
      );
      bucket.add(item);
    }
    return {
      for (final entry in buckets.entries) entry.key: entry.value.freeze(),
    };
  }

  static String _leverageBand(TradingJournalProjection item) {
    final leverage = item.plan?.leverage;
    if (leverage == null || leverage <= 0) return 'unknown';
    if (leverage <= 3) return '1-3x';
    if (leverage <= 10) return '4-10x';
    if (leverage <= 25) return '11-25x';
    if (leverage <= 50) return '26-50x';
    return '51x+';
  }

  static String _confidenceBand(TradingJournalProjection item) {
    final confidence = item.plan?.confidencePercent;
    if (confidence == null || !confidence.isFinite) return 'unknown';
    if (confidence < 60) return '<60';
    if (confidence < 75) return '60-74';
    if (confidence < 90) return '75-89';
    return '90+';
  }

  static TradingPerformanceUncertainty _bootstrap(
    List<double> values, {
    required int seed,
    required int iterations,
  }) {
    if (values.isEmpty) {
      return TradingPerformanceUncertainty(
        sampleSize: 0,
        seed: seed,
        iterations: iterations,
        expectancyRP05: 0,
        expectancyRMedian: 0,
        expectancyRP95: 0,
        probabilityPositiveExpectancy: 0,
      );
    }
    final random = math.Random(seed);
    final means = <double>[];
    for (var iteration = 0; iteration < iterations; iteration++) {
      var total = 0.0;
      for (var index = 0; index < values.length; index++) {
        total += values[random.nextInt(values.length)];
      }
      means.add(total / values.length);
    }
    means.sort();

    double percentile(double probability) {
      final index = ((means.length - 1) * probability).round();
      return means[index.clamp(0, means.length - 1)];
    }

    return TradingPerformanceUncertainty(
      sampleSize: values.length,
      seed: seed,
      iterations: iterations,
      expectancyRP05: percentile(0.05),
      expectancyRMedian: percentile(0.5),
      expectancyRP95: percentile(0.95),
      probabilityPositiveExpectancy:
          means.where((value) => value > 0).length / means.length,
    );
  }

  static double? _meanOrNull(List<double> values) => values.isEmpty
      ? null
      : values.fold<double>(0, (sum, value) => sum + value) / values.length;

  static double? _sharpe(List<double> values) {
    if (values.length < 2) return null;
    final mean =
        values.fold<double>(0, (sum, value) => sum + value) / values.length;
    final variance =
        values.fold<double>(
          0,
          (sum, value) => sum + math.pow(value - mean, 2),
        ) /
        (values.length - 1);
    final deviation = math.sqrt(variance);
    return deviation <= 0 ? null : mean / deviation;
  }

  static double? _sortino(List<double> values) {
    if (values.length < 2) return null;
    final mean =
        values.fold<double>(0, (sum, value) => sum + value) / values.length;
    final downside = values.where((value) => value < 0).toList(growable: false);
    if (downside.length < 2) return null;
    final downsideVariance =
        downside.fold<double>(0, (sum, value) => sum + value * value) /
        downside.length;
    final deviation = math.sqrt(downsideVariance);
    return deviation <= 0 ? null : mean / deviation;
  }
}

final class _GroupAccumulator {
  _GroupAccumulator(this.key);

  final String key;
  int trades = 0;
  int wins = 0;
  double netPnl = 0;
  double grossProfit = 0;
  double grossLoss = 0;
  double realizedRSum = 0;
  int realizedRCount = 0;
  double riskHours = 0;
  double capitalHours = 0;

  void add(TradingJournalProjection item) {
    final net = item.netPnl;
    if (net == null || !net.isFinite) return;
    trades += 1;
    netPnl += net;
    if (net > 0) {
      wins += 1;
      grossProfit += net;
    } else if (net < 0) {
      grossLoss += net.abs();
    }
    final realizedR = item.realizedR;
    if (realizedR != null && realizedR.isFinite) {
      realizedRSum += realizedR;
      realizedRCount += 1;
    }
    final duration = item.holdingDuration;
    final plan = item.plan;
    if (duration == null || duration.isNegative || plan == null) return;
    final hours = duration.inMicroseconds / Duration.microsecondsPerHour;
    if (plan.riskBudget.isFinite && plan.riskBudget > 0) {
      riskHours += plan.riskBudget * hours;
    }
    if (plan.expectedMargin.isFinite && plan.expectedMargin > 0) {
      capitalHours += plan.expectedMargin * hours;
    }
  }

  TradingPerformanceGroup freeze() => TradingPerformanceGroup(
    key: key,
    trades: trades,
    netPnl: netPnl,
    expectancyR: realizedRCount == 0 ? 0 : realizedRSum / realizedRCount,
    winRatePercent: trades == 0 ? 0 : wins / trades * 100,
    profitFactor: grossLoss <= 0
        ? (grossProfit > 0 ? double.infinity : 0)
        : grossProfit / grossLoss,
    riskHours: riskHours,
    capitalHours: capitalHours,
    netPnlPerRiskHour: riskHours <= 0 ? 0 : netPnl / riskHours,
    netPnlPerCapitalHour: capitalHours <= 0 ? 0 : netPnl / capitalHours,
  );
}
