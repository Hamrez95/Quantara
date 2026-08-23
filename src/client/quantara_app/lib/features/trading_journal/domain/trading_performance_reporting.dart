import 'dart:convert';

import 'trading_performance_models.dart';

enum TradingPerformancePeriod { daily, weekly, monthly, custom }

enum TradingPerformanceInsightKind { worked, didNotWork, insufficientEvidence }

enum TradingPerformanceSummaryLanguage { english, persian }

final class TradingPerformanceInsight {
  const TradingPerformanceInsight({
    required this.kind,
    required this.dimension,
    required this.key,
    required this.sampleSize,
    required this.expectancyR,
    required this.netPnl,
    required this.message,
  });

  final TradingPerformanceInsightKind kind;
  final String dimension;
  final String key;
  final int sampleSize;
  final double expectancyR;
  final double netPnl;
  final String message;
}

abstract final class TradingPerformanceReporting {
  static TradingPerformanceFilter periodFilter({
    required TradingPerformancePeriod period,
    required DateTime anchorUtc,
    DateTime? customStartedAtUtc,
    DateTime? customEndedAtUtc,
  }) {
    if (!anchorUtc.isUtc) {
      throw ArgumentError('Performance report anchor must be UTC.');
    }
    return switch (period) {
      TradingPerformancePeriod.daily => TradingPerformanceFilter(
        startedAtUtc: DateTime.utc(
          anchorUtc.year,
          anchorUtc.month,
          anchorUtc.day,
        ),
        endedAtUtc: DateTime.utc(
          anchorUtc.year,
          anchorUtc.month,
          anchorUtc.day,
        ).add(const Duration(days: 1)),
      ),
      TradingPerformancePeriod.weekly => _weekly(anchorUtc),
      TradingPerformancePeriod.monthly => TradingPerformanceFilter(
        startedAtUtc: DateTime.utc(anchorUtc.year, anchorUtc.month),
        endedAtUtc: anchorUtc.month == 12
            ? DateTime.utc(anchorUtc.year + 1)
            : DateTime.utc(anchorUtc.year, anchorUtc.month + 1),
      ),
      TradingPerformancePeriod.custom => TradingPerformanceFilter(
        startedAtUtc: customStartedAtUtc,
        endedAtUtc: customEndedAtUtc,
      ),
    };
  }

  static Map<String, Object?> toJson(TradingPerformanceReport report) => {
    'schemaVersion': 2,
    'generatedAtUtc': report.generatedAtUtc.toIso8601String(),
    'window': {
      'startedAtUtc': report.filter.startedAtUtc?.toIso8601String(),
      'endedAtUtc': report.filter.endedAtUtc?.toIso8601String(),
    },
    'filters': {
      'symbols': report.filter.symbols.toList(growable: false)..sort(),
      'timeframes': report.filter.timeframes.toList(growable: false)..sort(),
      'strategies': report.filter.strategies.toList(growable: false)..sort(),
      'strategyVersions': report.filter.strategyVersions.toList(growable: false)
        ..sort(),
      'regimes': report.filter.regimes.toList(growable: false)..sort(),
      'sources':
          report.filter.sources.map((item) => item.name).toList(growable: false)
            ..sort(),
      'directions':
          report.filter.directions
              .map((item) => item.name)
              .toList(growable: false)
            ..sort(),
    },
    'summary': {
      'closedTrades': report.closedTrades,
      'pricedTrades': report.pricedTrades,
      'economicsPendingTrades': report.economicsPendingTrades,
      'wins': report.wins,
      'losses': report.losses,
      'breakEvens': report.breakEvens,
      'grossPnl': report.grossPnl,
      'fees': report.fees,
      'funding': report.funding,
      'netPnl': report.netPnl,
      'entrySlippageAttribution': report.entrySlippageAttribution,
      'winRatePercent': report.winRatePercent,
      'averageWin': report.averageWin,
      'averageLoss': report.averageLoss,
      'payoffRatio': report.payoffRatio,
      'expectancyR': report.expectancyR,
      'profitFactor': report.profitFactor.isFinite ? report.profitFactor : null,
      'maximumDrawdown': report.maximumDrawdown,
      'averageDrawdown': report.averageDrawdown,
      'recoveryFactor': report.recoveryFactor,
      'sharpeLike': report.sharpeLike,
      'sortinoLike': report.sortinoLike,
      'maximumWinStreak': report.maximumWinStreak,
      'maximumLossStreak': report.maximumLossStreak,
      'timeInMarketSeconds': report.totalTimeInMarket.inSeconds,
      'averageMfePercent': report.averageMfePercent,
      'averageMaePercent': report.averageMaePercent,
      'averageGivebackPercent': report.averageGivebackPercent,
      'averageCapturePercent': report.averageCapturePercent,
      'riskHours': report.riskHours,
      'capitalHours': report.capitalHours,
      'netPnlPerRiskHour': report.netPnlPerRiskHour,
      'netPnlPerCapitalHour': report.netPnlPerCapitalHour,
    },
    'uncertainty': {
      'sampleSize': report.uncertainty.sampleSize,
      'seed': report.uncertainty.seed,
      'iterations': report.uncertainty.iterations,
      'expectancyRP05': report.uncertainty.expectancyRP05,
      'expectancyRMedian': report.uncertainty.expectancyRMedian,
      'expectancyRP95': report.uncertainty.expectancyRP95,
      'probabilityPositiveExpectancy':
          report.uncertainty.probabilityPositiveExpectancy,
    },
    'attribution': {
      'symbol': _groupsJson(report.bySymbol),
      'timeframe': _groupsJson(report.byTimeframe),
      'strategy': _groupsJson(report.byStrategy),
      'strategyVersion': _groupsJson(report.byStrategyVersion),
      'regime': _groupsJson(report.byRegime),
      'direction': _groupsJson(report.byDirection),
      'mode': _groupsJson(report.byMode),
      'leverageBand': _groupsJson(report.byLeverageBand),
      'confidenceBand': _groupsJson(report.byConfidenceBand),
    },
    'warnings': report.warnings.toList(growable: false),
  };

