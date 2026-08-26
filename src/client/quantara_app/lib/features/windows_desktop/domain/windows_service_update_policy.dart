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
        return _snapshot(
          event,
          hasExchangeReportedOpenPositions
              ? WindowsServiceUpdateMode.reconciliationOnly
              : WindowsServiceUpdateMode.disarmed,
          reconciliationRequired: hasExchangeReportedOpenPositions,
        );
    }
  }

  static WindowsServiceUpdateSnapshot _snapshot(
    WindowsServiceUpdateEvent event,
    WindowsServiceUpdateMode mode, {
    bool reconciliationRequired = false,
    bool rollbackRequired = false,
  }) => WindowsServiceUpdateSnapshot(
    event: event,
    mode: mode,
    blocksNewEntries: true,
    localManagementAvailable: false,
    exchangeProtectionAuthoritative: true,
    reconciliationRequired: reconciliationRequired,
    rollbackRequired: rollbackRequired,
    requiresExplicitStart: true,
  );
}
