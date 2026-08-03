import 'dart:math' as math;

import '../../owner_alpha/domain/owner_alpha_models.dart';
import 'trading_pnl_projection.dart';

final class ConfirmedTargetFillProgress {
  const ConfirmedTargetFillProgress._({
    required this.filledQuantities,
    required this.tp1Confirmed,
    required this.tp2Confirmed,
    required this.tp3Confirmed,
    required this.newTradeIds,
  });

  final List<double> filledQuantities;
  final bool tp1Confirmed;
  final bool tp2Confirmed;
  final bool tp3Confirmed;
  final Set<String> newTradeIds;

  double get tp1FilledQuantity => filledQuantities[0];
  double get tp2FilledQuantity => filledQuantities[1];
  double get tp3FilledQuantity => filledQuantities[2];

  static ConfirmedTargetFillProgress reconcile({
    required List<String> targetOrderIds,
    required List<double> targetQuantities,
    required Iterable<ExchangePnlFill> exchangeExitFills,
    required Set<String> processedTradeIds,
    required double quantityTolerance,
    double? observedRemainingQuantity,
  }) {
    if (targetOrderIds.length != 3 || targetQuantities.length != 3) {
      return const ConfirmedTargetFillProgress._(
        filledQuantities: [0, 0, 0],
        tp1Confirmed: false,
        tp2Confirmed: false,
        tp3Confirmed: false,
        newTradeIds: {},
      );
    }
    final orderToIndex = <String, int>{
      for (var index = 0; index < targetOrderIds.length; index++)
        if (targetOrderIds[index].trim().isNotEmpty)
          targetOrderIds[index].trim(): index,
    };
    final seenTradeIds = <String>{};
    final filled = <double>[0, 0, 0];
    final newlySeen = <String>{};
    for (final fill in exchangeExitFills) {
      if (!fill.reduceOnly) continue;
      final tradeId = fill.tradeId.trim();
      final index = orderToIndex[fill.orderId.trim()];
      if (tradeId.isEmpty || index == null || !seenTradeIds.add(tradeId)) {
        continue;
      }
      if (fill.quantity.isFinite && fill.quantity > 0) {
        filled[index] += fill.quantity;
      }
      if (!processedTradeIds.contains(tradeId)) newlySeen.add(tradeId);
    }
    bool confirmed(int index) =>
        targetQuantities[index].isFinite &&
        targetQuantities[index] > 0 &&
        filled[index] + math.max(0, quantityTolerance) >=
            targetQuantities[index];

    // observedRemainingQuantity is intentionally not used as confirmation.
    // Manual closes, liquidation, exchange corrections, or stale positions can
    // all reduce quantity without proving which target filled.
    return ConfirmedTargetFillProgress._(
      filledQuantities: List.unmodifiable(filled),
      tp1Confirmed: confirmed(0),
      tp2Confirmed: confirmed(1),
      tp3Confirmed: confirmed(2),
      newTradeIds: Set.unmodifiable(newlySeen),
    );
  }
}

final class ProfitLockStopDecision {
  const ProfitLockStopDecision({
    required this.proposedStop,
    required this.requiresMutation,
    required this.reason,
  });

  final double proposedStop;
  final bool requiresMutation;
  final String reason;
}

abstract final class ProfitLockStopPolicy {
  static ProfitLockStopDecision afterTp1({
    required TradeDirection direction,
    required double entryPrice,
    required double currentConfirmedStop,
    required double costBufferRate,
    required int pricePrecision,
  }) {
    if (direction == TradeDirection.wait) {
      return ProfitLockStopDecision(
        proposedStop: currentConfirmedStop,
        requiresMutation: false,
        reason: 'Direction is not actionable; stop promotion is blocked.',
      );
    }
    final raw = direction == TradeDirection.long
        ? entryPrice * (1 + costBufferRate)
        : entryPrice * (1 - costBufferRate);
    final candidate = _roundTowardProfit(
      raw,
      direction: direction,
      pricePrecision: pricePrecision,
    );
    return _neverWorsen(
      direction: direction,
      currentStop: currentConfirmedStop,
      candidateStop: candidate,
      reason: 'TP1 exchange fill confirmed; lock cost-aware profit.',
    );
  }

  static ProfitLockStopDecision afterTp2({
    required TradeDirection direction,
    required double tp1Price,
    required double currentConfirmedStop,
    required int pricePrecision,
  }) {
    if (direction == TradeDirection.wait) {
      return ProfitLockStopDecision(
        proposedStop: currentConfirmedStop,
        requiresMutation: false,
        reason: 'Direction is not actionable; stop promotion is blocked.',
      );
    }
    final candidate = _roundTowardProfit(
      tp1Price,
      direction: direction,
      pricePrecision: pricePrecision,
    );
    return _neverWorsen(
      direction: direction,
      currentStop: currentConfirmedStop,
      candidateStop: candidate,
      reason: 'TP2 exchange fill confirmed; promote runner stop to TP1.',
    );
  }

