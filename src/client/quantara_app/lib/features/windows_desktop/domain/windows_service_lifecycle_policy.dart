/// Fail-closed lifecycle policy for Windows service interruption boundaries.
///
/// Sleep, hibernate and network loss can make local market/account state stale.
/// The service therefore must not treat a resume/reconnect as continuity of
/// execution authority. Exchange-native protection remains authoritative while
/// local management is unavailable, and a fresh reconciliation is required
/// before the owner can explicitly re-arm new entries.
enum WindowsServiceLifecycleEvent {
  sleep,
  hibernate,
  networkLost,
  wake,
  networkRestored,
}

enum WindowsServiceLifecycleMode { interrupted, reconciliationOnly, disarmed }

final class WindowsServiceLifecycleSnapshot {
  const WindowsServiceLifecycleSnapshot({
    required this.event,
    required this.mode,
    required this.warningRequired,
    required this.blocksNewEntries,
    required this.canManageExistingPositions,
    required this.reconciliationRequired,
    required this.requiresExplicitStart,
  });

  final WindowsServiceLifecycleEvent event;
  final WindowsServiceLifecycleMode mode;
  final bool warningRequired;
  final bool blocksNewEntries;
  final bool canManageExistingPositions;
  final bool reconciliationRequired;
  final bool requiresExplicitStart;
}

final class WindowsServiceLifecyclePolicy {
  const WindowsServiceLifecyclePolicy._();

  static const _interruptionEvents = <WindowsServiceLifecycleEvent>{
    WindowsServiceLifecycleEvent.sleep,
    WindowsServiceLifecycleEvent.hibernate,
    WindowsServiceLifecycleEvent.networkLost,
  };

  static WindowsServiceLifecycleSnapshot resolve({
    required WindowsServiceLifecycleEvent event,
    required bool hasExchangeReportedOpenPositions,
  }) {
    final interruption = _interruptionEvents.contains(event);

    if (interruption) {
      return WindowsServiceLifecycleSnapshot(
        event: event,
        mode: WindowsServiceLifecycleMode.interrupted,
        warningRequired: true,
        blocksNewEntries: true,
        canManageExistingPositions: false,
        reconciliationRequired: true,
        requiresExplicitStart: true,
      );
    }

    return WindowsServiceLifecycleSnapshot(
      event: event,
      mode: hasExchangeReportedOpenPositions
          ? WindowsServiceLifecycleMode.reconciliationOnly
          : WindowsServiceLifecycleMode.disarmed,
      warningRequired: true,
      blocksNewEntries: true,
      canManageExistingPositions: false,
      reconciliationRequired: true,
      requiresExplicitStart: true,
    );
  }
}
