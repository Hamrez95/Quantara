final class FullPositionStopPolicy {
  const FullPositionStopPolicy._();

  static bool isConfirmed({
    required String evidencePositionId,
    required String expectedPositionId,
    required double stopLossPrice,
    required double stopLossQuantity,
    required double remainingQuantity,
    required double quantityTolerance,
    double? expectedStopLossPrice,
    double priceTolerance = 0,
  }) {
    if (evidencePositionId.trim() != expectedPositionId.trim() ||
        expectedPositionId.trim().isEmpty ||
        !stopLossPrice.isFinite ||
        stopLossPrice <= 0 ||
        !stopLossQuantity.isFinite ||
        !remainingQuantity.isFinite ||
        remainingQuantity <= 0 ||
        !quantityTolerance.isFinite ||
        quantityTolerance < 0) {
      return false;
    }

    if (expectedStopLossPrice != null) {
      if (!expectedStopLossPrice.isFinite ||
          expectedStopLossPrice <= 0 ||
          !priceTolerance.isFinite ||
          priceTolerance < 0 ||
          (stopLossPrice - expectedStopLossPrice).abs() > priceTolerance) {
        return false;
      }
    }

    // Bitunix can represent a whole-position stop with a non-positive
    // quantity. Otherwise the stop must cover the full remaining exposure.
    return stopLossQuantity <= 0 ||
        stopLossQuantity + quantityTolerance >= remainingQuantity;
  }
}
