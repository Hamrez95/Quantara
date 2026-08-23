import 'dart:collection';

import 'trading_journal_models.dart';
import 'trading_journal_projection.dart';
import 'trading_performance_models.dart';

final class TradingCounterfactualGroup {
  const TradingCounterfactualGroup({
    required this.missedSignals,
    required this.resolvedSignals,
    required this.wouldWin,
    required this.wouldLose,
    required this.breakEven,
    required this.unresolved,
    required this.averageResolvedR,
  });

  final int missedSignals;
  final int resolvedSignals;
  final int wouldWin;
  final int wouldLose;
  final int breakEven;
  final int unresolved;
  final double averageResolvedR;
}

final class TradingCounterfactualPerformanceSummary {
  TradingCounterfactualPerformanceSummary({
    required this.missedSignals,
    required this.resolvedSignals,
    required this.wouldWin,
    required this.wouldLose,
    required this.breakEven,
    required this.unresolved,
    required this.totalResolvedR,
    required this.averageResolvedR,
    required Map<String, TradingCounterfactualGroup> byStrategy,
    required Map<String, TradingCounterfactualGroup> bySymbol,
  }) : byStrategy = UnmodifiableMapView(byStrategy),
       bySymbol = UnmodifiableMapView(bySymbol);

  final int missedSignals;
  final int resolvedSignals;
  final int wouldWin;
  final int wouldLose;
  final int breakEven;
  final int unresolved;
  final double totalResolvedR;
  final double averageResolvedR;
  final UnmodifiableMapView<String, TradingCounterfactualGroup> byStrategy;
  final UnmodifiableMapView<String, TradingCounterfactualGroup> bySymbol;

  double get resolutionRatePercent =>
      missedSignals == 0 ? 0 : resolvedSignals / missedSignals * 100;

  Map<String, Object?> toJson() => {
    'missedSignals': missedSignals,
    'resolvedSignals': resolvedSignals,
    'wouldWin': wouldWin,
    'wouldLose': wouldLose,
    'breakEven': breakEven,
    'unresolved': unresolved,
    'totalResolvedR': totalResolvedR,
    'averageResolvedR': averageResolvedR,
    'resolutionRatePercent': resolutionRatePercent,
    'byStrategy': {
      for (final entry in byStrategy.entries)
        entry.key: _groupJson(entry.value),
    },
    'bySymbol': {
      for (final entry in bySymbol.entries) entry.key: _groupJson(entry.value),
    },
  };

  static Map<String, Object?> _groupJson(TradingCounterfactualGroup group) => {
    'missedSignals': group.missedSignals,
    'resolvedSignals': group.resolvedSignals,
    'wouldWin': group.wouldWin,
    'wouldLose': group.wouldLose,
    'breakEven': group.breakEven,
    'unresolved': group.unresolved,
    'averageResolvedR': group.averageResolvedR,
  };
}

/// Summarizes only explicit, already-resolved counterfactual Journal evidence.
///
/// It never infers an untaken signal outcome from later candles, target prices,
/// or current market state. Missing or internally inconsistent evidence remains
/// unresolved. This keeps hindsight analysis descriptive and prevents it from
/// becoming synthetic trade truth.
abstract final class TradingCounterfactualPerformance {
  static const defaultMaximumMissedSignals = 2000;

