import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/domain/adaptive_position_management.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';

void main() {
  AdaptiveManagementEvent event(String id, AdaptiveManagementEventKind kind) =>
      AdaptiveManagementEvent(id: id, kind: kind);

  test(
    'valid lifecycle progresses deterministically to runner then exited',
    () {
      var snapshot = AdaptiveManagementSnapshot.initial();
      snapshot = snapshot.apply(event('1', AdaptiveManagementEventKind.arm));
      expect(snapshot.state, AdaptiveManagementState.armed);
      snapshot = snapshot.apply(
        event('2', AdaptiveManagementEventKind.entryConfirmed),
      );
      expect(snapshot.state, AdaptiveManagementState.entered);
      snapshot = snapshot.apply(
        event('3', AdaptiveManagementEventKind.managementActivated),
      );
      expect(snapshot.state, AdaptiveManagementState.active);
      snapshot = snapshot.apply(
        event('4', AdaptiveManagementEventKind.protectionConfirmed),
      );
      expect(snapshot.state, AdaptiveManagementState.protected);
      snapshot = snapshot.apply(
        event('5', AdaptiveManagementEventKind.runnerActivated),
      );
      expect(snapshot.state, AdaptiveManagementState.runner);
      snapshot = snapshot.apply(
        event('6', AdaptiveManagementEventKind.exitConfirmed),
      );
      expect(snapshot.state, AdaptiveManagementState.exited);
      expect(snapshot.revision, 6);
    },
  );

  test('duplicate event id is idempotent', () {
    final armed = AdaptiveManagementSnapshot.initial().apply(
      event('arm-1', AdaptiveManagementEventKind.arm),
    );
    final duplicate = armed.apply(
      event('arm-1', AdaptiveManagementEventKind.arm),
    );

    expect(identical(duplicate, armed), isTrue);
    expect(duplicate.state, AdaptiveManagementState.armed);
    expect(duplicate.revision, armed.revision);
    expect(duplicate.processedEventIds, armed.processedEventIds);
  });

  test('invalid transition fails closed', () {
    final snapshot = AdaptiveManagementSnapshot.initial();

    expect(
      () => snapshot.apply(
        event('bad-1', AdaptiveManagementEventKind.runnerActivated),
      ),
      throwsStateError,
    );
  });

  test('snapshot survives JSON round trip for restart recovery', () {
    var snapshot = AdaptiveManagementSnapshot.initial();
    snapshot = snapshot.apply(event('1', AdaptiveManagementEventKind.arm));
    snapshot = snapshot.apply(
      event('2', AdaptiveManagementEventKind.entryConfirmed),
    );
    snapshot = snapshot.apply(
      event('3', AdaptiveManagementEventKind.managementActivated),
    );

    final restored = AdaptiveManagementSnapshot.fromJson(snapshot.toJson());

    expect(restored.state, snapshot.state);
    expect(restored.revision, snapshot.revision);
    expect(restored.processedEventIds, snapshot.processedEventIds);
    final next = restored.apply(
      event('4', AdaptiveManagementEventKind.protectionConfirmed),
    );
    expect(next.state, AdaptiveManagementState.protected);
  });

  test('terminal state cannot reactivate', () {
    var snapshot = AdaptiveManagementSnapshot.initial();
    snapshot = snapshot.apply(event('1', AdaptiveManagementEventKind.arm));
    snapshot = snapshot.apply(
      event('2', AdaptiveManagementEventKind.entryConfirmed),
    );
    snapshot = snapshot.apply(
      event('3', AdaptiveManagementEventKind.exitConfirmed),
    );
    final revision = snapshot.revision;

    final afterTerminal = snapshot.apply(
      event('4', AdaptiveManagementEventKind.managementActivated),
    );

    expect(afterTerminal.state, AdaptiveManagementState.exited);
    expect(afterTerminal.revision, revision);
    expect(afterTerminal.processedEventIds, contains('4'));
  });

  test('long stop widening is rejected', () {
    final decision = AdaptiveManagementInvariants.evaluateProtectionMutation(
      direction: TradeDirection.long,
      currentConfirmedStop: 95,
      proposedStop: 94,
      currentQuantity: 1,
      proposedQuantity: 1,
    );

    expect(decision.allowed, isFalse);
    expect(decision.reason, ManagementInvariantReason.stopWouldWiden);
  });

  test('short stop widening is rejected', () {
    final decision = AdaptiveManagementInvariants.evaluateProtectionMutation(
      direction: TradeDirection.short,
      currentConfirmedStop: 105,
      proposedStop: 106,
      currentQuantity: 1,
      proposedQuantity: 1,
    );

    expect(decision.allowed, isFalse);
    expect(decision.reason, ManagementInvariantReason.stopWouldWiden);
  });

  test('post-entry exposure increase is rejected', () {
    final decision = AdaptiveManagementInvariants.evaluateProtectionMutation(
      direction: TradeDirection.long,
      currentConfirmedStop: 95,
      proposedStop: 96,
      currentQuantity: 1,
      proposedQuantity: 1.01,
    );

    expect(decision.allowed, isFalse);
    expect(decision.reason, ManagementInvariantReason.exposureWouldIncrease);
  });

  test('tighter stop with reduced exposure is allowed', () {
    final longDecision =
        AdaptiveManagementInvariants.evaluateProtectionMutation(
          direction: TradeDirection.long,
          currentConfirmedStop: 95,
          proposedStop: 96,
          currentQuantity: 1,
          proposedQuantity: 0.5,
        );
    final shortDecision =
        AdaptiveManagementInvariants.evaluateProtectionMutation(
          direction: TradeDirection.short,
          currentConfirmedStop: 105,
          proposedStop: 104,
          currentQuantity: 1,
          proposedQuantity: 0.5,
        );

    expect(longDecision.allowed, isTrue);
    expect(shortDecision.allowed, isTrue);
  });
}
