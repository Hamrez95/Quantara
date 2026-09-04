import 'global_pause_observability.dart';
import 'global_pause_runtime_coordinator.dart';
import 'global_pause_runtime_policy.dart';

typedef GlobalPauseEvidenceRefresh = Future<GlobalPauseRuntimeEvidence> Function();
typedef GlobalPauseRuntimeAction = Future<void> Function();
typedef GlobalPauseActivityRead = Future<GlobalPauseActivitySnapshot> Function();

/// Concrete bridge between [GlobalPauseRuntimeCoordinator] and the real
/// Local Live / Owner Alpha runtime owners.
///
/// The bridge deliberately receives explicit delegates instead of owning any
/// exchange client. This keeps pause authority limited to quiescing runtime
/// work; it cannot place, amend, cancel, or synthesize exchange orders/fills.
final class GlobalPauseRuntimeOperationsAdapter
    implements GlobalPauseRuntimeOperations {
  const GlobalPauseRuntimeOperationsAdapter({
    required this.refreshEvidence,
    required this.stopScanning,
    required this.stopNonEssentialNetwork,
    required this.keepManagementOnly,
    required this.stopBackground,
    required this.prepareForResume,
    required this.readActivity,
  });

  final GlobalPauseEvidenceRefresh refreshEvidence;
  final GlobalPauseRuntimeAction stopScanning;
  final GlobalPauseRuntimeAction stopNonEssentialNetwork;
  final GlobalPauseRuntimeAction keepManagementOnly;
  final GlobalPauseRuntimeAction stopBackground;
  final GlobalPauseRuntimeAction prepareForResume;
  final GlobalPauseActivityRead readActivity;

  @override
  Future<GlobalPauseRuntimeEvidence> refreshAuthoritativeEvidence() =>
      refreshEvidence();

  @override
  Future<void> stopScanningAndCandidateWork() => stopScanning();

  @override
  Future<void> stopNonEssentialNetworkWork() => stopNonEssentialNetwork();

  @override
  Future<void> keepPrivateManagementOnly() => keepManagementOnly();

  @override
  Future<void> stopBackgroundService() => stopBackground();

  @override
  Future<void> prepareNonEssentialRuntimeForResume() => prepareForResume();

  @override
  Future<GlobalPauseActivitySnapshot> activitySnapshot() => readActivity();
}

/// Small activity counter used by production adapters and tests to expose the
/// exact work that remains alive while Global Pause is active.
///
/// Counts are clamped at zero so duplicate cleanup is observable but cannot
/// produce misleading negative activity in diagnostics.
final class GlobalPauseActivityTracker {
  int _activeScanners = 0;
  int _activeSubscriptions = 0;
  int _activeTimers = 0;
  bool _backgroundServiceActive = false;

  void scannerStarted() => _activeScanners += 1;
  void scannerStopped() => _activeScanners = _decrement(_activeScanners);
  void subscriptionStarted() => _activeSubscriptions += 1;
  void subscriptionStopped() =>
      _activeSubscriptions = _decrement(_activeSubscriptions);
  void timerStarted() => _activeTimers += 1;
  void timerStopped() => _activeTimers = _decrement(_activeTimers);
  void setBackgroundServiceActive(bool active) =>
      _backgroundServiceActive = active;

  GlobalPauseActivitySnapshot snapshot() => GlobalPauseActivitySnapshot(
    activeScanners: _activeScanners,
    activeSubscriptions: _activeSubscriptions,
    activeTimers: _activeTimers,
    backgroundServiceActive: _backgroundServiceActive,
  );

  int _decrement(int value) => value <= 0 ? 0 : value - 1;
}
