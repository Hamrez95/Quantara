import 'private_account_reconciliation.dart';

enum PrivateAccountEntryBlockDecision {
  none,
  transientProjectionWarning,
  hardBlockDisconnected,
  hardBlockDivergent,
}

abstract final class PrivateAccountEntryBlockPolicy {
  static PrivateAccountEntryBlockDecision evaluate({
    required bool connected,
    required PrivateAccountReconciliationState reconciliation,
  }) {
    if (!connected) {
      return PrivateAccountEntryBlockDecision.hardBlockDisconnected;
    }
    if (reconciliation.refreshing) {
      return PrivateAccountEntryBlockDecision.none;
    }
    return switch (reconciliation.health) {
      PrivateAccountReconciliationHealth.fresh =>
        PrivateAccountEntryBlockDecision.none,
      PrivateAccountReconciliationHealth.divergent =>
        PrivateAccountEntryBlockDecision.hardBlockDivergent,
      PrivateAccountReconciliationHealth.stale ||
      PrivateAccountReconciliationHealth.unavailable =>
        PrivateAccountEntryBlockDecision.transientProjectionWarning,
    };
  }
}
