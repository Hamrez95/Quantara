import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/market_analysis/domain/market_regime_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/profit_protection_policy.dart';

void main() {
  test('every profile is a valid three-stage plan with TP1 largest', () {
    for (final regime in MarketRegime.values) {
      final plan = ProfitProtectionPolicy.forRegime(regime);
      expect(plan.targetFractions, hasLength(3));
      expect(
        plan.targetFractions.fold<double>(0, (sum, value) => sum + value),
        closeTo(1, 0.000001),
      );
      expect(
        plan.targetFractions.first,
        greaterThanOrEqualTo(plan.targetFractions[1]),
      );
      expect(
        plan.targetFractions.first,
        greaterThanOrEqualTo(plan.targetFractions[2]),
      );
      expect(plan.minimumTargetFraction, greaterThanOrEqualTo(0.25));
      expect(plan.tp1RemainingTrigger, greaterThan(plan.tp2RemainingTrigger));
    }
  });

  test('range saves faster while breakout preserves a larger runner', () {
    final range = ProfitProtectionPolicy.forRegime(MarketRegime.range);
    final breakout = ProfitProtectionPolicy.forRegime(
      MarketRegime.breakoutExpansion,
    );

    expect(
      range.targetFractions.first,
      greaterThan(breakout.targetFractions.first),
    );
    expect(range.targetFractions.last, lessThan(breakout.targetFractions.last));
  });

  test('legacy transition profile preserves the 40/30/30 ladder', () {
    expect(
      ProfitProtectionPolicy.forRegime(MarketRegime.transition).targetFractions,
      const [0.40, 0.30, 0.30],
    );
  });
}