  static String toPrettyJson(TradingPerformanceReport report) =>
      const JsonEncoder.withIndent('  ').convert(toJson(report));

  static String toCsv(TradingPerformanceReport report) {
    final rows = <List<Object?>>[
      [
        'dimension',
        'key',
        'trades',
        'netPnl',
        'expectancyR',
        'winRatePercent',
        'profitFactor',
        'riskHours',
        'capitalHours',
        'netPnlPerRiskHour',
        'netPnlPerCapitalHour',
      ],
      ..._csvRows('symbol', report.bySymbol),
      ..._csvRows('timeframe', report.byTimeframe),
      ..._csvRows('strategy', report.byStrategy),
      ..._csvRows('strategyVersion', report.byStrategyVersion),
      ..._csvRows('regime', report.byRegime),
      ..._csvRows('direction', report.byDirection),
      ..._csvRows('mode', report.byMode),
      ..._csvRows('leverageBand', report.byLeverageBand),
      ..._csvRows('confidenceBand', report.byConfidenceBand),
    ];
    return rows.map(_csvRow).join('\n');
  }

  static List<TradingPerformanceInsight> evidenceInsights(
    TradingPerformanceReport report, {
    int minimumSamples = 20,
  }) {
    if (minimumSamples < 10) {
      throw ArgumentError('Insight minimum sample is too small.');
    }
    final candidates =
        <({String dimension, TradingPerformanceGroup group})>[
              for (final item in report.byStrategy.values)
                (dimension: 'strategy', group: item),
              for (final item in report.byStrategyVersion.values)
                (dimension: 'strategyVersion', group: item),
              for (final item in report.bySymbol.values)
                (dimension: 'symbol', group: item),
              for (final item in report.byTimeframe.values)
                (dimension: 'timeframe', group: item),
              for (final item in report.byRegime.values)
                (dimension: 'regime', group: item),
              for (final item in report.byDirection.values)
                (dimension: 'direction', group: item),
              for (final item in report.byMode.values)
                (dimension: 'mode', group: item),
              for (final item in report.byLeverageBand.values)
                (dimension: 'leverageBand', group: item),
              for (final item in report.byConfidenceBand.values)
                (dimension: 'confidenceBand', group: item),
            ]
            .where((item) => item.group.trades >= minimumSamples)
            .toList(growable: false);

    if (candidates.isEmpty) {
      return [
        TradingPerformanceInsight(
          kind: TradingPerformanceInsightKind.insufficientEvidence,
          dimension: 'all',
          key: 'sample',
          sampleSize: report.pricedTrades,
          expectancyR: report.expectancyR,
          netPnl: report.netPnl,
          message:
              'Insufficient sample for evidence-backed segment conclusions; do not change live parameters from this report.',
        ),
      ];
    }

    candidates.sort((left, right) {
      final expectancy = right.group.expectancyR.compareTo(
        left.group.expectancyR,
      );
      if (expectancy != 0) return expectancy;
      final efficiency = right.group.netPnlPerRiskHour.compareTo(
        left.group.netPnlPerRiskHour,
      );
      if (efficiency != 0) return efficiency;
      return right.group.netPnl.compareTo(left.group.netPnl);
    });
    final best = candidates.first;
    final worst = candidates.last;
    return [
      TradingPerformanceInsight(
        kind: TradingPerformanceInsightKind.worked,
        dimension: best.dimension,
        key: best.group.key,
        sampleSize: best.group.trades,
        expectancyR: best.group.expectancyR,
        netPnl: best.group.netPnl,
        message:
            '${best.dimension}=${best.group.key} had the strongest observed expectancy/efficiency in the selected window; treat it as evidence, not an automatic parameter change.',
      ),
      TradingPerformanceInsight(
        kind: TradingPerformanceInsightKind.didNotWork,
        dimension: worst.dimension,
        key: worst.group.key,
        sampleSize: worst.group.trades,
        expectancyR: worst.group.expectancyR,
        netPnl: worst.group.netPnl,
        message:
            '${worst.dimension}=${worst.group.key} had the weakest observed expectancy/efficiency in the selected window; investigate evidence and costs before proposing an experiment.',
      ),
    ];
  }

