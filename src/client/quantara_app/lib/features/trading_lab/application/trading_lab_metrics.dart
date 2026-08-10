import 'dart:math' as math;

import '../../owner_alpha/domain/owner_alpha_models.dart';
import '../domain/trading_lab_models.dart';

final class TradingLabMetrics {
  const TradingLabMetrics({
    required this.evidenceAtUtc,
    required this.startingEquity,
    required this.currentEquity,
    required this.netPnl,
    required this.grossRealizedPnl,
    required this.realizedPnl,
    required this.unrealizedPnl,
    required this.totalFees,
    required this.totalFunding,
    required this.totalSlippage,
    required this.returnPercent,
    required this.maximumDrawdownPercent,
    required this.maximumDrawdownDurationSeconds,
    required this.tradeCount,
    required this.wins,
    required this.losses,
    required this.breakevens,
    required this.winRatePercent,
    required this.profitFactor,
    required this.expectancyUsdt,
    required this.expectancyR,
    required this.averageR,
    required this.medianR,
    required this.averageWinner,
    required this.averageLoser,
    required this.payoffRatio,
    required this.bestTrade,
    required this.worstTrade,
    required this.averageHoldingSeconds,
    required this.maximumConsecutiveWins,
    required this.maximumConsecutiveLosses,
    required this.exposurePercent,
    required this.positionSlotUtilizationPercent,
    required this.candidatesObserved,
    required this.candidatesRejected,
    required this.entriesOpened,
    required this.signalToEntryConversionPercent,
    required this.rejectionsByReason,
    required this.averageMfeR,
    required this.medianMfeR,
    required this.averageMaeR,
    required this.medianMaeR,
    required this.stopOutCount,
    required this.tp1OrBetterCount,
    required this.tp2OrBetterCount,
    required this.tp3Count,
    required this.partialExitTrades,
    required this.sampleWarning,
  });

  final DateTime evidenceAtUtc;
  final double startingEquity;
  final double currentEquity;
  final double netPnl;
  final double grossRealizedPnl;
  final double realizedPnl;
  final double unrealizedPnl;
  final double totalFees;
  final double totalFunding;
  final double totalSlippage;
  final double returnPercent;
  final double maximumDrawdownPercent;
  final int maximumDrawdownDurationSeconds;
  final int tradeCount;
  final int wins;
  final int losses;
  final int breakevens;
  final double winRatePercent;
  final double? profitFactor;
  final double expectancyUsdt;
  final double expectancyR;
  final double averageR;
  final double medianR;
  final double averageWinner;
  final double averageLoser;
  final double? payoffRatio;
  final double bestTrade;
  final double worstTrade;
  final double averageHoldingSeconds;
  final int maximumConsecutiveWins;
  final int maximumConsecutiveLosses;
  final double exposurePercent;
  final double positionSlotUtilizationPercent;
  final int candidatesObserved;
  final int candidatesRejected;
  final int entriesOpened;
  final double signalToEntryConversionPercent;
  final Map<String, int> rejectionsByReason;
  final double averageMfeR;
  final double medianMfeR;
  final double averageMaeR;
  final double medianMaeR;
  final int stopOutCount;
  final int tp1OrBetterCount;
  final int tp2OrBetterCount;
  final int tp3Count;
  final int partialExitTrades;
  final String? sampleWarning;

  Map<String, Object?> toJson() => {
    'evidenceAtUtc': evidenceAtUtc.toIso8601String(),
    'startingEquity': startingEquity,
    'currentEquity': currentEquity,
    'netPnl': netPnl,
    'grossRealizedPnl': grossRealizedPnl,
    'realizedPnl': realizedPnl,
    'unrealizedPnl': unrealizedPnl,
    'totalFees': totalFees,
    'totalFunding': totalFunding,
    'totalSlippage': totalSlippage,
    'returnPercent': returnPercent,
    'maximumDrawdownPercent': maximumDrawdownPercent,
    'maximumDrawdownDurationSeconds': maximumDrawdownDurationSeconds,
    'tradeCount': tradeCount,
    'wins': wins,
    'losses': losses,
    'breakevens': breakevens,
    'winRatePercent': winRatePercent,
    'profitFactor': profitFactor?.isFinite == true ? profitFactor : null,
    'expectancyUsdt': expectancyUsdt,
    'expectancyR': expectancyR,
    'averageR': averageR,
    'medianR': medianR,
    'averageWinner': averageWinner,
    'averageLoser': averageLoser,
    'payoffRatio': payoffRatio,
    'bestTrade': bestTrade,
    'worstTrade': worstTrade,
    'averageHoldingSeconds': averageHoldingSeconds,
    'maximumConsecutiveWins': maximumConsecutiveWins,
    'maximumConsecutiveLosses': maximumConsecutiveLosses,
    'exposurePercent': exposurePercent,
    'positionSlotUtilizationPercent': positionSlotUtilizationPercent,
    'candidatesObserved': candidatesObserved,
    'candidatesRejected': candidatesRejected,
    'entriesOpened': entriesOpened,
    'signalToEntryConversionPercent': signalToEntryConversionPercent,
    'rejectionsByReason': rejectionsByReason,
    'averageMfeR': averageMfeR,
    'medianMfeR': medianMfeR,
    'averageMaeR': averageMaeR,
    'medianMaeR': medianMaeR,
    'stopOutCount': stopOutCount,
    'tp1OrBetterCount': tp1OrBetterCount,
    'tp2OrBetterCount': tp2OrBetterCount,
    'tp3Count': tp3Count,
    'partialExitTrades': partialExitTrades,
    'sampleWarning': sampleWarning,
  };
}

