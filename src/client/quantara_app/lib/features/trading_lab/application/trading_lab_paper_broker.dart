import 'dart:math' as math;

import '../../auto_trade/domain/profit_lock_stop_policy.dart';
import '../../market_analysis/domain/market_chart_models.dart';
import '../../owner_alpha/domain/owner_alpha_models.dart';
import '../../owner_alpha/domain/profit_protection_policy.dart';
import '../domain/trading_lab_account_context.dart';
import '../domain/trading_lab_models.dart';

final class TradingLabPaperBroker {
  const TradingLabPaperBroker();

  void processSnapshot(
    TradingLabRun run,
    OwnerAlphaSnapshot snapshot, {
    TradingLabAccountContext? accountContext,
  }) {
    if (!run.isRunning) return;
    final previous = run.lastSnapshotAtUtc;
    if (previous != null && !snapshot.generatedAt.isAfter(previous)) return;

    run.cycleId += 1;
    final cycle = run.cycleId;
    final snapshotGapSeconds = previous == null
        ? 0
        : snapshot.generatedAt.difference(previous).inSeconds;
    if (previous != null &&
        snapshotGapSeconds > run.manifest.scannerIntervalSeconds * 3) {
      _event(
        run,
        TradingLabEventKind.anomaly,
        snapshot.generatedAt,
        'Trading Lab market snapshot cadence exceeded the configured scanner interval.',
        metrics: {
          'gapSeconds': snapshotGapSeconds.toDouble(),
          'configuredScannerIntervalSeconds': run
              .manifest
              .scannerIntervalSeconds
              .toDouble(),
        },
        attributes: {'anomalyCode': 'scanner_gap'},
      );
    }
    final openedBefore = run.openPositions.length;
    final closedBefore = run.closedPositions.length;
    final lastScan = run.lastScanAtUtc;
    final scanDue =
        lastScan == null ||
        snapshot.generatedAt.difference(lastScan).inSeconds >=
            run.manifest.scannerIntervalSeconds;

    _manageOpenPositions(run, snapshot);
    if (scanDue) {
      _discoverCandidates(run, snapshot);
      _evaluatePendingCandidates(run, snapshot);
      run.lastScanAtUtc = snapshot.generatedAt.toUtc();
    }
    _markToMarket(run, snapshot);

    final openedThisCycle =
        math.max(0, run.openPositions.length - openedBefore) +
        math.max(0, run.closedPositions.length - closedBefore);
    if (openedThisCycle > 0) {
      run.lastWhyNoTrade =
          'A valid paper entry was admitted during cycle $cycle.';
    } else if (run.pendingCandidates.isNotEmpty) {
      run.lastWhyNoTrade = _pendingDiagnostic(run, snapshot);
    } else if (run.openPositions.length >=
        run.manifest.maximumConcurrentPositions) {
      run.lastWhyNoTrade =
          'Portfolio capacity is full (${run.openPositions.length}/${run.manifest.maximumConcurrentPositions}). Scanner is still recording candidates.';
    } else {
      final latestRejection = run.events.reversed
          .where((event) => event.kind == TradingLabEventKind.candidateRejected)
          .firstOrNull;
      run.lastWhyNoTrade =
          latestRejection?.reason ??
          'No actionable candidate was produced by the current market scan.';
    }

    run.lastSnapshotAtUtc = snapshot.generatedAt;
    _event(
      run,
      TradingLabEventKind.heartbeat,
      snapshot.generatedAt,
      run.lastWhyNoTrade,
      metrics: {
        'equity': run.currentEquity,
        'balance': run.balance,
        'virtualAvailableMargin': _virtualAvailableMargin(run),
        'reservedMargin': _reservedMargin(run),
        'openRisk': _openRisk(run),
        'portfolioRiskBudget':
            run.currentEquity * run.manifest.portfolioRiskPercent / 100,
        'portfolioRiskFree': math
            .max(
              0,
              run.currentEquity * run.manifest.portfolioRiskPercent / 100 -
                  _openRisk(run),
            )
            .toDouble(),
        'openPositions': run.openPositions.length.toDouble(),
        'freeSlots': math
            .max(
              0,
              run.manifest.maximumConcurrentPositions -
                  run.openPositions.length,
            )
            .toDouble(),
        'pendingCandidates': run.pendingCandidates.length.toDouble(),
        'closedTrades': run.closedPositions.length.toDouble(),
        'maximumDrawdownPercent': run.maximumDrawdownPercent,
        'realAccountEstimatedEquity': accountContext?.estimatedEquity ?? 0,
        'realAccountAvailable': accountContext?.available ?? 0,
        'realAccountOpenPositionCount': (accountContext?.openPositionCount ?? 0)
            .toDouble(),
        'realAccountPendingOrderCount': (accountContext?.pendingOrderCount ?? 0)
            .toDouble(),
        'snapshotGapSeconds': snapshotGapSeconds.toDouble(),
        'realAccountAgeSeconds': accountContext?.syncedAtUtc == null
            ? -1
            : math
                  .max(
                    0,
                    snapshot.generatedAt
                        .difference(accountContext!.syncedAtUtc!)
                        .inSeconds,
                  )
                  .toDouble(),
      },
      attributes: {
        'scanDue': scanDue.toString(),
        'accountConnected': (accountContext?.connected ?? false).toString(),
        'accountHealth': accountContext?.reconciliationHealth ?? 'unavailable',
        'accountBlocksNewEntries': (accountContext?.blocksNewEntries ?? true)
            .toString(),
        'marginMode': run.manifest.marginMode.name,
        'executionModel': run.manifest.executionModel.name,
      },
    );
  }

