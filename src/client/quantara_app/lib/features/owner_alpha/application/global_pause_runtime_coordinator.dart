import '../data/durable_global_pause_runtime_store.dart';
import 'global_pause_observability.dart';
import 'global_pause_runtime_policy.dart';

abstract interface class GlobalPauseRuntimeOperations {
  /// Returns fresh private/account truth. Implementations must never fabricate
  /// exposure, reconciliation, or protection evidence.
  Future<GlobalPauseRuntimeEvidence> refreshAuthoritativeEvidence();

  Future<void> stopScanningAndCandidateWork();

  Future<void> stopNonEssentialNetworkWork();

  Future<void> keepPrivateManagementOnly();

  Future<void> stopBackgroundService();

  /// Recreates only the non-entry runtime required before a final transition
  /// to running. This method must not arm the robot or grant order authority.
  Future<void> prepareNonEssentialRuntimeForResume();

  Future<GlobalPauseActivitySnapshot> activitySnapshot();
}

abstract interface class GlobalPauseEventSink {
  Future<void> record(GlobalPauseEvent event);
}

final class NoopGlobalPauseEventSink implements GlobalPauseEventSink {
  const NoopGlobalPauseEventSink();

  @override
  Future<void> record(GlobalPauseEvent event) async {}
}

/// Serialized runtime owner for Global Pause.
///
/// The coordinator deliberately has no exchange/order mutation API. It can
/// quiesce scanning/network/background work and re-create non-entry runtime,
/// but resuming execution authority remains owned by the existing Guarded Auto
/// admission/risk state machine.
final class GlobalPauseRuntimeCoordinator {
  GlobalPauseRuntimeCoordinator({
    required this.store,
    required this.operations,
    required this.sessionId,
    this.policy = const GlobalPauseRuntimePolicy(),
    this.events = const NoopGlobalPauseEventSink(),
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  final DurableGlobalPauseRuntimeStore store;
  final GlobalPauseRuntimeOperations operations;
  final GlobalPauseRuntimePolicy policy;
  final GlobalPauseEventSink events;
  final String sessionId;
  final DateTime Function() clock;

  GlobalPauseRuntimeMode _mode = GlobalPauseRuntimeMode.running;
  bool _pauseFullyWhenFlat = false;
  Future<void> _tail = Future<void>.value();
  bool _initialized = false;

  GlobalPauseRuntimeMode get mode => _mode;
  bool get pauseFullyWhenFlat => _pauseFullyWhenFlat;
  bool get initialized => _initialized;
  bool get blocksNewScanning => _mode != GlobalPauseRuntimeMode.running;

  Future<void> initialize() => _serialize(() async {
    if (_initialized) return;
    final restored = await store.restore();
    _mode = restored.mode;
    _pauseFullyWhenFlat = restored.pauseFullyWhenFlat;
    _initialized = true;

    if (_mode != GlobalPauseRuntimeMode.running) {
      await _applyPausedRuntime(_mode);
    }
  });

  Future<void> requestPause({bool pauseFullyWhenFlat = false}) =>
      _serialize(() async {
        _requireInitialized();
        final previous = _mode;
        final evidence = await operations.refreshAuthoritativeEvidence();
        await _record(
          GlobalPauseEventType.requested,
          previous: previous,
          next: previous,
          evidence: evidence,
          reasonCode: 'user_requested',
        );

        _pauseFullyWhenFlat = pauseFullyWhenFlat;
        final next = policy.pause(evidence);
        await _applyPausedRuntime(next);
        _mode = next;
        await store.persist(
          mode: _mode,
          pauseFullyWhenFlat: _pauseFullyWhenFlat,
          updatedAtUtc: clock().toUtc(),
        );
        await _record(
          GlobalPauseEventType.entered,
          previous: previous,
          next: next,
          evidence: evidence,
          reasonCode: next == GlobalPauseRuntimeMode.pausedOffline
              ? 'flat_full_offline'
              : 'live_management_required',
        );
        await _record(
          next == GlobalPauseRuntimeMode.pausedOffline
              ? GlobalPauseEventType.fullOfflineEntered
              : GlobalPauseEventType.deferredForLiveManagement,
          previous: previous,
          next: next,
          evidence: evidence,
          reasonCode: next == GlobalPauseRuntimeMode.pausedOffline
              ? 'flat_full_offline'
              : 'live_management_required',
        );
      });

  Future<void> setPauseFullyWhenFlat(bool enabled) => _serialize(() async {
    _requireInitialized();
    _pauseFullyWhenFlat = enabled;
    await store.persist(
      mode: _mode,
      pauseFullyWhenFlat: enabled,
      updatedAtUtc: clock().toUtc(),
    );
    if (!enabled ||
        _mode != GlobalPauseRuntimeMode.safePausedManagingExisting) {
      return;
    }
    await _reconcilePausedExposureLocked();
  });

  Future<void> reconcilePausedExposure() => _serialize(() async {
    _requireInitialized();
    await _reconcilePausedExposureLocked();
  });

  Future<void> _reconcilePausedExposureLocked() async {
    if (_mode != GlobalPauseRuntimeMode.safePausedManagingExisting ||
        !_pauseFullyWhenFlat) {
      return;
    }
    final evidence = await operations.refreshAuthoritativeEvidence();
    if (evidence.hasExposure) return;

    final previous = _mode;
    await _applyPausedRuntime(GlobalPauseRuntimeMode.pausedOffline);
    _mode = GlobalPauseRuntimeMode.pausedOffline;
    await store.persist(
      mode: _mode,
      pauseFullyWhenFlat: true,
      updatedAtUtc: clock().toUtc(),
    );
    await _record(
      GlobalPauseEventType.fullOfflineEntered,
      previous: previous,
      next: _mode,
      evidence: evidence,
      reasonCode: 'became_flat',
    );
  }

  /// Explicit resume only. Fresh authoritative reconciliation is obtained
  /// first; any failure leaves the runtime paused. This never arms Guarded Auto.
  Future<bool> requestResume() async {
    var resumed = false;
    await _serialize(() async {
      _requireInitialized();
      final previous = _mode;
      final evidence = await operations.refreshAuthoritativeEvidence();
      await _record(
        GlobalPauseEventType.resumeRequested,
        previous: previous,
        next: previous,
        evidence: evidence,
        reasonCode: 'user_requested',
      );

      final resuming = policy.beginResume(evidence);
      if (resuming == null) {
        await _applyPausedRuntime(previous);
        await _record(
          GlobalPauseEventType.resumeValidationFailed,
          previous: previous,
          next: previous,
          evidence: evidence,
          reasonCode: _resumeFailureReason(evidence),
        );
        return;
      }

      _mode = resuming;
      await store.persist(
        mode: _mode,
        pauseFullyWhenFlat: _pauseFullyWhenFlat,
        updatedAtUtc: clock().toUtc(),
      );

      try {
        await operations.prepareNonEssentialRuntimeForResume();
        final validated = await operations.refreshAuthoritativeEvidence();
        final next = policy.finishResume(current: _mode, evidence: validated);
        if (next != GlobalPauseRuntimeMode.running) {
          await _applyPausedRuntime(next);
          _mode = next;
          await store.persist(
            mode: _mode,
            pauseFullyWhenFlat: _pauseFullyWhenFlat,
            updatedAtUtc: clock().toUtc(),
          );
          await _record(
            GlobalPauseEventType.resumeValidationFailed,
            previous: previous,
            next: next,
            evidence: validated,
            reasonCode: _resumeFailureReason(validated),
          );
          return;
        }

        _mode = GlobalPauseRuntimeMode.running;
        _pauseFullyWhenFlat = false;
        await store.persist(
          mode: _mode,
          pauseFullyWhenFlat: false,
          updatedAtUtc: clock().toUtc(),
        );
        await _record(
          GlobalPauseEventType.resumeCompleted,
          previous: previous,
          next: _mode,
          evidence: validated,
          reasonCode: 'validated',
        );
        resumed = true;
      } on Object {
        final fallback = evidence.hasExposure
            ? GlobalPauseRuntimeMode.safePausedManagingExisting
            : GlobalPauseRuntimeMode.pausedOffline;
        await _applyPausedRuntime(fallback);
        _mode = fallback;
        await store.persist(
          mode: _mode,
          pauseFullyWhenFlat: _pauseFullyWhenFlat,
          updatedAtUtc: clock().toUtc(),
        );
        await _record(
          GlobalPauseEventType.resumeValidationFailed,
          previous: previous,
          next: fallback,
          evidence: evidence,
          reasonCode: 'runtime_prepare_failed',
        );
      }
    });
    return resumed;
  }

  Future<void> _applyPausedRuntime(GlobalPauseRuntimeMode mode) async {
    await operations.stopScanningAndCandidateWork();
    await operations.stopNonEssentialNetworkWork();
    if (mode == GlobalPauseRuntimeMode.pausedOffline) {
      await operations.stopBackgroundService();
    } else if (mode == GlobalPauseRuntimeMode.safePausedManagingExisting ||
        mode == GlobalPauseRuntimeMode.resuming) {
      await operations.keepPrivateManagementOnly();
    }
  }

  Future<void> _record(
    GlobalPauseEventType type, {
    required GlobalPauseRuntimeMode previous,
    required GlobalPauseRuntimeMode next,
    required GlobalPauseRuntimeEvidence evidence,
    required String reasonCode,
  }) async {
    final activity = await operations.activitySnapshot();
    await events.record(
      GlobalPauseEvent(
        type: type,
        occurredAtUtc: clock().toUtc(),
        sessionId: sessionId,
        previousState: previous,
        newState: next,
        openPositionCount: evidence.openPositionCount,
        openOrderCount: evidence.openOrderCount,
        protectionVerified: evidence.protectionVerified,
        activity: activity,
        reasonCode: reasonCode,
      ),
    );
  }

  String _resumeFailureReason(GlobalPauseRuntimeEvidence evidence) {
    if (!evidence.accountFresh) return 'stale_account';
    if (!evidence.reconciliationHealthy) return 'reconciliation_unhealthy';
    if (evidence.hasExposure && !evidence.protectionVerified) {
      return 'protection_unverified';
    }
    return 'resume_validation_failed';
  }

  void _requireInitialized() {
    if (!_initialized) {
      throw StateError('GlobalPauseRuntimeCoordinator is not initialized.');
    }
  }

  Future<void> _serialize(Future<void> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }
}
