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
      id: 'professional-range-reversal',
      version: '1.0',
      maturity: StrategyMaturity.validatedCandidate,
      allowedTimeframes: {'15m', '1h', '4h'},
    ),
    StrategyDefinition(
      kind: StrategyKind.trendCandle,
      id: 'professional-arshia-candle',
      version: '1.0',
      maturity: StrategyMaturity.validatedCandidate,
      allowedTimeframes: {'15m', '1h', '4h'},
    ),
    StrategyDefinition(
      kind: StrategyKind.dowContinuation,
      id: 'professional-trend-pullback',
      version: '1.0',
      maturity: StrategyMaturity.validatedCandidate,
      allowedTimeframes: {'15m', '1h', '4h'},
    ),
    StrategyDefinition(
      kind: StrategyKind.kbsmResearch,
      id: 'professional-breakout-retest',
      version: '1.0',
      maturity: StrategyMaturity.experimental,
      allowedTimeframes: {'15m', '1h', '4h'},
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
    this.fundingReserveRate = 0.0003,
    this.minimumQuantity = 0.001,
    this.minimumNotional = 5,
    this.maximumLeverage = 10,
    this.walkForwardFolds = 4,
    this.validationPurgeBars = 2,
    this.validationEmbargoBars = 2,
    this.lockedHoldoutFraction = 0.2,
  });

  final StrategyKind strategy;
  final String symbol;
  final String timeframe;
  final Duration window;
  final double initialCapital;
  final double riskPercent;
  final double feeRate;
  final double slippageRate;
  final double fundingReserveRate;
  final double minimumQuantity;
  final double minimumNotional;
  final int maximumLeverage;
  final int walkForwardFolds;
  final int validationPurgeBars;
  final int validationEmbargoBars;
  final double lockedHoldoutFraction;
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
    this.setupId = '',
    this.reservedRisk = 0,
    this.reservedMargin = 0,
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
  final String setupId;
  final double reservedRisk;
  final double reservedMargin;
}

final class StrategyLabFold {
  const StrategyLabFold({
    required this.index,
    required this.trainingStartedAt,
    required this.trainingEndedAt,
    required this.testStartedAt,
    required this.testEndedAt,
    required this.tradeCount,
    required this.netPnl,
    this.purgeStartedAt,
    this.purgeEndedAt,
    this.embargoStartedAt,
    this.embargoEndedAt,
  });

  final int index;
  final DateTime trainingStartedAt;
  final DateTime trainingEndedAt;
  final DateTime testStartedAt;
  final DateTime testEndedAt;
  final int tradeCount;
  final double netPnl;
  final DateTime? purgeStartedAt;
  final DateTime? purgeEndedAt;
  final DateTime? embargoStartedAt;
  final DateTime? embargoEndedAt;

  bool get leakFree => trainingEndedAt.isBefore(testStartedAt);

  bool get purgedAndEmbargoed {
    final purgeStart = purgeStartedAt;
    final purgeEnd = purgeEndedAt;
    final embargoStart = embargoStartedAt;
    final embargoEnd = embargoEndedAt;
    if (purgeStart == null ||
        purgeEnd == null ||
        embargoStart == null ||
        embargoEnd == null) {
      return false;
    }
    return !trainingEndedAt.isAfter(purgeStart) &&
        !purgeStart.isAfter(purgeEnd) &&
        !purgeEnd.isAfter(testStartedAt) &&
        !testEndedAt.isAfter(embargoStart) &&
        !embargoStart.isAfter(embargoEnd);
  }
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
    Iterable<StrategyLabFold> walkForwardFolds = const [],
    this.reservedEntries = 0,
    this.rejectedEntries = 0,
    this.dataLeakageDetected = false,
    this.lockedHoldoutStartedAt,
    this.lockedHoldoutTradeCount = 0,
    this.lockedHoldoutExpectancy = 0,
  }) : trades = UnmodifiableListView(trades.toList(growable: false)),
       walkForwardFolds = UnmodifiableListView(
         walkForwardFolds.toList(growable: false),
       );

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
  final UnmodifiableListView<StrategyLabFold> walkForwardFolds;
  final int reservedEntries;
  final int rejectedEntries;
  final bool dataLeakageDetected;
  final DateTime? lockedHoldoutStartedAt;
  final int lockedHoldoutTradeCount;
  final double lockedHoldoutExpectancy;

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
