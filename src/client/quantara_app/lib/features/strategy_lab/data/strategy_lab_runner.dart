import 'dart:math' as math;

import '../../market_analysis/data/chart_structure_analyzer.dart';
import '../../market_analysis/domain/market_chart_models.dart';
import '../../owner_alpha/data/trade_idea_factory.dart';
import '../../owner_alpha/domain/owner_alpha_models.dart';
import '../domain/strategy_lab_models.dart';
import 'market_regime_engine.dart';

abstract final class StrategyLabRunner {
  static StrategyLabReport run({
    required StrategyLabConfig config,
    required List<ChartCandle> candles,
  }) {
    if (candles.length < 36) {
      throw ArgumentError('At least 36 closed candles are required.');
    }
    final definition = StrategyDefinition.forKind(config.strategy);
    if (!definition.allowedTimeframes.contains(config.timeframe)) {
      throw ArgumentError('The timeframe is not supported by this strategy.');
    }
    final candleDuration = _durationFor(config.timeframe);
    final requestedStart = candles.last.openTime
        .add(candleDuration)
        .subtract(config.window);
    var startIndex = candles.indexWhere(
      (candle) => !candle.openTime.isBefore(requestedStart),
    );
    startIndex = math.max(30, startIndex < 0 ? 30 : startIndex);
    final trades = <StrategyLabTrade>[];
    var equity = config.initialCapital;
    var peakEquity = equity;
    var maxDrawdown = 0.0;
    _OpenTrade? openTrade;

    for (var index = startIndex; index < candles.length; index++) {
      final candle = candles[index];
      if (openTrade != null) {
        final closed = _advance(openTrade, candle, config);
        if (closed != null) {
          trades.add(closed);
          equity += closed.netPnl;
          peakEquity = math.max(peakEquity, equity);
          maxDrawdown = math.max(
            maxDrawdown,
            peakEquity <= 0 ? 0 : (peakEquity - equity) / peakEquity * 100,
          );
          openTrade = null;
        }
      }
      if (openTrade != null && !openTrade.openedAt.isAfter(candle.openTime)) {
        final markedEquity =
            equity + openTrade.markToMarket(candle.close, config);
        peakEquity = math.max(peakEquity, markedEquity);
        maxDrawdown = math.max(
          maxDrawdown,
          peakEquity <= 0 ? 0 : (peakEquity - markedEquity) / peakEquity * 100,
        );
      }
      if (openTrade != null || index >= candles.length - 1) {
        continue;
      }
      final history = candles.sublist(math.max(0, index - 119), index + 1);
      final signal = _signal(config, history, equity);
      if (signal == null || !signal.isActionable) {
        continue;
      }
      final next = candles[index + 1];
      if (!_touchesEntry(next, signal)) {
        continue;
      }
      final entry = signal.direction == TradeDirection.long
          ? signal.entryUpper!
          : signal.entryLower!;
      openTrade = _OpenTrade(
        idea: signal,
        openedAt: next.openTime,
        entry: entry,
        units: signal.positionSize!,
        remainingUnits: signal.positionSize!,
        initialRisk:
            signal.positionSize! * (entry - signal.stopLoss!).abs() +
            signal.positionSize! * entry * _totalCostRate(config),
      );
    }

    if (openTrade != null) {
      final last = candles.last;
      final closed = _closeAtEnd(openTrade, last, config);
      trades.add(closed);
      equity += closed.netPnl;
      peakEquity = math.max(peakEquity, equity);
      maxDrawdown = math.max(
        maxDrawdown,
        peakEquity <= 0 ? 0 : (peakEquity - equity) / peakEquity * 100,
      );
    }

    final grossWins = trades
        .where((trade) => trade.netPnl > 0)
        .fold<double>(0, (sum, trade) => sum + trade.netPnl);
    final grossLosses = trades
        .where((trade) => trade.netPnl < 0)
        .fold<double>(0, (sum, trade) => sum + trade.netPnl.abs());
    final netPnl = equity - config.initialCapital;
    final warnings = <String>[
      'Intrabar SL/TP ambiguity is resolved conservatively: stop first.',
      'Funding, liquidation tiers and partial-fill liquidity are unavailable in this device-only preview.',
      if (trades.length < 20)
        'Small sample: do not promote this strategy from this result.',
      if (definition.maturity != StrategyMaturity.validatedCandidate)
        'This strategy is experimental and remains in research/paper mode.',
      if (candles[startIndex].openTime.isAfter(
        requestedStart.add(candleDuration),
      ))
        'The requested window exceeded cached history; the report uses the available closed candles only.',
    ];
    return StrategyLabReport(
      config: config,
      regime: MarketRegimeEngine.classify(candles),
      startedAt: candles[startIndex].openTime,
      endedAt: candles.last.openTime.add(candleDuration),
      trades: trades,
      netPnl: netPnl,
      netReturnPercent: netPnl / config.initialCapital * 100,
      winRate: trades.isEmpty
          ? 0
          : trades.where((trade) => trade.netPnl > 0).length /
                trades.length *
                100,
      expectancy: trades.isEmpty ? 0 : netPnl / trades.length,
      profitFactor: grossLosses == 0
          ? (grossWins > 0 ? null : 0)
          : grossWins / grossLosses,
      maxDrawdownPercent: maxDrawdown,
      warnings: List.unmodifiable(warnings),
    );
  }