  void _discoverCandidates(TradingLabRun run, OwnerAlphaSnapshot snapshot) {
    for (final radar in snapshot.radar) {
      if (!run.manifest.symbols.contains(radar.quote.symbol.toUpperCase())) {
        continue;
      }
      for (final entry in radar.ideasByTimeframe.entries) {
        final timeframe = entry.key;
        final idea = entry.value;
        if (!run.manifest.timeframes.contains(timeframe)) continue;
        final analysis = radar.analysesByTimeframe[timeframe];
        if (analysis == null) continue;
        final signalCandle = analysis.latestCandle;
        final decisionKey = [
          idea.symbol.toUpperCase(),
          timeframe,
          idea.strategy.name,
          idea.strategyVersion,
          idea.setupId,
          idea.candleClosedAt.toUtc().toIso8601String(),
        ].join('|');
        if (run.processedDecisionKeys.contains(decisionKey)) continue;
        run.rememberDecision(decisionKey);

        final commonMetrics = <String, double>{
          'confidencePercent': idea.confidencePercent.toDouble(),
          'riskReward': idea.riskReward ?? 0,
          'lastPrice': radar.quote.lastPrice,
          'volatilityPercent': analysis.volatilityPercent,
          'directionStrength': analysis.directionStrength,
          ...idea.indicatorSnapshot,
        };
        _event(
          run,
          TradingLabEventKind.candidateObserved,
          snapshot.generatedAt,
          'Candidate observed by the production market/strategy pipeline.',
          idea: idea,
          metrics: commonMetrics,
          attributes: {
            'marketRegime': idea.marketRegime.name,
            'analysisFingerprint': analysis.fingerprint,
            'direction': idea.direction.name,
          },
        );

        if (!_isValidActionablePlan(idea)) {
          _event(
            run,
            TradingLabEventKind.candidateRejected,
            snapshot.generatedAt,
            idea.direction == TradeDirection.wait
                ? 'Strategy produced WAIT/non-actionable evidence: ${idea.rejectionReason.name}.'
                : 'Candidate plan is incomplete or has a wrong-side stop.',
            idea: idea,
            metrics: commonMetrics,
            attributes: {
              'rejectionReason': idea.direction == TradeDirection.wait
                  ? 'strategy_wait_${idea.rejectionReason.name}'
                  : idea.rejectionReason.name,
              'decisionClass': idea.direction == TradeDirection.wait
                  ? 'non_actionable_wait'
                  : 'invalid_plan',
            },
          );
          continue;
        }
        if (idea.confidencePercent < run.manifest.minimumConfidencePercent) {
          _event(
            run,
            TradingLabEventKind.candidateRejected,
            snapshot.generatedAt,
            'Actionable candidate rejected by experiment confidence gate.',
            idea: idea,
            metrics: commonMetrics,
            attributes: {'rejectionReason': 'confidence_below_gate'},
          );
          continue;
        }
        if ((idea.riskReward ?? 0) < run.manifest.minimumRiskReward) {
          _event(
            run,
            TradingLabEventKind.candidateRejected,
            snapshot.generatedAt,
            'Actionable candidate rejected by experiment minimum RR gate.',
            idea: idea,
            metrics: commonMetrics,
            attributes: {'rejectionReason': 'risk_reward_below_gate'},
          );
          continue;
        }

        final pending = TradingLabPendingCandidate(
          decisionKey: decisionKey,
          setupId: idea.setupId,
          symbol: idea.symbol.toUpperCase(),
          timeframe: idea.timeframe,
          direction: idea.direction,
          strategy: idea.strategy.name,
          strategyVersion: idea.strategyVersion,
          marketRegime: idea.marketRegime.name,
          confidencePercent: idea.confidencePercent,
          riskReward: idea.riskReward!,
          entryLower: idea.entryLower!,
          entryUpper: idea.entryUpper!,
          stopLoss: idea.stopLoss!,
          targets: idea.targets,
          recommendedLeverage: idea.recommendedLeverage ?? 1,
          maximumSafeLeverage: idea.maximumSafeLeverage ?? 1,
          observedAtUtc: snapshot.generatedAt,
          validUntilUtc: idea.validUntil.toUtc(),
          signalCandleOpenTimeUtc: signalCandle.openTime.toUtc(),
          indicatorSnapshot: idea.indicatorSnapshot,
        );
        run.pendingCandidates.add(pending);
        _event(
          run,
          TradingLabEventKind.candidatePending,
          snapshot.generatedAt,
          'Actionable candidate admitted to the paper-entry watch queue; waiting for a future candle to touch the entry zone.',
          candidate: pending,
          metrics: commonMetrics,
        );
      }
    }
  }

