final class PendingTargetProtectionEvidence {
  const PendingTargetProtectionEvidence({
    required this.orderId,
    required this.triggerPrice,
    required this.quantity,
  });

  final String orderId;
  final double triggerPrice;
  final double quantity;
}

abstract final class RemainingTargetProtectionPolicy {
  static bool allRemainingTargetsProtected({
    required List<String> targetOrderIds,
    required List<double> targetQuantities,
    required List<double> filledQuantities,
    required Iterable<PendingTargetProtectionEvidence> pendingProtection,
    required double quantityTolerance,
  }) {
    if (targetOrderIds.length != 3 ||
        targetQuantities.length != 3 ||
        filledQuantities.length != 3 ||
        !quantityTolerance.isFinite ||
        quantityTolerance < 0) {
      return false;
    }
    final comparisonTolerance = quantityTolerance / 2;
    final pending = pendingProtection.toList(growable: false);
    for (var index = 0; index < 3; index++) {
      final id = targetOrderIds[index].trim();
      final planned = targetQuantities[index];
      final filled = filledQuantities[index];
      if (!planned.isFinite ||
          planned < 0 ||
          !filled.isFinite ||
          filled < 0 ||
          filled > planned + comparisonTolerance) {
        return false;
      }
      if (planned == 0) {
        if (id.isNotEmpty || filled > comparisonTolerance) return false;
        continue;
      }
      if (id.isEmpty) return false;
      final remaining = (planned - filled).clamp(0, planned).toDouble();
      if (remaining <= comparisonTolerance) continue;
      final confirmed = pending.any(
        (item) =>
            item.orderId.trim() == id &&
            item.triggerPrice.isFinite &&
            item.triggerPrice > 0 &&
            item.quantity.isFinite &&
            item.quantity > 0 &&
            item.quantity + comparisonTolerance >= remaining,
      );
      if (!confirmed) return false;
    }
    return true;
  }
}
