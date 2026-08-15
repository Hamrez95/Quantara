import 'dart:math' as math;

import 'trading_journal_models.dart';
import 'trading_journal_projection.dart';
import 'trading_performance_models.dart';

abstract final class TradingPerformanceAnalytics {
  static const minimumInsightSamples = 20;
  static const minimumRatioSamples = 30;

  static TradingPerformanceReport build({
    required Iterable<TradingJournalProjection> projections,
    TradingPerformanceFilter? filter,
    DateTime? generatedAtUtc,
    int bootstrapSeed = 109,
    int bootstrapIterations = 1000,
  }) {
    final effectiveFilter = filter ?? TradingPerformanceFilter();
    final generatedAt = (generatedAtUtc ?? DateTime.now().toUtc()).toUtc();
    if (!generatedAt.isUtc ||
        bootstrapIterations < 200 ||
        bootstrapIterations > 20000) {
      throw ArgumentError('Performance report configuration is invalid.');
    }

    final selected =
        projections
            .where((projection) => _matches(projection, effectiveFilter))
            .where(
              (projection) =>
                  projection.state == TradingJournalTradeState.closed,
            )
            .where((projection) => projection.netPnl != null)
            .toList(growable: false)
          ..sort((left, right) {
            final leftAt = left.closedAt ?? left.decidedAt;
            final rightAt = right.closedAt ?? right.decidedAt;
            return leftAt.compareTo(rightAt);
          });

    final pnl = selected.map((item) => item.netPnl!).toList(growable: false);
    final rValues = selected
        .map((item) => item.realizedR)
        .whereType<double>()
        .where((value) => value.isFinite)
        .toList(growable: false);
    final wins = pnl.where((value) => value > 0).toList(growable: false);
    final losses = pnl.where((value) => value < 0).toList(growable: false);
    final grossProfit = wins.fold<double>(0, (sum, value) => sum + value);
    final grossLossAbs = losses.fold<double>(
      0,
      (sum, value) => sum + value.abs(),
    );
    final grossPnl = selected
        .map((item) => item.grossPnl)
        .whereType<double>()
        .fold<double>(0, (sum, value) => sum + value);
    final fees = selected
        .map((item) => item.fees)
        .whereType<double>()
        .fold<double>(0, (sum, value) => sum + value.abs());
    final funding = selected
        .map((item) => item.funding)
        .whereType<double>()
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
        : rValues.fold<double>(0, (sum, value) => sum + value) / rValues.length;
    final profitFactor = grossLossAbs <= 0
        ? (grossProfit > 0 ? double.infinity : 0.0)
        : grossProfit / grossLossAbs;

    final streaks = _streaks(pnl);
    final timeInMarket = selected
        .map((item) => item.holdingDuration ?? Duration.zero)
        .fold<Duration>(Duration.zero, (sum, value) => sum + value);
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
          !maximum.isFinite) {
        continue;
      }
      if (maximum > 0) {
        givebacks.add(math.max(0, maximum - move));
        captures.add((move / maximum * 100).clamp(-500, 500).toDouble());
      }
    }

    final entrySlippage = selected.fold<double>(0, (sum, item) {
      final plan = item.plan;
      final actual = item.entryPrice;
      final quantity = item.initialQuantity;
      if (plan == null || actual == null || quantity == null || quantity <= 0) {
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
      if (selected.length < minimumRatioSamples)
        'Sharpe/Sortino-like ratios are hidden until at least $minimumRatioSamples closed trades exist.',
      if (selected.any(
        (item) => item.integrity == TradingJournalIntegrity.unverified,
      ))
        'One or more selected trades are unverified; treat aggregate conclusions as provisional.',
      'Entry slippage is attribution only and is not subtracted from net PnL again because confirmed fills already affect gross/net economics.',
    ];

    return TradingPerformanceReport(
      generatedAtUtc: generatedAt,
      filter: effectiveFilter,
      closedTrades: selected.length,
      wins: wins.length,
      losses: losses.length,
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
      sharpeLike: selected.length < minimumRatioSamples
          ? null
          : _sharpe(rValues),
      sortinoLike: selected.length < minimumRatioSamples
          ? null
          : _sortino(rValues),
      maximumWinStreak: streaks.$1,
      maximumLossStreak: streaks.$2,
      totalTimeInMarket: timeInMarket,
      averageMfePercent: _meanOrNull(mfe),
      averageMaePercent: _meanOrNull(mae),
      averageGivebackPercent: _meanOrNull(givebacks),
      averageCapturePercent: _meanOrNull(captures),
      uncertainty: uncertainty,
      bySymbol: _groups(selected, (item) => item.symbol),
      byTimeframe: _groups(selected, (item) => item.timeframe),
      byStrategy: _groups(selected, (item) => item.strategy),
      byRegime: _groups(selected, (item) => item.plan?.regime ?? 'unknown'),
      byDirection: _groups(selected, (item) => item.direction.name),
      byMode: _groups(selected, (item) => item.source.name),
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
    if (filter.regimes.isNotEmpty &&
        !filter.regimes.contains(projection.plan?.regime ?? 'unknown')) {
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
    final buckets = <String, List<TradingJournalProjection>>{};
    for (final item in items) {
      buckets.putIfAbsent(keyOf(item), () => []).add(item);
    }
    return {
      for (final entry in buckets.entries)
        entry.key: _group(entry.key, entry.value),
    };
  }

  static TradingPerformanceGroup _group(
    String key,
    List<TradingJournalProjection> items,
  ) {
    final pnl = items.map((item) => item.netPnl ?? 0).toList(growable: false);
    final r = items
        .map((item) => item.realizedR)
        .whereType<double>()
        .toList(growable: false);
    final wins = pnl.where((value) => value > 0).toList(growable: false);
    final losses = pnl.where((value) => value < 0).toList(growable: false);
    final grossProfit = wins.fold<double>(0, (sum, value) => sum + value);
    final grossLoss = losses.fold<double>(0, (sum, value) => sum + value.abs());
    return TradingPerformanceGroup(
      key: key,
      trades: items.length,
      netPnl: pnl.fold<double>(0, (sum, value) => sum + value),
      expectancyR: r.isEmpty
          ? 0
          : r.fold<double>(0, (sum, value) => sum + value) / r.length,
      winRatePercent: items.isEmpty ? 0 : wins.length / items.length * 100,
      profitFactor: grossLoss <= 0
          ? (grossProfit > 0 ? double.infinity : 0)
          : grossProfit / grossLoss,
    );
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
    double percentile(double p) {
      final index = ((means.length - 1) * p).round();
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