  void _evaluatePendingCandidates(
    TradingLabRun run,
    OwnerAlphaSnapshot snapshot,
  ) {
    final remove = <TradingLabPendingCandidate>[];
    for (final candidate in List<TradingLabPendingCandidate>.of(
      run.pendingCandidates,
    )) {
      final currentIdea = _currentIdeaFor(snapshot, candidate);
      if (currentIdea != null &&
          (currentIdea.direction == TradeDirection.wait ||
              currentIdea.setupId != candidate.setupId ||
              currentIdea.strategy.name != candidate.strategy ||
              currentIdea.strategyVersion != candidate.strategyVersion)) {
        remove.add(candidate);
        _event(
          run,
          TradingLabEventKind.candidateRejected,
          snapshot.generatedAt,
          currentIdea.direction == TradeDirection.wait
              ? 'Pending candidate invalidated because the current strategy state is WAIT.'
              : 'Pending candidate superseded by a newer setup for the same symbol/timeframe.',
          candidate: candidate,
          attributes: {
            'rejectionReason': currentIdea.direction == TradeDirection.wait
                ? 'setup_invalidated'
                : 'setup_superseded',
          },
        );
        continue;
      }
      if (!snapshot.generatedAt.isBefore(candidate.validUntilUtc)) {
        remove.add(candidate);
        _event(
          run,
          TradingLabEventKind.candidateRejected,
          snapshot.generatedAt,
          'Pending candidate expired before a valid paper entry.',
          candidate: candidate,
          attributes: {'rejectionReason': 'expired_untriggered'},
        );
        continue;
      }
      final analysis = _analysisFor(
        snapshot,
        candidate.symbol,
        candidate.timeframe,
      );
      if (analysis == null) continue;
      final entryCandle = analysis.candles
          .where(
            (candle) =>
                candle.openTime.isAfter(candidate.signalCandleOpenTimeUtc) &&
                !candle.openTime.isBefore(candidate.observedAtUtc),
          )
          .where((candle) => _touchesEntry(candidate, candle))
          .firstOrNull;
      if (entryCandle == null) continue;

      final block = _entryBlockReason(run, candidate);
      if (block != null) {
        _event(
          run,
          TradingLabEventKind.candidateRejected,
          snapshot.generatedAt,
          block,
          candidate: candidate,
          attributes: {'rejectionReason': _reasonCode(block)},
        );
        continue;
      }

      final opened = _openPosition(
        run,
        candidate,
        entryCandle,
        entryCandle.openTime.toUtc(),
      );
      if (opened) {
        remove.add(candidate);
      }
    }
    run.pendingCandidates.removeWhere(remove.contains);
  }

  TradeIdea? _currentIdeaFor(
    OwnerAlphaSnapshot snapshot,
    TradingLabPendingCandidate candidate,
  ) {
    for (final radar in snapshot.radar) {
      if (radar.quote.symbol.toUpperCase() != candidate.symbol) continue;
      return radar.ideasByTimeframe[candidate.timeframe];
    }
    return null;
  }

