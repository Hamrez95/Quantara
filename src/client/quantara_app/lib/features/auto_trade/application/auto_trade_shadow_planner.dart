import 'dart:math' as math;

import '../domain/auto_trade_execution_models.dart';

abstract final class AutoTradeShadowPlanner {
  static const _maximumAccountAge = Duration(seconds: 45);

  static AutoTradePlanningResult create({
    required AutoTradeSignalCandidate candidate,
    required AutoTradePlanningContext context,
  }) {
    final rejections = <AutoTradeRejectionCode>[];
    final now = context.now.toUtc();
    final limits = context.limits;
    final account = context.account;
    final instrument = context.instrument;

    switch (context.mode) {
      case AutoTradeOperatingMode.shadow:
      case AutoTradeOperatingMode.manualApproval:
        break;
      case AutoTradeOperatingMode.paused:
      case AutoTradeOperatingMode.circuitBreaker:
        rejections.add(AutoTradeRejectionCode.circuitBreaker);
      case AutoTradeOperatingMode.readOnly:
      case AutoTradeOperatingMode.liveCanary:
      case AutoTradeOperatingMode.restrictedAuto:
        rejections.add(AutoTradeRejectionCode.unsupportedMode);
    }

    if (!context.privateStreamHealthy) {
      rejections.add(AutoTradeRejectionCode.unhealthyPrivateStream);
    }
    if (now.difference(account.syncedAt.toUtc()) > _maximumAccountAge) {
      rejections.add(AutoTradeRejectionCode.staleAccount);
    }
    if (now.difference(candidate.marketDataAt.toUtc()) > limits.maximumSignalAge ||
        now.difference(candidate.createdAt.toUtc()) > limits.maximumSignalAge) {
      rejections.add(AutoTradeRejectionCode.staleSignal);
    }
    if (!now.isBefore(candidate.validUntil.toUtc())) {
      rejections.add(AutoTradeRejectionCode.expiredSignal);
    }
    if (!limits.allowedSymbols.contains(candidate.symbol)) {
      rejections.add(AutoTradeRejectionCode.symbolDisabled);
    }
    if (!limits.allowedTimeframes.contains(candidate.timeframe)) {
      rejections.add(AutoTradeRejectionCode.timeframeDisabled);
    }
    if (!limits.allowedStrategies.contains(candidate.strategyVersion)) {
      rejections.add(AutoTradeRejectionCode.strategyDisabled);
    }
    if (!candidate.primarySetup) {
      rejections.add(AutoTradeRejectionCode.notPrimarySetup);
    }
    if (candidate.timeframeConflict) {
      rejections.add(AutoTradeRejectionCode.timeframeConflict);
    }
    if (context.currentDailyLossPercent >= limits.maximumDailyLossPercent) {
      rejections.add(AutoTradeRejectionCode.dailyLossLimit);
    }
    if (!instrument.tradable || instrument.symbol != candidate.symbol) {
      rejections.add(AutoTradeRejectionCode.symbolClosed);
    }
    if (!instrument.apiTradingSupported) {
      rejections.add(AutoTradeRejectionCode.apiTradingUnsupported);
    }
    if (candidate.estimatedSlippageBps > limits.maximumSlippageBps) {
      rejections.add(AutoTradeRejectionCode.excessiveSlippage);
    }

    final activePositionSymbols = account.positions
        .where((position) => position.quantity.abs() > 0)
        .map((position) => position.symbol)
        .toSet();
    final activeOrderSymbols = account.orders
        .where((order) => !order.reduceOnly)
        .map((order) => order.symbol)
        .toSet();
    if (activePositionSymbols.contains(candidate.symbol) ||
        activeOrderSymbols.contains(candidate.symbol)) {
      rejections.add(AutoTradeRejectionCode.existingExposure);
    }
    if (activePositionSymbols.length >= limits.maximumConcurrentPositions) {
      rejections.add(AutoTradeRejectionCode.tooManyPositions);
    }

    if (!_validPrices(candidate)) {
      rejections.add(AutoTradeRejectionCode.invalidPrices);
    }
    if (!limits.riskPercent.isFinite ||
        limits.riskPercent <= 0 ||
        limits.riskPercent > 2 ||
        account.estimatedEquity <= 0) {
      rejections.add(AutoTradeRejectionCode.invalidRisk);
    }
    if (rejections.isNotEmpty) {
      return AutoTradePlanningResult.rejected(rejections);
    }

    final leverage = limits.defaultLeverage
        .clamp(1, instrument.maximumLeverage)
        .toInt();
    final entryPrice = _roundToIncrement(candidate.entryPrice, instrument.tickSize);
    final stopLoss = _roundToIncrement(candidate.stopLoss, instrument.tickSize);
    final targets = candidate.targets
        .map((target) => _roundToIncrement(target, instrument.tickSize))
        .toList(growable: false);
    final stopDistance = (entryPrice - stopLoss).abs();
    final feePerUnit = entryPrice * candidate.estimatedRoundTripFeeRate;
    final slippagePerUnit =
        entryPrice * candidate.estimatedSlippageBps / 10000;
    final riskPerUnit = stopDistance + feePerUnit + slippagePerUnit;
    final riskBudget = account.estimatedEquity * limits.riskPercent / 100;
    if (!riskPerUnit.isFinite || riskPerUnit <= 0 || riskBudget <= 0) {
      return AutoTradePlanningResult.rejected(const [
        AutoTradeRejectionCode.invalidRisk,
      ]);
    }

    final rawQuantity = riskBudget / riskPerUnit;
    if (rawQuantity > instrument.maximumQuantity) {
      return AutoTradePlanningResult.rejected(const [
        AutoTradeRejectionCode.quantityAboveMaximum,
      ]);
    }
    final quantity = _floorToIncrement(rawQuantity, instrument.stepSize);
    if (quantity < instrument.minimumQuantity || quantity <= 0) {
      return AutoTradePlanningResult.rejected(const [
        AutoTradeRejectionCode.quantityBelowMinimum,
      ]);
    }

    final notional = quantity * entryPrice;
    final requiredMargin = notional / leverage;
    final requiredWithBuffer =
        requiredMargin * (1 + limits.marginBufferPercent / 100);
    if (requiredWithBuffer > account.available) {
      return AutoTradePlanningResult.rejected(const [
        AutoTradeRejectionCode.insufficientAvailableMargin,
      ]);
    }
    final projectedMarginUsage =
        (account.positionMargin + requiredMargin) /
        account.estimatedEquity *
        100;
    if (projectedMarginUsage > limits.maximumMarginUsagePercent) {
      return AutoTradePlanningResult.rejected(const [
        AutoTradeRejectionCode.totalMarginLimit,
      ]);
    }

    final estimatedFees = quantity * feePerUnit;
    final estimatedSlippage = quantity * slippagePerUnit;
    final maximumLoss = quantity * riskPerUnit;
    final status = context.mode == AutoTradeOperatingMode.manualApproval
        ? AutoTradePlanStatus.awaitingApproval
        : AutoTradePlanStatus.shadow;

    return AutoTradePlanningResult.accepted(
      AutoTradeOrderPlan(
        clientId: _clientId(candidate),
        setupId: candidate.setupId,
        status: status,
        symbol: candidate.symbol,
        direction: candidate.direction,
        leverage: leverage,
        quantity: quantity,
        entryPrice: entryPrice,
        stopLoss: stopLoss,
        targets: List.unmodifiable(targets),
        riskBudget: riskBudget,
        riskPerUnit: riskPerUnit,
        notional: notional,
        requiredMargin: requiredMargin,
        maximumLoss: maximumLoss,
        estimatedFees: estimatedFees,
        estimatedSlippage: estimatedSlippage,
        createdAt: now,
        expiresAt: candidate.validUntil.toUtc(),
      ),
    );
  }

