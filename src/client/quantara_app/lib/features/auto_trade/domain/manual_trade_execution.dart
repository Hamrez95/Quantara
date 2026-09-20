import 'dart:math' as math;

import '../../owner_alpha/domain/owner_alpha_models.dart';
import '../../owner_alpha/domain/profit_protection_policy.dart';
import 'auto_trade_models.dart';

enum ManualTradePlanBlockReason {
  none,
  setupNotExecutable,
  setupExpired,
  missingEntry,
  marketOutsideEntryZone,
  invalidStop,
  insufficientTargets,
  staleAccount,
  accountUnavailable,
  existingExposureUnprotected,
  duplicateSymbolExposure,
  marketClosed,
  apiUnsupported,
  invalidInstrumentRules,
  invalidLeverage,
  invalidMargin,
  insufficientMargin,
  quantityTooSmall,
  quantityTooLarge,
  hardRiskExceeded,
  invalidTargetAllocation,
}

final class ManualTradeInstrumentRules {
  const ManualTradeInstrumentRules({
    required this.symbol,
    required this.minimumQuantity,
    required this.maximumMarketQuantity,
    required this.quantityPrecision,
    required this.pricePrecision,
    required this.minimumLeverage,
    required this.maximumLeverage,
    required this.open,
    required this.apiSupported,
  });

  final String symbol;
  final double minimumQuantity;
  final double maximumMarketQuantity;
  final int quantityPrecision;
  final int pricePrecision;
  final int minimumLeverage;
  final int maximumLeverage;
  final bool open;
  final bool apiSupported;

  bool get valid =>
      symbol.trim().isNotEmpty &&
      minimumQuantity.isFinite &&
      minimumQuantity > 0 &&
      maximumMarketQuantity.isFinite &&
      maximumMarketQuantity >= minimumQuantity &&
      quantityPrecision >= 0 &&
      quantityPrecision <= 12 &&
      pricePrecision >= 0 &&
      pricePrecision <= 12 &&
      minimumLeverage >= 1 &&
      maximumLeverage >= minimumLeverage;

  double roundQuantityDown(double value) {
    final factor = math.pow(10, quantityPrecision).toDouble();
    return (value * factor).floor() / factor;
  }

  double roundPrice(double value) {
    final factor = math.pow(10, pricePrecision).toDouble();
    return (value * factor).round() / factor;
  }
}

final class ManualTradePlan {
  const ManualTradePlan({
    required this.policyVersion,
    required this.setupId,
    required this.symbol,
    required this.direction,
    required this.systemSuggested,
    required this.margin,
    required this.leverage,
    required this.notional,
    required this.quantity,
    required this.entryPrice,
    required this.stopLoss,
    required this.targets,
    required this.targetQuantities,
    required this.targetAllocation,
    required this.maximumLoss,
    required this.riskPercentOfEquity,
    required this.estimatedCosts,
    required this.availableMarginBefore,
    required this.remainingAvailableMargin,
    required this.hardRiskCap,
    required this.maximumPermittedMargin,
    required this.maximumPermittedLeverage,
    required this.qualityScore,
    required this.qualityRiskMultiplier,
    required this.blockReason,
    required this.explanation,
  });

  final String policyVersion;
  final String setupId;
  final String symbol;
  final TradeDirection direction;
  final bool systemSuggested;
  final double margin;
  final int leverage;
  final double notional;
  final double quantity;
  final double entryPrice;
  final double stopLoss;
  final List<double> targets;
  final List<double> targetQuantities;
  final ProfitProtectionTargetAllocation targetAllocation;
  final double maximumLoss;
  final double riskPercentOfEquity;
  final double estimatedCosts;
  final double availableMarginBefore;
  final double remainingAvailableMargin;
  final double hardRiskCap;
  final double maximumPermittedMargin;
  final int maximumPermittedLeverage;
  final int qualityScore;
  final double qualityRiskMultiplier;
  final ManualTradePlanBlockReason blockReason;
  final String explanation;

  bool get allowed => blockReason == ManualTradePlanBlockReason.none;
  int get targetCount => targets.length;
}

abstract final class ManualTradeSizingPolicy {
  static const version = 'manual-trade-sizing/1.0';
  static const accountFreshness = Duration(seconds: 45);
  static const maximumMarginFractionOfEquity = 0.20;
  static const maximumRiskFractionOfEquity = 0.02;
  static const entryZoneToleranceFraction = 0.0015;
  static const fallbackRoundTripCostRate = 0.0023;