  bool _openPosition(
    TradingLabRun run,
    TradingLabPendingCandidate candidate,
    ChartCandle entryCandle,
    DateTime now,
  ) {
    final referenceEntry = (candidate.entryLower + candidate.entryUpper) / 2;
    final afterSpread = _applyAdverseSlippage(
      referenceEntry,
      direction: candidate.direction,
      opening: true,
      bps: run.manifest.spreadBps / 2,
    );
    final entry = _applyAdverseSlippage(
      afterSpread,
      direction: candidate.direction,
      opening: true,
      bps: run.manifest.slippageBps,
    );
    final stopDistance = (entry - candidate.stopLoss).abs();
    if (stopDistance <= 0 || !stopDistance.isFinite) return false;
    final riskBudget = run.currentEquity * run.manifest.riskPercent / 100;
    final quantity = riskBudget / stopDistance;
    if (!quantity.isFinite || quantity <= 0) return false;

    final maxSafe = math.max(1, candidate.maximumSafeLeverage);
    final leverage = math.min(run.manifest.leverage, maxSafe);
    final notional = entry * quantity;
    final margin = notional / leverage;
    final availableMargin = math
        .max(
          0,
          run.currentEquity -
              run.openPositions.fold<double>(
                0,
                (sum, item) => sum + item.marginReserved,
              ),
        )
        .toDouble();
    if (margin > availableMargin + 0.0000001) {
      _event(
        run,
        TradingLabEventKind.candidateRejected,
        now,
        'Paper entry blocked: insufficient virtual available margin.',
        candidate: candidate,
        metrics: {'requiredMargin': margin, 'availableMargin': availableMargin},
        attributes: {'rejectionReason': 'insufficient_virtual_margin'},
      );
      return false;
    }

    final fractions = _fractionsForTargets(candidate.targets.length);
    final entryFee = _fee(notional, run.manifest.feeRateBps);
    final spreadCost = (afterSpread - referenceEntry).abs() * quantity;
    final slippageCost = (entry - afterSpread).abs() * quantity;
    final estimatedExitFee = _fee(notional, run.manifest.feeRateBps);
    final estimatedExitExecutionCost =
        notional *
        (run.manifest.spreadBps / 2 + run.manifest.slippageBps) /
        10000;
    final estimatedRoundTripExecutionCost =
        entryFee +
        estimatedExitFee +
        spreadCost +
        slippageCost +
        estimatedExitExecutionCost;
    final executionCostToRiskPercent =
        estimatedRoundTripExecutionCost / riskBudget * 100;
    if (executionCostToRiskPercent >
        run.manifest.maxEstimatedCostToRiskPercent) {
      _event(
        run,
        TradingLabEventKind.candidateRejected,
        now,
        'Paper entry blocked: estimated execution costs consume too much of the configured risk budget.',
        candidate: candidate,
        metrics: {
          'estimatedRoundTripExecutionCost': estimatedRoundTripExecutionCost,
          'riskBudget': riskBudget,
          'executionCostToRiskPercent': executionCostToRiskPercent,
          'maximumExecutionCostToRiskPercent':
              run.manifest.maxEstimatedCostToRiskPercent,
        },
        attributes: {'rejectionReason': 'execution_cost_to_risk_too_high'},
      );
      return false;
    }
    run.balance -= entryFee;
    final position = TradingLabPosition(
      positionId:
          '${run.manifest.runId}-p${run.closedPositions.length + run.openPositions.length + 1}',
      decisionKey: candidate.decisionKey,
      setupId: candidate.setupId,
      symbol: candidate.symbol,
      timeframe: candidate.timeframe,
      direction: candidate.direction,
      strategy: candidate.strategy,
      strategyVersion: candidate.strategyVersion,
      marketRegime: candidate.marketRegime,
      confidencePercent: candidate.confidencePercent,
      riskReward: candidate.riskReward,
      entryPrice: entry,
      originalStopLoss: candidate.stopLoss,
      currentStopLoss: candidate.stopLoss,
      targets: candidate.targets,
      targetFractions: fractions,
      initialQuantity: quantity,
      remainingQuantity: quantity,
      leverage: leverage,
      openedAtUtc: now,
      lastEvaluatedCandleAtUtc: entryCandle.openTime.toUtc(),
      marginReserved: margin,
      entryFee: entryFee,
      slippageCost: slippageCost,
      spreadCost: spreadCost,
      maximumFavorablePrice: entry,
      maximumAdversePrice: entry,
    );
    run.openPositions.add(position);
    _event(
      run,
      TradingLabEventKind.positionOpened,
      now,
      'Paper position opened after a future candle touched the strategy entry zone.',
      candidate: candidate,
      metrics: {
        'entryPrice': entry,
        'referenceEntry': referenceEntry,
        'stopLoss': candidate.stopLoss,
        'quantity': quantity,
        'initialRisk': position.initialRisk,
        'marginReserved': margin,
        'leverage': leverage.toDouble(),
        'entryFee': entryFee,
        'slippageCost': slippageCost,
        'spreadCost': spreadCost,
        'portfolioRiskAfter': _openRisk(run),
        'portfolioRiskBudget':
            run.currentEquity * run.manifest.portfolioRiskPercent / 100,
      },
      attributes: {'executionModel': run.manifest.executionModel.name},
    );
    return true;
  }