  static TradeIdea? _signal(
    StrategyLabConfig config,
    List<ChartCandle> candles,
    double equity,
  ) {
    final structure = ChartStructureAnalyzer.analyze(candles);
    final analysis = TimeframeChartAnalysis(
      symbol: config.symbol,
      timeframe: config.timeframe,
      candles: candles,
      zones: structure.zones,
      direction: structure.direction,
      directionStrength: structure.directionStrength,
      volatilityPercent: structure.volatilityPercent,
      summary: 'Strategy Lab point-in-time analysis',
      generatedAt: candles.last.openTime.toUtc(),
      fingerprint:
          '${config.symbol}|${config.timeframe}|${candles.last.openTime.millisecondsSinceEpoch}',
    );
    final idea = TradeIdeaFactory.create(
      analysis: analysis,
      capital: equity,
      riskPercent: config.riskPercent,
      languageCode: 'en',
    );
    if (!idea.isActionable) {
      return null;
    }
    return switch (config.strategy) {
      StrategyKind.structureZones => idea,
      StrategyKind.trendCandle =>
        _trendCandleConfirms(candles, idea) ? idea : null,
      StrategyKind.dowContinuation => _dowConfirms(candles, idea) ? idea : null,
      StrategyKind.kbsmResearch => _kbsmConfirms(candles, idea) ? idea : null,
    };
  }

  static bool _trendCandleConfirms(List<ChartCandle> candles, TradeIdea idea) {
    final latest = candles.last;
    final sma7 =
        candles
            .sublist(candles.length - 7)
            .fold<double>(0, (sum, item) => sum + item.close) /
        7;
    final body = (latest.close - latest.open).abs();
    final range = latest.high - latest.low;
    final alignedCandle = idea.direction == TradeDirection.long
        ? latest.isBullish && latest.close > sma7
        : !latest.isBullish && latest.close < sma7;
    return alignedCandle && range > 0 && body / range >= 0.52;
  }

  static bool _dowConfirms(List<ChartCandle> candles, TradeIdea idea) {
    final recent = candles.sublist(candles.length - 12);
    final first = recent.sublist(0, 6);
    final second = recent.sublist(6);
    final firstHigh = first.map((item) => item.high).reduce(math.max);
    final firstLow = first.map((item) => item.low).reduce(math.min);
    final secondHigh = second.map((item) => item.high).reduce(math.max);
    final secondLow = second.map((item) => item.low).reduce(math.min);
    return idea.direction == TradeDirection.long
        ? secondHigh > firstHigh && secondLow > firstLow
        : secondHigh < firstHigh && secondLow < firstLow;
  }

  static bool _kbsmConfirms(List<ChartCandle> candles, TradeIdea idea) {
    final latest = candles.last;
    final range = latest.high - latest.low;
    if (range <= 0) {
      return false;
    }
    final upperWick = latest.high - math.max(latest.open, latest.close);
    final lowerWick = math.min(latest.open, latest.close) - latest.low;
    return idea.direction == TradeDirection.long
        ? lowerWick / range >= 0.45
        : upperWick / range >= 0.45;
  }

  static bool _touchesEntry(ChartCandle candle, TradeIdea idea) =>
      candle.low <= idea.entryUpper! && candle.high >= idea.entryLower!;

