import '../domain/owner_alpha_models.dart';

/// Reconciles fresh deterministic sizing with durable journal history.
abstract final class SignalSizingReconciler {
  static SignalJournalEntry merge({
    required TradeIdea idea,
    required double sizingCapital,
    required double riskPercent,
    SignalJournalEntry? existing,
  }) {
    final fresh = SignalJournalEntry.fromIdea(
      idea,
      sizingCapital: sizingCapital,
    );
    if (existing == null) return fresh;
    final sizingChanged =
        (existing.sizingCapital - sizingCapital).abs() > 0.0001 ||
        (existing.maximumLoss - idea.maximumLoss).abs() > 0.0001 ||
        existing.positionSize <= 0 ||
        existing.notionalValue <= 0 ||
        (existing.sizingCapital > 0 &&
            (existing.sizingRiskPercent - riskPercent).abs() > 0.0001);
    if (!existing.canRefreshSizing || !sizingChanged) return existing;
    return fresh.copyWith(
      note: existing.note,
      closed: existing.closed,
      selectedLeverage: existing.selectedLeverage
          .clamp(1, TradeIdea.maximumManualLeverage)
          .toInt(),
    );
  }
}
