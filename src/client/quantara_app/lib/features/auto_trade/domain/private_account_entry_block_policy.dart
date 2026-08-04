import 'private_account_reconciliation.dart';

enum PrivateAccountEntryBlockDecision {
  none,
  transientProjectionWarning,
  hardBlockDisconnected,
  hardBlockDivergent,
}

abstract final class PrivateAccountEntryBlockPolicy {
  static PrivateAccountEntryBlockDecision evaluate({
    required bool explicitlyDisconnected,
    required bool refreshing,
    required PrivateAccountReconciliationHealth health,
  }) {
    if (explicitlyDisconnected) {
      return PrivateAccountEntryBlockDecision.hardBlockDisconnected;
    }
    if (health == PrivateAccountReconciliationHealth.divergent) {
      return PrivateAccountEntryBlockDecision.hardBlockDivergent;
    }
    if (refreshing) {
      return PrivateAccountEntryBlockDecision.none;
    }
    return switch (health) {
      PrivateAccountReconciliationHealth.fresh =>
        PrivateAccountEntryBlockDecision.none,
      PrivateAccountReconciliationHealth.stale ||
      PrivateAccountReconciliationHealth.unavailable =>
        PrivateAccountEntryBlockDecision.transientProjectionWarning,
      PrivateAccountReconciliationHealth.divergent =>
        PrivateAccountEntryBlockDecision.hardBlockDivergent,
    };
  }
}
