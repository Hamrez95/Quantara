enum LocalLiveCycleReadiness {
  ready,
  emptyAccountHistoryPending,
  managedExposureHistoryBlocked,
  unmanagedExposureBlocked,
}

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

  static bool blocksNewEntries(LocalLiveCycleReadiness readiness) => switch (
    readiness
  ) {
    LocalLiveCycleReadiness.managedExposureHistoryBlocked ||
    LocalLiveCycleReadiness.unmanagedExposureBlocked => true,
    LocalLiveCycleReadiness.ready ||
    LocalLiveCycleReadiness.emptyAccountHistoryPending => false,
  };
}
