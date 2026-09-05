import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/owner_alpha/application/global_pause_diagnostics_summary.dart';
import 'package:quantara_app/features/owner_alpha/application/global_pause_observability.dart';
import 'package:quantara_app/features/owner_alpha/application/global_pause_runtime_policy.dart';

void main() {
  test(
    'full offline reports healthy only when all runtime work is stopped',
    () {
      final summary = GlobalPauseDiagnosticsSummary(
        mode: GlobalPauseRuntimeMode.pausedOffline,
        activity: const GlobalPauseActivitySnapshot(
          activeScanners: 0,
          activeSubscriptions: 0,
          activeTimers: 0,
          backgroundServiceActive: false,
        ),
        openPositionCount: 0,
        openOrderCount: 0,
        protectionVerified: true,
        reasonCode: 'flat_full_offline',
      );

      expect(summary.fullOfflineQuiesced, isTrue);
      expect(summary.pauseInvariantSatisfied, isTrue);
      expect(summary.toJson()['scanningActive'], isFalse);
    },
  );

  test('full offline fails closed when any scanner remains active', () {
    final summary = GlobalPauseDiagnosticsSummary(
      mode: GlobalPauseRuntimeMode.pausedOffline,
      activity: const GlobalPauseActivitySnapshot(
        activeScanners: 1,
        activeSubscriptions: 0,
        activeTimers: 0,
        backgroundServiceActive: false,
      ),
      openPositionCount: 0,
      openOrderCount: 0,
      protectionVerified: true,
      reasonCode: 'unexpected_scanner',
    );

    expect(summary.fullOfflineQuiesced, isFalse);
    expect(summary.pauseInvariantSatisfied, isFalse);
  });

  test('safe pause permits management activity but never active scanners', () {
    final summary = GlobalPauseDiagnosticsSummary(
      mode: GlobalPauseRuntimeMode.safePausedManagingExisting,
      activity: const GlobalPauseActivitySnapshot(
        activeScanners: 0,
        activeSubscriptions: 1,
        activeTimers: 1,
        backgroundServiceActive: true,
      ),
      openPositionCount: 1,
      openOrderCount: 0,
      protectionVerified: true,
      reasonCode: 'live_management_required',
    );

    expect(summary.safePauseInvariantSatisfied, isTrue);
    expect(summary.pauseInvariantSatisfied, isTrue);
  });

  test('safe pause without authoritative exposure fails closed', () {
    final summary = GlobalPauseDiagnosticsSummary(
      mode: GlobalPauseRuntimeMode.safePausedManagingExisting,
      activity: const GlobalPauseActivitySnapshot(
        activeScanners: 0,
        activeSubscriptions: 1,
        activeTimers: 1,
        backgroundServiceActive: true,
      ),
      openPositionCount: 0,
      openOrderCount: 0,
      protectionVerified: false,
      reasonCode: 'unknown',
    );

    expect(summary.pauseInvariantSatisfied, isFalse);
  });

  test('event conversion retains only supplied authoritative evidence', () {
    final event = GlobalPauseEvent(
      type: GlobalPauseEventType.deferredForLiveManagement,
      occurredAtUtc: DateTime.utc(2026, 9, 4, 12),
      sessionId: 'session',
      previousState: GlobalPauseRuntimeMode.running,
      newState: GlobalPauseRuntimeMode.safePausedManagingExisting,
      openPositionCount: 2,
      openOrderCount: 3,
      protectionVerified: false,
      activity: const GlobalPauseActivitySnapshot(
        activeScanners: 0,
        activeSubscriptions: 1,
        activeTimers: 1,
        backgroundServiceActive: true,
      ),
      reasonCode: 'protection_uncertain',
    );

    final summary = GlobalPauseDiagnosticsSummary.fromEvent(event);

    expect(summary.openPositionCount, 2);
    expect(summary.openOrderCount, 3);
    expect(summary.protectionVerified, isFalse);
    expect(summary.reasonCode, 'protection_uncertain');
  });
}
