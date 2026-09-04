enum GlobalPauseRuntimeMode {
  running,
  safePausedManagingExisting,
  pausedOffline,
  resuming,
}

final class GlobalPauseRuntimeEvidence {
  const GlobalPauseRuntimeEvidence({
    required this.openPositionCount,
    required this.openOrderCount,
    required this.protectionVerified,
    required this.accountFresh,
    required this.reconciliationHealthy,
  });

  final int openPositionCount;
  final int openOrderCount;
  final bool protectionVerified;
  final bool accountFresh;
  final bool reconciliationHealthy;

  bool get hasExposure => openPositionCount > 0 || openOrderCount > 0;
}

/// Fail-closed policy for deciding whether Quantara may become fully offline
/// or must keep minimum existing-position management alive.
final class GlobalPauseRuntimePolicy {
  const GlobalPauseRuntimePolicy();

  GlobalPauseRuntimeMode pause(GlobalPauseRuntimeEvidence evidence) {
    if (!evidence.hasExposure) return GlobalPauseRuntimeMode.pausedOffline;
    return GlobalPauseRuntimeMode.safePausedManagingExisting;
  }

  bool mayStopScanning(GlobalPauseRuntimeMode mode) =>
      mode == GlobalPauseRuntimeMode.safePausedManagingExisting ||
      mode == GlobalPauseRuntimeMode.pausedOffline;

  bool mayStopNonEssentialNetwork(GlobalPauseRuntimeMode mode) =>
      mode == GlobalPauseRuntimeMode.safePausedManagingExisting ||
      mode == GlobalPauseRuntimeMode.pausedOffline;

  bool mustKeepPrivateManagement(GlobalPauseRuntimeMode mode) =>
      mode == GlobalPauseRuntimeMode.safePausedManagingExisting;

  bool mayStopBackgroundService(GlobalPauseRuntimeMode mode) =>
      mode == GlobalPauseRuntimeMode.pausedOffline;

  GlobalPauseRuntimeMode? beginResume(GlobalPauseRuntimeEvidence evidence) {
    if (!evidence.accountFresh || !evidence.reconciliationHealthy) return null;
    if (evidence.hasExposure && !evidence.protectionVerified) return null;
    return GlobalPauseRuntimeMode.resuming;
  }

  GlobalPauseRuntimeMode finishResume({
    required GlobalPauseRuntimeMode current,
    required GlobalPauseRuntimeEvidence evidence,
  }) {
    if (current != GlobalPauseRuntimeMode.resuming ||
        !evidence.accountFresh ||
        !evidence.reconciliationHealthy ||
        (evidence.hasExposure && !evidence.protectionVerified)) {
      return evidence.hasExposure
          ? GlobalPauseRuntimeMode.safePausedManagingExisting
          : GlobalPauseRuntimeMode.pausedOffline;
    }
    return GlobalPauseRuntimeMode.running;
  }
}
