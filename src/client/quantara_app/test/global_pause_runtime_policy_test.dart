import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/owner_alpha/application/global_pause_runtime_policy.dart';

void main() {
  const policy = GlobalPauseRuntimePolicy();

  GlobalPauseRuntimeEvidence evidence({
    int positions = 0,
    int orders = 0,
    bool protectionVerified = true,
    bool accountFresh = true,
    bool reconciliationHealthy = true,
  }) => GlobalPauseRuntimeEvidence(
    openPositionCount: positions,
    openOrderCount: orders,
    protectionVerified: protectionVerified,
    accountFresh: accountFresh,
    reconciliationHealthy: reconciliationHealthy,
  );

  test('flat pause becomes fully offline and can stop background service', () {
    final mode = policy.pause(evidence());

    expect(mode, GlobalPauseRuntimeMode.pausedOffline);
    expect(policy.mayStopScanning(mode), isTrue);
    expect(policy.mayStopNonEssentialNetwork(mode), isTrue);
    expect(policy.mustKeepPrivateManagement(mode), isFalse);
    expect(policy.mayStopBackgroundService(mode), isTrue);
  });

  test('live exposure enters safe pause and preserves private management', () {
    final mode = policy.pause(evidence(positions: 1));

    expect(mode, GlobalPauseRuntimeMode.safePausedManagingExisting);
    expect(policy.mayStopScanning(mode), isTrue);
    expect(policy.mayStopNonEssentialNetwork(mode), isTrue);
    expect(policy.mustKeepPrivateManagement(mode), isTrue);
    expect(policy.mayStopBackgroundService(mode), isFalse);
  });

  test('resume fails closed when account truth is stale or unreconciled', () {
    expect(policy.beginResume(evidence(accountFresh: false)), isNull);
    expect(
      policy.beginResume(evidence(reconciliationHealthy: false)),
      isNull,
    );
  });

  test('resume fails closed when live protection is uncertain', () {
    expect(
      policy.beginResume(evidence(positions: 1, protectionVerified: false)),
      isNull,
    );
  });

  test(
    'successful resume requires validation both before and after resume',
    () {
      final healthy = evidence(positions: 1);
      final started = policy.beginResume(healthy);

      expect(started, GlobalPauseRuntimeMode.resuming);
      expect(
        policy.finishResume(current: started!, evidence: healthy),
        GlobalPauseRuntimeMode.running,
      );

      expect(
        policy.finishResume(
          current: GlobalPauseRuntimeMode.resuming,
          evidence: evidence(positions: 1, protectionVerified: false),
        ),
        GlobalPauseRuntimeMode.safePausedManagingExisting,
      );
    },
  );
}
