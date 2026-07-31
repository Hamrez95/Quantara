import 'dart:math' as math;

/// Immutable release safety ceilings. User preferences may be stricter but
/// cannot expand authority beyond this policy.
final class LocalLiveSafetyPolicy {
  const LocalLiveSafetyPolicy({
    required this.maximumRiskPerTradePercent,
    required this.maximumDailyLossPercent,
    required this.maximumConcurrentPositions,
  });

  static const canary = LocalLiveSafetyPolicy(
    maximumRiskPerTradePercent: 0.25,
    maximumDailyLossPercent: 2,
    maximumConcurrentPositions: 3,
  );

  final double maximumRiskPerTradePercent;
  final double maximumDailyLossPercent;
  final int maximumConcurrentPositions;

  void validateUserPreferences({
    required double riskPerTradePercent,
    required double dailyLossPercent,
    required int maximumConcurrentPositions,
  }) {
    if (!riskPerTradePercent.isFinite ||
        riskPerTradePercent <= 0 ||
        riskPerTradePercent > maximumRiskPerTradePercent) {
      throw FormatException(
        'Risk per trade must be above 0% and no more than '
        '${maximumRiskPerTradePercent.toStringAsFixed(2)}% for this release.',
      );
    }
    if (!dailyLossPercent.isFinite ||
        dailyLossPercent <= 0 ||
        dailyLossPercent > maximumDailyLossPercent) {
      throw FormatException(
        'Daily loss limit must be above 0% and no more than '
        '${maximumDailyLossPercent.toStringAsFixed(2)}% for this release.',
      );
    }
    if (maximumConcurrentPositions < 1 ||
        maximumConcurrentPositions > this.maximumConcurrentPositions) {
      throw FormatException(
        'Concurrent positions must be between 1 and '
        '${this.maximumConcurrentPositions} for this release.',
      );
    }
  }
}

final class LocalLiveOpenRisk {
  const LocalLiveOpenRisk({
    required this.positionId,
    required this.symbol,
    required this.worstCaseLoss,
    this.protectionVerified = true,
  });

  final String positionId;
  final String symbol;
  final double worstCaseLoss;
  final bool protectionVerified;
}

final class LocalLiveRiskBudgetInput {
  const LocalLiveRiskBudgetInput({
    required this.startEquity,
    required this.dailyLossLimitPercent,
    required this.riskPerTradePercent,
    required this.maximumConcurrentPositions,
    required this.openPositionCount,
    required this.openRisks,
    this.realizedPnl = 0,
    this.pendingReservedRisk = 0,
    this.pendingPositionCount = 0,
    this.additionalFeeReserve = 0,
  });

  final double startEquity;
  final double dailyLossLimitPercent;
  final double riskPerTradePercent;
  final int maximumConcurrentPositions;
  final int openPositionCount;
  final List<LocalLiveOpenRisk> openRisks;
  final double realizedPnl;
  final double pendingReservedRisk;
  final int pendingPositionCount;
  final double additionalFeeReserve;
}

final class LocalLiveRiskBudgetSnapshot {
  const LocalLiveRiskBudgetSnapshot({
    required this.dailyBudget,
    required this.realizedLoss,
    required this.openStopRisk,
    required this.pendingReservedRisk,
    required this.additionalFeeReserve,
    required this.consumedRisk,
    required this.remainingRisk,
    required this.openSlots,
    required this.nextTradeAllocation,
    required this.protectionVerified,
  });

  final double dailyBudget;
  final double realizedLoss;
  final double openStopRisk;
  final double pendingReservedRisk;
  final double additionalFeeReserve;
  final double consumedRisk;
  final double remainingRisk;
  final int openSlots;
  final double nextTradeAllocation;
  final bool protectionVerified;

  bool get canOpenAnotherPosition =>
      protectionVerified && openSlots > 0 && nextTradeAllocation > 0;
}

/// Deterministic portfolio-level budget allocator.
///
/// It reserves an equal share of the remaining daily budget for every unused
/// position slot. This prevents the first entry from consuming the full daily
/// loss allowance while still respecting the user's per-trade ceiling.
abstract final class LocalLiveRiskBudget {
  static LocalLiveRiskBudgetSnapshot calculate(
    LocalLiveRiskBudgetInput input,
  ) {
    _validateInput(input);

    final dailyBudget =
        input.startEquity * input.dailyLossLimitPercent / 100;
    final realizedLoss = math.max(0, -input.realizedPnl).toDouble();
    final openStopRisk = input.openRisks.fold<double>(
      0,
      (sum, risk) => sum + math.max(0, risk.worstCaseLoss),
    );
    final pendingReservedRisk = math.max(0, input.pendingReservedRisk);
    final additionalFeeReserve = math.max(0, input.additionalFeeReserve);
    final consumedRisk =
        realizedLoss +
        openStopRisk +
        pendingReservedRisk +
        additionalFeeReserve;
    final remainingRisk = math.max(0, dailyBudget - consumedRisk).toDouble();
    final occupiedSlots =
        input.openPositionCount + input.pendingPositionCount;
    final openSlots = math.max(
      0,
      input.maximumConcurrentPositions - occupiedSlots,
    );
    final protectionVerified = input.openRisks.every(
      (risk) => risk.protectionVerified,
    );

    final userPerTradeCap =
        input.startEquity * input.riskPerTradePercent / 100;
    final equalSlotAllocation = openSlots == 0 ? 0 : remainingRisk / openSlots;
    final nextTradeAllocation = protectionVerified
        ? math.min(userPerTradeCap, equalSlotAllocation).toDouble()
        : 0.0;

    return LocalLiveRiskBudgetSnapshot(
      dailyBudget: dailyBudget,
      realizedLoss: realizedLoss,
      openStopRisk: openStopRisk,
      pendingReservedRisk: pendingReservedRisk,
      additionalFeeReserve: additionalFeeReserve,
      consumedRisk: consumedRisk,
      remainingRisk: remainingRisk,
      openSlots: openSlots,
      nextTradeAllocation: nextTradeAllocation,
      protectionVerified: protectionVerified,
    );
  }

  static void _validateInput(LocalLiveRiskBudgetInput input) {
    if (!input.startEquity.isFinite || input.startEquity <= 0) {
      throw const FormatException('Start equity must be greater than zero.');
    }
    if (!input.dailyLossLimitPercent.isFinite ||
        input.dailyLossLimitPercent <= 0) {
      throw const FormatException(
        'Daily loss limit percent must be greater than zero.',
      );
    }
    if (!input.riskPerTradePercent.isFinite ||
        input.riskPerTradePercent <= 0) {
      throw const FormatException(
        'Risk per trade percent must be greater than zero.',
      );
    }
    if (input.maximumConcurrentPositions < 1 ||
        input.openPositionCount < 0 ||
        input.pendingPositionCount < 0) {
      throw const FormatException('Position counts are invalid.');
    }
    for (final risk in input.openRisks) {
      if (!risk.worstCaseLoss.isFinite || risk.worstCaseLoss < 0) {
        throw const FormatException('Open position risk is invalid.');
      }
    }
  }
}
