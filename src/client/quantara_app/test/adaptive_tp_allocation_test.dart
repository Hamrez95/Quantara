import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/domain/remaining_target_protection_policy.dart';
import 'package:quantara_app/features/owner_alpha/domain/profit_protection_policy.dart';

void main() {
  double tenthDown(double value) => (value * 10).floor() / 10;

  ProfitProtectionPlan plan(ProfitProtectionTargetAllocation allocation) =>
      ProfitProtectionPlan(
        profile: ProfitProtectionProfile.transitionBalance,
        targetAllocation: allocation,
      );

  test('manual one and two target allocations are valid and contiguous', () {
    final one = ProfitProtectionTargetAllocation.checked(
      tp1Fraction: 1,
      tp2Fraction: 0,
      tp3Fraction: 0,
    );
    final two = ProfitProtectionTargetAllocation.checked(
      tp1Fraction: 0.8,
      tp2Fraction: 0.2,
      tp3Fraction: 0,
    );
    expect(one.activeTargetCount, 1);
    expect(two.activeTargetCount, 2);
    expect(
      () => ProfitProtectionTargetAllocation.checked(
        tp1Fraction: 0.8,
        tp2Fraction: 0,
        tp3Fraction: 0.2,
      ),
      throwsFormatException,
    );
  });

  test('adaptive allocation collapses an undersized TP3 into TP2', () {
    final configured = ProfitProtectionTargetAllocation.checked(
      tp1Fraction: 0.8,
      tp2Fraction: 0.15,
      tp3Fraction: 0.05,
    );
    final result = ProfitProtectionAllocation.allocateAdaptive(
      totalQuantity: 10,
      plan: plan(configured),
      minimumQuantity: 1,
      roundDown: tenthDown,
    );
    expect(result.activeTargetCount, 2);
    expect(result.targetAllocation.fractions, [0.8, 0.2, 0]);
    expect(result.quantities, [8, 2, 0]);
    expect(result.isValidFor(1), isTrue);
  });

  test('adaptive allocation collapses to one fully covered target', () {
    final configured = ProfitProtectionTargetAllocation.checked(
      tp1Fraction: 0.8,
      tp2Fraction: 0.15,
      tp3Fraction: 0.05,
    );
    final result = ProfitProtectionAllocation.allocateAdaptive(
      totalQuantity: 1.5,
      plan: plan(configured),
      minimumQuantity: 1,
      roundDown: tenthDown,
    );
    expect(result.activeTargetCount, 1);
    expect(result.targetAllocation.fractions, [1, 0, 0]);
    expect(result.quantities, [1.5, 0, 0]);
    expect(result.isValidFor(1), isTrue);
  });

  test('inactive target slots need zero quantity and empty order identity', () {
    expect(
      RemainingTargetProtectionPolicy.allRemainingTargetsProtected(
        targetOrderIds: const ['tp-1', '', ''],
        targetQuantities: const [1.5, 0, 0],
        filledQuantities: const [0, 0, 0],
        pendingProtection: const [
          PendingTargetProtectionEvidence(
            orderId: 'tp-1',
            triggerPrice: 110,
            quantity: 1.5,
          ),
        ],
        quantityTolerance: 0.01,
      ),
      isTrue,
    );
    expect(
      RemainingTargetProtectionPolicy.allRemainingTargetsProtected(
        targetOrderIds: const ['tp-1', 'unexpected', ''],
        targetQuantities: const [1.5, 0, 0],
        filledQuantities: const [0, 0, 0],
        pendingProtection: const [
          PendingTargetProtectionEvidence(
            orderId: 'tp-1',
            triggerPrice: 110,
            quantity: 1.5,
          ),
        ],
        quantityTolerance: 0.01,
      ),
      isFalse,
    );
  });
}
