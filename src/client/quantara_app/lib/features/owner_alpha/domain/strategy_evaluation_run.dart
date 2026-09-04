import 'dart:collection';

/// Immutable provenance tying an evaluation to one exact strategy snapshot.
final class StrategyEvaluationIdentity {
  StrategyEvaluationIdentity({
    required this.strategyId,
    required this.strategyVersion,
    required this.implementationVersion,
    required this.managementPolicyVersion,
    required this.parameterSchemaVersion,
    required Map<String, Object?> normalizedParameters,
    required this.snapshotHash,
  }) : normalizedParameters = UnmodifiableMapView<String, Object?>(
         Map<String, Object?>.from(normalizedParameters),
       ) {
    _requireText(strategyId, 'strategyId');
    _requireText(strategyVersion, 'strategyVersion');
    _requireText(implementationVersion, 'implementationVersion');
    _requireText(managementPolicyVersion, 'managementPolicyVersion');
    _requireText(snapshotHash, 'snapshotHash');
    if (parameterSchemaVersion <= 0) {
      throw ArgumentError.value(
        parameterSchemaVersion,
        'parameterSchemaVersion',
      );
    }
  }

  final String strategyId;
  final String strategyVersion;
  final String implementationVersion;
  final String managementPolicyVersion;
  final int parameterSchemaVersion;
  final Map<String, Object?> normalizedParameters;
  final String snapshotHash;

  Map<String, Object?> toJson() => <String, Object?>{
    'strategyId': strategyId,
    'strategyVersion': strategyVersion,
    'implementationVersion': implementationVersion,
    'managementPolicyVersion': managementPolicyVersion,
    'parameterSchemaVersion': parameterSchemaVersion,
    'normalizedParameters': normalizedParameters,
    'snapshotHash': snapshotHash,
  };
}

/// Reproducible assumptions applied to every observation in an evaluation run.
final class StrategyEvaluationCostModel {
  const StrategyEvaluationCostModel({
    required this.version,
    required this.takerFeeBps,
    required this.slippageBps,
  });

  final String version;
  final double takerFeeBps;
  final double slippageBps;

  void validate() {
    _requireText(version, 'costModel.version');
    _requireFiniteNonNegative(takerFeeBps, 'takerFeeBps');
    _requireFiniteNonNegative(slippageBps, 'slippageBps');
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'version': version,
    'takerFeeBps': takerFeeBps,
    'slippageBps': slippageBps,
  };
}

/// One observed trade outcome. Values must come from replay/paper evidence;
/// this model never synthesizes fills or exchange evidence.
final class StrategyEvaluationTrade {
  const StrategyEvaluationTrade({
    required this.tradeId,
    required this.openedAtUtc,
    required this.closedAtUtc,
    required this.grossPnl,
    required this.cost,
    required this.maximumFavorableExcursion,
    required this.maximumAdverseExcursion,
    this.regime,
  });

  final String tradeId;
  final DateTime openedAtUtc;
  final DateTime closedAtUtc;
  final double grossPnl;
  final double cost;
  final double maximumFavorableExcursion;
  final double maximumAdverseExcursion;
  final String? regime;

  double get netPnl => grossPnl - cost;
  Duration get duration => closedAtUtc.difference(openedAtUtc);

  void validate() {
    _requireText(tradeId, 'tradeId');
    if (!closedAtUtc.isAfter(openedAtUtc)) {
      throw ArgumentError('closedAtUtc must be after openedAtUtc');
    }
    _requireFinite(grossPnl, 'grossPnl');
    _requireFiniteNonNegative(cost, 'cost');
    _requireFiniteNonNegative(
      maximumFavorableExcursion,
      'maximumFavorableExcursion',
    );
    _requireFiniteNonNegative(
      maximumAdverseExcursion,
      'maximumAdverseExcursion',
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'tradeId': tradeId,
    'openedAtUtc': openedAtUtc.toUtc().toIso8601String(),
    'closedAtUtc': closedAtUtc.toUtc().toIso8601String(),
    'grossPnl': grossPnl,
    'cost': cost,
    'maximumFavorableExcursion': maximumFavorableExcursion,
    'maximumAdverseExcursion': maximumAdverseExcursion,
    if (regime != null) 'regime': regime,
  };
}

/// Deterministic scorecard derived only from supplied observed trades.
final class StrategyEvaluationScorecard {
  const StrategyEvaluationScorecard({
    required this.tradeCount,
    required this.winRate,
    required this.averageWinner,
    required this.averageLoser,
    required this.expectancy,
    required this.profitFactor,
    required this.averageMfe,
    required this.averageMae,
    required this.maximumDrawdown,
    required this.totalGrossPnl,
    required this.totalCosts,
    required this.totalNetPnl,
    required this.totalExposure,
    required this.insufficientSamples,
  });

  static const minimumDecisionSampleSize = 30;

  final int tradeCount;
  final double winRate;
  final double averageWinner;
  final double averageLoser;
  final double expectancy;
  final double? profitFactor;
  final double averageMfe;
  final double averageMae;
  final double maximumDrawdown;
  final double totalGrossPnl;
  final double totalCosts;
  final double totalNetPnl;
  final Duration totalExposure;
  final bool insufficientSamples;