  static bool _validPrices(AutoTradeSignalCandidate candidate) {
    if (!candidate.entryPrice.isFinite ||
        !candidate.stopLoss.isFinite ||
        candidate.entryPrice <= 0 ||
        candidate.stopLoss <= 0 ||
        candidate.targets.isEmpty ||
        candidate.targets.any((target) => !target.isFinite || target <= 0)) {
      return false;
    }
    return switch (candidate.direction) {
      AutoTradeDirection.long =>
        candidate.stopLoss < candidate.entryPrice &&
            candidate.targets.every((target) => target > candidate.entryPrice),
      AutoTradeDirection.short =>
        candidate.stopLoss > candidate.entryPrice &&
            candidate.targets.every((target) => target < candidate.entryPrice),
    };
  }

  static double _roundToIncrement(double value, double increment) {
    if (!increment.isFinite || increment <= 0) return value;
    return (value / increment).round() * increment;
  }

  static double _floorToIncrement(double value, double increment) {
    if (!increment.isFinite || increment <= 0) return value;
    return math.max(0, (value / increment).floor() * increment);
  }

  static String _clientId(AutoTradeSignalCandidate candidate) {
    final input = [
      candidate.setupId,
      candidate.symbol,
      candidate.direction.name,
      candidate.entryPrice.toStringAsFixed(8),
      candidate.stopLoss.toStringAsFixed(8),
    ].join('|');
    var hash = 0x811c9dc5;
    for (final unit in input.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return 'q-${hash.toRadixString(16).padLeft(8, '0')}';
  }
}
