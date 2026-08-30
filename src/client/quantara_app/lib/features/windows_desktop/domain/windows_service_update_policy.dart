/// Fail-closed coordination policy for a Windows application/service update.
///
/// This is a domain contract only. It never starts an installer, service, or
/// trading engine. Exchange-native protection remains authoritative while the
/// local service is unavailable, and no update transition may silently restore
/// new-entry authority.
enum WindowsServiceUpdateEvent {
  updateRequested,
  serviceStoppedForInstall,
  installSucceeded,
  installFailed,
  reconciliationSucceeded,
  reconciliationFailed,
}

enum WindowsServiceUpdateMode {
  preparing,
  installing,
  reconciliationOnly,
  managingExisting,
  rollbackRequired,
  disarmed,
  blocked,
}

final class WindowsServiceUpdateSnapshot {
  const WindowsServiceUpdateSnapshot({
    required this.event,
    required this.mode,
    required this.blocksNewEntries,
    required this.localManagementAvailable,
    required this.exchangeProtectionAuthoritative,
    required this.reconciliationRequired,
    required this.rollbackRequired,
    required this.requiresExplicitStart,
  });

  final WindowsServiceUpdateEvent event;
  final WindowsServiceUpdateMode mode;
  final bool blocksNewEntries;
  final bool localManagementAvailable;
  final bool exchangeProtectionAuthoritative;
  final bool reconciliationRequired;
  final bool rollbackRequired;
  final bool requiresExplicitStart;
}

final class WindowsServiceUpdatePolicy {
  const WindowsServiceUpdatePolicy._();

  static WindowsServiceUpdateSnapshot resolve({
    required WindowsServiceUpdateEvent event,
    required bool hasExchangeReportedOpenPositions,
    required bool hasVerifiedQuantaraManagedOpenPositions,
    required bool managementExecutorAvailable,
  }) {
    switch (event) {
      case WindowsServiceUpdateEvent.updateRequested:
        return _snapshot(event, WindowsServiceUpdateMode.preparing);
      case WindowsServiceUpdateEvent.serviceStoppedForInstall:
        return _snapshot(event, WindowsServiceUpdateMode.installing);
      case WindowsServiceUpdateEvent.installSucceeded:
        return _snapshot(
          event,
          WindowsServiceUpdateMode.reconciliationOnly,
          reconciliationRequired: true,
        );
      case WindowsServiceUpdateEvent.installFailed:
        return _snapshot(
          event,
          WindowsServiceUpdateMode.rollbackRequired,
          rollbackRequired: true,
          reconciliationRequired: true,
        );
      case WindowsServiceUpdateEvent.reconciliationFailed:
        return _snapshot(
          event,
          WindowsServiceUpdateMode.blocked,
          reconciliationRequired: true,
        );
      case WindowsServiceUpdateEvent.reconciliationSucceeded:
        return _resolveReconciled(
          event: event,
          hasExchangeReportedOpenPositions: hasExchangeReportedOpenPositions,
          hasVerifiedQuantaraManagedOpenPositions:
              hasVerifiedQuantaraManagedOpenPositions,
          managementExecutorAvailable: managementExecutorAvailable,
        );
    }
  }

  static WindowsServiceUpdateSnapshot _resolveReconciled({
    required WindowsServiceUpdateEvent event,
    required bool hasExchangeReportedOpenPositions,
    required bool hasVerifiedQuantaraManagedOpenPositions,
    required bool managementExecutorAvailable,
  }) {
    if (!hasExchangeReportedOpenPositions &&
        !hasVerifiedQuantaraManagedOpenPositions) {
      return _snapshot(event, WindowsServiceUpdateMode.disarmed);
    }

    final canManageVerifiedExisting = hasExchangeReportedOpenPositions &&
        hasVerifiedQuantaraManagedOpenPositions &&
        managementExecutorAvailable;
    if (canManageVerifiedExisting) {
      return _snapshot(
        event,
        WindowsServiceUpdateMode.managingExisting,
        localManagementAvailable: true,
      );
    }

    // Any position that cannot be proven Quantara-owned, any contradictory
    // ownership/exchange truth, or a missing runtime executor remains blocked.
    // The caller must reconcile again instead of widening local authority.
    return _snapshot(
      event,
      WindowsServiceUpdateMode.blocked,
      reconciliationRequired: true,
    );
  }

  static WindowsServiceUpdateSnapshot _snapshot(
    WindowsServiceUpdateEvent event,
    WindowsServiceUpdateMode mode, {
    bool localManagementAvailable = false,
    bool reconciliationRequired = false,
    bool rollbackRequired = false,
  }) => WindowsServiceUpdateSnapshot(
    event: event,
    mode: mode,
    blocksNewEntries: true,
    localManagementAvailable: localManagementAvailable,
    exchangeProtectionAuthoritative: true,
    reconciliationRequired: reconciliationRequired,
    rollbackRequired: rollbackRequired,
    requiresExplicitStart: true,
  );
}
