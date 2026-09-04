import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/owner_alpha/application/global_pause_observability.dart';
import 'package:quantara_app/features/owner_alpha/application/global_pause_runtime_policy.dart';

void main() {
  test('event names remain stable for diagnostic export', () {
    final names = GlobalPauseEventType.values
        .map((item) => item.stableName)
        .toList();

    expect(names.length, 7);
    expect(names.first, 'global_pause_requested');
    expect(names[1], 'global_pause_entered');
    expect(names[2], 'global_pause_deferred_for_live_management');
    expect(names[3], 'global_pause_full_offline_entered');
    expect(names[4], 'global_resume_requested');
    expect(names[5], 'global_resume_validation_failed');
    expect(names.last, 'global_resume_completed');
  });

  test('event exports pause state and remaining runtime activity', () {
    final event = GlobalPauseEvent(
      type: GlobalPauseEventType.deferredForLiveManagement,
      occurredAtUtc: DateTime.utc(2026, 9, 4, 4),
      sessionId: 'session-1',
      previousState: GlobalPauseRuntimeMode.running,
      newState: GlobalPauseRuntimeMode.safePausedManagingExisting,
      openPositionCount: 1,
      openOrderCount: 2,
      protectionVerified: true,
      activity: const GlobalPauseActivitySnapshot(
        activeScanners: 0,
        activeSubscriptions: 1,
        activeTimers: 1,
        backgroundServiceActive: true,
      ),
      reasonCode: 'live_management_required',
    );

    final json = event.toJson();
    final activity = json['activity']! as Map<String, Object?>;
    expect(json['event'], 'global_pause_deferred_for_live_management');
    expect(json['newState'], 'safePausedManagingExisting');
    expect(json['openPositionCount'], 1);
    expect(json['openOrderCount'], 2);
    expect(json['protectionVerified'], isTrue);
    expect(json['reasonCode'], 'live_management_required');
    expect(activity['activeScanners'], 0);
    expect(activity['activeSubscriptions'], 1);
    expect(activity['activeTimers'], 1);
    expect(activity['backgroundServiceActive'], isTrue);
  });
}