  static ManualTradePlan propose({
    required SignalJournalEntry setup,
    required AutoTradeAccountSnapshot account,
    required ManualTradeInstrumentRules rules,
    required double markPrice,
    required DateTime nowUtc,
    int targetCount = 3,
  }) {
    final quality = _qualityScore(setup);
    final multiplier = _qualityMultiplier(quality);
    final leverage = setup.recommendedLeverage
        .clamp(
          rules.minimumLeverage,
          math.min(setup.maximumSafeLeverage, rules.maximumLeverage),
        )
        .toInt();
    return _build(
      setup: setup,
      account: account,
      rules: rules,
      markPrice: markPrice,
      nowUtc: nowUtc,
      targetCount: targetCount,
      requestedMargin: null,
      requestedLeverage: leverage,
      systemSuggested: true,
      quality: quality,
      qualityMultiplier: multiplier,
    );
  }

  static ManualTradePlan recalculate({
    required SignalJournalEntry setup,
    required AutoTradeAccountSnapshot account,
    required ManualTradeInstrumentRules rules,
    required double markPrice,
    required DateTime nowUtc,
    required double margin,
    required int leverage,
    required int targetCount,
  }) {
    final quality = _qualityScore(setup);
    return _build(
      setup: setup,
      account: account,
      rules: rules,
      markPrice: markPrice,
      nowUtc: nowUtc,
      targetCount: targetCount,
      requestedMargin: margin,
      requestedLeverage: leverage,
      systemSuggested: false,
      quality: quality,
      qualityMultiplier: _qualityMultiplier(quality),
    );
  }