TradingLabMetrics calculateTradingLabMetrics(
  TradingLabRun run, {
  DateTime? evidenceAtUtc,
}) {
  final evidenceAt = (evidenceAtUtc ?? run.lastSnapshotAtUtc ?? DateTime.now())
      .toUtc();
  final closed = run.closedPositions;
  final allPositions = <TradingLabPosition>[
    ...closed,
    ...run.openPositions,
  ];
  final realizedPnl = closed.fold<double>(
    0,
    (sum, position) => sum + position.netRealizedPnl,
  );
  final grossRealizedPnl = closed.fold<double>(
    0,
    (sum, position) => sum + position.realizedGrossPnl,
  );
  final totalFees = allPositions.fold<double>(
    0,
    (sum, position) => sum + position.entryFee + position.exitFees,
  );
  final totalFunding = allPositions.fold<double>(
    0,
    (sum, position) => sum + position.funding,
  );
  final totalSlippage = allPositions.fold<double>(
    0,
    (sum, position) => sum + position.slippageCost,
  );
  final netPnl = run.currentEquity - run.manifest.startingEquity;
  final unrealizedPnl = netPnl - realizedPnl;

  final wins = closed.where((position) => position.netRealizedPnl > 1e-9).length;
  final losses = closed
      .where((position) => position.netRealizedPnl < -1e-9)
      .length;
  final breakevens = closed.length - wins - losses;
  final winningPnls = closed
      .map((position) => position.netRealizedPnl)
      .where((value) => value > 1e-9)
      .toList(growable: false);
  final losingPnls = closed
      .map((position) => position.netRealizedPnl)
      .where((value) => value < -1e-9)
      .map((value) => value.abs())
      .toList(growable: false);
  final grossProfit = winningPnls.fold<double>(0, (sum, value) => sum + value);
  final grossLoss = losingPnls.fold<double>(0, (sum, value) => sum + value);
  final profitFactor = grossLoss <= 1e-9
      ? (grossProfit > 1e-9 ? double.infinity : null)
      : grossProfit / grossLoss;

  final rValues = closed.map((position) => position.realizedR).toList();
  final mfeRValues = closed.map(_mfeR).toList();
  final maeRValues = closed.map(_maeR).toList();
  final holdingSeconds = closed
      .map(
        (position) => math.max(
          0,
          (position.closedAtUtc ?? evidenceAt)
              .difference(position.openedAtUtc)
              .inSeconds,
        ),
      )
      .toList(growable: false);

  var maxConsecutiveWins = 0;
  var maxConsecutiveLosses = 0;
  var currentWins = 0;
  var currentLosses = 0;
  final chronological = [...closed]
    ..sort((a, b) => (a.closedAtUtc ?? evidenceAt).compareTo(b.closedAtUtc ?? evidenceAt));
  for (final position in chronological) {
    if (position.netRealizedPnl > 1e-9) {
      currentWins += 1;
      currentLosses = 0;
      maxConsecutiveWins = math.max(maxConsecutiveWins, currentWins);
    } else if (position.netRealizedPnl < -1e-9) {
      currentLosses += 1;
      currentWins = 0;
      maxConsecutiveLosses = math.max(maxConsecutiveLosses, currentLosses);
    } else {
      currentWins = 0;
      currentLosses = 0;
    }
  }

  final observed = run.events
      .where((event) => event.kind == TradingLabEventKind.candidateObserved)
      .length;
  final rejectedEvents = run.events
      .where((event) => event.kind == TradingLabEventKind.candidateRejected)
      .toList(growable: false);
  final opened = run.events
      .where((event) => event.kind == TradingLabEventKind.positionOpened)
      .length;
  final rejections = <String, int>{};
  for (final event in rejectedEvents) {
    final reason = event.attributes['rejectionReason'] ?? 'unknown';
    rejections[reason] = (rejections[reason] ?? 0) + 1;
  }

  var stopOuts = 0;
  var tp1OrBetter = 0;
  var tp2OrBetter = 0;
  var tp3 = 0;
  var partialExitTrades = 0;
  for (final position in closed) {
    if ((position.closeReason ?? '').toLowerCase().contains('stop')) stopOuts += 1;
    final filled = position.filledTargetIndexes.length;
    if (filled >= 1) tp1OrBetter += 1;
    if (filled >= 2) tp2OrBetter += 1;
    if (filled >= 3) tp3 += 1;
    if (filled > 0 && filled < position.targets.length) partialExitTrades += 1;
  }

  final runDurationSeconds = math.max(
    1,
    evidenceAt.difference(run.manifest.startedAtUtc).inSeconds,
  );
  final occupiedSeconds = allPositions.fold<int>(0, (sum, position) {
    final end = position.closedAtUtc ?? evidenceAt;
    return sum + math.max(0, end.difference(position.openedAtUtc).inSeconds);
  });
  final exposurePercent = math.min(
    100.0,
    occupiedSeconds / runDurationSeconds * 100,
  );
  final slotCapacitySeconds =
      runDurationSeconds * run.manifest.maximumConcurrentPositions;
  final slotUtilization = slotCapacitySeconds <= 0
      ? 0.0
      : math.min(100.0, occupiedSeconds / slotCapacitySeconds * 100);

  return TradingLabMetrics(
    evidenceAtUtc: evidenceAt,
    startingEquity: run.manifest.startingEquity,
    currentEquity: run.currentEquity,
    netPnl: netPnl,
    grossRealizedPnl: grossRealizedPnl,
    realizedPnl: realizedPnl,
    unrealizedPnl: unrealizedPnl,
    totalFees: totalFees,
    totalFunding: totalFunding,
    totalSlippage: totalSlippage,
    returnPercent: run.returnPercent,
    maximumDrawdownPercent: run.maximumDrawdownPercent,
    maximumDrawdownDurationSeconds: _maximumDrawdownDuration(run, evidenceAt),
    tradeCount: closed.length,
    wins: wins,
    losses: losses,
    breakevens: breakevens,
    winRatePercent: closed.isEmpty ? 0 : wins / closed.length * 100,
    profitFactor: profitFactor,
    expectancyUsdt: closed.isEmpty ? 0 : realizedPnl / closed.length,
    expectancyR: rValues.isEmpty ? 0 : _average(rValues),
    averageR: rValues.isEmpty ? 0 : _average(rValues),
    medianR: _median(rValues),
    averageWinner: winningPnls.isEmpty ? 0 : _average(winningPnls),
    averageLoser: losingPnls.isEmpty ? 0 : _average(losingPnls),
    payoffRatio: losingPnls.isEmpty || _average(losingPnls) <= 1e-9
        ? null
        : (winningPnls.isEmpty ? 0 : _average(winningPnls)) /
              _average(losingPnls),
    bestTrade: closed.isEmpty
        ? 0
        : closed.map((item) => item.netRealizedPnl).reduce(math.max),
    worstTrade: closed.isEmpty
        ? 0
        : closed.map((item) => item.netRealizedPnl).reduce(math.min),
    averageHoldingSeconds: holdingSeconds.isEmpty
        ? 0
        : _average(holdingSeconds.map((item) => item.toDouble()).toList()),
    maximumConsecutiveWins: maxConsecutiveWins,
    maximumConsecutiveLosses: maxConsecutiveLosses,
    exposurePercent: exposurePercent,
    positionSlotUtilizationPercent: slotUtilization,
    candidatesObserved: observed,
    candidatesRejected: rejectedEvents.length,
    entriesOpened: opened,
    signalToEntryConversionPercent: observed == 0 ? 0 : opened / observed * 100,
    rejectionsByReason: Map.unmodifiable(rejections),
    averageMfeR: mfeRValues.isEmpty ? 0 : _average(mfeRValues),
    medianMfeR: _median(mfeRValues),
    averageMaeR: maeRValues.isEmpty ? 0 : _average(maeRValues),
    medianMaeR: _median(maeRValues),
    stopOutCount: stopOuts,
    tp1OrBetterCount: tp1OrBetter,
    tp2OrBetterCount: tp2OrBetter,
    tp3Count: tp3,
    partialExitTrades: partialExitTrades,
    sampleWarning: closed.length < 30
        ? 'Small sample (${closed.length} closed trades): do not label this strategy/configuration as winning or losing yet.'
        : null,
  );
}