  static StrategyLabTrade? _advance(
    _OpenTrade trade,
    ChartCandle candle,
    StrategyLabConfig config,
  ) {
    final long = trade.idea.direction == TradeDirection.long;
    final stopped = long
        ? candle.low <= trade.idea.stopLoss!
        : candle.high >= trade.idea.stopLoss!;
    if (stopped) {
      return _close(
        trade,
        candle.openTime,
        trade.idea.stopLoss!,
        LabExitReason.stopLoss,
        config,
      );
    }
    while (trade.targetsHit < 3) {
      final target = trade.idea.targets[trade.targetsHit];
      final hit = long ? candle.high >= target : candle.low <= target;
      if (!hit) {
        break;
      }
      trade.realizeTarget(target, config);
    }
    if (trade.targetsHit == 3) {
      return _finish(
        trade,
        candle.openTime,
        trade.idea.targets.last,
        LabExitReason.target3,
        config,
      );
    }
    return null;
  }

  static StrategyLabTrade _closeAtEnd(
    _OpenTrade trade,
    ChartCandle candle,
    StrategyLabConfig config,
  ) => _close(
    trade,
    candle.openTime,
    candle.close,
    LabExitReason.endOfWindow,
    config,
  );

  static StrategyLabTrade _close(
    _OpenTrade trade,
    DateTime time,
    double price,
    LabExitReason reason,
    StrategyLabConfig config,
  ) {
    trade.realizeRemaining(price, config);
    return _finish(trade, time, price, reason, config);
  }

  static StrategyLabTrade _finish(
    _OpenTrade trade,
    DateTime time,
    double price,
    LabExitReason reason,
    StrategyLabConfig config,
  ) {
    final entryCosts = trade.units * trade.entry * _totalCostRate(config) / 2;
    final net = trade.realizedPnl - entryCosts;
    return StrategyLabTrade(
      direction: trade.idea.direction.name,
      openedAt: trade.openedAt,
      closedAt: time,
      entryPrice: trade.entry,
      exitPrice: price,
      stopLoss: trade.idea.stopLoss!,
      targetsHit: trade.targetsHit,
      exitReason: reason,
      netPnl: net,
      rMultiple: trade.initialRisk <= 0 ? 0 : net / trade.initialRisk,
    );
  }

  static double _totalCostRate(StrategyLabConfig config) =>
      config.feeRate + config.slippageRate;

  static Duration _durationFor(String timeframe) => switch (timeframe) {
    '15m' => const Duration(minutes: 15),
    '1h' => const Duration(hours: 1),
    '4h' => const Duration(hours: 4),
    '1D' => const Duration(days: 1),
    _ => throw ArgumentError('Unsupported timeframe.'),
  };
}

final class _OpenTrade {
  _OpenTrade({
    required this.idea,
    required this.openedAt,
    required this.entry,
    required this.units,
    required this.remainingUnits,
    required this.initialRisk,
  });

  final TradeIdea idea;
  final DateTime openedAt;
  final double entry;
  final double units;
  double remainingUnits;
  final double initialRisk;
  double realizedPnl = 0;
  int targetsHit = 0;

  void realizeTarget(double price, StrategyLabConfig config) {
    final fraction = targetsHit < 2 ? 0.33 : 1.0;
    final exitUnits = targetsHit < 2 ? units * fraction : remainingUnits;
    _realize(exitUnits, price, config);
    targetsHit++;
  }

  void realizeRemaining(double price, StrategyLabConfig config) {
    _realize(remainingUnits, price, config);
  }

  double markToMarket(double price, StrategyLabConfig config) {
    final long = idea.direction == TradeDirection.long;
    final unrealized = long
        ? (price - entry) * remainingUnits
        : (entry - price) * remainingUnits;
    final entryCosts =
        units * entry * (config.feeRate + config.slippageRate) / 2;
    final estimatedExitCosts =
        remainingUnits * price * (config.feeRate + config.slippageRate) / 2;
    return realizedPnl + unrealized - entryCosts - estimatedExitCosts;
  }

  void _realize(double exitUnits, double price, StrategyLabConfig config) {
    if (exitUnits <= 0) {
      return;
    }
    final long = idea.direction == TradeDirection.long;
    final gross = long
        ? (price - entry) * exitUnits
        : (entry - price) * exitUnits;
    final exitCosts =
        exitUnits * price * (config.feeRate + config.slippageRate) / 2;
    realizedPnl += gross - exitCosts;
    remainingUnits = math.max(0, remainingUnits - exitUnits);
  }
}