  static ManualTradePlan _build({
    required SignalJournalEntry setup,
    required AutoTradeAccountSnapshot account,
    required ManualTradeInstrumentRules rules,
    required double markPrice,
    required DateTime nowUtc,
    required int targetCount,
    required double? requestedMargin,
    required int requestedLeverage,
    required bool systemSuggested,
    required int quality,
    required double qualityMultiplier,
  }) {
    ManualTradePlan blocked(
      ManualTradePlanBlockReason reason,
      String explanation, {
      double margin = 0,
      int leverage = 1,
      double quantity = 0,
      double maximumLoss = 0,
      double estimatedCosts = 0,
      double hardRiskCap = 0,
      double maximumPermittedMargin = 0,
      int maximumPermittedLeverage = 1,
      ProfitProtectionTargetAllocation? targetAllocation,
      List<double> targets = const [],
      List<double> targetQuantities = const [],
    }) {
      final notional = quantity > 0 && markPrice.isFinite && markPrice > 0
          ? quantity * markPrice
          : 0.0;
      return ManualTradePlan(
        policyVersion: version,
        setupId: setup.setupId,
        symbol: setup.symbol,
        direction: setup.direction,
        systemSuggested: systemSuggested,
        margin: margin,
        leverage: leverage,
        notional: notional,
        quantity: quantity,
        entryPrice: markPrice.isFinite && markPrice > 0 ? markPrice : 0,
        stopLoss: setup.stopLoss ?? 0,
        targets: List.unmodifiable(targets),
        targetQuantities: List.unmodifiable(targetQuantities),
        targetAllocation:
            targetAllocation ?? _allocationFor(setup, targetCount.clamp(1, 3).toInt()),
        maximumLoss: maximumLoss,
        riskPercentOfEquity: account.estimatedEquity > 0
            ? maximumLoss / account.estimatedEquity * 100
            : 0,
        estimatedCosts: estimatedCosts,
        availableMarginBefore: account.available,
        remainingAvailableMargin: math.max(0, account.available - margin),
        hardRiskCap: hardRiskCap,
        maximumPermittedMargin: maximumPermittedMargin,
        maximumPermittedLeverage: maximumPermittedLeverage,
        qualityScore: quality,
        qualityRiskMultiplier: qualityMultiplier,
        blockReason: reason,
        explanation: explanation,
      );
    }

    final now = nowUtc.toUtc();
    if (setup.closed ||
        (setup.outcome != SignalOutcome.pendingEntry &&
            setup.outcome != SignalOutcome.active)) {
      return blocked(
        ManualTradePlanBlockReason.setupNotExecutable,
        'This setup is no longer eligible for a new manual entry.',
      );
    }
    if (!now.isBefore(setup.validUntil.toUtc())) {
      return blocked(
        ManualTradePlanBlockReason.setupExpired,
        'The setup validity window has expired.',
      );
    }
    if (markPrice <= 0 || !markPrice.isFinite) {
      return blocked(
        ManualTradePlanBlockReason.accountUnavailable,
        'A valid current market price is required.',
      );
    }
    final entryLower = setup.entryLower;
    final entryUpper = setup.entryUpper;
    if (entryLower == null ||
        entryUpper == null ||
        !entryLower.isFinite ||
        !entryUpper.isFinite ||
        entryLower <= 0 ||
        entryUpper <= 0 ||
        entryLower > entryUpper) {
      return blocked(
        ManualTradePlanBlockReason.missingEntry,
        'The setup does not contain a valid entry zone.',
      );
    }
    final tolerance = markPrice * entryZoneToleranceFraction;
    if (markPrice < entryLower - tolerance ||
        markPrice > entryUpper + tolerance) {
      return blocked(
        ManualTradePlanBlockReason.marketOutsideEntryZone,
        'Current market price is outside the setup entry zone.',
      );
    }
    final stop = setup.stopLoss;
    final validStop =
        stop != null &&
        stop.isFinite &&
        stop > 0 &&
        (setup.direction == TradeDirection.long
            ? stop < markPrice
            : setup.direction == TradeDirection.short
            ? stop > markPrice
            : false);
    if (!validStop) {
      return blocked(
        ManualTradePlanBlockReason.invalidStop,
        'The setup stop loss is missing or on the wrong side of the entry.',
      );
    }
    if (targetCount < 1 ||
        targetCount > 3 ||
        setup.targets.length < targetCount) {
      return blocked(
        ManualTradePlanBlockReason.insufficientTargets,
        'The selected TP count is not available on this setup.',
      );
    }
    final selectedTargets = setup.targets
        .take(targetCount)
        .map(rules.roundPrice)
        .toList(growable: false);
    final validTargets = selectedTargets.every(
      (target) =>
          target.isFinite &&
          target > 0 &&
          (setup.direction == TradeDirection.long
              ? target > markPrice
              : target < markPrice),
    );
    if (!validTargets) {
      return blocked(
        ManualTradePlanBlockReason.insufficientTargets,
        'One or more selected targets are no longer valid from current price.',
        targets: selectedTargets,
      );
    }
    final accountAge = now.difference(account.syncedAt.toUtc());
    if (accountAge.isNegative || accountAge > accountFreshness) {
      return blocked(
        ManualTradePlanBlockReason.staleAccount,
        'The Bitunix account snapshot is stale and must be refreshed.',
        targets: selectedTargets,
      );
    }
    if (!account.available.isFinite ||
        !account.estimatedEquity.isFinite ||
        account.available <= 0 ||
        account.estimatedEquity <= 0) {
      return blocked(
        ManualTradePlanBlockReason.accountUnavailable,
        'Available margin or account equity is unavailable.',
        targets: selectedTargets,
      );
    }
    if (!account.allOpenPositionsFullyProtected) {
      return blocked(
        ManualTradePlanBlockReason.existingExposureUnprotected,
        'Existing open exposure is not fully protected.',
        targets: selectedTargets,
      );
    }
    final symbol = setup.symbol.trim().toUpperCase();
    if (account.positions.any(
      (position) =>
          position.quantity > 0 &&
          position.symbol.trim().toUpperCase() == symbol,
    )) {
      return blocked(
        ManualTradePlanBlockReason.duplicateSymbolExposure,
        'An open position already exists for this symbol.',
        targets: selectedTargets,
      );
    }
    if (!rules.valid || rules.symbol.trim().toUpperCase() != symbol) {
      return blocked(
        ManualTradePlanBlockReason.invalidInstrumentRules,
        'Bitunix instrument constraints are invalid.',
        targets: selectedTargets,
      );
    }
    if (!rules.apiSupported) {
      return blocked(
        ManualTradePlanBlockReason.apiUnsupported,
        'Bitunix API execution is unavailable for this symbol.',
        targets: selectedTargets,
      );
    }
    if (!rules.open) {
      return blocked(
        ManualTradePlanBlockReason.marketClosed,
        'Bitunix reports this futures market as closed.',
        targets: selectedTargets,
      );
    }

    final maximumPermittedLeverage = math.min(
      setup.maximumSafeLeverage,
      rules.maximumLeverage,
    );
    if (maximumPermittedLeverage < rules.minimumLeverage ||
        requestedLeverage < rules.minimumLeverage ||
        requestedLeverage > maximumPermittedLeverage) {
      return blocked(
        ManualTradePlanBlockReason.invalidLeverage,
        'Leverage is outside the exchange or Quantara safety range.',
        leverage: requestedLeverage,
        maximumPermittedLeverage: maximumPermittedLeverage,
        targets: selectedTargets,
      );
    }

    final hardRiskCap = math.min(
      setup.maximumLoss,
      account.estimatedEquity * maximumRiskFractionOfEquity,
    );
    final maximumPermittedMargin = math.min(
      account.available,
      account.estimatedEquity * maximumMarginFractionOfEquity,
    );
    if (!hardRiskCap.isFinite ||
        hardRiskCap <= 0 ||
        !maximumPermittedMargin.isFinite ||
        maximumPermittedMargin <= 0) {
      return blocked(
        ManualTradePlanBlockReason.accountUnavailable,
        'No safe risk or margin budget is available for this setup.',
        leverage: requestedLeverage,
        hardRiskCap: hardRiskCap,
        maximumPermittedMargin: maximumPermittedMargin,
        maximumPermittedLeverage: maximumPermittedLeverage,
        targets: selectedTargets,
      );
    }

    final stopDistance = (markPrice - stop!).abs();
    final costRate =
        setup.notionalValue > 0 && setup.estimatedRoundTripCosts >= 0
        ? (setup.estimatedRoundTripCosts / setup.notionalValue).clamp(0.0, 0.05)
        : fallbackRoundTripCostRate;
    final riskPerUnit = stopDistance + markPrice * costRate;
    if (!riskPerUnit.isFinite || riskPerUnit <= 0) {
      return blocked(
        ManualTradePlanBlockReason.invalidStop,
        'Risk per unit could not be calculated safely.',
        leverage: requestedLeverage,
        hardRiskCap: hardRiskCap,
        maximumPermittedMargin: maximumPermittedMargin,
        maximumPermittedLeverage: maximumPermittedLeverage,
        targets: selectedTargets,
      );
    }

    late final double rawQuantity;
    late final double requestedOrSuggestedMargin;
    if (systemSuggested) {
      final targetRisk = hardRiskCap * qualityMultiplier;
      final riskQuantity = targetRisk / riskPerUnit;
      final marginQuantity =
          maximumPermittedMargin * requestedLeverage / markPrice;
      rawQuantity = math.min(
        math.min(riskQuantity, marginQuantity),
        rules.maximumMarketQuantity,
      );
      final rounded = rules.roundQuantityDown(rawQuantity);
      requestedOrSuggestedMargin =
          rounded <= 0 ? 0 : rounded * markPrice / requestedLeverage;
    } else {
      if (requestedMargin == null ||
          !requestedMargin.isFinite ||
          requestedMargin <= 0) {
        return blocked(
          ManualTradePlanBlockReason.invalidMargin,
          'Margin must be a positive finite value.',
          leverage: requestedLeverage,
          hardRiskCap: hardRiskCap,
          maximumPermittedMargin: maximumPermittedMargin,
          maximumPermittedLeverage: maximumPermittedLeverage,
          targets: selectedTargets,
        );
      }
      requestedOrSuggestedMargin = requestedMargin;
      rawQuantity = requestedMargin * requestedLeverage / markPrice;
    }

    final quantity = rules.roundQuantityDown(rawQuantity);
    final notional = quantity * markPrice;
    final margin = notional / requestedLeverage;
    final estimatedCosts = notional * costRate;
    final maximumLoss = quantity * stopDistance + estimatedCosts;

    if (!systemSuggested &&
        (requestedOrSuggestedMargin > account.available + 1e-9 ||
            requestedOrSuggestedMargin > maximumPermittedMargin + 1e-9)) {
      return blocked(
        ManualTradePlanBlockReason.insufficientMargin,
        'Requested margin exceeds the available or per-position safety budget.',
        margin: requestedOrSuggestedMargin,
        leverage: requestedLeverage,
        quantity: quantity,
        maximumLoss: maximumLoss,
        estimatedCosts: estimatedCosts,
        hardRiskCap: hardRiskCap,
        maximumPermittedMargin: maximumPermittedMargin,
        maximumPermittedLeverage: maximumPermittedLeverage,
        targets: selectedTargets,
      );
    }
    if (quantity < rules.minimumQuantity) {
      return blocked(
        ManualTradePlanBlockReason.quantityTooSmall,
        'The resulting quantity is below the Bitunix minimum.',
        margin: margin,
        leverage: requestedLeverage,
        quantity: quantity,
        maximumLoss: maximumLoss,
        estimatedCosts: estimatedCosts,
        hardRiskCap: hardRiskCap,
        maximumPermittedMargin: maximumPermittedMargin,
        maximumPermittedLeverage: maximumPermittedLeverage,
        targets: selectedTargets,
      );
    }
    if (quantity > rules.maximumMarketQuantity + 1e-12) {
      return blocked(
        ManualTradePlanBlockReason.quantityTooLarge,
        'The resulting quantity exceeds the Bitunix market-order maximum.',
        margin: margin,
        leverage: requestedLeverage,
        quantity: quantity,
        maximumLoss: maximumLoss,
        estimatedCosts: estimatedCosts,
        hardRiskCap: hardRiskCap,
        maximumPermittedMargin: maximumPermittedMargin,
        maximumPermittedLeverage: maximumPermittedLeverage,
        targets: selectedTargets,
      );
    }
    if (maximumLoss > hardRiskCap + 1e-9) {
      return blocked(
        ManualTradePlanBlockReason.hardRiskExceeded,
        'The requested size exceeds the setup/account hard risk cap.',
        margin: margin,
        leverage: requestedLeverage,
        quantity: quantity,
        maximumLoss: maximumLoss,
        estimatedCosts: estimatedCosts,
        hardRiskCap: hardRiskCap,
        maximumPermittedMargin: maximumPermittedMargin,
        maximumPermittedLeverage: maximumPermittedLeverage,
        targets: selectedTargets,
      );
    }

    final targetAllocation = _allocationFor(setup, targetCount);
    final allocation = ProfitProtectionAllocation.allocate(
      totalQuantity: quantity,
      plan: ProfitProtectionPolicy.forJournal(
        setup,
      ).withTargetAllocation(targetAllocation),
      roundDown: rules.roundQuantityDown,
    );
    if (allocation.activeTargetCount != targetCount ||
        !allocation.isValidFor(rules.minimumQuantity)) {
      return blocked(
        ManualTradePlanBlockReason.invalidTargetAllocation,
        'This position size cannot support the selected TP count at exchange minimum quantity.',
        margin: margin,
        leverage: requestedLeverage,
        quantity: quantity,
        maximumLoss: maximumLoss,
        estimatedCosts: estimatedCosts,
        hardRiskCap: hardRiskCap,
        maximumPermittedMargin: maximumPermittedMargin,
        maximumPermittedLeverage: maximumPermittedLeverage,
        targetAllocation: targetAllocation,
        targets: selectedTargets,
        targetQuantities: allocation.quantities.take(targetCount).toList(),
      );
    }

    return ManualTradePlan(
      policyVersion: version,
      setupId: setup.setupId,
      symbol: symbol,
      direction: setup.direction,
      systemSuggested: systemSuggested,
      margin: margin,
      leverage: requestedLeverage,
      notional: notional,
      quantity: quantity,
      entryPrice: markPrice,
      stopLoss: rules.roundPrice(stop),
      targets: List.unmodifiable(selectedTargets),
      targetQuantities: List.unmodifiable(
        allocation.quantities.take(targetCount).toList(),
      ),
      targetAllocation: targetAllocation,
      maximumLoss: maximumLoss,
      riskPercentOfEquity: maximumLoss / account.estimatedEquity * 100,
      estimatedCosts: estimatedCosts,
      availableMarginBefore: account.available,
      remainingAvailableMargin: math.max(0, account.available - margin),
      hardRiskCap: hardRiskCap,
      maximumPermittedMargin: maximumPermittedMargin,
      maximumPermittedLeverage: maximumPermittedLeverage,
      qualityScore: quality,
      qualityRiskMultiplier: qualityMultiplier,
      blockReason: ManualTradePlanBlockReason.none,
      explanation:
          'Default sizing is risk-first: setup quality may scale the proposed risk down, never above the setup/account hard cap.',
    );
  }

  static int _qualityScore(SignalJournalEntry setup) =>
      (setup.setupQualityScore ?? setup.confidencePercent)
          .clamp(0, 100)
          .toInt();

  static double _qualityMultiplier(int score) =>
      (0.50 + score.clamp(0, 100) / 200).clamp(0.50, 1.0).toDouble();

  static ProfitProtectionTargetAllocation _allocationFor(
    SignalJournalEntry setup,
    int targetCount,
  ) {
    final base = ProfitProtectionPolicy.forJournal(setup).targetAllocation;
    return switch (targetCount) {
      1 => ProfitProtectionTargetAllocation.checked(
        tp1Fraction: 1,
        tp2Fraction: 0,
        tp3Fraction: 0,
      ),
      2 => ProfitProtectionTargetAllocation.checked(
        tp1Fraction: base.tp1Fraction,
        tp2Fraction: base.tp2Fraction + base.tp3Fraction,
        tp3Fraction: 0,
      ),
      _ => base,
    };
  }
}