  void _manageOpenPositions(TradingLabRun run, OwnerAlphaSnapshot snapshot) {
    for (final position in List<TradingLabPosition>.of(run.openPositions)) {
      final analysis = _analysisFor(
        snapshot,
        position.symbol,
        position.timeframe,
      );
      if (analysis == null) continue;
      _accrueFunding(run, position, snapshot.generatedAt.toUtc());
      final newCandles = analysis.candles
          .where(
            (candle) =>
                candle.openTime.isAfter(position.lastEvaluatedCandleAtUtc) &&
                !candle.openTime.isBefore(position.openedAtUtc),
          )
          .toList(growable: false);
      for (final candle in newCandles) {
        if (!position.isOpen) break;
        _updateExcursions(position, candle);
        _processPositionCandle(run, position, candle);
        position.lastEvaluatedCandleAtUtc = candle.openTime.toUtc();
      }
      if (position.isOpen) {
        _updateExcursions(position, analysis.latestCandle);
      }
    }
  }

  void _processPositionCandle(
    TradingLabRun run,
    TradingLabPosition position,
    ChartCandle candle,
  ) {
    final stopHit = _stopHit(position, candle);
    final anyTargetHit =
        List.generate(position.targets.length, (index) => index)
            .where((index) => !position.filledTargetIndexes.contains(index))
            .any(
              (index) => _targetHit(position, position.targets[index], candle),
            );

    // Deliberately pessimistic when OHLC cannot prove intrabar ordering.
    if (stopHit && anyTargetHit) {
      _closeRemainingAtStop(
        run,
        position,
        candle.openTime.toUtc(),
        reason:
            'Conservative OHLC collision: stop and target were both touched; stop assumed first.',
      );
      return;
    }
    if (stopHit) {
      _closeRemainingAtStop(
        run,
        position,
        candle.openTime.toUtc(),
        reason: 'Paper protective stop touched.',
      );
      return;
    }

    for (var index = 0; index < position.targets.length; index++) {
      if (!position.isOpen || position.filledTargetIndexes.contains(index)) {
        continue;
      }
      final target = position.targets[index];
      if (!_targetHit(position, target, candle)) continue;
      final isLast = index == position.targets.length - 1;
      final planned =
          position.initialQuantity * position.targetFractions[index];
      final quantity = isLast
          ? position.remainingQuantity
          : math.min(position.remainingQuantity, planned);
      if (quantity <= 0) continue;
      final spreadExit = _applyAdverseSlippage(
        target,
        direction: position.direction,
        opening: false,
        bps: run.manifest.spreadBps / 2,
      );
      final exit = _applyAdverseSlippage(
        spreadExit,
        direction: position.direction,
        opening: false,
        bps: run.manifest.slippageBps,
      );
      position.spreadCost += (spreadExit - target).abs() * quantity;
      position.slippageCost += (exit - spreadExit).abs() * quantity;
      _realize(run, position, quantity, exit);
      position.filledTargetIndexes.add(index);
      _event(
        run,
        TradingLabEventKind.targetFilled,
        candle.openTime.toUtc(),
        'Paper target ${index + 1} filled.',
        position: position,
        metrics: {
          'targetIndex': (index + 1).toDouble(),
          'targetPrice': target,
          'executionPrice': exit,
          'filledQuantity': quantity,
          'remainingQuantity': position.remainingQuantity,
        },
      );
      _promoteStopAfterTarget(run, position, index, candle.openTime.toUtc());
      if (position.remainingQuantity <= 0.0000000001) {
        _finalizeClosed(
          run,
          position,
          candle.openTime.toUtc(),
          'All active paper targets filled.',
        );
        return;
      }
    }
  }

