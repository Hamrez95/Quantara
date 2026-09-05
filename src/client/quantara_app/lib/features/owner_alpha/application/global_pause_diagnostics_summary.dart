import 'global_pause_observability.dart';
import 'global_pause_runtime_policy.dart';

/// Compact, secret-free diagnostics snapshot for Global Pause.
///
/// This is intentionally observational only. It never mutates runtime state,
/// grants order authority, or infers exchange protection that was not supplied
/// by authoritative runtime evidence.
final class GlobalPauseDiagnosticsSummary {
  const GlobalPauseDiagnosticsSummary({
    required this.mode,
    required this.activity,
    required this.openPositionCount,
    required this.openOrderCount,
    required this.protectionVerified,
    required this.reasonCode,
  });

  final GlobalPauseRuntimeMode mode;
  final GlobalPauseActivitySnapshot activity;
  final int openPositionCount;
  final int openOrderCount;
  final bool protectionVerified;
  final String reasonCode;

  bool get scanningActive => activity.activeScanners > 0;
  bool get subscriptionsActive => activity.activeSubscriptions > 0;
  bool get timersActive => activity.activeTimers > 0;
  bool get backgroundServiceActive => activity.backgroundServiceActive;

  /// Full Offline Pause is only healthy when every non-essential activity
  /// reported by the runtime is quiesced. Unknown/active work fails closed.
  bool get fullOfflineQuiesced =>
      mode == GlobalPauseRuntimeMode.pausedOffline &&
      !scanningActive &&
      !subscriptionsActive &&
      !timersActive &&
      !backgroundServiceActive;

  /// Safe Pause may retain minimum management runtime while exposure exists,
  /// but scanners must still remain stopped.
  bool get safePauseInvariantSatisfied =>
      mode == GlobalPauseRuntimeMode.safePausedManagingExisting &&
      !scanningActive &&
      (openPositionCount > 0 || openOrderCount > 0);

  bool get pauseInvariantSatisfied => switch (mode) {
    GlobalPauseRuntimeMode.pausedOffline => fullOfflineQuiesced,
    GlobalPauseRuntimeMode.safePausedManagingExisting =>
      safePauseInvariantSatisfied,
    GlobalPauseRuntimeMode.resuming => !scanningActive,
    GlobalPauseRuntimeMode.running => true,
  };

  Map<String, Object?> toJson() => <String, Object?>{
    'mode': mode.name,
    'openPositionCount': openPositionCount,
    'openOrderCount': openOrderCount,
    'protectionVerified': protectionVerified,
    'reasonCode': reasonCode,
    'scanningActive': scanningActive,
    'subscriptionsActive': subscriptionsActive,
    'timersActive': timersActive,
    'backgroundServiceActive': backgroundServiceActive,
    'fullOfflineQuiesced': fullOfflineQuiesced,
    'pauseInvariantSatisfied': pauseInvariantSatisfied,
  };

  factory GlobalPauseDiagnosticsSummary.fromEvent(GlobalPauseEvent event) =>
      GlobalPauseDiagnosticsSummary(
        mode: event.newState,
        activity: event.activity,
        openPositionCount: event.openPositionCount,
        openOrderCount: event.openOrderCount,
        protectionVerified: event.protectionVerified,
        reasonCode: event.reasonCode,
      );
}
