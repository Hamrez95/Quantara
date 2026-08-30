import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/domain/remaining_target_protection_policy.dart';

void main() {
  const ids = ['tp-1', 'tp-2', 'tp-3'];
  const quantities = [0.75, 0.20, 0.05];

  test('accepts pending protection for every unfilled target tranche', () {
    expect(
      RemainingTargetProtectionPolicy.allRemainingTargetsProtected(
        targetOrderIds: ids,
        targetQuantities: quantities,
        filledQuantities: const [0, 0, 0],
        pendingProtection: const [
          PendingTargetProtectionEvidence(
            orderId: 'tp-1',
            triggerPrice: 110,
            quantity: 0.75,
          ),
          PendingTargetProtectionEvidence(
            orderId: 'tp-2',
            triggerPrice: 120,
            quantity: 0.20,
          ),
          PendingTargetProtectionEvidence(
            orderId: 'tp-3',
            triggerPrice: 130,
            quantity: 0.05,
          ),
        ],
        quantityTolerance: 0.000001,
      ),
      isTrue,
    );
  });

  test('after TP1 fill only TP2 and TP3 must remain exchange-protected', () {
    expect(
      RemainingTargetProtectionPolicy.allRemainingTargetsProtected(
        targetOrderIds: ids,
        targetQuantities: quantities,
        filledQuantities: const [0.75, 0, 0],
        pendingProtection: const [
          PendingTargetProtectionEvidence(
            orderId: 'tp-2',
            triggerPrice: 120,
            quantity: 0.20,
          ),
          PendingTargetProtectionEvidence(
            orderId: 'tp-3',
            triggerPrice: 130,
            quantity: 0.05,
          ),
        ],
        quantityTolerance: 0.000001,
      ),
      isTrue,
    );
  });

  test(
    'blocks concurrency when a remaining target is missing or undersized',
    () {
      expect(
        RemainingTargetProtectionPolicy.allRemainingTargetsProtected(
          targetOrderIds: ids,
          targetQuantities: quantities,
          filledQuantities: const [0.75, 0, 0],
          pendingProtection: const [
            PendingTargetProtectionEvidence(
              orderId: 'tp-2',
              triggerPrice: 120,
              quantity: 0.19,
            ),
            PendingTargetProtectionEvidence(
              orderId: 'tp-3',
              triggerPrice: 130,
              quantity: 0.05,
            ),
          ],
          quantityTolerance: 0.000001,
        ),
        isFalse,
      );
    },
  );

  test('rejects duplicate active target order identities', () {
    expect(
      RemainingTargetProtectionPolicy.allRemainingTargetsProtected(
        targetOrderIds: const ['tp-shared', 'tp-shared', 'tp-3'],
        targetQuantities: quantities,
        filledQuantities: const [0, 0, 0],
        pendingProtection: const [
          PendingTargetProtectionEvidence(
            orderId: 'tp-shared',
            triggerPrice: 110,
            quantity: 0.75,
          ),
          PendingTargetProtectionEvidence(
            orderId: 'tp-3',
            triggerPrice: 130,
            quantity: 0.05,
          ),
        ],
        quantityTolerance: 0.000001,
      ),
      isFalse,
    );
  });
}