Map<String, Object?> compareTradingLabRuns(
  TradingLabRun champion,
  TradingLabRun candidate, {
  DateTime? evidenceAtUtc,
}) {
  final evidenceAt = evidenceAtUtc?.toUtc() ?? DateTime.now().toUtc();
  final left = calculateTradingLabMetrics(champion, evidenceAtUtc: evidenceAt);
  final right = calculateTradingLabMetrics(candidate, evidenceAtUtc: evidenceAt);
  return {
    'schema': 'quantara.trading_lab.comparison.v1',
    'evidenceAtUtc': evidenceAt.toIso8601String(),
    'championRunId': champion.manifest.runId,
    'candidateRunId': candidate.manifest.runId,
    'champion': left.toJson(),
    'candidate': right.toJson(),
    'delta': {
      'returnPercent': right.returnPercent - left.returnPercent,
      'maximumDrawdownPercent':
          right.maximumDrawdownPercent - left.maximumDrawdownPercent,
      'profitFactor': _finiteOrNull(right.profitFactor) == null ||
              _finiteOrNull(left.profitFactor) == null
          ? null
          : right.profitFactor! - left.profitFactor!,
      'expectancyUsdt': right.expectancyUsdt - left.expectancyUsdt,
      'averageR': right.averageR - left.averageR,
      'winRatePercent': right.winRatePercent - left.winRatePercent,
      'signalToEntryConversionPercent':
          right.signalToEntryConversionPercent - left.signalToEntryConversionPercent,
      'positionSlotUtilizationPercent':
          right.positionSlotUtilizationPercent -
          left.positionSlotUtilizationPercent,
    },
    'promotionGuard': {
      'candidateHasEnoughTrades': right.tradeCount >= 30,
      'championHasEnoughTrades': left.tradeCount >= 30,
      'sameSymbols': _sameSet(champion.manifest.symbols, candidate.manifest.symbols),
      'sameTimeframes':
          _sameSet(champion.manifest.timeframes, candidate.manifest.timeframes),
      'warning': right.tradeCount < 30 || left.tradeCount < 30
          ? 'Comparison is informational only until both samples are large enough.'
          : null,
    },
  };
}