  void _promoteStopAfterTarget(
    TradingLabRun run,
    TradingLabPosition position,
    int targetIndex,
    DateTime at,
  ) {
    ProfitLockStopDecision? decision;
    if (targetIndex == 0) {
      decision = ProfitLockStopPolicy.afterTp1(
        direction: position.direction,
        entryPrice: position.entryPrice,
        currentConfirmedStop: position.currentStopLoss,
        costBufferRate: 0.0017,
        pricePrecision: 8,
      );
    } else if (targetIndex == 1 && position.targets.isNotEmpty) {
      decision = ProfitLockStopPolicy.afterTp2(
        direction: position.direction,
        tp1Price: position.targets.first,
        currentConfirmedStop: position.currentStopLoss,
        pricePrecision: 8,
      );
    }
    if (decision == null || !decision.requiresMutation) return;
    position.currentStopLoss = decision.proposedStop;
    _event(
      run,
      TradingLabEventKind.stopPromoted,
      at,
      decision.reason,
      position: position,
      metrics: {'newStopLoss': decision.proposedStop},
    );
  }

  void _closeRemainingAtStop(
    TradingLabRun run,
    TradingLabPosition position,
    DateTime at, {
    required String reason,
  }) {
    final quantity = position.remainingQuantity;
    if (quantity <= 0) return;
    final spreadExit = _applyAdverseSlippage(
      position.currentStopLoss,
      direction: position.direction,
      opening: false,
      bps: run.manifest.spreadBps / 2,
    );
    final exit = _applyAdverseSlippage(
      spreadExit,
      direction: position.direction,
      opening: false,
      bps: run.manifest.slippageBps,
    );
    position.spreadCost +=
        (spreadExit - position.currentStopLoss).abs() * quantity;
    position.slippageCost += (exit - spreadExit).abs() * quantity;
    _realize(run, position, quantity, exit);
    _event(
      run,
      TradingLabEventKind.stopFilled,
      at,
      reason,
      position: position,
      metrics: {
        'stopPrice': position.currentStopLoss,
        'executionPrice': exit,
        'filledQuantity': quantity,
      },
    );
    _finalizeClosed(run, position, at, reason);
  }

  void _realize(
    TradingLabRun run,
    TradingLabPosition position,
    double quantity,
    double exit,
  ) {
    final gross = position.direction == TradeDirection.long
        ? (exit - position.entryPrice) * quantity
        : (position.entryPrice - exit) * quantity;
    final exitFee = _fee(exit * quantity, run.manifest.feeRateBps);
    position.realizedGrossPnl += gross;
    position.exitFees += exitFee;
    position.remainingQuantity = math.max(
      0,
      position.remainingQuantity - quantity,
    );
    run.balance += gross - exitFee;
  }

  void _finalizeClosed(
    TradingLabRun run,
    TradingLabPosition position,
    DateTime at,
    String reason,
  ) {
    if (!run.openPositions.contains(position)) return;
    position.closedAtUtc = at;
    position.closeReason = reason;
    position.remainingQuantity = 0;
    run.openPositions.remove(position);
    run.closedPositions.add(position);
    _event(
      run,
      TradingLabEventKind.positionClosed,
      at,
      reason,
      position: position,
      metrics: {
        'netPnl': position.netRealizedPnl,
        'realizedR': position.realizedR,
        'entryFee': position.entryFee,
        'exitFees': position.exitFees,
        'funding': position.funding,
        'slippageCost': position.slippageCost,
        'spreadCost': position.spreadCost,
      },
    );
  }

  void _markToMarket(TradingLabRun run, OwnerAlphaSnapshot snapshot) {
    var unrealized = 0.0;
    for (final position in run.openPositions) {
      final quote = snapshot.radar
          .where((item) => item.quote.symbol == position.symbol)
          .firstOrNull
          ?.quote;
      if (quote == null) continue;
      final mark = quote.lastPrice;
      unrealized += position.direction == TradeDirection.long
          ? (mark - position.entryPrice) * position.remainingQuantity
          : (position.entryPrice - mark) * position.remainingQuantity;
    }
    run.currentEquity = math.max(0, run.balance + unrealized).toDouble();
    if (run.currentEquity > run.peakEquity) run.peakEquity = run.currentEquity;
    final drawdown =
        (run.peakEquity <= 0
                ? 0
                : (run.peakEquity - run.currentEquity) / run.peakEquity * 100)
            .toDouble();
    if (drawdown > run.maximumDrawdownPercent) {
      run.maximumDrawdownPercent = drawdown;
    }
  }