  static TradingCounterfactualPerformanceSummary calculate({
    required Iterable<TradingJournalProjection> projections,
    TradingPerformanceFilter? filter,
    int maximumMissedSignals = defaultMaximumMissedSignals,
  }) {
    if (maximumMissedSignals <= 0) {
      throw ArgumentError.value(
        maximumMissedSignals,
        'maximumMissedSignals',
        'must be positive',
      );
    }
    final effectiveFilter = filter ?? TradingPerformanceFilter();
    final strategyGroups = <String, _CounterfactualAccumulator>{};
    final symbolGroups = <String, _CounterfactualAccumulator>{};
    final total = _CounterfactualAccumulator();

    for (final projection in projections) {
      if (projection.state != TradingJournalTradeState.missed ||
          !_matches(projection, effectiveFilter)) {
        continue;
      }
      total.missedSignals += 1;
      if (total.missedSignals > maximumMissedSignals) {
        throw StateError(
          'Counterfactual window exceeded $maximumMissedSignals missed signals.',
        );
      }

      final strategy = strategyGroups.putIfAbsent(
        projection.strategy,
        _CounterfactualAccumulator.new,
      );
      final symbol = symbolGroups.putIfAbsent(
        projection.symbol.toUpperCase(),
        _CounterfactualAccumulator.new,
      );
      strategy.missedSignals += 1;
      symbol.missedSignals += 1;

      final classified = _validatedOutcome(projection.counterfactualOutcome);
      total.add(classified);
      strategy.add(classified);
      symbol.add(classified);
    }

    return TradingCounterfactualPerformanceSummary(
      missedSignals: total.missedSignals,
      resolvedSignals: total.resolvedSignals,
      wouldWin: total.wouldWin,
      wouldLose: total.wouldLose,
      breakEven: total.breakEven,
      unresolved: total.unresolved,
      totalResolvedR: total.resolvedRSum,
      averageResolvedR: total.averageResolvedR,
      byStrategy: {
        for (final entry in strategyGroups.entries)
          entry.key: entry.value.freeze(),
      },
      bySymbol: {
        for (final entry in symbolGroups.entries)
          entry.key: entry.value.freeze(),
      },
    );
  }

  static _ValidatedCounterfactual _validatedOutcome(
    TradingJournalCounterfactualOutcome? outcome,
  ) {
    if (outcome == null ||
        outcome.classification ==
            TradingJournalCounterfactualClassification.unresolved ||
        !outcome.realizedR.isFinite) {
      return const _ValidatedCounterfactual.unresolved();
    }
    final consistent = switch (outcome.classification) {
      TradingJournalCounterfactualClassification.wouldWin =>
        outcome.realizedR > 0,
      TradingJournalCounterfactualClassification.wouldLose =>
        outcome.realizedR < 0,
      TradingJournalCounterfactualClassification.breakEven =>
        outcome.realizedR.abs() <= 1e-9,
      TradingJournalCounterfactualClassification.unresolved => false,
    };
    if (!consistent) return const _ValidatedCounterfactual.unresolved();
    return _ValidatedCounterfactual.resolved(
      outcome.classification,
      outcome.realizedR,
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
}

final class _ValidatedCounterfactual {
  const _ValidatedCounterfactual.resolved(this.classification, this.realizedR)
    : resolved = true;

  const _ValidatedCounterfactual.unresolved()
    : resolved = false,
      classification = TradingJournalCounterfactualClassification.unresolved,
      realizedR = 0;

  final bool resolved;
  final TradingJournalCounterfactualClassification classification;
  final double realizedR;
}

final class _CounterfactualAccumulator {
  int missedSignals = 0;
  int resolvedSignals = 0;
  int wouldWin = 0;
  int wouldLose = 0;
  int breakEven = 0;
  int unresolved = 0;
  double resolvedRSum = 0;

  void add(_ValidatedCounterfactual outcome) {
    if (!outcome.resolved) {
      unresolved += 1;
      return;
    }
    resolvedSignals += 1;
    resolvedRSum += outcome.realizedR;
    switch (outcome.classification) {
      case TradingJournalCounterfactualClassification.wouldWin:
        wouldWin += 1;
      case TradingJournalCounterfactualClassification.wouldLose:
        wouldLose += 1;
      case TradingJournalCounterfactualClassification.breakEven:
        breakEven += 1;
      case TradingJournalCounterfactualClassification.unresolved:
        unresolved += 1;
    }
  }

  double get averageResolvedR =>
      resolvedSignals == 0 ? 0 : resolvedRSum / resolvedSignals;

  TradingCounterfactualGroup freeze() => TradingCounterfactualGroup(
    missedSignals: missedSignals,
    resolvedSignals: resolvedSignals,
    wouldWin: wouldWin,
    wouldLose: wouldLose,
    breakEven: breakEven,
    unresolved: unresolved,
    averageResolvedR: averageResolvedR,
  );
}