double _mfeR(TradingLabPosition position) {
  final favorable = switch (position.direction) {
    TradeDirection.long =>
      (position.maximumFavorablePrice ?? position.entryPrice) -
          position.entryPrice,
    TradeDirection.short =>
      position.entryPrice -
          (position.maximumFavorablePrice ?? position.entryPrice),
    TradeDirection.wait => 0.0,
  };
  final pnl = favorable * position.initialQuantity;
  return position.initialRisk <= 1e-9 ? 0 : pnl / position.initialRisk;
}

double _maeR(TradingLabPosition position) {
  final adverse = switch (position.direction) {
    TradeDirection.long =>
      position.entryPrice -
          (position.maximumAdversePrice ?? position.entryPrice),
    TradeDirection.short =>
      (position.maximumAdversePrice ?? position.entryPrice) -
          position.entryPrice,
    TradeDirection.wait => 0.0,
  };
  final pnl = adverse * position.initialQuantity;
  return position.initialRisk <= 1e-9 ? 0 : pnl / position.initialRisk;
}

int _maximumDrawdownDuration(TradingLabRun run, DateTime evidenceAt) {
  final heartbeats = run.events
      .where((event) => event.kind == TradingLabEventKind.heartbeat)
      .where((event) => event.metrics['equity'] != null)
      .toList(growable: false)
    ..sort((a, b) => a.atUtc.compareTo(b.atUtc));
  if (heartbeats.isEmpty) return 0;
  var peak = run.manifest.startingEquity;
  DateTime? drawdownStarted;
  var maximumSeconds = 0;
  for (final heartbeat in heartbeats) {
    final equity = heartbeat.metrics['equity'] ?? peak;
    if (equity >= peak - 1e-9) {
      peak = math.max(peak, equity);
      if (drawdownStarted != null) {
        maximumSeconds = math.max(
          maximumSeconds,
          heartbeat.atUtc.difference(drawdownStarted).inSeconds,
        );
        drawdownStarted = null;
      }
    } else {
      drawdownStarted ??= heartbeat.atUtc;
    }
  }
  if (drawdownStarted != null) {
    maximumSeconds = math.max(
      maximumSeconds,
      evidenceAt.difference(drawdownStarted).inSeconds,
    );
  }
  return math.max(0, maximumSeconds);
}

double _average(List<double> values) =>
    values.fold<double>(0, (sum, value) => sum + value) / values.length;

double _median(List<double> values) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  final middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[middle];
  return (sorted[middle - 1] + sorted[middle]) / 2;
}

double? _finiteOrNull(double? value) =>
    value != null && value.isFinite ? value : null;

bool _sameSet(Iterable<String> left, Iterable<String> right) {
  final leftSet = left.toSet();
  final rightSet = right.toSet();
  return leftSet.length == rightSet.length && leftSet.containsAll(rightSet);
}