  static ProfitLockStopDecision _neverWorsen({
    required TradeDirection direction,
    required double currentStop,
    required double candidateStop,
    required String reason,
  }) {
    final currentIsValid = currentStop.isFinite && currentStop > 0;
    final candidateIsSafer =
        !currentIsValid ||
        (direction == TradeDirection.long
            ? candidateStop > currentStop
            : candidateStop < currentStop);
    return ProfitLockStopDecision(
      proposedStop: candidateIsSafer ? candidateStop : currentStop,
      requiresMutation: candidateIsSafer,
      reason: candidateIsSafer ? reason : 'Existing stop is already safer.',
    );
  }

  static double _roundTowardProfit(
    double value, {
    required TradeDirection direction,
    required int pricePrecision,
  }) {
    final factor = math.pow(10, math.max(0, pricePrecision)).toDouble();
    final scaled = value * factor;
    return direction == TradeDirection.long
        ? (scaled - 0.000000001).ceil() / factor
        : (scaled + 0.000000001).floor() / factor;
  }

  static bool isAtLeastAsSafe({
    required TradeDirection direction,
    required double confirmedStop,
    required double proposedStop,
    required double tolerance,
  }) {
    if (direction == TradeDirection.wait) return false;
    return direction == TradeDirection.long
        ? confirmedStop + tolerance >= proposedStop
        : confirmedStop - tolerance <= proposedStop;
  }
}

final class ProfitLockProgress {
  const ProfitLockProgress({
    this.confirmedStage = 0,
    this.pendingStage,
    this.pendingProposedStop,
    this.processedTradeIds = const {},
    this.warning,
  });

  final int confirmedStage;
  final int? pendingStage;
  final double? pendingProposedStop;
  final Set<String> processedTradeIds;
  final String? warning;

  bool get hasPendingPromotion =>
      pendingStage != null && pendingProposedStop != null;

  ProfitLockProgress copyWith({
    int? confirmedStage,
    int? pendingStage,
    bool clearPendingStage = false,
    double? pendingProposedStop,
    bool clearPendingStop = false,
    Set<String>? processedTradeIds,
    String? warning,
    bool clearWarning = false,
  }) => ProfitLockProgress(
    confirmedStage: confirmedStage ?? this.confirmedStage,
    pendingStage: clearPendingStage ? null : pendingStage ?? this.pendingStage,
    pendingProposedStop: clearPendingStop
        ? null
        : pendingProposedStop ?? this.pendingProposedStop,
    processedTradeIds: Set.unmodifiable(
      processedTradeIds ?? this.processedTradeIds,
    ),
    warning: clearWarning ? null : warning ?? this.warning,
  );

  Map<String, Object?> toJson() => {
    'version': 1,
    'confirmedStage': confirmedStage,
    'pendingStage': pendingStage,
    'pendingProposedStop': pendingProposedStop,
    'processedTradeIds': processedTradeIds.toList(growable: false)..sort(),
    'warning': warning,
  };

  factory ProfitLockProgress.fromJson(Object? value) {
    if (value is! Map<Object?, Object?>) return const ProfitLockProgress();
    final json = value.map((key, item) => MapEntry(key.toString(), item));
    return ProfitLockProgress(
      confirmedStage: (json['confirmedStage'] as num?)?.toInt() ?? 0,
      pendingStage: (json['pendingStage'] as num?)?.toInt(),
      pendingProposedStop: (json['pendingProposedStop'] as num?)?.toDouble(),
      processedTradeIds: Set.unmodifiable(
        (json['processedTradeIds'] as List<Object?>? ?? const [])
            .whereType<String>()
            .where((item) => item.trim().isNotEmpty)
            .toSet(),
      ),
      warning: json['warning']?.toString(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ProfitLockProgress &&
      other.confirmedStage == confirmedStage &&
      other.pendingStage == pendingStage &&
      other.pendingProposedStop == pendingProposedStop &&
      _setEquals(other.processedTradeIds, processedTradeIds) &&
      other.warning == warning;

  @override
  int get hashCode => Object.hash(
    confirmedStage,
    pendingStage,
    pendingProposedStop,
    Object.hashAll(processedTradeIds.toList()..sort()),
    warning,
  );

  static bool _setEquals(Set<String> left, Set<String> right) =>
      left.length == right.length && left.containsAll(right);
}
