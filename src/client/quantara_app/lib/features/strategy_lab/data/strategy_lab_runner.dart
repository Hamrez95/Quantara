import 'dart:math' as math;

import '../../market_analysis/data/chart_structure_analyzer.dart';
import '../../market_analysis/domain/market_chart_models.dart';
import '../../owner_alpha/data/professional_portfolio_candidate_adapter.dart';
import '../../owner_alpha/data/professional_strategy_engine.dart';
import '../../owner_alpha/domain/owner_alpha_models.dart';
import '../../portfolio_risk/domain/portfolio_risk_models.dart';
import '../domain/strategy_lab_models.dart';
import 'market_regime_engine.dart';

abstract final class StrategyLabRunner {
  static StrategyLabReport run({
    required StrategyLabConfig config,
    required List<ChartCandle> candles,
  }) {
    _validateInput(config, candles);
    final definition = StrategyDefinition.forKind(config.strategy);
    final candleDuration = _durationFor(config.timeframe);
    final requestedStart = candles.last.openTime
        .add(candleDuration)
        .subtract(config.window);
    final minimumHistory = _minimumHistory(config.timeframe);
    var startIndex = candles.indexWhere(
      (candle) => !candle.openTime.isBefore(requestedStart),
    );
    startIndex = math.max(
      minimumHistory - 1,
      startIndex < 0 ? minimumHistory - 1 : startIndex,
    );
    if (startIndex >= candles.length - 1) {
      throw ArgumentError(
        'The closed-candle history is too short for testing.',
      );
    }

    final trades = <StrategyLabTrade>[];
    var equity = config.initialCapital;
    var peakEquity = equity;
    var maxDrawdown = 0.0;
    var admittedReservations = 0;
    var rejectedReservations = 0;
    _OpenTrade? openTrade;
    final gate = _LabPortfolioGate(
      config: config,
      startedAt: candles[startIndex].openTime,
    );

    for (var index = startIndex; index < candles.length; index++) {
      final candle = candles[index];
      if (openTrade != null) {
        final closed = _advance(openTrade, candle, config);
        if (closed != null) {
          gate.close(
            positionId: openTrade.positionId,
            setupId: openTrade.idea.setupId,
            netPnl: closed.netPnl,
            at: candle.openTime,
          );
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
      if (openTrade != null || index >= candles.length - 1) continue;

      final history = candles.sublist(
        math.max(0, index - _historyLimit(config.timeframe) + 1),
        index + 1,
      );
      final signal = _signal(config, history, equity);
      if (signal == null || !signal.isActionable) continue;

      PortfolioEntryCandidate candidate;
      try {
        candidate = ProfessionalPortfolioCandidateAdapter.fromIdea(
          idea: signal,
          rules: _exchangeRules(config),
        );
      } on ProfessionalCandidateException {
        rejectedReservations += 1;
        continue;
      }

      final signalClosedAt = history.last.openTime.add(candleDuration);
      final admission = gate.reserve(
        candidate: candidate,
        equity: equity,
        at: signalClosedAt,
      );
      if (!admission.allowed) {
        rejectedReservations += 1;
        continue;
      }
      admittedReservations += 1;

      final next = candles[index + 1];
      if (!_touchesEntry(next, signal)) {
        gate.cancel(
          reservationId: candidate.reservationId,
          setupId: candidate.candidateId,
          at: next.openTime,
        );
        continue;
      }

      final entry = signal.direction == TradeDirection.long
          ? signal.entryUpper!
          : signal.entryLower!;
      final positionId = gate.fill(candidate: candidate, at: next.openTime);
      openTrade = _OpenTrade(
        idea: signal,
        candidate: candidate,
        positionId: positionId,
        openedAt: next.openTime,
        entry: entry,
        units: candidate.plannedQuantity,
        remainingUnits: candidate.plannedQuantity,
        initialRisk: admission.maximumLoss,
        reservedMargin: admission.requiredMargin,
      );
    }

    if (openTrade != null) {
      final last = candles.last;
      final closed = _closeAtEnd(openTrade, last, config);
      gate.close(
        positionId: openTrade.positionId,
        setupId: openTrade.idea.setupId,
        netPnl: closed.netPnl,
        at: last.openTime.add(candleDuration),
      );
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
    final folds = _walkForwardFolds(
      config: config,
      candles: candles,
      startIndex: startIndex,
      trades: trades,
      candleDuration: candleDuration,
    );
    final leakageDetected = folds.any((fold) => !fold.leakFree);
    final warnings = <String>[
      'Signals use only candles closed at or before their decision time.',
      'Walk-forward folds use an expanding training window and a strictly later test window; no parameter is optimized on test data.',
      'Every simulated entry is converted to a PortfolioEntryCandidate and atomically admitted against risk and margin before fill.',
      'Intrabar SL/TP ambiguity is resolved conservatively: stop first.',
      'Fees, slippage and a funding reserve are included; liquidation tiers and order-book impact remain unavailable.',
      'Real exchange execution remains disabled.',
      if (trades.length < 20)
        'Small sample: do not promote this strategy from this result.',
      if (definition.maturity != StrategyMaturity.validatedCandidate)
        'This strategy remains experimental and paper-only.',
      if (candles[startIndex].openTime.isAfter(
        requestedStart.add(candleDuration),
      ))
        'The requested window exceeded cached history; only available closed candles were used.',
      if (rejectedReservations > 0)
        '$rejectedReservations setup candidates were rejected by exchange, risk or margin gates.',
      if (leakageDetected)
        'DATA LEAKAGE DETECTED: this report must not be used.',
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
      walkForwardFolds: folds,
      reservedEntries: admittedReservations,
      rejectedEntries: rejectedReservations,
      dataLeakageDetected: leakageDetected,
    );
  }

  static void _validateInput(
    StrategyLabConfig config,
    List<ChartCandle> candles,
  ) {
    if (candles.length < _minimumHistory(config.timeframe) + 1) {
      throw ArgumentError(
        'More closed candles are required for this timeframe.',
      );
    }
    if (!StrategyDefinition.forKind(
      config.strategy,
    ).allowedTimeframes.contains(config.timeframe)) {
      throw ArgumentError('The timeframe is not supported by this strategy.');
    }
    if (!config.initialCapital.isFinite || config.initialCapital <= 0) {
      throw ArgumentError('Initial capital is invalid.');
    }
    if (!config.riskPercent.isFinite ||
        config.riskPercent <= 0 ||
        config.riskPercent > 2) {
      throw ArgumentError('Risk percent is invalid.');
    }
    for (var index = 0; index < candles.length; index++) {
      final candle = candles[index];
      if (!candle.isValid ||
          (index > 0 &&
              !candle.openTime.isAfter(candles[index - 1].openTime))) {
        throw ArgumentError('Candles must be valid, UTC and strictly ordered.');
      }
    }
  }

  static TradeIdea? _signal(
    StrategyLabConfig config,
    List<ChartCandle> candles,
    double equity,
  ) {
    final structure = ChartStructureAnalyzer.analyze(candles);
    final closedAt = candles.last.openTime.add(_durationFor(config.timeframe));
    final analysis = TimeframeChartAnalysis(
      symbol: config.symbol,
      timeframe: config.timeframe,
      candles: candles,
      zones: structure.zones,
      direction: structure.direction,
      directionStrength: structure.directionStrength,
      volatilityPercent: structure.volatilityPercent,
      summary: 'Point-in-time professional Strategy Lab analysis',
      generatedAt: closedAt,
      fingerprint:
          '${config.symbol}|${config.timeframe}|${closedAt.millisecondsSinceEpoch}',
    );
    final requestedStrategy = switch (config.strategy) {
      StrategyKind.structureZones ||
      StrategyKind.trendCandle => AnalysisStrategy.structureZones,
      StrategyKind.dowContinuation => AnalysisStrategy.trendPullback,
      StrategyKind.kbsmResearch => AnalysisStrategy.momentumContinuation,
    };
    final confluence = _parentConfluence(
      timeframe: config.timeframe,
      candles: candles,
      evaluatedAt: closedAt,
    );
    final idea = ProfessionalStrategyEngine.create(
      analysis: analysis,
      capital: equity,
      riskPercent: config.riskPercent,
      confluence: confluence,
      languageCode: 'en',
      strategy: requestedStrategy,
      cadence: SignalCadence.balanced,
      context: ProfessionalStrategyContext(
        evaluatedAt: closedAt,
        entryFeeRate: config.feeRate / 2,
        exitFeeRate: config.feeRate / 2,
        slippageRate: config.slippageRate,
        fundingReserveRate: config.fundingReserveRate,
        minimumQuantity: config.minimumQuantity,
        minimumNotional: config.minimumNotional,
        maximumLeverage: config.maximumLeverage,
      ),
    );
    if (!idea.isActionable) return null;
    final requiredVersion = switch (config.strategy) {
      StrategyKind.structureZones => 'rangeReversal/1.0',
      StrategyKind.trendCandle => 'arshiaCandle/1.0',
      StrategyKind.dowContinuation => 'trendPullback/1.0',
      StrategyKind.kbsmResearch => 'breakoutRetest/1.0',
    };
    return idea.strategyVersion == requiredVersion ? idea : null;
  }

  static Map<String, ChartDirection> _parentConfluence({
    required String timeframe,
    required List<ChartCandle> candles,
    required DateTime evaluatedAt,
  }) {
    final parent = _parentTimeframe(timeframe);
    if (parent == null) return const {};
    final factor = _parentFactor(timeframe);
    final childDuration = _durationFor(timeframe);
    final parentDuration = _durationFor(parent);
    final aggregated = _aggregateClosedParents(
      candles: candles,
      factor: factor,
      childDuration: childDuration,
      parentDuration: parentDuration,
      evaluatedAt: evaluatedAt,
    );
    if (aggregated.length < 20) return const {};
    final latestParentClose = aggregated.last.openTime.add(parentDuration);
    if (latestParentClose.isAfter(evaluatedAt) ||
        evaluatedAt.difference(latestParentClose) > parentDuration * 2) {
      return const {};
    }
    final structure = ChartStructureAnalyzer.analyze(aggregated);
    return {parent: structure.direction};
  }

  static List<ChartCandle> _aggregateClosedParents({
    required List<ChartCandle> candles,
    required int factor,
    required Duration childDuration,
    required Duration parentDuration,
    required DateTime evaluatedAt,
  }) {
    final buckets = <int, List<ChartCandle>>{};
    final parentMillis = parentDuration.inMilliseconds;
    for (final candle in candles) {
      final key = candle.openTime.millisecondsSinceEpoch ~/ parentMillis;
      buckets.putIfAbsent(key, () => <ChartCandle>[]).add(candle);
    }
    final keys = buckets.keys.toList()..sort();
    final result = <ChartCandle>[];
    for (final key in keys) {
      final values = buckets[key]!
        ..sort((left, right) => left.openTime.compareTo(right.openTime));
      if (values.length != factor) continue;
      var contiguous = true;
      for (var index = 1; index < values.length; index++) {
        if (values[index].openTime.difference(values[index - 1].openTime) !=
            childDuration) {
          contiguous = false;
          break;
        }
      }
      if (!contiguous) continue;
      final openTime = DateTime.fromMillisecondsSinceEpoch(
        key * parentMillis,
        isUtc: true,
      );
      final closedAt = openTime.add(parentDuration);
      if (closedAt.isAfter(evaluatedAt)) continue;
      result.add(
        ChartCandle(
          openTime: openTime,
          open: values.first.open,
          high: values.map((item) => item.high).reduce(math.max),
          low: values.map((item) => item.low).reduce(math.min),
          close: values.last.close,
          volume: values.fold<double>(0, (sum, item) => sum + item.volume),
        ),
      );
    }
    return result;
  }

  static ProfessionalExchangeRules _exchangeRules(StrategyLabConfig config) =>
      ProfessionalExchangeRules(
        symbol: config.symbol,
        minimumQuantity: config.minimumQuantity,
        minimumNotional: config.minimumNotional,
        quantityPrecision: 6,
        contractMultiplier: 1,
        entryFeeRate: config.feeRate / 2,
        exitFeeRate: config.feeRate / 2,
        slippageRate: config.slippageRate,
        fundingReserveRate: config.fundingReserveRate,
        maximumLeverage: config.maximumLeverage,
      );

  static List<StrategyLabFold> _walkForwardFolds({
    required StrategyLabConfig config,
    required List<ChartCandle> candles,
    required int startIndex,
    required List<StrategyLabTrade> trades,
    required Duration candleDuration,
  }) {
    final evaluationCount = candles.length - startIndex;
    final count = config.walkForwardFolds.clamp(2, 6).toInt();
    if (evaluationCount < count * 2) return const [];
    final folds = <StrategyLabFold>[];
    for (var fold = 0; fold < count; fold++) {
      final testStart = startIndex + evaluationCount * fold ~/ count;
      final testEndExclusive =
          startIndex + evaluationCount * (fold + 1) ~/ count;
      if (testEndExclusive <= testStart) continue;
      final testStartedAt = candles[testStart].openTime;
      final testEndedAt = candles[testEndExclusive - 1].openTime.add(
        candleDuration,
      );
      final foldTrades = trades
          .where(
            (trade) =>
                !trade.openedAt.isBefore(testStartedAt) &&
                trade.openedAt.isBefore(testEndedAt),
          )
          .toList(growable: false);
      folds.add(
        StrategyLabFold(
          index: fold + 1,
          trainingStartedAt: candles.first.openTime,
          trainingEndedAt: testStartedAt.subtract(
            const Duration(microseconds: 1),
          ),
          testStartedAt: testStartedAt,
          testEndedAt: testEndedAt,
          tradeCount: foldTrades.length,
          netPnl: foldTrades.fold<double>(
            0,
            (sum, trade) => sum + trade.netPnl,
          ),
        ),
      );
    }
    return folds;
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
      if (!hit) break;
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
    final entryCosts =
        trade.units *
        trade.entry *
        StrategyLabRunner._totalCostRate(config) /
        2;
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
      setupId: trade.idea.setupId,
      reservedRisk: trade.initialRisk,
      reservedMargin: trade.reservedMargin,
    );
  }

  static double _totalCostRate(StrategyLabConfig config) =>
      config.feeRate + config.slippageRate + config.fundingReserveRate;

  static int _minimumHistory(String timeframe) => switch (timeframe) {
    '15m' || '1h' => 80,
    '4h' => 120,
    '1D' => 60,
    _ => throw ArgumentError('Unsupported timeframe.'),
  };

  static int _historyLimit(String timeframe) => switch (timeframe) {
    '4h' => 240,
    _ => 160,
  };

  static int _parentFactor(String timeframe) => switch (timeframe) {
    '15m' || '1h' => 4,
    '4h' => 6,
    _ => 1,
  };

  static String? _parentTimeframe(String timeframe) => switch (timeframe) {
    '15m' => '1h',
    '1h' => '4h',
    '4h' => '1D',
    '1D' => null,
    _ => null,
  };

  static Duration _durationFor(String timeframe) => switch (timeframe) {
    '15m' => const Duration(minutes: 15),
    '1h' => const Duration(hours: 1),
    '4h' => const Duration(hours: 4),
    '1D' => const Duration(days: 1),
    _ => throw ArgumentError('Unsupported timeframe.'),
  };
}

final class _LabPortfolioGate {
  _LabPortfolioGate({required this.config, required DateTime startedAt})
    : _dailyRiskLimit = math.max(
        config.initialCapital * 0.005,
        math.min(
          config.initialCapital * 0.05,
          config.initialCapital * config.riskPercent / 100 * 4,
        ),
      ),
      _ledger = PortfolioRiskLedger.initial(
        tradingDay: TradingDayId.start(
          now: startedAt,
          timezoneOffsetMinutes: 0,
        ),
        dailyRiskLimit: math.max(
          config.initialCapital * 0.005,
          math.min(
            config.initialCapital * 0.05,
            config.initialCapital * config.riskPercent / 100 * 4,
          ),
        ),
      );

  final StrategyLabConfig config;
  final double _dailyRiskLimit;
  final PortfolioRiskPolicy _policy = const PortfolioRiskPolicy(
    maximumDirectionRiskFraction: 1,
  );
  PortfolioRiskLedger _ledger;

  PortfolioEntryDecision reserve({
    required PortfolioEntryCandidate candidate,
    required double equity,
    required DateTime at,
  }) {
    _ledger = _ledger.rollTradingDay(
      now: at,
      nextDailyRiskLimit: _dailyRiskLimit,
    );
    final decision = _policy.evaluate(
      ledger: _ledger,
      candidate: candidate,
      account: _account(equity: equity, at: at),
    );
    if (decision.allowed) {
      _ledger = _ledger.reserve(
        candidate: candidate,
        decision: decision,
        createdAt: at,
      );
    }
    return decision;
  }

  String fill({
    required PortfolioEntryCandidate candidate,
    required DateTime at,
  }) {
    final positionId = 'lab-position-${candidate.candidateId}';
    _ledger = _ledger.applyPartialFill(
      reservationId: candidate.reservationId,
      eventId: 'lab-fill-${candidate.candidateId}-${at.microsecondsSinceEpoch}',
      entryOrderId: 'lab-order-${candidate.candidateId}',
      positionId: positionId,
      fillQuantity: candidate.plannedQuantity,
    );
    return positionId;
  }

  void cancel({
    required String reservationId,
    required String setupId,
    required DateTime at,
  }) {
    _ledger = _ledger.release(
      reservationId: reservationId,
      eventId: 'lab-cancel-$setupId-${at.microsecondsSinceEpoch}',
    );
  }

  void close({
    required String positionId,
    required String setupId,
    required double netPnl,
    required DateTime at,
  }) {
    _ledger = _ledger.rollTradingDay(
      now: at,
      nextDailyRiskLimit: _dailyRiskLimit,
    );
    _ledger = _ledger.closePosition(
      positionId: positionId,
      eventId: 'lab-close-$setupId-${at.microsecondsSinceEpoch}',
      exchangeConfirmedNetPnl: netPnl,
    );
  }

  PortfolioAccountTruth _account({
    required double equity,
    required DateTime at,
  }) => PortfolioAccountTruth(
    asOf: at.toUtc(),
    fresh: true,
    allOpenPositionsProtected: true,
    marginMode: 'isolated',
    freeMargin: math.max(0, equity),
    usedMargin: 0,
    maintenanceMargin: 0,
    pendingMarginReservations: _ledger.reservedMargin,
    safetyBuffer: math.max(1, equity * 0.05),
    feeReserve: math.max(0.1, equity * 0.005),
  );
}

final class _OpenTrade {
  _OpenTrade({
    required this.idea,
    required this.candidate,
    required this.positionId,
    required this.openedAt,
    required this.entry,
    required this.units,
    required this.remainingUnits,
    required this.initialRisk,
    required this.reservedMargin,
  });

  final TradeIdea idea;
  final PortfolioEntryCandidate candidate;
  final String positionId;
  final DateTime openedAt;
  final double entry;
  final double units;
  double remainingUnits;
  final double initialRisk;
  final double reservedMargin;
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
        units * entry * StrategyLabRunner._totalCostRate(config) / 2;
    final estimatedExitCosts =
        remainingUnits * price * StrategyLabRunner._totalCostRate(config) / 2;
    return realizedPnl + unrealized - entryCosts - estimatedExitCosts;
  }

  void _realize(double exitUnits, double price, StrategyLabConfig config) {
    if (exitUnits <= 0) return;
    final long = idea.direction == TradeDirection.long;
    final gross = long
        ? (price - entry) * exitUnits
        : (entry - price) * exitUnits;
    final exitCosts =
        exitUnits * price * StrategyLabRunner._totalCostRate(config) / 2;
    realizedPnl += gross - exitCosts;
    remainingUnits = math.max(0, remainingUnits - exitUnits);
  }
}
