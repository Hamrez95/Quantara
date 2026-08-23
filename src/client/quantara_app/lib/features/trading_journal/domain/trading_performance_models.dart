import 'dart:collection';

import 'trading_journal_models.dart';

final class TradingPerformanceFilter {
  TradingPerformanceFilter({
    this.startedAtUtc,
    this.endedAtUtc,
    Iterable<String> symbols = const [],
    Iterable<String> timeframes = const [],
    Iterable<String> strategies = const [],
    Iterable<String> strategyVersions = const [],
    Iterable<String> regimes = const [],
    Iterable<TradingJournalSource> sources = const [],
    Iterable<TradingJournalDirection> directions = const [],
  }) : symbols = UnmodifiableSetView(
         symbols
             .map((value) => value.trim().toUpperCase())
             .where((value) => value.isNotEmpty)
             .toSet(),
       ),
       timeframes = UnmodifiableSetView(
         timeframes
             .map((value) => value.trim())
             .where((value) => value.isNotEmpty)
             .toSet(),
       ),
       strategies = UnmodifiableSetView(
         strategies
             .map((value) => value.trim())
             .where((value) => value.isNotEmpty)
             .toSet(),
       ),
       strategyVersions = UnmodifiableSetView(
         strategyVersions
             .map((value) => value.trim())
             .where((value) => value.isNotEmpty)
             .toSet(),
       ),
       regimes = UnmodifiableSetView(
         regimes
             .map((value) => value.trim())
             .where((value) => value.isNotEmpty)
             .toSet(),
       ),
       sources = UnmodifiableSetView(sources.toSet()),
       directions = UnmodifiableSetView(directions.toSet()) {
    if (startedAtUtc != null && !startedAtUtc!.isUtc) {
      throw ArgumentError('Performance filter start must be UTC.');
    }
    if (endedAtUtc != null && !endedAtUtc!.isUtc) {
      throw ArgumentError('Performance filter end must be UTC.');
    }
    if (startedAtUtc != null &&
        endedAtUtc != null &&
        !startedAtUtc!.isBefore(endedAtUtc!)) {
      throw ArgumentError('Performance filter window is invalid.');
    }
  }

  final DateTime? startedAtUtc;
  final DateTime? endedAtUtc;
  final UnmodifiableSetView<String> symbols;
  final UnmodifiableSetView<String> timeframes;
  final UnmodifiableSetView<String> strategies;
  final UnmodifiableSetView<String> strategyVersions;
  final UnmodifiableSetView<String> regimes;
  final UnmodifiableSetView<TradingJournalSource> sources;
  final UnmodifiableSetView<TradingJournalDirection> directions;
}

final class TradingPerformanceUncertainty {
  const TradingPerformanceUncertainty({
    required this.sampleSize,
    required this.seed,
    required this.iterations,
    required this.expectancyRP05,
    required this.expectancyRMedian,
    required this.expectancyRP95,
    required this.probabilityPositiveExpectancy,
  });

  final int sampleSize;
  final int seed;
  final int iterations;
  final double expectancyRP05;
  final double expectancyRMedian;
  final double expectancyRP95;
  final double probabilityPositiveExpectancy;
}

final class TradingPerformanceGroup {
  const TradingPerformanceGroup({
    required this.key,
    required this.trades,
    required this.netPnl,
    required this.expectancyR,
    required this.winRatePercent,
    required this.profitFactor,
    required this.riskHours,
    required this.capitalHours,
    required this.netPnlPerRiskHour,
    required this.netPnlPerCapitalHour,
  });

  final String key;
  final int trades;
  final double netPnl;
  final double expectancyR;
  final double winRatePercent;
  final double profitFactor;
  final double riskHours;
  final double capitalHours;
  final double netPnlPerRiskHour;
  final double netPnlPerCapitalHour;
}