  String? _entryBlockReason(
    TradingLabRun run,
    TradingLabPendingCandidate candidate,
  ) {
    if (run.openPositions.length >= run.manifest.maximumConcurrentPositions) {
      return 'Paper entry blocked: portfolio slots are full.';
    }
    if (run.openPositions.any(
      (position) => position.symbol == candidate.symbol,
    )) {
      return 'Paper entry blocked: same-symbol exposure already exists.';
    }
    final entry = (candidate.entryLower + candidate.entryUpper) / 2;
    final stopDistance = (entry - candidate.stopLoss).abs();
    if (stopDistance <= 0) return 'Paper entry blocked: invalid stop distance.';
    final candidateRisk = run.currentEquity * run.manifest.riskPercent / 100;
    final riskCap = run.currentEquity * run.manifest.portfolioRiskPercent / 100;
    final symbolHeatCap =
        run.currentEquity * run.manifest.symbolHeatPercent / 100;
    final openRisk = _openRisk(run);
    final symbolRisk = run.openPositions
        .where((position) => position.symbol == candidate.symbol)
        .fold<double>(
          0,
          (sum, position) =>
              sum +
              position.initialRisk *
                  (position.remainingQuantity / position.initialQuantity),
        );
    if (candidateRisk > symbolHeatCap + 0.0000001 ||
        symbolRisk + candidateRisk > symbolHeatCap + 0.0000001) {
      return 'Paper entry blocked: symbol heat budget is exhausted.';
    }
    if (openRisk + candidateRisk > riskCap + 0.0000001) {
      return 'Paper entry blocked: portfolio risk budget is exhausted.';
    }
    return null;
  }

  static double _reservedMargin(TradingLabRun run) => run.openPositions
      .fold<double>(0, (sum, position) => sum + position.marginReserved);

  static double _virtualAvailableMargin(TradingLabRun run) =>
      math.max(0, run.currentEquity - _reservedMargin(run)).toDouble();

  static double _openRisk(TradingLabRun run) => run.openPositions.fold<double>(
    0,
    (sum, position) =>
        sum +
        position.initialRisk *
            (position.remainingQuantity / position.initialQuantity),
  );

  void _accrueFunding(
    TradingLabRun run,
    TradingLabPosition position,
    DateTime now,
  ) {
    if (!now.isAfter(position.lastFundingAccrualAtUtc)) return;
    final elapsedSeconds = now
        .difference(position.lastFundingAccrualAtUtc)
        .inSeconds;
    if (elapsedSeconds <= 0) return;
    final rate = run.manifest.fundingRatePerEightHours;
    position.lastFundingAccrualAtUtc = now;
    if (rate == 0 || position.remainingQuantity <= 0) return;
    final intervals = elapsedSeconds / const Duration(hours: 8).inSeconds;
    final notional = position.entryPrice * position.remainingQuantity;
    final directionalRate = position.direction == TradeDirection.long
        ? rate
        : -rate;
    final charge = notional * directionalRate * intervals;
    if (!charge.isFinite || charge == 0) return;
    position.funding += charge;
    run.balance -= charge;
    _event(
      run,
      TradingLabEventKind.fundingAccrued,
      now,
      'Paper funding accrued using the configured eight-hour rate.',
      position: position,
      metrics: {
        'fundingCharge': charge,
        'fundingRatePerEightHours': rate,
        'elapsedSeconds': elapsedSeconds.toDouble(),
        'remainingNotional': notional,
      },
    );
  }

  static bool _isValidActionablePlan(TradeIdea idea) {
    if (!idea.isActionable ||
        idea.entryLower == null ||
        idea.entryUpper == null ||
        idea.stopLoss == null ||
        idea.riskReward == null ||
        idea.targets.isEmpty) {
      return false;
    }
    final entry = (idea.entryLower! + idea.entryUpper!) / 2;
    return idea.direction == TradeDirection.long
        ? idea.stopLoss! < entry
        : idea.stopLoss! > entry;
  }

  static bool _touchesEntry(
    TradingLabPendingCandidate candidate,
    ChartCandle candle,
  ) =>
      candle.high >= candidate.entryLower && candle.low <= candidate.entryUpper;

  static bool _stopHit(TradingLabPosition position, ChartCandle candle) =>
      position.direction == TradeDirection.long
      ? candle.low <= position.currentStopLoss
      : candle.high >= position.currentStopLoss;

  static bool _targetHit(
    TradingLabPosition position,
    double target,
    ChartCandle candle,
  ) => position.direction == TradeDirection.long
      ? candle.high >= target
      : candle.low <= target;