  static String toShareableSummary(
    TradingPerformanceReport report, {
    TradingPerformanceSummaryLanguage language =
        TradingPerformanceSummaryLanguage.english,
  }) {
    final insights = evidenceInsights(report);
    final best = insights.where(
      (item) => item.kind == TradingPerformanceInsightKind.worked,
    );
    final worst = insights.where(
      (item) => item.kind == TradingPerformanceInsightKind.didNotWork,
    );
    if (language == TradingPerformanceSummaryLanguage.persian) {
      final evidenceLine = best.isEmpty
          ? 'نمونه برای نتیجه‌گیری بخشی کافی نیست.'
          : 'بهترین بخش مشاهده‌شده: ${best.first.dimension}=${best.first.key}؛ ضعیف‌ترین: ${worst.first.dimension}=${worst.first.key}.';
      return 'گزارش عملکرد Quantara — ${report.pricedTrades} معامله قیمت‌گذاری‌شده از ${report.closedTrades} معامله بسته، سود/زیان خالص ${report.netPnl.toStringAsFixed(2)}، امید ریاضی ${report.expectancyR.toStringAsFixed(3)}R، Profit Factor ${_finiteText(report.profitFactor)}, افت سرمایه بیشینه ${report.maximumDrawdown.toStringAsFixed(2)}، PnL به‌ازای risk-hour ${report.netPnlPerRiskHour.toStringAsFixed(3)}. $evidenceLine این گزارش تضمین سود یا مجوز تغییر خودکار پارامترها نیست.';
    }
    final evidenceLine = best.isEmpty
        ? 'There is not enough segment evidence for a mature conclusion.'
        : 'Strongest observed segment: ${best.first.dimension}=${best.first.key}; weakest: ${worst.first.dimension}=${worst.first.key}.';
    return 'Quantara performance — ${report.pricedTrades} priced of ${report.closedTrades} closed trades, net PnL ${report.netPnl.toStringAsFixed(2)}, expectancy ${report.expectancyR.toStringAsFixed(3)}R, profit factor ${_finiteText(report.profitFactor)}, max drawdown ${report.maximumDrawdown.toStringAsFixed(2)}, PnL/risk-hour ${report.netPnlPerRiskHour.toStringAsFixed(3)}. $evidenceLine This report is evidence, not a profit guarantee or an automatic parameter change.';
  }

  static TradingPerformanceFilter _weekly(DateTime anchorUtc) {
    final dayStart = DateTime.utc(
      anchorUtc.year,
      anchorUtc.month,
      anchorUtc.day,
    );
    final monday = dayStart.subtract(
      Duration(days: dayStart.weekday - DateTime.monday),
    );
    return TradingPerformanceFilter(
      startedAtUtc: monday,
      endedAtUtc: monday.add(const Duration(days: 7)),
    );
  }

  static List<Map<String, Object?>> _groupsJson(
    Map<String, TradingPerformanceGroup> groups,
  ) {
    final values = groups.values.toList(growable: false)
      ..sort((left, right) => left.key.compareTo(right.key));
    return values
        .map(
          (group) => {
            'key': group.key,
            'trades': group.trades,
            'netPnl': group.netPnl,
            'expectancyR': group.expectancyR,
            'winRatePercent': group.winRatePercent,
            'profitFactor': group.profitFactor.isFinite
                ? group.profitFactor
                : null,
            'riskHours': group.riskHours,
            'capitalHours': group.capitalHours,
            'netPnlPerRiskHour': group.netPnlPerRiskHour,
            'netPnlPerCapitalHour': group.netPnlPerCapitalHour,
          },
        )
        .toList(growable: false);
  }

  static Iterable<List<Object?>> _csvRows(
    String dimension,
    Map<String, TradingPerformanceGroup> groups,
  ) sync* {
    final values = groups.values.toList(growable: false)
      ..sort((left, right) => left.key.compareTo(right.key));
    for (final group in values) {
      yield [
        dimension,
        group.key,
        group.trades,
        group.netPnl,
        group.expectancyR,
        group.winRatePercent,
        group.profitFactor.isFinite ? group.profitFactor : '',
        group.riskHours,
        group.capitalHours,
        group.netPnlPerRiskHour,
        group.netPnlPerCapitalHour,
      ];
    }
  }

  static String _csvRow(List<Object?> values) => values
      .map((value) {
        final text = value?.toString() ?? '';
        if (text.contains(',') || text.contains('"') || text.contains('\n')) {
          return '"${text.replaceAll('"', '""')}"';
        }
        return text;
      })
      .join(',');

  static String _finiteText(double value) =>
      value.isFinite ? value.toStringAsFixed(2) : '∞';
}