final class TradingPerformanceReport {
  TradingPerformanceReport({
    required this.generatedAtUtc,
    required this.filter,
    required this.closedTrades,
    required this.pricedTrades,
    required this.economicsPendingTrades,
    required this.wins,
    required this.losses,
    required this.breakEvens,
    required this.grossPnl,
    required this.fees,
    required this.funding,
    required this.netPnl,
    required this.entrySlippageAttribution,
    required this.winRatePercent,
    required this.averageWin,
    required this.averageLoss,
    required this.payoffRatio,
    required this.expectancyR,
    required this.profitFactor,
    required this.maximumDrawdown,
    required this.averageDrawdown,
    required this.recoveryFactor,
    required this.sharpeLike,
    required this.sortinoLike,
    required this.maximumWinStreak,
    required this.maximumLossStreak,
    required this.totalTimeInMarket,
    required this.averageMfePercent,
    required this.averageMaePercent,
    required this.averageGivebackPercent,
    required this.averageCapturePercent,
    required this.riskHours,
    required this.capitalHours,
    required this.netPnlPerRiskHour,
    required this.netPnlPerCapitalHour,
    required this.uncertainty,
    required Map<String, TradingPerformanceGroup> bySymbol,
    required Map<String, TradingPerformanceGroup> byTimeframe,
    required Map<String, TradingPerformanceGroup> byStrategy,
    required Map<String, TradingPerformanceGroup> byStrategyVersion,
    required Map<String, TradingPerformanceGroup> byRegime,
    required Map<String, TradingPerformanceGroup> byDirection,
    required Map<String, TradingPerformanceGroup> byMode,
    required Map<String, TradingPerformanceGroup> byLeverageBand,
    required Map<String, TradingPerformanceGroup> byConfidenceBand,
    Iterable<String> warnings = const [],
  }) : bySymbol = UnmodifiableMapView(bySymbol),
       byTimeframe = UnmodifiableMapView(byTimeframe),
       byStrategy = UnmodifiableMapView(byStrategy),
       byStrategyVersion = UnmodifiableMapView(byStrategyVersion),
       byRegime = UnmodifiableMapView(byRegime),
       byDirection = UnmodifiableMapView(byDirection),
       byMode = UnmodifiableMapView(byMode),
       byLeverageBand = UnmodifiableMapView(byLeverageBand),
       byConfidenceBand = UnmodifiableMapView(byConfidenceBand),
       warnings = UnmodifiableListView(warnings.toList(growable: false));

  final DateTime generatedAtUtc;
  final TradingPerformanceFilter filter;
  final int closedTrades;
  final int pricedTrades;
  final int economicsPendingTrades;
  final int wins;
  final int losses;
  final int breakEvens;
  final double grossPnl;
  final double fees;
  final double funding;
  final double netPnl;
  final double entrySlippageAttribution;
  final double winRatePercent;
  final double averageWin;
  final double averageLoss;
  final double payoffRatio;
  final double expectancyR;
  final double profitFactor;
  final double maximumDrawdown;
  final double averageDrawdown;
  final double recoveryFactor;
  final double? sharpeLike;
  final double? sortinoLike;
  final int maximumWinStreak;
  final int maximumLossStreak;
  final Duration totalTimeInMarket;
  final double? averageMfePercent;
  final double? averageMaePercent;
  final double? averageGivebackPercent;
  final double? averageCapturePercent;
  final double riskHours;
  final double capitalHours;
  final double netPnlPerRiskHour;
  final double netPnlPerCapitalHour;
  final TradingPerformanceUncertainty uncertainty;
  final UnmodifiableMapView<String, TradingPerformanceGroup> bySymbol;
  final UnmodifiableMapView<String, TradingPerformanceGroup> byTimeframe;
  final UnmodifiableMapView<String, TradingPerformanceGroup> byStrategy;
  final UnmodifiableMapView<String, TradingPerformanceGroup> byStrategyVersion;
  final UnmodifiableMapView<String, TradingPerformanceGroup> byRegime;
  final UnmodifiableMapView<String, TradingPerformanceGroup> byDirection;
  final UnmodifiableMapView<String, TradingPerformanceGroup> byMode;
  final UnmodifiableMapView<String, TradingPerformanceGroup> byLeverageBand;
  final UnmodifiableMapView<String, TradingPerformanceGroup> byConfidenceBand;
  final UnmodifiableListView<String> warnings;

  bool get sampleSupportsRiskAdjustedRatios => pricedTrades >= 30;
}