  static void _updateExcursions(
    TradingLabPosition position,
    ChartCandle candle,
  ) {
    if (position.direction == TradeDirection.long) {
      position.maximumFavorablePrice = math.max(
        position.maximumFavorablePrice ?? position.entryPrice,
        candle.high,
      );
      position.maximumAdversePrice = math.min(
        position.maximumAdversePrice ?? position.entryPrice,
        candle.low,
      );
    } else {
      position.maximumFavorablePrice = math.min(
        position.maximumFavorablePrice ?? position.entryPrice,
        candle.low,
      );
      position.maximumAdversePrice = math.max(
        position.maximumAdversePrice ?? position.entryPrice,
        candle.high,
      );
    }
  }

  static TimeframeChartAnalysis? _analysisFor(
    OwnerAlphaSnapshot snapshot,
    String symbol,
    String timeframe,
  ) {
    final radar = snapshot.radar
        .where((item) => item.quote.symbol == symbol)
        .firstOrNull;
    return radar?.analysesByTimeframe[timeframe];
  }

  static List<double> _fractionsForTargets(int count) {
    if (count <= 0) return const [];
    final standard = ProfitProtectionTargetAllocation.standard.fractions;
    final raw = standard
        .take(math.min(count, standard.length))
        .toList(growable: false);
    if (count > standard.length) {
      final equal = 1 / count;
      return List<double>.filled(count, equal, growable: false);
    }
    final total = raw.fold<double>(0, (sum, item) => sum + item);
    return raw.map((item) => item / total).toList(growable: false);
  }

  static double _fee(double notional, double bps) =>
      notional.abs() * bps / 10000;

  static double _applyAdverseSlippage(
    double price, {
    required TradeDirection direction,
    required bool opening,
    required double bps,
  }) {
    final rate = bps / 10000;
    final buying = opening
        ? direction == TradeDirection.long
        : direction == TradeDirection.short;
    return price * (buying ? 1 + rate : 1 - rate);
  }

  static String _reasonCode(String reason) {
    final value = reason.toLowerCase();
    if (value.contains('slots')) return 'portfolio_slots_full';
    if (value.contains('same-symbol')) return 'same_symbol_exposure';
    if (value.contains('symbol heat')) return 'symbol_heat_exhausted';
    if (value.contains('symbol heat')) return 'symbol_heat_exhausted';
    if (value.contains('risk budget')) return 'portfolio_risk_exhausted';
    if (value.contains('margin')) return 'insufficient_virtual_margin';
    if (value.contains('stop')) return 'invalid_stop';
    return 'paper_admission_blocked';
  }

  static String _pendingDiagnostic(
    TradingLabRun run,
    OwnerAlphaSnapshot snapshot,
  ) {
    final candidate = run.pendingCandidates.first;
    if (run.openPositions.length >= run.manifest.maximumConcurrentPositions) {
      return 'Scanner active; ${run.pendingCandidates.length} candidate(s) pending, but portfolio capacity is full (all slots occupied).';
    }
    final analysis = _analysisFor(
      snapshot,
      candidate.symbol,
      candidate.timeframe,
    );
    if (analysis == null) {
      return 'Scanner active; pending candidate exists but its chart context is not present in the latest snapshot.';
    }
    return 'Scanner active; ${run.pendingCandidates.length} candidate(s) are waiting for a future candle to touch their entry zone.';
  }

  static void _event(
    TradingLabRun run,
    TradingLabEventKind kind,
    DateTime at,
    String reason, {
    TradeIdea? idea,
    TradingLabPendingCandidate? candidate,
    TradingLabPosition? position,
    Map<String, double> metrics = const {},
    Map<String, String> attributes = const {},
  }) {
    run.appendEvent(
      TradingLabEvent(
        eventId:
            '${run.manifest.runId}:${run.cycleId}:${run.events.length + 1}',
        atUtc: at.toUtc(),
        kind: kind,
        cycleId: run.cycleId,
        reason: reason,
        setupId: position?.setupId ?? candidate?.setupId ?? idea?.setupId,
        symbol: position?.symbol ?? candidate?.symbol ?? idea?.symbol,
        timeframe:
            position?.timeframe ?? candidate?.timeframe ?? idea?.timeframe,
        strategy:
            position?.strategy ?? candidate?.strategy ?? idea?.strategy.name,
        strategyVersion:
            position?.strategyVersion ??
            candidate?.strategyVersion ??
            idea?.strategyVersion,
        metrics: metrics,
        attributes: attributes,
      ),
    );
  }
}
