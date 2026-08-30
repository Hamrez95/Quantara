import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/domain/private_account_entry_block_policy.dart';
import 'package:quantara_app/features/auto_trade/domain/private_account_reconciliation.dart';

void main() {
  test('refreshing and transient stale projections preserve armed intent', () {
    expect(
      PrivateAccountEntryBlockPolicy.evaluate(
        explicitlyDisconnected: false,
        refreshing: true,
        health: PrivateAccountReconciliationHealth.unavailable,
      ),
      PrivateAccountEntryBlockDecision.none,
    );
    expect(
      PrivateAccountEntryBlockPolicy.evaluate(
        explicitlyDisconnected: false,
        refreshing: false,
        health: PrivateAccountReconciliationHealth.stale,
      ),
      PrivateAccountEntryBlockDecision.transientProjectionWarning,
    );
    expect(
      PrivateAccountEntryBlockPolicy.evaluate(
        explicitlyDisconnected: false,
        refreshing: false,
        health: PrivateAccountReconciliationHealth.unavailable,
      ),
      PrivateAccountEntryBlockDecision.transientProjectionWarning,
    );
  });

  test('disconnect and divergent exchange truth remain hard blocks', () {
    expect(
      PrivateAccountEntryBlockPolicy.evaluate(
        explicitlyDisconnected: true,
        refreshing: false,
        health: PrivateAccountReconciliationHealth.unavailable,
      ),
      PrivateAccountEntryBlockDecision.hardBlockDisconnected,
    );
    expect(
      PrivateAccountEntryBlockPolicy.evaluate(
        explicitlyDisconnected: false,
        refreshing: true,
        health: PrivateAccountReconciliationHealth.divergent,
      ),
      PrivateAccountEntryBlockDecision.hardBlockDivergent,
    );
  });

  test('fresh coherent projection requires no controller intervention', () {
    expect(
      PrivateAccountEntryBlockPolicy.evaluate(
        explicitlyDisconnected: false,
        refreshing: false,
        health: PrivateAccountReconciliationHealth.fresh,
      ),
      PrivateAccountEntryBlockDecision.none,
    );
  });
}
