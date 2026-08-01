final class LocalLiveEntryAffordability {
  const LocalLiveEntryAffordability({
    required this.requiredQuantity,
    required this.minimumNotional,
    required this.minimumBufferedMargin,
    required this.availableMargin,
  });

  final double requiredQuantity;
  final double minimumNotional;
  final double minimumBufferedMargin;
  final double availableMargin;

  double get shortfall =>
      (minimumBufferedMargin - availableMargin).clamp(0, double.infinity);

  bool get affordable =>
      availableMargin.isFinite &&
      minimumBufferedMargin.isFinite &&
      availableMargin >= minimumBufferedMargin;

  static LocalLiveEntryAffordability calculate({
    required double availableMargin,
    required double markPrice,
    required double minimumExchangeQuantity,
    required int leverage,
    int takeProfitTranches = 3,
    double marginBufferMultiplier = 1.15,
  }) {
    if (!availableMargin.isFinite || availableMargin < 0) {
      throw const FormatException('Available margin is invalid.');
    }
    if (!markPrice.isFinite || markPrice <= 0) {
      throw const FormatException('Mark price is invalid.');
    }
    if (!minimumExchangeQuantity.isFinite || minimumExchangeQuantity <= 0) {
      throw const FormatException('Minimum exchange quantity is invalid.');
    }
    if (leverage < 1) {
      throw const FormatException('Leverage must be at least 1x.');
    }
    if (takeProfitTranches < 1) {
      throw const FormatException('At least one target tranche is required.');
    }
    if (!marginBufferMultiplier.isFinite || marginBufferMultiplier < 1) {
      throw const FormatException('Margin buffer multiplier is invalid.');
    }

    final requiredQuantity = minimumExchangeQuantity * takeProfitTranches;
    final minimumNotional = requiredQuantity * markPrice;
    final minimumBufferedMargin =
        minimumNotional / leverage * marginBufferMultiplier;

    return LocalLiveEntryAffordability(
      requiredQuantity: requiredQuantity,
      minimumNotional: minimumNotional,
      minimumBufferedMargin: minimumBufferedMargin,
      availableMargin: availableMargin,
    );
  }
}