  factory StrategyEvaluationScorecard.fromTrades(
    Iterable<StrategyEvaluationTrade> source,
  ) {
    final trades = source.toList(growable: false);
    for (final trade in trades) {
      trade.validate();
    }
    if (trades.isEmpty) {
      return const StrategyEvaluationScorecard(
        tradeCount: 0,
        winRate: 0,
        averageWinner: 0,
        averageLoser: 0,
        expectancy: 0,
        profitFactor: null,
        averageMfe: 0,
        averageMae: 0,
        maximumDrawdown: 0,
        totalGrossPnl: 0,
        totalCosts: 0,
        totalNetPnl: 0,
        totalExposure: Duration.zero,
        insufficientSamples: true,
      );
    }

    var wins = 0;
    var winnerSum = 0.0;
    var losses = 0;
    var loserSum = 0.0;
    var grossProfit = 0.0;
    var grossLoss = 0.0;
    var totalGross = 0.0;
    var totalCosts = 0.0;
    var totalNet = 0.0;
    var totalMfe = 0.0;
    var totalMae = 0.0;
    var exposureMicros = 0;
    var equity = 0.0;
    var peak = 0.0;
    var maximumDrawdown = 0.0;

    for (final trade in trades) {
      final net = trade.netPnl;
      totalGross += trade.grossPnl;
      totalCosts += trade.cost;
      totalNet += net;
      totalMfe += trade.maximumFavorableExcursion;
      totalMae += trade.maximumAdverseExcursion;
      exposureMicros += trade.duration.inMicroseconds;
      if (net > 0) {
        wins += 1;
        winnerSum += net;
        grossProfit += net;
      } else if (net < 0) {
        losses += 1;
        loserSum += net;
        grossLoss += net.abs();
      }
      equity += net;
      if (equity > peak) peak = equity;
      final drawdown = peak - equity;
      if (drawdown > maximumDrawdown) maximumDrawdown = drawdown;
    }

    final count = trades.length;
    return StrategyEvaluationScorecard(
      tradeCount: count,
      winRate: wins / count,
      averageWinner: wins == 0 ? 0 : winnerSum / wins,
      averageLoser: losses == 0 ? 0 : loserSum / losses,
      expectancy: totalNet / count,
      profitFactor: grossLoss == 0 ? null : grossProfit / grossLoss,
      averageMfe: totalMfe / count,
      averageMae: totalMae / count,
      maximumDrawdown: maximumDrawdown,
      totalGrossPnl: totalGross,
      totalCosts: totalCosts,
      totalNetPnl: totalNet,
      totalExposure: Duration(microseconds: exposureMicros),
      insufficientSamples: count < minimumDecisionSampleSize,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'tradeCount': tradeCount,
    'winRate': winRate,
    'averageWinner': averageWinner,
    'averageLoser': averageLoser,
    'expectancy': expectancy,
    'profitFactor': profitFactor,
    'averageMfe': averageMfe,
    'averageMae': averageMae,
    'maximumDrawdown': maximumDrawdown,
    'totalGrossPnl': totalGrossPnl,
    'totalCosts': totalCosts,
    'totalNetPnl': totalNetPnl,
    'totalExposureMicros': totalExposure.inMicroseconds,
    'insufficientSamples': insufficientSamples,
  };
}

/// First-class reproducible evidence run for one evaluated setup.
final class StrategyEvaluationRun {
  StrategyEvaluationRun({
    required this.runId,
    required this.setupId,
    required this.identity,
    required this.symbol,
    required this.market,
    required this.timeframe,
    required this.rangeStartUtc,
    required this.rangeEndUtc,
    required this.createdAtUtc,
    required this.costModel,
    required Iterable<StrategyEvaluationTrade> trades,
    this.deterministicSeed,
  }) : trades = List<StrategyEvaluationTrade>.unmodifiable(trades),
       scorecard = StrategyEvaluationScorecard.fromTrades(trades) {
    _requireText(runId, 'runId');
    _requireText(setupId, 'setupId');
    _requireText(symbol, 'symbol');
    _requireText(market, 'market');
    _requireText(timeframe, 'timeframe');
    if (!rangeEndUtc.isAfter(rangeStartUtc)) {
      throw ArgumentError('rangeEndUtc must be after rangeStartUtc');
    }
    costModel.validate();
  }

  final String runId;
  final String setupId;
  final StrategyEvaluationIdentity identity;
  final String symbol;
  final String market;
  final String timeframe;
  final DateTime rangeStartUtc;
  final DateTime rangeEndUtc;
  final DateTime createdAtUtc;
  final StrategyEvaluationCostModel costModel;
  final int? deterministicSeed;
  final List<StrategyEvaluationTrade> trades;
  final StrategyEvaluationScorecard scorecard;

  /// Evaluation evidence is informational. It can never directly arm Local Live.
  bool get grantsLocalLiveAuthority => false;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'runId': runId,
    'setupId': setupId,
    'identity': identity.toJson(),
    'symbol': symbol,
    'market': market,
    'timeframe': timeframe,
    'rangeStartUtc': rangeStartUtc.toUtc().toIso8601String(),
    'rangeEndUtc': rangeEndUtc.toUtc().toIso8601String(),
    'createdAtUtc': createdAtUtc.toUtc().toIso8601String(),
    'costModel': costModel.toJson(),
    if (deterministicSeed != null) 'deterministicSeed': deterministicSeed,
    'trades': trades.map((trade) => trade.toJson()).toList(growable: false),
    'scorecard': scorecard.toJson(),
  };
}

void _requireText(String value, String name) {
  if (value.trim().isEmpty) throw ArgumentError.value(value, name);
}

void _requireFinite(double value, String name) {
  if (!value.isFinite) throw ArgumentError.value(value, name);
}

void _requireFiniteNonNegative(double value, String name) {
  _requireFinite(value, name);
  if (value < 0) throw ArgumentError.value(value, name);
}
