import 'windows_tray_policy.dart';

/// Explicit policy for UI close/minimize behavior while the native Windows
/// service owns background lifecycle state.
///
/// This policy never grants execution authority and never stops a managing
/// service implicitly. Native window/tray wiring must consume this result
/// rather than terminating the process/service directly.
enum WindowsWindowCloseDisposition {
  exitUi,
  minimizeToTray,
  requireConfirmation,
}

final class WindowsWindowCloseDecision {
  const WindowsWindowCloseDecision({
    required this.disposition,
    required this.serviceContinues,
    required this.blocksImplicitServiceStop,
  });

  final WindowsWindowCloseDisposition disposition;
  final bool serviceContinues;
  final bool blocksImplicitServiceStop;
}

final class WindowsWindowClosePolicy {
  const WindowsWindowClosePolicy._();

  static WindowsWindowCloseDecision resolve({
    required WindowsServiceRuntimeState serviceState,
    required bool trayAvailable,
  }) {
    switch (serviceState) {
      case WindowsServiceRuntimeState.monitoring:
      case WindowsServiceRuntimeState.managing:
      case WindowsServiceRuntimeState.reconciling:
      case WindowsServiceRuntimeState.circuitBreaker:
        if (trayAvailable) {
          return const WindowsWindowCloseDecision(
            disposition: WindowsWindowCloseDisposition.minimizeToTray,
            serviceContinues: true,
            blocksImplicitServiceStop: true,
          );
        }
        return const WindowsWindowCloseDecision(
          disposition: WindowsWindowCloseDisposition.requireConfirmation,
          serviceContinues: true,
          blocksImplicitServiceStop: true,
        );
      case WindowsServiceRuntimeState.starting:
        return const WindowsWindowCloseDecision(
          disposition: WindowsWindowCloseDisposition.requireConfirmation,
          serviceContinues: true,
          blocksImplicitServiceStop: true,
        );
      case WindowsServiceRuntimeState.stopped:
        return const WindowsWindowCloseDecision(
          disposition: WindowsWindowCloseDisposition.exitUi,
          serviceContinues: false,
          blocksImplicitServiceStop: true,
        );
    }
  }
}
