import 'dart:collection';

enum MarketRegime {
  accumulation,
  markup,
  distribution,
  markdown,
  range,
  transition,
}

enum StrategyKind { structureZones, trendCandle, dowContinuation, kbsmResearch }

enum StrategyMaturity { validatedCandidate, experimental, researchOnly }

enum LabExitReason { stopLoss, target1, target2, target3, endOfWindow }

final class StrategyDefinition {
  const StrategyDefinition({
    required this.kind,
    required this.id,
    required this.version,
    required this.maturity,
    required this.allowedTimeframes,
  });

  final StrategyKind kind;
  final String id;
  final String version;
  final StrategyMaturity maturity;
  final Set<String> allowedTimeframes;

  static const all = [
    StrategyDefinition(
      kind: StrategyKind.structureZones,
      id: 'structure-zones',
      version: '1.1',
      maturity: StrategyMaturity.validatedCandidate,
      allowedTimeframes: {'15m', '1h', '4h'},
    ),
    StrategyDefinition(
      kind: StrategyKind.trendCandle,
      id: 'trend-candle-continuation',
      version: '0.1-research',
      maturity: StrategyMaturity.experimental,
      allowedTimeframes: {'15m', '1h', '4h'},
    ),
    StrategyDefinition(
      kind: StrategyKind.dowContinuation,
      id: 'dow-swing-continuation',
      version: '0.1-research',
      maturity: StrategyMaturity.experimental,
      allowedTimeframes: {'1h', '4h'},
    ),
    StrategyDefinition(
      kind: StrategyKind.kbsmResearch,
      id: 'kbsm-weekly-shadow',
      version: '0.1-shadow',
      maturity: StrategyMaturity.researchOnly,
      allowedTimeframes: {'4h', '1D'},
    ),
  ];

  static StrategyDefinition forKind(StrategyKind kind) =>
      all.firstWhere((item) => item.kind == kind);
}

final class StrategyLabConfig {
  const StrategyLabConfig({
    required this.strategy,
    required this.symbol,
    required this.timeframe,
    required this.window,
    required this.initialCapital,
    required this.riskPercent,
    this.feeRate = 0.0012,
    this.slippageRate = 0.0008,
  });

  final StrategyKind strategy;
  final String symbol;
  final String timeframe;
  final Duration window;
  final double initialCapital;
  final double riskPercent;
  final double feeRate;
  final double slippageRate;
}

final class StrategyLabTrade {
  const StrategyLabTrade({
    required this.direction,
    required this.openedAt,
    required this.closedAt,
    required this.entryPrice,
    required this.exitPrice,
    required this.stopLoss,
    required this.targetsHit,
    required this.exitReason,
    required this.netPnl,
    required this.rMultiple,
  });

  final String direction;
  final DateTime openedAt;
  final DateTime closedAt;
  final double entryPrice;
  final double exitPrice;
  final double stopLoss;
  final int targetsHit;
  final LabExitReason exitReason;
  final double netPnl;
  final double rMultiple;
}

final class StrategyLabReport {
  StrategyLabReport({
    required this.config,
    required this.regime,
    required this.startedAt,
    required this.endedAt,
    required Iterable<StrategyLabTrade> trades,
    required this.netPnl,
    required this.netReturnPercent,
    required this.winRate,
    required this.expectancy,
    required this.profitFactor,
    required this.maxDrawdownPercent,
    required this.warnings,
  }) : trades = UnmodifiableListView(trades.toList(growable: false));

  final StrategyLabConfig config;
  final MarketRegime regime;
  final DateTime startedAt;
  final DateTime endedAt;
  final UnmodifiableListView<StrategyLabTrade> trades;
  final double netPnl;
  final double netReturnPercent;
  final double winRate;
  final double expectancy;
  final double? profitFactor;
  final double maxDrawdownPercent;
  final List<String> warnings;

  int get stopCount => trades
      .where((trade) => trade.exitReason == LabExitReason.stopLoss)
      .length;
  int targetCount(int target) =>
      trades.where((trade) => trade.targetsHit >= target).length;
  int get wins => trades.where((trade) => trade.netPnl > 0).length;
  int get losses => trades.where((trade) => trade.netPnl < 0).length;
}

final class StrategyLabSession {
  const StrategyLabSession({
    required this.config,
    required this.startedAt,
    required this.endsAt,
  });

  final StrategyLabConfig config;
  final DateTime startedAt;
  final DateTime endsAt;

  bool isCompleteAt(DateTime now) => !now.isBefore(endsAt);
}

abstract interface class StrategyLabSessionStore {
  Future<StrategyLabSession?> load();

  Future<void> save(StrategyLabSession? session);
}
