enum WindowsServiceStartupReason {
  coldLaunch,
  reboot,
  serviceRestart,
  appUpdate,
  crashRecovery,
}

enum WindowsServiceAuthorityState { disarmed, monitoring, reconciliationOnly }

final class WindowsServiceStartupSnapshot {
  const WindowsServiceStartupSnapshot({
    required this.reason,
    required this.authority,
    required this.requiresExplicitStart,
    required this.reconciliationRequired,
  });

  final WindowsServiceStartupReason reason;
  final WindowsServiceAuthorityState authority;
  final bool requiresExplicitStart;
  final bool reconciliationRequired;
}

/// Fail-closed startup policy for the future Windows background service.
///
/// Persisted state must never restore new-entry authority after a process,
/// service, device or update boundary. Exchange-reported positions only grant
/// enough authority to reconcile truth; ownership/protection must be verified
/// separately before any management path can be enabled.
final class WindowsServiceStartupPolicy {
  const WindowsServiceStartupPolicy._();

  static WindowsServiceStartupSnapshot resolve({
    required WindowsServiceStartupReason reason,
    required bool hasExchangeReportedOpenPositions,
  }) {
    if (hasExchangeReportedOpenPositions) {
      return WindowsServiceStartupSnapshot(
        reason: reason,
        authority: WindowsServiceAuthorityState.reconciliationOnly,
        requiresExplicitStart: true,
        reconciliationRequired: true,
      );
    }

    return WindowsServiceStartupSnapshot(
      reason: reason,
      authority: WindowsServiceAuthorityState.disarmed,
      requiresExplicitStart: true,
      reconciliationRequired: reason != WindowsServiceStartupReason.coldLaunch,
    );
  }
}
