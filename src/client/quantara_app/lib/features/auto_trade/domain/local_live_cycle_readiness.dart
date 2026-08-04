enum LocalLiveCycleReadiness {
  ready,
  emptyAccountHistoryPending,
  managedExposureHistoryBlocked,
  unmanagedExposureBlocked,
}

/// Separates entry readiness from historical PnL availability. Missing history
/// is informational only when both the exchange and Local Live are flat, while
/// any known exchange exposure keeps the guarded entry path fail-closed.
abstract final class LocalLiveCycleReadinessPolicy {
  static LocalLiveCycleReadiness evaluate({
    required bool hasManagedExposure,
    required bool hasUnmanagedExchangeExposure,
    required bool pnlVerified,
    required bool fillsAvailable,
  }) {
    if (hasUnmanagedExchangeExposure) {
      return LocalLiveCycleReadiness.unmanagedExposureBlocked;
    }
    final historyReady = pnlVerified && fillsAvailable;
    if (hasManagedExposure && !historyReady) {
      return LocalLiveCycleReadiness.managedExposureHistoryBlocked;
    }
    if (!hasManagedExposure && !historyReady) {
      return LocalLiveCycleReadiness.emptyAccountHistoryPending;
    }
    return LocalLiveCycleReadiness.ready;
  }

  static bool blocksNewEntries(LocalLiveCycleReadiness readiness) =>
      switch (readiness) {
        LocalLiveCycleReadiness.managedExposureHistoryBlocked ||
        LocalLiveCycleReadiness.unmanagedExposureBlocked => true,
        LocalLiveCycleReadiness.ready ||
        LocalLiveCycleReadiness.emptyAccountHistoryPending => false,
      };
}
