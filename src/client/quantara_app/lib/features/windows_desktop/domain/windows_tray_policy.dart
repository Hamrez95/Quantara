enum WindowsServiceRuntimeState {
  stopped,
  starting,
  reconciling,
  monitoring,
  managing,
  circuitBreaker,
}

enum WindowsTrayAction { open, stopEntries, emergencyClose }

final class WindowsTrayPolicy {
  const WindowsTrayPolicy._();

  static Set<WindowsTrayAction> actionsFor(
    WindowsServiceRuntimeState state, {
    required bool emergencyCloseExplicitlyEnabled,
  }) {
    final actions = <WindowsTrayAction>{WindowsTrayAction.open};

    if (state == WindowsServiceRuntimeState.monitoring ||
        state == WindowsServiceRuntimeState.managing) {
      actions.add(WindowsTrayAction.stopEntries);
    }

    if (state == WindowsServiceRuntimeState.managing &&
        emergencyCloseExplicitlyEnabled) {
      actions.add(WindowsTrayAction.emergencyClose);
    }

    return Set.unmodifiable(actions);
  }

  static bool requiresConfirmation(WindowsTrayAction action) =>
      action == WindowsTrayAction.emergencyClose;
}
